local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil

local applyFrameBackdrop

local function unpackColor(rgb, alpha, fallbackRGB, fallbackAlpha)
    local source = rgb or fallbackRGB or { 1, 1, 1 }
    return source[1] or 1, source[2] or 1, source[3] or 1, alpha or fallbackAlpha or 1
end

applyFrameBackdrop = function(frame, backdropConfig)
    if not frame or not frame.SetBackdrop then
        return
    end

    local edgeSize = (backdropConfig and backdropConfig.edgeSize) or 12
    local insets = (backdropConfig and backdropConfig.insets) or { left = 3, right = 3, top = 3, bottom = 3 }

    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = edgeSize,
        insets = insets,
    })

    frame:SetBackdropColor(unpackColor(backdropConfig and backdropConfig.bgColor, backdropConfig and backdropConfig.bgAlpha, { 0.05, 0.05, 0.06 }, 0.95))
    frame:SetBackdropBorderColor(unpackColor(backdropConfig and backdropConfig.borderColor, backdropConfig and backdropConfig.borderAlpha, { 0.72, 0.62, 0.33 }, 0.95))
end

local function applySolidBlockBackdrop(block, cfg)
    if block.SetBackdrop then
        block:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            tile = true,
            tileSize = 16,
            edgeSize = 0,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        block:SetBackdropColor(unpackColor(cfg.bgColor, cfg.bgAlpha, { 0.1, 0.1, 0.11 }, 0.75))
    else
        local texture = block:CreateTexture(nil, "BACKGROUND")
        texture:SetAllPoints(true)
        texture:SetColorTexture(unpackColor(cfg.bgColor, cfg.bgAlpha, { 0.1, 0.1, 0.11 }, 0.75))
        block.bgTexture = texture
    end
end

local function positionTopAnchored(region, parent, cfg)
    region:ClearAllPoints()
    local point = cfg.point or "TOPLEFT"
    local relativePoint = cfg.relativePoint or point
    local x = tonumber(cfg.x) or 0
    local y = -(tonumber(cfg.y) or 0)
    region:SetPoint(point, parent, relativePoint, x, y)
end

local function applyTextElement(element, cfg, parent)
    if not element or not cfg or not parent then
        return
    end

    positionTopAnchored(element, parent, cfg)

    if cfg.width then element:SetWidth(cfg.width) end
    if cfg.height then element:SetHeight(cfg.height) end
    if cfg.font then element:SetFontObject(cfg.font) end
    if cfg.fontPath and element.SetFont then
        local _, currentSize, currentFlags = element:GetFont()
        element:SetFont(cfg.fontPath, tonumber(cfg.fontSize) or currentSize or 14, cfg.fontFlags or currentFlags)
    end
    if cfg.justifyH then element:SetJustifyH(cfg.justifyH) end
    if cfg.justifyV then element:SetJustifyV(cfg.justifyV) end
    if cfg.text then element:SetText(cfg.text) end

    element:SetTextColor(unpackColor(cfg.textColor, cfg.textAlpha, { 1, 1, 1 }, 1))
end


local function layoutMainFrameHeader(frame)
    if not frame then
        return
    end

    local elements = FWR.UI_CONFIG and FWR.UI_CONFIG.MainFrame and FWR.UI_CONFIG.MainFrame.elements or {}

    for _, key in ipairs({ "zone", "zoneSeparator", "subzone", "totalTimeLabel", "totalTimeValue", "runtimeSeparator", "runtimeLabel", "runtimeValue" }) do
        if frame[key] and frame[key].SetWordWrap then
            frame[key]:SetWordWrap(false)
        end
    end

    if frame.title and frame.titleAccent then
        local titleCfg = elements.title or {}
        local accentCfg = elements.titleAccent or {}
        frame.titleAccent:ClearAllPoints()
        frame.titleAccent:SetPoint("LEFT", frame.title, "RIGHT", tonumber(accentCfg.spacingFromTitle) or 6, tonumber(accentCfg.y) or 0)

        if frame.titleVersion then
            frame.titleVersion:ClearAllPoints()
            frame.titleVersion:SetPoint("LEFT", frame.titleAccent, "RIGHT", tonumber((elements.titleVersion or {}).spacingFromTitle) or 6, -1)
        end
    end

    if frame.totalTimeLabel and frame.totalTimeValue and frame.runtimeSeparator and frame.runtimeLabel and frame.runtimeValue then
        local totalValueWidth = math.max(frame.totalTimeValue:GetStringWidth() or 0, 24)
        local separatorWidth = math.max(frame.runtimeSeparator:GetStringWidth() or 0, 8)
        local runtimeLabelWidth = math.max(frame.runtimeLabel:GetStringWidth() or 0, 24)
        local totalValueCfg = elements.totalTimeValue or {}
        local runtimeSeparatorCfg = elements.runtimeSeparator or {}
        local runtimeLabelCfg = elements.runtimeLabel or {}
        local runtimeValueCfg = elements.runtimeValue or {}

        frame.totalTimeValue:SetWidth(totalValueWidth)

        frame.runtimeSeparator:ClearAllPoints()
        frame.runtimeSeparator:SetPoint("LEFT", frame.totalTimeValue, "RIGHT", tonumber(runtimeSeparatorCfg.spacingFromTotalValue) or 8, 0)
        frame.runtimeSeparator:SetWidth(separatorWidth)

        frame.runtimeLabel:ClearAllPoints()
        frame.runtimeLabel:SetPoint("LEFT", frame.runtimeSeparator, "RIGHT", tonumber(runtimeLabelCfg.spacingFromSeparator) or 8, 0)
        frame.runtimeLabel:SetWidth(runtimeLabelWidth)

        frame.runtimeValue:ClearAllPoints()
        frame.runtimeValue:SetPoint("LEFT", frame.runtimeLabel, "RIGHT", tonumber(runtimeValueCfg.spacingFromLabel) or 4, 0)

        -- zone above "Total", sub-zone above "Session", and the two "-" one under the other
        if frame.zone and frame.zoneSeparator and frame.subzone then
            local parent = frame.zone:GetParent()
            local rowY = -(tonumber((elements.zone or {}).y) or 21)
            local gap = 6
            local totalLeft = tonumber((elements.totalTimeLabel or {}).x) or 5
            local totalRight = (tonumber(totalValueCfg.x) or 40) + totalValueWidth
            local separatorLeft = totalRight + (tonumber(runtimeSeparatorCfg.spacingFromTotalValue) or 8)
            local sessionLeft = separatorLeft + separatorWidth + (tonumber(runtimeLabelCfg.spacingFromSeparator) or 8)
            local sessionRight = sessionLeft + runtimeLabelWidth + (tonumber(runtimeValueCfg.spacingFromLabel) or 4) + (frame.runtimeValue:GetStringWidth() or 0)
            local rightLimit = (parent:GetWidth() or 405) - 10

            -- names are never shortened: they take the room they need
            frame.zone:SetWidth(0)
            frame.subzone:SetWidth(0)
            frame.zone:SetJustifyH("LEFT")
            frame.subzone:SetJustifyH("LEFT")
            local zoneWidth = frame.zone:GetStringWidth() or 0
            local subzoneWidth = frame.subzone:GetStringWidth() or 0

            -- a name shorter than the group below it is centered over it; a longer one starts at the group's left edge
            local function placeOver(nameWidth, groupLeft, groupRight)
                local groupWidth = groupRight - groupLeft
                if nameWidth <= groupWidth then
                    return groupLeft + (groupWidth - nameWidth) / 2
                end
                return groupLeft
            end

            -- the zone name starts exactly where "Total:" starts and extends to the right
            local zoneLeft = totalLeft

            -- the dash stays above the dash below; a long zone pushes it, and the sub-zone, to the right
            frame.runtimeSeparator:SetJustifyH("CENTER")
            frame.zoneSeparator:SetJustifyH("CENTER")
            frame.zoneSeparator:SetWidth(separatorWidth)
            local dashLeft = math.max(separatorLeft, zoneLeft + zoneWidth + gap)
            local subzoneLeft = math.max(placeOver(subzoneWidth, sessionLeft, sessionRight), dashLeft + separatorWidth + gap)

            -- only a name that would leave the window is shortened
            if subzoneLeft + subzoneWidth > rightLimit then
                frame.subzone:SetWidth(math.max(24, rightLimit - subzoneLeft))
            end

            frame.zone:ClearAllPoints()
            frame.zone:SetPoint("TOPLEFT", parent, "TOPLEFT", zoneLeft, rowY)
            frame.zoneSeparator:ClearAllPoints()
            frame.zoneSeparator:SetPoint("TOPLEFT", parent, "TOPLEFT", dashLeft, rowY)
            frame.subzone:ClearAllPoints()
            frame.subzone:SetPoint("TOPLEFT", parent, "TOPLEFT", subzoneLeft, rowY)
        end
    end
