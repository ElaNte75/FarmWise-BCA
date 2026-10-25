local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local GetItemInfoInstant = GetItemInfoInstant
local GetItemInfo = GetItemInfo
local GetSpellInfo = GetSpellInfo

local SKINNING_BATCH_SECONDS = 8.0
local SKINNING_BATCH_EXTENSION_SECONDS = 6.0
local SKINNING_USAGE_PROFESSIONS = "Leatherworking"
local SKINNING_DISPLAY_PROFESSION = "Leatherworking"
local SHARED_MULTI_REAGENT_RULES = {
    ["mote of light"] = {
        itemTypeContext = "Reagent",
        profession = "Skinning",
        baseProfession = "Leatherworking",
        activityKey = "skinning",
        activityContext = "Skinning",
        activitySource = "skinning_trigger",
        observedSourceLabel = "Skinning",
        isDynamicSharedReagent = true,
    },
}
local SKINNING_SPELL_NAMES = {
    ["skinning"] = true,
    ["skinning corpse"] = true,
}

local ITEM_BIND_ON_ACQUIRE = (Enum and Enum.ItemBind and Enum.ItemBind.OnAcquire) or 1
local ITEM_BIND_TO_ACCOUNT = (Enum and Enum.ItemBind and Enum.ItemBind.ToWoWAccount) or 7
local ITEM_BIND_TO_BNET_ACCOUNT = (Enum and Enum.ItemBind and Enum.ItemBind.ToBnetAccount) or 8
local ITEM_BIND_TO_BNET_ACCOUNT_UNTIL_EQUIP = (Enum and Enum.ItemBind and Enum.ItemBind.ToBnetAccountUntilEquipped) or 9

local ITEM_TYPE_RULES = {
    { itemType = "Elemental Reagent", tooltip = { "mote", "primal", "volatile", "eternal", "crystallized", "elemental" }, subtype = { "elemental", "elemental reagent" }, type = { "elemental", "elemental reagent" } },
    { itemType = "Leather", tooltip = { "leather", "hide", "pelt", "fur", "skin" }, subtype = { "leather", "hide" }, type = { "leather", "hide" } },
    { itemType = "Scale", tooltip = { "scale", "scales" }, subtype = { "scale", "scales" }, type = { "scale", "scales" } },
    { itemType = "Meat", tooltip = { "meat", "egg", "haunch", "rib", "fillet" }, subtype = { "meat", "cooking" }, type = { "meat", "cooking" } },
    { itemType = "Reagent", tooltip = { "crafting reagent", "optional reagent" }, subtype = { "reagent" }, type = {} },
}

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

local function normalizeLower(value)
    value = normalizeText(value)
    return value and value:lower() or nil
end

local function getCurrentZoneName()
    local zone = type(GetRealZoneText) == "function" and GetRealZoneText() or nil
    zone = normalizeText(zone)
    if zone then
        return zone
    end
    zone = type(GetZoneText) == "function" and GetZoneText() or nil
    return normalizeText(zone) or ""
end

local function getCurrentSubZoneName()
    local subZone = FWR:GetAreaSubZoneText()
    return normalizeText(subZone)
end

local function getSpellName(spellID)
    spellID = tonumber(spellID)
    if spellID then
        local spellName = GetSpellInfo(spellID)
        if type(spellName) == "string" and spellName ~= "" then
            return spellName
        end
    end
    return nil
end

local function resolvePlayerCastOrChannelSpellName()
    local channelName = UnitChannelInfo and UnitChannelInfo("player") or nil
    if type(channelName) == "string" and channelName ~= "" then
        return channelName
    end

    local castName = UnitCastingInfo and UnitCastingInfo("player") or nil
    if type(castName) == "string" and castName ~= "" then
        return castName
    end

    return nil
end

local function isSkinningSpell(spellID, fallbackName)
    local spellName = normalizeLower(getSpellName(spellID) or fallbackName or resolvePlayerCastOrChannelSpellName())
    if not spellName then
        return false, nil
    end

    if SKINNING_SPELL_NAMES[spellName] == true then
        return true, spellName
    end

    if spellName:find("skinning", 1, true) or spellName:find("skin", 1, true) then
        return true, spellName
    end

    return false, spellName
end

local function containsAny(text, needles)
    if text == "" or type(needles) ~= "table" then
        return false
    end
    for _, needle in ipairs(needles) do
        if text:find(needle, 1, true) then
            return true
        end
    end
    return false
end

