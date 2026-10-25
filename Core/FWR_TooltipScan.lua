local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- Classic tooltip scanner: reads an item link's tooltip text through a hidden
-- GameTooltip (the modern C_TooltipInfo API does not exist on the BCA client).

local scanTip = CreateFrame("GameTooltip", "FWRScanTooltip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- Returns the tooltip's left and right line texts joined by spaces.
function FWR:GetTooltipText(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return ""
    end

    scanTip:ClearLines()
    local ok = pcall(scanTip.SetHyperlink, scanTip, itemLink)
    if not ok then
        return ""
    end

    local chunks = {}
    local name = scanTip:GetName()
    for i = 1, scanTip:NumLines() do
        local left = _G[name .. "TextLeft" .. i]
        local right = _G[name .. "TextRight" .. i]
        if left and left.GetText then
            local t = left:GetText()
            if t and t ~= "" then
                chunks[#chunks + 1] = t
            end
        end
        if right and right.GetText then
            local t = right:GetText()
            if t and t ~= "" then
                chunks[#chunks + 1] = t
            end
        end
    end

    return table.concat(chunks, " ")
end
