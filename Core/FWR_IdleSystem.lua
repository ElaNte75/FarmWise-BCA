local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local GATHER_TRIGGER_GRACE_SECONDS = 45
local SKINNING_TRIGGER_GRACE_SECONDS = 30

local function normalizeText(value)
    if type(value) ~= "string" then
        return nil
    end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end
    return value
end

local function getCurrentZoneInfo()
    local zone = normalizeText(type(GetRealZoneText) == "function" and GetRealZoneText() or nil)
        or normalizeText(type(GetZoneText) == "function" and GetZoneText() or nil)
    local subzone = normalizeText(FWR:GetAreaSubZoneText())
    if subzone == zone then
        subzone = nil
    end
    return zone or "", subzone
end

local function getTimeDisplayFormatConfig()
    local elements = FWR.UI_CONFIG and FWR.UI_CONFIG.MainFrame and FWR.UI_CONFIG.MainFrame.elements or nil
    local cfg = elements and elements.timeDisplayFormat or nil
    return cfg or {}
end

local function formatTimePart(value, zeroPad)
    value = math.max(0, math.floor(tonumber(value) or 0))
    if zeroPad == false then
        return tostring(value)
    end
    return string.format("%02d", value)
end

local function formatClock(seconds)
    local cfg = getTimeDisplayFormatConfig()
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))

    local totalHours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    local timeSeparator = tostring(cfg.timeSeparator or ":")
    local showHoursWhenZero = cfg.showHoursWhenZero == true

    if totalHours <= 0 and not showHoursWhenZero then
        return table.concat({
            formatTimePart(minutes, cfg.zeroPadMinutes ~= false),
            formatTimePart(secs, cfg.zeroPadSeconds ~= false),
        }, timeSeparator)
    end

    return table.concat({
        formatTimePart(totalHours, cfg.zeroPadHours ~= false),
        formatTimePart(minutes, cfg.zeroPadMinutes ~= false),
        formatTimePart(secs, cfg.zeroPadSeconds ~= false),
    }, timeSeparator)
end

local function isGatherOwner(owner)
    return owner == "herbalism" or owner == "mining" or owner == "fishing" or owner == "skinning"
end

local function normalizeTriggerOwner(owner)
    if type(owner) ~= "string" then
        return nil
    end

    owner = owner:lower()
    if owner == "combat" or isGatherOwner(owner) then
        return owner
    end

    return nil
end

local function clearGatherTriggerState(state)
    state.activeTriggerOwner = nil
    state.gatherCastActive = false
    state.gatherDeadline = nil
    state.gatherContextKey = nil
end


function FWR:EnsureIdleSystemState()
    self:EnsureDatabases()
    self.DB.idleSystem = self.DB.idleSystem or {
        current = {
            zone = "",
            subzone = nil,
            key = "",
        },
        timersByContext = {},
        inCombat = false,
        graceDeadline = nil,
        graceContextKey = nil,
        activeTriggerOwner = nil,
        gatherCastActive = false,
        gatherDeadline = nil,
        gatherContextKey = nil,
        mode = "IDLE",
        lastUpdateAt = self:Now(),
    }

    local state = self.DB.idleSystem
    state.current = state.current or { zone = "", subzone = nil, key = "" }
    state.timersByContext = state.timersByContext or {}
    state.inCombat = state.inCombat == true
    state.mode = state.mode or "IDLE"
    state.graceDeadline = tonumber(state.graceDeadline)
    state.graceContextKey = state.graceContextKey or nil
    state.activeTriggerOwner = normalizeTriggerOwner(state.activeTriggerOwner)
    state.gatherCastActive = state.gatherCastActive == true
    state.gatherDeadline = tonumber(state.gatherDeadline)
    state.gatherContextKey = state.gatherContextKey or nil
    state.lastUpdateAt = tonumber(state.lastUpdateAt) or self:Now()
    return state
end


function FWR:GetIdleGatherGraceSeconds(owner)
    owner = normalizeTriggerOwner(owner)
    if owner == "skinning" then
        return SKINNING_TRIGGER_GRACE_SECONDS
    end
    return GATHER_TRIGGER_GRACE_SECONDS
