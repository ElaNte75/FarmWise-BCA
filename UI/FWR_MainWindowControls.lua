local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- Main window controls: a lock (with an optional auto-lock) and a minimize button.
--   locked    the window cannot be dragged
--   minimized the window is replaced by a small button on one of its corners (or its center), chosen in
--             the Interface options; its position never changes, so it opens again exactly where it was
-- The main window can also be minimized by the combat rule ("Minimize main window during combat").

local AUTO_LOCK_SECONDS = 60
local BUTTON_SIZE = 20
local MINI_BUTTON_WIDTH = 62   -- about the size of a chat tab
local MINI_BUTTON_HEIGHT = 20

local controls = {}
local autoLockRun = 0

local function getUi()
    FWR.Settings = FWR.Settings or {}
    FWR.Settings.ui = FWR.Settings.ui or {}
    return FWR.Settings.ui
end

local function touch()
    if FWR.TouchDatabase then
        FWR:TouchDatabase()
    end
end

local function showTip(owner, text)
    if FWR.ShowSimpleTooltip then
        FWR:ShowSimpleTooltip(owner, text)
    end
end

local function hideTip()
    if FWR.HideSimpleTooltip then
        FWR:HideSimpleTooltip()
    end
end

local function refreshLockButton()
    local button = controls.lockButton
    if not button or not button.icon then
        return
    end

    button.icon:SetTexture(getUi().lockMainWindow == true and "Interface/Buttons/LockButton-Locked-Up" or "Interface/Buttons/LockButton-Unlocked-Up")
end

-- Starts (again) the countdown after which an unlocked window locks itself. Called when the window is
-- unlocked, after every move, at login and when the option is changed.
function FWR:RestartMainWindowAutoLock()
    autoLockRun = autoLockRun + 1
    local ui = getUi()
    if ui.lockMainWindow == true or ui.autoLockMainWindow == false then
        return
    end

    local mine = autoLockRun
    C_Timer.After(AUTO_LOCK_SECONDS, function()
        if mine ~= autoLockRun then
            return
        end
        local current = getUi()
        if current.lockMainWindow ~= true and current.autoLockMainWindow ~= false then
            FWR:SetMainWindowLocked(true)
        end
    end)
end

function FWR:SetMainWindowLocked(locked)
    getUi().lockMainWindow = locked == true
    touch()
    refreshLockButton()
    self:RestartMainWindowAutoLock()
end

function FWR:NoteMainWindowMoved()
    self:RestartMainWindowAutoLock()
end

-- Shows the window, the small button, or neither, from the settings (and the combat rule).
function FWR:ApplyMainWindowPresentation(inCombat)
    local frame = self.MainFrame
    if not frame then
        return
    end

    local ui = getUi()
    if inCombat == nil then
        inCombat = self.IsPlayerInCombat and self:IsPlayerInCombat() or false
    end

    local wanted = ui.mainWindowVisible ~= false
    -- Minimized by the fight: it goes back after the fight only when "Open it again after combat" is on. What
    -- you minimized yourself (the window's own button) is never opened for you.
    if ui.hideMainWindowInCombat ~= true then
        self.minimizedByCombat = nil
    elseif inCombat then
        self.minimizedByCombat = true
    elseif ui.restoreMainWindowAfterCombat == true then
        self.minimizedByCombat = nil
    end
    local minimized = ui.mainWindowMinimized == true or self.minimizedByCombat == true
    local mini = controls.miniButton

    if wanted and not minimized then
        if not frame:IsShown() then
            frame:Show()
        end
        if mini then
            mini:Hide()
        end
    elseif wanted and mini then
        if frame:IsShown() then
            frame:Hide()
        end
        local corner = ui.minimizeCorner
        if corner ~= "TOPLEFT" and corner ~= "TOPRIGHT" and corner ~= "BOTTOMRIGHT" and corner ~= "CENTER" then
            corner = "BOTTOMLEFT"
        end
        mini:ClearAllPoints()
        mini:SetPoint(corner, frame, corner, 0, 0)
        mini:SetScale(frame:GetScale() or 1)
        mini:Show()
    else
        if frame:IsShown() then
            frame:Hide()
        end
        if mini then
            mini:Hide()
        end
    end
end

-- the small button the window is turned into (nil before the window exists): the floating loot text rises from it
function FWR:GetMainWindowMiniButton()
    return controls.miniButton
end

function FWR:SetMainWindowMinimized(minimized)
    getUi().mainWindowMinimized = minimized == true
    if minimized ~= true then
        self.minimizedByCombat = nil   -- you opened it yourself
    end
    touch()
    self:ApplyMainWindowPresentation()
end

local function createHeaderButton(parent, offsetX, offsetY, normal, pushed, highlight)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", offsetX, offsetY or 2)
    button:SetFrameLevel(parent:GetFrameLevel() + 10)
    if normal then
        button:SetNormalTexture(normal)
        button:SetPushedTexture(pushed or normal)
        button:SetHighlightTexture(highlight or normal, "ADD")
    end
    return button
end

-- Both header buttons look the same: a dark square with the window's gold border and a gold sign.
local function createFramedButton(parent, offsetX, offsetY)
    local button = createHeaderButton(parent, offsetX, offsetY)
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("TOPLEFT", 3, -3)
    background:SetPoint("BOTTOMRIGHT", -3, 3)
    background:SetColorTexture(0.16, 0.13, 0.06, 0.95)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 3, -3)
    highlight:SetPoint("BOTTOMRIGHT", -3, 3)
    highlight:SetColorTexture(1, 1, 1, 0.2)
    if FWR.AddPanelBorder then
        local border = FWR:AddPanelBorder(button)
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", 2, -2)
        border:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    return button
