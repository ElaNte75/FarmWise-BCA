local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local DEFAULT_ANGLE = 220
local BUTTON_SIZE = 31
local ICON_SIZE = 19
local MINIMAP_RADIUS = 80

local minimapShapeQuadrants = {
    ROUND = { true, true, true, true },
    SQUARE = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function ensureLauncherDB(self)
    self.Settings = self.Settings or {}
    self.Settings.ui = self.Settings.ui or {}
    if type(self.Settings.ui.launcherMinimap) ~= "table" then
        self.Settings.ui.launcherMinimap = { hide = false, angle = DEFAULT_ANGLE }
    end
    if self.Settings.ui.launcherMinimap.hide == nil then
        self.Settings.ui.launcherMinimap.hide = false
    end
    if self.Settings.ui.launcherMinimap.angle == nil then
        self.Settings.ui.launcherMinimap.angle = DEFAULT_ANGLE
    end
    return self.Settings.ui.launcherMinimap
end

local function getMinimapShape()
    if type(GetMinimapShape) == "function" then
        return GetMinimapShape() or "ROUND"
    end
    return "ROUND"
end

local function placeOnMinimap(button, angle)
    if not button or not Minimap then
        return
    end

    local x = math.cos(angle)
    local y = math.sin(angle)
    local shape = getMinimapShape()
    local quadTable = minimapShapeQuadrants[shape] or minimapShapeQuadrants.ROUND

    local q
    if x < 0 then
        if y < 0 then
            q = 1
        else
            q = 2
        end
    else
        if y < 0 then
            q = 4
        else
            q = 3
        end
    end

    local radius = MINIMAP_RADIUS
    if quadTable[q] == false then
        x = math.max(-radius, math.min(x * radius, radius))
        y = math.max(-radius, math.min(y * radius, radius))
    else
        x = x * radius
        y = y * radius
    end

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function refreshLauncherPosition(self)
    if not self or not self.LauncherIcon then
        return
    end
    local db = ensureLauncherDB(self)
    local angle = math.rad(tonumber(db.angle) or DEFAULT_ANGLE)
    placeOnMinimap(self.LauncherIcon, angle)
end

local function updateAngleFromCursor(self, button)
    if not self or not button or not Minimap then
        return
    end

    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not mx or not my or not cx or not cy or not scale or scale == 0 then
        return
    end

    cx = cx / scale
    cy = cy / scale

    local angle = math.deg(math.atan2(cy - my, cx - mx))
    local db = ensureLauncherDB(self)
    db.angle = angle
    if self.TouchDatabase then
        self:TouchDatabase()
    end
    refreshLauncherPosition(self)
end

function FWR:RefreshLauncherIcon()
    local button = self.LauncherIcon
    if not button then
        return
    end

    local db = ensureLauncherDB(self)
    if db.hide then
        button:Hide()
        return
    end

    refreshLauncherPosition(self)
    button:Show()
end

function FWR:CreateLauncherIcon()
    if self.LauncherIcon then
        self:RefreshLauncherIcon()
        return self.LauncherIcon
    end

    local button = CreateFrame("Button", "FarmWiseReforgedLauncherIcon", Minimap)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:EnableMouse(true)

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(53, 53)
    background:SetPoint("TOPLEFT", 7, -5)
    background:SetTexture("Interface/Minimap/MiniMap-TrackingBackground")
    button.background = background

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface/Icons/INV_Misc_Herb_16")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    button.border = border

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(23, 23)
    highlight:SetPoint("CENTER", 0, 1)
    highlight:SetTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")
    button.highlight = highlight

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            if FWR and FWR.ToggleMainFrameVisibleState then
                FWR:ToggleMainFrameVisibleState()
            end
        elseif mouseButton == "RightButton" then
            if FWR and FWR.OpenControlPanelWindow then
                FWR:OpenControlPanelWindow()
            end
        end
    end)

    button:SetScript("OnDragStart", function(selfButton)
        selfButton:SetScript("OnUpdate", function(updateButton)
            updateAngleFromCursor(FWR, updateButton)
        end)
    end)

    button:SetScript("OnDragStop", function(selfButton)
        selfButton:SetScript("OnUpdate", nil)
        if FWR and FWR.TouchDatabase then
            FWR:TouchDatabase()
        end
        refreshLauncherPosition(FWR)
    end)

    button:SetScript("OnEnter", function(selfButton)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(selfButton, "ANCHOR_LEFT")
        GameTooltip:SetText("FarmWise " .. tostring(FWR.PRODUCT_NAME or "BCA") .. " v" .. tostring(FWR.VERSION or "") .. (FWR.RELEASE_STAGE and (" " .. FWR.RELEASE_STAGE) or ""), 1, 0.82, 0)
        GameTooltip:AddLine("Left Click: Show / Hide Main Frame", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right Click: Open Control Panel", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Drag: Move around Minimap", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    self.LauncherIcon = button
    self:RefreshLauncherIcon()
    return button
end