end

function FWR:RefreshIdleTriggerState(now)
    local state = self:EnsureIdleSystemState()
    now = tonumber(now) or self:Now()

    if isGatherOwner(state.activeTriggerOwner) then
        if state.gatherCastActive == true then
            return state
        end

        local deadline = tonumber(state.gatherDeadline)
        if not deadline or now >= deadline then
            clearGatherTriggerState(state)
            if not state.inCombat and type(state.graceDeadline) ~= "number" then
                state.mode = "IDLE"
            end
        end
    elseif state.activeTriggerOwner ~= "combat" then
        state.activeTriggerOwner = nil
    end


    return state
end

function FWR:CanActivateIdleTrigger(owner, now)
    owner = normalizeTriggerOwner(owner)
    if not owner then
        return false
    end

    local state = self:RefreshIdleTriggerState(now)
    local activeOwner = normalizeTriggerOwner(state.activeTriggerOwner)
    if not activeOwner then
        return true
    end

    if owner == activeOwner then
        return true
    end

    if isGatherOwner(activeOwner) then
        if state.gatherCastActive == true then
            return owner == "combat"
        end

        return true
    end

    return true
end

function FWR:BeginIdleGatherCast(owner, options)
    owner = normalizeTriggerOwner(owner)
    if not isGatherOwner(owner) then
        return false
    end
    if self.NoteGatheringActivity then
        self:NoteGatheringActivity()   -- gathering is counted for the whole zone
    end

    local now = self:Now()
    self:ApplyIdleElapsed(now)

    local state = self:RefreshIdleTriggerState(now)
    local activeOwner = state.activeTriggerOwner
    if activeOwner and activeOwner ~= owner then
        if not self:CanActivateIdleTrigger(owner, now) then
            return false
        end

        if isGatherOwner(activeOwner) then
            clearGatherTriggerState(state)
        end
    end

    options = type(options) == "table" and options or {}
    state.activeTriggerOwner = owner
    state.gatherCastActive = true
    state.gatherDeadline = nil
    state.gatherContextKey = state.current and state.current.key or nil
    state.graceDeadline = nil
    state.graceContextKey = nil
    state.mode = "ACTIVE"
    state.lastUpdateAt = now

    if options.forceZone then
        state.current.zone = options.forceZone
        state.current.subzone = normalizeText(options.forceSubzone)
    end

    self:RefreshIdleZoneInfo()
    state = self:EnsureIdleSystemState()
    state.gatherContextKey = state.current and state.current.key or nil
    state.mode = "ACTIVE"

    return true
end

function FWR:ConfirmIdleGatherSuccess(owner, durationSeconds, options)
    owner = normalizeTriggerOwner(owner)
    if not isGatherOwner(owner) then
        return false
    end
    if self.NoteGatheringActivity then
        self:NoteGatheringActivity()
    end

    local now = self:Now()
    self:ApplyIdleElapsed(now)

    local state = self:RefreshIdleTriggerState(now)
    local activeOwner = state.activeTriggerOwner
    if activeOwner and activeOwner ~= owner then
        if not self:CanActivateIdleTrigger(owner, now) then
            return false
        end

        if isGatherOwner(activeOwner) then
            clearGatherTriggerState(state)
        end
    end

    options = type(options) == "table" and options or {}
    state.activeTriggerOwner = owner
    state.gatherCastActive = false
    state.gatherDeadline = now + math.max(0, tonumber(durationSeconds) or self:GetIdleGatherGraceSeconds(owner))
    state.graceDeadline = nil
    state.graceContextKey = nil
    state.mode = "GRACE"
    state.lastUpdateAt = now

    if options.forceZone then
        state.current.zone = options.forceZone
        state.current.subzone = normalizeText(options.forceSubzone)
    end

    self:RefreshIdleZoneInfo()
    state = self:EnsureIdleSystemState()
    state.gatherContextKey = state.current and state.current.key or nil
    state.mode = "GRACE"

    return true
end

