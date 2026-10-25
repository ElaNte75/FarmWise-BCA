local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- Classic API uses global GetItemInfo directly

-- Value of looted scrap.
-- Scrap is every poor quality (grey) item: it is only good for the vendor. Its vendor price is
-- recorded the moment it is looted, for the zone and sub-zone you are standing in, so it does not
-- matter where it is sold later. Gear and other drops are not counted, because nobody can know
-- whether they will be sold, disenchanted or kept. Crafting materials are valued at the Auction
-- House elsewhere.

local selfLootPatterns = nil
local otherLootPatterns = nil

local function formatToPattern(format)
    if type(format) ~= "string" or format == "" then
        return nil
    end

    local pattern = format:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    pattern = pattern:gsub("%%s", ".+")
    pattern = pattern:gsub("%%d", "%%d+")
    return "^" .. pattern .. "$"
end

local function buildPatterns(formats)
    local patterns = {}
    for _, format in ipairs(formats) do
        local pattern = formatToPattern(format)
        if pattern then
            patterns[#patterns + 1] = pattern
        end
    end
    return patterns
end

local function getSelfLootPatterns()
    selfLootPatterns = selfLootPatterns or buildPatterns({ LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE })
    return selfLootPatterns
end

local function getOtherLootPatterns()
    otherLootPatterns = otherLootPatterns or buildPatterns({
        LOOT_ITEM, LOOT_ITEM_MULTIPLE, LOOT_ITEM_PUSHED, LOOT_ITEM_PUSHED_MULTIPLE,
    })
    return otherLootPatterns
end

-- True for "Bob receives loot: ..." (a group member's loot). Everything else, including your own
-- loot and the results of processing, is not matched.
function FWR:IsOtherPlayerLootMessage(message)
    if type(message) ~= "string" then
        return false
    end

    for _, pattern in ipairs(getOtherLootPatterns()) do
        if message:match(pattern) then
            return true
        end
    end
    return false
end

-- True only for "You receive loot: ..." (never for other players' loot or quest rewards).
function FWR:IsOwnLootMessage(message)
    if type(message) ~= "string" then
        return false
    end

    for _, pattern in ipairs(getSelfLootPatterns()) do
        if message:match(pattern) then
            return true
        end
    end
    return false
end

function FWR:HandleVendorLootMessage(message)
    if not self:IsOwnLootMessage(message) then
        return
    end

    local zone = type(GetZoneText) == "function" and GetZoneText() or ""
    local subzone = self:GetAreaSubZoneText()

    for _, entry in ipairs(self:ExtractLootEntries(message)) do
        local itemID = tonumber(entry.itemLink:match("item:(%d+)"))
        local quantity = tonumber(entry.quantity) or 1

        if itemID then
            Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
                local _, _, quality, _, _, _, _, _, _, _, sellPrice, classID, _, _, _, _, isCraftingReagent = GetItemInfo(itemID)
                sellPrice = tonumber(sellPrice) or 0

                -- only poor quality items are scrap; trade materials are valued at the Auction House
                if quality ~= 0 or classID == 7 or isCraftingReagent == true or sellPrice <= 0 then
                    return
                end

                self:Emit("vendorValueRecorded", sellPrice * quantity, zone, subzone)
            end)
        end
    end
end
