local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- The FarmWise tab of the Auction House (Burning Crusade Anniversary client).
-- This client has the classic AuctionFrame (Browse / Bids / Auctions), not the modern
-- AuctionHouseFrame: the tab is a fourth button next to the game's own three, and the pages
-- below are our own frame shown over the browse area.
--
-- Pages: Sell (post from the bags with a suggested price), Auctions (the ledger of my posts),
-- History (the sales books) and Options.
--
-- Posting on this client: ClickAuctionSellItemButton(bag, slot) puts an item into the sell
-- slot, GetAuctionSellItemInfo() reads it, StartAuction(minBid, buyoutPrice, runTime) posts it
-- (runTime 1 = 12 h, 2 = 24 h, 3 = 48 h). Prices are totals of the whole stack. One post per
-- click, as everywhere.

local PREFIX = "|cffd7be6aFarmWise|r "
local ROW_HEIGHT = 18
local VISIBLE_ROWS = 14
local HOURS = { 12, 24, 48 }

local CUT = 0.05

local tabButton
local panel
local pageFrames = {}
local pageButtons = {}
local currentPage = "sell"

local sellRows = {}          -- the list of the Sell page
local sellOffset = 0
local vendorMarked = {}
local pendingPrice           -- itemID whose live price query is on the wire

local function say(message)
    print(PREFIX .. message)
end

local function money(copper)
    copper = math.floor(tonumber(copper) or 0)
    if GetCoinTextureString then
        return GetCoinTextureString(copper)
    end
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    if g > 0 then return g .. "g " .. s .. "s " .. c .. "c" end
    if s > 0 then return s .. "s " .. c .. "c" end
    return c .. "c"
end

------------------------------------------------------------
-- Sell list: what the bags hold that the Auction House takes
------------------------------------------------------------

local function isSoulbound(itemLink)
    local text = FWR:GetTooltipText(itemLink)
    return text and (text:find("Soulbound") or text:find("Binds when picked up")) or false
end

local function refreshSellRows()
    wipe(sellRows)
    wipe(vendorMarked)

    local settings = FWR:GetSellTabSettings()
    if not settings.enabled then
        return
    end

    local seen = {}
    local lastBag = tonumber(NUM_BAG_SLOTS) or 4
    for bag = 0, lastBag do
        local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
            local info = GetContainerItemInfo and GetContainerItemInfo(bag, slot)
            local itemID = info and tonumber(info.itemID)
            local count = info and tonumber(info.stackCount) or 1
            local locked = info and info.isLocked
            if link and itemID and not locked and not seen[itemID] then
                seen[itemID] = true
                local name, _, rarity, _, _, _, _, _, _, _, sellPrice = GetItemInfo(link)
                local classID = select(6, GetItemInfoInstant(itemID))
                if name and rarity and rarity > 0 and sellPrice and sellPrice > 0
                    and not isSoulbound(link) then
                    local groupOk = classID == 7 and settings.groups.trade
                        or classID == 0 and settings.groups.consumables
                        or classID == 3 and settings.groups.gems
                        or (classID ~= 7 and classID ~= 0 and classID ~= 3) and settings.groups.other
                    local farmedOk = not settings.onlyFarmed or (FWR.IsFarmedItem and FWR:IsFarmedItem(itemID))
                    if groupOk and farmedOk then
                        local hidden, keep = FWR:GetSellFilter(itemID)
                        local owned = count
                        for b = 0, lastBag do
                            -- count every stack of the same item, not only the first seen
                        end
                        -- total count across bags
                        local total = 0
                        for b = 0, lastBag do
                            local n = GetContainerNumSlots and GetContainerNumSlots(b) or 0
                            for s = 1, n do
                                local i2 = GetContainerItemInfo and GetContainerItemInfo(b, s)
                                if i2 and tonumber(i2.itemID) == itemID then
                                    total = total + (tonumber(i2.stackCount) or 1)
                                end
                            end
                        end
                        owned = total

                        local sellable = owned - (tonumber(keep) or 0)
                        local scanPrice = FWR.GetAuctionPrice and FWR:GetAuctionPrice(itemID, "commodities")
                        local vendor = sellPrice
                        local vendorBetter = vendor and scanPrice and vendor > math.floor(scanPrice * (1 - CUT))

                        if vendorBetter then
                            vendorMarked[itemID] = true
                        end

                        if not hidden and sellable > 0 and not vendorBetter then
                            sellRows[#sellRows + 1] = {
                                itemID = itemID,
                                name = name,
                                rarity = rarity,
                                link = link,
                                bag = bag,
                                slot = slot,
                                count = sellable,
                                price = scanPrice,
                            }
                        end
                    end
                end
            end
        end
    end

    table.sort(sellRows, function(a, b) return a.name < b.name end)
    if FWR.SetBagVendorCoins then
        FWR:SetBagVendorCoins(vendorMarked)
    end
