TankerLogic = {}

trigger.action.outText("TankerLogic v4 (Expanded Types) Loaded", 10)

-- =======================
-- Settings
-- =======================
TankerLogic.COOLDOWN        = 300       -- seconds
TankerLogic.MIN_REFUEL_TIME = 20        -- seconds
TankerLogic.MIN_FUEL_GAIN   = 0.05      -- 5% fuel gained
TankerLogic.MIN_SPEED_KTS   = 100
TankerLogic.MIN_AGL_FT      = 100

TankerLogic.CALLOUT_RANGE_NM    = 0.5   -- Adjusted to 0.5 as requested
TankerLogic.CALLOUT_INTERVAL    = 1
TankerLogic.CALLOUT_COOLDOWN    = 5

-- =======================
-- Tanker Definitions (EXPANDED)
-- =======================
TankerLogic.TANKERS = {
    -- KC-135 Tankers 
    ["KC-135"] = true,
    ["KC135MPRS"] = true,
  
    -- S-3B Tanker 
    ["S-3B Tanker"] = true,
    
    -- KC-130 Tanker 
    ["KC-130"] = true,
	["KC130"] = true,
    
    -- A-6E Tanker 
    ["A-6E"] = true,
	["A6E"] = true,
	["A-6E Intruder"] = true,

    -- IL-78M Tanker 
    ["IL-78M"] = true,
	
	-- KC-10 Tankers 
	["KC_10_Extender"] = true,
	["KC_10_Extender_D"] = true,
}

-- Tables for tracking
TankerLogic.lastTriggerTime   = {}
TankerLogic.refuelStartTime   = {}
TankerLogic.refuelStartFuel   = {}
TankerLogic.lastCallout       = {}
TankerLogic.nextFuelCallout   = {}

-- =======================
-- Helper functions
-- =======================
local function vecMag(v)
    return math.sqrt(v.x^2 + v.y^2 + v.z^2)
end

local function vecSub(a, b)
    return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

