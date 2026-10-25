local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local GetItemInfoInstant = GetItemInfoInstant
local GetItemInfo = GetItemInfo

local function detectSourceContext(itemInfo)
    if TradeFrame and TradeFrame:IsShown() then
        return "trade", false, "rejected_trade"
    end

    if MerchantFrame and MerchantFrame:IsShown() then
        return "vendor", false, "rejected_vendor"
    end

    if MailFrame and MailFrame:IsShown() then
        return "mail", false, "rejected_mail"
    end

    local recentlyCrafted, craftedRow = FWR.IsRecentlyCraftedOutput and FWR:IsRecentlyCraftedOutput(itemInfo) or false, nil
    if type(recentlyCrafted) == "table" then
        craftedRow = recentlyCrafted
        recentlyCrafted = true
    end
    if recentlyCrafted then
        return "crafting", false, "rejected_recent_crafted_output", craftedRow
    end

    local acquisitionContext = FWR.GetActiveAcquisitionContext and FWR:GetActiveAcquisitionContext() or nil
    if type(acquisitionContext) == "table" then
        local activeType = type(acquisitionContext.activeType) == "string" and acquisitionContext.activeType:lower() or nil
        if activeType == "processing" then
            return "processing", true, "accepted_processing_output", acquisitionContext
        end
        if activeType == "crafting" then
            return "crafting", false, "rejected_crafting_output", acquisitionContext
        end
    end

    local fishingState = FWR.GetFishingRouteSourceState and FWR:GetFishingRouteSourceState() or nil
    if type(fishingState) == "table" then
        return "fishing", true, "accepted_fishing_trigger"
    end

    local skinningState = FWR.GetSkinningRouteSourceState and FWR:GetSkinningRouteSourceState() or nil
    if type(skinningState) == "table" then
        return "skinning", true, "accepted_skinning_trigger"
    end

    local miningState = FWR.GetMiningRouteSourceState and FWR:GetMiningRouteSourceState() or nil
    if type(miningState) == "table" then
        return "mining", true, "accepted_mining_trigger"
    end

    local herbalismState = FWR.GetHerbalismRouteSourceState and FWR:GetHerbalismRouteSourceState() or nil
    if type(herbalismState) == "table" then
        return "herbalism", true, "accepted_herbalism_trigger"
    end

    return "combat", true, "accepted_loot_event"
end

function FWR:EvaluateLootSource(itemInfo)
    local itemID = itemInfo and GetItemInfoInstant(itemInfo) or nil
    local itemName, itemLink = itemInfo and GetItemInfo(itemInfo) or nil, itemInfo

    local sourceType, passed, reason, acquisitionContext = detectSourceContext(itemInfo)

    return {
        itemInfo = itemInfo,
        itemID = itemID,
        itemName = itemName,
        itemLink = itemLink,
        passed = passed,
        reason = reason,
        stage = "source_filter",
        sourceType = sourceType,
        acquisitionContext = acquisitionContext,
        activityContext = acquisitionContext and acquisitionContext.activityContext or nil,
        professionContext = acquisitionContext and acquisitionContext.professionContext or nil,
    }
end
