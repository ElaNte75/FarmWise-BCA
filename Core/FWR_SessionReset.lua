local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- Session reset (Engine page). In "manual" mode sessions only reset when the user asks.
-- In "local" mode every session counter is reset once per day at the chosen local time.
-- "auto" mode lives in FWR_AutoReset.lua. Totals and the Advisor statistics are never touched.

local CHECK_INTERVAL_SECONDS = 30

local function forEachTable(root, callback)
    if type(root) ~= "table" then
        return
    end
    for _, value in pairs(root) do
        if type(value) == "table" then
            callback(value)
        end
    end
end

function FWR:ResetSessionsInScope(scope)
    local db = self.DB
    if type(db) ~= "table" then
        return
    end

    scope = scope or { mode = "all" }

    self:ForEachInViewScope(db.idleSystem and db.idleSystem.timersByContext, scope, function(_, timer)
        timer.sessionSeconds = 0
    end)

    self:ForEachInViewScope(db.goldLedger and db.goldLedger.byContextKey, scope, function(_, bucket)
        bucket.rawLootCopperSession = 0
        bucket.scrapCopperSession = 0
    end)

    self:ForEachInViewScope(db.renderState and db.renderState.displayBasketByContext, scope, function(_, basket)
        forEachTable(basket.byKey, function(entry)
            entry.quantityCount = 0
        end)
    end)

    if self.TouchDatabase then
        self:TouchDatabase()
    end
    if self.RefreshMainWindowText then
        self:RefreshMainWindowText()
    end
    if self.RefreshDisplayLiveMetrics then
        self:RefreshDisplayLiveMetrics(true)
    end
end

function FWR:ResetAllSessions()
    self:ResetSessionsInScope({ mode = "all" })
end

local function getScheduledTimestamp(minutesOfDay, nowTimestamp)
    local today = date("*t", nowTimestamp)
    return time({
        year = today.year,
        month = today.month,
        day = today.day,
        hour = math.floor(minutesOfDay / 60),
        min = minutesOfDay % 60,
        sec = 0,
    })
end

-- Cheap enough to call every frame: it only does work every CHECK_INTERVAL_SECONDS.
function FWR:TickSessionReset()
    local engine = self.Settings and self.Settings.engine
    if type(engine) ~= "table" or engine.sessionResetMode ~= "local" then
        return
    end

    local now = time()
    if now - (self.__fwrSessionResetCheckedAt or 0) < CHECK_INTERVAL_SECONDS then
        return
    end
    self.__fwrSessionResetCheckedAt = now

    local meta = self.DB and self.DB.meta
    if type(meta) ~= "table" then
        return
    end

    local scheduled = getScheduledTimestamp(tonumber(engine.localResetMinutes) or 0, now)
    local lastReset = tonumber(meta.lastScheduledSessionReset)

    if now < scheduled then
        -- remember when the schedule was first seen, so the coming reset time is not skipped
        if not lastReset then
            meta.lastScheduledSessionReset = now
        end
        return
    end

    if lastReset and lastReset >= scheduled then
        return
    end

    meta.lastScheduledSessionReset = now

    -- The first time the schedule is seen only records the moment; it never resets retroactively.
    if lastReset then
        self:ResetAllSessions()
    end
end

-- Seconds until the next daily reset of the "local" mode.
local function getSecondsUntilLocalReset(engine)
    local now = time()
    local scheduled = getScheduledTimestamp(tonumber(engine.localResetMinutes) or 0, now)
    if now >= scheduled then
        scheduled = scheduled + 24 * 3600
    end
    return scheduled - now
end

local function formatWait(seconds)
    local minutes = math.max(1, math.ceil(seconds / 60))
    if minutes >= 60 then
        return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
    end
    return string.format("%dm", minutes)
end

-- What the main window's Reset button shows: its text, whether it can be pressed, and its tooltip.
-- Only the manual mode has a real button; the other two modes show how the reset will happen.
function FWR:GetSessionResetButtonState()
    local engine = self.Settings and self.Settings.engine or {}
    local mode = engine.sessionResetMode

    if mode == "local" then
        local wait = getSecondsUntilLocalReset(engine)
        return {
            text = formatWait(wait),
            enabled = false,
            tooltip = string.format("Session reset: daily\nThe session starts over by itself every day at %s (in %s).\nChange this in Options > Engine.",
                string.format("%02d:%02d", math.floor((tonumber(engine.localResetMinutes) or 0) / 60), (tonumber(engine.localResetMinutes) or 0) % 60), formatWait(wait)),
        }
    elseif mode == "auto" then
        return {
            text = "Auto",
            enabled = false,
            tooltip = string.format("Session reset: automatic\nThe session of an area starts over %d seconds after you left it and finished fighting. Coming back in time keeps it. It follows the Tracking setting: Zone or Sub-Zone.\nChange this in Options > Engine.",
                self:GetAutoResetDelaySeconds()),
        }
    end

    return {
        text = "Reset",
        enabled = true,
        tooltip = "Reset session\nStarts a new session for what the window shows: session time, session items and session gold go back to zero.\nYour saved data and the Advisor are NOT erased.",
    }
end
