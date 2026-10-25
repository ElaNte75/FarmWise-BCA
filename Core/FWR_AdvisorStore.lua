local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local GetItemInfoInstant = GetItemInfoInstant
local GetItemInfo = GetItemInfo

-- Advisor store.
-- Keeps farming statistics in the original FarmWise data format (FarmWiseDB) so that
-- statistics collected by older FarmWise versions keep working without any conversion.
--
--   FarmWiseDB["Zone - SubZone"] = {
--       items = { ["itemID|Qn"] = { id, name, count, quality, itemQuality, exp, prof } },
--       gold = copper looted, vendor = copper of scrap (poor quality) vendor value looted, time = seconds,
--       daily = { date, items = { key = count }, gold, vendor, time },
--       zone = "Zone", subzone = "SubZone",   -- added by this version, absent in old entries
--   }
--   FarmWiseDB._ah       = Auction House price snapshot (same shape as before)
--   FarmWiseDB._settings = old FarmWise settings (left untouched)
--   FarmWiseDB._advisor  = Advisor preferences (this version)
--
-- Every key starting with "_" is metadata and is never treated as a zone.
-- Results are always per zone + sub-zone: the Advisor says exactly where to go.

-- A result needs this much farming time in one place before it is shown, and the time
-- decides how sure FarmWise is about it.
FWR.ADVISOR_MIN_SECONDS = 15 * 60
local CONFIDENCE_HIGH_SECONDS = 60 * 60

-- The Auction House keeps 5% of every sale.
local AUCTION_HOUSE_CUT = 0.05
FWR.AUCTION_HOUSE_CUT = AUCTION_HOUSE_CUT   -- the main window's session gold uses the same cut

local DEFAULT_ADVISOR_SETTINGS = {
    currentExpansionOnly = true,   -- ignore items older than the current expansion
    includeQuality = true,         -- item mode: each quality on its own line (false adds the qualities up)
}

-- Profession skill line IDs.
local SKILL_TAILORING = 197
local SKILL_SKINNING = 393
local SKILL_MINING = 186
local SKILL_HERBALISM = 182
local SKILL_FISHING = 356

local PROFESSION_KEYS = {
    herbalism = SKILL_HERBALISM,
    mining = SKILL_MINING,
    skinning = SKILL_SKINNING,
    tailoring = SKILL_TAILORING,
    fishing = SKILL_FISHING,
}

local PROFESSION_NAMES = {
    [SKILL_TAILORING] = "Tailoring",
    [SKILL_SKINNING] = "Skinning",
    [SKILL_MINING] = "Mining",
    [SKILL_HERBALISM] = "Herbalism",
    [SKILL_FISHING] = "Fishing",
}

-- Trade goods (item class 7) subclass -> professions that can obtain it.
local SUBCLASS_PROFESSIONS = {
    [5] = { SKILL_TAILORING },                        -- Cloth
    [6] = { SKILL_SKINNING },                         -- Leather
    [7] = { SKILL_MINING },                           -- Metal & Stone
    [8] = { SKILL_FISHING, SKILL_SKINNING },          -- Cooking (fish and meat)
    [9] = { SKILL_HERBALISM },                        -- Herb
}

local todayKeyCache = nil
local todayKeyCheckedAt = 0

local function getTodayKey()
    local now = time()
    if not todayKeyCache or now - todayKeyCheckedAt >= 30 then
        todayKeyCache = date("%Y-%m-%d")
        todayKeyCheckedAt = now
    end
    return todayKeyCache
end

local function isMetaKey(key)
    return type(key) == "string" and key:sub(1, 1) == "_"
end

local function buildZoneKey(zone, subzone)
    if subzone and subzone ~= "" and subzone ~= zone then
        return zone .. " - " .. subzone
    end
    return zone
end

local function getLiveZone()
    local zone = type(GetZoneText) == "function" and GetZoneText() or ""
    local subzone = FWR:GetAreaSubZoneText()
    if zone == nil or zone == "" then
        zone = "Unknown"
    end
    return zone, subzone or ""
end

