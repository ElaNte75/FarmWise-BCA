local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local CONTROL_PANEL_CONFIG = (FWR.UI_CONFIG and FWR.UI_CONFIG.ControlPanelWindow) or {}
local WINDOW_CONFIG = CONTROL_PANEL_CONFIG.window or {}
local COLOR_CONFIG = CONTROL_PANEL_CONFIG.colors or {}
local HEADER_CONFIG = CONTROL_PANEL_CONFIG.header or {}
local FOOTER_CONFIG = CONTROL_PANEL_CONFIG.footer or {}
local CATEGORY_CONFIG = CONTROL_PANEL_CONFIG.categories or {}
local PAGE_CONFIG = CONTROL_PANEL_CONFIG.pages or {}

local WINDOW_WIDTH = WINDOW_CONFIG.width or 590
local WINDOW_HEIGHT = WINDOW_CONFIG.height or 370
local SIDEBAR_WIDTH = WINDOW_CONFIG.sidebarWidth or 150
local FOOTER_HEIGHT = WINDOW_CONFIG.footerHeight or 52
local HEADER_HEIGHT = WINDOW_CONFIG.headerHeight or 56
local CONTENT_PADDING = WINDOW_CONFIG.contentPadding or 18

local DISPLAY_PAGE_CONFIG = PAGE_CONFIG.display or {}
local DISPLAY_CONTROL_ENTRIES = DISPLAY_PAGE_CONFIG.controls or {}

local CATEGORY_ORDER = CATEGORY_CONFIG.order or {}

local INTERFACE_PAGE_CONFIG = PAGE_CONFIG.interface or {}
local INTERFACE_OPTIONS = INTERFACE_PAGE_CONFIG.options or {}

local TRACKING_PAGE_CONFIG = PAGE_CONFIG.tracking or {}
local TRACKING_OPTIONS = TRACKING_PAGE_CONFIG.options or {}

local CATEGORY_NOTES = CATEGORY_CONFIG.notes or {}

local CLEAR_ALL_DATA_POPUP_KEY = "FWR_CONTROL_PANEL_CLEAR_ALL_DATA"

local ENGINE_PAGE_CONFIG = PAGE_CONFIG.engine or {}
local ENGINE_RARITY_LEVEL_VALUES = ENGINE_PAGE_CONFIG.rarityLevels or {}

local function formatQuarterHourLabel(totalMinutes)
    totalMinutes = math.max(0, math.min(1435, math.floor((tonumber(totalMinutes) or 0) / 15 + 0.5) * 15))
    local hours = math.floor(totalMinutes / 60)
    local minutes = totalMinutes % 60
    return string.format("%02d:%02d", hours, minutes)
end

local function getIndexedValueIndex(entries, currentValue, defaultIndex)
    if type(entries) ~= "table" then
        return defaultIndex or 1
    end
    for index, entry in ipairs(entries) do
        if entry.value == currentValue then
            return index
        end
    end
    return defaultIndex or 1
end

local function createBorderLine(parent, point, relativeTo, relativePoint, xOfs, yOfs, width, height, r, g, b, a)
    local line = parent:CreateTexture(nil, "BORDER")
    line:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)
    line:SetSize(width, height)
    line:SetColorTexture(r or 1, g or 1, b or 1, a or 0.14)
    return line
end


local function ensureClearAllDataPopup()
    StaticPopupDialogs = StaticPopupDialogs or {}
    if StaticPopupDialogs[CLEAR_ALL_DATA_POPUP_KEY] then
        return
    end

    StaticPopupDialogs[CLEAR_ALL_DATA_POPUP_KEY] = {
        text = "Erase ALL FarmWise saved data?\n\nThis also deletes the statistics the Advisor uses. This cannot be undone.",
        button1 = YES,
        button2 = CANCEL,
        OnAccept = function()
            if FWR and FWR.ClearAllSavedData then
                FWR:ClearAllSavedData()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = STATICPOPUP_NUMDIALOGS,
    }
end

local function getBooleanSetting(path, defaultValue)
    local settings = FWR and FWR.Settings or nil
    local current = settings

    if type(path) == "string" then
        path = { "ui", path }
    end

    if type(path) ~= "table" then
        return defaultValue == true
    end

    for _, key in ipairs(path) do
        if type(current) ~= "table" then
            current = nil
            break
        end
        current = current[key]
    end

    if current == nil then
        return defaultValue == true
    end

    return current == true
end

