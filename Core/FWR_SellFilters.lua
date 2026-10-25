local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local GetItemInfo = GetItemInfo

-- What FarmWise sells and what it does not: the filters you set per item, the comparison with the vendor,
-- and which items count as "farmed". Used by the Auction House tab (its list and its right-click window)
-- and by the item tooltip.
--
-- Saved in FarmWiseDB._sellFilters[tostring(itemID)] = { hide = true, keep = n }.
-- Every quality of an item is a different item ID in the game, so each quality has its own filters.

local AUCTION_HOUSE_CUT = 0.05   -- the Auction House keeps 5% of what an item sells for
local FARMED_CACHE_SECONDS = 10

------------------------------------------------------------
-- Filters per item
------------------------------------------------------------

local function filterStore(create)
    if type(FarmWiseDB) ~= "table" then
        return nil
    end
    if type(FarmWiseDB._sellFilters) ~= "table" then
        if not create then
            return nil
        end
        FarmWiseDB._sellFilters = {}
    end
    return FarmWiseDB._sellFilters
end

-- The settings of the FarmWise tab chosen in the options (they are read straight from the saved settings, so
-- that they are also there while the addon is still being loaded).
function FWR:GetSellTabSettings()
    local ah = type(FarmWiseReforgedSettingsDB) == "table" and FarmWiseReforgedSettingsDB.ah
    ah = type(ah) == "table" and ah or {}
    local duration = tonumber(ah.tabPostTime)
    if duration ~= 1 and duration ~= 2 and duration ~= 3 then
        duration = 1
    end
    return {
        enabled = ah.tabEnabled ~= false,
        tooltips = ah.tabTooltips ~= false,
        openFirst = ah.tabOpenFirst ~= false,
        priceAutoFix = ah.tabPriceAutoFix == true,
        priceCheckLevel = math.max(1, math.min(4, math.floor(tonumber(ah.tabPriceCheckLevel) or 2))),
        vendorCoin = ah.tabVendorCoin ~= false,
        wheel = ah.tabWheel == true,
        wheelShift = ah.tabWheelShift ~= false,   -- the wheel posts only while Shift is held
        onlyFarmed = ah.tabOnlyFarmed == true,
        groups = {
            trade = ah.tabShowTrade ~= false,
            consumables = ah.tabShowConsumables ~= false,
            gems = ah.tabShowGems ~= false,
            other = ah.tabShowOther ~= false,
        },
        duration = duration,
        priceCheck = ah.tabPriceCheck == true,
        averageFloor = ah.tabAverageFloor == true,
        averageSales = math.max(5, math.min(30, math.floor(tonumber(ah.tabAverageSales) or 10))),
        priceStep = math.max(1, math.min(20, math.floor(tonumber(ah.tabPriceStep) or 5))),
        showTrend = ah.tabShowTrend ~= false,
        showValue = ah.tabShowValue ~= false,
    }
end

local function rawRecord(itemID)
    local store = filterStore(false)
    local record = store and store[tostring(itemID)]
    return type(record) == "table" and record or nil
end

-- The record of an item is changed by `change(record)` and kept only while something is set in it.
local function updateRecord(self, itemID, change)
    local record = {}
    local current = rawRecord(itemID)
    if current then
        for key, value in pairs(current) do
            record[key] = value
        end
    end
    change(record)

    record.keep = (tonumber(record.keep) or 0) > 0 and math.floor(record.keep) or nil
    record.hide = record.hide == true or nil

    local key = tostring(itemID)
    if record.hide == nil and record.keep == nil and record.check == nil and record.duration == nil
        and record.floor == nil then
        local store = filterStore(false)
        if store then
            store[key] = nil
        end
    else
        filterStore(true)[key] = record
    end
    self:Emit("sellFiltersChanged", itemID)
end