function FWR:CancelIdleGatherCast(owner)
    owner = normalizeTriggerOwner(owner)
    if not isGatherOwner(owner) then
        return false
    end

    local now = self:Now()
    self:ApplyIdleElapsed(now)

    local state = self:RefreshIdleTriggerState(now)
    if state.activeTriggerOwner ~= owner then
        return false
    end


    clearGatherTriggerState(state)
    if state.inCombat then
        state.mode = "COMBAT"
    elseif type(state.graceDeadline) == "number" then
        state.mode = "GRACE"
    else
        state.mode = "IDLE"
    end
    state.lastUpdateAt = now
    self:RefreshIdleZoneInfo()

    return true
end

function FWR:EnsureIdleContext(zone, subzone)
    local state = self:EnsureIdleSystemState()
    zone = normalizeText(zone) or ""
    subzone = normalizeText(subzone)
    local key = self:BuildDetailedContextKey(zone, subzone)
    if key == "" then
        return nil, key
    end

    state.timersByContext[key] = state.timersByContext[key] or {
        zone = zone,
        subzone = subzone,
        totalSeconds = 0,
        sessionSeconds = 0,
    }

    local context = state.timersByContext[key]
    context.zone = zone
    context.subzone = subzone
    context.totalSeconds = tonumber(context.totalSeconds) or 0
    context.sessionSeconds = tonumber(context.sessionSeconds) or 0
    return context, key
end

function FWR:RefreshIdleZoneInfo()
    local now = self:Now()
    self:ApplyIdleElapsed(now)

    local state = self:RefreshIdleTriggerState(now)
    local zone, subzone = getCurrentZoneInfo()
    local nextKey = self:BuildDetailedContextKey(zone, subzone)
    local previousKey = state.current and state.current.key or ""
    local previousZone = state.current and state.current.zone or ""

    state.current.zone = zone
    state.current.subzone = subzone
    state.current.key = nextKey
    self:EnsureIdleContext(zone, subzone)
    state.lastUpdateAt = now

    if nextKey ~= previousKey then
        if nextKey ~= "" then
            self:Emit("areaChanged", nextKey)
        end
        if state.gatherCastActive == true or type(state.gatherDeadline) == "number" then
            state.gatherContextKey = nextKey
        end
        if state.inCombat or type(state.graceDeadline) == "number" then
            state.graceContextKey = nextKey
        end
        state.lastUpdateAt = now
    end

    if self.SyncRenderStateToCurrentContext then
        self:SyncRenderStateToCurrentContext()
    end

    if self.RefreshMainWindowText then
        self:RefreshMainWindowText()
    end
end

function FWR:ApplyIdleElapsed(now)
    local state = self:RefreshIdleTriggerState(now)
    now = tonumber(now) or self:Now()
    local lastUpdateAt = tonumber(state.lastUpdateAt) or now
    if now <= lastUpdateAt then
        state.lastUpdateAt = now
        return
    end

    local elapsed = now - lastUpdateAt
    local context = state.timersByContext[state.current.key or ""]
    if not context then
        state.lastUpdateAt = now
        return
    end

    local activeSeconds = 0

    if isGatherOwner(state.activeTriggerOwner) then
        if state.gatherCastActive == true then
            activeSeconds = elapsed
            state.mode = "ACTIVE"
        else
            local gatherDeadline = tonumber(state.gatherDeadline)
            if gatherDeadline and lastUpdateAt < gatherDeadline then
                local activeUntil = math.min(now, gatherDeadline)
                activeSeconds = math.max(0, activeUntil - lastUpdateAt)
            end

            if not gatherDeadline or now >= gatherDeadline then
                clearGatherTriggerState(state)
                if state.inCombat then
                    state.mode = "COMBAT"
                elseif type(state.graceDeadline) == "number" then
                    state.mode = "GRACE"
                else
                    state.mode = "IDLE"
                end
            else
                state.mode = "GRACE"
            end
        end
    elseif state.inCombat then
        activeSeconds = elapsed
        state.mode = "COMBAT"
    elseif type(state.graceDeadline) == "number" then
        if lastUpdateAt < state.graceDeadline then
            local activeUntil = math.min(now, state.graceDeadline)
            activeSeconds = math.max(0, activeUntil - lastUpdateAt)
        end
        if now >= state.graceDeadline then
            state.graceDeadline = nil
            state.graceContextKey = nil
            state.mode = "IDLE"
        else
            state.mode = "GRACE"
        end
    else
        state.mode = "IDLE"
    end

    if activeSeconds > 0 then
        context.totalSeconds = (tonumber(context.totalSeconds) or 0) + activeSeconds
        context.sessionSeconds = (tonumber(context.sessionSeconds) or 0) + activeSeconds
        self:Emit("activeTimeElapsed", activeSeconds)
        self:TouchDatabase()
    end

    state.lastUpdateAt = now
