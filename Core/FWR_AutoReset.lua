local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- Automatic session reset (Engine page: "Auto Session Reset").
-- Everything you do is always recorded in the area you are standing in. This module only decides when
-- the session of an area you LEFT starts over. "Area" follows the Tracking setting: a zone or a sub-zone.
--
-- After leaving an area:
--   1. while you are still in combat nothing counts: the delay starts when the fight ends;
--   2. during the delay, coming back to the area cancels the reset (a few steps over a border change nothing);
--   3. otherwise it resets when the delay is over, even if you are fighting somewhere else by then.
-- With a combined view (all characters, or all zones of the character) there is no area: nothing happens.

local DEFAULT_DELAY_SECONDS = 30

local lastKey = nil
local inCombat = false
local pending = {}   -- area -> { scope, number, timerRunning }
local departures = 0

-- The area of a context key under the current tracking mode, and the scope that covers exactly it.
local function resolveArea(self, contextKey, mode)
    local zone, subzone, characterKey = self:ParseContextKey(contextKey)
    if not zone then
        return nil
    end

    if mode == "subzone" then
        return zone .. "::" .. (subzone or ""), { mode = "subzone", characterKey = characterKey, zone = zone, subzone = subzone or "" }
    end
    return zone, { mode = "zone", characterKey = characterKey, zone = zone }
end

function FWR:GetAutoResetDelaySeconds()
    local engine = self.Settings and self.Settings.engine
    return math.max(15, tonumber(engine and engine.autoResetDelaySeconds) or DEFAULT_DELAY_SECONDS)
end

local function resetArea(self, area)
    local waiting = pending[area]
    pending[area] = nil
    if waiting then
        self:ResetSessionsInScope(waiting.scope)
    end
end

local function startDelay(self, area)
    local waiting = pending[area]
    if not waiting then
        return
    end

    waiting.timerRunning = true
    local mine = waiting.number
    C_Timer.After(self:GetAutoResetDelaySeconds(), function()
        if pending[area] and pending[area].number == mine then
            resetArea(FWR, area)
        end
    end)
end

function FWR:HandleAreaChanged(newKey)
    local previousKey = lastKey
    lastKey = newKey

    local engine = self.Settings and self.Settings.engine
    if type(engine) ~= "table" or engine.sessionResetMode ~= "auto" or not previousKey or previousKey == newKey then
        return
    end

    local mode = self:GetViewScope().mode
    if mode ~= "zone" and mode ~= "subzone" then
        return
    end

    local oldArea, oldScope = resolveArea(self, previousKey, mode)
    local newArea = resolveArea(self, newKey, mode)
    if not oldArea then
        return
    end

    -- What is gathered is counted for the whole zone (the context of the zone, with no sub-zone), so a move
    -- between the whole zone and a sub-zone of the same zone leaves nothing: no reset. Only leaving the zone
    -- resets the area of the whole zone.
    local oldZone, oldSubzone, characterKey = self:ParseContextKey(previousKey)
    local newZone, newSubzone = self:ParseContextKey(newKey)
    local wholeZoneArea = mode == "subzone" and oldZone and (oldZone .. "::") or nil
    if mode == "subzone" and newZone then
        pending[newZone .. "::"] = nil   -- being back in the zone cancels the waiting reset of its gathering
    end
    if mode == "subzone" and oldZone and oldZone == newZone and ((oldSubzone or "") == "" or (newSubzone or "") == "") then
        if newArea then
            pending[newArea] = nil
        end
        return
    end

    if newArea then
        pending[newArea] = nil   -- being back in an area cancels its waiting reset
    end
    if oldArea == newArea then
        return
    end

    departures = departures + 1
    pending[oldArea] = { scope = oldScope, number = departures, timerRunning = false }
    if not inCombat then
        startDelay(self, oldArea)
    end

    -- leaving the zone: what was gathered in it (counted for the whole zone) starts over too
    if wholeZoneArea and oldZone ~= newZone and wholeZoneArea ~= oldArea then
        departures = departures + 1
        pending[wholeZoneArea] = {
            scope = { mode = "subzone", characterKey = characterKey, zone = oldZone, subzone = "" },
            number = departures,
            timerRunning = false,
        }
        if not inCombat then
            startDelay(self, wholeZoneArea)
        end
    end
end

-- Combat started or ended. Areas that were left while fighting start their delay when the fight ends.
function FWR:HandleAutoResetCombat(isInCombat)
    inCombat = isInCombat == true

    local engine = self.Settings and self.Settings.engine
    if type(engine) ~= "table" or engine.sessionResetMode ~= "auto" then
        return
    end

    local areas = {}
    for area in pairs(pending) do
        areas[#areas + 1] = area
    end

    for _, area in ipairs(areas) do
        local waiting = pending[area]
        if waiting and not inCombat and not waiting.timerRunning then
            startDelay(self, area)
        end
    end
end
