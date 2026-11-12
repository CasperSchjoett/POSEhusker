# POSEhusker

A small WoW Forever addon that nags you, raid-warning style, when your **Cozy Sleeping Bag** is off cooldown and your **Well Rested** buff has **1 hour or less** left (or is missing). It repeats every 10 seconds until you use the bag or snooze. It only reads game state and shows text and sound — no protected actions.

## Install

1. Download `POSEhusker-<version>.zip` from the [latest release](../../releases/latest).
2. Unzip it so you get `.../Interface/AddOns/POSEhusker/POSEhusker.toc`. WoW Forever shares the retail `Interface/AddOns` folder.
3. Start the game. If it shows as out of date, tick **Load out of date AddOns** or fix the Interface number (below).

### Setting the Interface number

The `.toc` ships with `120000` (Midnight) as a guess. In game run `/dump select(4, GetBuildInfo())` and put the result in the `## Interface:` line of `POSEhusker.toc`.

## Commands (`/posehusker` or `/ph`)

| Command | Effect |
|---|---|
| `/ph`, `/ph status` | Show state and why an alert is or isn't firing |
| `/ph on` / `off` | Enable / disable |
| `/ph threshold <min>` | Alert when buff has at most this many minutes left (default 60) |
| `/ph interval <sec>` | Repeat interval, min 3 (default 10) |
| `/ph sound on\|off` | Toggle sound |
| `/ph snooze [min]` | Snooze (default 15); `0` cancels. Cleared on reload |
| `/ph test` | Fire one alert now |
| `/ph item <id>` / `/ph spell <id>` | Manual ID override (non-English clients); `/ph reset` clears both |

The bag item and the buff's spell ID are auto-detected by English name and cached in `POSEhuskerDB`.

## Known limitations / to verify in game

- Interface number and the exact buff name ("Well Rested") are unconfirmed for Forever; see `docs/PLAN.md` §2, §5.2 and the checklist in §8. Confirm the buff with `/dump C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")`.
- Nothing is evaluated in combat; secret values are skipped silently.
- If `/ph` collides with another addon, `/posehusker` always works.

## Development

```sh
sh scripts/check.sh        # headless tests (stubbed WoW API), luac, luacheck
python3 scripts/package.py # builds dist/POSEhusker-<version>.zip
```

### Releasing

Bump `## Version:` in `src/POSEhusker/POSEhusker.toc`, commit, then:

```sh
git tag v1.0.0 && git push origin main v1.0.0
```

The GitHub Action runs the checks, builds the zip and publishes it as a release (the tag must match the TOC version).