end

local function getMainFrameScrollConfig()
    local mainFrameConfig = FWR.UI_CONFIG and FWR.UI_CONFIG.MainFrame
    return (type(mainFrameConfig) == "table" and type(mainFrameConfig.scroll) == "table") and mainFrameConfig.scroll or {}
end

local function getMainRenderLayoutMetrics()
    if FWR.GetMainRenderLayoutConfig then
        local layout = FWR:GetMainRenderLayoutConfig() or {}
        return {
            visibleRows = math.max(1, math.floor(tonumber(layout.visibleRows) or 5)),
            rowHeight = math.max(12, math.floor(tonumber(layout.rowHeight) or 16)),
            topPadding = math.max(0, math.floor(tonumber(layout.topPadding) or 2)),
            bottomPadding = math.max(0, math.floor(tonumber(layout.bottomPadding) or 4)),
        }
    end

    return {
        visibleRows = 5,
        rowHeight = 16,
        topPadding = 2,
        bottomPadding = 4,
    }
end

local function getMainFrameScrollGeometry(contentWidth)
    local scrollConfig = getMainFrameScrollConfig()
    local layout = getMainRenderLayoutMetrics()
    local baseGapBefore = 2
    local baseGapAfter = 2
    local baseBottomOffset = 2
    local baseTopOffset = 2
    local baseScrollWidth = 10
    local visibleDataHeight = (layout.visibleRows * layout.rowHeight) + layout.topPadding + layout.bottomPadding
    local scrollWidth = math.max(6, baseScrollWidth + (tonumber(scrollConfig.width) or 0))
    local scrollLeft = math.max(0, (tonumber(contentWidth) or 0) + baseGapBefore + (tonumber(scrollConfig.x) or 0))
    local scrollBottom = math.max(0, baseBottomOffset + (tonumber(scrollConfig.y) or 0))
    local scrollHeight = math.max(40, visibleDataHeight - baseTopOffset - baseBottomOffset + (tonumber(scrollConfig.height) or 0))
    local shellWidth = math.max(0, (tonumber(contentWidth) or 0) + baseGapBefore + scrollWidth + baseGapAfter)
    return {
        gapBefore = baseGapBefore,
        gapAfter = baseGapAfter,
        topOffset = baseTopOffset,
        bottomOffset = baseBottomOffset,
        width = scrollWidth,
        height = scrollHeight,
        x = scrollLeft,
        y = scrollBottom,
        shellWidth = shellWidth,
        visibleDataHeight = visibleDataHeight,
    }
end

local function computeMainFrameContentHeight(config)
    local blocks = config.blocks or {}
    local content = blocks.content or {}
    local layout = getMainRenderLayoutMetrics()
    local visibleScrollHeight = (layout.visibleRows * layout.rowHeight) + layout.topPadding + layout.bottomPadding
    local headerHeight = 22
    local headerTopInset = 8
    local dividerOffset = 1
    local scrollAreaTop = headerTopInset + headerHeight + dividerOffset + 6
    local contentBottomInset = 8
    local calculatedHeight = scrollAreaTop + visibleScrollHeight + contentBottomInset
    return calculatedHeight
end

local function computeMainFrameWidth(config)
    local frame = config.frame or {}
    local contentWidth = (FWR.GetResolvedMainFrameContentWidth and FWR:GetResolvedMainFrameContentWidth()) or nil
    local minimumContentWidth = (FWR.GetMinimumMainFrameContentWidth and FWR:GetMinimumMainFrameContentWidth()) or nil
    if FWR.GetResolvedMainFrameShellWidth then
        local resolvedShellWidth = contentWidth and FWR:GetResolvedMainFrameShellWidth(contentWidth) or 0
        local minimumShellWidth = minimumContentWidth and FWR:GetResolvedMainFrameShellWidth(minimumContentWidth) or 0
        return math.max(tonumber(frame.width) or 405, resolvedShellWidth, minimumShellWidth)
    end
    return tonumber(frame.width) or 405
end

local function computeMainFrameHeight(config)
    local blocks = config.blocks or {}
    local header = blocks.header or {}
    local footer = blocks.footer or {}
    return (tonumber(header.height) or 0) + computeMainFrameContentHeight(config) + (tonumber(footer.height) or 0)
end

function FWR:GetMainFrameShellMetrics(resolvedContentWidth)
    local config = self.UI_CONFIG and self.UI_CONFIG.MainFrame or {}
    local layout = getMainRenderLayoutMetrics()
    local headerCfg = config.blocks and config.blocks.header or {}
    local footerCfg = config.blocks and config.blocks.footer or {}
    local contentWidth = math.max(0, tonumber(resolvedContentWidth) or 0)
    local contentHeight = computeMainFrameContentHeight(config)
    local scrollMetrics = getMainFrameScrollGeometry(contentWidth)
    local frameWidth = scrollMetrics.shellWidth + 16
    local frameHeight = (tonumber(headerCfg.height) or 0) + contentHeight + (tonumber(footerCfg.height) or 0)
    return {
        contentWidth = contentWidth,
        contentHeight = contentHeight,
        frameWidth = frameWidth,
        frameHeight = frameHeight,
        scrollMetrics = scrollMetrics,
        visibleRows = layout.visibleRows,
        rowHeight = layout.rowHeight,
        topPadding = layout.topPadding,
        bottomPadding = layout.bottomPadding,
    }
end

