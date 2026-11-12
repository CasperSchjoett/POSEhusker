-- POSEhusker: raid-warning nag when the Cozy Sleeping Bag is ready and
-- Well Rested has <= threshold seconds left. Read-only: no protected actions.
local ADDON_NAME = "POSEhusker"
local BAG_NAME = "Cozy Sleeping Bag"
local BUFF_NAME = "Well Rested"
local PREFIX = "|cff66ccffPOSEhusker|r: "

local DEFAULTS = {
  enabled = true,
  threshold = 3600,
  interval = 10,
  sound = true,
  ignoreMaxLevel = true,
}

local snoozeUntil = 0
local lastAlertTime = 0
local DB

local function Print(msg) print(PREFIX .. msg) end

-- Returns true if v is a Midnight "secret value" (or otherwise unusable).
local function IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end

local function SafeNumber(v)
  if type(v) ~= "number" or IsSecret(v) then return nil end
  return v
end

---------------------------------------------------------------- helpers

local function FindBag()
  local id = DB.itemID
  if id and C_Item.GetItemCount(id) > 0 then return id end
  local last = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
  for bag = 0, last do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        local name = info.itemName or C_Item.GetItemNameByID(info.itemID)
        if name == BAG_NAME then
          DB.itemID = info.itemID
          return info.itemID
        end
      end
    end
  end
  return nil
end

-- Seconds of cooldown left (0 = ready). Global cooldown is ignored.
local function GetBagCooldownLeft(itemID)
  local start, duration = C_Container.GetItemCooldown(itemID)
  start, duration = SafeNumber(start), SafeNumber(duration)
  if not start or not duration then return nil end
  if start == 0 or duration == 0 then return 0 end
  if duration <= 1.5 then return 0 end
  local left = start + duration - GetTime()
  return left > 0 and left or 0
end

-- Returns remaining seconds, stacks. Missing buff -> 0, 0. nil on failure.
-- Remaining of math.huge means "no expiry".
local function GetBuffInfo()
  local ok, aura = pcall(function()
    if DB.spellID then
      return C_UnitAuras.GetPlayerAuraBySpellID(DB.spellID)
    end
    local a = C_UnitAuras.GetAuraDataBySpellName("player", BUFF_NAME, "HELPFUL")
    if a and SafeNumber(a.spellId) then DB.spellID = a.spellId end
    return a
  end)
  if not ok then return nil end
  if not aura then return 0, 0 end
  local exp = SafeNumber(aura.expirationTime)
  if exp == nil then return nil end
  local stacks = SafeNumber(aura.applications)
  if not stacks or stacks < 1 then stacks = 1 end
  if exp == 0 then return math.huge, stacks end
  local left = exp - GetTime()
  return left > 0 and left or 0, stacks
end

local function PlayerGainsXP()
  if not DB.ignoreMaxLevel then return true end
  if IsPlayerAtEffectiveMaxLevel then
    if IsPlayerAtEffectiveMaxLevel() then return false end
  elseif GetMaxLevelForPlayerExpansion
      and UnitLevel("player") >= GetMaxLevelForPlayerExpansion() then
    return false
  end
  if IsXPUserDisabled and IsXPUserDisabled() then return false end
  return true
end

-- Returns nil when an alert is warranted, else a reason string.
-- Also returns remaining, stacks, cooldownLeft for status output.
local function IsSuppressed()
  if not DB.enabled then return "disabled" end
  if GetTime() < snoozeUntil then
    return ("snoozed for %d more min"):format(math.ceil((snoozeUntil - GetTime()) / 60))
  end
  if InCombatLockdown() or UnitAffectingCombat("player") then return "in combat" end
  local itemID = FindBag()
  if not itemID then return "Sleeping bag not found in bags" end
  local cd = GetBagCooldownLeft(itemID)
  if cd == nil then return "bag cooldown unreadable" end
  if cd > 0 then return ("bag on cooldown (%dm left)"):format(math.ceil(cd / 60)), nil, nil, cd end
  if IsResting() then return "resting (bag unusable here)" end
  if UnitIsDeadOrGhost("player") then return "dead" end
  if UnitOnTaxi("player") then return "on a taxi" end
  if not PlayerGainsXP() then return "no XP gain (max level / XP disabled)" end
  local remaining, stacks = GetBuffInfo()
  if remaining == nil then return "buff unreadable" end
  if remaining > DB.threshold then
    return ("Well Rested has %dm left (threshold %dm)"):format(
      remaining == math.huge and 9999 or math.ceil(remaining / 60), math.ceil(DB.threshold / 60)), remaining, stacks, 0
  end
  return nil, remaining, stacks, 0
end

---------------------------------------------------------------- alert