local function setBooleanSetting(path, value)
    if type(path) == "string" then
        path = { "ui", path }
    end

    if type(path) ~= "table" or #path == 0 then
        return
    end

    FWR.Settings = FWR.Settings or {}
    local current = FWR.Settings
    for index = 1, #path - 1 do
        local key = path[index]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end

    current[path[#path]] = value == true

    if FWR.TouchDatabase then
        FWR:TouchDatabase()
    end
end

local function getNumberSetting(path, defaultValue)
    local settings = FWR and FWR.Settings or nil
    local current = settings

    if type(path) ~= "table" then
        return tonumber(defaultValue) or 0
    end

    for _, key in ipairs(path) do
        if type(current) ~= "table" then
            current = nil
            break
        end
        current = current[key]
    end

    current = tonumber(current)
    if current == nil then
        current = tonumber(defaultValue) or 0
    end

    return current
end

local function setNumberSetting(path, value)
    if type(path) ~= "table" or #path == 0 then
        return
    end

    FWR.Settings = FWR.Settings or {}
    local current = FWR.Settings
    for index = 1, #path - 1 do
        local key = path[index]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end

    current[path[#path]] = tonumber(value) or 0

    if FWR.TouchDatabase then
        FWR:TouchDatabase()
    end
end

local function setValueSetting(path, value)
    if type(path) ~= "table" or #path == 0 then
        return
    end

    FWR.Settings = FWR.Settings or {}
    local current = FWR.Settings
    for index = 1, #path - 1 do
        local key = path[index]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end

    current[path[#path]] = value

    if FWR.TouchDatabase then
        FWR:TouchDatabase()
    end
end

local function updateCheckboxVisual(check)
    if not check or not check.Text then
        return
    end

    if check:IsEnabled() then
        check:SetAlpha(1)
        if check:GetChecked() then
            check.Text:SetTextColor(1.0, 0.82, 0.0, 1.0)
        else
            check.Text:SetTextColor(0.82, 0.82, 0.82, 1.0)
        end
    else
        check:SetAlpha(0.45)
        check.Text:SetTextColor(0.55, 0.55, 0.55, 1.0)
    end
end

-- Shows an explanation next to a checkbox while the mouse is over it.
local function attachTooltip(frame, title, text)
    if not frame or type(text) ~= "string" or text == "" then
        return
    end

    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title or "", 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- ===== Layout of the pages =====
-- A page is a column of sections: a small gold title with a thin line under it, then what belongs to it.
-- A page that is taller than the window scrolls (the scrollbar is there only when it is needed).

local PAGE_CONTENT_WIDTH = WINDOW_WIDTH - SIDEBAR_WIDTH - 2 * CONTENT_PADDING - 26

-- The distances every page uses, so all of them look made by the same hand (pixels, downwards).
local GAP_AFTER_LINE = 8      -- the line of a section title -> the first checkbox
local GAP_AFTER_NOTE = 12     -- a note or a small title -> the first checkbox under it
local GAP_NEXT_CHECK = -2     -- a checkbox -> the next one (the boxes are 26 high: this makes 24 per row)
local GAP_SECTION = 20        -- the last thing of a section -> the title of the next section

-- The title of a section. anchor = what it goes under (nil: the top of the page). Returns the line under the
-- title: whatever belongs to the section is anchored to it.
local function createSection(page, title, anchor, gap)
    local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if anchor then
        label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or GAP_SECTION))
    else
        label:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -2)
    end
    label:SetJustifyH("LEFT")
    label:SetTextColor(0.95, 0.82, 0.42, 1)
    label:SetText(title or "")

    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    line:SetPoint("RIGHT", page, "RIGHT", -4, 0)
    line:SetHeight(1)
    line:SetColorTexture(0.85, 0.65, 0.15, 0.35)
    return line, label
end

-- A short explanation in small grey text, wrapped inside the page.
local function createNote(page, text, anchor, offsetX, gap)
    local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", offsetX or 0, -(gap or 6))
    note:SetPoint("RIGHT", page, "RIGHT", -8, 0)
    note:SetJustifyH("LEFT")
    note:SetJustifyV("TOP")
    note:SetTextColor(0.72, 0.72, 0.72, 1)
    note:SetText(text or "")
    return note
end

-- Puts a page inside a scroll frame. createFn(content, ...) builds the page; the scroll frame is what
-- the window shows and hides, and its .Page is the page itself.
local function createScrollPage(parent, createFn, ...)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -24, 0)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PAGE_CONTENT_WIDTH, 10)
    scroll:SetScrollChild(content)

    local page = createFn(content, ...)
    scroll.Page = page

    -- the height of the page is where its lowest part ends
    local function measure()
        local top = content:GetTop()
        if not top then
            return
        end
        local lowest = top
        local function consider(object)
            if object.IsShown and not object:IsShown() then
                return
            end
            local bottom = object:GetBottom()
            if bottom and bottom < lowest then
                lowest = bottom
            end
        end
        for _, region in ipairs({ page:GetRegions() }) do
            consider(region)
        end
        for _, child in ipairs({ page:GetChildren() }) do
            consider(child)
        end

        local needed = top - lowest + 14
        local viewport = scroll:GetHeight() or 0
        content:SetHeight(math.max(needed, viewport, 10))
        local bar = scroll.ScrollBar
        if bar then
            bar:SetShown(needed > viewport + 1)
        end
        if needed <= viewport + 1 then
            scroll:SetVerticalScroll(0)
        end
    end
    scroll.FWRMeasure = measure
    scroll:HookScript("OnShow", function()
        measure()
        C_Timer.After(0, measure)
    end)

    return scroll
end

local function createCategoryButton(parent, label)
    local navButtonConfig = CATEGORY_CONFIG.button or {}
    local navTextColor = COLOR_CONFIG.navText or { 0.96, 0.96, 0.96, 1.0 }
    local navSelectedTextColor = COLOR_CONFIG.navSelectedText or { 1.0, 0.90, 0.55, 1.0 }
    local navSelectedBg = COLOR_CONFIG.navSelectedBg or { 1.0, 0.82, 0.02, 0.12 }
    local navHighlightBg = COLOR_CONFIG.navHighlightBg or { 1.0, 1.0, 1.0, 0.05 }

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(navButtonConfig.width or (SIDEBAR_WIDTH - 24), navButtonConfig.height or 28)

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetColorTexture(1, 0.82, 0.02, 0.0)

    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetColorTexture(unpack(navHighlightBg))

    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    button.text:SetPoint("LEFT", navButtonConfig.textX or 10, 0)
    button.text:SetJustifyH("LEFT")
    button.text:SetText(label)
    button.text:SetTextColor(unpack(navTextColor))

    function button:SetSelected(isSelected)
        if isSelected then
            self.bg:SetColorTexture(unpack(navSelectedBg))
            self.text:SetTextColor(unpack(navSelectedTextColor))
        else
            self.bg:SetColorTexture(1, 0.82, 0.02, 0.0)
            self.text:SetTextColor(unpack(navTextColor))
        end
    end

    button:SetSelected(false)
    return button
end

local function refreshInterfaceDependencies(frame)
    if not frame or not frame.InterfaceControls then
        return
    end

    local controls = frame.InterfaceControls
    local showOnLoadCheck = controls.showMainWindowOnGameLoad
    local hideMainFrameCheck = controls.hideMainWindowInCombat
    local hidePanelsCheck = controls.hideControlPanelsInCombat
    local restoreCheck = controls.restoreControlPanelsAfterCombat

    if showOnLoadCheck then
        showOnLoadCheck:Enable()
        updateCheckboxVisual(showOnLoadCheck)
    end

    if hideMainFrameCheck then
        hideMainFrameCheck:Enable()
        updateCheckboxVisual(hideMainFrameCheck)
    end

    -- "Open it again after combat" follows "Minimize the main window during combat"
    local restoreMainCheck = controls.restoreMainWindowAfterCombat
    if hideMainFrameCheck and restoreMainCheck then
        if hideMainFrameCheck:GetChecked() then
            restoreMainCheck:Enable()
        else
            restoreMainCheck:SetChecked(false)
            setBooleanSetting("restoreMainWindowAfterCombat", false)
            restoreMainCheck:Disable()
        end
        updateCheckboxVisual(restoreMainCheck)
    end

    -- the loot text: its alert and the value of the alert follow it, the value also follows the alert
    local floatCheck = controls.floatLootText
    local alertCheck = controls.lootAlertSound
    local alertSlider = controls.lootAlertSlider
    if floatCheck and alertCheck then
        if floatCheck:GetChecked() then
            alertCheck:Enable()
        else
            alertCheck:Disable()
        end
        updateCheckboxVisual(alertCheck)
        if alertSlider then
            local on = floatCheck:GetChecked() == true and alertCheck:GetChecked() == true
            alertSlider:SetEnabled(on)
            alertSlider:SetAlpha(on and 1 or 0.45)
            if controls.lootAlertTitle then
                controls.lootAlertTitle:SetAlpha(on and 1 or 0.45)
            end
        end
    end

    if hidePanelsCheck and restoreCheck then
        if hidePanelsCheck:GetChecked() then
            restoreCheck:Enable()
        else
            restoreCheck:SetChecked(false)
            setBooleanSetting("restoreControlPanelsAfterCombat", false)
            restoreCheck:Disable()
        end
        updateCheckboxVisual(hidePanelsCheck)
        updateCheckboxVisual(restoreCheck)
    end
end

local function updateDisplayCheckboxVisual(check, isLocked, isEnabled)
    if not check then
        return
    end

    if isLocked then
        check:SetAlpha(0.75)
        if check.Text then
            check.Text:SetTextColor(1.0, 0.82, 0.0, 0.9)
        end
        return
    end

    if isEnabled then
        check:SetAlpha(1)
        if check.Text then
            check.Text:SetTextColor(1.0, 0.82, 0.0, 1.0)
        end
    else
        check:SetAlpha(0.55)
        if check.Text then
            check.Text:SetTextColor(0.55, 0.55, 0.55, 1)
        end
    end
end

local function createDisplayPage(parent, frame)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    local displayConfig = PAGE_CONFIG.display or {}
    local rowSliderConfig = displayConfig.rowSlider or {}
    local transparencyConfig = displayConfig.transparencySlider or {}
    local dividerConfig = displayConfig.divider or {}
    local headerConfig = displayConfig.headers or {}
    local scrollConfig = displayConfig.scroll or {}
    local listConfig = displayConfig.list or {}
    local checkboxConfig = displayConfig.checkbox or listConfig.checkbox or {
        startX = listConfig.checkboxX or 0,
        startY = listConfig.startY or -8,
        spacing = listConfig.spacing or 6,
        textOffsetX = listConfig.textOffsetX or 0,
        textOffsetY = listConfig.textOffsetY or 1,
    }

    local visibleRowsTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    visibleRowsTitle:SetPoint("TOPLEFT", rowSliderConfig.titleX or 0, rowSliderConfig.titleY or -2)
    visibleRowsTitle:SetJustifyH("LEFT")
    visibleRowsTitle:SetTextColor(1, 1, 1, 1)
    visibleRowsTitle:SetText(rowSliderConfig.title or "Set Visible Rows")

    local rowSlider = CreateFrame("Slider", nil, page, "OptionsSliderTemplate")
    rowSlider:SetPoint("TOPLEFT", rowSliderConfig.sliderX or 180, rowSliderConfig.sliderY or -4)
    rowSlider:SetWidth(rowSliderConfig.sliderWidth or 140)
    rowSlider:SetMinMaxValues(rowSliderConfig.min or 5, rowSliderConfig.max or 20)
    rowSlider:SetValueStep(1)
    rowSlider:SetObeyStepOnDrag(true)
    rowSlider:SetOrientation("HORIZONTAL")
    rowSlider:SetStepsPerPage(1)
    rowSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if rowSlider.Text then rowSlider.Text:SetText("") end
    if rowSlider.Low then
        rowSlider.Low:ClearAllPoints()
        rowSlider.Low:SetPoint("RIGHT", rowSlider, "LEFT", rowSliderConfig.lowOffsetX or -2, 0)
        rowSlider.Low:SetText(rowSliderConfig.low or "5")
    end
    if rowSlider.High then
        rowSlider.High:ClearAllPoints()
        rowSlider.High:SetPoint("LEFT", rowSlider, "RIGHT", rowSliderConfig.highOffsetX or 2, 0)
        rowSlider.High:SetText(rowSliderConfig.high or "20")
    end

    local transparencyTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    transparencyTitle:SetPoint("TOPLEFT", transparencyConfig.titleX or 0, transparencyConfig.titleY or -26)
    transparencyTitle:SetJustifyH("LEFT")
    transparencyTitle:SetTextColor(1, 1, 1, 1)
    transparencyTitle:SetText(transparencyConfig.title or "Set Transparency")

    local transparencySlider = CreateFrame("Slider", nil, page, "OptionsSliderTemplate")
    transparencySlider:SetPoint("TOPLEFT", transparencyConfig.sliderX or 180, transparencyConfig.sliderY or -28)
    transparencySlider:SetWidth(transparencyConfig.sliderWidth or 140)
    transparencySlider:SetMinMaxValues(transparencyConfig.min or 0, transparencyConfig.max or 100)
    transparencySlider:SetValueStep(1)
    transparencySlider:SetObeyStepOnDrag(true)
    transparencySlider:SetOrientation("HORIZONTAL")
    transparencySlider:SetStepsPerPage(1)
    transparencySlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if transparencySlider.Text then transparencySlider.Text:SetText("") end
    if transparencySlider.Low then
        transparencySlider.Low:ClearAllPoints()
        transparencySlider.Low:SetPoint("RIGHT", transparencySlider, "LEFT", transparencyConfig.lowOffsetX or -2, 0)
        transparencySlider.Low:SetText(transparencyConfig.low or "0")
    end
    if transparencySlider.High then
        transparencySlider.High:ClearAllPoints()
        transparencySlider.High:SetPoint("LEFT", transparencySlider, "RIGHT", transparencyConfig.highOffsetX or 2, 0)
        transparencySlider.High:SetText(transparencyConfig.high or "100")
    end

    local divider = page:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(unpack(dividerConfig.color or { 1, 1, 1, 0.18 }))
    divider:SetPoint("TOPLEFT", dividerConfig.x or 0, dividerConfig.y or -64)
    divider:SetPoint("TOPRIGHT", -(dividerConfig.rightInset or 18), dividerConfig.y or -64)
    divider:SetHeight(dividerConfig.height or 1)

    local visibilityHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    visibilityHeader:SetPoint("TOPLEFT", (headerConfig.visibility and headerConfig.visibility.x) or 0, (headerConfig.visibility and headerConfig.visibility.y) or -80)
    visibilityHeader:SetTextColor(0.95, 0.82, 0.42, 1)
    visibilityHeader:SetText((headerConfig.visibility and headerConfig.visibility.text) or "Enable / Disable Columns")

    local orderHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    orderHeader:SetPoint("TOPLEFT", (headerConfig.order and headerConfig.order.x) or 180, (headerConfig.order and headerConfig.order.y) or -80)
    orderHeader:SetTextColor(0.95, 0.82, 0.42, 1)
    orderHeader:SetText((headerConfig.order and headerConfig.order.text) or "Reorder Columns")

    local scrollFrame = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", scrollConfig.left or 0, scrollConfig.top or -102)
    scrollFrame:SetPoint("BOTTOMRIGHT", scrollConfig.right or -24, scrollConfig.bottom or 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)
    page.ScrollFrame = scrollFrame
    page.ScrollChild = scrollChild
    page.DisplayControls = {}

    local function refreshDisplayControls()
        if FWR.NormalizeDisplayColumnSettings then
            FWR:NormalizeDisplayColumnSettings()
        end

        local visibleRowsValue = math.max(5, math.min(20, getNumberSetting({ "display", "visibleRows" }, 5)))
        visibleRowsTitle:SetText(string.format("Set Visible Rows (%d)", visibleRowsValue))
        rowSlider.__fwrRefreshing = true
        rowSlider:SetValue(visibleRowsValue)
        rowSlider.__fwrPendingVisibleRowsValue = visibleRowsValue
        rowSlider.__fwrRefreshing = nil

        local transparencyValue = math.max(0, math.min(100, getNumberSetting({ "display", "frameTransparency" }, 50)))
        transparencyTitle:SetText(string.format("Set Transparency (%d%%)", transparencyValue))
        transparencySlider.__fwrRefreshing = true
        transparencySlider:SetValue(transparencyValue)
        transparencySlider.__fwrPendingTransparencyValue = transparencyValue
        transparencySlider.__fwrRefreshing = nil

        local enabledCount = FWR.GetEnabledReorderableMainColumnCount and FWR:GetEnabledReorderableMainColumnCount() or 0
        local enabledMaxPosition = math.max(2, enabledCount + 1)

        for _, entry in ipairs(displayConfig.controls or DISPLAY_CONTROL_ENTRIES) do
            local widgets = page.DisplayControls[entry.key]
            if widgets then
                local isLocked = entry.locked == true
                local enabled = isLocked and true or getBooleanSetting({ "display", "optionalColumns", entry.key }, entry.defaultValue)
                local defaultOrderValue = widgets.defaultOrderValue or entry.fixedOrder or 1
                local value = getNumberSetting({ "display", "columnOrder", entry.key }, defaultOrderValue)
                local orderSuffix = ""
                if not isLocked then
                    orderSuffix = enabled and string.format(" (%d)", math.floor(value or defaultOrderValue or 0)) or " (Hidden)"
                end
                if widgets.check and widgets.check.Text then
                    widgets.check:SetChecked(enabled)
                    widgets.check.Text:SetText((entry.label or "") .. orderSuffix)
                    updateDisplayCheckboxVisual(widgets.check, isLocked, enabled)
                end
                if widgets.slider then
                    local sliderMin = 2
                    local sliderMax = enabledMaxPosition
                    local sliderValue = enabled and math.max(sliderMin, math.min(sliderMax, value)) or sliderMax
                    widgets.slider.__fwrRefreshing = true
                    widgets.slider:SetMinMaxValues(sliderMin, sliderMax)
                    if widgets.slider.Low then widgets.slider.Low:SetText(tostring(sliderMin)) end
                    if widgets.slider.High then widgets.slider.High:SetText(tostring(sliderMax)) end
                    widgets.slider:SetValue(sliderValue)
                    widgets.slider.__fwrRefreshing = nil
                    local thumb = widgets.slider.GetThumbTexture and widgets.slider:GetThumbTexture() or nil
                    if isLocked or not enabled then
                        widgets.slider:Disable()
                        if thumb and thumb.SetAlpha then thumb:SetAlpha(0) end
                    else
                        widgets.slider:Enable()
                        if thumb and thumb.SetAlpha then thumb:SetAlpha(1) end
                    end
                end
            end
        end
    end

    local function applyDisplayRefresh()
        if FWR.ApplyDisplaySettings then
            FWR:ApplyDisplaySettings()
        end
        if FWR.RefreshDisplayText then
            FWR:RefreshDisplayText()
            if FWR.RefreshDisplayLiveMetrics then
                FWR:RefreshDisplayLiveMetrics(true)
            end
        end
    end

    local function handleSliderValueChanged(changedKey, requestedValue)
        if not changedKey or not FWR.NormalizeDisplayColumnSettings then
            return
        end

        local display = FWR:NormalizeDisplayColumnSettings()
        local orderMap = display.columnOrder or {}
        local currentOrder = FWR.GetOrderedMainColumnKeys and FWR:GetOrderedMainColumnKeys() or nil
        if type(currentOrder) ~= "table" then
            return
        end

        local reorderable = {}
        for _, key in ipairs(currentOrder) do
            if key ~= "item" and key ~= "quality" then
                reorderable[#reorderable + 1] = key
            end
        end

        local currentIndex
        for index, key in ipairs(reorderable) do
            if key == changedKey then
                currentIndex = index
                break
            end
        end
        if not currentIndex then
            return
        end

        local enabledCount = FWR.GetEnabledReorderableMainColumnCount and FWR:GetEnabledReorderableMainColumnCount() or #reorderable
        local targetIndex = math.max(1, math.min(enabledCount, math.floor((tonumber(requestedValue) or 2) - 1)))
        if targetIndex ~= currentIndex then
            table.remove(reorderable, currentIndex)
            table.insert(reorderable, targetIndex, changedKey)
        end

        for index, key in ipairs(reorderable) do
            orderMap[key] = index + 1
        end

        setNumberSetting({ "display", "columnOrder", changedKey }, orderMap[changedKey])
        refreshDisplayControls()
        applyDisplayRefresh()
    end

    local function commitVisibleRows(value)
        local snapped = math.floor((tonumber(value) or 0) + 0.5)
        local clamped = math.max(5, math.min(20, snapped))
        if getNumberSetting({ "display", "visibleRows" }, 5) == clamped then
            visibleRowsTitle:SetText(string.format("Set Visible Rows (%d)", clamped))
            return
        end
        setNumberSetting({ "display", "visibleRows" }, clamped)
        visibleRowsTitle:SetText(string.format("Set Visible Rows (%d)", clamped))
        applyDisplayRefresh()
    end

    local function commitTransparency(value)
        local snapped = math.floor((tonumber(value) or 0) + 0.5)
        local clamped = math.max(0, math.min(100, snapped))
        if getNumberSetting({ "display", "frameTransparency" }, 50) == clamped then
            transparencyTitle:SetText(string.format("Set Transparency (%d%%)", clamped))
            return
        end
        setNumberSetting({ "display", "frameTransparency" }, clamped)
        transparencyTitle:SetText(string.format("Set Transparency (%d%%)", clamped))
        applyDisplayRefresh()
    end

    rowSlider:SetScript("OnValueChanged", function(self, value)
        local snapped = math.floor((tonumber(value) or 0) + 0.5)
        if math.abs((tonumber(value) or 0) - snapped) > 0.001 then
            self:SetValue(snapped)
            return
        end
        if self.__fwrRefreshing then
            return
        end
        local clamped = math.max(5, math.min(20, snapped))
        self.__fwrPendingVisibleRowsValue = clamped
        visibleRowsTitle:SetText(string.format("Set Visible Rows (%d)", clamped))
    end)
    rowSlider:SetScript("OnMouseUp", function(self)
        commitVisibleRows(self.__fwrPendingVisibleRowsValue or self:GetValue())
    end)
    rowSlider:SetScript("OnHide", function(self)
        commitVisibleRows(self.__fwrPendingVisibleRowsValue or self:GetValue())
    end)

    transparencySlider:SetScript("OnValueChanged", function(self, value)
        local snapped = math.floor((tonumber(value) or 0) + 0.5)
        if math.abs((tonumber(value) or 0) - snapped) > 0.001 then
            self:SetValue(snapped)
            return
        end
        if self.__fwrRefreshing then
            return
        end
        local clamped = math.max(0, math.min(100, snapped))
        self.__fwrPendingTransparencyValue = clamped
        transparencyTitle:SetText(string.format("Set Transparency (%d%%)", clamped))
    end)
    transparencySlider:SetScript("OnMouseUp", function(self)
        commitTransparency(self.__fwrPendingTransparencyValue or self:GetValue())
    end)
    transparencySlider:SetScript("OnHide", function(self)
        commitTransparency(self.__fwrPendingTransparencyValue or self:GetValue())
    end)

    local previous
    for index, entry in ipairs(DISPLAY_CONTROL_ENTRIES) do
        local check = CreateFrame("CheckButton", nil, scrollChild, "InterfaceOptionsCheckButtonTemplate")
        if index == 1 then
            check:SetPoint("TOPLEFT", checkboxConfig.startX or 0, checkboxConfig.startY or -8)
        else
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -GAP_NEXT_CHECK)
        end
        check:SetHitRectInsets(0, 0, 0, 0)
        if check.Text then
            check.Text:ClearAllPoints()
            check.Text:SetPoint("LEFT", check, "RIGHT", checkboxConfig.textOffsetX or 0, checkboxConfig.textOffsetY or 1)
            check.Text:SetJustifyH("LEFT")
            check.Text:SetText(entry.label or "")
        end
        attachTooltip(check, entry.label, entry.tooltip)

        if entry.locked then
            check:SetChecked(true)
            check:Disable()
            updateDisplayCheckboxVisual(check, true, true)
        else
            check:SetChecked(getBooleanSetting({ "display", "optionalColumns", entry.key }, entry.defaultValue))
            updateDisplayCheckboxVisual(check, false, check:GetChecked() == true)
            check:SetScript("OnClick", function(self)
                local checked = self:GetChecked() == true
                if FWR.SetOptionalMainColumnEnabled then
                    FWR:SetOptionalMainColumnEnabled(entry.key, checked)
                else
                    setBooleanSetting({ "display", "optionalColumns", entry.key }, checked)
                    if FWR.NormalizeDisplayColumnSettings then
                        FWR:NormalizeDisplayColumnSettings()
                    end
                end
                refreshDisplayControls()
                applyDisplayRefresh()
            end)
        end

        local slider
        if not entry.locked then
            slider = CreateFrame("Slider", nil, scrollChild, "OptionsSliderTemplate")
            slider:SetPoint("LEFT", 180, 0)
            slider:SetPoint("TOP", check, "TOP", 0, -4)
            slider:SetWidth(150)
            slider:SetMinMaxValues(2, math.max(2, #DISPLAY_CONTROL_ENTRIES))
            slider:SetValueStep(1)
            slider:SetObeyStepOnDrag(true)
            slider:SetOrientation("HORIZONTAL")
            slider:SetStepsPerPage(1)
            slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
            if slider.Text then slider.Text:SetText("") end
            if slider.Low then
                slider.Low:ClearAllPoints()
                slider.Low:SetPoint("RIGHT", slider, "LEFT", listConfig.lowOffsetX or -2, 0)
                slider.Low:SetText("2")
            end
            if slider.High then
                slider.High:ClearAllPoints()
                slider.High:SetPoint("LEFT", slider, "RIGHT", listConfig.highOffsetX or 2, 0)
                slider.High:SetText(tostring(math.max(2, #DISPLAY_CONTROL_ENTRIES)))
            end
            slider:SetScript("OnValueChanged", function(self, value)
                local snapped = math.floor((tonumber(value) or 0) + 0.5)
                if math.abs((tonumber(value) or 0) - snapped) > 0.001 then
                    self:SetValue(snapped)
                    return
                end
                if self.__fwrRefreshing then
                    return
                end
                if self:IsEnabled() then
                    handleSliderValueChanged(entry.key, snapped)
                end
            end)
        end

        page.DisplayControls[entry.key] = {
            check = check,
            slider = slider,
            defaultOrderValue = entry.fixedOrder or math.max(2, index),
        }

        previous = check
    end

    local childHeight = math.max(240, (#DISPLAY_CONTROL_ENTRIES * 24) + 20)
    scrollChild:SetSize(420, childHeight)

    page.RefreshDisplayControls = refreshDisplayControls
    page:SetScript("OnShow", function(self)
        if self.RefreshDisplayControls then
            self:RefreshDisplayControls()
        end
    end)
    page:RefreshDisplayControls()

    return page
end

local function createInterfacePage(parent, frame)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    local interfaceConfig = PAGE_CONFIG.interface or {}
    local checkboxConfig = interfaceConfig.checkbox or {}
    page.InterfaceControls = {}

    local sectionTitles = {}
    for _, section in ipairs(interfaceConfig.sections or {}) do
        sectionTitles[section.key] = section.title
    end

    local previous
    local currentSection
    local afterTitle
    for index, option in ipairs(INTERFACE_OPTIONS) do
        local check = CreateFrame("CheckButton", nil, page, "InterfaceOptionsCheckButtonTemplate")
        check:SetHitRectInsets(0, 0, 0, 0)

        if option.section ~= currentSection then
            currentSection = option.section
            previous = createSection(page, sectionTitles[currentSection] or "", previous)
            afterTitle = true
        end
        if afterTitle then
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -GAP_AFTER_LINE)
            afterTitle = false
        else
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -GAP_NEXT_CHECK)
        end

        if check.Text then
            check.Text:ClearAllPoints()
            check.Text:SetPoint("LEFT", check, "RIGHT", checkboxConfig.textOffsetX or 0, checkboxConfig.textOffsetY or 1)
            check.Text:SetJustifyH("LEFT")
            check.Text:SetText(option.label)
        end

        check:SetChecked(getBooleanSetting(option.key, option.defaultValue))
        updateCheckboxVisual(check)
        attachTooltip(check, option.label, option.tooltip)
        check:SetScript("OnClick", function(self)
            local checked = self:GetChecked() == true
            setBooleanSetting(option.key, checked)
            updateCheckboxVisual(self)
            refreshInterfaceDependencies(frame)
            if option.key == "keepColumnWidths" and not checked and FWR.ResetColumnWidthMemory then
                FWR:ResetColumnWidthMemory()
            end
            if FWR.RestartMainWindowAutoLock then
                FWR:RestartMainWindowAutoLock()
            end
            if FWR.ApplySettingsVisibilityRules then
                FWR:ApplySettingsVisibilityRules(true)
            end
        end)

        page.InterfaceControls[option.key] = check
        previous = check

        -- under the sound: the value from which a loot is "valuable" (bigger letters, and the sound), a slider
        if option.key == "lootAlertSound" then
            local spacer = CreateFrame("Frame", nil, page)
            spacer:SetSize(1, 54)
            spacer:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 0, -4)

            local alertTitle = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            alertTitle:SetPoint("TOPLEFT", spacer, "TOPLEFT", 4, 0)

            local alertSlider = CreateFrame("Slider", nil, page, "OptionsSliderTemplate")
            alertSlider:SetPoint("TOPLEFT", alertTitle, "BOTTOMLEFT", 0, -10)
            alertSlider:SetWidth(240)
            alertSlider:SetOrientation("HORIZONTAL")
            alertSlider:SetMinMaxValues(10, 1000)
            alertSlider:SetValueStep(10)
            alertSlider:SetObeyStepOnDrag(true)
            alertSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
            if alertSlider.Text then alertSlider.Text:SetText("") end
            if alertSlider.Low then alertSlider.Low:SetText("10g") end
            if alertSlider.High then alertSlider.High:SetText("1000g") end

            local function savedAlertValue()
                local saved = tonumber(((FWR.Settings or {}).ui or {}).lootAlertGold) or 100
                if saved < 10 then
                    saved = 100
                end
                return math.min(1000, saved)
            end
            local function showAlertValue(value)
                alertTitle:SetText(string.format("Valuable loot from: %dg", value))
            end

            alertSlider.__fwrRefreshing = true
            alertSlider:SetValue(savedAlertValue())
            alertSlider.__fwrRefreshing = nil
            showAlertValue(savedAlertValue())

            alertSlider:SetScript("OnValueChanged", function(self, value)
                local snapped = math.max(10, math.min(1000, math.floor((tonumber(value) or 100) / 10 + 0.5) * 10))
                showAlertValue(snapped)
                if self.__fwrRefreshing then
                    return
                end
                setValueSetting({ "ui", "lootAlertGold" }, snapped)
            end)
            page:HookScript("OnShow", function()
                alertSlider.__fwrRefreshing = true
                alertSlider:SetValue(savedAlertValue())
                alertSlider.__fwrRefreshing = nil
                showAlertValue(savedAlertValue())
            end)
            attachTooltip(alertSlider, "Valuable loot", "In the floating loot text (while the window is minimized), a loot that is worth at least this much comes in bigger letters, and with a sound if the sound is on. The worth is the Auction House price of your last scan, or what a vendor pays.")
            page.InterfaceControls.lootAlertSlider = alertSlider
            page.InterfaceControls.lootAlertTitle = alertTitle
            previous = spacer
        end
    end

    -- start again from the smallest column widths
    local resetWidths = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    resetWidths:SetSize(170, 24)
    local layoutLine = createSection(page, sectionTitles.layout or "Window layout", previous)
    resetWidths:SetPoint("TOPLEFT", layoutLine, "BOTTOMLEFT", 4, -GAP_AFTER_NOTE)
    resetWidths:SetText("Reset column widths")
    resetWidths:SetScript("OnClick", function()
        if FWR.ResetColumnWidthMemory then
            FWR:ResetColumnWidthMemory()
        end
    end)
    attachTooltip(resetWidths, "Reset column widths", "Makes every column as narrow as its content again. They then grow only when something needs more room.")

    -- where the minimized window's small button sits: one button that goes through the places
    local CORNERS = {
        { "BOTTOMLEFT", "Bottom left" },
        { "TOPLEFT", "Top left" },
        { "TOPRIGHT", "Top right" },
        { "BOTTOMRIGHT", "Bottom right" },
        { "CENTER", "Center" },
    }
    local cornerButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    cornerButton:SetSize(220, 24)
    cornerButton:SetPoint("TOPLEFT", resetWidths, "BOTTOMLEFT", 0, -8)

    local function currentCornerIndex()
        local saved = ((FWR.Settings or {}).ui or {}).minimizeCorner
        for index, entry in ipairs(CORNERS) do
            if entry[1] == saved then
                return index
            end
        end
        return 1
    end

    local function refreshCornerButton()
        cornerButton:SetText("Minimize to: " .. CORNERS[currentCornerIndex()][2])
    end

    -- both buttons get the width of the longest text either of them can show
    local widest = 0
    local function measureText(text)
        cornerButton:SetText(text)
        widest = math.max(widest, cornerButton:GetFontString():GetStringWidth() or 0)
    end
    measureText("Reset column widths")
    for _, entry in ipairs(CORNERS) do
        measureText("Minimize to: " .. entry[2])
    end
    local sameWidth = math.ceil(widest) + 28
    resetWidths:SetWidth(sameWidth)
    cornerButton:SetWidth(sameWidth)

    cornerButton:SetScript("OnClick", function()
        local nextIndex = currentCornerIndex() % #CORNERS + 1
        setValueSetting({ "ui", "minimizeCorner" }, CORNERS[nextIndex][1])
        refreshCornerButton()
        if FWR.ApplyMainWindowPresentation then
            FWR:ApplyMainWindowPresentation()
        end
    end)
    attachTooltip(cornerButton, "Minimize to", "Where the small FarmWise button appears on the window when you minimize it. Click to go through: bottom left, top left, top right, bottom right, center.")
    page:SetScript("OnShow", refreshCornerButton)
    refreshCornerButton()

    frame.InterfaceControls = page.InterfaceControls
    refreshInterfaceDependencies(frame)

    return page
end

local function refreshTrackingDependencies(page)
    if not page or not page.TrackingControls then
        return
    end

    local showControl = page.TrackingControls.showSpecializedClassifications
    local onlyControl = page.TrackingControls.onlySpecializedClassifications
    local onlyChecked = FWR and FWR.IsOnlySpecializedClassificationVisible and FWR:IsOnlySpecializedClassificationVisible() or false

    if showControl then
        if onlyChecked then
            showControl:SetChecked(false)
            showControl:Disable()
        else
            local showChecked = FWR and FWR.IsSpecializedClassificationVisible and FWR:IsSpecializedClassificationVisible() or false
            showControl:SetChecked(showChecked)
            showControl:Enable()
        end
        updateCheckboxVisual(showControl)
    end

    if onlyControl then
        onlyControl:SetChecked(onlyChecked)
        onlyControl:Enable()
        updateCheckboxVisual(onlyControl)
    end

    local combinedAllChecked = FWR and FWR.IsCombinedAllDataEnabled and FWR:IsCombinedAllDataEnabled() or false
    local combinedCharacterChecked = FWR and FWR.IsCombinedCharacterAllZonesEnabled and FWR:IsCombinedCharacterAllZonesEnabled() or false
    local combinedModeActive = combinedAllChecked or combinedCharacterChecked

    local combinedAllControl = page.TrackingControls.combinedAllData
    local combinedCharacterControl = page.TrackingControls.combinedCharacterAllZones
    local zoneControl = page.TrackingControls.zoneData
    local subZoneControl = page.TrackingControls.subZoneData

    if combinedAllControl then
        combinedAllControl:SetChecked(combinedAllChecked)
        combinedAllControl:Enable()
        updateCheckboxVisual(combinedAllControl)
    end

    if combinedCharacterControl then
        combinedCharacterControl:SetChecked(combinedCharacterChecked)
        combinedCharacterControl:Enable()
        updateCheckboxVisual(combinedCharacterControl)
    end

    if zoneControl then
        local zoneChecked = FWR and FWR.IsZoneDataEnabled and FWR:IsZoneDataEnabled() or false
        if combinedModeActive then
            zoneControl:SetChecked(false)
            zoneControl:Disable()
        else
            zoneControl:SetChecked(zoneChecked)
            zoneControl:Enable()
        end
        updateCheckboxVisual(zoneControl)
    end

    if subZoneControl then
        local subZoneChecked = FWR and FWR.IsSubZoneDataEnabled and FWR:IsSubZoneDataEnabled() or false
        if combinedModeActive then
            subZoneControl:SetChecked(false)
            subZoneControl:Disable()
        else
            subZoneControl:SetChecked(subZoneChecked)
            subZoneControl:Enable()
        end
        updateCheckboxVisual(subZoneControl)
    end

    -- "Count gathering for the whole zone" only matters while the exact sub-zone is shown: it follows that option
    local gatherControl = page.TrackingControls.gatheringWholeZone
    if gatherControl then
        local subZoneOn = FWR and FWR.IsSubZoneDataEnabled and FWR:IsSubZoneDataEnabled() or false
        gatherControl:SetChecked(getBooleanSetting({ "tracking", "gatheringWholeZone" }, true))
        if subZoneOn and not combinedModeActive then
            gatherControl:Enable()
        else
            gatherControl:Disable()
        end
        updateCheckboxVisual(gatherControl)
    end
end

local function createTrackingPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    page.TrackingControls = {}

    local trackingConfig = PAGE_CONFIG.tracking or {}
    local checkboxConfig = trackingConfig.checkbox or {}
    local sectionTitles = {}
    for _, section in ipairs(trackingConfig.sections or {}) do
        sectionTitles[section.key] = section.title
    end

    local previous
    local currentSection
    local afterTitle
    for index, option in ipairs(TRACKING_OPTIONS) do
        local check = CreateFrame("CheckButton", nil, page, "InterfaceOptionsCheckButtonTemplate")
        check:SetHitRectInsets(0, 0, 0, 0)
        if option.section ~= currentSection then
            currentSection = option.section
            previous = createSection(page, sectionTitles[currentSection] or "", previous)
            afterTitle = true
        end
        -- an option that depends on the one above it stands a little further in
        local indent = option.indent or 0
        if afterTitle then
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -GAP_AFTER_LINE)
            afterTitle = false
        elseif indent > 0 then
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", indent, -GAP_NEXT_CHECK)
        else
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -GAP_NEXT_CHECK)
        end

        if check.Text then
            check.Text:ClearAllPoints()
            check.Text:SetPoint("LEFT", check, "RIGHT", checkboxConfig.textOffsetX or 0, checkboxConfig.textOffsetY or 1)
            check.Text:SetJustifyH("LEFT")
            check.Text:SetText(option.label)
        end
        attachTooltip(check, option.label, option.tooltip)

        check:SetScript("OnClick", function(self)
            local checked = self:GetChecked() == true
            if option.key == "combinedAllData" and FWR.SetCombinedAllDataEnabled then
                FWR:SetCombinedAllDataEnabled(checked)
            elseif option.key == "combinedCharacterAllZones" and FWR.SetCombinedCharacterAllZonesEnabled then
                FWR:SetCombinedCharacterAllZonesEnabled(checked)
            elseif option.key == "zoneData" and FWR.SetZoneDataEnabled then
                FWR:SetZoneDataEnabled(checked)
            elseif option.key == "subZoneData" and FWR.SetSubZoneDataEnabled then
                FWR:SetSubZoneDataEnabled(checked)
            elseif option.key == "showSpecializedClassifications" and FWR.SetSpecializedClassificationVisible then
                FWR:SetSpecializedClassificationVisible(checked)
            elseif option.key == "onlySpecializedClassifications" and FWR.SetOnlySpecializedClassificationVisible then
                FWR:SetOnlySpecializedClassificationVisible(checked)
            elseif option.key == "showOldExpansions" and FWR.SetOldExpansionVisible then
                FWR:SetOldExpansionVisible(checked)
            else
                setBooleanSetting(option.settingPath, checked)
            end
            if FWR.ApplyDisplaySettings then
                FWR:ApplyDisplaySettings()
            end
            if FWR.RefreshDisplayText then
                FWR:RefreshDisplayText()
            end
            if page.RefreshTrackingControls then
                page:RefreshTrackingControls()
            end
        end)

        page.TrackingControls[option.key] = check
        previous = check
    end

    function page:RefreshTrackingControls()
        for _, option in ipairs(TRACKING_OPTIONS) do
            local check = self.TrackingControls[option.key]
            if check then
                local checked = getBooleanSetting(option.settingPath, option.defaultValue)
                check:SetChecked(checked)
                updateCheckboxVisual(check)
            end
        end
        refreshTrackingDependencies(self)
    end

    page:SetScript("OnShow", function(self)
        if self.RefreshTrackingControls then
            self:RefreshTrackingControls()
        end
    end)

    page:RefreshTrackingControls()
    return page
end

local function createEnginePage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    local engineConfig = PAGE_CONFIG.engine or {}
    local checkboxConfig = engineConfig.checkbox or {}
    local localResetConfig = engineConfig.localReset or {}
    local rarityConfig = engineConfig.rarity or {}

    local function styleEngineCheck(check, text)
        if not check then return end
        check:SetHitRectInsets(0, 0, 0, 0)
        if check.Text then
            check.Text:ClearAllPoints()
            check.Text:SetPoint("LEFT", check, "RIGHT", checkboxConfig.textOffsetX or 0, checkboxConfig.textOffsetY or 1)
            check.Text:SetJustifyH("LEFT")
            check.Text:SetText(text or "")
        end
    end

    local resetLine = createSection(page, "Session reset")
    local manualCheck = CreateFrame("CheckButton", nil, page, "InterfaceOptionsCheckButtonTemplate")
    manualCheck:SetPoint("TOPLEFT", resetLine, "BOTTOMLEFT", 0, -GAP_AFTER_LINE)
    styleEngineCheck(manualCheck, (engineConfig.manualReset and engineConfig.manualReset.label) or "Manual Session Reset")

    local localCheck = CreateFrame("CheckButton", nil, page, "InterfaceOptionsCheckButtonTemplate")
    localCheck:SetPoint("TOPLEFT", manualCheck, "BOTTOMLEFT", 0, -GAP_NEXT_CHECK)
    styleEngineCheck(localCheck, localResetConfig.label or "Local Session Reset")

    attachTooltip(manualCheck, (engineConfig.manualReset or {}).label, (engineConfig.manualReset or {}).tooltip)
    attachTooltip(localCheck, localResetConfig.label, localResetConfig.tooltip)

    local localTimeSlider = CreateFrame("Slider", nil, page, "OptionsSliderTemplate")
    -- every slider sits on its own line under its option, one step in, so the option can have a long text
    localTimeSlider:SetPoint("TOPLEFT", localCheck, "BOTTOMLEFT", 30, -4)
    localTimeSlider:SetWidth(200)
    localTimeSlider:SetMinMaxValues(0, 95)
    localTimeSlider:SetValueStep(1)
    localTimeSlider:SetObeyStepOnDrag(true)
    localTimeSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if localTimeSlider.Text then localTimeSlider.Text:SetText("") end
    if localTimeSlider.Low then localTimeSlider.Low:SetText(localResetConfig.low or "00:00") end
    if localTimeSlider.High then localTimeSlider.High:SetText(localResetConfig.high or "23:45") end

    local localTimeValue = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    localTimeValue:SetPoint("LEFT", localTimeSlider, "RIGHT", localResetConfig.valueTextX or 8, 0)
    localTimeValue:SetWidth(localResetConfig.valueTextWidth or 46)
    localTimeValue:SetJustifyH("LEFT")
    localTimeValue:SetTextColor(0.82, 0.82, 0.82, 1)

    local autoResetConfig = engineConfig.autoReset or {}
    local autoCheck = CreateFrame("CheckButton", nil, page, "InterfaceOptionsCheckButtonTemplate")
    autoCheck:SetPoint("TOPLEFT", localTimeSlider, "BOTTOMLEFT", -30, -22)
    styleEngineCheck(autoCheck, autoResetConfig.label or "Auto Session Reset")
    attachTooltip(autoCheck, autoResetConfig.label, autoResetConfig.tooltip)

    -- how long you may stay away from an area, after a fight, before its session starts over: 15 seconds to 2 minutes
    local AUTO_DELAY_STEP, AUTO_DELAY_STEPS = 15, 8
    local autoDelaySlider = CreateFrame("Slider", nil, page, "OptionsSliderTemplate")
    autoDelaySlider:SetPoint("TOPLEFT", autoCheck, "BOTTOMLEFT", 30, -4)
    autoDelaySlider:SetWidth(200)
    autoDelaySlider:SetMinMaxValues(1, AUTO_DELAY_STEPS)
    autoDelaySlider:SetValueStep(1)
    autoDelaySlider:SetObeyStepOnDrag(true)
    autoDelaySlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if autoDelaySlider.Text then autoDelaySlider.Text:SetText("") end
    if autoDelaySlider.Low then autoDelaySlider.Low:SetText(autoResetConfig.low or "15s") end
    if autoDelaySlider.High then autoDelaySlider.High:SetText(autoResetConfig.high or "2m") end

    local autoDelayValue = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoDelayValue:SetPoint("LEFT", autoDelaySlider, "RIGHT", autoResetConfig.valueTextX or 8, 0)
    autoDelayValue:SetWidth(autoResetConfig.valueTextWidth or 46)
    autoDelayValue:SetJustifyH("LEFT")
    autoDelayValue:SetTextColor(0.82, 0.82, 0.82, 1)

    local function formatDelay(seconds)
        if seconds >= 60 then
            return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
        end
        return string.format("%ds", seconds)
    end

    local rarityCheck = CreateFrame("CheckButton", nil, page, "InterfaceOptionsCheckButtonTemplate")
    local afterAuto = CreateFrame("Frame", nil, page)
    afterAuto:SetSize(1, 1)
    afterAuto:SetPoint("TOPLEFT", autoDelaySlider, "BOTTOMLEFT", -30, -12)
    local rarityLine = createSection(page, "Rarity filter", afterAuto, GAP_SECTION)
    rarityCheck:SetPoint("TOPLEFT", rarityLine, "BOTTOMLEFT", 0, -GAP_AFTER_LINE)
    styleEngineCheck(rarityCheck, rarityConfig.label or "Set Rarity Level")

    attachTooltip(rarityCheck, rarityConfig.label, rarityConfig.tooltip)

    local raritySlider = CreateFrame("Slider", nil, page, "OptionsSliderTemplate")
    raritySlider:SetPoint("TOPLEFT", rarityCheck, "BOTTOMLEFT", 30, -4)
    raritySlider:SetWidth(200)
    raritySlider:SetMinMaxValues(1, #ENGINE_RARITY_LEVEL_VALUES)
    raritySlider:SetValueStep(1)
    raritySlider:SetObeyStepOnDrag(true)
    raritySlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if raritySlider.Text then raritySlider.Text:SetText("") end
    if raritySlider.Low then raritySlider.Low:SetText(ENGINE_RARITY_LEVEL_VALUES[1].label) end
    if raritySlider.High then raritySlider.High:SetText(ENGINE_RARITY_LEVEL_VALUES[#ENGINE_RARITY_LEVEL_VALUES].label) end

    local rarityValueText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rarityValueText:SetPoint("LEFT", raritySlider, "RIGHT", rarityConfig.valueTextX or 8, 0)
    rarityValueText:SetWidth(rarityConfig.valueTextWidth or 62)
    rarityValueText:SetJustifyH("LEFT")
    rarityValueText:SetTextColor(0.82, 0.82, 0.82, 1)

    local function getNormalizedMode()
        local modeValue = ((FWR.Settings or {}).engine or {}).sessionResetMode or "manual"
        if modeValue ~= "local" and modeValue ~= "auto" then
            modeValue = "manual"
        end
        return modeValue
    end

    local function touchEngine()
        if FWR.RefreshDisplayText then
            FWR:RefreshDisplayText()
        end
    end

    local function refreshEngineControls()
        local modeValue = getNormalizedMode()
        manualCheck:SetChecked(modeValue == "manual")
        localCheck:SetChecked(modeValue == "local")
        autoCheck:SetChecked(modeValue == "auto")
        updateCheckboxVisual(manualCheck)
        updateCheckboxVisual(localCheck)
        updateCheckboxVisual(autoCheck)

        local autoSeconds = math.max(AUTO_DELAY_STEP, math.min(AUTO_DELAY_STEP * AUTO_DELAY_STEPS, getNumberSetting({ "engine", "autoResetDelaySeconds" }, 30)))
        local autoIndex = math.floor(autoSeconds / AUTO_DELAY_STEP + 0.5)
        autoDelaySlider.__fwrRefreshing = true
        autoDelaySlider:SetValue(autoIndex)
        autoDelaySlider.__fwrPendingIndex = autoIndex
        autoDelaySlider.__fwrRefreshing = nil
        autoDelaySlider:SetEnabled(modeValue == "auto")
        autoDelayValue:SetText(formatDelay(autoIndex * AUTO_DELAY_STEP))
        autoDelayValue:SetAlpha(modeValue == "auto" and 1 or 0.45)
        do
            local thumb = autoDelaySlider.GetThumbTexture and autoDelaySlider:GetThumbTexture() or nil
            if thumb and thumb.SetAlpha then thumb:SetAlpha(modeValue == "auto" and 1 or 0) end
        end
        if autoDelaySlider.Low then autoDelaySlider.Low:SetAlpha(modeValue == "auto" and 1 or 0.45) end
        if autoDelaySlider.High then autoDelaySlider.High:SetAlpha(modeValue == "auto" and 1 or 0.45) end

        local localMinutes = math.max(0, math.min(1435, getNumberSetting({ "engine", "localResetMinutes" }, 0)))
        local localIndex = math.floor(localMinutes / 15 + 0.5)
        localTimeSlider.__fwrRefreshing = true
        localTimeSlider:SetValue(localIndex)
        localTimeSlider.__fwrPendingLocalTimeIndex = localIndex
        localTimeSlider.__fwrRefreshing = nil
        localTimeSlider:SetEnabled(modeValue == "local")
        localTimeValue:SetText(formatQuarterHourLabel(localMinutes))
        localTimeValue:SetAlpha(modeValue == "local" and 1 or 0.45)
        do
            local thumb = localTimeSlider.GetThumbTexture and localTimeSlider:GetThumbTexture() or nil
            if thumb and thumb.SetAlpha then thumb:SetAlpha(modeValue == "local" and 1 or 0) end
        end
        if localTimeSlider.Low then localTimeSlider.Low:SetAlpha(modeValue == "local" and 1 or 0.45) end
        if localTimeSlider.High then localTimeSlider.High:SetAlpha(modeValue == "local" and 1 or 0.45) end

        local rarityEnabled = getBooleanSetting({ "engine", "rarityFilterEnabled" }, false)
        rarityCheck:SetChecked(rarityEnabled)
        updateCheckboxVisual(rarityCheck)

        local rarityValue = getNumberSetting({ "engine", "rarityLevel" }, 1)
        local rarityIndex = getIndexedValueIndex(ENGINE_RARITY_LEVEL_VALUES, rarityValue, 2)
        raritySlider.__fwrRefreshing = true
        raritySlider:SetValue(rarityIndex)
        raritySlider.__fwrPendingRarityIndex = rarityIndex
        raritySlider.__fwrRefreshing = nil
        raritySlider:SetEnabled(rarityEnabled)
        rarityValueText:SetText(ENGINE_RARITY_LEVEL_VALUES[rarityIndex].label)
        rarityValueText:SetAlpha(rarityEnabled and 1 or 0.45)
        do
            local thumb = raritySlider.GetThumbTexture and raritySlider:GetThumbTexture() or nil
            if thumb and thumb.SetAlpha then thumb:SetAlpha(rarityEnabled and 1 or 0) end
        end
        if raritySlider.Low then raritySlider.Low:SetAlpha(rarityEnabled and 1 or 0.45) end
        if raritySlider.High then raritySlider.High:SetAlpha(rarityEnabled and 1 or 0.45) end
    end

    local function setMode(modeValue)
        if modeValue ~= "local" and modeValue ~= "auto" then
            modeValue = "manual"
        end
        setValueSetting({ "engine", "sessionResetMode" }, modeValue)
        touchEngine()
        refreshEngineControls()
    end

    manualCheck:SetScript("OnClick", function(self)
        if not self:GetChecked() then
            self:SetChecked(true)
            return
        end
        setMode("manual")
    end)

    localCheck:SetScript("OnClick", function(self)
        if not self:GetChecked() then
            self:SetChecked(true)
            return
        end
        setMode("local")
    end)

    autoCheck:SetScript("OnClick", function(self)
        if not self:GetChecked() then
            self:SetChecked(true)
            return
        end
        setMode("auto")
    end)

    autoDelaySlider:SetScript("OnValueChanged", function(self, value)
        if self.__fwrRefreshing then
            return
        end
        local snapped = math.max(1, math.min(AUTO_DELAY_STEPS, math.floor((tonumber(value) or 1) + 0.5)))
        self.__fwrPendingIndex = snapped
        autoDelayValue:SetText(formatDelay(snapped * AUTO_DELAY_STEP))
    end)
    local function commitAutoDelay(self)
        local idx = self.__fwrPendingIndex or math.max(1, math.min(AUTO_DELAY_STEPS, math.floor((tonumber(self:GetValue()) or 1) + 0.5)))
        setNumberSetting({ "engine", "autoResetDelaySeconds" }, idx * AUTO_DELAY_STEP)
    end
    autoDelaySlider:SetScript("OnMouseUp", function(self)
        commitAutoDelay(self)
        refreshEngineControls()
    end)
    autoDelaySlider:SetScript("OnHide", commitAutoDelay)

    localTimeSlider:SetScript("OnValueChanged", function(self, value)
        if self.__fwrRefreshing then
            return
        end
        local snapped = math.max(0, math.min(95, math.floor((tonumber(value) or 0) + 0.5)))
        self.__fwrPendingLocalTimeIndex = snapped
        localTimeValue:SetText(formatQuarterHourLabel(snapped * 15))
    end)
    localTimeSlider:SetScript("OnMouseUp", function(self)
        local idx = self.__fwrPendingLocalTimeIndex or math.max(0, math.min(95, math.floor((tonumber(self:GetValue()) or 0) + 0.5)))
        setNumberSetting({ "engine", "localResetMinutes" }, idx * 15)
        refreshEngineControls()
    end)
    localTimeSlider:SetScript("OnHide", function(self)
        local idx = self.__fwrPendingLocalTimeIndex or math.max(0, math.min(95, math.floor((tonumber(self:GetValue()) or 0) + 0.5)))
        setNumberSetting({ "engine", "localResetMinutes" }, idx * 15)
    end)

    rarityCheck:SetScript("OnClick", function(self)
        local checked = self:GetChecked() == true
        setBooleanSetting({ "engine", "rarityFilterEnabled" }, checked)
        touchEngine()
        refreshEngineControls()
    end)

    raritySlider:SetScript("OnValueChanged", function(self, value)
        if self.__fwrRefreshing then
            return
        end
        local snapped = math.max(1, math.min(#ENGINE_RARITY_LEVEL_VALUES, math.floor((tonumber(value) or 1) + 0.5)))
        self.__fwrPendingRarityIndex = snapped
        rarityValueText:SetText(ENGINE_RARITY_LEVEL_VALUES[snapped].label)
    end)
    raritySlider:SetScript("OnMouseUp", function(self)
        local idx = self.__fwrPendingRarityIndex or math.max(1, math.min(#ENGINE_RARITY_LEVEL_VALUES, math.floor((tonumber(self:GetValue()) or 1) + 0.5)))
        setNumberSetting({ "engine", "rarityLevel" }, ENGINE_RARITY_LEVEL_VALUES[idx].value)
        touchEngine()
        refreshEngineControls()
    end)
    raritySlider:SetScript("OnHide", function(self)
        local idx = self.__fwrPendingRarityIndex or math.max(1, math.min(#ENGINE_RARITY_LEVEL_VALUES, math.floor((tonumber(self:GetValue()) or 1) + 0.5)))
        setNumberSetting({ "engine", "rarityLevel" }, ENGINE_RARITY_LEVEL_VALUES[idx].value)
    end)

    page:SetScript("OnShow", refreshEngineControls)
    page.RefreshEngineControls = refreshEngineControls
    refreshEngineControls()
    return page
end

-- The page "FarmWise AH" of this window holds only the switch of the FarmWise Auction House: all its other
-- settings are on the Options page of its tab, in the Auction House (FWR:BuildAuctionOptions below).
local function createAuctionSwitchPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    local config = (PAGE_CONFIG.selltab or {}).enabled or {}
    local checkboxConfig = (PAGE_CONFIG.engine or {}).checkbox or {}

    local line = createSection(page, "FarmWise AH")
    local note = createNote(page, "The FarmWise Auction House is the tab of the Auction House where you post what you farmed. All its settings (posting time, price steps, price check, average price, what the list holds, the columns, the sales history) are on the Options page of that tab: open the Auction House, choose the FarmWise AH tab, then Options. What is scanned is set in the Scanner page of this window.", line, 0, 6)

    local check = CreateFrame("CheckButton", nil, page, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -GAP_AFTER_NOTE)
    check:SetHitRectInsets(0, 0, 0, 0)
    if check.Text then
        check.Text:ClearAllPoints()
        check.Text:SetPoint("LEFT", check, "RIGHT", checkboxConfig.textOffsetX or 0, checkboxConfig.textOffsetY or 1)
        check.Text:SetJustifyH("LEFT")
        check.Text:SetText(config.label or "Add the FarmWise AH tab to the Auction House")
    end
    attachTooltip(check, config.label or "FarmWise AH", config.tooltip)

    local function refresh()
        check:SetChecked(getBooleanSetting({ "ah", "tabEnabled" }, true))
        updateCheckboxVisual(check)
    end
    check:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "tabEnabled" }, self:GetChecked() == true)
        updateCheckboxVisual(self)
        FWR:Emit("sellTabEnabledChanged")
    end)
    page:SetScript("OnShow", refresh)
    refresh()
    return page
end

local function createAuctionPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    local config = PAGE_CONFIG.auction or {}
    local titles = config.sections or {}
    local checkboxConfig = (PAGE_CONFIG.engine or {}).checkbox or {}

    local function styleCheck(check, text)
        check:SetHitRectInsets(0, 0, 0, 0)
        if check.Text then
            check.Text:ClearAllPoints()
            check.Text:SetPoint("LEFT", check, "RIGHT", checkboxConfig.textOffsetX or 0, checkboxConfig.textOffsetY or 1)
            check.Text:SetJustifyH("LEFT")
            check.Text:SetText(text or "")
        end
    end

    local function newCheck(anchor, gap, entry)
        local check = CreateFrame("CheckButton", nil, page, "InterfaceOptionsCheckButtonTemplate")
        check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
        styleCheck(check, entry.label)
        attachTooltip(check, entry.label, entry.tooltip)
        return check
    end

    -- Scanning
    local scanLine = createSection(page, titles.scanning or "Scanning")
    local note = createNote(page, config.note or "", scanLine, 0, 6)
    local autoCheck = newCheck(note, GAP_AFTER_NOTE, config.autoScan or {})
    local soundCheck = newCheck(autoCheck, GAP_NEXT_CHECK, config.sound or {})

    -- What is scanned
    local depthLine = createSection(page, titles.depth or "What is scanned", soundCheck)
    local depthNote = createNote(page, config.depthNote or "", depthLine, 0, 6)
    local commoditiesCheck = newCheck(depthNote, GAP_AFTER_NOTE, config.commodities or {})
    local fullCheck = newCheck(commoditiesCheck, GAP_NEXT_CHECK, config.fullScan or {})

    -- How often
    local intervalLine = createSection(page, titles.interval or "How often", fullCheck)
    local intervalNote = createNote(page, config.intervalNote or "", intervalLine, 0, 6)
    local intervalTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intervalTitle:SetPoint("TOPLEFT", intervalNote, "BOTTOMLEFT", 0, -8)
    intervalTitle:SetTextColor(1, 1, 1, 1)
    intervalTitle:SetText(config.intervalTitle or "")

    local intervalChecks = {}
    local previous = intervalTitle
    local firstInterval = true
    for _, interval in ipairs(config.intervals or {}) do
        local check = CreateFrame("CheckButton", nil, page, "InterfaceOptionsCheckButtonTemplate")
        check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, firstInterval and -GAP_AFTER_LINE or -GAP_NEXT_CHECK)
        firstInterval = false
        styleCheck(check, interval.label)
        check.minutes = interval.minutes
        intervalChecks[#intervalChecks + 1] = check
        previous = check
    end

    -- Tooltips
    local tooltipLine = createSection(page, titles.tooltips or "Tooltips", previous)
    local tooltipCheck = newCheck(tooltipLine, GAP_AFTER_LINE, config.tooltipPrice or {})

    local function refresh()
        local autoEnabled = getBooleanSetting({ "ah", "autoScan" }, true)
        autoCheck:SetChecked(autoEnabled)
        updateCheckboxVisual(autoCheck)

        soundCheck:SetChecked(getBooleanSetting({ "ah", "sound" }, true))
        updateCheckboxVisual(soundCheck)

        tooltipCheck:SetChecked(getBooleanSetting({ "ah", "tooltipPrice" }, true))
        updateCheckboxVisual(tooltipCheck)

        -- the whole Auction House includes everything sold by amount
        local full = getBooleanSetting({ "ah", "fullScan" }, false)
        fullCheck:SetChecked(full)
        updateCheckboxVisual(fullCheck)
        commoditiesCheck:SetChecked(full or getBooleanSetting({ "ah", "scanCommodities" }, true))
        if full then
            commoditiesCheck:Disable()
        else
            commoditiesCheck:Enable()
        end
        updateCheckboxVisual(commoditiesCheck)

        local current = getNumberSetting({ "ah", "freshnessMinutes" }, 30)
        for _, check in ipairs(intervalChecks) do
            check:SetChecked(check.minutes == current)
            if autoEnabled then
                check:Enable()
            else
                check:Disable()
            end
            updateCheckboxVisual(check)
        end
        intervalTitle:SetAlpha(autoEnabled and 1 or 0.45)
    end

    autoCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "autoScan" }, self:GetChecked() == true)
        refresh()
    end)

    soundCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "sound" }, self:GetChecked() == true)
        refresh()
    end)

    tooltipCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "tooltipPrice" }, self:GetChecked() == true)
        refresh()
    end)

    commoditiesCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "scanCommodities" }, self:GetChecked() == true)
        refresh()
    end)

    fullCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "fullScan" }, self:GetChecked() == true)
        refresh()
    end)

    for _, check in ipairs(intervalChecks) do
        check:SetScript("OnClick", function(self)
            setNumberSetting({ "ah", "freshnessMinutes" }, self.minutes)
            refresh()
            if FWR.RefreshAdvisorPanel then
                FWR:RefreshAdvisorPanel()
            end
        end)
    end

    page:SetScript("OnShow", refresh)
    refresh()
    return page
