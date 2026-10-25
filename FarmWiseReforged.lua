local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local frame = CreateFrame("Frame")
FWR.EventFrame = frame
local function printStatus()
    local status = FWR:GetAdvisorStatus()
    local productName = FWR.PRODUCT_NAME or "BCA"
    print(string.format(
        "|cffd7be6aFarmWise %s|r ready - Advisor data: %d zones, %d tracked items. Type /fw advisor to open the Advisor.",
        productName,
        status.zones,
        status.items
    ))
end

function FWR:SetMainFrameVisibleState(isVisible, forceRefresh)
    self.Settings = self.Settings or {}
    self.Settings.ui = self.Settings.ui or {}
    self.Settings.ui.mainWindowVisible = isVisible == true
    if self.TouchDatabase then
        self:TouchDatabase()
    end
    if self.ApplySettingsVisibilityRules then
        self:ApplySettingsVisibilityRules(forceRefresh == true)
    elseif self.MainFrame then
        if isVisible then
            self.MainFrame:Show()
        else
            self.MainFrame:Hide()
        end
    end
end

function FWR:ToggleMainFrameVisibleState()
    local ui = self.Settings and self.Settings.ui or {}
    local isVisible = ui.mainWindowVisible ~= false
    self:SetMainFrameVisibleState(not isVisible, true)
end

local function handleAddonLoaded(addonName)
    if addonName ~= "FarmWiseBCA" then
        return
    end

    if FWR.RefreshVersion then
        FWR.RefreshVersion()
    end
    FWR:EnsureDatabases()
    FWR:EnsureAdvisorStore()
end

function FWR:ResetSessionForScope()
    local scope = self:GetViewScope()
    self:ResetSessionsInScope(scope)
    print("|cffd7be6aFarmWise|r session reset: " .. self:GetViewScopeLabel(scope) .. ".")
end

function FWR:ResetCurrentSessionView()
    return self:ResetSessionForScope()
end

local function handlePlayerLogin()
    FWR:EnsureDatabases()
    if FWR.EnsureRenderState then
        FWR:EnsureRenderState()
    end
    FWR:ResetIdleTransientState()
    if FWR.RefreshIdleZoneInfo then
        FWR:RefreshIdleZoneInfo()
    end
    FWR:InitializeMainFrameUI()
    local ui = FWR.Settings and FWR.Settings.ui or {}
    if FWR.Settings and FWR.Settings.ui then
        FWR.Settings.ui.mainWindowVisible = (ui.showMainWindowOnGameLoad ~= false)
    end
    if FWR.ApplySettingsVisibilityRules then
        FWR:ApplySettingsVisibilityRules(true)
    end
    if FWR.CreateLauncherIcon then
        FWR:CreateLauncherIcon()
    end
    printStatus()
end

