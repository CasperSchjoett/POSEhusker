# POSEhusker — Design & Implementation Plan

A small WoW Forever addon that nags you, raid-warning style, when your **Cozy Sleeping Bag** is off cooldown and your **Well Rested** buff has **1 hour or less** remaining.

This document is a design and implementation spec. It covers the target environment, behavior, file layout, API usage, edge cases, and acceptance criteria.

---

## 1. Background and goal

**The item (WoW Forever version):**
- *Cozy Sleeping Bag* is a reusable item with a **1-hour cooldown**.
- Using it places a bag on the ground. Each minute you lie on it gives one stack of **Well Rested** (+1% XP from all sources), up to **3 stacks**.
- The buff lasts **2 hours** and persists through death.
- It cannot be used in rested areas (cities/inns).

**What this means for timing:** after you use the bag, its cooldown ends at almost exactly the moment your buff drops to 1 hour remaining. In normal use the alert will therefore start right as the cooldown expires. The 1-hour threshold is still checked explicitly, so the addon behaves correctly if the bag was used without refreshing the buff, or the buff came from someone else's bag.

**Goal:** while the player is out of combat, not resting, and the conditions below are true, show a raid-warning style message plus a sound **every 10 seconds** until they use the bag or snooze the alert.

---

## 2. Target environment (important)

WoW Forever looks like Classic but runs on the **modern Mainline client (Midnight-era 12.x API)**. Implications:

- Write against the **Mainline/retail API**, not the Classic API. Use `C_Container.*`, `C_UnitAuras.*`, `C_Timer.*`.
- The Midnight addon restrictions apply. Some combat-related values (including aura data) may be **"secret values"** in combat and cannot be compared or used in arithmetic. **Do no evaluation in combat.** Also guard reads with `issecretvalue(v)` if that global exists (`if issecretvalue and issecretvalue(v) then return end`).
- **Interface version:** unknown for Forever at writing time. The implementer should get it in-game with `/dump select(4, GetBuildInfo())` and put it in the `.toc`. Until then, users can enable "Load out of date AddOns".
- Forever shares the retail `Interface/AddOns` folder. That doesn't affect the code, but mention it in the README.

---

## 3. Alert condition

The alert fires when **all** of the following are true:

| # | Condition | How |
|---|-----------|-----|
| 1 | Addon enabled and not snoozed | `POSEhuskerDB.enabled` and `GetTime() >= snoozeUntil` |
| 2 | Player owns the bag | Found in bags (see §5.1) |
| 3 | Bag is off cooldown | `C_Container.GetItemCooldown(itemID)` → `start == 0` or `start + duration <= GetTime()` |
| 4 | Buff remaining ≤ threshold (default **3600 s**) | Buff missing counts as 0 remaining → true |
| 5 | Not in combat | `not InCombatLockdown()` and `not UnitAffectingCombat("player")` |
| 6 | Not resting (bag unusable there) | `not IsResting()` |
| 7 | Player alive and not on a taxi | `not UnitIsDeadOrGhost("player")`, `not UnitOnTaxi("player")` |
| 8 | Player still gains XP (configurable, default on) | Skip if `IsPlayerAtEffectiveMaxLevel()` (fallback: `UnitLevel("player") >= GetMaxLevelForPlayerExpansion()`), or if XP is disabled (`IsXPUserDisabled and IsXPUserDisabled()`) |

**Note on condition 3:** ignore the global cooldown. If `duration > 0 and duration <= 1.5`, treat the bag as ready.

---

## 4. Behavior

### 4.1 Alert
- Message, shown in the center of the screen in raid-warning style:
  `RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])`
- Sound: `PlaySound(SOUNDKIT.RAID_WARNING, "Master")` (toggleable).
- Message text:
  - Buff missing: `"POSEhusker: Sleeping bag ready, no Well Rested buff!"`
  - Buff present: `"POSEhusker: Sleeping bag ready, Well Rested 47m left (2 stacks)"`
- **Repeat every 10 seconds** (configurable) while the condition holds.
- Fire the **first alert immediately** when the condition goes from false to true. Don't wait for the next tick.

### 4.2 Stopping
The alert stops automatically when any condition becomes false. Usually this happens because the bag is used (cooldown starts) or combat starts.

### 4.3 Snooze
`/ph snooze [minutes]` (default 15) suppresses alerts until the snooze expires. The snooze is not saved across reloads. A reload clears it, and that's fine.

---

## 5. Implementation details

### 5.1 Finding the bag (no hardcoded IDs required)
The Forever item ID may differ from the Season of Discovery ID, so detect it at runtime:

1. If `POSEhuskerDB.itemID` is set and `C_Item.GetItemCount(itemID) > 0`, use it.
2. Otherwise scan bags `0..NUM_BAG_SLOTS` (in Mainline, include the reagent bag index if present). Use `C_Container.GetContainerNumSlots(bag)` and `C_Container.GetContainerItemInfo(bag, slot)`. Match `info.itemName` (or `C_Item.GetItemNameByID(info.itemID)`) against `"Cozy Sleeping Bag"`. When found, store `info.itemID` in `POSEhuskerDB.itemID`.
3. Allow a manual override with `/ph item <itemID>` for non-English clients.
4. Re-scan on `BAG_UPDATE_DELAYED` only when no item is known.

If no bag is found, never alert. `/ph status` should say "Sleeping bag not found in bags".

