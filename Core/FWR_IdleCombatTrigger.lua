local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local COMBAT_GRACE_SECONDS = 30

function FWR:HandleIdleCombatStart()
    if self.ApplyIdleElapsed then
        self:ApplyIdleElapsed(self:Now())
    end

    local state = self:EnsureIdleSystemState()

    state.inCombat = true
    state.graceDeadline = nil
    state.graceContextKey = nil
    state.activeTriggerOwner = "combat"
    state.mode = "COMBAT"

    if self.ClearHerbalismRouteState then
        self:ClearHerbalismRouteState(true)
    end
    if self.ClearMiningRouteState then
        self:ClearMiningRouteState(true)
    end
    if self.ClearSkinningRouteState then
        self:ClearSkinningRouteState(true)
    end


    if self.RefreshMainWindowText then
        self:RefreshMainWindowText()
    end
end

function FWR:HandleIdleCombatEnd()
    if self.ApplyIdleElapsed then
        self:ApplyIdleElapsed(self:Now())
    end

    local state = self:EnsureIdleSystemState()
    state.inCombat = false
    local now = self:Now()
    state.graceDeadline = now + COMBAT_GRACE_SECONDS
    state.graceContextKey = state.current and state.current.key or nil
    if state.activeTriggerOwner == "combat" then
        state.activeTriggerOwner = nil
    end
    state.mode = "GRACE"


    if self.RefreshMainWindowText then
        self:RefreshMainWindowText()
    end
end
