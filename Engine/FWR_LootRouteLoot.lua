local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local GetItemInfoInstant = GetItemInfoInstant
local GetItemInfo = GetItemInfo

-- Integrated generic loot pipeline.
-- Reject gates live in source/reagent/trade. Classification from stage 4 down only tags the item.

local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local function normalizeInput(candidate)
    if type(candidate) == "table" and candidate.stage == "source_filter" then
        return candidate.itemInfo or candidate.itemLink or candidate.itemID, candidate
    end
    return candidate, nil
end

local function buildBaseResult(itemInfo)
    return {
        itemInfo = itemInfo,
        itemID = itemInfo and GetItemInfoInstant(itemInfo) or nil,
        itemLink = itemInfo and select(2, GetItemInfo(itemInfo)) or nil,
        passed = false,
        reason = "unresolved_item",
        stage = "st2_reagent_filter",
    }
end

function FWR:EvaluateCraftingReagent(candidate)
    local itemInfo, previousStage = normalizeInput(candidate)
    local result = buildBaseResult(itemInfo)
    result.previousStagePassed = previousStage and previousStage.passed or nil

    if previousStage and not previousStage.passed then
        result.reason = "blocked_by_previous_stage"
        return result
    end

    if not itemInfo then
        return result
    end

    local itemName, itemLink, itemRarity, _, _, itemType, itemSubType, _, _, _, _, classID, subclassID, bindType, expansionID, _, isCraftingReagent = GetItemInfo(itemInfo)

    result.itemName = itemName
    result.itemLink = itemLink or result.itemLink
    result.itemRarity = itemRarity
    result.itemQuality = nil or 0
    result.itemType = itemType
    result.itemSubType = itemSubType
    result.classID = classID
    result.subclassID = subclassID
    result.bindType = bindType
    result.expansionID = expansionID
    result.isCraftingReagent = isCraftingReagent and true or false
    result.sourceType = previousStage and previousStage.sourceType or nil

    if itemName == nil and itemLink == nil and classID == nil and isCraftingReagent == nil then
        result.reason = "item_info_not_ready"
        return result
    end

    if result.isCraftingReagent then
        result.passed = true
        result.reason = "crafting_reagent"
    else
        result.reason = "not_crafting_reagent"
    end

    return result
end

function FWR:EvaluateReagentFilter(candidate)
    return self:EvaluateCraftingReagent(candidate)
end

local ITEM_BIND_ON_ACQUIRE = (Enum and Enum.ItemBind and Enum.ItemBind.OnAcquire) or 1
local ITEM_BIND_TO_ACCOUNT = (Enum and Enum.ItemBind and Enum.ItemBind.ToWoWAccount) or 7
local ITEM_BIND_TO_BNET_ACCOUNT = (Enum and Enum.ItemBind and Enum.ItemBind.ToBnetAccount) or 8
local ITEM_BIND_TO_BNET_ACCOUNT_UNTIL_EQUIP = (Enum and Enum.ItemBind and Enum.ItemBind.ToBnetAccountUntilEquipped) or 9

local function normalizeInput(candidate)
    if type(candidate) == "table" and candidate.stage == "st2_reagent_filter" then
        return candidate.itemInfo or candidate.itemLink or candidate.itemID, candidate
    end
    return candidate, nil
end

local function isSoulboundBindType(bindType)
    return bindType == ITEM_BIND_ON_ACQUIRE
end

local function isWarbandBindType(bindType)
    return bindType == ITEM_BIND_TO_ACCOUNT
        or bindType == ITEM_BIND_TO_BNET_ACCOUNT
        or bindType == ITEM_BIND_TO_BNET_ACCOUNT_UNTIL_EQUIP
end