function FWR:EnsureAdvisorStore()
    if type(FarmWiseDB) ~= "table" then
        FarmWiseDB = {}
    end

    local settings = FarmWiseDB._advisor
    if type(settings) ~= "table" then
        settings = {}
        FarmWiseDB._advisor = settings
    end

    for key, value in pairs(DEFAULT_ADVISOR_SETTINGS) do
        if settings[key] == nil then
            settings[key] = value
        end
    end

    -- options and data of earlier builds that no longer exist
    settings.aggregate = nil
    settings.professionFilter = nil
    FarmWiseDB._guideIds = nil

    return FarmWiseDB, settings
end

function FWR:GetAdvisorSettings()
    local _, settings = self:EnsureAdvisorStore()
    return settings
end

local function ensureZoneData(zoneKey, zone, subzone)
    local db = FWR:EnsureAdvisorStore()
    local data = db[zoneKey]
    if type(data) ~= "table" then
        data = {}
        db[zoneKey] = data
    end

    data.items = data.items or {}
    data.gold = tonumber(data.gold) or 0
    data.vendor = tonumber(data.vendor) or 0
    data.time = tonumber(data.time) or 0
    data.daily = data.daily or {}
    if data.daily.date ~= getTodayKey() then
        data.daily = { date = getTodayKey(), items = {}, gold = 0, vendor = 0, time = 0 }
    end
    data.daily.items = data.daily.items or {}
    data.daily.gold = tonumber(data.daily.gold) or 0
    data.daily.vendor = tonumber(data.daily.vendor) or 0
    data.daily.time = tonumber(data.daily.time) or 0

    if zone and not data.zone then
        data.zone = zone
        data.subzone = subzone or ""
    end

    return data
end

function FWR:GetAdvisorStatus()
    local db = self:EnsureAdvisorStore()
    local zones, items = 0, 0
    local seen = {}
    for key, data in pairs(db) do
        if not isMetaKey(key) and type(data) == "table" and type(data.items) == "table" then
            zones = zones + 1
            for _, info in pairs(data.items) do
                if info.id and not seen[info.id] then
                    seen[info.id] = true
                    items = items + 1
                end
            end
        end
    end
    return { zones = zones, items = items }
end

-- Erases every zone entry and the processing statistics. Advisor preferences, old settings and the AH
-- price snapshot stay.
function FWR:ClearAdvisorData()
    local db, settings = self:EnsureAdvisorStore()
    settings.processing = nil
    for key in pairs(db) do
        if not isMetaKey(key) then
            db[key] = nil
        end
    end
end

------------------------------------------------------------
-- Processing (disenchant, milling, prospecting)
-- What these give is not tied to a place or to time: what counts is how much one use gives. So the
-- uses and the results are kept per process, separately from the places.
--   _advisor.processing[key] = { uses = n, items = { ["id|Qn"] = { id, name, quality, count, exp } } }
------------------------------------------------------------

local PROCESS_LABELS = { disenchant = "Disenchant", milling = "Milling", prospecting = "Prospecting" }

local function getProcess(key, create)
    local _, settings = FWR:EnsureAdvisorStore()
    if type(settings.processing) ~= "table" then
        if not create then
            return nil
        end
        settings.processing = {}
    end

    local process = settings.processing[key]
    if type(process) ~= "table" then
        if not create then
            return nil
        end
        process = { uses = 0, items = {} }
        settings.processing[key] = process
    end
    process.uses = tonumber(process.uses) or 0
    process.items = type(process.items) == "table" and process.items or {}
    return process
end

function FWR:RecordAdvisorProcessingUse(key)
    if not PROCESS_LABELS[key] then
        return
    end
    local process = getProcess(key, true)
    process.uses = process.uses + 1
end

-- Item IDs that have been seen as the result of a processing: they are not "farmed" in a place.
local function processingResultIds()
    local _, settings = FWR:EnsureAdvisorStore()
    local ids = {}
    for _, process in pairs(type(settings.processing) == "table" and settings.processing or {}) do
        for _, info in pairs(type(process) == "table" and process.items or {}) do
            if info.id then
                ids[tonumber(info.id)] = true
            end
        end
    end
    return ids
end

