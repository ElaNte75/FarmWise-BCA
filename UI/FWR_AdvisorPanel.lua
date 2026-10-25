local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local GetItemInfo = GetItemInfo

-- Advisor window.
--   Gold: the places with the most gold per hour. With no farming data yet it shows the starter guide.
--   Item: the best yields so far, or the best places for one item you search, drop or shift-click.
-- It uses the same look as the control panel (colors come from UI_CONFIG.ControlPanelWindow).

local PANEL_CONFIG = (FWR.UI_CONFIG and FWR.UI_CONFIG.ControlPanelWindow) or {}
local COLOR_CONFIG = PANEL_CONFIG.colors or {}

local PANEL_WIDTH = 440
local PANEL_HEIGHT = 440
local HEADER_HEIGHT = 56
local FOOTER_HEIGHT = 44
local PADDING = 18
local ROW_HEIGHT = 76
local VISIBLE_ROWS = 3   -- the mouse wheel moves by this many results at a time
local MAX_ROWS = 60
local MAX_STAT_CHARS = 66

local MODE_ITEM = "item"
local MODE_GOLD = "gold"

-- amounts are written with the game's own gold and silver coin pictures
-- (the picture the bag's money display uses: gold, silver and copper side by side, 16 pixels each)
local GOLD_LETTER = "|TInterface/MoneyFrame/UI-MoneyIcons:11:11:2:-3:64:16:0:16:0:16|t"
local SILVER_LETTER = "|TInterface/MoneyFrame/UI-MoneyIcons:11:11:2:-3:64:16:16:32:0:16|t"

local GUIDE_TAG_COLOR = { 0.55, 0.8, 1.0 }
local NOTICE_COLOR = { 1.0, 0.82, 0.0 }
local MUTED_COLOR = { 0.8, 0.8, 0.8 }

local panel = nil
local mode = MODE_GOLD
local exactItemID = nil
local exactQuality = nil
local exactName = nil
local autoFilledText = nil
local scrollOffset = 0
local setScrollOffset, updateScrollRange

local function color(name, fallback)
    return unpack(COLOR_CONFIG[name] or fallback)
end

local function formatTime(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    local minutes = math.floor(seconds / 60)
    local hours = math.floor(minutes / 60)
    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes % 60)
    end
    return string.format("%dm", minutes)
end

local function groupThousands(number)
    local text = tostring(number)
    local replaced
    repeat
        text, replaced = text:gsub("^(%-?%d+)(%d%d%d)", "%1.%2")
    until replaced == 0
    return text
end

-- Whole gold, rounded to the nearest. Under one gold the silver is shown, so a cheap amount is not "0".
local function formatGold(copper)
    copper = tonumber(copper) or 0
    if copper > 0 and copper < 5000 then
        return string.format("%d", math.max(1, math.floor(copper / 100 + 0.5))) .. SILVER_LETTER
    end
    return groupThousands(math.floor(copper / 10000 + 0.5)) .. GOLD_LETTER
end

-- Price of one item: gold with up to two decimals and a decimal comma (1,35), as exact as the Auction House
-- price; a whole price has no decimals (1). The dot is already the thousands separator.
local function formatPrice(copper)
    local gold = (tonumber(copper) or 0) / 10000
    local text = string.format("%.2f", gold)
    text = text:gsub("0+$", "")
    text = text:gsub("[.]$", "")
    text = text:gsub("[.]", ",")
    return text .. GOLD_LETTER
end

local function truncate(text, limit)
    if #text <= limit then
        return text
    end
    return text:sub(1, limit - 3) .. "..."
end

local function createButton(parent, width, label)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(label)
    return button
end

-- Same checkbox look as the control panel: gold text when selected.
local function createCheck(parent, label)
    local check = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    check:SetHitRectInsets(0, 0, 0, 0)
    if check.Text then
        check.Text:ClearAllPoints()
        check.Text:SetPoint("LEFT", check, "RIGHT", 0, 1)
        check.Text:SetJustifyH("LEFT")
        check.Text:SetText(label)
    end
    return check
end

local function setCheckState(check, isChecked)
    check:SetChecked(isChecked)
    if check.Text then
        if isChecked then
            check.Text:SetTextColor(1.0, 0.82, 0.0, 1.0)
        else
            check.Text:SetTextColor(0.82, 0.82, 0.82, 1.0)
        end
    end
end

local function includeQuality()
    return FWR:GetAdvisorSettings().includeQuality == true
end

local function getRow(index)
    local row = panel.rows[index]
    if row then
        return row
    end

    row = {}
    row.zone = panel.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.zone:SetJustifyH("LEFT")
    row.zone:SetWordWrap(false)
    row.confidence = panel.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.confidence:SetJustifyH("RIGHT")
    row.stats = panel.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.stats:SetJustifyH("LEFT")
    row.stats:SetSpacing(2)
    row.divider = panel.content:CreateTexture(nil, "ARTWORK")
    row.divider:SetColorTexture(color("divider", { 1, 1, 1, 0.10 }))
    row.divider:SetHeight(1)

    local top = -((index - 1) * ROW_HEIGHT)
    row.confidence:SetPoint("TOPRIGHT", panel.content, "TOPRIGHT", -4, top - 6)
    row.zone:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 4, top - 4)
    row.zone:SetPoint("RIGHT", row.confidence, "LEFT", -8, 0)
    row.stats:SetPoint("TOPLEFT", row.zone, "BOTTOMLEFT", 0, -3)
    row.stats:SetPoint("RIGHT", panel.content, "RIGHT", -4, 0)
    row.divider:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, top - ROW_HEIGHT + 2)
    row.divider:SetPoint("RIGHT", panel.content, "RIGHT", 0, 0)

    panel.rows[index] = row
    return row
