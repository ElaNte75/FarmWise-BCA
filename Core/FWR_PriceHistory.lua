local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- Price history of the materials you farm: one line per item per day (lowest, highest and average of the
-- prices that the scans of that day found). Kept quietly for later use (what is "usual" for an item).
-- Saved in FarmWiseDB._priceHistory[realm][itemID][day] = { low, high, sum, count, { the last prices of the day } }
-- for the last 30 days.
-- It belongs to the realm: the Auction House of one realm says nothing about another.

local KEEP_DAYS = 30
local SECONDS_PER_DAY = 86400
local VALUES_PER_DAY = 6   -- the prices of the day that are kept (the price of the day is their median)

local function realmKey()
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
    if type(realm) ~= "string" or realm == "" then
        return nil
    end
    return realm
end

local function historyStore(realm)
    if type(FarmWiseDB) ~= "table" then
        return nil
    end
    if type(FarmWiseDB._priceHistory) ~= "table" then
        FarmWiseDB._priceHistory = {}
    end
    if type(FarmWiseDB._priceHistory[realm]) ~= "table" then
        FarmWiseDB._priceHistory[realm] = {}
    end
    return FarmWiseDB._priceHistory[realm]
end

-- items: { [tostring(itemID)] = { unitPrice = copper, ... } } as the scan stores it.
function FWR:RecordPriceHistory(items, now)
    local realm = realmKey()
    if not realm or type(items) ~= "table" or not self.GetFarmedItemIDs then
        return
    end
    if self.GetSellTabSettings and self:GetSellTabSettings().enabled == false then
        return   -- the history is for the FarmWise tab of the Auction House
    end
    local store = historyStore(realm)
    if not store then
        return
    end

    local today = math.floor((now or time()) / SECONDS_PER_DAY)
    local oldest = today - KEEP_DAYS + 1

    -- only what you farm (a whole-Auction-House scan has tens of thousands of items)
    for itemID in pairs(self:GetFarmedItemIDs(0)) do
        local record = items[tostring(itemID)]
        local price = record and tonumber(record.unitPrice)
        if price and price > 0 then
            local key = tostring(itemID)
            local days = store[key]
            if type(days) ~= "table" then
                days = {}
                store[key] = days
            end

            local entry = days[today]
            if type(entry) ~= "table" then
                entry = { price, price, price, 1 }
                days[today] = entry
            else
                entry[1] = math.min(entry[1], price)
                entry[2] = math.max(entry[2], price)
                entry[3] = entry[3] + price
                entry[4] = entry[4] + 1
            end

            entry[5] = type(entry[5]) == "table" and entry[5] or {}
            entry[5][#entry[5] + 1] = price
            while #entry[5] > VALUES_PER_DAY do
                table.remove(entry[5], 1)
            end

            for day in pairs(days) do
                if tonumber(day) and tonumber(day) < oldest then
                    days[day] = nil
                end
            end
        end
    end
end

-- The days kept for an item, oldest first: { { day = n, low = , high = , average = }, ... }
function FWR:GetPriceHistory(itemID)
    local realm = realmKey()
    local store = realm and type(FarmWiseDB) == "table" and type(FarmWiseDB._priceHistory) == "table"
        and FarmWiseDB._priceHistory[realm]
    local days = type(store) == "table" and store[tostring(itemID)]
    local result = {}
    if type(days) == "table" then
        for day, entry in pairs(days) do
            if type(entry) == "table" and entry[4] and entry[4] > 0 then
                result[#result + 1] = { day = tonumber(day), low = entry[1], high = entry[2], average = entry[3] / entry[4] }
            end
        end
        table.sort(result, function(a, b)
            return a.day < b.day
        end)
    end
    return result
end

------------------------------------------------------------
-- The trend of an item
------------------------------------------------------------

-- The trend says where the price of an item has been going, in a way that one odd price cannot turn:
--   * one price for each day (the median of that day's scans),
--   * "now" is the median of the last 3 days, "before" the median of the 4 days before them,
--   * it is "up" or "down" only if the change is bigger than what this item normally moves from one day to the
--     next (and at least 5%), otherwise it is "flat",
--   * with too few days there is no trend at all.
local NOW_DAYS = 3
local BEFORE_LAST_DAY = 6        -- the days before are 3 to 6 days ago
local MIN_DAYS_NOW = 1
local MIN_DAYS_BEFORE = 2
local MIN_CHANGE = 0.05
local MAX_THRESHOLD = 0.25
local NOISE_FACTOR = 1.5

local function median(values)
    local sorted = {}
    for index, value in ipairs(values) do
        sorted[index] = value
    end
    table.sort(sorted)
    local count = #sorted
    if count == 0 then
        return nil
    elseif count % 2 == 1 then
        return sorted[(count + 1) / 2]
    end
    return (sorted[count / 2] + sorted[count / 2 + 1]) / 2
end

local function dayPrice(entry)
    if type(entry) ~= "table" then
        return nil
    end
    if type(entry[5]) == "table" and #entry[5] > 0 then
        return median(entry[5])
    end
    if entry[4] and entry[4] > 0 then
        return entry[3] / entry[4]
    end
    return nil
end

-- Returns nil when there is not enough to say, or:
-- { direction = "up" | "down" | "flat", change = 0.12, now = copper, before = copper, daysNow, daysBefore, threshold }
function FWR:GetPriceTrend(itemID, currentTime)
    local realm = realmKey()
    local store = realm and type(FarmWiseDB) == "table" and type(FarmWiseDB._priceHistory) == "table"
        and FarmWiseDB._priceHistory[realm]
    local days = type(store) == "table" and store[tostring(itemID)]
    if type(days) ~= "table" then
        return nil
    end

    local today = math.floor((currentTime or time()) / SECONDS_PER_DAY)
    local nowValues, beforeValues, series = {}, {}, {}
    for key, entry in pairs(days) do
        local day = tonumber(key)
        local value = dayPrice(entry)
        if day and value and value > 0 and day <= today then
            local ago = today - day
            if ago < NOW_DAYS then
                nowValues[#nowValues + 1] = value
            elseif ago <= BEFORE_LAST_DAY then
                beforeValues[#beforeValues + 1] = value
            end
            series[#series + 1] = { day = day, value = value }
        end
    end
    if #nowValues < MIN_DAYS_NOW or #beforeValues < MIN_DAYS_BEFORE then
        return nil
    end

    -- how much the price normally moves from one day to the next, for this item
    table.sort(series, function(a, b)
        return a.day < b.day
    end)
    local moves = {}
    for index = 2, #series do
        moves[#moves + 1] = math.abs(series[index].value / series[index - 1].value - 1)
    end
    local noise = median(moves) or 0
    local threshold = math.min(MAX_THRESHOLD, math.max(MIN_CHANGE, NOISE_FACTOR * noise))

    local now, before = median(nowValues), median(beforeValues)
    local change = now / before - 1
    local direction = "flat"
    if change > threshold then
        direction = "up"
    elseif change < -threshold then
        direction = "down"
    end

    return {
        direction = direction, change = change, now = now, before = before,
        daysNow = #nowValues, daysBefore = #beforeValues, threshold = threshold,
    }
end

FWR:Subscribe("auctionScanFinished", function(items, now)
    pcall(FWR.RecordPriceHistory, FWR, items, now)
end)
