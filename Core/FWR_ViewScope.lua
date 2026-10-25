local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- View scope.
-- Data is ALWAYS stored in its most detailed form: one context per zone + sub-zone + character
-- ("Zone::SubZone##Character-Realm", or "Zone##Character-Realm" when there is no sub-zone).
-- The Tracking settings only decide what is shown: this module turns those settings into a
-- "scope" and sums time, gold and items over every stored context that belongs to it.
--
--   subzone   current character, current zone and sub-zone
--   zone      current character, current zone (all its sub-zones)
--   character current character, all zones          (Tracking: All Current Character Data)
--   all       all characters, all zones             (Tracking: Combined All Character Data)

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

-- Splits a context key into zone, sub-zone and character key. Missing parts are nil.
function FWR:ParseContextKey(contextKey)
    if type(contextKey) ~= "string" or contextKey == "" then
        return nil, nil, nil
    end

    local base, characterKey = contextKey:match("^(.-)##(.+)$")
    if not base then
        base = contextKey
        characterKey = nil
    end

    local zone, subzone = base:match("^(.-)::(.+)$")
    if not zone then
        zone = base
    end

    return normalizeText(zone), normalizeText(subzone), characterKey
end

-- Builds the storage key. The sub-zone is always part of it when the game reports one.
function FWR:BuildDetailedContextKey(zone, subzone)
    zone = normalizeText(zone) or ""
    subzone = normalizeText(subzone)
    if zone == "" then
        return ""
    end

    local baseKey = zone
    if subzone and subzone ~= zone then
        baseKey = zone .. "::" .. subzone
    end

    local characterKey = self.GetCurrentCharacterKey and select(1, self:GetCurrentCharacterKey()) or ""
    if self.BuildCharacterScopedContextKey then
        return self:BuildCharacterScopedContextKey(baseKey, characterKey)
    end
    return baseKey
end

function FWR:GetViewScope()
    local characterKey = self.GetCurrentCharacterKey and select(1, self:GetCurrentCharacterKey()) or ""

    if self.IsCombinedAllDataEnabled and self:IsCombinedAllDataEnabled() then
        return { mode = "all" }
    end

    if self.IsCombinedCharacterAllZonesEnabled and self:IsCombinedCharacterAllZonesEnabled() then
        return { mode = "character", characterKey = characterKey }
    end

    local zone = normalizeText(self.GetLiveZoneText and self:GetLiveZoneText() or nil) or ""
    local subzone = normalizeText(self.GetLiveSubzoneText and self:GetLiveSubzoneText() or nil) or ""

    if self.IsSubZoneDataEnabled and self:IsSubZoneDataEnabled() then
        return { mode = "subzone", characterKey = characterKey, zone = zone, subzone = subzone }
    end

    return { mode = "zone", characterKey = characterKey, zone = zone }
end

function FWR:ContextMatchesViewScope(contextKey, scope)
    scope = scope or self:GetViewScope()
    if scope.mode == "all" then
        return true
    end

    local zone, subzone, characterKey = self:ParseContextKey(contextKey)
    if characterKey ~= scope.characterKey then
        return false
    end

    if scope.mode == "character" then
        return true
    end

    if zone ~= normalizeText(scope.zone) then
        return false
    end

    if scope.mode == "subzone" then
        return (subzone or "") == (normalizeText(scope.subzone) or "")
    end

    return true
end

function FWR:GetViewScopeLabel(scope)
    scope = scope or self:GetViewScope()
    if scope.mode == "all" then
        return "all data"
    elseif scope.mode == "character" then
        return "all zones of this character"
    elseif scope.mode == "subzone" and normalizeText(scope.subzone) then
        return scope.subzone
    end
    return normalizeText(scope.zone) or "current zone"
end

-- Calls callback(key, value) for every stored entry of the given table that belongs to the scope.
function FWR:ForEachInViewScope(storeTable, scope, callback)
    if type(storeTable) ~= "table" then
        return
    end
    scope = scope or self:GetViewScope()
    for key, value in pairs(storeTable) do
        if type(value) == "table" and self:ContextMatchesViewScope(key, scope) then
            callback(key, value)
        end
    end
end

-- Total and session seconds of active farming time inside the scope.
function FWR:SumViewScopeSeconds(scope)
    local idleState = self.EnsureIdleSystemState and self:EnsureIdleSystemState() or nil
    local totalSeconds, sessionSeconds = 0, 0
    self:ForEachInViewScope(idleState and idleState.timersByContext, scope, function(_, timer)
        totalSeconds = totalSeconds + math.max(0, tonumber(timer.totalSeconds) or 0)
        sessionSeconds = sessionSeconds + math.max(0, tonumber(timer.sessionSeconds) or 0)
    end)
    return totalSeconds, sessionSeconds
end

-- Session copper inside the scope: money looted from mobs, and the vendor value of scrap.
function FWR:SumViewScopeGold(scope)
    local ledger = self.DB and self.DB.goldLedger
    local rawCopper, scrapCopper = 0, 0
    self:ForEachInViewScope(ledger and ledger.byContextKey, scope, function(_, bucket)
        rawCopper = rawCopper + math.max(0, tonumber(bucket.rawLootCopperSession) or 0)
        scrapCopper = scrapCopper + math.max(0, tonumber(bucket.scrapCopperSession) or 0)
    end)
    return rawCopper, scrapCopper
end

-- Auction House value (before the cut) of the trade materials collected this session inside the scope.
function FWR:SumViewScopeMaterialsValue(scope)
    local render = self.DB and self.DB.renderState
    local copper = 0
    self:ForEachInViewScope(render and render.displayBasketByContext, scope, function(_, basket)
        for _, entry in pairs(type(basket.byKey) == "table" and basket.byKey or {}) do
            local quantity = type(entry) == "table" and tonumber(entry.quantityCount) or 0
            if quantity > 0 then
                local price = self:GetAuctionPrice(entry.itemID, true)
                if price then
                    copper = copper + price * quantity
                end
            end
        end
    end)
    return copper
end

-- Makes an entry's zone fields describe the context it is stored in.
function FWR:ApplyContextZoneFields(entry)
    if type(entry) ~= "table" then
        return
    end

    local zone = normalizeText(self.GetLiveZoneText and self:GetLiveZoneText() or nil)
    local subzone = normalizeText(self.GetLiveSubzoneText and self:GetLiveSubzoneText() or nil)
    if not zone then
        return
    end

    entry.zoneContext = zone
    entry.zoneName = zone
    entry.subZoneContext = subzone
    entry.subZoneName = subzone
end
