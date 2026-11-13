-- Headless tests with a stubbed WoW API. Run: lua tests/run.lua
local now = 1000
local W -- world state
local printed, raid, sounds = {}, {}, 0
local handlers, timers = {}, nil

local function reset()
  W = { combat=false, resting=false, dead=false, taxi=false, maxlevel=false,
        bag={ id=111, name="Cozy Sleeping Bag" }, cd={0,0}, aura=nil }
  POSEhuskerDB = nil
  printed, raid, sounds = {}, {}, 0
end

function GetTime() return now end
function print(...) printed[#printed+1] = table.concat({...}, " ") end
function InCombatLockdown() return W.combat end
function UnitAffectingCombat() return W.combat end
function IsResting() return W.resting end
function UnitIsDeadOrGhost() return W.dead end
function UnitOnTaxi() return W.taxi end
function IsPlayerAtEffectiveMaxLevel() return W.maxlevel end
NUM_BAG_SLOTS = 4
C_Item = { GetItemCount=function(id) return (W.bag and W.bag.id==id) and 1 or 0 end,
           GetItemNameByID=function() return nil end }
C_Container = {
  GetContainerNumSlots=function(b) return b==1 and 2 or 0 end,
  GetContainerItemInfo=function(b,s) if b==1 and s==2 and W.bag then return {itemID=W.bag.id,itemName=W.bag.name} end end,
  GetItemCooldown=function() return W.cd[1], W.cd[2] end }
C_UnitAuras = {
  GetAuraDataBySpellName=function(_,n) return W.aura and n=="Well-Rested" and W.aura or nil end,
  GetPlayerAuraBySpellID=function(id) return W.aura and W.aura.spellId==id and W.aura or nil end }
C_Timer = { NewTicker=function() return {} end }
RaidWarningFrame, ChatTypeInfo, SOUNDKIT = {}, {RAID_WARNING={}}, {RAID_WARNING=1}
function RaidNotice_AddMessage(_, m) raid[#raid+1] = m end
function PlaySound() sounds = sounds + 1 end
SlashCmdList = {}
local frame = { RegisterEvent=function() end, UnregisterEvent=function() end,
  RegisterUnitEvent=function() end, SetScript=function(_, _, f) handlers.f = f end }
function CreateFrame() return frame end

local fails = 0
local function check(name, cond) if not cond then fails = fails + 1 end print = print; io.write((cond and "ok   " or "FAIL ") .. name .. "\n") end

local function load()
  dofile("src/POSEhusker/POSEhusker.lua")
  handlers.f(frame, "ADDON_LOADED", "POSEhusker")
end
local function tick() handlers.f(frame, "PLAYER_ENTERING_WORLD") end
local out = io.write
local function slash(s) SlashCmdList.POSEHUSKER(s) end

reset(); load()
tick(); check("no buff -> immediate alert", #raid == 1 and raid[1]:find("no Well Rested"))
check("sound played", sounds == 1)
now = now + 5; tick(); check("no repeat before interval", #raid == 1)
now = now + 5; tick(); check("repeat at 10s", #raid == 2)
check("item id cached", POSEhuskerDB.itemID == 111)

W.cd = { now - 10, 3600 }; tick(); now = now + 20; tick()
check("on cooldown -> no alert", #raid == 2)
W.cd = { now, 1.5 }; tick(); check("GCD ignored", #raid == 3)
W.cd = { 0, 0 }

W.combat = true; now = now + 20; tick(); check("combat -> none", #raid == 3)
W.combat = false; tick(); check("resumes after combat immediately", #raid == 4)
W.resting = true; now = now + 20; tick(); check("resting -> none", #raid == 4)
W.resting = false; W.dead = true; now = now + 20; tick(); check("dead -> none", #raid == 4)
W.dead = false; W.taxi = true; now = now + 20; tick(); check("taxi -> none", #raid == 4)
W.taxi = false; W.maxlevel = true; now = now + 20; tick(); check("max level -> none", #raid == 4)
W.maxlevel = false

W.aura = { spellId=222, expirationTime = now + 3900, applications = 2 }
now = now + 20; tick(); check("buff 65m -> none", #raid == 4)
W.aura.expirationTime = now + 2820; tick()
check("buff 47m -> alert w/ stacks", raid[5] and raid[5]:find("47m left %(2 stacks%)"))
check("spell id cached", POSEhuskerDB.spellID == 222)
W.aura.expirationTime = 0; now = now + 20; tick(); check("no expiry -> none", #raid == 5)

slash("threshold 90"); W.aura = { spellId=222, expirationTime = now + 4000, applications = 1 }
now = now + 20; tick(); check("threshold 90m alerts at 66m", #raid == 6)
slash("snooze 1"); now = now + 20; tick(); check("snoozed", #raid == 6)
now = now + 60; tick(); check("snooze expires", #raid == 7)
slash("snooze 1"); slash("snooze 0"); now = now + 20; tick(); check("snooze 0 cancels", #raid == 8)
slash("off"); now = now + 20; tick(); check("off -> none", #raid == 8)
slash("on"); slash("interval 1"); check("interval min 3", POSEhuskerDB.interval == 3)
slash("test"); check("test fires", #raid >= 9)

W.bag = nil; POSEhuskerDB.itemID = nil; local n = #raid; now = now + 20; tick()
check("no bag -> none", #raid == n)
printed = {}; slash("status"); local joined = table.concat(printed, "\n")
check("status explains no bag", joined:find("Sleeping bag not found in bags"))

-- secret values must not error or alert
reset(); load(); issecretvalue = function(v) return v == "SECRET" end
W.aura = { spellId=222, expirationTime="SECRET" }
tick(); check("secret aura -> silent skip", #raid == 0)
issecretvalue = nil

-- persistence of defaults
reset(); POSEhuskerDB = { threshold = 1800 }; load()
check("defaults merged, user value kept", POSEhuskerDB.threshold == 1800 and POSEhuskerDB.interval == 10 and POSEhuskerDB.enabled)

os.exit(fails == 0 and 0 or 1)