end

local function setRowVisible(row, visible)
    row.zone:SetShown(visible)
    row.confidence:SetShown(visible)
    row.stats:SetShown(visible)
    row.divider:SetShown(visible)
end

local function fillRow(row, data)
    row.zone:SetText(data.title)
    row.confidence:SetText(data.right or "")
    local rightColor = data.rightColor or { 1, 1, 1 }
    row.confidence:SetTextColor(rightColor[1], rightColor[2], rightColor[3])
    row.stats:SetText(data.stats or "")
end

------------------------------------------------------------
-- What the list shows
------------------------------------------------------------

local function confidenceText(result)
    return "Confidence: " .. (result.confidence or "-"), result.confidenceColor
end

-- Item mode, last line: what one item costs, so nobody has to do the sum, and in brackets what the whole
-- yield of an hour is worth. When several qualities are added up, the price of one is their average.
local function priceLine(result)
    if not result.unitPrice then
        return ""
    end
    return string.format("\n%s: %s each  (%s per hour)",
        result.averaged and "Average price" or "Price", formatPrice(result.unitPrice), formatGold(result.valuePerHour))
end

-- A disenchant, milling or prospecting: no place and no time, only what one use gives.
local function formatRate(value)
    if value >= 10 then
        return string.format("%d", math.floor(value + 0.5))
    elseif value >= 1 then
        return (string.format("%.1f", value):gsub("[.]", ","))
    end
    return (string.format("%.2f", value):gsub("[.]", ","))
end

