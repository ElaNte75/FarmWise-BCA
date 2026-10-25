local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- Combat visibility: minimizes the main window and/or hides the FarmWise panels (control panel,
-- Advisor) during combat and brings them back afterwards, following the Interface settings.

local panelsHiddenByCombat = {}

local function isPlayerInCombat()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return true
    end

    if type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") then
        return true
    end

    return false
end

function FWR:IsPlayerInCombat()
    return isPlayerInCombat()
end

local function collectManagedPanels(self)
    local panels = {}
    if self.ControlPanel then
        panels.controlPanel = self.ControlPanel
    end
    if self.AdvisorPanel then
        panels.advisorPanel = self.AdvisorPanel
    end
    return panels
end

-- The main window follows the Interface settings: in combat it is minimized to its small button when
-- "Minimize main window during combat" is on, and it opens again after the fight.
local function applyMainFrameRule(self, inCombat)
    self:ApplyMainWindowPresentation(inCombat)
end

local function applyPanelsRule(self, ui, inCombat)
    local panels = collectManagedPanels(self)

    if inCombat and ui.hideControlPanelsInCombat == true then
        for key, panel in pairs(panels) do
            if panel:IsShown() then
                panelsHiddenByCombat[key] = true
                panel:Hide()
            end
        end
        return
    end

    if not inCombat then
        if ui.restoreControlPanelsAfterCombat == true then
            for key in pairs(panelsHiddenByCombat) do
                local panel = panels[key]
                if panel and not panel:IsShown() then
                    panel:Show()
                end
            end
        end
        panelsHiddenByCombat = {}
    end
end

function FWR:ApplySettingsVisibilityRules(forceRefresh)
    local ui = self.Settings and self.Settings.ui or {}
    local inCombat = isPlayerInCombat()

    applyMainFrameRule(self, inCombat)
    applyPanelsRule(self, ui, inCombat)
end
