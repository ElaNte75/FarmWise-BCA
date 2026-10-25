local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- Shared look for FarmWise windows. The gold border is the one of the main window
-- (UI_CONFIG.MainFrame.frame.backdrop) and is drawn on top of the window's content.

function FWR:AddPanelBorder(frame)
    local mainFrameConfig = self.UI_CONFIG and self.UI_CONFIG.MainFrame and self.UI_CONFIG.MainFrame.frame or {}
    local backdrop = mainFrameConfig.backdrop or {}
    local borderColor = backdrop.borderColor or { 0.72, 0.62, 0.33 }

    local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    border:SetAllPoints(frame)
    border:SetFrameLevel(frame:GetFrameLevel() + 20)
    border:SetBackdrop({
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = backdrop.edgeSize or 12,
    })
    border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], backdrop.borderAlpha or 0.95)
    return border
end
