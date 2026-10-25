local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- Floating loot text: while the main window is minimized to its small button, every item that is looted rises from
-- that button, in the colour of its rarity ("Bright Linen x3"), and fades away, like the combat text of the game.
-- An item that is worth more than the value chosen in the Interface options comes bigger and with a sound.
-- Nothing is shown when the window is open: the window is where the information is then.

local MAX_LINES = 6          -- on the screen at the same time (the oldest is let go when more come)
local LIFE = 4.8             -- seconds a line lives
local RISE = 140             -- pixels it rises
local GAP = 0.85             -- seconds between two lines that start: with the speed, about 25 pixels between them
local MERGE_WITHIN = 1.6     -- an item looted again this soon joins the line that is still near the button

local host = CreateFrame("Frame", nil, UIParent)
host:SetFrameStrata("HIGH")
host:SetSize(1, 1)
host:EnableMouse(false)

local active, pending, pool = {}, {}, {}
local sinceStart = GAP

local function settings()
    return (FWR.Settings and FWR.Settings.ui) or {}
end

local function isOn()
    local mini = FWR.GetMainWindowMiniButton and FWR:GetMainWindowMiniButton()
    return settings().floatLootText == true and mini and mini:IsShown() and mini or nil
end

local function rarityHex(entry)
    local quality = tonumber(entry.itemRarity)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then
        return (color.hex:gsub("^|c", ""):gsub("|r$", ""))
    end
    if type(entry.itemLink) == "string" then
        local fromLink = entry.itemLink:match("|c(%x%x%x%x%x%x%x%x)")
        if fromLink then
            return fromLink
        end
    end
    return "ffffffff"
end

-- the worth of what was looted, in copper: the Auction House price of the last scan, else what a vendor pays
local function valueOf(entry, quantity)
    local itemID = tonumber(entry.itemID)
    if not itemID then
        return 0
    end
    local unit = FWR.GetAuctionPrice and FWR:GetAuctionPrice(itemID) or nil
    if not unit and GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, sellPrice = pcall(GetItemInfo, itemID)
        unit = ok and tonumber(sellPrice) or nil
    end
    return (unit or 0) * (tonumber(quantity) or 1)
end

local function release(line)
    line.text:Hide()
    pool[#pool + 1] = line
end

local function acquire()
    local line = table.remove(pool)
    if not line then
        line = { text = host:CreateFontString(nil, "OVERLAY", "GameFontNormal") }
        line.text:SetShadowOffset(1, -1)
    end
    return line
end

-- Where the lines grow: from the corner of the small button that is on the side of the screen's edge, towards the
-- middle of the screen: near the bottom they rise, near the top they go down; near the left edge they run to the
-- right (and are written from the left), near the right edge they run to the left.
local function directions(mini)
    local x, y = mini:GetCenter()
    local scale = mini:GetScale() or 1
    local width, height = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
    return not (x and x > width / 2), not (y and y > height / 2)   -- fromLeft, rising
end

local function place(line, mini)
    local offset = line.age / line.life * RISE
    local fromLeft, rising = directions(mini)
    local side = fromLeft and "LEFT" or "RIGHT"
    line.text:ClearAllPoints()
    line.text:SetJustifyH(side)
    if rising then
        line.text:SetPoint("BOTTOM" .. side, mini, "TOP" .. side, 0, 4 + offset)
    else
        line.text:SetPoint("TOP" .. side, mini, "BOTTOM" .. side, 0, -4 - offset)
    end
end

local function stopIfIdle()
    if #active == 0 and #pending == 0 then
        host:SetScript("OnUpdate", nil)
    end
end

local function onUpdate(_, elapsed)
    local mini = isOn()
    if not mini then
        -- the window opened (or the option went off): everything goes
        for index = #active, 1, -1 do
            release(table.remove(active, index))
        end
        for index = #pending, 1, -1 do
            release(table.remove(pending, index))
        end
        stopIfIdle()
        return
    end

    sinceStart = sinceStart + elapsed
    if #pending > 0 and sinceStart >= GAP then
        sinceStart = 0
        local line = table.remove(pending, 1)
        if #active >= MAX_LINES then
            release(table.remove(active, 1))
        end
        active[#active + 1] = line
        line.text:Show()
    end

    for index = #active, 1, -1 do
        local line = active[index]
        line.age = line.age + elapsed
        local progress = line.age / line.life
        if progress >= 1 then
            release(table.remove(active, index))
        else
            place(line, mini)
            -- full for the first 60%, then it fades
            line.text:SetAlpha(progress < 0.6 and 1 or (1 - (progress - 0.6) / 0.4))
        end
    end
    stopIfIdle()
end

local function write(line, name, quantity)
    line.name, line.quantity = name, quantity
    line.text:SetText(string.format("|c%s%s|r x%d", line.hex, name, quantity))
end

local function show(entry, quantity)
    local mini = isOn()
    if not mini then
        return
    end
    quantity = tonumber(quantity) or 1
    local name = entry.itemName or "?"

    -- the same item again, soon: it joins the line that is still near the button
    for _, line in ipairs(active) do
        if line.name == name and line.age < MERGE_WITHIN then
            write(line, name, line.quantity + quantity)
            line.age = 0
            return
        end
    end
    for _, line in ipairs(pending) do
        if line.name == name then
            write(line, name, line.quantity + quantity)
            return
        end
    end

    local line = acquire()
    line.age, line.life = 0, LIFE
    line.hex = rarityHex(entry)

    -- worth more than the value chosen: bigger, and a sound
    local gold = tonumber(settings().lootAlertGold) or 100
    if gold < 10 then
        gold = 100    -- there is no "off": the slider goes from 10 to 1000 (the alert has its own switch)
    end
    local valuable = settings().lootAlertSound ~= false and valueOf(entry, quantity) >= gold * 10000
    line.text:SetFontObject(valuable and "GameFontNormalHuge" or "GameFontNormalLarge")
    write(line, name, quantity)
    if valuable and PlaySound and SOUNDKIT then
        pcall(PlaySound, SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.READY_CHECK)
    end

    -- never a long queue: when many come at once, the oldest of those waiting is let go
    if #pending >= MAX_LINES then
        release(table.remove(pending, 1))
    end
    pending[#pending + 1] = line
    host:SetScript("OnUpdate", onUpdate)
end

-- the floating lines follow the same display rules as the window: what the filters hide
-- (rarity below the chosen level, old-expansion items when they are off) is not shown either
local function hiddenByFilters(entry)
    if FWR.IsEntryBelowRarityFilter and FWR:IsEntryBelowRarityFilter(entry) then
        return true
    end
    if entry.expansionCategory == "old" and not (FWR.IsOldExpansionVisible and FWR:IsOldExpansionVisible()) then
        return true
    end
    return false
end

FWR:Subscribe("lootRecorded", function(entry, quantity)
    if type(entry) == "table" and settings().floatLootText == true and not hiddenByFilters(entry) then
        pcall(show, entry, quantity)
    end
end)
