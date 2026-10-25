local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local function extractQuantityFromSegment(segment)
    if type(segment) ~= "string" or segment == "" then
        return 1
    end

    local qty = segment:match("[xX](%d+)")
    if qty then
        return tonumber(qty) or 1
    end

    qty = segment:match("×%s*(%d+)")
    if qty then
        return tonumber(qty) or 1
    end

    return 1
end

local function extractLootEntries(message)
    local entries = {}
    if message == nil then
        return entries
    end

    local ok, safeMessage = pcall(tostring, message)
    if not ok or type(safeMessage) ~= "string" or safeMessage == "" then
        return entries
    end

    local searchStart = 1
    while true do
        local linkStart, linkEnd, itemLink = safeMessage:find("(|Hitem:.-|h%[.-%]|h)", searchStart)
        if not linkStart then
            break
        end

        local nextLinkStart = safeMessage:find("|Hitem:", linkEnd + 1)
        local segmentEnd = nextLinkStart and (nextLinkStart - 1) or #safeMessage
        local segment = safeMessage:sub(linkEnd + 1, segmentEnd)
        local quantity = extractQuantityFromSegment(segment)

        table.insert(entries, {
            itemLink = itemLink,
            quantity = quantity,
        })

        searchStart = linkEnd + 1
    end

    return entries
end

-- Splits a loot chat message into { itemLink, quantity } entries.
function FWR:ExtractLootEntries(message)
    return extractLootEntries(message)
end

function FWR:RetryPendingRoutedLootEntry(itemLink, quantity, attempts)
    attempts = tonumber(attempts) or 0
    if attempts >= 5 or not itemLink then
        return
    end

    local sourceStage = self:EvaluateLootSource(itemLink)
    if type(sourceStage) ~= "table" or not sourceStage.passed then
        return
    end

    local needsRetry = false
    if sourceStage.sourceType == "fishing" and self.RouteFishingLoot then
        local _, routeNeedsRetry = self:RouteFishingLoot(sourceStage, quantity or 1)
        needsRetry = routeNeedsRetry == true
    elseif sourceStage.sourceType == "skinning" and self.RouteSkinningLoot then
        local _, routeNeedsRetry = self:RouteSkinningLoot(sourceStage, quantity or 1)
        needsRetry = routeNeedsRetry == true
    elseif sourceStage.sourceType == "mining" and self.RouteMiningLoot then
        local _, routeNeedsRetry = self:RouteMiningLoot(sourceStage, quantity or 1)
        needsRetry = routeNeedsRetry == true
    elseif sourceStage.sourceType == "herbalism" and self.RouteHerbalismLoot then
        local _, routeNeedsRetry = self:RouteHerbalismLoot(sourceStage, quantity or 1)
        needsRetry = routeNeedsRetry == true
    elseif (sourceStage.sourceType == "combat" or sourceStage.sourceType == "processing" or sourceStage.sourceType == "crafting") and self.RouteCombatLoot then
        local _, routeNeedsRetry = self:RouteCombatLoot(sourceStage, quantity or 1)
        needsRetry = routeNeedsRetry == true
    end

    if needsRetry and C_Timer and C_Timer.After then
        C_Timer.After(0.2, function()
            if FarmWiseReforged and FarmWiseReforged.RetryPendingRoutedLootEntry then
                FarmWiseReforged:RetryPendingRoutedLootEntry(itemLink, quantity, attempts + 1)
            end
        end)
    end
end

function FWR:HandleLootChatMessage(message)
    local lootEntries = extractLootEntries(message)
    if #lootEntries == 0 then
        return
    end

    for _, entry in ipairs(lootEntries) do
        local sourceStage = self:EvaluateLootSource(entry.itemLink)
        if type(sourceStage) == "table" and sourceStage.passed then
            if sourceStage.sourceType == "fishing" and self.RouteFishingLoot then
                local _, needsRetry = self:RouteFishingLoot(sourceStage, entry.quantity or 1)
                if needsRetry then
                    self:RetryPendingRoutedLootEntry(entry.itemLink, entry.quantity or 1, 0)
                end
            elseif sourceStage.sourceType == "skinning" and self.RouteSkinningLoot then
                local _, needsRetry = self:RouteSkinningLoot(sourceStage, entry.quantity or 1)
                if needsRetry then
                    self:RetryPendingRoutedLootEntry(entry.itemLink, entry.quantity or 1, 0)
                end
            elseif sourceStage.sourceType == "mining" and self.RouteMiningLoot then
                local _, needsRetry = self:RouteMiningLoot(sourceStage, entry.quantity or 1)
                if needsRetry then
                    self:RetryPendingRoutedLootEntry(entry.itemLink, entry.quantity or 1, 0)
                end
            elseif sourceStage.sourceType == "herbalism" and self.RouteHerbalismLoot then
                local _, needsRetry = self:RouteHerbalismLoot(sourceStage, entry.quantity or 1)
                if needsRetry then
                    self:RetryPendingRoutedLootEntry(entry.itemLink, entry.quantity or 1, 0)
                end
            elseif (sourceStage.sourceType == "combat" or sourceStage.sourceType == "processing" or sourceStage.sourceType == "crafting") and self.RouteCombatLoot then
                local _, needsRetry = self:RouteCombatLoot(sourceStage, entry.quantity or 1)
                if needsRetry then
                    self:RetryPendingRoutedLootEntry(entry.itemLink, entry.quantity or 1, 0)
                end
            end
        end
    end
end