local function FireAlert(remaining, stacks)
  local msg
  if not remaining or remaining <= 0 then
    msg = "POSEhusker: Sleeping bag ready, no Well Rested buff!"
  else
    msg = ("POSEhusker: Sleeping bag ready, Well Rested %dm left (%d stack%s)"):format(
      math.ceil(remaining / 60), stacks or 1, (stacks or 1) == 1 and "" or "s")
  end
  RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
  if DB.sound then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
end

local function Evaluate()
  if not DB then return end
  local ok, reason, remaining, stacks = pcall(IsSuppressed)
  if not ok then return end -- silent skip (e.g. secret values)
  if reason then
    lastAlertTime = 0
    return
  end
  local now = GetTime()
  if lastAlertTime == 0 or now - lastAlertTime >= DB.interval then
    lastAlertTime = now
    FireAlert(remaining, stacks)
  end
end

---------------------------------------------------------------- slash

local function Status()
  local ok, reason, remaining, stacks, cd = pcall(IsSuppressed)
  if not ok then Print("could not evaluate: " .. tostring(reason)) return end
  Print("enabled: " .. tostring(DB.enabled)
    .. ", threshold " .. math.floor(DB.threshold / 60) .. "m"
    .. ", interval " .. DB.interval .. "s, sound " .. tostring(DB.sound))
  Print("item " .. tostring(DB.itemID or "unknown") .. ", spell " .. tostring(DB.spellID or "unknown"))
  if cd then Print(("bag cooldown left: %dm"):format(math.ceil(cd / 60))) end
  if remaining then
    Print(remaining == math.huge and "buff: no expiry"
      or ("buff: %dm left, %d stack(s)"):format(math.ceil(remaining / 60), stacks or 0))
  end
  Print(reason and ("no alert: " .. reason) or "alert condition TRUE")
end

local function ToggleArg(arg) return arg == "on" end

local function Slash(input)
  local cmd, arg = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  local num = tonumber(arg)
  if cmd == "" or cmd == "status" then Status()
  elseif cmd == "on" or cmd == "off" then
    DB.enabled = (cmd == "on"); Print(cmd); Evaluate()
  elseif cmd == "threshold" and num and num >= 0 then
    DB.threshold = num * 60; Print("threshold " .. num .. "m")
  elseif cmd == "interval" and num then
    DB.interval = math.max(3, num); Print("interval " .. DB.interval .. "s")
  elseif cmd == "sound" and (arg == "on" or arg == "off") then
    DB.sound = ToggleArg(arg); Print("sound " .. arg)
  elseif cmd == "snooze" then
    local m = num or 15
    if m <= 0 then snoozeUntil = 0; Print("snooze cancelled")
    else snoozeUntil = GetTime() + m * 60; Print("snoozed " .. m .. "m") end
    lastAlertTime = 0
  elseif cmd == "test" then
    FireAlert(DB.threshold / 2, 2)
  elseif cmd == "item" and num then
    DB.itemID = num; Print("item " .. num)
  elseif cmd == "spell" and num then
    DB.spellID = num; Print("spell " .. num)
  elseif cmd == "reset" or (cmd == "item" and arg == "reset") or (cmd == "spell" and arg == "reset") then
    DB.itemID, DB.spellID = nil, nil; Print("item and spell IDs cleared (will re-detect)")
  else
    Print("/ph [status] | on | off | threshold <min> | interval <sec> | sound on|off"
      .. " | snooze [min] | test | item <id> | spell <id> | reset")
  end
end

---------------------------------------------------------------- events

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

local function OnEvent(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON_NAME then return end
    POSEhuskerDB = POSEhuskerDB or {}
    DB = POSEhuskerDB
    for k, v in pairs(DEFAULTS) do
      if DB[k] == nil then DB[k] = v end
    end
    frame:UnregisterEvent("ADDON_LOADED")
    for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
      "PLAYER_UPDATE_RESTING", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED",
      "PLAYER_ENTERING_WORLD" }) do
      frame:RegisterEvent(e)
    end
    frame:RegisterUnitEvent("UNIT_AURA", "player")
    C_Timer.NewTicker(1, Evaluate)
  elseif event == "PLAYER_REGEN_DISABLED" then
    lastAlertTime = 0 -- paused; Evaluate also bails in combat
  elseif event == "BAG_UPDATE_DELAYED" then
    if DB and not DB.itemID then Evaluate() end
  else
    Evaluate()
  end
end
frame:SetScript("OnEvent", OnEvent)

SLASH_POSEHUSKER1 = "/posehusker"
SLASH_POSEHUSKER2 = "/ph"
SlashCmdList["POSEHUSKER"] = Slash