local function collectTooltipText(itemLink)
    local chunks = {}
    if type(itemLink) ~= "string" or itemLink == "" then
        return ""
    end

    local tipText = FWR:GetTooltipText(itemLink)
    if tipText ~= "" then
        chunks[#chunks + 1] = tipText
    end

    return normalizeLower(table.concat(chunks, " ")) or ""
end

local function resolveSharedMultiReagentRule(candidate)
    local itemName = normalizeLower(candidate and candidate.itemName)
    return itemName and SHARED_MULTI_REAGENT_RULES[itemName] or nil
end

local function classifyItemTypeFromTooltip(candidate)
    local tooltipText = collectTooltipText(candidate.itemLink)
    local subtypeText = normalizeLower(candidate.itemSubType) or ""
    local typeText = normalizeLower(candidate.itemType) or ""

    for _, rule in ipairs(ITEM_TYPE_RULES) do
        if containsAny(tooltipText, rule.tooltip) then
            return rule.itemType, "tooltip_text"
        end
    end
    for _, rule in ipairs(ITEM_TYPE_RULES) do
        if containsAny(subtypeText, rule.subtype) then
            return rule.itemType, "item_subtype"
        end
    end
    for _, rule in ipairs(ITEM_TYPE_RULES) do
        if containsAny(typeText, rule.type) then
            return rule.itemType, "item_type"
        end
    end

    if candidate.isCraftingReagent then
        return "Reagent", "crafting_reagent_flag"
    end

    return "General", "general_fallback"
end

local function getExpansionName(expansionID)
    if expansionID == nil then
        return nil
    end
    local globalName = _G and _G["EXPANSION_NAME" .. tostring(expansionID)]
    if type(globalName) == "string" and globalName ~= "" then
        return globalName
    end
    return string.format("Expansion %d", expansionID)
end

local function getCurrentExpansionID()
    if type(GetExpansionLevel) == "function" then
        local value = tonumber(GetExpansionLevel())
        if value ~= nil then
            return value
        end
    end
    local value = tonumber(_G and _G.LE_EXPANSION_LEVEL_CURRENT)
    if value ~= nil then
        return value
    end
    local numLevels = tonumber(_G and _G.NUM_LE_EXPANSION_LEVELS)
    if numLevels ~= nil and numLevels > 0 then
        return numLevels - 1
    end
    return nil
end

local function isSoulboundBindType(bindType)
    return bindType == ITEM_BIND_ON_ACQUIRE
end

local function isWarbandBindType(bindType)
    return bindType == ITEM_BIND_TO_ACCOUNT
        or bindType == ITEM_BIND_TO_BNET_ACCOUNT
        or bindType == ITEM_BIND_TO_BNET_ACCOUNT_UNTIL_EQUIP
end

function FWR:EnsureSkinningRouteState()
    self:EnsureDatabases()
    self.DB.skinningRoute = self.DB.skinningRoute or {
        castActive = false,
        castGUID = nil,
        spellID = nil,
        spellName = nil,
        startedAt = nil,
        batchActive = false,
        batchExpiresAt = nil,
        zoneName = nil,
        subZoneName = nil,
        lastSuccessAt = nil,
    }

    local state = self.DB.skinningRoute
    state.castActive = state.castActive == true
    state.castGUID = type(state.castGUID) == "string" and state.castGUID or nil
    state.spellID = tonumber(state.spellID)
    state.spellName = type(state.spellName) == "string" and state.spellName or nil
    state.startedAt = tonumber(state.startedAt)
    state.batchActive = state.batchActive == true
    state.batchExpiresAt = tonumber(state.batchExpiresAt)
    state.zoneName = type(state.zoneName) == "string" and state.zoneName or nil
    state.subZoneName = type(state.subZoneName) == "string" and state.subZoneName or nil
    state.lastSuccessAt = tonumber(state.lastSuccessAt)
    return state
end

function FWR:ClearSkinningRouteState(clearBatch)
    local state = self:EnsureSkinningRouteState()
    state.castActive = false
    state.castGUID = nil
    state.spellID = nil
    state.spellName = nil
    state.startedAt = nil
    if clearBatch then
        state.batchActive = false
        state.batchExpiresAt = nil
        state.zoneName = nil
        state.subZoneName = nil
        state.lastSuccessAt = nil
    end
    return state
end

function FWR:RefreshSkinningRouteState(now)
    local state = self:EnsureSkinningRouteState()
    now = tonumber(now) or (GetTime and GetTime() or 0)
    if state.batchActive and state.batchExpiresAt and now >= state.batchExpiresAt then
        state.batchActive = false
        state.batchExpiresAt = nil
        state.zoneName = nil
        state.subZoneName = nil
        state.lastSuccessAt = nil
    end
    return state
end

function FWR:GetSkinningRouteSourceState()
    local state = self:RefreshSkinningRouteState(GetTime and GetTime() or 0)
    if not state.batchActive then
        return nil
    end

    return {
        routeName = "skinning",
        sourceType = "skinning",
        zoneName = state.zoneName,
        subZoneName = state.subZoneName,
        expiresAt = state.batchExpiresAt,
    }
end

function FWR:HandleSkinningSpellcastStart(unitToken, castGUID, spellID)
    if unitToken ~= "player" then
        return
    end

    local fallbackSpellName = resolvePlayerCastOrChannelSpellName()
    local isMatch, spellName = isSkinningSpell(spellID, fallbackSpellName)
    if not isMatch then
        return
    end

    local zoneName = getCurrentZoneName()
    local subZoneName = getCurrentSubZoneName()
    local canTakeOwnership = self.CanActivateIdleTrigger and self:CanActivateIdleTrigger("skinning", self:Now()) or true

    if not canTakeOwnership then
        return
    end

    local beganIdleCast = true
    if self.BeginIdleGatherCast then
        beganIdleCast = self:BeginIdleGatherCast("skinning", {
            forceZone = zoneName,
            forceSubzone = subZoneName,
        })
    end

    if beganIdleCast == false then
        return
    end

    local state = self:EnsureSkinningRouteState()
    state.castActive = true
    state.castGUID = castGUID
    state.spellID = tonumber(spellID)
    state.spellName = spellName
    state.startedAt = GetTime and GetTime() or 0
    state.zoneName = zoneName
    state.subZoneName = subZoneName

end

function FWR:HandleSkinningSpellcastCancelled(unitToken, castGUID, spellID, reasonText)
    if unitToken ~= "player" then
        return
    end

    local state = self:EnsureSkinningRouteState()
    local isMatch = state.castActive == true and (not spellID or tonumber(spellID) == state.spellID)
    if not isMatch then
        return
    end

    if self.CancelIdleGatherCast then
        self:CancelIdleGatherCast("skinning")
    end

    self:ClearSkinningRouteState(false)

end

function FWR:HandleSkinningSpellcastSucceeded(unitToken, castGUID, spellID)
    if unitToken ~= "player" then
        return
    end

    local state = self:EnsureSkinningRouteState()
    local isMatch = state.castActive == true and (not spellID or tonumber(spellID) == state.spellID)
    if not isMatch then
        return
    end

    local zoneName = getCurrentZoneName()
    local subZoneName = getCurrentSubZoneName()
    local gatherGraceStarted = true
    if self.ConfirmIdleGatherSuccess then
        gatherGraceStarted = self:ConfirmIdleGatherSuccess("skinning", self.GetIdleGatherGraceSeconds and self:GetIdleGatherGraceSeconds("skinning") or 30, {
            forceZone = zoneName,
            forceSubzone = subZoneName,
        })
    end

    if gatherGraceStarted == false then
        self:ClearSkinningRouteState(true)
        return
    end

    state.castActive = false
    state.batchActive = true
    state.batchExpiresAt = (GetTime and GetTime() or 0) + SKINNING_BATCH_SECONDS
    state.zoneName = zoneName
    state.subZoneName = subZoneName
    state.lastSuccessAt = GetTime and GetTime() or 0

end

local function buildBaseCandidate(sourceStage)
    local itemInfo = sourceStage and (sourceStage.itemInfo or sourceStage.itemLink or sourceStage.itemID) or nil
    return {
        itemInfo = itemInfo,
        itemID = itemInfo and GetItemInfoInstant(itemInfo) or nil,
        itemLink = itemInfo and select(2, GetItemInfo(itemInfo)) or nil,
        itemName = itemInfo and GetItemInfo(itemInfo) or nil,
        passed = false,
        reason = "unresolved_item",
        stage = "rt_skinning_route",
        sourceType = sourceStage and sourceStage.sourceType or nil,
        triggerSource = "skinning",
        routeName = "skinning",
    }
end

function FWR:BuildSkinningRouteResult(sourceStage)
    local result = buildBaseCandidate(sourceStage)
    if type(sourceStage) ~= "table" or not sourceStage.passed then
        result.reason = "blocked_by_source_filter"
        return result, false
    end

    local itemInfo = result.itemInfo
    if not itemInfo then
        return result, false
    end

    local itemName, itemLink, itemRarity, _, _, itemType, itemSubType, _, itemEquipLoc, icon, _, classID, subclassID, bindType, expansionID, _, isCraftingReagent = GetItemInfo(itemInfo)
    result.itemName = itemName
    result.itemLink = itemLink or result.itemLink
    result.itemRarity = itemRarity
    result.itemType = itemType
    result.itemSubType = itemSubType
    result.classID = classID
    result.subclassID = subclassID
    result.bindType = bindType
    result.expansionID = expansionID
    result.isCraftingReagent = isCraftingReagent and true or false
    result.itemQuality = nil or 0

    if itemName == nil and itemLink == nil and classID == nil and isCraftingReagent == nil then
        result.reason = "item_info_not_ready"
        return result, true
    end

    result.isTradeMaterial = result.isCraftingReagent == true
    if not result.isTradeMaterial then
        result.reason = "not_skinning_material"
        return result, false
    end

    result.isSoulboundType = isSoulboundBindType(bindType)
    result.isWarbandType = isWarbandBindType(bindType)
    result.isAuctionHouseValid = not result.isSoulboundType and not result.isWarbandType
    if not result.isAuctionHouseValid then
        result.reason = result.isSoulboundType and "rejected_soulbound" or "rejected_warband"
        return result, false
    end

    local sharedRule = resolveSharedMultiReagentRule(result)
    if sharedRule then
        result.itemTypeContext = sharedRule.itemTypeContext
        result.itemTypeSource = "shared_multi_reagent_rule"
        result.profession = sharedRule.profession
        result.baseProfession = sharedRule.baseProfession
        result.activityKey = sharedRule.activityKey
        result.activityContext = sharedRule.activityContext
        result.activitySource = sharedRule.activitySource
        result.observedSourceLabel = sharedRule.observedSourceLabel
        result.isDynamicSharedReagent = sharedRule.isDynamicSharedReagent == true
    else
        result.itemTypeContext, result.itemTypeSource = classifyItemTypeFromTooltip(result)
        result.profession = SKINNING_DISPLAY_PROFESSION
        result.baseProfession = SKINNING_USAGE_PROFESSIONS
        result.activityKey = "skinning"
        result.activityContext = "Skinning"
        result.activitySource = "skinning_trigger"
        result.observedSourceLabel = "Skinning"
        result.isDynamicSharedReagent = false
    end

    result.isTradeMaterial = result.isTradeMaterial
        or result.itemTypeContext == "Leather"
        or result.itemTypeContext == "Scale"
        or result.itemTypeContext == "Meat"
        or result.itemTypeContext == "Reagent"
        or result.itemTypeContext == "Elemental Reagent"

    local currentExpansionID = getCurrentExpansionID()
    result.currentExpansionID = currentExpansionID
    result.expansionName = getExpansionName(result.expansionID)
    result.expansionCategory = (result.expansionID and currentExpansionID and result.expansionID < currentExpansionID) and "old" or "current"

    local characterName, realmName = nil, nil
    if self.GetCurrentCharacterIdentity then
        characterName, realmName = self:GetCurrentCharacterIdentity()
    end
    local className, classFile = nil, nil
    if UnitClass then
        className, classFile = UnitClass("player")
    end
    result.characterContext = characterName
    result.characterName = characterName
    result.characterKey = self.BuildCharacterKey and self:BuildCharacterKey(characterName, realmName) or characterName
    result.characterClassName = className
    result.characterClassFile = classFile
    result.realmName = realmName

    local state = self:RefreshSkinningRouteState(GetTime and GetTime() or 0)
    local zoneName = state.zoneName or getCurrentZoneName()
    local subZoneName = state.subZoneName or getCurrentSubZoneName()
    result.zoneContext = zoneName
    result.zoneName = zoneName
    result.subZoneContext = subZoneName
    result.subZoneName = subZoneName
    result.zoneRouting = subZoneName and "subzone_preferred" or "zone_fallback"

    result.passed = true
    result.reason = "route_skinning_committed"
    return result, false
end

function FWR:RouteSkinningLoot(sourceStage, quantity)
    local result, needsRetry = self:BuildSkinningRouteResult(sourceStage)
    if needsRetry then
        return result, true
    end

    if not result.passed then
        return result, false
    end

    local state = self:EnsureSkinningRouteState()
    if state.batchActive then
        state.batchExpiresAt = math.max(tonumber(state.batchExpiresAt) or 0, (GetTime and GetTime() or 0) + SKINNING_BATCH_EXTENSION_SECONDS)
    end

    if self.AddToDisplayBasket then
        self:AddToDisplayBasket(result, quantity)
    end


    return result, false
end