end

------------------------------------------------------------
-- Pages
------------------------------------------------------------

local function newRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -4, 0)
    row.right:SetJustifyH("RIGHT")
    return row
end

local function makeList(parent)
    local rows = {}
    for i = 1, VISIBLE_ROWS do
        rows[i] = newRow(parent)
        rows[i]:SetPoint("TOPLEFT", 4, -(i - 1) * ROW_HEIGHT)
        rows[i]:SetWidth(parent:GetWidth() - 12)
    end
    parent.rows = rows
    return rows
end

local function showList(parent, data, offset, renderRow)
    for i = 1, VISIBLE_ROWS do
        local row = parent.rows[i]
        local item = data[offset + i]
        if item then
            renderRow(row, item)
            row:Show()
        else
            row:Hide()
        end
    end
end

-- Sell page ------------------------------------------------------------

local function buildSellPage(parent)
    makeList(parent)
    local post = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    post:SetSize(90, 20)
    post:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 6)
    post:SetText("Post")
    parent.postButton = post

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 6, 8)
    hint:SetText("Click a line to place it in the sell box, then Post.")
    parent.hint = hint
end

local selectedSell

local function renderSellPage()
    local page = pageFrames.sell
    showList(page, sellRows, sellOffset, function(row, item)
        local priceText = item.price and money(item.price) or "?"
        row.text:SetText(item.name .. " x" .. item.count)
        row.right:SetText(priceText)
        row:SetScript("OnClick", function()
            selectedSell = item
            if ClickAuctionSellItemButton then
                pcall(ClickAuctionSellItemButton, item.bag, item.slot)
            end
        end)
        if selectedSell == item then
            row.text:SetTextColor(1, 0.82, 0)
        else
            row.text:SetTextColor(1, 1, 1)
        end
    end)

    page.postButton:SetScript("OnClick", function()
        local item = selectedSell
        if not item then
            say("Choose an item first.")
            return
        end
        local unit = item.price
        if not unit or unit <= 0 then
            say("No price for " .. item.name .. " yet - run a scan first (/fw scan).")
            return
        end
        if GetAuctionSellItemInfo then
            local placed = GetAuctionSellItemInfo()
            if not placed then
                pcall(ClickAuctionSellItemButton, item.bag, item.slot)
            end
        end
        local total = unit * item.count
        local ok, err = pcall(StartAuction, total, total, HOURS[FWR:GetSellTabSettings().duration] and FWR:GetSellTabSettings().duration or 1)
        if ok then
            say("Posted " .. item.name .. " x" .. item.count .. " for " .. money(total) .. ".")
        else
            say("The post did not go through: " .. tostring(err))
        end
    end)
end

-- Auctions page --------------------------------------------------------

local function renderAuctionsPage()
    local page = pageFrames.auctions
    local rows = FWR.GetActionRows and FWR:GetActionRows() or {}
    showList(page, rows, 0, function(row, item)
        local stateText = ({ active = "active", sold = "SOLD", ended = "ended" })[item.state] or item.state
        row.text:SetText(item.name .. " x" .. item.qty .. "  -  " .. stateText)
        row.right:SetText(money(item.net))
        row:SetScript("OnClick", function()
            if item.state == "active" and item.id then
                FWR:CancelPost(item.id)
            end
        end)
    end)
