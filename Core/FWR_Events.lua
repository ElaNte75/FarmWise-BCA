local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- Tiny internal event bus.
-- Modules announce what happened with FWR:Emit(); the main file (the orchestrator)
-- decides which modules react by calling FWR:Subscribe(). A failing subscriber never
-- breaks the module that emitted the event.
--
-- Events:
--   lootRecorded(entry, quantity)    an accepted loot entry was added to the display basket
--   activeTimeElapsed(seconds)       active farming time was credited
--   lootMoneyRecorded(copper)        looted money was credited
--   vendorValueRecorded(copper, zone, subzone)  vendor value of looted scrap (poor quality items)
--   areaChanged(contextKey)          the player moved to another zone or sub-zone
--   combatChanged(inCombat)          the player entered or left combat
--   processingUsed(key)              a disenchant, milling or prospecting was used (key: disenchant, milling, prospecting)
--   dataCleared()                    the user erased all saved data

local subscribers = {}

function FWR:Subscribe(eventName, handler)
    if type(eventName) ~= "string" or type(handler) ~= "function" then
        return
    end
    subscribers[eventName] = subscribers[eventName] or {}
    table.insert(subscribers[eventName], handler)
end

function FWR:Emit(eventName, ...)
    local handlers = subscribers[eventName]
    if not handlers then
        return
    end

    for index = 1, #handlers do
        local ok, err = pcall(handlers[index], ...)
        if not ok and type(geterrorhandler) == "function" then
            geterrorhandler()("FarmWise event '" .. eventName .. "': " .. tostring(err))
        end
    end
end