end

-- A gold "minus" (the game's own minimize picture looks like a close button).
local function createMinusButton(parent, offsetX, offsetY)
    local button = createFramedButton(parent, offsetX, offsetY)
    local bar = button:CreateTexture(nil, "ARTWORK")
    bar:SetSize(10, 3)
    bar:SetPoint("BOTTOM", 0, 5)
    bar:SetColorTexture(1, 0.82, 0, 1)
    return button
end

-- The game's own padlock (closed / open) in gold. The picture has wide empty margins, so it is drawn
-- larger than the button; only the padlock itself is visible.
local function createLockButton(parent, offsetX, offsetY)
    local button = createFramedButton(parent, offsetX, offsetY)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetDesaturated(true)
    icon:SetVertexColor(1, 0.82, 0)
    button.icon = icon
    return button
end

-- Called once by the main window: the minimize button goes in the header, and the lock below it, in the
-- footer, at the right of the Advisor button (the same vertical line).
function FWR:CreateMainWindowControls(frame, header, footer)
    if controls.lockButton or not frame or not header then
        return
    end

    controls.minimizeButton = createMinusButton(header, -2)
    controls.minimizeButton:SetScript("OnClick", function()
        FWR:SetMainWindowMinimized(true)
    end)
    controls.minimizeButton:SetScript("OnEnter", function(button)
        showTip(button, "Minimize\nShrinks the window to a small button at its bottom-left corner. Click that button to open it again.")
    end)
    controls.minimizeButton:SetScript("OnLeave", hideTip)

    controls.lockButton = createLockButton(footer or header, -2, footer and -4 or nil)
    controls.lockButton:SetScript("OnClick", function()
        FWR:SetMainWindowLocked(getUi().lockMainWindow ~= true)
    end)
    controls.lockButton:SetScript("OnEnter", function(button)
        if getUi().lockMainWindow == true then
            showTip(button, "Window locked\nThe window cannot be moved. Click to unlock it.")
        else
            showTip(button, "Window unlocked\nYou can drag the window. Click to lock it" ..
                (getUi().autoLockMainWindow ~= false and ", or it locks itself after a minute without moving." or "."))
        end
    end)
    controls.lockButton:SetScript("OnLeave", hideTip)
    refreshLockButton()

    -- the small button the window turns into
    local mini = CreateFrame("Button", nil, UIParent)
    mini:SetSize(MINI_BUTTON_WIDTH, MINI_BUTTON_HEIGHT)
    mini:SetFrameStrata("MEDIUM")
    mini:Hide()
    local background = mini:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.08, 0.08, 0.09, 0.95)
    local label = mini:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", 0, 0)
    label:SetText("FarmWise")
    local highlight = mini:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.15)
    if FWR.AddPanelBorder then
        FWR:AddPanelBorder(mini)
    end
    mini:SetScript("OnClick", function()
        FWR:SetMainWindowMinimized(false)
    end)
    mini:SetScript("OnEnter", function(button)
        showTip(button, "FarmWise\nClick to open the main window.")
    end)
    mini:SetScript("OnLeave", hideTip)
    controls.miniButton = mini

    self:RestartMainWindowAutoLock()
    self:ApplyMainWindowPresentation()
end