local function processingRow(result)
    local lines = { string.format("Used %d times", result.uses) }
    for index = 1, math.min(#result.outputs, 2) do
        local output = result.outputs[index]
        local name = truncate(output.name or "?", 26)
        if output.quality then
            name = string.format("%s (%s)", name, output.quality)
        end
        local line = string.format("%s: %d  (%s per use)", name, output.count, formatRate(output.perUse))
        if output.unitPrice then
            line = line .. string.format("  -  %s each", formatPrice(output.unitPrice))
        end
        lines[#lines + 1] = line
    end
    if result.valuePerUse then
        lines[#lines + 1] = string.format("Worth per use: %s", formatPrice(result.valuePerUse))
    end

    return {
        title = result.label,
        right = "Processing",
        rightColor = GUIDE_TAG_COLOR,
        stats = table.concat(lines, "\n"),
    }
end

local function processingRows(query)
    local rows = {}
    local quality = includeQuality() and exactQuality or nil
    for _, result in ipairs(FWR:BuildAdvisorProcessingResults(includeQuality(), query, exactItemID, quality)) do
        rows[#rows + 1] = processingRow(result)
    end
    return rows
end

local function placeRow(result)
    local right, rightColor = confidenceText(result)
    local stats
    if mode == MODE_GOLD then
        stats = string.format(
            "Farming time: %s\nEstimated gold/hour: %s\nRaw gold %s  -  Materials %s",
            formatTime(result.totalTime), formatGold(result.goldPerHour),
            formatGold((result.rawPerHour or 0) + (result.vendorPerHour or 0)), formatGold(result.materialsPerHour))
    else
        stats = string.format(
            "Farming time: %s\nGathered: %d items\nAverage yield: %d/hour",
            formatTime(result.totalTime), result.count, result.perHour)
        stats = stats .. priceLine(result)
    end
    return { title = result.zone, right = right, rightColor = rightColor, stats = stats }
end

local function overviewRow(result)
    local right, rightColor = confidenceText(result)
    local title = tostring(result.itemName)
    if result.quality then
        title = string.format("%s (%s)", title, result.quality)
    end
    local stats = string.format(
        "Best place: %s\nFarming time: %s\nAverage yield: %d/hour",
        truncate(result.zone, MAX_STAT_CHARS - 12), formatTime(result.totalTime), result.perHour)
    stats = stats .. priceLine(result)
    return { title = title, right = right, rightColor = rightColor, stats = stats }
end

local function guideRow(entry)
    local materials = {}
    for _, material in ipairs(entry.materials) do
        if material.price then
            materials[#materials + 1] = string.format("%s %s", material.name, formatPrice(material.price))
        else
            materials[#materials + 1] = material.name
        end
    end

    local lines = { "Where: " .. truncate(entry.place or "", MAX_STAT_CHARS - 7) }
    if #materials > 0 then
        lines[#lines + 1] = "Materials: " .. table.concat(materials, ", ")
    end
    if entry.note and entry.note ~= "" then
        lines[#lines + 1] = truncate(entry.note, MAX_STAT_CHARS)
    end

    return {
        title = entry.title,
        right = "Starter guide",
        rightColor = GUIDE_TAG_COLOR,
        stats = table.concat(lines, "\n"),
    }
end

local function guideRows()
    local rows = {}
    for _, entry in ipairs(FWR:GetStarterGuideEntries()) do
        rows[#rows + 1] = guideRow(entry)
    end
    return rows
end

-- Returns rows, notice text, notice color for the current mode and search.
local function buildView()
    local minutes = math.floor(FWR.ADVISOR_MIN_SECONDS / 60)

    if mode == MODE_GOLD then
        local rows = {}
        for _, result in ipairs(FWR:BuildAdvisorGoldResults()) do
            rows[#rows + 1] = placeRow(result)
        end
        if #rows > 0 then
            return rows, "", MUTED_COLOR
        end

        local notice
        if FWR:GetAuctionSyncAgeSeconds() == nil then
            notice = "No Auction House prices yet. Open the Auction House and keep it open until the scan finishes. "
                .. FWR:GetAuctionScanEstimateText() .. " A sound plays when it is done."
        else
            notice = string.format("Not enough farming data yet (a place needs %d+ minutes). The starter guide below (%s) is replaced by your own data as you farm.",
                minutes, FWR:GetStarterGuideVersion() or "community guides")
        end
        return guideRows(), notice, NOTICE_COLOR
    end

    local query = panel.input:GetText() or ""
    if query == "" then
        local rows = {}
        for _, result in ipairs(FWR:BuildAdvisorItemOverview(includeQuality())) do
            rows[#rows + 1] = overviewRow(result)
        end
        for _, row in ipairs(processingRows("")) do
            rows[#rows + 1] = row
        end
        if #rows > 0 then
            return rows, "Your best yields so far, ranked by quantity per hour (not by value). Search an item for its best places.", MUTED_COLOR
        end
        return rows, string.format("Type an item name, drop an item here, or shift-click one. Nothing has %d+ minutes of farming yet.", minutes), NOTICE_COLOR
    end

    local quality = includeQuality() and exactQuality or nil
    local results, restriction, partial = FWR:BuildAdvisorItemResults(query, exactItemID, quality, includeQuality())
    local rows = {}
    for _, result in ipairs(results) do
        rows[#rows + 1] = placeRow(result)
    end
    for _, row in ipairs(processingRows(query)) do
        rows[#rows + 1] = row
    end
    if #rows > 0 then
        return rows, "", MUTED_COLOR
    end

    if restriction then
        return rows, restriction, NOTICE_COLOR
    end
    if partial then
        return rows, string.format("Not enough farming time yet. Best place so far: %s (%s of %d minutes needed).",
            partial.zone, formatTime(partial.seconds), minutes), NOTICE_COLOR
    end
    return rows, string.format("No place with %d+ minutes of farming for this item.", minutes), NOTICE_COLOR
end

local function refreshControls()
    local settings = FWR:GetAdvisorSettings()
    panel.modeButton:SetText(mode == MODE_GOLD and "Mode: Gold" or "Mode: Item")
    setCheckState(panel.qualityCheck, includeQuality())
    setCheckState(panel.expansionCheck, settings.currentExpansionOnly == true)

    local isItemMode = mode == MODE_ITEM
    panel.qualityCheck:SetShown(isItemMode)
    panel.input:SetShown(isItemMode)
    panel.clearButton:SetShown(isItemMode)

    panel.notice:ClearAllPoints()
    if isItemMode then
        panel.notice:SetPoint("TOPLEFT", panel.input, "BOTTOMLEFT", -4, -6)
        panel.help:SetText("Best yields and best places for the items you farm.")
    else
        panel.notice:SetPoint("TOPLEFT", panel.modeRow, "BOTTOMLEFT", 0, -8)
        panel.help:SetText("Where to go for the most gold per hour (Auction House prices minus 5%).")
    end
    panel.notice:SetPoint("RIGHT", panel.body, "RIGHT", -PADDING, 0)
end

-- The age of the prices and the Scan AH button (which waits for the 15 minute safety lock).
local function refreshScanStatus()
    local text, r, g, b = FWR:GetAuctionSyncAgeText()
    panel.syncAge:SetText(text)
    panel.syncAge:SetTextColor(r, g, b)
    panel.syncButton:SetEnabled(FWR:IsAuctionHouseOpen() and not FWR:IsAuctionScanRunning()
        and FWR:GetAuctionScanCooldownSeconds() == 0)
end

function FWR:RefreshAdvisorPanel()
    if not panel or not panel:IsShown() then
        return
    end

    refreshControls()
    refreshScanStatus()

    local rows, notice, noticeColor = buildView()

    panel.notice:SetText(notice)
    panel.notice:SetTextColor(noticeColor[1], noticeColor[2], noticeColor[3])
    panel.notice:SetHeight(notice ~= "" and math.max(14, panel.notice:GetStringHeight()) or 1)

    panel.scroll:ClearAllPoints()
    panel.scroll:SetPoint("TOPLEFT", panel.notice, "BOTTOMLEFT", 0, -8)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel.body, "BOTTOMRIGHT", -(PADDING + 12), 10)

    local shown = math.min(#rows, MAX_ROWS)
    for index = 1, shown do
        local row = getRow(index)
        fillRow(row, rows[index])
        setRowVisible(row, true)
    end
    for index = shown + 1, #panel.rows do
        setRowVisible(panel.rows[index], false)
    end

    panel.contentHeight = shown * ROW_HEIGHT
    panel.content:SetHeight(math.max(panel.contentHeight, 1))
    updateScrollRange()

    -- start from the top when what the list shows changes
    local viewKey = mode .. "|" .. (panel.input:GetText() or "") .. "|" .. tostring(includeQuality())
    if panel.lastViewKey ~= viewKey then
        panel.lastViewKey = viewKey
        setScrollOffset(0)
    end
end

------------------------------------------------------------
-- Search box
------------------------------------------------------------

local function clearExactSelection()
    exactItemID = nil
    exactQuality = nil
    exactName = nil
    autoFilledText = nil
end

local function buildAutoText()
    if includeQuality() and exactQuality then
        return string.format("%s (%s)", exactName, exactQuality)
    end
    return exactName
end

-- Keeps the text in the search box in line with the "Include quality" choice.
local function syncSearchTextWithQuality()
    if exactItemID then
        autoFilledText = buildAutoText()
        panel.input:SetText(autoFilledText)
        return
    end

    if not includeQuality() then
        local text = panel.input:GetText() or ""
        local stripped = text:gsub("%s*%([Qq]%d+%)%s*$", "")
        if stripped ~= text then
            panel.input:SetText(stripped)
        end
    end
end

-- Puts an item into the search box from an item link (shift-click, drag and drop).
local function setItemFromLink(link)
    if type(link) ~= "string" then
        return false
    end

    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then
        return false
    end

    local tier = nil

    mode = MODE_ITEM
    exactItemID = itemID
    exactQuality = (tier and tier > 0) and ("Q" .. tier) or nil
    exactName = GetItemInfo(itemID) or link:match("%[(.-)%]") or tostring(itemID)
    autoFilledText = buildAutoText()
    panel.input:SetText(autoFilledText)
    panel.input:SetCursorPosition(#autoFilledText)
    FWR:RefreshAdvisorPanel()
    return true
end

-- Shift-click works while the search box has the keyboard focus.
local function applyItemLinkFromClick(link)
    if panel and panel.input:HasFocus() then
        return setItemFromLink(link)
    end
    return false
end

-- Dropping an item from the bags onto the window.
local function receiveDroppedItem()
    local infoType, itemID, itemLink = GetCursorInfo()
    if infoType ~= "item" then
        return
    end

    ClearCursor()
    setItemFromLink(itemLink or ("item:" .. tostring(itemID)))
end

local function enableDrop(frame)
    frame:SetScript("OnReceiveDrag", receiveDroppedItem)
    frame:HookScript("OnMouseUp", function()
        if GetCursorInfo() then
            receiveDroppedItem()
        end
    end)
end

-- Moves the list; the scroll bar follows (fromSlider is true when the bar itself caused the move).
setScrollOffset = function(value, fromSlider)
    local range = panel.scrollRange or 0
    scrollOffset = math.max(0, math.min(tonumber(value) or 0, range))
    panel.content:ClearAllPoints()
    panel.content:SetPoint("TOPLEFT", panel.scroll, "TOPLEFT", 0, scrollOffset)
    if not fromSlider then
        panel.scrollbar:SetValue(scrollOffset)
    end
end

-- How far the list can move: the height of all results minus the height of the view.
updateScrollRange = function()
    local viewHeight = panel.scroll:GetHeight() or 0
    local range = math.max(0, (panel.contentHeight or 0) - viewHeight)
    panel.scrollRange = range
    panel.scrollbar:SetMinMaxValues(0, range)
    panel.scrollbar:SetShown(range > 0)
    setScrollOffset(scrollOffset)
end

-- The mouse wheel moves by whole pages of VISIBLE_ROWS results.
local function pageScroll(_, delta)
    local step = VISIBLE_ROWS * ROW_HEIGHT
    local currentPage = math.floor(scrollOffset / step + 0.5)
    setScrollOffset((currentPage - delta) * step)
end

------------------------------------------------------------
-- Building the window
------------------------------------------------------------

local function createBackground(parent, colorName, fallback)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(color(colorName, fallback))
    return texture
end

local function buildFrame()
    panel = CreateFrame("Frame", "FarmWiseAdvisorFrame", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(30)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:Hide()
    panel.rows = {}
    FWR.AdvisorPanel = panel
    table.insert(UISpecialFrames, "FarmWiseAdvisorFrame")

    panel:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    panel:SetBackdropColor(color("frameBg", { 0.04, 0.03, 0.02, 0.94 }))

    panel.header = CreateFrame("Frame", nil, panel)
    panel.header:SetPoint("TOPLEFT", 0, 0)
    panel.header:SetPoint("TOPRIGHT", 0, 0)
    panel.header:SetHeight(HEADER_HEIGHT)
    panel.header:EnableMouse(true)
    panel.header:RegisterForDrag("LeftButton")
    panel.header:SetScript("OnDragStart", function() panel:StartMoving() end)
    panel.header:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    createBackground(panel.header, "headerBg", { 0.10, 0.08, 0.05, 0.95 })

    panel.footer = CreateFrame("Frame", nil, panel)
    panel.footer:SetPoint("BOTTOMLEFT", 0, 0)
    panel.footer:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.footer:SetHeight(FOOTER_HEIGHT)
    createBackground(panel.footer, "footerBg", { 0.10, 0.08, 0.05, 0.95 })

    panel.body = CreateFrame("Frame", nil, panel)
    panel.body:SetPoint("TOPLEFT", panel.header, "BOTTOMLEFT", 0, 0)
    panel.body:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", 0, 0)
    panel.body:EnableMouse(true)
    createBackground(panel.body, "contentBg", { 0.06, 0.05, 0.03, 0.82 })

    local headerLine = panel:CreateTexture(nil, "BORDER")
    headerLine:SetPoint("TOPLEFT", panel.header, "BOTTOMLEFT", 0, 0)
    headerLine:SetPoint("TOPRIGHT", panel.header, "BOTTOMRIGHT", 0, 0)
    headerLine:SetHeight(1)
    headerLine:SetColorTexture(color("divider", { 1, 1, 1, 0.10 }))

    local footerLine = panel:CreateTexture(nil, "BORDER")
    footerLine:SetPoint("BOTTOMLEFT", panel.footer, "TOPLEFT", 0, 0)
    footerLine:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", 0, 0)
    footerLine:SetHeight(1)
    footerLine:SetColorTexture(color("divider", { 1, 1, 1, 0.10 }))

    panel.title = panel.header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 18, -12)
    panel.title:SetTextColor(color("title", { 0.95, 0.82, 0.42, 1.0 }))
    panel.title:SetText("FarmWise")

    panel.titleAccent = panel.header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.titleAccent:SetPoint("LEFT", panel.title, "RIGHT", 6, 0)
    panel.titleAccent:SetTextColor(color("titleAccent", { 0.96, 0.96, 0.96, 1.0 }))
    panel.titleAccent:SetText("Advisor")

    panel.help = panel.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.help:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
    panel.help:SetPoint("RIGHT", panel.header, "RIGHT", -18, 0)
    panel.help:SetJustifyH("LEFT")
    panel.help:SetWordWrap(false)
    panel.help:SetTextColor(color("subtitle", { 0.80, 0.80, 0.80, 1.0 }))

    FWR:AddPanelBorder(panel)
end

local function buildControls()
    -- first row: the mode switch, "Include quality" (item mode only) and "This expansion only" (always, fixed place)
    panel.modeRow = CreateFrame("Frame", nil, panel.body)
    panel.modeRow:SetSize(1, 22)
    panel.modeRow:SetPoint("TOPLEFT", panel.body, "TOPLEFT", PADDING, -12)

    panel.modeButton = createButton(panel.body, 104, "Mode: Gold")
    panel.modeButton:SetPoint("LEFT", panel.modeRow, "LEFT", 0, 0)
    panel.modeButton:SetScript("OnClick", function()
        mode = mode == MODE_GOLD and MODE_ITEM or MODE_GOLD
        FWR:RefreshAdvisorPanel()
    end)
    panel.modeButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(mode == MODE_GOLD and "Click to switch to Item mode." or "Click to switch to Gold mode.")
        GameTooltip:Show()
    end)
    panel.modeButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.qualityCheck = createCheck(panel.body, "Include quality")
    panel.qualityCheck:SetPoint("LEFT", panel.modeRow, "LEFT", 112, 0)
    panel.qualityCheck:SetScript("OnClick", function(self)
        FWR:GetAdvisorSettings().includeQuality = self:GetChecked() == true
        syncSearchTextWithQuality()
        FWR:RefreshAdvisorPanel()
    end)

    panel.expansionCheck = createCheck(panel.body, "This expansion only")
    panel.expansionCheck:SetPoint("LEFT", panel.modeRow, "LEFT", 250, 0)
    panel.expansionCheck:SetScript("OnClick", function(self)
        FWR:GetAdvisorSettings().currentExpansionOnly = self:GetChecked() == true
        FWR:RefreshAdvisorPanel()
    end)

    panel.input = CreateFrame("EditBox", nil, panel.body, "InputBoxTemplate")
    panel.input:SetSize(PANEL_WIDTH - 2 * PADDING - 74, 22)
    panel.input:SetPoint("TOPLEFT", panel.modeRow, "BOTTOMLEFT", 8, -8)
    panel.input:SetAutoFocus(false)
    panel.input:SetScript("OnEscapePressed", panel.input.ClearFocus)
    panel.input:SetScript("OnEnterPressed", panel.input.ClearFocus)
    panel.input:SetScript("OnTextChanged", function(self, userInput)
        if userInput and autoFilledText and self:GetText() ~= autoFilledText then
            clearExactSelection()
        end
        FWR:RefreshAdvisorPanel()
    end)

    panel.clearButton = createButton(panel.body, 60, "Clear")
    panel.clearButton:SetPoint("LEFT", panel.input, "RIGHT", 6, 0)
    panel.clearButton:SetScript("OnClick", function()
        clearExactSelection()
        panel.input:SetText("")
        panel.input:ClearFocus()
        FWR:RefreshAdvisorPanel()
    end)

    -- a short message above the list: instructions, hints or why the list is empty
    panel.notice = panel.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.notice:SetJustifyH("LEFT")
    panel.notice:SetJustifyV("TOP")

    -- the view clips the results; the content inside it is moved up and down by the scroll offset
    panel.scroll = CreateFrame("Frame", nil, panel.body)
    panel.scroll:SetClipsChildren(true)
    panel.scroll:EnableMouse(true)
    panel.scroll:EnableMouseWheel(true)
    panel.scroll:SetScript("OnMouseWheel", pageScroll)
    panel.scroll:SetScript("OnSizeChanged", function() updateScrollRange() end)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetPoint("TOPLEFT", panel.scroll, "TOPLEFT", 0, 0)
    panel.content:SetSize(PANEL_WIDTH - 2 * PADDING - 24, 1)

    panel.scrollbar = CreateFrame("Slider", nil, panel.body)
    panel.scrollbar:SetOrientation("VERTICAL")
    panel.scrollbar:SetWidth(10)
    panel.scrollbar:SetPoint("TOPLEFT", panel.scroll, "TOPRIGHT", 4, 0)
    panel.scrollbar:SetPoint("BOTTOMLEFT", panel.scroll, "BOTTOMRIGHT", 4, 0)
    panel.scrollbar:SetMinMaxValues(0, 0)
    panel.scrollbar:SetValueStep(1)
    panel.scrollbar:SetObeyStepOnDrag(true)
    panel.scrollbar:SetValue(0)
    local track = panel.scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.08)
    panel.scrollbar:SetThumbTexture("Interface/Buttons/WHITE8X8")
    local thumb = panel.scrollbar:GetThumbTexture()
    thumb:SetSize(10, 36)
    thumb:SetColorTexture(0.85, 0.65, 0.15, 0.75)
    panel.scrollbar:SetScript("OnValueChanged", function(_, value)
        setScrollOffset(value, true)
    end)
    panel.scrollbar:Hide()

    enableDrop(panel.body)
    enableDrop(panel.input)
    enableDrop(panel.scroll)
end

local function buildFooter()
    panel.closeButton = CreateFrame("Button", nil, panel.footer, "UIPanelButtonTemplate")
    panel.closeButton:SetSize(84, 24)
    panel.closeButton:SetPoint("RIGHT", panel.footer, "RIGHT", -PADDING, 0)
    panel.closeButton:SetText("Close")
    panel.closeButton:SetScript("OnClick", function() panel:Hide() end)

    panel.syncButton = CreateFrame("Button", nil, panel.footer, "UIPanelButtonTemplate")
    panel.syncButton:SetSize(84, 24)
    panel.syncButton:SetPoint("RIGHT", panel.closeButton, "LEFT", -8, 0)
    panel.syncButton:SetText("Scan AH")
    panel.syncButton:SetScript("OnClick", function()
        FWR:StartAuctionScan()
    end)
    panel.syncButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local cooldown = FWR:GetAuctionScanCooldownSeconds()
        if FWR:IsAuctionScanRunning() then
            GameTooltip:SetText("A scan is already running.")
        elseif cooldown > 0 then
            GameTooltip:SetText(string.format("The prices are still fresh. Available again in %d minutes.", math.ceil(cooldown / 60)))
        elseif not FWR:IsAuctionHouseOpen() then
            GameTooltip:SetText("Open the Auction House to scan trade material prices.")
        else
            GameTooltip:SetText("Scan the Auction House for trade material prices now.")
        end
        GameTooltip:Show()
    end)
    panel.syncButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.syncAge = panel.footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.syncAge:SetPoint("LEFT", panel.footer, "LEFT", PADDING, 0)
end

local function hookItemLinks()
    if type(hooksecurefunc) ~= "function" then
        return
    end

    if type(ChatEdit_InsertLink) == "function" then
        hooksecurefunc("ChatEdit_InsertLink", applyItemLinkFromClick)
    end
    if type(HandleModifiedItemClick) == "function" then
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if IsModifiedClick and IsModifiedClick("CHATLINK") then
                applyItemLinkFromClick(link)
            end
        end)
    end
end

local function buildPanel()
    buildFrame()
    buildControls()
    buildFooter()
    hookItemLinks()

    panel:SetScript("OnShow", function()
        FWR:RefreshAdvisorPanel()
    end)

    local elapsedSinceStatus = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceStatus = elapsedSinceStatus + elapsed
        if elapsedSinceStatus >= 1 then
            elapsedSinceStatus = 0
            refreshScanStatus()
        end
    end)

    return panel
end

-- Item data arrives in bursts; refresh once after it settles.
local itemInfoRefreshPending = false

function FWR:HandleItemInfoReceived()
    if itemInfoRefreshPending or not panel or not panel:IsShown() then
        return
    end

    itemInfoRefreshPending = true
    C_Timer.After(0.5, function()
        itemInfoRefreshPending = false
        FWR:RefreshAdvisorPanel()
    end)
end

function FWR:ToggleAdvisorPanel()
    if not panel then
        buildPanel()
    end
    if panel:IsShown() then
        panel:Hide()
    else
        mode = MODE_GOLD -- the Advisor always opens on Gold
        panel:Show()
    end
end