end

local function createSellTabPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    local config = PAGE_CONFIG.selltab or {}
    local titles = config.sections or {}
    local checkboxConfig = (PAGE_CONFIG.engine or {}).checkbox or {}

    local function styleCheck(check, text)
        check:SetHitRectInsets(0, 0, 0, 0)
        if check.Text then
            check.Text:ClearAllPoints()
            check.Text:SetPoint("LEFT", check, "RIGHT", checkboxConfig.textOffsetX or 0, checkboxConfig.textOffsetY or 1)
            check.Text:SetJustifyH("LEFT")
            check.Text:SetText(text or "")
        end
    end

    local function newCheck(anchor, gap, entry, offsetX)
        local check = CreateFrame("CheckButton", nil, page, "InterfaceOptionsCheckButtonTemplate")
        check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", offsetX or 0, -gap)
        styleCheck(check, entry.label)
        attachTooltip(check, entry.label, entry.tooltip)
        return check
    end

    -- The tab
    local tabLine = createSection(page, titles.tab or "The tab")
    local note = createNote(page, config.note or "", tabLine, 0, 6)
    local enabledCheck = newCheck(note, GAP_AFTER_NOTE, config.enabled or {})

    -- Posting
    local postingLine = createSection(page, titles.posting or "Posting", enabledCheck)
    local durationTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durationTitle:SetPoint("TOPLEFT", postingLine, "BOTTOMLEFT", 0, -8)
    durationTitle:SetTextColor(1, 1, 1, 1)
    durationTitle:SetText(config.durationTitle or "")

    -- the three times side by side
    local durationChecks = {}
    local previousDuration
    for _, entry in ipairs(config.durations or {}) do
        local check = CreateFrame("CheckButton", nil, page, "InterfaceOptionsCheckButtonTemplate")
        if previousDuration then
            check:SetPoint("LEFT", previousDuration.Text, "RIGHT", 18, 0)
        else
            check:SetPoint("TOPLEFT", durationTitle, "BOTTOMLEFT", 0, -GAP_AFTER_LINE)
        end
        styleCheck(check, entry.label)
        check.value = entry.value
        durationChecks[#durationChecks + 1] = check
        previousDuration = check
    end

    -- the step of + and -: a slider, from 1% to 20%
    local stepConfig = config.priceStep or {}
    local stepTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stepTitle:SetPoint("TOPLEFT", durationChecks[1] or durationTitle, "BOTTOMLEFT", 0, -14)
    stepTitle:SetTextColor(1, 1, 1, 1)
    stepTitle:SetText(stepConfig.title or "")

    local stepSlider = CreateFrame("Slider", nil, page, "OptionsSliderTemplate")
    stepSlider:SetPoint("TOPLEFT", stepTitle, "BOTTOMLEFT", 6, -12)
    stepSlider:SetWidth(200)
    stepSlider:SetMinMaxValues(1, 20)
    stepSlider:SetValueStep(1)
    stepSlider:SetObeyStepOnDrag(true)
    stepSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if stepSlider.Text then stepSlider.Text:SetText("") end
    if stepSlider.Low then stepSlider.Low:SetText("1%") end
    if stepSlider.High then stepSlider.High:SetText("20%") end
    attachTooltip(stepSlider, stepConfig.title, stepConfig.tooltip)

    local stepValue = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stepValue:SetPoint("LEFT", stepSlider, "RIGHT", 10, 0)
    stepValue:SetJustifyH("LEFT")
    stepValue:SetTextColor(1, 0.82, 0, 1)

    local afterStep = CreateFrame("Frame", nil, page)
    afterStep:SetSize(1, 1)
    afterStep:SetPoint("TOPLEFT", stepSlider, "BOTTOMLEFT", -6, -22)

    local priceCheck = newCheck(afterStep, GAP_NEXT_CHECK, config.priceCheck or {})
    local averageCheck = newCheck(priceCheck, GAP_NEXT_CHECK, config.averageFloor or {})

    -- the number of sales the average price is made of: a slider, from 5 to 30
    local salesConfig = config.averageSales or {}
    local salesTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    salesTitle:SetPoint("TOPLEFT", averageCheck, "BOTTOMLEFT", 0, -10)
    salesTitle:SetTextColor(1, 1, 1, 1)
    salesTitle:SetText(salesConfig.title or "")

    local salesSlider = CreateFrame("Slider", nil, page, "OptionsSliderTemplate")
    salesSlider:SetPoint("TOPLEFT", salesTitle, "BOTTOMLEFT", 6, -12)
    salesSlider:SetWidth(200)
    salesSlider:SetMinMaxValues(5, 30)
    salesSlider:SetValueStep(1)
    salesSlider:SetObeyStepOnDrag(true)
    salesSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if salesSlider.Text then salesSlider.Text:SetText("") end
    if salesSlider.Low then salesSlider.Low:SetText("5") end
    if salesSlider.High then salesSlider.High:SetText("30") end
    attachTooltip(salesSlider, salesConfig.title, salesConfig.tooltip)

    local salesValue = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    salesValue:SetPoint("LEFT", salesSlider, "RIGHT", 10, 0)
    salesValue:SetJustifyH("LEFT")
    salesValue:SetTextColor(1, 0.82, 0, 1)

    local afterSales = CreateFrame("Frame", nil, page)
    afterSales:SetSize(1, 1)
    afterSales:SetPoint("TOPLEFT", salesSlider, "BOTTOMLEFT", -6, -20)
    local wheelCheck = newCheck(afterSales, 0, config.wheel or {})
    -- one step in: it belongs to the wheel option above
    local shiftCheck = newCheck(wheelCheck, GAP_NEXT_CHECK, config.wheelShift or {}, 24)

    -- Display
    -- the sections start at the margin: the step in of the Shift option is not passed on to them
    local afterShift = CreateFrame("Frame", nil, page)
    afterShift:SetSize(1, 1)
    afterShift:SetPoint("TOPLEFT", shiftCheck, "BOTTOMLEFT", -24, 0)
    local displayLine = createSection(page, titles.display or "Display", afterShift)
    local tooltipsCheck = newCheck(displayLine, GAP_AFTER_LINE, config.tooltips or {})
    local trendCheck = newCheck(tooltipsCheck, GAP_NEXT_CHECK, config.showTrend or {})
    local valueCheck = newCheck(trendCheck, GAP_NEXT_CHECK, config.showValue or {})

    -- Sales history
    local historyLine = createSection(page, titles.history or "Sales history", valueCheck)
    local historyCheck = newCheck(historyLine, GAP_AFTER_LINE, config.history or {})

    local function refresh()
        local enabled = getBooleanSetting({ "ah", "tabEnabled" }, true)
        enabledCheck:SetChecked(enabled)
        updateCheckboxVisual(enabledCheck)
        durationTitle:SetAlpha(enabled and 1 or 0.45)

        local current = getNumberSetting({ "ah", "tabPostTime" }, 1)
        for _, check in ipairs(durationChecks) do
            check:SetChecked(check.value == current)
            if enabled then
                check:Enable()
            else
                check:Disable()
            end
            updateCheckboxVisual(check)
        end
        for _, check in ipairs({ priceCheck, averageCheck, tooltipsCheck, wheelCheck, trendCheck, valueCheck, historyCheck }) do
            if enabled then
                check:Enable()
            else
                check:Disable()
            end
        end

        local stepNow = math.max(1, math.min(20, math.floor(getNumberSetting({ "ah", "tabPriceStep" }, 5) + 0.5)))
        stepSlider.__fwrRefreshing = true
        stepSlider:SetValue(stepNow)
        stepSlider.__fwrRefreshing = nil
        stepValue:SetText(string.format("%d%%", stepNow))
        stepSlider:SetEnabled(enabled)
        stepTitle:SetAlpha(enabled and 1 or 0.45)
        stepValue:SetAlpha(enabled and 1 or 0.45)

        priceCheck:SetChecked(getBooleanSetting({ "ah", "tabPriceCheck" }, false))
        updateCheckboxVisual(priceCheck)
        -- the average is made of the sales history: without it there is nothing to turn on
        local historyOn = getBooleanSetting({ "ah", "tabHistory" }, true)
        local averageSales = math.max(5, math.min(30, math.floor(getNumberSetting({ "ah", "tabAverageSales" }, 10) + 0.5)))
        if averageCheck.Text then
            averageCheck.Text:SetText(string.format("%s (%d sales)", (config.averageFloor or {}).label or "", averageSales))
        end
        averageCheck:SetChecked(getBooleanSetting({ "ah", "tabAverageFloor" }, false))
        if enabled and historyOn then
            averageCheck:Enable()
        else
            averageCheck:Disable()
        end
        updateCheckboxVisual(averageCheck)
        tooltipsCheck:SetChecked(getBooleanSetting({ "ah", "tabTooltips" }, true))
        updateCheckboxVisual(tooltipsCheck)
        wheelCheck:SetChecked(getBooleanSetting({ "ah", "tabWheel" }, false))
        updateCheckboxVisual(wheelCheck)
        shiftCheck:SetChecked(getBooleanSetting({ "ah", "tabWheelShift" }, true))
        if enabled and wheelCheck:GetChecked() then
            shiftCheck:Enable()
        else
            shiftCheck:Disable()
        end
        updateCheckboxVisual(shiftCheck)
        trendCheck:SetChecked(getBooleanSetting({ "ah", "tabShowTrend" }, true))
        updateCheckboxVisual(trendCheck)
        valueCheck:SetChecked(getBooleanSetting({ "ah", "tabShowValue" }, true))
        updateCheckboxVisual(valueCheck)
        historyCheck:SetChecked(getBooleanSetting({ "ah", "tabHistory" }, true))
        updateCheckboxVisual(historyCheck)

        local salesNow = math.max(5, math.min(30, math.floor(getNumberSetting({ "ah", "tabAverageSales" }, 10) + 0.5)))
        salesSlider.__fwrRefreshing = true
        salesSlider:SetValue(salesNow)
        salesSlider.__fwrRefreshing = nil
        salesValue:SetText(string.format("%d sales", salesNow))
        local salesUsable = enabled and getBooleanSetting({ "ah", "tabHistory" }, true)
        salesSlider:SetEnabled(salesUsable)
        salesTitle:SetAlpha(salesUsable and 1 or 0.45)
        salesValue:SetAlpha(salesUsable and 1 or 0.45)
    end

    -- the tab makes its list again (posting time and price check are used at once)
    local function changed()
        refresh()
        FWR:Emit("sellFiltersChanged")
    end

    enabledCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "tabEnabled" }, self:GetChecked() == true)
        refresh()
        FWR:Emit("sellTabEnabledChanged")
    end)

    for _, check in ipairs(durationChecks) do
        check:SetScript("OnClick", function(self)
            setNumberSetting({ "ah", "tabPostTime" }, self.value)
            changed()
        end)
    end
    salesSlider:SetScript("OnValueChanged", function(self, value)
        if self.__fwrRefreshing then
            return
        end
        local snapped = math.max(5, math.min(30, math.floor((tonumber(value) or 10) + 0.5)))
        salesValue:SetText(string.format("%d sales", snapped))
        setNumberSetting({ "ah", "tabAverageSales" }, snapped)
        if averageCheck.Text then
            averageCheck.Text:SetText(string.format("%s (%d sales)", (config.averageFloor or {}).label or "", snapped))
        end
        FWR:Emit("sellFiltersChanged")
    end)
    stepSlider:SetScript("OnValueChanged", function(self, value)
        if self.__fwrRefreshing then
            return
        end
        local snapped = math.max(1, math.min(20, math.floor((tonumber(value) or 5) + 0.5)))
        stepValue:SetText(string.format("%d%%", snapped))
        setNumberSetting({ "ah", "tabPriceStep" }, snapped)
    end)
    priceCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "tabPriceCheck" }, self:GetChecked() == true)
        changed()
    end)
    averageCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "tabAverageFloor" }, self:GetChecked() == true)
        changed()
    end)
    wheelCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "tabWheel" }, self:GetChecked() == true)
        refresh()
        FWR:Emit("sellTabWheelChanged")
    end)
    shiftCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "tabWheelShift" }, self:GetChecked() == true)
        refresh()
        FWR:Emit("sellTabWheelChanged")
    end)
    tooltipsCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "tabTooltips" }, self:GetChecked() == true)
        refresh()
    end)
    trendCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "tabShowTrend" }, self:GetChecked() == true)
        changed()
    end)
    valueCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "tabShowValue" }, self:GetChecked() == true)
        changed()
    end)
    historyCheck:SetScript("OnClick", function(self)
        setBooleanSetting({ "ah", "tabHistory" }, self:GetChecked() == true)
        refresh()
        FWR:Emit("sellFiltersChanged")
        FWR:Emit("sellTabHistoryChanged")
    end)

    page:SetScript("OnShow", refresh)
    refresh()
    return page