-- Called for every loot entry that passed the Reforged filters.
function FWR:RecordAdvisorItem(entry, quantity)
    if type(entry) ~= "table" then
        return
    end

    local itemID = tonumber(entry.itemID)
    if not itemID then
        return
    end

    local amount = tonumber(quantity) or 1
    if amount < 1 then
        amount = 1
    end

    local zone, subzone = getLiveZone()
    local data = ensureZoneData(buildZoneKey(zone, subzone), zone, subzone)

    local tier = tonumber(entry.itemQuality)
    local label = "Q" .. ((tier and tier > 0) and tier or 1)
    local key = itemID .. "|" .. label

    local info = data.items[key]
    if not info then
        info = {
            id = itemID,
            name = entry.itemName,
            count = 0,
            quality = label,
            itemQuality = entry.itemRarity,
        }
        data.items[key] = info
    end

    info.name = entry.itemName or info.name
    info.exp = tonumber(entry.expansionID) or info.exp
    info.prof = entry.baseProfession or info.prof
    info.count = (tonumber(info.count) or 0) + amount
    data.daily.items[key] = (data.daily.items[key] or 0) + amount

    -- the result of a disenchant, milling or prospecting is also counted per process
    if entry.activityKey == "processing" and self.GetActiveProcessingKey then
        local processKey = self:GetActiveProcessingKey()
        if processKey then
            local process = getProcess(processKey, true)
            local result = process.items[key]
            if not result then
                result = { id = itemID, name = entry.itemName, count = 0, quality = label }
                process.items[key] = result
            end
            result.name = entry.itemName or result.name
            result.exp = tonumber(entry.expansionID) or result.exp
            result.count = (tonumber(result.count) or 0) + amount
        end
    end
end