end

-- History page ---------------------------------------------------------

local function renderHistoryPage()
    local page = pageFrames.history
    local rows = FWR.GetSalesHistoryRows and FWR:GetSalesHistoryRows() or {}
    table.sort(rows, function(a, b) return (a.net or 0) > (b.net or 0) end)
    showList(page, rows, 0, function(row, item)
        row.text:SetText(item.name .. "  sold " .. (item.sold or 0))
        row.right:SetText(money(item.net))
        row:SetScript("OnClick", nil)
    end)
end

-- Options page ---------------------------------------------------------

local OPTION_KEYS = {
    { key = "autoScan", label = "Scan automatically when the Auction House opens" },
    { key = "sound", label = "Sound when a scan finishes" },
    { key = "tooltipPrice", label = "Auction House price in item tooltips" },
    { key = "tabOpenFirst", label = "Open the FarmWise tab first" },
    { key = "tabVendorCoin", label = "Coin on items a vendor pays more for" },
    { key = "tabOnlyFarmed", label = "Sell list: only what I have farmed" },
    { key = "tabPriceCheck", label = "Price check for all items" },
    { key = "tabAverageFloor", label = "Never below my average price" },
}

local function buildOptionsPage(parent)
    local y = -8
    for _, opt in ipairs(OPTION_KEYS) do
        local check = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
        check:SetPoint("TOPLEFT", 8, y)
        check.Text:SetText(opt.label)
        check.optionKey = opt.key
        check:SetScript("OnClick", function(self2)
            local ah = FWR.Settings and FWR.Settings.ah
            if type(ah) == "table" then
                ah[opt.key] = self2:GetChecked() == true
                if FWR.Emit then
                    FWR:Emit("sellTabEnabledChanged")
                    FWR:Emit("sellTabVendorCoinChanged")
                end
            end
        end)
        parent["check_" .. opt.key] = check
        y = y - 24
    end
end

local function renderOptionsPage()
    local page = pageFrames.options
    local ah = FWR.Settings and FWR.Settings.ah or {}
    for _, opt in ipairs(OPTION_KEYS) do
        local check = page["check_" .. opt.key]
        if check then
            check:SetChecked(ah[opt.key] ~= false and ah[opt.key] ~= nil)
        end
    end
end

------------------------------------------------------------
-- Tab on the AuctionFrame
------------------------------------------------------------

local function selectPage(name)
    currentPage = name
    for key, frame in pairs(pageFrames) do
        if key == name then
            frame:Show()
        else
            frame:Hide()
        end
    end
    for key, button in pairs(pageButtons) do
        if key == name then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end
    if name == "sell" then
        refreshSellRows()
        renderSellPage()
    elseif name == "auctions" then
        if FWR.RefreshOwnedAuctions then
            FWR:RefreshOwnedAuctions()
        end
        renderAuctionsPage()
    elseif name == "history" then
        renderHistoryPage()
    elseif name == "options" then
        renderOptionsPage()
    end
end

local function showPanel()
    if panel then
        -- cover the game's own pages
        if _G.AuctionFrameBrowse then _G.AuctionFrameBrowse:Hide() end
        if _G.AuctionFrameBid then _G.AuctionFrameBid:Hide() end
        if _G.AuctionFrameAuctions then _G.AuctionFrameAuctions:Hide() end
        panel:Show()
        selectPage(currentPage)
    end
end

local function hidePanel()
    if panel then
        panel:Hide()
    end
end