function FWR:ApplyResolvedMainFrameLayout(layoutInfo)
    local frame = self.MainFrame
    if not frame or not frame.blocks or not frame.renderHost then
        return
    end
    local currentContentWidth = frame.renderHost.resolvedContentWidth or 0
    local requestedContentWidth = type(layoutInfo) == "table" and tonumber(layoutInfo.contentWidth) or tonumber(layoutInfo)
    if not requestedContentWidth or requestedContentWidth <= 0 then
        requestedContentWidth = currentContentWidth
    end
    local minimumContentWidth = (self.GetMinimumMainFrameContentWidth and self:GetMinimumMainFrameContentWidth()) or 0
    if requestedContentWidth and requestedContentWidth > 0 then
        requestedContentWidth = math.max(requestedContentWidth, minimumContentWidth)
    end
    local metrics = self:GetMainFrameShellMetrics(requestedContentWidth)
    if currentContentWidth == requestedContentWidth and math.abs((frame:GetWidth() or 0) - metrics.frameWidth) < 0.5 and math.abs((frame.blocks.content:GetHeight() or 0) - metrics.contentHeight) < 0.5 then
        return
    end

    local oldWidth = frame:GetWidth() or metrics.frameWidth
    local oldHeight = frame:GetHeight() or metrics.frameHeight
    local left = frame:GetLeft()
    local bottom = frame:GetBottom()
    frame:SetSize(metrics.frameWidth, metrics.frameHeight)
    if left and bottom then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    end

    local blocks = frame.blocks
    local config = self.UI_CONFIG and self.UI_CONFIG.MainFrame or {}
    local headerCfg = config.blocks and config.blocks.header or {}
    local contentCfg = config.blocks and config.blocks.content or {}
    local footerCfg = config.blocks and config.blocks.footer or {}

    blocks.header:SetSize(metrics.frameWidth, tonumber(headerCfg.height) or 48)
    blocks.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", tonumber(footerCfg.x) or 0, tonumber(footerCfg.y) or 0)
    blocks.footer:SetSize(metrics.frameWidth, tonumber(footerCfg.height) or 40)
    blocks.content:SetPoint("TOPLEFT", frame, "TOPLEFT", tonumber(contentCfg.insetLeft) or 0, -((tonumber(headerCfg.height) or 48) + (tonumber(contentCfg.insetTop) or 0)))
    blocks.content:SetSize(metrics.frameWidth - (tonumber(contentCfg.insetLeft) or 0) - (tonumber(contentCfg.insetRight) or 0), metrics.contentHeight)

    local host = frame.renderHost
    local contentLeftInset = 8
    local headerTopInset = 8
    local headerHeight = 22
    local dividerOffset = 1
    local scrollAreaTop = headerTopInset + headerHeight + dividerOffset + 6
    local scrollFrameWidth = metrics.contentWidth
    local scrollMetrics = metrics.scrollMetrics or getMainFrameScrollGeometry(metrics.contentWidth)
    local scrollFrameHeight = scrollMetrics.visibleDataHeight

    host.resolvedContentWidth = metrics.contentWidth
    host.columnsHeader:ClearAllPoints()
    host.columnsHeader:SetPoint("TOPLEFT", blocks.content, "TOPLEFT", contentLeftInset, -headerTopInset)
    host.columnsHeader:SetPoint("TOPRIGHT", blocks.content, "TOPLEFT", contentLeftInset + scrollFrameWidth, -headerTopInset)
    host.columnsHeader:SetHeight(headerHeight)

    host.divider:ClearAllPoints()
    host.divider:SetPoint("TOPLEFT", host.columnsHeader, "BOTTOMLEFT", 0, -1)
    host.divider:SetPoint("TOPRIGHT", host.columnsHeader, "BOTTOMRIGHT", 0, -1)
    host.divider:SetHeight(1)

    host.scrollFrame:ClearAllPoints()
    host.scrollFrame:SetPoint("TOPLEFT", blocks.content, "TOPLEFT", contentLeftInset, -scrollAreaTop)
    host.scrollFrame:SetPoint("BOTTOMRIGHT", blocks.content, "TOPLEFT", contentLeftInset + scrollFrameWidth, -(scrollAreaTop + scrollFrameHeight))

    local scrollBar = host.scrollFrame.ScrollBar or host.scrollFrame.scrollBar or (_G[(host.scrollFrame:GetName() or "") .. "ScrollBar"])
    if scrollBar then
        local buttonSize = math.max(scrollMetrics.width + 6, 14)
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("BOTTOMLEFT", blocks.content, "BOTTOMLEFT", scrollMetrics.x, scrollMetrics.y)
        scrollBar:SetSize(scrollMetrics.width, scrollMetrics.height)
        if scrollBar.Track then
            scrollBar.Track:ClearAllPoints()
            scrollBar.Track:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
            scrollBar.Track:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
        end
        if scrollBar.ThumbTexture then
            scrollBar.ThumbTexture:SetWidth(scrollMetrics.width)
        end
        if scrollBar.ScrollUpButton then
            scrollBar.ScrollUpButton:ClearAllPoints()
            scrollBar.ScrollUpButton:SetPoint("TOP", scrollBar, "TOP", 0, 0)
            scrollBar.ScrollUpButton:SetSize(buttonSize, buttonSize)
        end
        if scrollBar.ScrollDownButton then
            scrollBar.ScrollDownButton:ClearAllPoints()
            scrollBar.ScrollDownButton:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, 0)
            scrollBar.ScrollDownButton:SetSize(buttonSize, buttonSize)
        end
    end
end

local function createMainBlocks(frame, frameConfig, config)
    local blocks = {}
    local headerCfg = config.blocks.header or {}
    local contentCfg = config.blocks.content or {}
    local footerCfg = config.blocks.footer or {}
    local frameWidth = frame:GetWidth() or frameConfig.width or 405
    local frameHeight = frame:GetHeight()

    blocks.header = CreateFrame("Frame", nil, frame, backdropTemplate)
    blocks.header:SetPoint("TOPLEFT", frame, "TOPLEFT", tonumber(headerCfg.x) or 0, -(tonumber(headerCfg.y) or 0))
    blocks.header:SetSize(frameWidth, tonumber(headerCfg.height) or 48)
    applySolidBlockBackdrop(blocks.header, headerCfg)

    blocks.footer = CreateFrame("Frame", nil, frame, backdropTemplate)
    blocks.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", tonumber(footerCfg.x) or 0, tonumber(footerCfg.y) or 0)
    blocks.footer:SetSize(frameWidth, tonumber(footerCfg.height) or 40)
    applySolidBlockBackdrop(blocks.footer, footerCfg)

    blocks.content = CreateFrame("Frame", nil, frame, backdropTemplate)
    blocks.content:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        tonumber(contentCfg.insetLeft) or 0,
        -((tonumber(headerCfg.height) or 48) + (tonumber(contentCfg.insetTop) or 0))
    )
    local contentWidth = frameWidth - (tonumber(contentCfg.insetLeft) or 0) - (tonumber(contentCfg.insetRight) or 0)
    local contentHeight = computeMainFrameContentHeight(config)
    blocks.content:SetSize(contentWidth, contentHeight)
    applySolidBlockBackdrop(blocks.content, contentCfg)

    return blocks
end

local function createConfiguredFontString(parent, cfg)
    local fs = parent:CreateFontString(nil, "OVERLAY", cfg.font or "GameFontHighlight")
    applyTextElement(fs, cfg, parent)
    return fs
end

local function createMoneyValueFontString(parent, anchorRegion, cfg)
    local fs = parent:CreateFontString(nil, "OVERLAY", (cfg and cfg.font) or "GameFontHighlightSmall")
    fs:SetJustifyH((cfg and cfg.justifyH) or "CENTER")
    fs:SetJustifyV((cfg and cfg.justifyV) or "MIDDLE")
    fs:SetTextColor(unpackColor(cfg and cfg.textColor, cfg and cfg.textAlpha, { 0.90, 0.90, 0.92 }, 1))
    fs:SetText("0")
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", anchorRegion, "TOPLEFT", tonumber(cfg and cfg.xOffset) or 0, -(tonumber(cfg and cfg.yOffset) or 0))
    fs:SetWidth(tonumber(cfg and cfg.width) or 24)
    return fs
end

local function applyMoneyColumnLayout(group)
    if not group or not group.gold or not group.silver or not group.copper then
        return
    end

    local cfg = group.config or {}
    local widths = group.widths or {}
    local goldWidth = widths.gold or (math.max(group.gold:GetStringWidth() or 0, 12) + (tonumber(cfg.goldWidthPadding) or 6))
    local silverWidth = widths.silver or (math.max(group.silver:GetStringWidth() or 0, 12) + (tonumber(cfg.silverWidthPadding) or 6))
    local copperWidth = widths.copper or (math.max(group.copper:GetStringWidth() or 0, 12) + (tonumber(cfg.copperWidthPadding) or 6))

    -- numbers end at the right edge of their column, so the coin icons stand in one line
    group.gold:SetJustifyH("RIGHT")
    group.silver:SetJustifyH("RIGHT")
    group.copper:SetJustifyH("RIGHT")

    group.gold:SetWidth(goldWidth)

    group.silver:ClearAllPoints()
    group.silver:SetPoint("LEFT", group.gold, "RIGHT", tonumber(cfg.silverOffsetX) or 0, tonumber(cfg.silverOffsetY) or 0)
    group.silver:SetWidth(silverWidth)

    group.copper:ClearAllPoints()
    group.copper:SetPoint("LEFT", group.silver, "RIGHT", tonumber(cfg.copperOffsetX) or 0, tonumber(cfg.copperOffsetY) or 0)
    group.copper:SetWidth(copperWidth)