local CANCEL_REASONS = {
    UNIT_SPELLCAST_INTERRUPTED = "interrupt",
    UNIT_SPELLCAST_FAILED = "failed",
    UNIT_SPELLCAST_STOP = "stop",
    UNIT_SPELLCAST_CHANNEL_STOP = "channel_stop",
}
local CANCEL_HANDLERS = {
    "HandleHerbalismSpellcastCancelled",
    "HandleMiningSpellcastCancelled",
    "HandleFishingSpellcastCancelled",
    "HandleSkinningSpellcastCancelled",
}

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        handleAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then
        handlePlayerLogin()
    elseif event == "CHAT_MSG_LOOT" then
        if not FWR:IsOtherPlayerLootMessage(...) then
            FWR:HandleLootChatMessage(...)
            FWR:HandleVendorLootMessage(...)
        end
    elseif event == "CHAT_MSG_MONEY" then
        if FWR.HandleLootMoneyChatMessage then
            FWR:HandleLootMoneyChatMessage(...)
        end
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        if FWR.HandleHerbalismSpellcastStart then
            FWR:HandleHerbalismSpellcastStart(...)
        end
        if FWR.HandleMiningSpellcastStart then
            FWR:HandleMiningSpellcastStart(...)
        end
        if FWR.HandleFishingSpellcastStart then
            FWR:HandleFishingSpellcastStart(...)
        end
        if FWR.HandleSkinningSpellcastStart then
            FWR:HandleSkinningSpellcastStart(...)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if FWR.HandleHerbalismSpellcastSucceeded then
            FWR:HandleHerbalismSpellcastSucceeded(...)
        end
        if FWR.HandleMiningSpellcastSucceeded then
            FWR:HandleMiningSpellcastSucceeded(...)
        end
        if FWR.HandleFishingSpellcastSucceeded then
            FWR:HandleFishingSpellcastSucceeded(...)
        end
        if FWR.HandleSkinningSpellcastSucceeded then
            FWR:HandleSkinningSpellcastSucceeded(...)
        end
        if FWR.HandleProcessingSpellcastSucceeded then
            FWR:HandleProcessingSpellcastSucceeded(...)
        end
    elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        if FWR.HandleTradeSkillItemCraftedResult then
            FWR:HandleTradeSkillItemCraftedResult(...)
        end
    elseif CANCEL_REASONS[event] then
        local unit, castGUID, spellID = ...
        for _, handlerName in ipairs(CANCEL_HANDLERS) do
            if FWR[handlerName] then
                FWR[handlerName](FWR, unit, castGUID, spellID, CANCEL_REASONS[event])
            end
        end
    elseif event:find("^AUCTION_HOUSE_") or event:find("^AUCTION_ITEM_LIST_") or event:find("^AUCTION_OWNED_LIST_")
        or event:find("^AUCTION_BIDDER_LIST_") or event == "NEW_AUCTION_UPDATE" then
        FWR:HandleAuctionHouseEvent(event, ...)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        FWR:HandleItemInfoReceived()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if FWR.HandleIdleCombatStart then
            FWR:HandleIdleCombatStart(...)
        end
        FWR:Emit("combatChanged", true)
        if FWR.ApplySettingsVisibilityRules then
            FWR:ApplySettingsVisibilityRules(true)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if FWR.HandleIdleCombatEnd then
            FWR:HandleIdleCombatEnd(...)
        end
        FWR:Emit("combatChanged", false)
        if FWR.ApplySettingsVisibilityRules then
            FWR:ApplySettingsVisibilityRules(true)
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
        if FWR.RefreshIdleZoneInfo then
            FWR:RefreshIdleZoneInfo()
        end
    end
end)

-- Runs every frame, but the work (cast timers, idle clock, reset schedule) needs a few checks a second.
local FRAME_WORK_SECONDS = 0.2
local frameWorkWaited = 0

frame:SetScript("OnUpdate", function(_, elapsed)
    frameWorkWaited = frameWorkWaited + (tonumber(elapsed) or 0)
    if frameWorkWaited < FRAME_WORK_SECONDS then
        return
    end
    frameWorkWaited = 0

    if FWR.RefreshHerbalismRouteState then
        FWR:RefreshHerbalismRouteState(GetTime and GetTime() or 0)
    end
    if FWR.RefreshMiningRouteState then
        FWR:RefreshMiningRouteState(GetTime and GetTime() or 0)
    end
    if FWR.RefreshFishingRouteState then
        FWR:RefreshFishingRouteState(GetTime and GetTime() or 0)
    end
    if FWR.RefreshSkinningRouteState then
        FWR:RefreshSkinningRouteState(GetTime and GetTime() or 0)
    end
    if FWR.UpdateIdleSystem then
        FWR:UpdateIdleSystem(FWR:Now())
    end
    FWR:TickSessionReset()
    if FWR.ApplySettingsVisibilityRules then
        local inCombat = false
        if type(InCombatLockdown) == "function" and InCombatLockdown() then
            inCombat = true
        elseif type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") then
            inCombat = true
        end

        if FWR.__fwrLastObservedCombatState ~= inCombat then
            FWR.__fwrLastObservedCombatState = inCombat
            FWR:ApplySettingsVisibilityRules(true)
        end
    end
end)