end

local function createInfoPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    local infoConfig = PAGE_CONFIG.info or {}
    local titleConfig = infoConfig.title or {}
    local bodyConfig = infoConfig.body or {}

    local title = createSection(page, titleConfig.text or "Quick commands")

    local body = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", bodyConfig.x or 0, -GAP_AFTER_NOTE)
    body:SetPoint("RIGHT", page, "RIGHT", -(bodyConfig.rightInset or 18), 0)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText(bodyConfig.text or "")

    return page
end

local function createDataPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    local eraseConfig = (PAGE_CONFIG.data or {}).erase or {}

    local eraseSection = createSection(page, "Erase data")
    local eraseNote = createNote(page, eraseConfig.note or "", eraseSection, 0, 8)

    local eraseLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    eraseLabel:SetPoint("TOPLEFT", eraseNote, "BOTTOMLEFT", 0, -GAP_AFTER_NOTE - 6)
    eraseLabel:SetTextColor(1, 1, 1, 1)
    eraseLabel:SetText(eraseConfig.label or "Erase Data")

    local eraseButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    eraseButton:SetSize(eraseConfig.buttonWidth or 110, eraseConfig.buttonHeight or 24)
    eraseButton:SetPoint("LEFT", eraseLabel, "RIGHT", eraseConfig.buttonOffsetX or 36, 0)
    eraseButton:SetText(eraseConfig.buttonText or "Erase")
    eraseButton:SetScript("OnClick", function()
        ensureClearAllDataPopup()
        if StaticPopup_Show then
            StaticPopup_Show(CLEAR_ALL_DATA_POPUP_KEY)
        end
    end)

    return page