-- Called with the number of seconds of active farming time.
function FWR:RecordAdvisorTime(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then
        return
    end

    local zone, subzone = getLiveZone()
    local data = ensureZoneData(buildZoneKey(zone, subzone), zone, subzone)
    data.time = data.time + seconds
    data.daily.time = data.daily.time + seconds
end

function FWR:RecordAdvisorGold(copper)
    copper = tonumber(copper) or 0
    if copper <= 0 then
        return
    end

    local zone, subzone = getLiveZone()
    local data = ensureZoneData(buildZoneKey(zone, subzone), zone, subzone)
    data.gold = data.gold + copper
    data.daily.gold = data.daily.gold + copper
end

-- Vendor value of looted scrap (poor quality items). The zone is the one the item
-- was looted in, which can differ from the live one when item data arrives late.
function FWR:RecordAdvisorVendor(copper, zone, subzone)
    copper = tonumber(copper) or 0
    if copper <= 0 then
        return
    end

    if not zone or zone == "" then
        zone, subzone = getLiveZone()
    end
    local data = ensureZoneData(buildZoneKey(zone, subzone or ""), zone, subzone or "")
    data.vendor = data.vendor + copper
    data.daily.vendor = data.daily.vendor + copper
end

------------------------------------------------------------
-- Item classification helpers
------------------------------------------------------------

-- The content expansion of the game right now (not the expansions the account owns).
local function getCurrentExpansion()
    if type(GetServerExpansionLevel) == "function" then
        return tonumber(GetServerExpansionLevel())
    end
    if type(GetExpansionLevel) == "function" then
        return tonumber(GetExpansionLevel())
    end
    return nil
end

-- Item data is asked for once per item and session; asking again only repeats the answer.
local requestedItemData = {}

local function requestItemData(itemID)
    if not requestedItemData[itemID] and nil then
        requestedItemData[itemID] = true
        RequestLoadItemDataByID(itemID)
    end
end

local function resolveItemExpansion(info)
    if info.exp ~= nil then
        return info.exp
    end

    local itemID = tonumber(info.id)
    if not itemID then
        return nil
    end

    local expansion = select(15, GetItemInfo(itemID))
    if expansion == nil then
        requestItemData(itemID)
        return nil
    end

    info.exp = expansion
    return expansion
end

local function getKnownProfessionSkillLines()
    local known = {}
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
        return nil
    end

    local indexes = { GetProfessions() }
    for slot = 1, 6 do
        local index = indexes[slot]
        if index then
            local skillLine = select(7, GetProfessionInfo(index))
            if skillLine then
                known[skillLine] = true
            end
        end
    end
    return known
end

local function professionsForItem(itemID)
    if not itemID or type(GetItemInfoInstant) ~= "function" then
        return nil
    end

    local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    if classID ~= 7 then
        return nil
    end
    return SUBCLASS_PROFESSIONS[subClassID]
end

local function characterCanObtain(itemID, known)
    local professions = professionsForItem(itemID)
    if not professions or not known then
        return true -- elementals, enchanting and other categories, or professions unknown
    end

    for _, skillLine in ipairs(professions) do
        if known[skillLine] then
            return true
        end
    end
    return false
end

-- Text explaining why this character cannot obtain the item, or nil when it can.
function FWR:GetAdvisorItemRestriction(itemID)
    local known = getKnownProfessionSkillLines()
    if characterCanObtain(itemID, known) then
        return nil
    end

    local names = {}
    for _, skillLine in ipairs(professionsForItem(itemID)) do
        names[#names + 1] = PROFESSION_NAMES[skillLine]
    end
    return "This character cannot gather this item (needs " .. table.concat(names, " or ") .. ")."
end

-- Confidence of a result from the farming time behind it.
-- Returns label, r, g, b.
function FWR:GetAdvisorConfidence(seconds)
    seconds = tonumber(seconds) or 0
    if seconds >= CONFIDENCE_HIGH_SECONDS then
        return "High", 0.3, 1, 0.3
    end
    return "Low", 1, 0.85, 0.2
end

------------------------------------------------------------
-- Queries
------------------------------------------------------------

-- Groups all stored data per zone + sub-zone.
-- explicitItemID bypasses the expansion/profession filters for a specific item search.
local function buildGroups(explicitItemID, leaveOutProcessing)
    local db, settings = FWR:EnsureAdvisorStore()
    local currentExpansion = getCurrentExpansion()
    local known = getKnownProfessionSkillLines()
    local processed = leaveOutProcessing and processingResultIds() or {}
    local groups = {}

    for key, data in pairs(db) do
        if not isMetaKey(key) and type(data) == "table" and type(data.items) == "table" then
            local group = { name = key, time = 0, gold = 0, vendor = 0, items = {} }
            groups[key] = group

            group.time = tonumber(data.time) or 0
            group.gold = tonumber(data.gold) or 0
            group.vendor = tonumber(data.vendor) or 0

            for itemKey, info in pairs(data.items) do
                local include = not processed[tonumber(info.id)]
                if include and not explicitItemID then
                    if settings.currentExpansionOnly and currentExpansion then
                        local expansion = resolveItemExpansion(info)
                        include = expansion ~= nil and expansion >= currentExpansion
                    end
                    if include then
                        include = characterCanObtain(tonumber(info.id), known)
                    end
                end

                if include then
                    group.items[itemKey] = { id = info.id, name = info.name, quality = info.quality, count = tonumber(info.count) or 0 }
                end
            end
        end
    end

    return groups
end

local function sortResults(results, valueField)
    table.sort(results, function(a, b)
        if a[valueField] == b[valueField] then
            return a.zone < b.zone
        end
        return a[valueField] > b[valueField]
    end)
    return results
end

local function cleanQueryText(text)
    local plain = tostring(text or "")
    plain = plain:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    plain = plain:gsub("|Hitem:.-|h(.-)|h", "%1")
    plain = plain:gsub("|h", ""):gsub("|A:.-|a", "")
    plain = plain:gsub("^%s*%[+", ""):gsub("%]+%s*$", "")
    plain = plain:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return plain
end

local function normalizeName(name)
    name = cleanQueryText(name)
    name = name:gsub("%s*%([Qq]%d+%)$", "")
    name = name:gsub("%s+[Qq]uality%s*%d+$", "")
    name = name:gsub("%s+[Qq]%d+$", "")
    return string.lower(name)
end

-- Returns itemID (may be nil), normalized name, quality label (may be nil).
function FWR:ParseAdvisorQuery(queryText)
    local raw = tostring(queryText or "")
    local itemID = tonumber(raw:match("item:(%d+)"))
    local plain = cleanQueryText(raw)

    local quality = plain:match("%(([Qq]%d+)%)$") or plain:match("%s([Qq]%d+)$")
    if quality then
        quality = string.upper(quality)
    end

    local name = normalizeName(plain)
    if itemID and type(GetItemInfo) == "function" then
        local resolved = GetItemInfo(itemID)
        if resolved then
            name = normalizeName(resolved)
        end
    end

    return itemID, name, quality
end

-- First stored item ID that matches a typed name.
local function findStoredItemID(groups, name)
    for _, group in pairs(groups) do
        for _, info in pairs(group.items) do
            if normalizeName(info.name) == name then
                return tonumber(info.id)
            end
        end
    end
    return nil
end

-- exactItemID / exactQuality come from a dropped or shift-clicked item and take priority over
-- whatever can be parsed from the typed text. includeQuality == false ignores every quality.
-- Returns the result list; when this character could never gather the item, a text saying why;
-- and, when no place has enough time yet, the best place so far ({ zone, seconds }).
function FWR:BuildAdvisorItemResults(queryText, exactItemID, exactQuality, includeQuality)
    local itemID, name, quality = self:ParseAdvisorQuery(queryText)
    itemID = exactItemID or itemID
    quality = exactQuality or quality
    if includeQuality == false then
        quality = nil
    end
    if not itemID and (not name or name == "") then
        return {}
    end

    local groups = buildGroups(true, true)

    local restriction = self:GetAdvisorItemRestriction(itemID or findStoredItemID(groups, name))
    if restriction then
        return {}, restriction
    end

    local results = {}
    local partial = nil
    for _, group in pairs(groups) do
        if group.time >= self.ADVISOR_MIN_SECONDS then
            local count = 0
            local value = 0
            local matchedIds, matchedIdCount = {}, 0
            local matchedName = nil
            for _, info in pairs(group.items) do
                local matches
                if itemID then
                    matches = tonumber(info.id) == itemID
                else
                    matches = normalizeName(info.name) == name
                end
                if matches and quality then
                    matches = string.upper(info.quality or "") == quality
                end
                if matches then
                    count = count + info.count
                    matchedName = info.name
                    if not matchedIds[info.id] then
                        matchedIds[info.id] = true
                        matchedIdCount = matchedIdCount + 1
                    end
                    local price = self:GetAuctionPrice(info.id, true)
                    if price then
                        value = value + price * info.count
                    end
                end
            end

            if count > 0 then
                local label, r, g, b = self:GetAdvisorConfidence(group.time)
                results[#results + 1] = {
                    zone = group.name,
                    totalTime = group.time,
                    count = count,
                    perHour = math.floor((count / group.time) * 3600),
                    valuePerHour = value > 0 and (value / group.time * 3600) or nil,
                    unitPrice = value > 0 and (value / count) or nil,
                    averaged = matchedIdCount > 1,
                    itemName = matchedName,
                    confidence = label,
                    confidenceColor = { r, g, b },
                }
            end
        elseif group.time > 0 then
            for _, info in pairs(group.items) do
                local matches
                if itemID then
                    matches = tonumber(info.id) == itemID
                else
                    matches = normalizeName(info.name) == name
                end
                if matches and info.count > 0 and (not partial or group.time > partial.seconds) then
                    partial = { zone = group.name, seconds = group.time }
                end
            end
        end
    end

    if #results == 0 then
        return {}, nil, partial
    end
    return sortResults(results, "perHour")
end

-- Estimated gold per hour per place: looted gold + vendor value of scrap + Auction House
-- value of the materials (after the Auction House cut).
function FWR:BuildAdvisorGoldResults()
    local ahStore = FarmWiseDB and FarmWiseDB._ah
    local prices = type(ahStore) == "table" and ahStore.items or {}
    local results = {}

    for _, group in pairs(buildGroups(false)) do
        if group.time >= self.ADVISOR_MIN_SECONDS then
            local materialsCopper = 0
            for _, info in pairs(group.items) do
                local record = prices[tostring(info.id)]
                local unitPrice = record and tonumber(record.unitPrice or record.price)
                if unitPrice and unitPrice > 0 and info.count > 0 then
                    materialsCopper = materialsCopper + unitPrice * info.count * (1 - AUCTION_HOUSE_CUT)
                end
            end

            local totalCopper = group.gold + group.vendor + materialsCopper
            if totalCopper > 0 then
                local perHour = 3600 / group.time
                local label, r, g, b = self:GetAdvisorConfidence(group.time)
                results[#results + 1] = {
                    zone = group.name,
                    totalTime = group.time,
                    goldPerHour = math.floor(totalCopper * perHour),
                    rawPerHour = math.floor(group.gold * perHour),
                    vendorPerHour = math.floor(group.vendor * perHour),
                    materialsPerHour = math.floor(materialsCopper * perHour),
                    confidence = label,
                    confidenceColor = { r, g, b },
                }
            end
        end
    end

    return sortResults(results, "goldPerHour")
end

-- Best place for every item this character farms, ranked by quantity per hour (not by value).
-- includeQuality == false adds up every quality of an item.
function FWR:BuildAdvisorItemOverview(includeQuality)
    local best = {}

    for _, group in pairs(buildGroups(false, true)) do
        if group.time >= self.ADVISOR_MIN_SECONDS then
            local perItem = {}
            for _, info in pairs(group.items) do
                -- every quality of an item has its own item ID: without "Include quality" they share a name, so
                -- they are added up under it (each quality worth its own price)
                local key = includeQuality and (tostring(info.id) .. "|" .. tostring(info.quality)) or (normalizeName(info.name) or tostring(info.id))
                local entry = perItem[key]
                if not entry then
                    entry = { name = info.name, quality = includeQuality and info.quality or nil, count = 0, value = 0, ids = {}, idCount = 0 }
                    perItem[key] = entry
                end
                entry.count = entry.count + info.count
                if not entry.ids[info.id] then
                    entry.ids[info.id] = true
                    entry.idCount = entry.idCount + 1
                end
                local price = self:GetAuctionPrice(info.id, true)
                if price then
                    entry.value = entry.value + price * info.count
                end
            end

            for key, entry in pairs(perItem) do
                if entry.count > 0 then
                    local perHour = math.floor((entry.count / group.time) * 3600)
                    local current = best[key]
                    if not current or perHour > current.perHour then
                        local label, r, g, b = self:GetAdvisorConfidence(group.time)
                        best[key] = {
                            itemName = entry.name,
                            quality = entry.quality,
                            zone = group.name,
                            totalTime = group.time,
                            count = entry.count,
                            perHour = perHour,
                            valuePerHour = entry.value > 0 and (entry.value / group.time * 3600) or nil,
                            unitPrice = entry.value > 0 and (entry.value / entry.count) or nil,
                            averaged = entry.idCount > 1,
                            confidence = label,
                            confidenceColor = { r, g, b },
                        }
                    end
                end
            end
        end
    end

    local list = {}
    for _, entry in pairs(best) do
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b)
        if a.perHour == b.perHour then
            return tostring(a.itemName) < tostring(b.itemName)
        end
        return a.perHour > b.perHour
    end)
    return list