local function buildPanel()
    local ah = _G.AuctionFrame
    if not ah then
        return false
    end

    panel = CreateFrame("Frame", "FarmWiseAuctionPanel", ah)
    panel:SetPoint("TOPLEFT", ah, "TOPLEFT", 12, -70)
    panel:SetPoint("BOTTOMRIGHT", ah, "BOTTOMRIGHT", -12, 40)
    panel:SetFrameStrata("HIGH")
    panel:Hide()

    -- sub-tab buttons
    local names = { sell = "Sell", auctions = "Auctions", history = "History", options = "Options" }
    local x = 0
    for _, key in ipairs({ "sell", "auctions", "history", "options" }) do
        local button = CreateFrame("Button", nil, panel, "CharacterFrameTabButtonTemplate")
        button:SetText(names[key])
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", x, 24)
        button:SetScript("OnClick", function()
            selectPage(key)
        end)
        pageButtons[key] = button
        x = x + 90
    end

    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", 4, -2)
    content:SetPoint("BOTTOMRIGHT", -4, 0)

    for key in pairs(names) do
        local frame = CreateFrame("Frame", nil, panel)
        frame:SetPoint("TOPLEFT", 8, -6)
        frame:SetPoint("BOTTOMRIGHT", -8, 4)
        frame:Hide()
        pageFrames[key] = frame
    end

    buildSellPage(pageFrames.sell)
    makeList(pageFrames.auctions)
    makeList(pageFrames.history)
    buildOptionsPage(pageFrames.options)

    -- the tab button, after the game's own three
    local id = (#{ _G.AuctionFrameTab1, _G.AuctionFrameTab2, _G.AuctionFrameTab3 }) + 1
    local anchor = _G["AuctionFrameTab" .. (id - 1)]
    tabButton = CreateFrame("Button", "AuctionFrameTab" .. id, ah, "CharacterFrameTabButtonTemplate")
    tabButton:SetID(id)
    tabButton:SetText("FarmWise")
    if anchor then
        tabButton:SetPoint("LEFT", anchor, "RIGHT", -16, 0)
    end
    tabButton:SetScript("OnClick", function()
        PanelTemplates_SetTab(ah, id)
        if _G.AuctionFrameTopRight then _G.AuctionFrameTopRight:Hide() end
        showPanel()
    end)

    if PanelTemplates_SetNumTabs then
        pcall(PanelTemplates_SetNumTabs, ah, id)
    end

    -- leaving to a game tab hides our panel
    for index = 1, 3 do
        local gameTab = _G["AuctionFrameTab" .. index]
        if gameTab then
            gameTab:HookScript("OnClick", hidePanel)
        end
    end

    -- scan progress note inside the panel
    panel.scanText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.scanText:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 4, -2)
    panel.scanText:SetJustifyH("LEFT")

    return true
end

local installed = false
local function install()
    if installed then
        return
    end
    if buildPanel() then
        installed = true
        local settings = FWR.GetSellTabSettings and FWR:GetSellTabSettings()
        if settings and settings.openFirst and FWR.IsAuctionScanComing and FWR:IsAuctionScanComing() then
            -- a scan is about to run: the tab opens after it (the scan needs the list pages)
        elseif settings and settings.openFirst and tabButton then
            tabButton:Click()
        end
    end
end

FWR:Subscribe("auctionScanChanged", function()
    if panel and panel.scanText then
        local text = FWR.GetAuctionSyncAgeText and FWR:GetAuctionSyncAgeText() or ""
        panel.scanText:SetText(text)
    end
end)
FWR:Subscribe("actionsChanged", function()
    if panel and panel:IsShown() and currentPage == "auctions" then
        renderAuctionsPage()
    end
end)
FWR:Subscribe("salesHistoryChanged", function()
    if panel and panel:IsShown() and currentPage == "history" then
        renderHistoryPage()
    end
end)

local events = CreateFrame("Frame")
local function safeRegisterEvent(event)
    pcall(events.RegisterEvent, events, event)
end

safeRegisterEvent("AUCTION_HOUSE_SHOW")
safeRegisterEvent("AUCTION_HOUSE_CLOSED")
events:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        install()
        if panel and panel:IsShown() then
            selectPage(currentPage)
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        hidePanel()
    end
end)