function FWR:EvaluateTradeEligibility(candidate)
    local itemInfo, previousStage = normalizeInput(candidate)
    local result = {
        itemInfo = itemInfo,
        itemID = itemInfo and GetItemInfoInstant(itemInfo) or nil,
        itemLink = itemInfo and select(2, GetItemInfo(itemInfo)) or nil,
        passed = false,
        reason = "unresolved_item",
        stage = "st3_trade_filter",
        previousStagePassed = previousStage and previousStage.passed or nil,
    }

    if previousStage and not previousStage.passed then
        result.reason = "blocked_by_previous_stage"
        return result
    end

    if not itemInfo then
        return result
    end

    local itemName, itemLink, itemRarity, _, _, itemType, itemSubType, _, _, _, _, classID, subclassID, bindType, expansionID, _, isCraftingReagent = GetItemInfo(itemInfo)

    result.itemName = itemName
    result.itemLink = itemLink or result.itemLink
    result.itemRarity = itemRarity
    result.itemQuality = nil or 0
    result.itemType = itemType
    result.itemSubType = itemSubType
    result.classID = classID
    result.subclassID = subclassID
    result.bindType = bindType
    result.expansionID = expansionID
    result.isCraftingReagent = isCraftingReagent and true or false
    result.sourceType = previousStage and previousStage.sourceType or nil
    result.isSoulboundType = isSoulboundBindType(bindType)
    result.isWarbandType = isWarbandBindType(bindType)

    if itemName == nil and itemLink == nil and classID == nil and bindType == nil then
        result.reason = "item_info_not_ready"
        return result
    end

    if not result.isCraftingReagent then
        result.reason = "not_crafting_reagent"
        return result
    end

    if result.isSoulboundType then
        result.reason = "rejected_soulbound"
        return result
    end

    if result.isWarbandType then
        result.reason = "rejected_warband"
        return result
    end

    result.passed = true
    result.reason = "trade_eligible"
    return result
end

function FWR:EvaluateTradeFilter(candidate)
    return self:EvaluateTradeEligibility(candidate)
end

