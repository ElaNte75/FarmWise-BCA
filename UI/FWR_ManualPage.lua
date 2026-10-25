local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- The Manual page of the control panel: a list of chapters, and the text of the chapter that was chosen.
-- The window shows a "Back" button next to "Close" while a chapter is open (see FWR_ControlPanelWindow.lua).
-- The text is in FWR_ManualContent.lua.

local GOLD = { 0.95, 0.82, 0.42 }
local ROW_HEIGHT = 46

-- A text with lines that start with "# " (small titles) turned into the colours the manual uses.
local function decorate(body)
    local lines = {}
    for line in string.gmatch((body or "") .. "\n", "(.-)\n") do
        local shown = line
        if string.sub(line, 1, 2) == "# " then
            shown = "|cffffd100" .. string.sub(line, 3) .. "|r"
        end
        lines[#lines + 1] = shown
    end
    return table.concat(lines, "\n")
end

-- parent: the page area; frame: the control panel window (it owns the Back button).
function FWR.CreateManualPage(parent, frame)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    local chapters = FWR.ManualChapters or {}

    local function section(host, title)
        local label = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -2)
        label:SetJustifyH("LEFT")
        label:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
        label:SetText(title)
        local line = host:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
        line:SetPoint("RIGHT", host, "RIGHT", -4, 0)
        line:SetHeight(1)
        line:SetColorTexture(0.85, 0.65, 0.15, 0.35)
        return label, line
    end

    ----------------------------------------------------------
    -- the list of chapters
    ----------------------------------------------------------
    local home = CreateFrame("Frame", nil, page)
    home:SetAllPoints(page)

    local _, homeLine = section(home, "Manual")

    local intro = home:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", homeLine, "BOTTOMLEFT", 0, -6)
    intro:SetPoint("RIGHT", home, "RIGHT", -8, 0)
    intro:SetJustifyH("LEFT")
    intro:SetTextColor(0.72, 0.72, 0.72, 1)
    intro:SetText("Choose a chapter to read how that part of FarmWise works.")

    local previous = intro
    local buttons = {}
    for index, chapter in ipairs(chapters) do
        local button = CreateFrame("Button", nil, home)
        button:SetHeight(ROW_HEIGHT)
        button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, index == 1 and -10 or 0)
        button:SetPoint("RIGHT", home, "RIGHT", -4, 0)

        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints()
        button.highlight:SetColorTexture(1, 1, 1, 0.06)

        button.title = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        button.title:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -7)
        button.title:SetJustifyH("LEFT")
        button.title:SetText(string.format("%d.  %s", index, chapter.title))
        button.title:SetTextColor(1, 1, 1, 1)

        button.summary = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.summary:SetPoint("TOPLEFT", button.title, "BOTTOMLEFT", 20, -3)
        button.summary:SetPoint("RIGHT", button, "RIGHT", -8, 0)
        button.summary:SetJustifyH("LEFT")
        button.summary:SetWordWrap(false)
        button.summary:SetTextColor(0.72, 0.72, 0.72, 1)
        button.summary:SetText(chapter.summary or "")

        local rule = button:CreateTexture(nil, "ARTWORK")
        rule:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        rule:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        rule:SetHeight(1)
        rule:SetColorTexture(1, 1, 1, 0.07)

        button:SetScript("OnEnter", function(self)
            self.title:SetTextColor(1, 0.82, 0, 1)
        end)
        button:SetScript("OnLeave", function(self)
            self.title:SetTextColor(1, 1, 1, 1)
        end)
        button:SetScript("OnClick", function()
            page:ShowChapter(index)
        end)

        buttons[index] = button
        previous = button
    end

    ----------------------------------------------------------
    -- a chapter
    ----------------------------------------------------------
    local reader = CreateFrame("Frame", nil, page)
    reader:SetAllPoints(page)
    reader:Hide()

    local chapterTitle = reader:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    chapterTitle:SetPoint("TOPLEFT", reader, "TOPLEFT", 0, -2)
    chapterTitle:SetJustifyH("LEFT")
    chapterTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)

    local chapterLine = reader:CreateTexture(nil, "ARTWORK")
    chapterLine:SetPoint("TOPLEFT", chapterTitle, "BOTTOMLEFT", 0, -4)
    chapterLine:SetPoint("RIGHT", reader, "RIGHT", -4, 0)
    chapterLine:SetHeight(1)
    chapterLine:SetColorTexture(0.85, 0.65, 0.15, 0.35)

    local body = reader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", chapterLine, "BOTTOMLEFT", 0, -12)
    body:SetPoint("RIGHT", reader, "RIGHT", -8, 0)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(3)

    -- the scroll frame around the page measures its content again, from the top
    local function measureAgain()
        local scroll = parent:GetParent()
        C_Timer.After(0, function()
            if scroll and scroll.FWRMeasure then
                scroll.FWRMeasure()
            end
            if scroll and scroll.SetVerticalScroll then
                scroll:SetVerticalScroll(0)
            end
        end)
    end

    function page:ShowHome()
        frame.ManualChapter = nil
        reader:Hide()
        home:Show()
        if frame.UpdateBackButton then
            frame:UpdateBackButton()
        end
        measureAgain()
    end

    function page:ShowChapter(index)
        local chapter = chapters[index]
        if not chapter then
            return
        end
        frame.ManualChapter = index
        chapterTitle:SetText(chapter.title)
        body:SetText(decorate(chapter.body))
        home:Hide()
        reader:Show()
        if frame.UpdateBackButton then
            frame:UpdateBackButton()
        end
        measureAgain()
    end

    -- the page is always opened on the list of chapters
    page:SetScript("OnShow", function()
        if not frame.ManualChapter then
            home:Show()
            reader:Hide()
        end
    end)

    return page
end
