local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local GetItemInfoInstant = GetItemInfoInstant
local GetItemInfo = GetItemInfo

local PROCESSING_WINDOW_SECONDS = 4.0
local CRAFTING_WINDOW_SECONDS = 4.0

local PROCESSING_SPELLS = {
    [13262] = { profession = "Enchanting", activity = "processing", key = "disenchant" },
    [51005] = { profession = "Inscription", activity = "processing", key = "milling" },
    [31252] = { profession = "Jewelcrafting", activity = "processing", key = "prospecting" },
}

local CRAFTED_OUTPUT_WINDOW_SECONDS = 10.0
local MAX_RECENT_CRAFTED_OUTPUTS = 20

local function nowSeconds()
    return GetTime and GetTime() or 0
end

function FWR:EnsureAcquisitionContextState()
    self:EnsureDatabases()
    self.DB.renderState = self.DB.renderState or {}
    self.DB.renderState.acquisitionContext = self.DB.renderState.acquisitionContext or {
        activeType = nil,
        activityContext = nil,
        professionContext = nil,
        startedAt = nil,
        expiresAt = nil,
        spellID = nil,
    }

    local ctx = self.DB.renderState.acquisitionContext
    ctx.activeType = type(ctx.activeType) == "string" and ctx.activeType or nil
    ctx.activityContext = type(ctx.activityContext) == "string" and ctx.activityContext or nil
    ctx.professionContext = type(ctx.professionContext) == "string" and ctx.professionContext or nil
    ctx.startedAt = tonumber(ctx.startedAt)
    ctx.expiresAt = tonumber(ctx.expiresAt)
    ctx.spellID = tonumber(ctx.spellID)
    return ctx
end

function FWR:ClearAcquisitionContext()
    local ctx = self:EnsureAcquisitionContextState()
    ctx.activeType = nil
    ctx.activityContext = nil
    ctx.professionContext = nil
    ctx.startedAt = nil
    ctx.expiresAt = nil
    ctx.spellID = nil
    return ctx
end

function FWR:RefreshAcquisitionContext(now)
    local ctx = self:EnsureAcquisitionContextState()
    now = tonumber(now) or nowSeconds()
    if ctx.expiresAt and now >= ctx.expiresAt then
        self:ClearAcquisitionContext()
    end
    return ctx
end

function FWR:BeginAcquisitionContext(activeType, durationSeconds, spellID, professionContext)
    if activeType ~= "crafting" and activeType ~= "processing" then
        return self:ClearAcquisitionContext()
    end

    local now = nowSeconds()
    local ctx = self:EnsureAcquisitionContextState()
    ctx.activeType = activeType
    ctx.activityContext = activeType
    ctx.professionContext = type(professionContext) == "string" and professionContext or nil
    ctx.startedAt = now
    ctx.expiresAt = now + (tonumber(durationSeconds) or 0)
    ctx.spellID = tonumber(spellID)
    return ctx
end

function FWR:HandleProcessingSpellcastSucceeded(unitToken, castGUID, spellID)
    if unitToken ~= "player" then
        return
    end

    spellID = tonumber(spellID)
    local spellData = spellID and PROCESSING_SPELLS[spellID] or nil
    if not spellData then
        return
    end

    self:BeginAcquisitionContext("processing", PROCESSING_WINDOW_SECONDS, spellID, spellData.profession)
    self:Emit("processingUsed", spellData.key)
end

-- "disenchant", "milling" or "prospecting" while the result of one of them is arriving, else nil.
function FWR:GetActiveProcessingKey()
    local ctx = self:GetActiveAcquisitionContext()
    local spellData = ctx and ctx.activeType == "processing" and PROCESSING_SPELLS[tonumber(ctx.spellID)] or nil
    return spellData and spellData.key or nil
end

function FWR:HandleTradeSkillItemCraftedResult(...)
    self:BeginAcquisitionContext("crafting", CRAFTING_WINDOW_SECONDS, nil, nil)
    self:RegisterRecentCraftedOutput(...)
end

function FWR:GetActiveAcquisitionContext()
    local ctx = self:RefreshAcquisitionContext(nowSeconds())
    if not ctx or (ctx.activeType ~= "crafting" and ctx.activeType ~= "processing") then
        return nil
    end

    return {
        activeType = ctx.activeType,
        activityContext = ctx.activityContext,
        professionContext = ctx.professionContext,
        spellID = ctx.spellID,
        startedAt = ctx.startedAt,
        expiresAt = ctx.expiresAt,
    }