local function normalizeText(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:lower()
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

    return normalizeText(table.concat(chunks, " "))
end

local EXACT_ITEM_TYPE_OVERRIDES = {
    ["plant protein"] = "Vegetable",
    ["plump provisions"] = "Vegetable",
    ["putrid mushroom spores"] = "Junk",
    ["light-infused leaves"] = "Junk",
    ["colorful leaves"] = "Junk",
    ["polished purple pebble"] = "Junk",
}

local ITEM_TYPE_RULES = {
    { itemType = "Card", tooltip = { "darkmoon card", "card" }, subtype = { "cards", "card" }, type = {} },
    { itemType = "Junk", tooltip = { "scrap", "scraps", "residue", "remnant", "broken piece", "worthless" }, subtype = { "junk" }, type = { "junk" } },
    { itemType = "Fish", tooltip = { " fish", "fish ", "common fish", "uncommon fish", "rare fish", "a fish", "fish in " }, subtype = { "fish" }, type = { "fish" } },
    { itemType = "Ore", tooltip = { "ore", "metal", "ingot", "mineral", "vein" }, subtype = { "ore", "metal & stone", "metal" }, type = { "metal & stone", "metal" } },
    { itemType = "Stone", tooltip = { "stone", "rock fragment" }, subtype = { "stone" }, type = { "stone" } },
    { itemType = "Elemental Reagent", tooltip = { "mote", "primal", "volatile", "eternal", "crystallized", "elemental" }, subtype = { "elemental", "elemental reagent" }, type = { "elemental", "elemental reagent" } },
    { itemType = "Herb", tooltip = { "herb", "flower", "bloom", "blossom", "petal", "root", "seed", "pollen" }, subtype = { "herb" }, type = { "herb" } },
    { itemType = "Leather", tooltip = { "leather", "hide" }, subtype = { "leather", "hide" }, type = { "leather", "hide" } },
    { itemType = "Scale", tooltip = { "scale", "carapace", "chitin" }, subtype = { "hide" }, type = { "hide" } },
    { itemType = "Cloth", tooltip = { "cloth", "linen", "silk", "weave" }, subtype = { "cloth" }, type = { "cloth" } },
    { itemType = "Bolt", tooltip = { "bolt", "spool", "thread" }, subtype = { "cloth" }, type = { "cloth" } },
    { itemType = "Vegetable", tooltip = { "vegetable", "vegetables", "vegetarian", "veggie", "plant protein", "provisions" }, subtype = { "vegetable" }, type = { "vegetable" } },
    { itemType = "Meat", tooltip = { "meat", "egg", "haunch", "rib", "fillet" }, subtype = { "meat", "cooking" }, type = { "meat", "cooking" } },
    { itemType = "Dust", tooltip = { "dust" }, subtype = { "enchanting" }, type = { "enchanting" } },
    { itemType = "Essence", tooltip = { "essence" }, subtype = { "enchanting" }, type = { "enchanting" } },
    { itemType = "Shard", tooltip = { "shard", "crystal" }, subtype = { "enchanting" }, type = { "enchanting" } },
    { itemType = "Pigment", tooltip = { "pigment" }, subtype = { "inscription", "pigment" }, type = { "inscription" } },
    { itemType = "Ink", tooltip = { "ink" }, subtype = { "inscription", "ink" }, type = { "inscription" } },
    { itemType = "Gem", tooltip = { "gem", "ruby", "emerald", "sapphire", "opal", "amber" }, subtype = { "gem", "jewel" }, type = { "gem", "jewel" } },
    { itemType = "Finishing Reagent", tooltip = { "finishing reagent", "finishing reagents" }, subtype = { "finishing reagent", "finishing reagents" }, type = {} },
    { itemType = "Crafting Reagent", tooltip = { "crafting reagent", "optional reagent" }, subtype = { "reagent" }, type = {} },
    { itemType = "Parts", tooltip = { "parts", "gear", "wire", "spring", "device", "explosive" }, subtype = { "parts", "devices", "explosives" }, type = { "parts", "devices", "explosives" } },
}

local function classifyItemType(candidate)
    local tooltipText = collectTooltipText(candidate.itemLink)
    local subtypeText = normalizeText(candidate.itemSubType)
    local typeText = normalizeText(candidate.itemType)
    local itemNameText = normalizeText(candidate.itemName)

    local exactOverride = itemNameText and EXACT_ITEM_TYPE_OVERRIDES[itemNameText] or nil
    if exactOverride then
        return exactOverride, "exact_item_name", tooltipText
    end

    for _, rule in ipairs(ITEM_TYPE_RULES) do
        if containsAny(tooltipText, rule.tooltip) then
            return rule.itemType, "tooltip_text", tooltipText
        end
    end
    for _, rule in ipairs(ITEM_TYPE_RULES) do
        if containsAny(subtypeText, rule.subtype) then
            return rule.itemType, "item_subtype", tooltipText
        end
    end
    for _, rule in ipairs(ITEM_TYPE_RULES) do
        if containsAny(typeText, rule.type) then
            return rule.itemType, "item_type", tooltipText
        end
    end

    if candidate.isCraftingReagent then
        return "Crafting Reagent", "crafting_reagent_flag", tooltipText
    end

    return "General", "general_fallback", tooltipText
end

function FWR:EvaluateItemTypeClassification(candidate)
    local result = {
        passed = false,
        stage = "st4_item_type_classification",
        reason = "unresolved_item",
        itemTypeContext = "General",
    }

    if type(candidate) ~= "table" then
        return result
    end

    for k, v in pairs(candidate) do
        result[k] = v
    end

    result.previousStagePassed = candidate.passed
    if not candidate.passed then
        result.reason = "blocked_by_previous_stage"
        return result
    end

    local itemTypeContext, source, tooltipText = classifyItemType(candidate)
    result.itemTypeContext = itemTypeContext
    result.itemTypeSource = source
    result.tooltipText = tooltipText
    result.reason = itemTypeContext == "General" and "general_item_type" or "item_type_classified"
    result.passed = true

    return result
end

local TOOLTIP_PROFESSION_HINTS = {
    { label = "Alchemy", keywords = { "alchemy", "alchemist" } },
    { label = "Blacksmithing", keywords = { "blacksmithing", "blacksmith" } },
    { label = "Cooking", keywords = { "cooking", "cook" } },
    { label = "Enchanting", keywords = { "enchanting", "enchanter" } },
    { label = "Engineering", keywords = { "engineering", "engineer" } },
    { label = "Herbalism", keywords = { "herbalism", "herbalist" } },
    { label = "Inscription", keywords = { "inscription", "scribe" } },
    { label = "Jewelcrafting", keywords = { "jewelcrafting", "jewelcrafter" } },
    { label = "Leatherworking", keywords = { "leatherworking", "leatherworker" } },
    { label = "Mining", keywords = { "mining", "miner" } },
    { label = "Skinning", keywords = { "skinning", "skinner" } },
    { label = "Tailoring", keywords = { "tailoring", "tailor" } },
}

local function inferProfessionFromTooltipText(tooltipText)
    if type(tooltipText) ~= "string" or tooltipText == "" then
        return nil, nil, false
    end

    local matches = {}
    local seen = {}
    for _, rule in ipairs(TOOLTIP_PROFESSION_HINTS) do
        for _, keyword in ipairs(rule.keywords) do
            if string.find(tooltipText, keyword, 1, true) then
                if not seen[rule.label] then
                    seen[rule.label] = true
                    table.insert(matches, rule.label)
                end
                break
            end
        end
    end

    if #matches == 0 then
        return nil, nil, false
    end

    if #matches == 1 then
        return matches[1], matches[1], false
    end

    return "Multiple", table.concat(matches, ", "), true
end

local ITEM_TYPE_TO_PROFESSION = {
    ["Fish"] = "Cooking",
    ["Vegetable"] = "Cooking",
    ["Meat"] = "Cooking",
    ["Cloth"] = "Tailoring",
    ["Bolt"] = "Tailoring",
    ["Leather"] = "Leatherworking",
    ["Scale"] = "Leatherworking",
    ["Dust"] = "Enchanting",
    ["Essence"] = "Enchanting",
    ["Shard"] = "Enchanting",
    ["Pigment"] = "Inscription",
    ["Ink"] = "Inscription",
    ["Card"] = "Inscription",
    ["Gem"] = "Jewelcrafting",
    ["Ore"] = "Mining",
    ["Stone"] = "Mining",
    ["Elemental Reagent"] = "General",
    ["Herb"] = "Herbalism",
    ["Parts"] = "Engineering",
    ["Finishing Reagent"] = "General",
    ["Crafting Reagent"] = "General",
    ["Junk"] = "",
}

function FWR:EvaluateProfessionClassification(candidate)
    local result = {
        passed = false,
        stage = "st5_profession_classification",
        reason = "unresolved_item",
        profession = "General",
    }

    if type(candidate) ~= "table" then
        return result
    end

    for k, v in pairs(candidate) do
        result[k] = v
    end

    result.previousStagePassed = candidate.passed
    if not candidate.passed then
        result.reason = "blocked_by_previous_stage"
        return result
    end

    local profession = ITEM_TYPE_TO_PROFESSION[candidate.itemTypeContext]
    if profession == nil then
        profession = "General"
    end
    local baseProfession = profession
    local source = (profession == "General" or profession == "") and "item_type_general" or "item_type_context"

    local tooltipProfession, tooltipBaseProfession = inferProfessionFromTooltipText(candidate.tooltipText)
    if (profession == "General" or profession == "") and tooltipProfession and tooltipProfession ~= "" then
        profession = tooltipProfession
        baseProfession = tooltipBaseProfession or tooltipProfession
        source = "tooltip_profession_hint"
    end

    local acquisitionContext = self.GetActiveAcquisitionContext and self:GetActiveAcquisitionContext() or nil
    if type(acquisitionContext) == "table" and type(acquisitionContext.professionContext) == "string" and acquisitionContext.professionContext ~= "" then
        profession = acquisitionContext.professionContext
        baseProfession = acquisitionContext.professionContext
        source = "acquisition_context"
    end

    result.baseProfession = baseProfession
    result.profession = profession
    result.classificationSource = source
    result.reason = (profession == "General" or profession == "") and "general_category" or "profession_classified"
    result.passed = true
    return result
end

local ITEM_TYPE_ACTIVITY = {
    Fish = "fishing",
    Herb = "herbalism",
    Ore = "mining",
    Stone = "mining",
    Leather = "skinning",
    Scale = "skinning",
}

local function titleCaseActivity(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    return value:sub(1, 1):upper() .. value:sub(2):lower()
end

function FWR:EvaluateActivityContext(candidate)
    local result = {
        passed = false,
        stage = "st6_activity_context",
        reason = "unresolved_item",
    }

    if type(candidate) ~= "table" then
        return result
    end

    for k, v in pairs(candidate) do
        result[k] = v
    end

    result.previousStagePassed = candidate.passed
    if not candidate.passed then
        result.reason = "blocked_by_previous_stage"
        return result
    end

    local acquisitionContext = self.GetActiveAcquisitionContext and self:GetActiveAcquisitionContext() or nil
    local activityKey = nil
    if type(acquisitionContext) == "table" and type(acquisitionContext.activityContext) == "string" and acquisitionContext.activityContext ~= "" then
        activityKey = acquisitionContext.activityContext:lower()
        result.activitySource = "acquisition_context"
    elseif type(candidate.itemTypeContext) == "string" and ITEM_TYPE_ACTIVITY[candidate.itemTypeContext] and candidate.sourceType == "world" then
        activityKey = ITEM_TYPE_ACTIVITY[candidate.itemTypeContext]
        result.activitySource = "item_type_context"
    elseif candidate.sourceType == "world" then
        activityKey = "drop"
        result.activitySource = "source_filter"
    else
        activityKey = candidate.sourceType or "unknown"
        if activityKey == "combat" then
            activityKey = "loot"
        end
        result.activitySource = "source_filter"
    end

    result.activityKey = activityKey
    result.activityContext = titleCaseActivity(activityKey) or "Unknown"
    result.reason = "activity_context_applied"
    result.passed = true
    return result
end

local function getCurrentExpansionID()
    if type(GetExpansionLevel) == "function" then
        local value = tonumber(GetExpansionLevel())
        if value ~= nil then
            return value
        end
    end

    if _G and _G.Enum and _G.Enum.ExpansionLevel then
        local enumCurrent = tonumber(_G.Enum.ExpansionLevel.CurrentExpansion)
        if enumCurrent ~= nil then
            return enumCurrent
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

local EXPANSION_NAME_FALLBACKS = {
    [0] = "Classic",
    [1] = "The Burning Crusade",
    [2] = "Wrath of the Lich King",
    [3] = "Cataclysm",
    [4] = "Mists of Pandaria",
    [5] = "Warlords of Draenor",
    [6] = "Legion",
    [7] = "Battle for Azeroth",
    [8] = "Shadowlands",
    [9] = "Dragonflight",
    [10] = "The War Within",
    [11] = "Midnight",
    [12] = "The Last Titan",
}

local function getExpansionName(expansionID)
    expansionID = tonumber(expansionID)
    if expansionID == nil then
        return nil
    end

    local globalName = _G and _G["EXPANSION_NAME" .. tostring(expansionID)]
    if type(globalName) == "string" and globalName ~= "" then
        return globalName
    end

    local fallbackName = EXPANSION_NAME_FALLBACKS[expansionID]
    if type(fallbackName) == "string" and fallbackName ~= "" then
        return fallbackName
    end

    return string.format("Expansion %d", expansionID)
end

function FWR:EvaluateExpansionClassification(candidate)
    local result = {
        passed = false,
        stage = "st7_expansion_classification",
        reason = "unresolved_item",
    }

    if type(candidate) ~= "table" then
        return result
    end

    for k, v in pairs(candidate) do
        result[k] = v
    end

    result.previousStagePassed = candidate.passed

    if not candidate.passed then
        result.reason = "blocked_by_previous_stage"
        return result
    end

    local expansionID = tonumber(candidate.expansionID)
    if expansionID == nil and candidate.itemInfo then
        local _, _, _, _, _, _, _, _, _, _, _, _, _, _, itemExpansionID = GetItemInfo(candidate.itemInfo)
        expansionID = tonumber(itemExpansionID)
    end

    local currentExpansionID = getCurrentExpansionID()
    local expansionCategory = "unknown"
    if expansionID ~= nil and currentExpansionID ~= nil then
        expansionCategory = expansionID >= currentExpansionID and "current" or "old"
    elseif expansionID ~= nil then
        expansionCategory = "known"
    elseif currentExpansionID ~= nil then
        expansionID = currentExpansionID
        expansionCategory = "current"
    end

    result.expansionID = expansionID
    result.expansionName = getExpansionName(expansionID)
    if (result.expansionName == nil or result.expansionName == "") and expansionCategory == "current" then
        result.expansionName = getExpansionName(currentExpansionID)
    end
    result.currentExpansionID = currentExpansionID
    result.expansionCategory = expansionCategory
    result.passed = true
    result.reason = expansionCategory == "old" and "old_expansion_classified" or "expansion_classified"
    return result
end

function FWR:IsOldExpansionVisible()
    local displayFilters = self.GetDisplayFilterSettings and self:GetDisplayFilterSettings() or nil
    if type(displayFilters) ~= "table" then
        self:EnsureDatabases()
        displayFilters = self.Settings.displayFilters or {}
        self.Settings.displayFilters = displayFilters
    end
    return displayFilters.showOldExpansions and true or false
end

function FWR:SetOldExpansionVisible(isVisible)
    local displayFilters = self.GetDisplayFilterSettings and self:GetDisplayFilterSettings() or nil
    if type(displayFilters) ~= "table" then
        self:EnsureDatabases()
        displayFilters = self.Settings.displayFilters or {}
        self.Settings.displayFilters = displayFilters
    end
    displayFilters.showOldExpansions = isVisible and true or false
    if self.TouchDatabase then
        self:TouchDatabase()
    end
end

local function normalizeZoneText(value)
    if type(value) ~= "string" then
        return nil
    end

    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end

    return value
end

local function getCurrentZoneContext()
    local realZone = normalizeZoneText(type(GetRealZoneText) == "function" and GetRealZoneText() or nil)
    local zone = normalizeZoneText(type(GetZoneText) == "function" and GetZoneText() or nil)
    local subZone = normalizeZoneText(FWR:GetAreaSubZoneText())

    local resolvedZone = realZone or zone
    if resolvedZone == nil and subZone ~= nil then
        resolvedZone = subZone
    end

    if subZone == resolvedZone then
        subZone = nil
    end

    return resolvedZone, subZone
end

function FWR:EvaluateZoneContext(candidate)
    local result = {
        passed = false,
        stage = "st8_zone_context",
        reason = "unresolved_item",
    }

    if type(candidate) ~= "table" then
        return result
    end

    for k, v in pairs(candidate) do
        result[k] = v
    end

    result.previousStagePassed = candidate.passed

    if not candidate.passed then
        result.reason = "blocked_by_previous_stage"
        return result
    end

    local zoneName, subZoneName = getCurrentZoneContext()
    result.zoneContext = zoneName
    result.zoneName = zoneName
    result.subZoneContext = subZoneName
    result.subZoneName = subZoneName
    result.passed = true
    result.reason = (zoneName or subZoneName) and "zone_context_applied" or "zone_context_unavailable"
    return result
end

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

local function getPlayerCharacterContext()
    local fullName = nil
    local realmName = nil
    if type(UnitFullName) == "function" then
        local name, realm = UnitFullName("player")
        fullName = normalizeText(name)
        realmName = normalizeText(realm)
    end

    if fullName == nil and type(GetUnitName) == "function" then
        fullName = normalizeText(GetUnitName("player", false))
    end

    if fullName == nil and type(UnitName) == "function" then
        local name, realm = UnitName("player")
        fullName = normalizeText(name)
        realmName = realmName or normalizeText(realm)
    end

    local className = nil
    local classFile = nil
    if type(UnitClass) == "function" then
        className, classFile = UnitClass("player")
        className = normalizeText(className)
        classFile = normalizeText(classFile)
    end

    return fullName, className, classFile, realmName
end

function FWR:EvaluateCharacterContext(candidate)
    local result = {
        passed = false,
        stage = "st9_character_context",
        reason = "unresolved_item",
    }

    if type(candidate) ~= "table" then
        return result
    end

    for k, v in pairs(candidate) do
        result[k] = v
    end

    result.previousStagePassed = candidate.passed

    if not candidate.passed then
        result.reason = "blocked_by_previous_stage"
        return result
    end

    local characterName, className, classFile, realmName = getPlayerCharacterContext()
    result.characterContext = characterName
    result.characterName = characterName
    result.characterKey = self.BuildCharacterKey and self:BuildCharacterKey(characterName, realmName) or characterName
    result.characterClassName = className
    result.characterClassFile = classFile
    result.realmName = realmName
    result.passed = true
    result.reason = characterName and "character_context_applied" or "character_context_unavailable"
    return result
end

local function copyLootRouteFields(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return target
    end
    for key, value in pairs(source) do
        if key ~= "stage" and key ~= "previousStagePassed" then
            target[key] = value
        end
    end
    target.stage = "rt_loot_route"
    return target
end

local function buildLootRouteBase(sourceStage)
    local itemInfo = sourceStage and (sourceStage.itemInfo or sourceStage.itemLink or sourceStage.itemID) or nil
    return {
        itemInfo = itemInfo,
        itemID = itemInfo and GetItemInfoInstant(itemInfo) or nil,
        itemLink = itemInfo and select(2, GetItemInfo(itemInfo)) or nil,
        itemName = itemInfo and GetItemInfo(itemInfo) or nil,
        passed = false,
        reason = "unresolved_item",
        stage = "rt_loot_route",
        sourceType = sourceStage and sourceStage.sourceType or nil,
        triggerSource = sourceStage and sourceStage.sourceType or nil,
        routeName = "loot",
        contextKey = sourceStage and sourceStage.contextKey or nil,
    }
end

local function isBlockingGenericLootStageFailure(index, stageResult)
    if type(stageResult) ~= "table" then
        return true
    end
    if stageResult.reason == "item_info_not_ready" then
        return true
    end
    if index <= 2 then
        return not stageResult.passed
    end
    return false
end

function FWR:BuildIntegratedLootRouteResult(sourceStage)
    local result = buildLootRouteBase(sourceStage)
    if type(sourceStage) ~= "table" or not sourceStage.passed then
        result.reason = "blocked_by_source_filter"
        return result, false
    end

    if not result.itemInfo then
        result.reason = "missing_item"
        return result, false
    end

    local current = sourceStage
    local stages = {
        { fn = self.EvaluateReagentFilter, retry = true },
        { fn = self.EvaluateTradeFilter, retry = true },
        { fn = self.EvaluateItemTypeClassification, retry = false },
        { fn = self.EvaluateProfessionClassification, retry = false },
        { fn = self.EvaluateActivityContext, retry = false },
        { fn = self.EvaluateExpansionClassification, retry = false },
        { fn = self.EvaluateZoneContext, retry = false },
        { fn = self.EvaluateCharacterContext, retry = false },
    }

    for index, stage in ipairs(stages) do
        local stageResult = stage.fn and stage.fn(self, current) or current
        copyLootRouteFields(result, stageResult)
        current = stageResult
        if type(stageResult) == "table" and stageResult.reason == "item_info_not_ready" and stage.retry then
            result.reason = "item_info_not_ready"
            return result, true
        end
        if isBlockingGenericLootStageFailure(index, stageResult) then
            result.reason = type(stageResult) == "table" and stageResult.reason or "stage_failed"
            return result, false
        end
    end

    result.classification = result.itemTypeContext
    result.triggerSource = sourceStage.sourceType or result.triggerSource
    result.routeName = "loot"
    result.passed = true
    result.reason = "route_loot_committed"
    return result, false
end

function FWR:RouteGenericLoot(sourceStage, quantity)
    local result, needsRetry = self:BuildIntegratedLootRouteResult(sourceStage)
    if needsRetry then
        return result, true
    end

    if not result.passed then
        return result, false
    end

    if self.AddToDisplayBasket then
        self:AddToDisplayBasket(result, quantity)
    end


    return result, false
end