end

local function selectCategory(frame, categoryKey)
    if not frame then
        return
    end

    frame.SelectedCategoryKey = categoryKey

    for _, entry in ipairs(CATEGORY_ORDER) do
        local button = frame.CategoryButtons and frame.CategoryButtons[entry.key]
        local page = frame.Pages and frame.Pages[entry.key]
        local selected = entry.key == categoryKey

        if button then
            button:SetSelected(selected)
        end

        if page then
            page:SetShown(selected)
        end
    end

    local selectedLabel = categoryKey
    for _, entry in ipairs(CATEGORY_ORDER) do
        if entry.key == categoryKey then
            selectedLabel = entry.label
            break
        end
    end

    if frame.titleAccent then
        frame.titleAccent:SetText((HEADER_CONFIG.titleAccent and HEADER_CONFIG.titleAccent.text) or "Control Panel")
    end
    if frame.subtitle then
        frame.subtitle:SetText(CATEGORY_NOTES[categoryKey] or "")
    end

    -- the manual always opens on its list of chapters
    if categoryKey == "manual" then
        local scroll = frame.Pages and frame.Pages.manual
        if scroll and scroll.Page and scroll.Page.ShowHome then
            scroll.Page:ShowHome()
        end
    end
    if frame.UpdateBackButton then
        frame:UpdateBackButton()
    end