end

local function applyMainFrameMoneyLayout(frame)
    if not frame or not frame.totalGoldGold or not frame.totalGoldSilver or not frame.totalGoldCopper or not frame.estimatedGoldPerHourGold or not frame.estimatedGoldPerHourSilver or not frame.estimatedGoldPerHourCopper then
        return
    end

    local elements = FWR.UI_CONFIG and FWR.UI_CONFIG.MainFrame and FWR.UI_CONFIG.MainFrame.elements or {}

    local totalGroup = {
        gold = frame.totalGoldGold,
        silver = frame.totalGoldSilver,
        copper = frame.totalGoldCopper,
        config = elements.totalGoldMoneyLayout,
    }
    local hourlyGroup = {
        gold = frame.estimatedGoldPerHourGold,
        silver = frame.estimatedGoldPerHourSilver,
        copper = frame.estimatedGoldPerHourCopper,
        config = elements.estimatedGoldPerHourMoneyLayout,
    }

    -- the two labels end at the same place: the colons line up and the words grow to the left
    if frame.totalGoldLabel and frame.estimatedGoldPerHourLabel then
        local labelWidth = math.max(frame.totalGoldLabel:GetStringWidth() or 0, frame.estimatedGoldPerHourLabel:GetStringWidth() or 0)
        for _, label in ipairs({ frame.totalGoldLabel, frame.estimatedGoldPerHourLabel }) do
            label:SetWidth(labelWidth)
            label:SetJustifyH("RIGHT")
        end

        -- the amounts start a little after the colon, however wide the labels are
        for _, pair in ipairs({
            { frame.totalGoldValue, elements.totalGoldLabel, elements.totalGoldValue },
            { frame.estimatedGoldPerHourValue, elements.estimatedGoldPerHourLabel, elements.estimatedGoldPerHourValue },
        }) do
            local anchor, labelConfig, valueConfig = pair[1], pair[2] or {}, pair[3] or {}
            anchor:ClearAllPoints()
            anchor:SetPoint("TOPLEFT", anchor:GetParent(), "TOPLEFT",
                (tonumber(labelConfig.x) or 10) + labelWidth + (tonumber(valueConfig.spacingFromLabel) or 6), -(tonumber(valueConfig.y) or 0))
        end
    end

    -- both rows use the widest width of each column
    local function columnWidth(key, paddingKey)
        local widest = 0
        for _, group in ipairs({ totalGroup, hourlyGroup }) do
            local width = math.max(group[key]:GetStringWidth() or 0, 12) + (tonumber((group.config or {})[paddingKey]) or 6)
            widest = math.max(widest, width)
        end
        return widest
    end
    local shared = {
        gold = columnWidth("gold", "goldWidthPadding"),
        silver = columnWidth("silver", "silverWidthPadding"),
        copper = columnWidth("copper", "copperWidthPadding"),
    }
    totalGroup.widths = shared
    hourlyGroup.widths = shared

    applyMoneyColumnLayout(totalGroup)
    applyMoneyColumnLayout(hourlyGroup)
end


local function getAccentGoldColor()
    if FWR.GetAccentGoldColor then
        return FWR:GetAccentGoldColor()
    end
    return 1.0, 0.82, 0.0, 1.0
end

local function attachSimpleTooltip(frame, textProvider)
    if not frame then
        return
    end

    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(selfFrame)
        if FWR.IsMainFrameTooltipEnabled and not FWR:IsMainFrameTooltipEnabled() then
            return
        end

        local tooltipText = type(textProvider) == "function" and textProvider(selfFrame) or textProvider
        if tooltipText and FWR.ShowSimpleTooltip then
            FWR:ShowSimpleTooltip(selfFrame, tooltipText)
        end
    end)
    frame:SetScript("OnLeave", function()
        if FWR.HideSimpleTooltip then
            FWR:HideSimpleTooltip()
        end
    end)
end

local function createFooterValueTooltipHitbox(parent, anchorRegion, cfg, textProvider)
    if not parent or not anchorRegion or type(cfg) ~= "table" then
        return nil
    end

    local hitbox = CreateFrame("Frame", nil, parent)
    hitbox:SetFrameLevel(parent:GetFrameLevel() + 5)
    hitbox:ClearAllPoints()
    hitbox:SetPoint("TOPLEFT", anchorRegion, "TOPLEFT", 0, 2)
    local anchorWidth = tonumber(anchorRegion.GetStringWidth and anchorRegion:GetStringWidth()) or tonumber(anchorRegion.GetWidth and anchorRegion:GetWidth()) or 0
    local configuredWidth = tonumber(cfg.hitboxWidth) or 0
    local safeWidth = math.max(40, math.min(math.max(anchorWidth + 72, 96), configuredWidth > 0 and configuredWidth or 140))
    hitbox:SetSize(safeWidth, math.max(12, tonumber(cfg.hitboxHeight) or 14))
    attachSimpleTooltip(hitbox, textProvider)
    return hitbox
end



local function createHeaderTooltipHitbox(parent, columnKey, textProvider)
    if not parent or type(columnKey) ~= "string" or columnKey == "" then
        return nil
    end

    local hitbox = CreateFrame("Frame", nil, parent)
    hitbox:SetFrameLevel(parent:GetFrameLevel() + 6)
    hitbox:Hide()
    attachSimpleTooltip(hitbox, textProvider)
    return hitbox
end

local function getSavedMainFramePosition(self)
    local settings = self and self.Settings
    local ui = settings and settings.ui
    local position = ui and ui.mainFramePosition
    if type(position) ~= "table" then
        return nil
    end
    return position
end

local function applyMainFramePosition(self, frame, frameConfig)
    if not frame then
        return
    end
    local position = getSavedMainFramePosition(self)
    frame:ClearAllPoints()
    if position and position.point and position.relativePoint then
        frame:SetPoint(position.point, UIParent, position.relativePoint, tonumber(position.x) or 0, tonumber(position.y) or 0)
        return
    end

    local anchorPoint = (frameConfig.anchor and frameConfig.anchor.point) or "TOPLEFT"
    local relativePoint = (frameConfig.anchor and frameConfig.anchor.relativePoint) or "TOPLEFT"
    local anchorX = tonumber(frameConfig.anchor and frameConfig.anchor.x) or 0
    local anchorY = tonumber(frameConfig.anchor and frameConfig.anchor.y) or 0

    local contentHeightFromConfig = tonumber(FWR.UI_CONFIG and FWR.UI_CONFIG.MainFrame and FWR.UI_CONFIG.MainFrame.blocks and FWR.UI_CONFIG.MainFrame.blocks.content and FWR.UI_CONFIG.MainFrame.blocks.content.height) or 0
    local computedContentHeight = computeMainFrameContentHeight(FWR.UI_CONFIG and FWR.UI_CONFIG.MainFrame or {})
    local frameHeightDelta = computedContentHeight - contentHeightFromConfig
    if anchorPoint == "TOPLEFT" and relativePoint == "TOPLEFT" and frameHeightDelta > 0 then
        anchorY = anchorY - frameHeightDelta
    end

    frame:SetPoint(anchorPoint, UIParent, relativePoint, anchorX, -anchorY)
end

local function saveMainFramePosition(self, frame)
    if not self or not frame then
        return
    end
    self.Settings = self.Settings or {}
    self.Settings.ui = self.Settings.ui or {}
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    self.Settings.ui.mainFramePosition = {
        point = point or "TOPLEFT",
        relativePoint = relativePoint or point or "TOPLEFT",
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
    }
    if self.TouchDatabase then
        self:TouchDatabase()
    end
end