-- Returns: hide (true when the item must not be listed), keep (how many to keep in the bags, 0 for none),
-- check (the price check is on: the item's own choice, or else the one for all items) and duration (1, 2 or 3:
-- 12, 24 or 48 hours; the item's own choice, or else the one for all items).
function FWR:GetSellFilter(itemID)
    local record = rawRecord(itemID)
    local defaults = self:GetSellTabSettings()
    local hide = (record and record.hide == true) or false
    local keep = record and math.max(0, math.floor(tonumber(record.keep) or 0)) or 0
    local check = defaults.priceCheck
    if record and record.check ~= nil then
        check = record.check == true
    end
    local duration = record and tonumber(record.duration) or defaults.duration
    if duration ~= 1 and duration ~= 2 and duration ~= 3 then
        duration = defaults.duration
    end
    return hide, keep, check, duration
end

function FWR:SetSellFilter(itemID, hide, keep)
    updateRecord(self, itemID, function(record)
        record.hide = hide == true
        record.keep = keep
    end)
end

-- The price check of this item: on or off. It is kept only when it differs from the choice for all items.
function FWR:SetPriceCheck(itemID, on)
    local default = self:GetSellTabSettings().priceCheck
    updateRecord(self, itemID, function(record)
        if (on == true) == default then
            record.check = nil
        else
            record.check = on == true
        end
    end)
end

-- "Never below my average price" for this item: on or off. Kept only when it differs from the choice for all items.
function FWR:SetAveragePriceFloor(itemID, on)
    local default = self:GetSellTabSettings().averageFloor
    updateRecord(self, itemID, function(record)
        if (on == true) == default then
            record.floor = nil
        else
            record.floor = on == true
        end
    end)
end

-- Is "never below my average price" on for this item (its own choice, or else the one for all items)?
function FWR:IsAveragePriceFloorOn(itemID)
    local record = rawRecord(itemID)
    if record and record.floor ~= nil then
        return record.floor == true
    end
    return self:GetSellTabSettings().averageFloor
end

-- The price an item must not be posted below (copper for one piece), or nil when the choice is off for the item
-- or the history does not hold enough sales to make an average.
function FWR:GetAveragePriceFloor(itemID)
    if not self:IsAveragePriceFloorOn(itemID) or not self.GetMyAveragePrice then
        return nil
    end
    -- the average is made of the sales history: switched off, there is none
    if self.IsSalesHistoryEnabled and not self:IsSalesHistoryEnabled() then
        return nil
    end
    return (self:GetMyAveragePrice(itemID))
end

-- The posting time of this item (1, 2, 3), or nil to follow the choice for all items.
function FWR:SetItemDuration(itemID, duration)
    local default = self:GetSellTabSettings().duration
    updateRecord(self, itemID, function(record)
        if duration == default then
            record.duration = nil
        else
            record.duration = duration
        end
    end)
end

-- The item's own posting time, or nil when it follows the choice for all items.
function FWR:GetItemDurationOverride(itemID)
    local record = rawRecord(itemID)
    return record and tonumber(record.duration) or nil
end

-- True when any filter of yours is set for the item, of whatever kind: a record exists only while at least one
-- is on (updateRecord removes it when nothing is left), so a new kind of filter needs nothing added here.
function FWR:HasSellFilter(itemID)
    return rawRecord(itemID) ~= nil
end

-- What the Auction House keeps as a deposit for posting this many of the item for this long (copper).
-- This client's CalculateAuctionDeposit only answers for what sits in the sell slot, so the deposit is
-- estimated from the vendor price: 15% of it per piece per 12 hours (12/24/48 h -> x1/x2/x4).
function FWR:GetPostDeposit(itemID, duration, quantity)
    if not itemID or itemID == 0 then
        return nil
    end
    local sellPrice = select(11, GetItemInfo(itemID))
    if type(sellPrice) ~= "number" or sellPrice <= 0 then
        return nil
    end
    local factor = ({ 1, 2, 4 })[tonumber(duration) or 1] or 1
    return math.floor(sellPrice * 0.15 * factor * math.max(1, quantity or 1))
end

------------------------------------------------------------
-- Is a price usual? (from the listings of the Auction House right now)
------------------------------------------------------------

-- Somebody puts a few pieces at a very low price to pull the price of everybody down. The lowest price then
-- says little: where most of the quantity is listed says more. The "usual price" is the price at which the
-- cheapest 15% of all that is for sale has been counted.
local USUAL_SHARE = 0.15
local USUAL_MIN_UNITS = 20    -- fewer pieces for sale than this: not enough to judge
local USUAL_MIN_LISTINGS = 3
local LOW_FACTOR = 0.85       -- below 85% of the usual price: unusually low
-- the same, by the strictness the user chose: relaxed, normal, strict, very strict
local LOW_FACTORS = { 0.70, 0.85, 0.92, 0.97 }
local HIGH_FACTOR = 1.25      -- above 125% of it: high

-- listings: { { price = copper, quantity = n }, ... } cheapest first. Returns the usual price, or nil.
function FWR:GetUsualPrice(listings)
    local total, count = 0, 0
    for _, listing in ipairs(listings or {}) do
        total = total + (tonumber(listing.quantity) or 0)
        count = count + 1
    end
    if count < USUAL_MIN_LISTINGS or total < USUAL_MIN_UNITS then
        return nil
    end

    local target = total * USUAL_SHARE
    local counted = 0
    for _, listing in ipairs(listings) do
        counted = counted + (tonumber(listing.quantity) or 0)
        if counted >= target then
            return tonumber(listing.price)
        end
    end
    return tonumber(listings[#listings].price)
end

-- "low", "normal" or "high" for a price against the usual price, and the lowest price that is still usual.
function FWR:GetPriceZone(price, usual)
    price, usual = tonumber(price), tonumber(usual)
    if not price or not usual then
        return nil
    end

    -- prices of the Auction House are in whole silver (not one of the 358 listings that were looked at had
    -- copper): the lowest usual price is rounded up to a whole silver
    local level = self.GetSellTabSettings and self:GetSellTabSettings().priceCheckLevel or 2
    local lowest = usual * (LOW_FACTORS[level] or LOW_FACTOR)
    if lowest >= 100 then
        lowest = math.ceil(lowest / 100) * 100
    else
        lowest = math.ceil(lowest)
    end
    if price < lowest then
        return "low", lowest
    elseif price > usual * HIGH_FACTOR then
        return "high", lowest
    end
    return "normal", lowest
end

------------------------------------------------------------
-- Vendor against Auction House
------------------------------------------------------------

local function vendorPrice(itemID)
    local price
    if GetItemInfo then
        price = select(11, GetItemInfo(itemID))
    end
    if price == nil and GetItemInfo then
        price = select(11, GetItemInfo(itemID))
    end
    return tonumber(price)
end

-- The same, against a price that is known now (for items that the scan does not read): the live lowest price.
function FWR:IsVendorBetterThanPrice(itemID, unitPrice)
    unitPrice = tonumber(unitPrice)
    local vendor = vendorPrice(itemID)
    if not itemID or not unitPrice or unitPrice <= 0 or not vendor or vendor <= 0 then
        return false
    end
    return vendor > math.floor(unitPrice * (1 - AUCTION_HOUSE_CUT))
end

-- The live lowest price at which a vendor turned out to pay more (the tab asked the Auction House), per item.
-- It is what the tooltip of an item left out of the list uses for the items the scan does not read.
local liveVendorBetter = {}

function FWR:NoteVendorBetter(itemID, unitPrice)
    if itemID and tonumber(unitPrice) then
        liveVendorBetter[itemID] = tonumber(unitPrice)
    end
end

-- What a vendor and the Auction House (after its 5%) pay for one of this item, when the vendor pays more:
-- vendorPrice, auctionNetPrice. nil when it is not so, or not known.
function FWR:GetVendorBetterInfo(itemID)
    local vendor = vendorPrice(itemID)
    if not itemID or not vendor or vendor <= 0 then
        return nil
    end
    local auctionPrice = self.GetAuctionPrice and self:GetAuctionPrice(itemID, "commodities") or liveVendorBetter[itemID]
    auctionPrice = auctionPrice or liveVendorBetter[itemID]
    if not auctionPrice then
        return nil
    end
    local net = math.floor(auctionPrice * (1 - AUCTION_HOUSE_CUT))
    if vendor > net then
        return vendor, net
    end
    return nil
end

-- True when a vendor pays more for one of this material than the Auction House would, after its 5%.
-- It is not known (false) while the Auction House price or the vendor price is not known.
function FWR:IsSoldBetterToVendor(itemID)
    if not itemID or not self.GetAuctionPrice then
        return false
    end

    local auctionPrice = self:GetAuctionPrice(itemID, "commodities")
    local vendor = vendorPrice(itemID)
    if not auctionPrice or not vendor or vendor <= 0 then
        return false
    end
    return vendor > math.floor(auctionPrice * (1 - AUCTION_HOUSE_CUT))
end

------------------------------------------------------------
-- Items you have farmed
------------------------------------------------------------

local farmed = { ids = {}, at = nil }

local function buildFarmedItemIDs()
    local ids = {}
    local db = FarmWiseDB
    if type(db) ~= "table" then
        return ids
    end

    for key, data in pairs(db) do
        if type(key) == "string" and key:sub(1, 1) ~= "_" and type(data) == "table" and type(data.items) == "table" then
            for _, info in pairs(data.items) do
                if type(info) == "table" and info.id then
                    ids[tonumber(info.id)] = true
                end
            end
        end
    end

    local processing = type(db._advisor) == "table" and db._advisor.processing
    if type(processing) == "table" then
        for _, process in pairs(processing) do
            for _, info in pairs(type(process) == "table" and process.items or {}) do
                if type(info) == "table" and info.id then
                    ids[tonumber(info.id)] = true
                end
            end
        end
    end
    return ids
end

-- Item IDs FarmWise has seen you gather, loot or process (from the saved statistics). The answer is kept
-- for a few seconds (item tooltips ask all the time); maxAgeSeconds = 0 asks again.
function FWR:GetFarmedItemIDs(maxAgeSeconds)
    local now = GetTime()
    local limit = maxAgeSeconds or FARMED_CACHE_SECONDS
    if not farmed.at or now - farmed.at >= limit then
        farmed.ids = buildFarmedItemIDs()
        farmed.at = now
    end
    return farmed.ids
end

function FWR:IsFarmedItem(itemID)
    return itemID ~= nil and self:GetFarmedItemIDs()[tonumber(itemID)] == true
end

-- This client has no reagent qualities: an item has one quality, its rarity.
function FWR:GetItemQualityTier(itemID)
    return nil
end

-- "Q1", "Q2", "Q3", or nil.
function FWR:GetItemQualityLabel(itemID)
    local tier = self:GetItemQualityTier(itemID)
    return tier and ("Q" .. tier) or nil
end