-- Module wiring: which module reacts to which engine event.
FWR:Subscribe("lootRecorded", function(entry, quantity)
    FWR:RecordAdvisorItem(entry, quantity)
end)
FWR:Subscribe("activeTimeElapsed", function(seconds)
    FWR:RecordAdvisorTime(seconds)
end)
FWR:Subscribe("lootMoneyRecorded", function(copper)
    FWR:RecordAdvisorGold(copper)
end)
FWR:Subscribe("vendorValueRecorded", function(copper, zone, subzone)
    FWR:RecordAdvisorVendor(copper, zone, subzone)
    FWR:RecordScrapGold(copper, zone, subzone)
end)
FWR:Subscribe("areaChanged", function(contextKey)
    FWR:HandleAreaChanged(contextKey)
end)
FWR:Subscribe("processingUsed", function(key)
    FWR:RecordAdvisorProcessingUse(key)
end)
FWR:Subscribe("combatChanged", function(inCombat)
    FWR:HandleAutoResetCombat(inCombat)
end)
FWR:Subscribe("dataCleared", function()
    FWR:ClearAdvisorData()
end)

-- Wrap RegisterEvent in pcall for WoW Forever compatibility (unknown events throw errors)
local function safeRegisterEvent(event)
    pcall(frame.RegisterEvent, frame, event)
end

local function safeRegisterUnitEvent(event, unit)
    pcall(frame.RegisterUnitEvent, frame, event, unit)
end

safeRegisterEvent("ADDON_LOADED")
safeRegisterEvent("PLAYER_LOGIN")
safeRegisterEvent("GET_ITEM_INFO_RECEIVED")
safeRegisterEvent("AUCTION_HOUSE_SHOW")
safeRegisterEvent("AUCTION_HOUSE_CLOSED")
safeRegisterEvent("AUCTION_ITEM_LIST_UPDATE")
safeRegisterEvent("AUCTION_OWNED_LIST_UPDATE")
safeRegisterEvent("AUCTION_BIDDER_LIST_UPDATE")
safeRegisterEvent("NEW_AUCTION_UPDATE")
safeRegisterEvent("CHAT_MSG_LOOT")
safeRegisterEvent("CHAT_MSG_MONEY")
safeRegisterUnitEvent("UNIT_SPELLCAST_START", "player")
safeRegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
safeRegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
safeRegisterEvent("TRADE_SKILL_ITEM_CRAFTED_RESULT")
safeRegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
safeRegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
safeRegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
safeRegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
safeRegisterEvent("PLAYER_REGEN_DISABLED")
safeRegisterEvent("PLAYER_REGEN_ENABLED")
safeRegisterEvent("PLAYER_ENTERING_WORLD")
safeRegisterEvent("ZONE_CHANGED")
safeRegisterEvent("ZONE_CHANGED_INDOORS")
safeRegisterEvent("ZONE_CHANGED_NEW_AREA")

SLASH_FARMWISEREFORGED1 = "/fw"
SlashCmdList.FARMWISEREFORGED = function(message)
    local command = message and message:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""

    if command == "status" or command == "" then
        printStatus()
        return
    end

    if command == "advisor" or command == "adv" then
        FWR:ToggleAdvisorPanel()
        return
    end

    if command == "scan" or command == "sync" then
        FWR:StartAuctionScan()
        return
    end

    if command == "ui" or command == "toggle" or command == "show" or command == "hide" then
        if not FWR.MainFrame then
            FWR:InitializeMainFrameUI()
        end
        FWR:ToggleMainFrameVisibleState()
        if FWR.Settings and FWR.Settings.ui and FWR.Settings.ui.mainWindowVisible ~= true and FWR.ControlPanel then
            FWR.ControlPanel:Hide()
        end
        return
    end

    if command == "options" then
        FWR:OpenControlPanelWindow()
        return
    end

    print("|cffd7be6aFarmWise|r commands: /fw advisor, /fw scan, /fw ui, /fw options, /fw status")
end