local function createMainRenderHost(frame, contentBlock)
    if not frame or not contentBlock then
        return
    end

    local headerHeight = 22
    local headerTopInset = 8
    local dividerOffset = 1
    local contentLeftInset = 8
    local resolvedContentWidth = (FWR.GetResolvedMainFrameContentWidth and FWR:GetResolvedMainFrameContentWidth()) or ((contentBlock:GetWidth() or 0) - 22)
    local scrollMetrics = getMainFrameScrollGeometry(resolvedContentWidth)
    local scrollFrameHeight = scrollMetrics.visibleDataHeight
    local scrollAreaTop = headerTopInset + headerHeight + dividerOffset + 6
    local scrollFrameWidth = math.max(40, resolvedContentWidth)

    local header = CreateFrame("Frame", nil, contentBlock)
    header:SetPoint("TOPLEFT", contentBlock, "TOPLEFT", contentLeftInset, -headerTopInset)
    header:SetPoint("TOPRIGHT", contentBlock, "TOPLEFT", contentLeftInset + scrollFrameWidth, -headerTopInset)
    header:SetHeight(headerHeight)

    local function makeHeader(text, justify)
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH(justify or "LEFT")
        local red, green, blue, alpha = getAccentGoldColor()
        fs:SetTextColor(red, green, blue, alpha)
        fs:SetText(text)
        return fs
    end

    local divider = contentBlock:CreateTexture(nil, "BORDER")
    divider:SetColorTexture(0.35, 0.35, 0.38, 0.9)
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
    divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -1)
    divider:SetHeight(1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, contentBlock, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", contentBlock, "TOPLEFT", contentLeftInset, -scrollAreaTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", contentBlock, "TOPLEFT", contentLeftInset + scrollFrameWidth, -(scrollAreaTop + scrollFrameHeight))
    scrollFrame:EnableMouseWheel(true)

    local scrollBar = scrollFrame.ScrollBar or scrollFrame.scrollBar or (_G[(scrollFrame:GetName() or "") .. "ScrollBar"])
    if scrollBar then
        local buttonSize = math.max(scrollMetrics.width + 6, 14)

        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("BOTTOMLEFT", contentBlock, "BOTTOMLEFT", scrollMetrics.x, scrollMetrics.y)
        scrollBar:SetSize(scrollMetrics.width, scrollMetrics.height)
        scrollBar:Show()

        if scrollBar.Track then
            scrollBar.Track:ClearAllPoints()
            scrollBar.Track:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
            scrollBar.Track:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
        end

        if scrollBar.ThumbTexture then
            scrollBar.ThumbTexture:SetWidth(scrollMetrics.width)
        end

        if scrollBar.ScrollUpButton then
            scrollBar.ScrollUpButton:ClearAllPoints()
            scrollBar.ScrollUpButton:SetPoint("TOP", scrollBar, "TOP", 0, 0)
            scrollBar.ScrollUpButton:SetSize(buttonSize, buttonSize)
            scrollBar.ScrollUpButton:Show()
        end

        if scrollBar.ScrollDownButton then
            scrollBar.ScrollDownButton:ClearAllPoints()
            scrollBar.ScrollDownButton:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, 0)
            scrollBar.ScrollDownButton:SetSize(buttonSize, buttonSize)
            scrollBar.ScrollDownButton:Show()
        end
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local config = (FWR.GetMainRenderConfig and FWR:GetMainRenderConfig()) or {}
    local layoutConfig = (FWR.GetMainRenderLayoutConfig and FWR:GetMainRenderLayoutConfig()) or nil
    local host = {
        scrollFrame = scrollFrame,
        scrollChild = scrollChild,
        columnsHeader = header,
        renderColumnConfig = config,
        renderLayoutConfig = layoutConfig,
        divider = divider,
        resolvedContentWidth = scrollFrameWidth,
    }

    host.columnHeaders = {
        name = makeHeader((config.item and config.item.label) or "Item Name", "LEFT"),
        quality = makeHeader((config.quality and config.quality.label) or "", "CENTER"),
        quantity = makeHeader((config.quantity and config.quantity.label) or "Quantity", "CENTER"),
        total = makeHeader((config.total and config.total.label) or "Total", "CENTER"),
        itemPerHour = makeHeader((config.itemPerHour and config.itemPerHour.label) or "Item / Hour", "CENTER"),
        itemType = makeHeader((config.itemType and config.itemType.label) or "Reagent Type", "LEFT"),
        classification = makeHeader((config.classification and config.classification.label) or "Profession", "LEFT"),
        activity = makeHeader((config.activity and config.activity.label) or "Activity", "LEFT"),
        expansion = makeHeader((config.expansion and config.expansion.label) or "Expansion", "LEFT"),
        zone = makeHeader((config.zone and config.zone.label) or "Zone", "LEFT"),
        subZone = makeHeader((config.subZone and config.subZone.label) or "Sub-Zone", "LEFT"),
        character = makeHeader((config.character and config.character.label) or "Character", "LEFT"),
        price = makeHeader((config.price and config.price.label) or "Price", "CENTER"),
        value = makeHeader((config.value and config.value.label) or "Value", "CENTER"),
    }

host.columnHeaderHitboxes = {
    name = createHeaderTooltipHitbox(header, "item", function() return FWR.GetMainColumnTooltipText and FWR:GetMainColumnTooltipText("item") or nil end),
    quantity = createHeaderTooltipHitbox(header, "quantity", function() return FWR.GetMainColumnTooltipText and FWR:GetMainColumnTooltipText("quantity") or nil end),
    total = createHeaderTooltipHitbox(header, "total", function() return FWR.GetMainColumnTooltipText and FWR:GetMainColumnTooltipText("total") or nil end),
    itemPerHour = createHeaderTooltipHitbox(header, "itemPerHour", function() return FWR.GetMainColumnTooltipText and FWR:GetMainColumnTooltipText("itemPerHour") or nil end),
    itemType = createHeaderTooltipHitbox(header, "itemType", function() return FWR.GetMainColumnTooltipText and FWR:GetMainColumnTooltipText("itemType") or nil end),
    classification = createHeaderTooltipHitbox(header, "classification", function() return FWR.GetMainColumnTooltipText and FWR:GetMainColumnTooltipText("classification") or nil end),
    activity = createHeaderTooltipHitbox(header, "activity", function() return FWR.GetMainColumnTooltipText and FWR:GetMainColumnTooltipText("activity") or nil end),
    expansion = createHeaderTooltipHitbox(header, "expansion", function() return FWR.GetMainColumnTooltipText and FWR:GetMainColumnTooltipText("expansion") or nil end),
    zone = createHeaderTooltipHitbox(header, "zone", function() return FWR.GetMainColumnTooltipText and FWR:GetMainColumnTooltipText("zone") or nil end),
    subZone = createHeaderTooltipHitbox(header, "subZone", function() return FWR.GetMainColumnTooltipText and FWR:GetMainColumnTooltipText("subZone") or nil end),
    character = createHeaderTooltipHitbox(header, "character", function() return FWR.GetMainColumnTooltipText and FWR:GetMainColumnTooltipText("character") or nil end),
    price = createHeaderTooltipHitbox(header, "price", function() return FWR.GetMainColumnTooltipText and FWR:GetMainColumnTooltipText("price") or nil end),
    value = createHeaderTooltipHitbox(header, "value", function() return FWR.GetMainColumnTooltipText and FWR:GetMainColumnTooltipText("value") or nil end),
}


    local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -8)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText("No object loaded yet.")
    host.emptyText = emptyText

    scrollFrame:SetScript("OnMouseWheel", function(selfFrame, delta)
        local current = selfFrame:GetVerticalScroll() or 0
        local step = 60
        local childHeight = scrollChild:GetHeight() or 0
        local visibleHeight = math.max(100, selfFrame:GetHeight() or 100)
        local maxScroll = math.max(0, childHeight - visibleHeight)
        local nextScroll = current - (delta * step)
        if nextScroll < 0 then
            nextScroll = 0
        elseif nextScroll > maxScroll then
            nextScroll = maxScroll
        end
        selfFrame:SetVerticalScroll(nextScroll)
    end)

    frame.renderHost = host