end

-- Runs a few times a second; the window clock only needs a refresh twice a second.
local WINDOW_REFRESH_SECONDS = 0.5

function FWR:UpdateIdleSystem(now)
    self:ApplyIdleElapsed(now or self:Now())

    local clock = GetTime()
    if clock - (self.__fwrWindowRefreshedAt or 0) >= WINDOW_REFRESH_SECONDS then
        self.__fwrWindowRefreshedAt = clock
        if self.RefreshMainWindowClock then
            self:RefreshMainWindowClock()
        end
    end
end

-- Forgets what was in progress when the game last closed, so offline time is never counted.
function FWR:ResetIdleTransientState()
    local state = self:EnsureIdleSystemState()
    state.inCombat = false
    state.graceDeadline = nil
    state.graceContextKey = nil
    clearGatherTriggerState(state)
    state.mode = "IDLE"
    state.lastUpdateAt = self:Now()
end

function FWR:GetLiveZoneText()
    local state = self:EnsureIdleSystemState()
    return state.current.zone or ""
end

function FWR:GetLiveSubzoneText()
    local state = self:EnsureIdleSystemState()
    return state.current.subzone or ""
end

function FWR:GetLiveTotalTimeValueText(totalSeconds)
    return formatClock(totalSeconds or self:SumViewScopeSeconds())
end

function FWR:GetLiveSessionTimeValueText(sessionSeconds)
    if not sessionSeconds then
        local _, seconds = self:SumViewScopeSeconds()
        sessionSeconds = seconds
    end
    return formatClock(sessionSeconds)
end

function FWR:GetIdleIndicatorText()
    local state = self:EnsureIdleSystemState()
    if state.inCombat then
        return "In Combat"
    end
    if isGatherOwner(state.activeTriggerOwner) then
        if state.gatherCastActive == true then
            if state.activeTriggerOwner == "herbalism" then
                return "Herbalism"
            end
            if state.activeTriggerOwner == "mining" then
                return "Mining"
            end
            if state.activeTriggerOwner == "fishing" then
                return "Fishing"
            end
            if state.activeTriggerOwner == "skinning" then
                return "Skinning"
            end
            return "ACTIVE"
        end
        local deadline = tonumber(state.gatherDeadline)
        if deadline then
            local remaining = math.max(0, math.ceil(deadline - self:Now()))
            if remaining > 0 then
                return tostring(remaining) .. "s"
            end
        end
    end
    if type(state.graceDeadline) == "number" then
        local remaining = math.max(0, math.ceil(state.graceDeadline - self:Now()))
        if remaining > 0 then
            return tostring(remaining) .. "s"
        end
    end
    return "IDLE"
end

function FWR:GetIdleIndicatorVisual()
    local state = self:EnsureIdleSystemState()
    if state.inCombat or state.gatherCastActive == true then
        return {
            color = { 0.25, 1.0, 0.25 },
            alpha = 1.0,
            font = "GameFontNormalSmall",
        }
    end

    if type(state.gatherDeadline) == "number" or type(state.graceDeadline) == "number" then
        return {
            color = { 1.0, 0.25, 0.25 },
            alpha = 1.0,
            font = "GameFontNormalSmall",
        }
    end


    -- only the idle state blinks; the main window drives the blink on its own steady clock
    return {
        color = { 1.0, 0.15, 0.15 },
        alpha = 1.0,
        font = "GameFontNormalSmall",
        blink = true,
    }
end