end


local function normalizeItemName(value)
    if type(value) ~= "string" then
        return nil
    end

    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end

    return value:lower()
end

local function extractCraftedResultIdentity(...)
    local identity = {
        itemID = nil,
        itemLink = nil,
        itemName = nil,
    }

    local argCount = select("#", ...)
    for index = 1, argCount do
        local value = select(index, ...)
        if type(value) == "string" then
            if not identity.itemLink and value:find("|Hitem:", 1, true) then
                identity.itemLink = value
                identity.itemID = identity.itemID or GetItemInfoInstant(value)
                identity.itemName = identity.itemName or select(1, GetItemInfo(value))
            elseif not identity.itemName and not value:find("|H", 1, true) then
                identity.itemName = value
            end
        elseif type(value) == "number" then
            local numberValue = tonumber(value)
            if numberValue and numberValue > 0 and numberValue == math.floor(numberValue) then
                identity.itemID = identity.itemID or numberValue
            end
        end
    end

    if identity.itemID and (not identity.itemName or identity.itemName == "") then
        identity.itemName = GetItemInfo(identity.itemID)
    end

    identity.itemName = normalizeItemName(identity.itemName)
    return identity
end

function FWR:EnsureRecentCraftedOutputState()
    self:EnsureDatabases()
    self.DB.renderState = self.DB.renderState or {}
    self.DB.renderState.recentCraftedOutputs = self.DB.renderState.recentCraftedOutputs or {}
    return self.DB.renderState.recentCraftedOutputs
end

function FWR:TrimRecentCraftedOutputs(now)
    local state = self:EnsureRecentCraftedOutputState()
    now = tonumber(now) or nowSeconds()

    for index = #state, 1, -1 do
        local row = state[index]
        if type(row) ~= "table" or not row.expiresAt or now >= row.expiresAt then
            table.remove(state, index)
        end
    end

    while #state > MAX_RECENT_CRAFTED_OUTPUTS do
        table.remove(state, 1)
    end

    return state
end