end


-- The IDLE text switches between bright and dim on a fixed clock: the same pattern in every cycle.
local IDLE_BLINK_PERIOD = 1.0
local IDLE_BLINK_DIM_ALPHA = 0.2
local idleBlinker = nil

local function ensureIdleBlinker(self)
    if idleBlinker then
        return
    end

    idleBlinker = CreateFrame("Frame")
    idleBlinker:SetScript("OnUpdate", function()
        local idle = self.MainFrame and self.MainFrame.idle
        if idle and self.__fwrIdleBlinks then
            local bright = (GetTime() % IDLE_BLINK_PERIOD) < (IDLE_BLINK_PERIOD / 2)
            idle:SetAlpha(bright and 1 or IDLE_BLINK_DIM_ALPHA)
        end
    end)
end

-- light = only what time changes (clocks, gold per hour, item / hour); the places and items are not
-- walked again and the list is not rebuilt.
local function refreshMainWindow(self, light)
    if not self.MainFrame then
        return
    end

    local elements = self.UI_CONFIG and self.UI_CONFIG.MainFrame and self.UI_CONFIG.MainFrame.elements or {}
    local zoneText = self.GetLiveZoneText and self:GetLiveZoneText() or ((elements.zone and elements.zone.text) or "Zone Placeholder")
    local subzoneText = (self.IsSubZoneDataEnabled and self:IsSubZoneDataEnabled() and self.GetLiveSubzoneText and self:GetLiveSubzoneText()) or ""
    local hasSubzone = type(subzoneText) == "string" and subzoneText ~= ""
    local totalSeconds, sessionSeconds = self:SumViewScopeSeconds()
    local totalTimeValueText = self.GetLiveTotalTimeValueText and self:GetLiveTotalTimeValueText(totalSeconds) or "00:00"
    local sessionTimeValueText = self.GetLiveSessionTimeValueText and self:GetLiveSessionTimeValueText(sessionSeconds) or "00:00"
    local idleText = self.GetIdleIndicatorText and self:GetIdleIndicatorText() or ((elements.idle and elements.idle.text) or "IDLE")
    local idleVisual = self.GetIdleIndicatorVisual and self:GetIdleIndicatorVisual() or nil

    local headerKey = table.concat({ tostring(zoneText), tostring(subzoneText), totalTimeValueText, sessionTimeValueText }, "|")
    if not (light and self.__fwrHeaderKey == headerKey) then
        self.__fwrHeaderKey = headerKey
        if self.MainFrame.zone then
            self.MainFrame.zone:SetText(zoneText)
        end

        if self.MainFrame.zoneSeparator then
            if hasSubzone then
                self.MainFrame.zoneSeparator:SetText((((elements.zoneSeparator or {}).text) or "-"))
                self.MainFrame.zoneSeparator:Show()
            else
                self.MainFrame.zoneSeparator:Hide()
            end
        end

        if self.MainFrame.subzone then
            if hasSubzone then
                self.MainFrame.subzone:SetText(subzoneText)
                self.MainFrame.subzone:Show()
            else
                self.MainFrame.subzone:SetText("")
                self.MainFrame.subzone:Hide()
            end
        end

        if self.MainFrame.titleAccent then
            local productName = self.PRODUCT_NAME or "REFORGE"
            self.MainFrame.titleAccent:SetText(((elements.titleAccent or {}).text) or productName)
        end

        if self.MainFrame.titleVersion then
            local versionText = "v" .. tostring(self.VERSION or "")
            if self.RELEASE_STAGE then
                versionText = versionText .. " |cffff9a1f" .. self.RELEASE_STAGE .. "|r"
            end
            self.MainFrame.titleVersion:SetText(versionText)
        end

        if self.MainFrame.totalTimeLabel then
            self.MainFrame.totalTimeLabel:SetText((elements.totalTimeLabel and elements.totalTimeLabel.text) or "Total:")
        end

        if self.MainFrame.totalTimeValue then
            self.MainFrame.totalTimeValue:SetText(totalTimeValueText)
        end

        if self.MainFrame.runtimeLabel then
            self.MainFrame.runtimeLabel:SetText((elements.runtimeLabel and elements.runtimeLabel.text) or "Session:")
        end

        if self.MainFrame.runtimeValue then
            self.MainFrame.runtimeValue:SetText(sessionTimeValueText)
        end

        layoutMainFrameHeader(self.MainFrame)
    end

    if self.MainFrame.totalGoldValue then
        self.MainFrame.totalGoldValue:Hide()
    end

    if self.MainFrame.estimatedGoldPerHourValue then
        self.MainFrame.estimatedGoldPerHourValue:Hide()
    end

    if self.GetGoldContextSummary and self.MainFrame.totalGoldGold and self.MainFrame.estimatedGoldPerHourGold then
        local summary = self:GetGoldContextSummary(light, sessionSeconds)
        local gold, silver, copper = self:GetMoneyBreakdownFromCopper(summary.sessionCopper)
        local perHourGold, perHourSilver, perHourCopper = self:GetMoneyBreakdownFromCopper(summary.estimatedCopperPerHour)
        local goldKey = table.concat({ gold, silver, copper, perHourGold, perHourSilver, perHourCopper }, "|")

        if self.__fwrGoldKey ~= goldKey then
            self.__fwrGoldKey = goldKey
            self.MainFrame.totalGoldGold:SetText(tostring(gold) .. "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t")
            self.MainFrame.totalGoldSilver:SetText(string.format("%02d", tonumber(silver) or 0) .. "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t")
            self.MainFrame.totalGoldCopper:SetText(string.format("%02d", tonumber(copper) or 0) .. "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t")
            self.MainFrame.estimatedGoldPerHourGold:SetText(tostring(perHourGold) .. "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t")
            self.MainFrame.estimatedGoldPerHourSilver:SetText(string.format("%02d", tonumber(perHourSilver) or 0) .. "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t")
            self.MainFrame.estimatedGoldPerHourCopper:SetText(string.format("%02d", tonumber(perHourCopper) or 0) .. "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t")
            applyMainFrameMoneyLayout(self.MainFrame)
        end
    end

    -- the Reset button shows the reset mode of the Engine page; only the manual mode can be pressed
    if self.MainFrame.resetButton and self.GetSessionResetButtonState then
        local state = self:GetSessionResetButtonState()
        if self.MainFrame.resetButton.__fwrText ~= state.text then
            self.MainFrame.resetButton.__fwrText = state.text
            self.MainFrame.resetButton:SetText(state.text)
        end
        self.MainFrame.resetButton:SetEnabled(state.enabled)
    end

    if self.MainFrame.scanner and self.GetAuctionSyncAgeText then
        local scannerText, red, green, blue = self:GetAuctionSyncAgeText()
        self.MainFrame.scanner:SetText(scannerText)
        self.MainFrame.scanner:SetTextColor(red, green, blue, 1)
    end

    if self.MainFrame.idle then
        local idle = self.MainFrame.idle
        if idle.__fwrText ~= idleText then
            idle.__fwrText = idleText
            idle:SetText(idleText)
        end
        if idleVisual then
            -- setting a font resets the color, so the font goes first, and neither is touched when unchanged
            if idleVisual.font and idle.__fwrFont ~= idleVisual.font then
                idle.__fwrFont = idleVisual.font
                idle.__fwrColorKey = nil
                idle:SetFontObject(idleVisual.font)
            end
            local red = (idleVisual.color and idleVisual.color[1]) or 1
            local green = (idleVisual.color and idleVisual.color[2]) or 0.15
            local blue = (idleVisual.color and idleVisual.color[3]) or 0.15
            local colorKey = red .. "," .. green .. "," .. blue
            if idle.__fwrColorKey ~= colorKey then
                idle.__fwrColorKey = colorKey
                idle:SetTextColor(red, green, blue, 1)
            end
        end
        self.__fwrIdleBlinks = idleVisual ~= nil and idleVisual.blink == true
        if not self.__fwrIdleBlinks then
            self.MainFrame.idle:SetAlpha(1)
        end
        ensureIdleBlinker(self)
    end

    if self.MainFrame.renderHost then
        if light then
            if self.RefreshDisplayLiveRows then
                self:RefreshDisplayLiveRows(self.MainFrame.renderHost)
            end
        elseif self.RefreshDisplayScrollMetrics then
            self:RefreshDisplayScrollMetrics(self.MainFrame.renderHost, true)
        end
    end
