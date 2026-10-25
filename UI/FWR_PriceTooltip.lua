local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local GetItemInfoInstant = GetItemInfoInstant

-- Adds the Auction House price (from the last FarmWise scan) to item tooltips, on a line that says
-- "FarmWise" so it is clear where the number comes from.

-- the colours of what FarmWise adds to a tooltip: a strong orange-gold for its names, the yellow of the game's own
-- titles for what it says
local NAME_COLOR = "ff9d1f"
local NAME_RGB = { 1, 0.616, 0.122 }
local TEXT_RGB = { 1, 0.82, 0 }

local LABEL = "|cff" .. NAME_COLOR .. "FarmWise|r AH"

local GOLD_ICON = "|TInterface/MoneyFrame/UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface/MoneyFrame/UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface/MoneyFrame/UI-CopperIcon:0:0:2:0|t"

-- Full price like the game's own lines: gold is left out when there is none, but once the first
-- unit is shown every smaller unit follows, even when it is zero (1 46 00).
local function formatPrice(copper)
    copper = math.floor(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100

    if gold > 0 then
        return string.format("%d%s %02d%s %02d%s", gold, GOLD_ICON, silver, SILVER_ICON, rest, COPPER_ICON)
    elseif silver > 0 then
        return string.format("%d%s %02d%s", silver, SILVER_ICON, rest, COPPER_ICON)
    end
    return string.format("%d%s", rest, COPPER_ICON)
end

-- The same price with every unit in a column of its own, so that the prices of a list stand gold under gold, silver
-- under silver, copper under copper. goldDigits: the width of the gold column (the most digits of any line); what is
-- not there (the missing gold digits, a gold or a silver that does not exist) is written invisibly, so that the
-- places stay. All the digits of this font are of the same width.
local BLANK_ICON = "|TInterface/MoneyFrame/UI-GoldIcon:0:0:2:0:64:64:0:1:0:1|t"   -- the empty corner of the picture

local function invisible(text)
    return "|c00000000" .. text .. "|r"
end

function FWR:FormatAlignedMoney(copper, goldDigits)
    copper = math.floor(tonumber(copper) or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    goldDigits = math.max(goldDigits or 1, 1)

    local goldText
    if gold > 0 then
        local text = tostring(gold)
        goldText = invisible(string.rep("0", goldDigits - #text)) .. text .. GOLD_ICON
    else
        goldText = invisible(string.rep("0", goldDigits)) .. BLANK_ICON
    end

    local silverText
    if gold > 0 or silver > 0 then
        silverText = string.format(" %02d%s", silver, SILVER_ICON)
    else
        silverText = " " .. invisible("00") .. BLANK_ICON
    end

    return goldText .. silverText .. string.format(" %02d%s", rest, COPPER_ICON)
end

-- how many digits the gold of the biggest of these amounts has
function FWR:GoldDigitsOf(amounts)
    local most = 1
    for _, copper in ipairs(amounts) do
        local gold = math.floor((tonumber(copper) or 0) / 10000)
        most = math.max(most, #tostring(gold > 0 and gold or 0))
    end
    return most
end

-- Which kinds of item the last scan can have read: trade materials always, the other things sold by amount
-- when that level of the scan is on, and everything when the whole Auction House is scanned.
local ITEM_CLASS = (Enum and Enum.ItemClass) or {}
local COMMODITY_CLASSES = {
    [ITEM_CLASS.Consumable or 0] = true,
    [ITEM_CLASS.Gem or 3] = true,
    [ITEM_CLASS.Reagent or 5] = true,
    [ITEM_CLASS.Tradegoods or 7] = true,
    [ITEM_CLASS.ItemEnhancement or 8] = true,
}
local TRADEGOODS = ITEM_CLASS.Tradegoods or 7

-- an item's class never changes, so it is asked of the game once
local classCache = {}

-- Lowest Auction House price of one item from the last scan, or nil. Only the kinds of item the scan level
-- covers have a price, so an old bigger scan never leaves a stale price on another kind of item.
-- materialsOnly: true = trade materials only (what the Advisor counts); "commodities" = the things sold by
-- amount that the scan level covers (what the AH Tab lists), also when the whole Auction House was scanned,
-- because gear is not the business of the tab.
function FWR:GetAuctionPrice(itemID, materialsOnly)
    local settings = self.Settings and self.Settings.ah
    if not itemID then
        return nil
    end
    settings = type(settings) == "table" and settings or {}

    local classID = classCache[itemID]
    if classID == nil then
        classID = select(6, GetItemInfoInstant(itemID))
        if classID == nil then
            return nil
        end
        classCache[itemID] = classID
    end

    local covered
    if materialsOnly == true then
        covered = classID == TRADEGOODS
    elseif settings.fullScan == true and not materialsOnly then
        covered = true
    elseif settings.fullScan == true or settings.scanCommodities ~= false then
        covered = COMMODITY_CLASSES[classID] == true
    else
        covered = classID == TRADEGOODS
    end
    if not covered then
        return nil
    end

    local store = FarmWiseDB and FarmWiseDB._ah
    local record = type(store) == "table" and type(store.items) == "table" and store.items[tostring(itemID)] or nil
    local price = record and tonumber(record.unitPrice or record.price)
    if price and price > 0 then
        return price
    end
    return nil
end

-- the tooltip of an item the AH Tab leaves out because a vendor pays more than the Auction House
local function addVendorInfo(tooltip, itemID)
    if FWR.GetSellTabSettings and not FWR:GetSellTabSettings().enabled then
        return
    end
    if not FWR.GetVendorBetterInfo then
        return
    end
    local vendor, auction = FWR:GetVendorBetterInfo(itemID)
    if not vendor then
        return
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("FarmWise Info", NAME_RGB[1], NAME_RGB[2], NAME_RGB[3])
    tooltip:AddLine("Not listed in the AH Tab:", TEXT_RGB[1], TEXT_RGB[2], TEXT_RGB[3], false)
    tooltip:AddLine("a vendor pays more than the Auction House", TEXT_RGB[1], TEXT_RGB[2], TEXT_RGB[3], false)
    tooltip:AddLine(" ")
    local digits = FWR:GoldDigitsOf({ vendor, auction })
    tooltip:AddDoubleLine("Vendor", FWR:FormatAlignedMoney(vendor, digits), 0.8, 0.8, 0.8, 1, 1, 1)
    tooltip:AddDoubleLine("Auction House (after the 5% cut)", FWR:FormatAlignedMoney(auction, digits), 0.8, 0.8, 0.8, 1, 1, 1)
end

local function addPriceLine(tooltip, itemID)
    itemID = tonumber(itemID)
    if not itemID then
        return
    end

    local settings = FWR.Settings and FWR.Settings.ah
    local showPrice = not (type(settings) == "table" and settings.tooltipPrice == false)

    if showPrice then
        local price = FWR:GetAuctionPrice(itemID)
        if price then
            tooltip:AddDoubleLine(LABEL, formatPrice(price), 1, 1, 1, 1, 1, 1)
        end
    end

    addVendorInfo(tooltip, itemID)
end

-- On this client there is no TooltipDataProcessor: a tooltip hook on the item tooltips does the same.
-- The link of the item the tooltip shows gives its id.
local function itemIDOf(tooltip)
    local _, link = tooltip:GetItem()
    if not link then
        return nil
    end
    return tonumber(link:match("item:(%d+)"))
end

for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
    "ShoppingTooltip1", "ShoppingTooltip2" }) do
    local tip = _G[name]
    if tip and tip.HookScript then
        tip:HookScript("OnTooltipSetItem", function(tooltip)
            pcall(addPriceLine, tooltip, itemIDOf(tooltip))
        end)
    end
end