function FWR:RegisterRecentCraftedOutput(...)
    local identity = extractCraftedResultIdentity(...)
    if not identity.itemID and not identity.itemName then
        return nil
    end

    local now = nowSeconds()
    local state = self:TrimRecentCraftedOutputs(now)
    table.insert(state, {
        itemID = identity.itemID,
        itemLink = identity.itemLink,
        itemName = identity.itemName,
        createdAt = now,
        expiresAt = now + CRAFTED_OUTPUT_WINDOW_SECONDS,
    })

    self:TrimRecentCraftedOutputs(now)
    return state[#state]
end

function FWR:IsRecentlyCraftedOutput(itemInfo)
    local state = self:TrimRecentCraftedOutputs(nowSeconds())
    if type(state) ~= "table" or #state == 0 or not itemInfo then
        return false, nil
    end

    local itemID = GetItemInfoInstant(itemInfo)
    local itemName = normalizeItemName(select(1, GetItemInfo(itemInfo)) or itemInfo)

    for index = #state, 1, -1 do
        local row = state[index]
        if type(row) == "table" then
            if row.itemID and itemID and row.itemID == itemID then
                return true, row
            end
            if row.itemName and itemName and row.itemName == itemName then
                return true, row
            end
        end
    end

    return false, nil
end

local function resolveDisplayFilterSettings(settings)
    settings = type(settings) == "table" and settings or {}
    local displayFilters = settings.displayFilters or {}
    settings.displayFilters = displayFilters
    return displayFilters
end

function FWR:GetDisplayFilterSettings()
    self:EnsureDatabases()
    return resolveDisplayFilterSettings(self.Settings)
end

function FWR:IsSpecializedClassificationVisible()
    local displayFilters = self:GetDisplayFilterSettings()
    if displayFilters.onlySpecializedClassifications == true then
        return false
    end
    return displayFilters.showSpecializedClassifications and true or false
end

function FWR:IsOnlySpecializedClassificationVisible()
    local displayFilters = self:GetDisplayFilterSettings()
    return displayFilters.onlySpecializedClassifications and true or false
end

function FWR:SetSpecializedClassificationVisible(isVisible)
    local displayFilters = self:GetDisplayFilterSettings()
    displayFilters.showSpecializedClassifications = isVisible and true or false
    if isVisible then
        displayFilters.onlySpecializedClassifications = false
    end
    if self.TouchDatabase then
        self:TouchDatabase()
    end
end

function FWR:SetOnlySpecializedClassificationVisible(isVisible)
    local displayFilters = self:GetDisplayFilterSettings()
    displayFilters.onlySpecializedClassifications = isVisible and true or false
    if isVisible then
        displayFilters.showSpecializedClassifications = false
    end
    if self.TouchDatabase then
        self:TouchDatabase()
    end
end

local function resolveTrackingSettings(settings)
    settings = type(settings) == "table" and settings or {}
    local tracking = settings.tracking or {}
    settings.tracking = tracking
    return tracking
end

function FWR:GetTrackingSettings()
    self:EnsureDatabases()
    return resolveTrackingSettings(self.Settings)
end

function FWR:IsCombinedAllDataEnabled()
    local tracking = self:GetTrackingSettings()
    return tracking.combinedAllData == true
end

function FWR:IsCombinedCharacterAllZonesEnabled()
    local tracking = self:GetTrackingSettings()
    return tracking.combinedCharacterAllZones == true
end

function FWR:IsZoneDataEnabled()
    local tracking = self:GetTrackingSettings()
    if tracking.subZoneData == true then
        return false
    end
    return tracking.zoneData ~= false
end

local refreshTrackingDisplay

function FWR:IsSubZoneDataEnabled()
    local tracking = self:GetTrackingSettings()
    return tracking.subZoneData == true
end

function FWR:SetZoneDataEnabled(isEnabled)
    local tracking = self:GetTrackingSettings()
    local enabled = isEnabled == true
    if tracking.combinedAllData == true or tracking.combinedCharacterAllZones == true then
        tracking.zoneData = false
        tracking.subZoneData = false
    elseif enabled then
        tracking.zoneData = true
        tracking.subZoneData = false
    else
        tracking.zoneData = false
        tracking.subZoneData = true
    end
    refreshTrackingDisplay(self)
    if self.RefreshIdleZoneInfo then
        self:RefreshIdleZoneInfo()
    end
    if self.SyncRenderStateToCurrentContext then
        self:SyncRenderStateToCurrentContext()
    end
end

function FWR:SetSubZoneDataEnabled(isEnabled)
    local tracking = self:GetTrackingSettings()
    local enabled = isEnabled == true
    if tracking.combinedAllData == true or tracking.combinedCharacterAllZones == true then
        tracking.zoneData = false
        tracking.subZoneData = false
    elseif enabled then
        tracking.subZoneData = true
        tracking.zoneData = false
    else
        tracking.subZoneData = false
        tracking.zoneData = true
    end
    refreshTrackingDisplay(self)
    if self.RefreshIdleZoneInfo then
        self:RefreshIdleZoneInfo()
    end
    if self.SyncRenderStateToCurrentContext then
        self:SyncRenderStateToCurrentContext()
    end
end

refreshTrackingDisplay = function(self)
    if self.TouchDatabase then
        self:TouchDatabase()
    end
    if self.QueueDisplayRefreshes then
        self:QueueDisplayRefreshes()
    elseif self.RefreshDisplayText then
        self:RefreshDisplayText()
    end
end

function FWR:SetCombinedAllDataEnabled(isEnabled)
    local tracking = self:GetTrackingSettings()
    local enabled = isEnabled == true
    tracking.combinedAllData = enabled
    if enabled then
        tracking.combinedCharacterAllZones = false
        tracking.zoneData = false
        tracking.subZoneData = false
    elseif tracking.combinedCharacterAllZones ~= true then
        tracking.zoneData = false
        tracking.subZoneData = true
    end
    refreshTrackingDisplay(self)
    if self.RefreshIdleZoneInfo then
        self:RefreshIdleZoneInfo()
    end
    if self.SyncRenderStateToCurrentContext then
        self:SyncRenderStateToCurrentContext()
    end
end

function FWR:SetCombinedCharacterAllZonesEnabled(isEnabled)
    local tracking = self:GetTrackingSettings()
    local enabled = isEnabled == true
    tracking.combinedCharacterAllZones = enabled
    if enabled then
        tracking.combinedAllData = false
        tracking.zoneData = false
        tracking.subZoneData = false
    elseif tracking.combinedAllData ~= true then
        tracking.zoneData = false
        tracking.subZoneData = true
    end
    refreshTrackingDisplay(self)
    if self.RefreshIdleZoneInfo then
        self:RefreshIdleZoneInfo()
    end
    if self.SyncRenderStateToCurrentContext then
        self:SyncRenderStateToCurrentContext()
    end
end