end

local function buildWindow()
    if FWR.ControlPanelWindow then
        return FWR.ControlPanelWindow
    end

    local frame = CreateFrame("Frame", "FarmWiseReforgedControlPanelWindow", UIParent, "BackdropTemplate")
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    do local fp = WINDOW_CONFIG.framePoint or {}; frame:SetPoint(fp.point or "CENTER", UIParent, fp.relativePoint or "CENTER", fp.x or 0, fp.y or 0) end
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(30)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:Hide()

    frame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(unpack(COLOR_CONFIG.frameBg or { 0.04, 0.03, 0.02, 0.94 }))
    FWR:AddPanelBorder(frame)

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", 0, 0)
    frame.header:SetPoint("TOPRIGHT", 0, 0)
    frame.header:SetHeight(HEADER_HEIGHT)
    frame.header:EnableMouse(true)
    frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    frame.header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    frame.headerBg = frame.header:CreateTexture(nil, "BACKGROUND")
    frame.headerBg:SetAllPoints()
    frame.headerBg:SetColorTexture(unpack(COLOR_CONFIG.headerBg or { 0.10, 0.08, 0.05, 0.95 }))

    frame.footer = CreateFrame("Frame", nil, frame)
    frame.footer:SetPoint("BOTTOMLEFT", 0, 0)
    frame.footer:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.footer:SetHeight(FOOTER_HEIGHT)

    frame.footerBg = frame.footer:CreateTexture(nil, "BACKGROUND")
    frame.footerBg:SetAllPoints()
    frame.footerBg:SetColorTexture(unpack(COLOR_CONFIG.footerBg or { 0.10, 0.08, 0.05, 0.95 }))

    frame.sidebar = CreateFrame("Frame", nil, frame)
    frame.sidebar:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
    frame.sidebar:SetPoint("BOTTOMLEFT", 0, FOOTER_HEIGHT)
    frame.sidebar:SetWidth(SIDEBAR_WIDTH)

    frame.sidebarBg = frame.sidebar:CreateTexture(nil, "BACKGROUND")
    frame.sidebarBg:SetAllPoints()
    frame.sidebarBg:SetColorTexture(unpack(COLOR_CONFIG.sidebarBg or { 0.08, 0.06, 0.04, 0.9 }))

    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT", 0, 0)
    frame.content:SetPoint("BOTTOMRIGHT", 0, FOOTER_HEIGHT)

    frame.contentBg = frame.content:CreateTexture(nil, "BACKGROUND")
    frame.contentBg:SetAllPoints()
    frame.contentBg:SetColorTexture(unpack(COLOR_CONFIG.contentBg or { 0.06, 0.05, 0.03, 0.82 }))

    do local c = COLOR_CONFIG.divider or {1,1,1,0.10}; createBorderLine(frame, "BOTTOMLEFT", frame.header, "BOTTOMLEFT", 0, 0, WINDOW_WIDTH, 1, c[1], c[2], c[3], c[4]) end
    do local c = COLOR_CONFIG.divider or {1,1,1,0.10}; createBorderLine(frame, "TOPLEFT", frame.footer, "TOPLEFT", 0, 0, WINDOW_WIDTH, 1, c[1], c[2], c[3], c[4]) end
    do local c = COLOR_CONFIG.divider or {1,1,1,0.10}; createBorderLine(frame, "TOPRIGHT", frame.sidebar, "TOPRIGHT", 0, 0, 1, WINDOW_HEIGHT - HEADER_HEIGHT - FOOTER_HEIGHT, c[1], c[2], c[3], c[4]) end

    frame.title = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", (HEADER_CONFIG.title and HEADER_CONFIG.title.x) or 18, (HEADER_CONFIG.title and HEADER_CONFIG.title.y) or -12)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetTextColor(unpack(COLOR_CONFIG.title or { 0.95, 0.82, 0.42, 1.0 }))
    frame.title:SetText((HEADER_CONFIG.title and HEADER_CONFIG.title.text) or "FarmWise")

    frame.titleAccent = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.titleAccent:SetPoint("LEFT", frame.title, "RIGHT", (HEADER_CONFIG.titleAccent and HEADER_CONFIG.titleAccent.x) or 6, (HEADER_CONFIG.titleAccent and HEADER_CONFIG.titleAccent.y) or 0)
    frame.titleAccent:SetJustifyH("LEFT")
    frame.titleAccent:SetTextColor(unpack(COLOR_CONFIG.titleAccent or { 0.96, 0.96, 0.96, 1.0 }))
    frame.titleAccent:SetText((HEADER_CONFIG.titleAccent and HEADER_CONFIG.titleAccent.text) or "Control Panel")

    frame.subtitle = frame.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", (HEADER_CONFIG.subtitle and HEADER_CONFIG.subtitle.x) or 0, (HEADER_CONFIG.subtitle and HEADER_CONFIG.subtitle.y) or -6)
    frame.subtitle:SetJustifyH("LEFT")
    frame.subtitle:SetTextColor(unpack(COLOR_CONFIG.subtitle or { 0.80, 0.80, 0.80, 1.0 }))
    frame.subtitle:SetText(CATEGORY_NOTES.interface or "")

    frame.closeButton = CreateFrame("Button", nil, frame.footer, "UIPanelButtonTemplate")
    frame.closeButton:SetSize((FOOTER_CONFIG.closeButton and FOOTER_CONFIG.closeButton.width) or 84, (FOOTER_CONFIG.closeButton and FOOTER_CONFIG.closeButton.height) or 24)
    frame.closeButton:SetPoint("RIGHT", frame.footer, "RIGHT", (FOOTER_CONFIG.closeButton and FOOTER_CONFIG.closeButton.x) or -18, (FOOTER_CONFIG.closeButton and FOOTER_CONFIG.closeButton.y) or 0)
    frame.closeButton:SetText((FOOTER_CONFIG.closeButton and FOOTER_CONFIG.closeButton.text) or "Close")
    frame.closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- "Back": next to Close, only while a chapter of the manual is open
    frame.backButton = CreateFrame("Button", nil, frame.footer, "UIPanelButtonTemplate")
    frame.backButton:SetSize(84, 24)
    frame.backButton:SetPoint("RIGHT", frame.closeButton, "LEFT", -8, 0)
    frame.backButton:SetText("Back")
    frame.backButton:Hide()
    frame.backButton:SetScript("OnClick", function()
        local scroll = frame.Pages and frame.Pages.manual
        if scroll and scroll.Page and scroll.Page.ShowHome then
            scroll.Page:ShowHome()
        end
    end)
    function frame:UpdateBackButton()
        self.backButton:SetShown(self.SelectedCategoryKey == "manual" and self.ManualChapter ~= nil)
    end

    frame.footerNote = frame.footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.footerNote:SetPoint("LEFT", frame.footer, "LEFT", (FOOTER_CONFIG.note and FOOTER_CONFIG.note.x) or 18, (FOOTER_CONFIG.note and FOOTER_CONFIG.note.y) or 0)
    frame.footerNote:SetPoint("RIGHT", frame.closeButton, "LEFT", -12, 0)
    frame.footerNote:SetJustifyH("LEFT")
    frame.footerNote:SetWordWrap(false)
    frame.footerNote:SetTextColor(unpack(COLOR_CONFIG.footerNote or { 0.72, 0.72, 0.72, 1.0 }))
    frame.footerNote:SetText((FOOTER_CONFIG.note and FOOTER_CONFIG.note.text) or "Use the left menu to move between pages.")

    frame.contentInset = CreateFrame("Frame", nil, frame.content)
    frame.contentInset:SetPoint("TOPLEFT", frame.content, "TOPLEFT", CONTENT_PADDING, -18)
    frame.contentInset:SetPoint("BOTTOMRIGHT", frame.content, "BOTTOMRIGHT", -CONTENT_PADDING, CONTENT_PADDING)

    frame.CategoryButtons = {}
    frame.Pages = {}

    local navButtonConfig = CATEGORY_CONFIG.button or {}
    local previousButton
    for index, entry in ipairs(CATEGORY_ORDER) do
        local button = createCategoryButton(frame.sidebar, entry.label)
        if index == 1 then
            button:SetPoint("TOPLEFT", frame.sidebar, "TOPLEFT", navButtonConfig.startX or 12, navButtonConfig.startY or -18)
        else
            button:SetPoint("TOPLEFT", previousButton, "BOTTOMLEFT", 0, -(navButtonConfig.spacing or 4))
        end
        button:SetScript("OnClick", function()
            selectCategory(frame, entry.key)
        end)
        frame.CategoryButtons[entry.key] = button
        previousButton = button
    end

    frame.Pages.interface = createScrollPage(frame.contentInset, createInterfacePage, frame)
    frame.Pages.display = createDisplayPage(frame.contentInset, frame)
    frame.Pages.tracking = createScrollPage(frame.contentInset, createTrackingPage)
    frame.Pages.engine = createScrollPage(frame.contentInset, createEnginePage)
    frame.Pages.auction = createScrollPage(frame.contentInset, createAuctionPage)
    frame.Pages.selltab = createScrollPage(frame.contentInset, createAuctionSwitchPage)
    frame.Pages.data = createScrollPage(frame.contentInset, createDataPage)
    frame.Pages.info = createScrollPage(frame.contentInset, createInfoPage)
    if FWR.CreateManualPage then
        frame.Pages.manual = createScrollPage(frame.contentInset, FWR.CreateManualPage, frame)
    end

    selectCategory(frame, "interface")

    FWR.ControlPanelWindow = frame
    FWR.ControlPanel = frame
    return frame
end

function FWR:OpenControlPanelWindow()
    local frame = buildWindow()
    selectCategory(frame, "interface")
    refreshInterfaceDependencies(frame)
    if self.ApplySettingsVisibilityRules then
        self:ApplySettingsVisibilityRules(true)
    end
    frame:Show()
    frame:Raise()
end