### 5.2 Reading the buff
1. If `POSEhuskerDB.spellID` is known, use `C_UnitAuras.GetPlayerAuraBySpellID(spellID)`.
2. Otherwise use `C_UnitAuras.GetAuraDataBySpellName("player", "Well Rested", "HELPFUL")`. If it's found, store `aura.spellId` in `POSEhuskerDB.spellID`.
3. Remaining time = `aura.expirationTime - GetTime()`. If `aura.expirationTime == 0` (no expiry), treat as not needing refresh.
4. Stacks = `aura.applications` (0 or nil → 1).
5. Manual override: `/ph spell <spellID>`.
6. Wrap every aura read in `pcall` and check for secret values. If anything fails, skip this tick silently. Don't spam errors.

**Note:** "Well Rested" is the name given by guides. The implementer should confirm the exact in-game name with `/dump C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")`. The name is also a localization concern, which the spellID caching solves after the first detection.

### 5.3 Scheduling
- One `C_Timer.NewTicker(1, Evaluate)` running for the addon's lifetime. It's cheap: a few API calls per second.
- `Evaluate()` computes the condition. It tracks `lastAlertTime`, and when the condition holds and `GetTime() - lastAlertTime >= interval`, it fires the alert.
- When the condition goes false, reset `lastAlertTime = 0` so the next true transition alerts immediately.
- Also call `Evaluate()` directly on these events to get instant reactions: `PLAYER_REGEN_ENABLED`, `PLAYER_UPDATE_RESTING`, `UNIT_AURA` (player only), `BAG_UPDATE_COOLDOWN`, `PLAYER_ENTERING_WORLD`.
- Pause evaluation on `PLAYER_REGEN_DISABLED`.

### 5.4 Saved variables
`.toc`: `## SavedVariables: POSEhuskerDB`

Defaults, merged on `ADDON_LOADED`:
```lua
{
  enabled   = true,
  threshold = 3600,   -- seconds of buff remaining at or below which we alert
  interval  = 10,     -- seconds between repeated alerts
  sound     = true,
  ignoreMaxLevel = true,
  itemID    = nil,    -- auto-detected
  spellID   = nil,    -- auto-detected
}
```

### 5.5 Slash commands (`/posehusker` and `/ph`)
| Command | Effect |
|---|---|
| `/ph` or `/ph status` | Print: enabled, bag found and its cooldown left, buff remaining and stacks, current condition, and the reason it's false if it is |
| `/ph on` / `/ph off` | Enable or disable |
| `/ph threshold <minutes>` | Set threshold (default 60) |
| `/ph interval <seconds>` | Set repeat interval (minimum 3, default 10) |
| `/ph sound on\|off` | Toggle sound |
| `/ph snooze [minutes]` | Snooze (default 15). `/ph snooze 0` cancels |
| `/ph test` | Fire one alert now, ignoring conditions |
| `/ph item <id>` / `/ph spell <id>` | Manual ID overrides. `reset` clears both |

**Note:** `/ph` may collide with another addon's slash command. Register it anyway; `/posehusker` always works.

---

## 6. File layout

```
POSEhusker/
├── POSEhusker.toc
├── POSEhusker.lua      -- everything; single file, ~200 lines expected
└── README.md           -- install, commands, known limitations
```

`POSEhusker.toc`:
```
## Interface: <from GetBuildInfo() in Forever>
## Title: POSEhusker
## Notes: Reminds you to refresh your Cozy Sleeping Bag buff.
## Author: Casper
## Version: 1.0.0
## SavedVariables: POSEhuskerDB
POSEhusker.lua
```

Suggested structure for `POSEhusker.lua`:
1. Namespace and defaults
2. Helpers: `FindBag()`, `GetBagCooldownLeft()`, `GetBuffInfo()`, `IsSuppressed()` (returns a reason string)
3. `Evaluate()` and `FireAlert(remaining, stacks)`
4. Event frame and handlers
5. Slash command parser
6. `ADDON_LOADED`: init the DB and start the ticker

Print chat messages with a colored prefix: `|cff66ccffPOSEhusker|r:`.

---

## 7. Out of scope for v1 (possible v2)
- A clickable "use bag" button. This needs `SecureActionButtonTemplate` with `type=item`, and it only works out of combat.
- A minimap icon or options panel (Settings API).
- Tracking the bag across alts.
- Reminding party members, or noticing a party member's bag.

---

## 8. Testing checklist

| Test | Expected |
|---|---|
| `/ph test` | Raid-warning text in the center of the screen plus sound |
| Bag ready, no buff, outside a city | Alert immediately, then every 10 s |
| Use the bag | Alerts stop at once (cooldown started) |
| Enter combat while alerting | Alerts stop. They resume within about 1 s after combat if still valid |
| Walk into an inn or city | Alerts stop. They resume on leaving |
| Buff at 1h05m, bag ready | No alert. Alert starts when buff crosses 60m |
| `/ph threshold 30` | Alert only starts at ≤30m |
| `/ph snooze 1` | Silence for 1 minute, then alerts resume |
| No bag in bags | No alerts. `/ph status` explains why |
| `/reload` | Settings persist, no Lua errors |
| Max level with `ignoreMaxLevel` on | No alerts |

Turn on `/console scriptErrors 1` during testing. There should be zero Lua errors, including in combat.

---

## 9. Acceptance criteria
- Loads in WoW Forever without errors, and doesn't need "Load out of date AddOns" once the Interface number is set.
- Alerts appear every 10 s exactly when the §3 conditions hold, and never in combat or while resting.
- Item and spell IDs are auto-detected on an English client, with manual overrides available.
- All settings persist via `POSEhuskerDB`.
- No taint or protected-action errors. The addon only reads state and displays text and sound.