end

-- Full refresh of the window. Many things ask for it at once (every loot, every gold message, the
-- late item info), so calls closer together than FULL_REFRESH_MIN_SECONDS become one. A hidden
-- window is not drawn at all: it redraws itself when it is shown again.
local FULL_REFRESH_MIN_SECONDS = 0.25

function FWR:RefreshMainWindowText()
    local frame = self.MainFrame
    if not frame then
        return
    end
    if frame.IsVisible and not frame:IsVisible() then
        return
    end

    local clock = GetTime()
    local wait = FULL_REFRESH_MIN_SECONDS - (clock - (self.__fwrFullRefreshAt or -100))
    if wait > 0.001 then
        if not self.__fwrFullRefreshQueued then
            self.__fwrFullRefreshQueued = true
            C_Timer.After(wait, function()
                FWR.__fwrFullRefreshQueued = false
                FWR:RefreshMainWindowText()
            end)
        end
        return
    end

    self.__fwrFullRefreshAt = clock
    refreshMainWindow(self, false)
end

-- Called twice a second by the idle system: clocks and per-hour figures only.
function FWR:RefreshMainWindowClock()
    local frame = self.MainFrame
    if not frame or (frame.IsVisible and not frame:IsVisible()) then
        return
    end
    if not self.__fwrFullRefreshAt then
        return self:RefreshMainWindowText()
    end
    refreshMainWindow(self, true)
end

function FWR:InitializeMainFrameUI()
    return self:CreateMainFrame()
end


function FWR:ApplyMainFrameBackdropTransparency()
    local frame = self.MainFrame
    if not frame then
        return
    end

    local display = self.Settings and self.Settings.display or {}
    local transparency = math.max(0, math.min(100, tonumber(display.frameTransparency) or 50))
    local alphaFactor = 1 - (transparency / 100) * 0.8
    if alphaFactor < 0.2 then
        alphaFactor = 0.2
    elseif alphaFactor > 1 then
        alphaFactor = 1
    end

    local ui = self.UI_CONFIG and self.UI_CONFIG.MainFrame or {}
    local frameBackdrop = ui.frame and ui.frame.backdrop or {}
    local blocks = ui.blocks or {}

    frame:SetAlpha(1)
    if frame.SetBackdropColor then
        frame:SetBackdropColor(unpackColor(frameBackdrop.bgColor, 0, { 0.05, 0.05, 0.06 }, 0))
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    end

    if frame.accentBorder and frame.accentBorder.SetBackdropBorderColor then
        frame.accentBorder:SetBackdropBorderColor(unpackColor(frameBackdrop.borderColor, frameBackdrop.borderAlpha, { 0.72, 0.62, 0.33 }, 0.95))
    end

    local frameBlocks = frame.blocks or {}
    local function applyBlockAlpha(blockFrame, cfg, fallbackRGB, fallbackAlpha)
        if not blockFrame then return end
        if blockFrame.SetBackdropColor then
            blockFrame:SetBackdropColor(unpackColor(cfg and cfg.bgColor, ((cfg and cfg.bgAlpha) or fallbackAlpha) * alphaFactor, fallbackRGB, fallbackAlpha * alphaFactor))
        elseif blockFrame.bgTexture then
            local r, g, b, a = unpackColor(cfg and cfg.bgColor, ((cfg and cfg.bgAlpha) or fallbackAlpha) * alphaFactor, fallbackRGB, fallbackAlpha * alphaFactor)
            blockFrame.bgTexture:SetColorTexture(r, g, b, a)
        end
    end

    -- the title area (name, zone, times, scanner, buttons) is dark and does not follow the transparency,
    -- so its text stays readable however see-through the rest of the window is
    local titleArea = frameBlocks.header
    if titleArea then
        if titleArea.SetBackdropColor then
            titleArea:SetBackdropColor(0.04, 0.04, 0.05, 0.96)
        elseif titleArea.bgTexture then
            titleArea.bgTexture:SetColorTexture(0.04, 0.04, 0.05, 0.96)
        end
    end
    applyBlockAlpha(frameBlocks.content, blocks.content, { 0.02, 0.02, 0.02 }, 1.0)
    applyBlockAlpha(frameBlocks.footer, blocks.footer, { 0.11, 0.11, 0.12 }, 0.90)
end