-- Get all tankers alive (Scanning all Blue/Red Airplanes)
function TankerLogic.getTankers()
    local tankers = {}
    
    -- Safety wrap the search
    local status, err = pcall(function()
        for _, coalitionID in pairs({coalition.side.BLUE, coalition.side.RED}) do
            local groups = coalition.getGroups(coalitionID, Group.Category.AIRPLANE)
            if groups then
                for _, grp in ipairs(groups) do
                    if grp and grp:isExist() then
                        for _, unit in ipairs(grp:getUnits()) do
                            if unit and unit:isExist() then
                                local typeName = unit:getTypeName()
                                if TankerLogic.TANKERS[typeName] then
                                    table.insert(tankers, unit)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    
    if not status then
        trigger.action.outText("Error searching tankers: " .. tostring(err), 10)
    end
    
    return tankers
end

-- =======================
-- Refueling event handler
-- =======================
function TankerLogic:onEvent(event)
    -- Safety check: event and initiator must exist
    if not event or not event.initiator then return end
    
    -- Safely check isExist
    local status, exists = pcall(function() return event.initiator:isExist() end)
    if not status or not exists then return end

    local unit = event.initiator
    local id = unit:getID()
    local now = timer.getTime()

    -- Only player-controlled F/A-18C
    if unit:getTypeName() ~= "FA-18C_hornet" then return end
    if unit:getPlayerName() == nil then return end

    -- Refueling start
    if event.id == world.event.S_EVENT_REFUELING_START then
        self.refuelStartTime[id] = now
        self.refuelStartFuel[id] = unit:getFuel()
        self.nextFuelCallout[id] = 2000 
        return
    end

    -- Refueling stop
    if event.id ~= world.event.S_EVENT_REFUELING_STOP then return end

    local startTime = self.refuelStartTime[id]
    local startFuel = self.refuelStartFuel[id]
    if not startTime or not startFuel then return end

    local timeConnected = now - startTime
    local fuelNow       = unit:getFuel()
    local fuelGain      = fuelNow - startFuel

    -- Calculate params safely
    local v = unit:getVelocity()
    local speed_kts = vecMag(v) * 1.94384

    local p = unit:getPoint()
    local ground = land.getHeight({ x = p.x, y = p.z })
    local agl_ft = (p.y - ground) * 3.28084

    local speedOK = speed_kts > self.MIN_SPEED_KTS
    local altOK   = agl_ft   > self.MIN_AGL_FT
    local timeOK  = timeConnected >= self.MIN_REFUEL_TIME
    local fuelOK  = fuelGain >= self.MIN_FUEL_GAIN
    
    -- Full check (Internal + External)
    local full = fuelNow >= 0.99 
    
    -- Tank configuration check
    local fuelTankCount = 0
    local ammo = unit:getAmmo()
    if ammo then
        for _, w in ipairs(ammo) do
            if w.desc and w.desc.category == Weapon.Category.FUEL_TANK then
                fuelTankCount = fuelTankCount + w.count
            end
        end
    end
    local tankConfigOK = (fuelTankCount == 0 or fuelTankCount == 1 or fuelTankCount == 3)

    -- Fuel transfer callouts logic would go here if we were connected
    -- (Removed pure looping callout here to rely on updates, but kept event logic structure)

    -- SUCCESS: play gangster music
    if timeOK and fuelOK and full and tankConfigOK then
        local last = self.lastTriggerTime[id]
        if not last or (now - last) >= self.COOLDOWN then
            self.lastTriggerTime[id] = now
            trigger.action.outSoundForUnit(id, "gangster.ogg")
        end
    elseif (not speedOK) or (not altOK) then
        -- Silent on pilot errors to avoid spam per request
    else
        -- Silent on tanker errors
    end

    -- Cleanup
    self.refuelStartTime[id] = nil
    self.refuelStartFuel[id] = nil
end

world.addEventHandler(TankerLogic)

-- =======================
-- Update Loop: Callouts + DEBUG DISPLAY
-- =======================
function TankerLogic.updateLoop()
    local now = timer.getTime()
    
    -- Wrap main loop in pcall
    local status, err = pcall(function()
        local tankers = TankerLogic.getTankers()
        
        -- Find players
        local players = {}
        local groups = coalition.getGroups(coalition.side.BLUE, Group.Category.AIRPLANE)
        if groups then
            for _, grp in ipairs(groups) do
                if grp and grp:isExist() then
                    for _, unit in ipairs(grp:getUnits()) do
                        if unit and unit:isExist() and unit:getPlayerName() and unit:getTypeName() == "FA-18C_hornet" then
                            table.insert(players, unit)
                        end
                    end
                end
            end
        end

        -- Iterate Players
        for _, player in ipairs(players) do
            local uid = player:getID()
            local pPos = player:getPoint()
            local pVel = player:getVelocity()

            -- 1. Sort Tankers by distance to THIS player
            local sortedTankers = {}
            for _, t in ipairs(tankers) do
                if t and t:isExist() then
                    local tPos = t:getPoint()
                    local dist = vecMag(vecSub(pPos, tPos)) / 1852 -- NM
                    table.insert(sortedTankers, { unit = t, dist = dist, type = t:getTypeName() })
                end
            end
            table.sort(sortedTankers, function(a,b) return a.dist < b.dist end)

            -- 2. Debug Display (Nearest 2)
            local msg = "DEBUG TRACKER:\n"
            for i = 1, 2 do
                if sortedTankers[i] then
                    msg = msg .. string.format("T%d: %s | %.2f NM\n", i, sortedTankers[i].type, sortedTankers[i].dist)
                end
            end
            
            -- Display the box constantly
            trigger.action.outTextForUnit(uid, msg, 1, true)

            -- 3. Audio Callouts (For the closest tanker only)
            if sortedTankers[1] then
                local closest = sortedTankers[1]
                local dist_nm = closest.dist
                
                -- Refueling Progress Callout (If connected)
                if TankerLogic.refuelStartTime[uid] then
                    local startFuel = TankerLogic.refuelStartFuel[uid]
                    local currentFuel = player:getFuel()
                    -- Approx max fuel for Hornet internal + typical external ~17000lbs roughly? 
                    -- Just using raw ratio for now or generic calc
                    local lbsTransferred = (currentFuel - startFuel) * 11000 -- rough approx for internal
                    
                    if not TankerLogic.nextFuelCallout[uid] then TankerLogic.nextFuelCallout[uid] = 2000 end
                    
                    -- Check full
                    local isFull = currentFuel >= 0.99
                    
                    if lbsTransferred >= TankerLogic.nextFuelCallout[uid] and not isFull then
                        trigger.action.outTextForUnit(uid, string.format("Boom Operator: %.0f lbs transferred", TankerLogic.nextFuelCallout[uid]), 5)
                        TankerLogic.nextFuelCallout[uid] = TankerLogic.nextFuelCallout[uid] + 2000
                    end
                
                -- Approach Callout (If NOT connected)
                elseif dist_nm <= TankerLogic.CALLOUT_RANGE_NM then
                    -- Check cooldown
                    if not TankerLogic.lastCallout[uid] or (now - TankerLogic.lastCallout[uid] > TankerLogic.CALLOUT_COOLDOWN) then
                        local tUnit = closest.unit
                        local tVel = tUnit:getVelocity()
                        local relPos = vecSub(pPos, tUnit:getPoint())
                        local dist_m = vecMag(relPos)
                        local relVel = vecSub(pVel, tVel)
                        
                        -- Closure calculation
                        local closure_mps = (relPos.x * relVel.x + relPos.y * relVel.y + relPos.z * relVel.z) / dist_m
                        -- INVERT SIGN: Negative math means distance closing. We want positive display for "Closing at X knots"
                        local closure_kts = -(closure_mps * 1.94384) 

                        trigger.action.outTextForUnit(uid, string.format("Tanker: %.2f NM, Closure %.0f kts", dist_nm, closure_kts), 4)
                        TankerLogic.lastCallout[uid] = now
                    end
                end
            end
        end
    end)

    if not status then
        trigger.action.outText("Script Crash in UpdateLoop: " .. tostring(err), 20)
    end

    return now + TankerLogic.CALLOUT_INTERVAL
end

timer.scheduleFunction(TankerLogic.updateLoop, nil, timer.getTime() + 1)