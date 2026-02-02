-- F/A-18C Fuel System Detector
-- Reports Player Name, Fuel Percentage, and Calculated Tank Count

local function trackF18Tanks()
    
    -- Initialize the message string
    local messageString = "--- F/A-18C TANK REPORT ---\n"
    local playersFound = false

    -- Define the coalition sides to check (Red and Blue)
    local sides = {coalition.side.RED, coalition.side.BLUE}

    for _, side in pairs(sides) do
        local groups = coalition.getGroups(side)
        
        if groups then
            for _, group in pairs(groups) do
                local units = group:getUnits()
                
                for _, unit in pairs(units) do
                    -- Check if unit exists, is active, and is an F/A-18C
                    if unit and Unit.isExist(unit) and unit:isActive() then
                        local typeName = unit:getTypeName()
                        
                        if typeName == "FA-18C_hornet" or typeName == "F/A-18C" then
                            -- Check if it is a Player or Client (ignores AI)
                            local playerName = unit:getPlayerName()
                            
                            if playerName then
                                playersFound = true
                                
                                -- 1. Get Fuel Ratio and convert to Percentage
                                local fuelRatio = unit:getFuel()
                                local fuelPct = fuelRatio * 100 -- Convert 1.207 to 120.7
                                
                                -- 2. Determine Tank Count based total capacity of fuel system 
								-- Internal fuel +0 external tank = 99.9
								-- Internal fuel +1 external tank = 120.7
								-- Internal fuel +2 external tank = 141.1
								-- Internal fuel +3 external tank = 162.2
								-- Bases on DCS internal reporting
                                local tankCount = 0
                                
                                if fuelPct > 142.0 then
                                    tankCount = 3
                                elseif fuelPct > 121.0 then
                                    tankCount = 2
                                elseif fuelPct > 100.0 then
                                    tankCount = 1
                                else
                                    tankCount = 0
                                end
                                
                                -- 3. Add to the message string
                                -- Format: Name | Fuel: 123.4% | Tanks: 2
                                messageString = messageString .. string.format(
                                    "Pilot: %s | Fuel: %.1f%% | Tanks: %d\n", 
                                    playerName, 
                                    fuelPct, 
                                    tankCount
                                )
                            end
                        end
                    end
                end
            end
        end
    end

    -- If no players are found, indicate waiting status
    if not playersFound then
        messageString = messageString .. "Waiting for F/A-18C Pilots..."
    end

    -- Display the message to ALL players
    -- 10 seconds display time, true = clear previous message immediately (updates smoothly)
    trigger.action.outText(messageString, 2, true)

    -- Re-run this function in 1 second
    timer.scheduleFunction(trackF18Tanks, nil, timer.getTime() + 1)
end

-- Start the loop
trackF18Tanks()