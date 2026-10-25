local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- Rarity filter (Engine page: "Set Rarity Level"). Presentation only: items below the
-- chosen rarity are hidden from the main window but are still recorded.

function FWR:IsEntryBelowRarityFilter(entry)
    local engine = self.Settings and self.Settings.engine
    if type(engine) ~= "table" or engine.rarityFilterEnabled ~= true then
        return false
    end

    local minimumRarity = tonumber(engine.rarityLevel) or 1
    local rarity = type(entry) == "table" and tonumber(entry.itemRarity) or nil
    return rarity ~= nil and rarity < minimumRarity
end
