-- Fuel HUD for F/A-18C (Mission Start DO SCRIPT) do local FuelHUD = {}

-- ========================= -- Configuration ⚙️ -- ========================= FuelHUD.cfg = { INTERNAL_BASE_LBS = 10820, -- Internal full baseline (lbs) EXT_TANK_LBS = 2250, -- Each external tank capacity (lbs) UPDATE_INTERVAL = 0.5, -- HUD update interval (seconds) MESSAGE_DURATION = 1.2, -- OutText duration per update (seconds) to avoid flicker CONTINUOUS_SCAN = true, -- Continuously re-evaluate external tank count TYPE_HORNET = "FA-18C_hornet", }

FuelHUD.active = {} -- unitID -> state

-- ========================= -- Utility helpers 🔧 -- ========================= local function isValidUnit(u) return u and Unit.isExist(u) and u:getLife() and u:getLife() > 0 end

local function isPlayerHornet(u) if not isValidUnit(u) then return false end if u:getTypeName() ~= FuelHUD.cfg.TYPE_HORNET then return false end return u:getPlayerName() ~= nil end

local function descIsFuelTank(desc) if not desc then return false end -- Prefer explicit category if available (commonly 6 for FUEL_TANK) if desc.category == 6 then return true end -- Fallback: match by typeName keywords (robust for F/A-18C FPU-8A, etc.) local tn = (desc.typeName or ""):lower() if tn:find("fuel") or tn:find("tank") or tn:find("fpu") then return true end return false end

-- Count external fuel tanks attached (Hornet has them only on stations 3/5/7) -- We use Unit:getAmmo() which exposes mounted stores including fuel tanks. function FuelHUD.countExternalTanks(u) if not isValidUnit(u) then return 0 end local ammo = u:getAmmo() if not ammo then return 0 end local count = 0 for _, w in ipairs(ammo) do if w and w.desc and descIsFuelTank(w.desc) then -- w.count should reflect number of tanks of this type mounted local c = w.count or 1 count = count + c end end -- Limit to Hornet’s possible tank stations (3, 5, 7) → max 3 if count > 3 then count = 3 end return count end

function FuelHUD.compute(state) local u = state.unit local fuelFactor = u:getFuel() or 0 local totFOB_lbs = fuelFactor * FuelHUD.cfg.INTERNAL_BASE_LBS

if FuelHUD.cfg.CONTINUOUS_SCAN then
  state.tankCount = FuelHUD.countExternalTanks(u)
end

local maxCap_lbs = FuelHUD.cfg.INTERNAL_BASE_LBS + (state.tankCount * FuelHUD.cfg.EXT_TANK_LBS)
local pct = 0
if maxCap_lbs > 0 then
  pct = (totFOB_lbs / maxCap_lbs) * 100.0
  if pct < 0 then pct = 0 end
  if pct > 100 then pct = 100 end
end
return pct, totFOB_lbs, maxCap_lbs
end

function FuelHUD.display(state) local pct = FuelHUD.compute(state) local text = string.format("Fuel: %.1f%% of MaxCap", pct) trigger.action.outTextForUnit(state.unitID, text, FuelHUD.cfg.MESSAGE_DURATION) end

function FuelHUD.tick(state, t) if not state.active then return nil end if not isValidUnit(state.unit) then FuelHUD.stopByID(state.unitID) return nil end FuelHUD.display(state) return t + FuelHUD.cfg.UPDATE_INTERVAL end

function FuelHUD.start(u) if not isPlayerHornet(u) then return end local id = u:getID() if FuelHUD.active[id] then return end

local s = {
  unit = u,
  unitID = id,
  active = true,
  tankCount = FuelHUD.countExternalTanks(u),
}
FuelHUD.active[id] = s
timer.scheduleFunction(FuelHUD.tick, s, timer.getTime() + 0.1)
end

function FuelHUD.stopByID(id) local s = FuelHUD.active[id] if s then s.active = false FuelHUD.active[id] = nil end end

-- ========================= -- Event handling 🎯 -- ========================= FuelHUD.handler = {}

function FuelHUD.handler:onEvent(e) if not e or not e.initiator then return end local u = e.initiator if not isValidUnit(u) then return end local id = u:getID()

if e.id == world.event.S_EVENT_PLAYER_ENTER_UNIT or e.id == world.event.S_EVENT_BIRTH then
  -- Start tracking when a player is in a Hornet
  if isPlayerHornet(u) then
    FuelHUD.start(u)
  end

elseif e.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT
    or e.id == world.event.S_EVENT_DEAD
    or e.id == world.event.S_EVENT_CRASH then
  -- Stop tracking on exit/death/crash
  FuelHUD.stopByID(id)

elseif e.id == world.event.S_EVENT_PAYLOAD_CHANGE then
  -- Re-evaluate tank count on payload changes (rearm/add/remove)
  if isPlayerHornet(u) then
    local s = FuelHUD.active[id]
    if s then
      s.tankCount = FuelHUD.countExternalTanks(u)
    else
      FuelHUD.start(u)
    end
  end

elseif e.id == world.event.S_EVENT_JETTISON then
  -- Immediate decrement on jettison of a fuel tank
  if isPlayerHornet(u) and e.weapon and e.weapon.getDesc then
    local desc = e.weapon:getDesc()
    if descIsFuelTank(desc) then
      local s = FuelHUD.active[id]
      if s then
        s.tankCount = math.max(0, (s.tankCount or 0) - 1)
      end
    end
  end
end
end

world.addEventHandler(FuelHUD.handler) end