end

-- Auction House price of each guide material (best price among its quality ranks), found by item ID.
local function buildPriceByName()
    local ahStore = FarmWiseDB and FarmWiseDB._ah
    local prices = type(ahStore) == "table" and ahStore.items or {}
    local guide = FWR.STARTER_GUIDE
    local byName = {}

    for name, idList in pairs(guide and guide.itemIds or {}) do
        for _, itemID in ipairs(idList) do
            local record = prices[tostring(itemID)]
            local unitPrice = record and tonumber(record.unitPrice or record.price)
            if unitPrice and (not byName[name] or unitPrice > byName[name]) then
                byName[name] = unitPrice
            end
        end
    end
    return byName
end

-- Starter guide suggestions for this character: combinations of its professions first, then single
-- professions, then what anyone can farm. Data lives in Data/FWR_StarterGuideData.lua.
-- Returns a list of { title, place, materials = { { name, price } }, note, professions }.
function FWR:GetStarterGuideEntries()
    local guide = self.STARTER_GUIDE
    if type(guide) ~= "table" or type(guide.entries) ~= "table" then
        return {}
    end

    local known = getKnownProfessionSkillLines() or {}
    local priceByName = buildPriceByName()
    local list = {}

    for index, entry in ipairs(guide.entries) do
        local required = entry.requires or {}
        local available = true
        local names = {}
        for _, key in ipairs(required) do
            if not known[PROFESSION_KEYS[key]] then
                available = false
                break
            end
            names[#names + 1] = PROFESSION_NAMES[PROFESSION_KEYS[key]]
        end

        if available then
            local materials = {}
            for _, name in ipairs(entry.materials or {}) do
                materials[#materials + 1] = { name = name, price = priceByName[name] }
            end
            list[#list + 1] = {
                order = index,
                need = #required,
                title = entry.title,
                place = entry.place,
                materials = materials,
                note = entry.note,
                professions = #names > 0 and table.concat(names, " + ") or "Any character",
            }
        end
    end

    table.sort(list, function(a, b)
        if a.need ~= b.need then
            return a.need > b.need
        end
        return a.order < b.order
    end)
    return list
end

function FWR:GetStarterGuideVersion()
    return self.STARTER_GUIDE and self.STARTER_GUIDE.version or nil
end

-- What each processing (disenchant, milling, prospecting) gave, per use. Returns a list, most used first:
--   { key, label, uses, valuePerUse (copper, nil without prices),
--     outputs = { { name, quality, count, perUse, unitPrice, value }, ... } }  best paid first
-- includeQuality false adds up the qualities of an item. With a query (or an exact item) only the matching
-- results are listed.
function FWR:BuildAdvisorProcessingResults(includeQuality, queryText, exactItemID, exactQuality)
    local _, settings = self:EnsureAdvisorStore()
    local processing = type(settings.processing) == "table" and settings.processing or {}
    local currentExpansion = settings.currentExpansionOnly and getCurrentExpansion() or nil

    local searchID, searchName, searchQuality
    if queryText and queryText ~= "" then
        searchID, searchName, searchQuality = self:ParseAdvisorQuery(queryText)
        searchID = exactItemID or searchID
        searchQuality = exactQuality or searchQuality
        if not includeQuality then
            searchQuality = nil
        end
    elseif exactItemID then
        searchID = exactItemID
    end

    local rows = {}
    for key, label in pairs(PROCESS_LABELS) do
        local process = processing[key]
        local uses = type(process) == "table" and tonumber(process.uses) or 0
        if uses > 0 then
            local grouped = {}
            for _, info in pairs(process.items or {}) do
                local include = true
                if currentExpansion then
                    local expansion = resolveItemExpansion(info)
                    include = expansion ~= nil and expansion >= currentExpansion
                end
                if include and searchID then
                    include = tonumber(info.id) == searchID
                elseif include and searchName and searchName ~= "" then
                    include = normalizeName(info.name) == searchName
                end
                if include and searchQuality then
                    include = string.upper(info.quality or "") == searchQuality
                end

                if include then
                    local groupKey = includeQuality and (tostring(info.id) .. "|" .. tostring(info.quality)) or (normalizeName(info.name) or tostring(info.id))
                    local output = grouped[groupKey]
                    if not output then
                        output = { name = info.name, quality = includeQuality and info.quality or nil, count = 0, value = 0 }
                        grouped[groupKey] = output
                    end
                    local count = tonumber(info.count) or 0
                    output.count = output.count + count
                    local price = self:GetAuctionPrice(info.id, true)
                    if price then
                        output.value = output.value + price * count
                    end
                end
            end

            local outputs = {}
            local totalValue = 0
            for _, output in pairs(grouped) do
                if output.count > 0 then
                    output.perUse = output.count / uses
                    output.unitPrice = output.value > 0 and (output.value / output.count) or nil
                    totalValue = totalValue + output.value
                    outputs[#outputs + 1] = output
                end
            end

            if #outputs > 0 then
                table.sort(outputs, function(a, b)
                    if a.value == b.value then
                        return a.count > b.count
                    end
                    return a.value > b.value
                end)
                rows[#rows + 1] = {
                    key = key,
                    label = label,
                    uses = uses,
                    valuePerUse = totalValue > 0 and (totalValue / uses) or nil,
                    outputs = outputs,
                }
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.uses == b.uses then
            return a.label < b.label
        end
        return a.uses > b.uses
    end)
    return rows
end
