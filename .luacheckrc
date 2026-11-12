std = "lua51"
max_line_length = 120
globals = { "POSEhuskerDB", "SlashCmdList", "SLASH_POSEHUSKER1", "SLASH_POSEHUSKER2" }
read_globals = {
  "C_Container", "C_Item", "C_Timer", "C_UnitAuras", "CreateFrame", "ChatTypeInfo",
  "GetMaxLevelForPlayerExpansion", "GetTime", "InCombatLockdown", "IsPlayerAtEffectiveMaxLevel",
  "IsResting", "IsXPUserDisabled", "NUM_BAG_SLOTS", "NUM_REAGENTBAG_SLOTS", "PlaySound",
  "RaidNotice_AddMessage", "RaidWarningFrame", "SOUNDKIT", "UnitAffectingCombat",
  "UnitIsDeadOrGhost", "UnitLevel", "UnitOnTaxi", "issecretvalue",
}
files["tests/run.lua"] = { std = "lua51+max", ignore = { "." } }
