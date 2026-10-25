local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local EXPANSION_INFO = {
    [1] = { fullName = "The Burning Crusade", shortName = "TBC", ordinal = "1st" },
    [2] = { fullName = "Wrath of the Lich King", shortName = "WotLK", ordinal = "2nd" },
    [3] = { fullName = "Cataclysm", shortName = "Cata", ordinal = "3rd" },
    [4] = { fullName = "Mists of Pandaria", shortName = "MoP", ordinal = "4th" },
    [5] = { fullName = "Warlords of Draenor", shortName = "WoD", ordinal = "5th" },
    [6] = { fullName = "Legion", shortName = "Legion", ordinal = "6th" },
    [7] = { fullName = "Battle for Azeroth", shortName = "BfA", ordinal = "7th" },
    [8] = { fullName = "Shadowlands", shortName = "SL", ordinal = "8th" },
    [9] = { fullName = "Dragonflight", shortName = "DF", ordinal = "9th" },
    [10] = { fullName = "The War Within", shortName = "TWW", ordinal = "10th" },
    [11] = { fullName = "Midnight", shortName = "Midnight", ordinal = "11th" },
    [12] = { fullName = "The Last Titan", shortName = "The Last Titan", ordinal = "12th" },
}



local ACCENT_GOLD_COLOR = { 1.0, 0.82, 0.0, 1.0 }

local MAIN_COLUMN_TOOLTIP_TEXTS = {
    item = "Item Name\nShows the tracked item recorded on this row.\nThis is the main item identity for the current area data.",
    quantity = "Quantity\nShows how many of this item have been recorded on this row.\nThis reflects the tracked count for the current area view.",
    total = "Total\nShows the total recorded amount for this item in this area context.\nUse it to compare how much of each item has been gathered overall.",
    itemPerHour = "Item / Hour\nShows the estimated rate for this item based on the area's tracked total time.\nHigher values mean this item is being gathered faster in this area.",
    itemType = "Reagent Type\nShows the detected material category used by the tracker.\nThis helps separate elemental, cloth, ore, herb, darkmoon, and other reagent groups.",
    classification = "Profession\nShows the detected profession grouping for this item.\nThis is the tracker classification, not necessarily the profession currently being used.",
    activity = "Activity\nShows how the item was obtained, such as loot, gathering, or processing.\nUse it to understand the source path behind the row.",
    expansion = "Expansion\nShows which WoW expansion this item belongs to.\nShort labels are used in the column, and the tooltip explains the full expansion name.",
    zone = "Zone\nShows the main zone tied to this row.\nThis is the larger area context used for the tracked data.",
    subZone = "Sub-Zone\nShows the sub-zone tied to this row when one is available.\nThis is the more specific location inside the main zone.",
    character = "Character\nShows which character recorded this row.\nUse it to distinguish data when multiple characters contribute to the history.",
    price = "Price\nThe lowest Auction House price of one item, from the last FarmWise scan.\nShows - when the item has no scanned price.",
    value = "Value\nPrice multiplied by the Session quantity: what the items collected since the last reset are worth.\nIt uses the latest scanned price, not the price at the time of looting.",
}

local EXPANSION_LOOKUP = {}
for _, info in pairs(EXPANSION_INFO) do
    local fullName = tostring(info.fullName or "")
    if fullName ~= "" then
        EXPANSION_LOOKUP[string.lower(fullName)] = info
    end
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



function FWR:GetAccentGoldColor()
    return ACCENT_GOLD_COLOR[1], ACCENT_GOLD_COLOR[2], ACCENT_GOLD_COLOR[3], ACCENT_GOLD_COLOR[4]
end

function FWR:GetMainColumnTooltipText(columnKey)
    if type(columnKey) ~= "string" or columnKey == "" then
        return nil
    end
    return MAIN_COLUMN_TOOLTIP_TEXTS[columnKey]
end

function FWR:IsTooltipEnabled()
    local settings = self.Settings or {}
    local ui = settings.ui or {}
    if ui.showTooltips == nil then
        return true
    end
    return ui.showTooltips == true
end

function FWR:IsMainFrameTooltipEnabled()
    local settings = self.Settings or {}
    local ui = settings.ui or {}
    if ui.showMainFrameTooltips == nil then
        return true
    end
    return ui.showMainFrameTooltips == true
end

function FWR:GetExpansionInfo(expansionName, expansionID)
    expansionID = tonumber(expansionID)
    local info = expansionID and EXPANSION_INFO[expansionID] or nil
    if info then
        return info
    end

    local normalizedName = normalizeText(expansionName)
    if normalizedName then
        return EXPANSION_LOOKUP[string.lower(normalizedName)]
    end

    return nil
end

function FWR:GetExpansionDisplayLabel(expansionName, expansionID)
    local info = self:GetExpansionInfo(expansionName, expansionID)
    if info and info.shortName and info.shortName ~= "" then
        return info.shortName
    end
    return normalizeText(expansionName) or ""
end

function FWR:GetExpansionTooltipText(expansionName, expansionID)
    local info = self:GetExpansionInfo(expansionName, expansionID)
    local fallbackName = normalizeText(expansionName)

    if not info and fallbackName then
        return table.concat({
            fallbackName,
            "This expansion is currently shown with its full name.",
            "A short acronym has not been assigned yet.",
        }, "\n")
    end

    if not info then
        return nil
    end

    if info.shortName and info.shortName ~= "" and info.shortName ~= info.fullName then
        return table.concat({
            info.fullName,
            string.format("This is the %s WoW expansion.", info.ordinal),
            string.format("It is usually abbreviated as %s.", info.shortName),
        }, "\n")
    end

    return table.concat({
        info.fullName,
        string.format("This is the %s WoW expansion.", info.ordinal),
    }, "\n")
end

function FWR:ShowSimpleTooltip(owner, text)
    if not owner or type(text) ~= "string" or text == "" or not self:IsTooltipEnabled() then
        return
    end

    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    GameTooltip:ClearLines()

    local lines = {}
    for line in string.gmatch(text, "[^\n]+") do
        line = tostring(line or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            table.insert(lines, line)
        end
    end

    if #lines == 0 then
        return
    end

    local red, green, blue, _ = self:GetAccentGoldColor()
    GameTooltip:AddLine(lines[1], red, green, blue, true)
    for i = 2, #lines do
        GameTooltip:AddLine(lines[i], 0.95, 0.95, 0.95, true)
    end
    GameTooltip:Show()
end

function FWR:HideSimpleTooltip()
    GameTooltip:Hide()
end