function FWR:CreateMainFrame()
    if self.MainFrame then
        return self.MainFrame
    end

    local config = self.UI_CONFIG and self.UI_CONFIG.MainFrame
    if not config then return nil end

    local frameConfig = config.frame or {}
    local frame = CreateFrame("Frame", frameConfig.name or "FarmWiseReforgedMainFrame", UIParent, backdropTemplate)
    self.MainFrame = frame

    local computedWidth = computeMainFrameWidth(config)
    local computedHeight = computeMainFrameHeight(config)
    frame:SetSize(computedWidth, computedHeight)
    frame:SetScale(frameConfig.scale or 1)
    frame:SetFrameStrata(frameConfig.strata or "MEDIUM")
    frame:SetClampedToScreen(frameConfig.clampToScreen ~= false)
    frame:EnableMouse(true)
    if frameConfig.movable ~= false then
        frame:SetMovable(true)
        frame:SetResizable(false)
        if type(frame.SetUserPlaced) == "function" then
            frame:SetUserPlaced(true)
        end
    end
    applyMainFramePosition(self, frame, frameConfig)
    applyFrameBackdrop(frame, frameConfig.backdrop)

    local accentBorder = CreateFrame("Frame", nil, frame, backdropTemplate)
    accentBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 4)
    accentBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
    accentBorder:SetFrameLevel(frame:GetFrameLevel() + 1)
    accentBorder:EnableMouse(false)
    applyFrameBackdrop(accentBorder, {
        bgColor = { 0, 0, 0 },
        bgAlpha = 0,
        borderColor = { 0.72, 0.62, 0.33 },
        borderAlpha = 0.98,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame.accentBorder = accentBorder

    if frameConfig.movable ~= false then
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(selfFrame)
            if FWR.Settings and FWR.Settings.ui and FWR.Settings.ui.lockMainWindow then
                return
            end
            selfFrame:StartMoving()
        end)
        frame:SetScript("OnDragStop", function(selfFrame)
            selfFrame:StopMovingOrSizing()
            saveMainFramePosition(FWR, selfFrame)
            FWR:NoteMainWindowMoved()
        end)
    end

    local blocks = createMainBlocks(frame, frameConfig, config)
    frame.blocks = blocks
    if self.ApplyMainFrameBackdropTransparency then
        self:ApplyMainFrameBackdropTransparency()
    end

    if frameConfig.movable ~= false then
        blocks.header:EnableMouse(true)
        blocks.header:RegisterForDrag("LeftButton")
        blocks.header:SetScript("OnDragStart", function()
            if FWR.Settings and FWR.Settings.ui and FWR.Settings.ui.lockMainWindow then
                return
            end
            frame:StartMoving()
        end)
        blocks.header:SetScript("OnDragStop", function()
            frame:StopMovingOrSizing()
            saveMainFramePosition(FWR, frame)
            FWR:NoteMainWindowMoved()
        end)
    end

    local elements = config.elements or {}

    frame.title = createConfiguredFontString(blocks[elements.title.parentBlock], elements.title)
    frame.titleAccent = createConfiguredFontString(blocks[elements.titleAccent.parentBlock], elements.titleAccent)
    frame.titleVersion = createConfiguredFontString(blocks[elements.titleVersion.parentBlock], elements.titleVersion)
    self:CreateMainWindowControls(frame, blocks.header, blocks.footer)
    frame.zone = createConfiguredFontString(blocks[elements.zone.parentBlock], elements.zone)
    frame.zoneSeparator = createConfiguredFontString(blocks[elements.zoneSeparator.parentBlock], elements.zoneSeparator)
    frame.subzone = createConfiguredFontString(blocks[elements.subzone.parentBlock], elements.subzone)
    frame.totalTimeLabel = createConfiguredFontString(blocks[elements.totalTimeLabel.parentBlock], elements.totalTimeLabel)
    frame.totalTimeValue = createConfiguredFontString(blocks[elements.totalTimeValue.parentBlock], elements.totalTimeValue)
    frame.runtimeSeparator = createConfiguredFontString(blocks[elements.runtimeSeparator.parentBlock], elements.runtimeSeparator)
    frame.runtimeLabel = createConfiguredFontString(blocks[elements.runtimeLabel.parentBlock], elements.runtimeLabel)
    frame.runtimeValue = createConfiguredFontString(blocks[elements.runtimeValue.parentBlock], elements.runtimeValue)
    frame.totalGoldLabel = createConfiguredFontString(blocks[elements.totalGoldLabel.parentBlock], elements.totalGoldLabel)
    frame.totalGoldValue = createConfiguredFontString(blocks[elements.totalGoldValue.parentBlock], elements.totalGoldValue)
    frame.estimatedGoldPerHourLabel = createConfiguredFontString(blocks[elements.estimatedGoldPerHourLabel.parentBlock], elements.estimatedGoldPerHourLabel)
    frame.estimatedGoldPerHourValue = createConfiguredFontString(blocks[elements.estimatedGoldPerHourValue.parentBlock], elements.estimatedGoldPerHourValue)
    frame.idle = createConfiguredFontString(blocks[elements.idle.parentBlock], elements.idle)
    frame.scanner = createConfiguredFontString(blocks[elements.scanner.parentBlock], elements.scanner)

    layoutMainFrameHeader(frame)

    frame.resetButton = CreateFrame("Button", nil, blocks[elements.resetButton.parentBlock], "UIPanelButtonTemplate")
    positionTopAnchored(frame.resetButton, blocks[elements.resetButton.parentBlock], elements.resetButton)
    frame.resetButton:SetSize(elements.resetButton.width or 78, elements.resetButton.height or 24)
    frame.resetButton:SetText(elements.resetButton.text or "Reset")
    frame.resetButton:SetScript("OnClick", function() FWR:ResetCurrentSessionView() end)
    attachSimpleTooltip(frame.resetButton, function() return FWR:GetSessionResetButtonState().tooltip end)

    frame.optionsButton = CreateFrame("Button", nil, blocks[elements.optionsButton.parentBlock], "UIPanelButtonTemplate")
    positionTopAnchored(frame.optionsButton, blocks[elements.optionsButton.parentBlock], elements.optionsButton)
    frame.optionsButton:SetSize(elements.optionsButton.width or 78, elements.optionsButton.height or 24)
    frame.optionsButton:SetText(elements.optionsButton.text or "Options")
    frame.optionsButton:SetScript("OnClick", function() FWR:OpenControlPanelWindow() end)

    frame.advisorButton = CreateFrame("Button", nil, blocks[elements.advisorButton.parentBlock], "UIPanelButtonTemplate")
    positionTopAnchored(frame.advisorButton, blocks[elements.advisorButton.parentBlock], elements.advisorButton)
    frame.advisorButton:SetSize(elements.advisorButton.width or 78, elements.advisorButton.height or 24)
    frame.advisorButton:SetText(elements.advisorButton.text or "Advisor")
    frame.advisorButton:SetScript("OnClick", function() FWR:ToggleAdvisorPanel() end)

    frame.totalGoldGold = createMoneyValueFontString(blocks[elements.totalGoldValue.parentBlock], frame.totalGoldValue, { font = elements.totalGoldValue.font, justifyH = "LEFT", justifyV = elements.totalGoldValue.justifyV, textColor = elements.totalGoldValue.textColor, textAlpha = elements.totalGoldValue.textAlpha, width = 64 })
    frame.totalGoldSilver = createMoneyValueFontString(blocks[elements.totalGoldValue.parentBlock], frame.totalGoldGold, { font = elements.totalGoldValue.font, justifyH = "LEFT", justifyV = elements.totalGoldValue.justifyV, textColor = elements.totalGoldValue.textColor, textAlpha = elements.totalGoldValue.textAlpha, width = 24 })
    frame.totalGoldCopper = createMoneyValueFontString(blocks[elements.totalGoldValue.parentBlock], frame.totalGoldSilver, { font = elements.totalGoldValue.font, justifyH = "LEFT", justifyV = elements.totalGoldValue.justifyV, textColor = elements.totalGoldValue.textColor, textAlpha = elements.totalGoldValue.textAlpha, width = 24 })

    frame.estimatedGoldPerHourGold = createMoneyValueFontString(blocks[elements.estimatedGoldPerHourValue.parentBlock], frame.estimatedGoldPerHourValue, { font = elements.estimatedGoldPerHourValue.font, justifyH = "LEFT", justifyV = elements.estimatedGoldPerHourValue.justifyV, textColor = elements.estimatedGoldPerHourValue.textColor, textAlpha = elements.estimatedGoldPerHourValue.textAlpha, width = 64 })
    frame.estimatedGoldPerHourSilver = createMoneyValueFontString(blocks[elements.estimatedGoldPerHourValue.parentBlock], frame.estimatedGoldPerHourGold, { font = elements.estimatedGoldPerHourValue.font, justifyH = "LEFT", justifyV = elements.estimatedGoldPerHourValue.justifyV, textColor = elements.estimatedGoldPerHourValue.textColor, textAlpha = elements.estimatedGoldPerHourValue.textAlpha, width = 24 })
    frame.estimatedGoldPerHourCopper = createMoneyValueFontString(blocks[elements.estimatedGoldPerHourValue.parentBlock], frame.estimatedGoldPerHourSilver, { font = elements.estimatedGoldPerHourValue.font, justifyH = "LEFT", justifyV = elements.estimatedGoldPerHourValue.justifyV, textColor = elements.estimatedGoldPerHourValue.textColor, textAlpha = elements.estimatedGoldPerHourValue.textAlpha, width = 24 })

    createFooterValueTooltipHitbox(blocks[elements.totalGoldLabel.parentBlock], frame.totalGoldLabel, elements.totalGoldLabel, function() return elements.totalGoldLabel.tooltipText end)
    createFooterValueTooltipHitbox(blocks[elements.estimatedGoldPerHourLabel.parentBlock], frame.estimatedGoldPerHourLabel, elements.estimatedGoldPerHourLabel, function() return elements.estimatedGoldPerHourLabel.tooltipText end)

    createMainRenderHost(frame, blocks.content)
    applyMainFrameMoneyLayout(frame)

    frame:SetScript("OnShow", function()
        FWR:RefreshMainWindowText()
        if FWR.RefreshDisplayText then
            FWR:RefreshDisplayText()
        end
        if FWR.RefreshDisplayLiveMetrics then
            FWR:RefreshDisplayLiveMetrics(true)
        end
    end)

    frame:Show()
    self:RefreshMainWindowText()
    if self.RefreshDisplayText then
        self:RefreshDisplayText()
    end
    if self.RefreshDisplayLiveMetrics then
        self:RefreshDisplayLiveMetrics(true)
    end

    return frame
end
