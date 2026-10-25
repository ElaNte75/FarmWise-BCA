
local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

FWR.UI_CONFIG = FWR.UI_CONFIG or {}

FWR.UI_CONFIG.ControlPanelWindow = {
    window = {
        width = 590,
        height = 490,
        sidebarWidth = 150,
        footerHeight = 52,
        headerHeight = 56,
        contentPadding = 18,
        framePoint = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    },

    colors = {
        frameBg = { 0.04, 0.03, 0.02, 0.94 },
        frameBorder = { 0.85, 0.65, 0.15, 0.55 },
        headerBg = { 0.10, 0.08, 0.05, 0.95 },
        footerBg = { 0.10, 0.08, 0.05, 0.95 },
        sidebarBg = { 0.08, 0.06, 0.04, 0.90 },
        contentBg = { 0.06, 0.05, 0.03, 0.82 },
        divider = { 1.0, 1.0, 1.0, 0.10 },
        navText = { 0.96, 0.96, 0.96, 1.0 },
        navSelectedText = { 1.0, 0.90, 0.55, 1.0 },
        navSelectedBg = { 1.0, 0.82, 0.02, 0.12 },
        navHighlightBg = { 1.0, 1.0, 1.0, 0.05 },
        title = { 0.95, 0.82, 0.42, 1.0 },
        titleAccent = { 0.96, 0.96, 0.96, 1.0 },
        subtitle = { 0.80, 0.80, 0.80, 1.0 },
        footerNote = { 0.72, 0.72, 0.72, 1.0 },
    },

    header = {
        title = { text = "FarmWise", x = 18, y = -12 },
        titleAccent = { text = "Control Panel", x = 6, y = 0 },
        subtitle = { x = 0, y = -6 },
    },

    footer = {
        closeButton = { text = "Close", width = 84, height = 24, x = -18, y = 0 },
        note = {
            text = "Use the left menu to move between pages.",
            x = 18,
            y = 0,
        },
    },

    categories = {
        order = {
            { key = "interface", label = "Interface" },
            { key = "display", label = "Display" },
            { key = "tracking", label = "Tracking" },
            { key = "engine", label = "Engine" },
            { key = "auction", label = "Scanner" },
            { key = "selltab", label = "FarmWise AH" },
            { key = "data", label = "Data" },
            { key = "info", label = "Info" },
            { key = "manual", label = "Manual" },
        },
        button = {
            width = 126,
            height = 28,
            startX = 12,
            startY = -18,
            spacing = 4,
            textX = 10,
        },
        notes = {
            interface = "Main window startup and control panel behavior.",
            display = "Display columns, rows, and main background transparency.",
            tracking = "Tracking filters, combined views, and current data scope.",
            engine = "Internal timers, reset behavior, and rarity filter settings.",
            auction = "The scan of the Auction House prices: what it reads, how deep and how often.",
            selltab = "The switch of the FarmWise Auction House tab. Its own settings are on its Options page, in the Auction House.",
            data = "Saved data tools.",
            info = "Addon commands, main window controls, and quick usage notes.",
            manual = "How the parts of FarmWise work, chapter by chapter.",
        },
    },

    pages = {
        interface = {
            checkbox = {
                startX = 0,
                startY = -2,
                spacing = -2,
                textOffsetX = 0,
                textOffsetY = 1,
            },
            sections = {
                { key = "window", title = "Main window" },
                { key = "floatText", title = "Loot text while minimized" },
                { key = "panels", title = "Control panels" },
                { key = "layout", title = "Window layout" },
            },
            options = {
                { key = "showMainWindowOnGameLoad", section = "window", label = "Show the main window when the game starts", defaultValue = true },
                { key = "hideMainWindowInCombat", section = "window", label = "Minimize the main window during combat", defaultValue = false },
                { key = "restoreMainWindowAfterCombat", section = "window", label = "Open it again after combat", defaultValue = false,
                  tooltip = "After the fight the main window opens again by itself. Off: it stays the small button until you click it. A window you minimized yourself (with its own minimize button) always stays minimized: it is never opened for you." },
                { key = "autoLockMainWindow", section = "window", label = "Lock the main window after a minute without moving it", defaultValue = true,
                  tooltip = "An unlocked window locks itself when it has not been moved for a minute, so it cannot be dragged by accident." },
                { key = "keepColumnWidths", section = "window", label = "Keep the columns at their widest size (the window never shrinks)", defaultValue = true,
                  tooltip = "Each column keeps the widest size it has needed, also after a reload or after closing the game, so the window never jumps around. Turn it off and the columns always fit what they show. Use the button below to start again from the smallest widths." },
                { key = "showMainFrameTooltips", section = "window", label = "Show tooltips in the main window", defaultValue = true },
                { key = "floatLootText", section = "floatText", label = "Show the loot as floating text while minimized", defaultValue = true,
                  tooltip = "While the main window is minimized to its small button, every item you loot rises from that button in the colour of its rarity (for example: Bright Linen x3) and fades away. It stops when the window is open." },
                { key = "lootAlertSound", section = "floatText", label = "Alert for valuable loot: bigger letters and a sound", defaultValue = true,
                  tooltip = "A loot that is worth at least the value chosen with the slider below comes in bigger letters, with a sound. Off: no alert, and the slider does nothing. It works only while the loot text is on." },
                { key = "hideControlPanelsInCombat", section = "panels", label = "Hide the control panels during combat", defaultValue = true },
                { key = "restoreControlPanelsAfterCombat", section = "panels", label = "Show the control panels again after combat", defaultValue = true },
            },
        },

        display = {
            rowSlider = {
                title = "Set Visible Rows",
                titleX = 0,
                titleY = -2,
                sliderX = 180,
                sliderY = -1,
                sliderWidth = 140,
                min = 5,
                max = 20,
                low = "5",
                high = "20",
                lowOffsetX = -2,
                highOffsetX = 2,
            },
            transparencySlider = {
                title = "Set Transparency",
                titleX = 0,
                titleY = -26,
                sliderX = 180,
                sliderY = -25,
                sliderWidth = 140,
                min = 0,
                max = 100,
                low = "0",
                high = "100",
                lowOffsetX = -2,
                highOffsetX = 2,
            },
            divider = {
                x = 0,
                y = -64,
                rightInset = 18,
                height = 1,
                color = { 1, 1, 1, 0.18 },
            },
            headers = {
                visibility = { text = "Enable / Disable Columns", x = 0, y = -80 },
                order = { text = "Reorder Columns", x = 180, y = -80 },
            },
            scroll = {
                left = 0,
                top = -102,
                right = -24,
                bottom = 0,
            },
            list = {
                checkboxX = 0,
                sliderX = 180,
                startY = -8,
                rowSpacing = 34,
                sliderWidth = 140,
                sliderOffsetY = -4,
                lowOffsetX = -2,
                highOffsetX = 2,
            },
            controls = {
                { key = "item", label = "Item Name", locked = true, defaultValue = true, fixedOrder = 1 },
                { key = "quantity", label = "Session", defaultValue = true },
                { key = "total", label = "Total", defaultValue = true },
                { key = "itemPerHour", label = "Item / Hour", tooltip = "How many of this item you get per hour of active farming.", defaultValue = true },
                { key = "activity", label = "Activity", tooltip = "Where the item came from: looting, skinning, mining, fishing and so on.", defaultValue = true },
                { key = "itemType", label = "Reagent Type", tooltip = "The kind of reagent, for example ore, herb, cloth or leather.", defaultValue = false },
                { key = "classification", label = "Profession", tooltip = "The profession the item belongs to.", defaultValue = false },
                { key = "expansion", label = "Expansion", tooltip = "The expansion the item comes from.", defaultValue = false },
                { key = "zone", label = "Zone", defaultValue = false },
                { key = "subZone", label = "Sub-Zone", defaultValue = false },
                { key = "character", label = "Character", tooltip = "The character that collected the item.", defaultValue = false },
                { key = "price", label = "Price", tooltip = "The lowest Auction House price of one item, from the last FarmWise scan.", defaultValue = false },
                { key = "value", label = "Value", tooltip = "Price multiplied by the Session quantity: what the items collected since the last reset are worth.", defaultValue = false },
            },
        },

        tracking = {
            checkbox = {
                startX = 0,
                startY = -2,
                spacing = -2,
                textOffsetX = 0,
                textOffsetY = 1,
            },
            sections = {
                { key = "listed", title = "What the main window lists" },
                { key = "scope", title = "Which data is shown" },
            },
            options = {
                { key = "showSpecializedClassifications", section = "listed", label = "Show processing and crafting reagents too", tooltip = "Also lists processing and crafting products (dust, essence, shards, pigments, ink, gems, bolts) in the main window. Off by default, so the list shows only what you gather. This only changes what is shown; the data is always saved.", settingPath = { "displayFilters", "showSpecializedClassifications" }, defaultValue = false },
                { key = "onlySpecializedClassifications", section = "listed", label = "Show only processing and crafting reagents", tooltip = "Shows only processing and crafting products and hides everything else. Turns off the option above while it is on. Only changes what is shown.", settingPath = { "displayFilters", "onlySpecializedClassifications" }, defaultValue = false },
                { key = "showOldExpansions", section = "listed", label = "Show items from older expansions too", tooltip = "Also shows items from earlier expansions. Off by default, so only items of the current expansion are listed. Only changes what is shown.", settingPath = { "displayFilters", "showOldExpansions" }, defaultValue = false },
                { key = "combinedAllData", section = "scope", label = "Add up the data of all my characters", tooltip = "Adds up the data of all your characters, in every zone, in one view. While on, the Zone and Sub-Zone options below are switched off. Only changes what is shown.", settingPath = { "tracking", "combinedAllData" }, defaultValue = false },
                { key = "combinedCharacterAllZones", section = "scope", label = "Add up all the zones of this character", tooltip = "Adds up the data of the current character over all zones, in one view. While on, the Zone and Sub-Zone options below are switched off. Only changes what is shown.", settingPath = { "tracking", "combinedCharacterAllZones" }, defaultValue = false },
                { key = "zoneData", section = "scope", label = "Show the data of the whole zone", tooltip = "Shows the data of the zone you are in, with all its sub-zones added together. Only changes what is shown; the data is always saved per sub-zone.", settingPath = { "tracking", "zoneData" }, defaultValue = false },
                { key = "subZoneData", section = "scope", label = "Show the data of the exact sub-zone", tooltip = "Shows only the data of the exact sub-zone you are in (the default). The Advisor works per sub-zone, whatever you choose here (gathering is counted for the whole zone, see the option below).", settingPath = { "tracking", "subZoneData" }, defaultValue = true },
                { key = "gatheringWholeZone", section = "scope", indent = 24, label = "Count gathering for the whole zone", tooltip = "Mining, herbalism, fishing and skinning are counted for the whole zone, not for the sub-zone where the node was: what you gather adds up in the zone, the session is not reset by walking into another sub-zone, and the Advisor tells you the zone to go to. Off: gathering is counted per sub-zone like everything else. It matters only while the exact sub-zone is shown above.", settingPath = { "tracking", "gatheringWholeZone" }, defaultValue = true },
            },
        },

        engine = {
            checkbox = {
                startX = 0,
                startY = -2,
                spacing = -2,
                textOffsetX = 0,
                textOffsetY = 1,
            },
            manualReset = {
                label = "Reset the session only when I press Reset",
                tooltip = "The session in the main window (and its per-hour figures) starts over only when you press the Reset button.",
            },
            localReset = {
                label = "Reset the session every day at this time",
                tooltip = "The session starts over by itself every day at the time you choose with the slider. The Total column and the saved data are not touched.",
                sliderX = 170,
                sliderY = -1,
                sliderWidth = 130,
                low = "00:00",
                high = "23:45",
                valueTextX = 8,
                valueTextWidth = 46,
            },
            autoReset = {
                label = "Reset the session when I leave the area",
                tooltip = "The session of an area starts over when you have left it. It follows the Tracking setting (Zone or Sub-Zone). While you are still fighting nothing happens; after the fight, coming back within the chosen time keeps the session. Not used with the Combined views.",
                sliderX = 170,
                sliderY = -1,
                sliderWidth = 130,
                low = "15s",
                high = "2m",
                valueTextX = 8,
                valueTextWidth = 46,
            },
            rarity = {
                label = "Hide items below this quality",
                tooltip = "Hides items below the chosen quality from the main window. They are still saved and still count for the Advisor.",
                sliderX = 170,
                sliderY = -1,
                sliderWidth = 130,
                valueTextX = 8,
                valueTextWidth = 62,
            },
            rarityLevels = {
                { value = 0, label = "Poor+" },
                { value = 1, label = "Common+" },
                { value = 2, label = "Uncommon+" },
                { value = 3, label = "Rare+" },
                { value = 4, label = "Epic+" },
            },
        },

        auction = {
            note = "Prices from the Auction House. The Advisor uses them to estimate gold per hour.",
            sections = {
                scanning = "Scanning",
                depth = "What is scanned",
                interval = "How often",
                tooltips = "Tooltips",
            },
            autoScan = {
                label = "Scan the Auction House by itself when it opens",
                tooltip = "When you open the Auction House, FarmWise scans by itself if the prices are older than the interval chosen below.",
            },
            sound = {
                label = "Play a sound when the scan is finished",
                tooltip = "Plays a short sound when a scan completes, so you know you can use the Auction House normally again.",
            },
            depthNote = "Trade materials are always scanned. The larger levels take longer.",
            commodities = {
                label = "Scan commodities too (everything sold by amount)",
                tooltip = "Commodities are the items the Auction House sells by amount, at one price for every unit: herbs, ore, cloth, potions, flasks, food, runes and similar items. Gear, which is sold one piece at a time, is not a commodity. With this on, the scan reads their prices too, so they get a price in the tooltip, the vendor comparison and the trend. It takes a little longer than the trade materials alone.",
            },
            fullScan = {
                label = "Scan the whole Auction House",
                tooltip = "Scans every category, so prices can be shown for any item. It takes noticeably longer than the other levels and may make the game stutter for a moment. It includes everything sold by amount.",
            },
            intervalNote = "While the Auction House is open, FarmWise scans again by itself when the prices get older than this. The AH Tab does not need it: it asks for its own prices.",
            intervalTitle = "Scan again when the prices are older than:",
            intervals = {
                { minutes = 15, label = "15 minutes" },
                { minutes = 30, label = "30 minutes" },
                { minutes = 60, label = "1 hour" },
                { minutes = 120, label = "2 hours" },
            },
            tooltipPrice = {
                label = "Show the FarmWise Auction House price in item tooltips",
                tooltip = "Adds a \"FarmWise AH\" line with the lowest Auction House price from the last scan to item tooltips. It is shown for the kinds of item the scan level above reads.",
            },
        },

        selllist = {
            note = "The list holds everything in your bags that the Auction House sells by amount. Gear and bound items never. One item can be hidden with a right-click in the tab.",
            sections = {
                source = "Source",
                groups = "Groups shown in the list",
            },
            onlyFarmed = {
                label = "Show only what I have farmed",
                tooltip = "Off: everything that can be sold. On: only the items that FarmWise has seen you gather, loot or process.",
            },
                        trade = {
                label = "Show trade materials",
                tooltip = "Herbs, ore, cloth, leather, dusts, shards and the other materials of the professions.",
            },
            consumables = {
                label = "Show consumables",
                tooltip = "Potions, flasks, food and drink, runes, and the other items that you use.",
            },
            gems = {
                label = "Show gems and enhancements",
                tooltip = "Gems, and the items that improve gear.",
            },
            other = {
                label = "Show other things sold by amount",
                tooltip = "Any other item that stacks and that the Auction House sells by amount.",
            },
        },

        selltab = {
            note = "What you set for one item with a right-click in the tab is stronger than what is set here.",
            sections = {
                tab = "The tab",
                posting = "Posting",
                display = "Display",
                history = "Sales history",
            },
            averageSales = {
                title = "How many of the last sales make the average:",
                tooltip = "How many of your last sales of an item make its average price (\"Never sell below my average price\"). A small number follows the market faster, a bigger number is steadier. Sales older than 30 days are never counted.",
            },
            history = {
                label = "Record my sales in the History page",
                tooltip = "FarmWise counts what you sell: when you take the gold of a sale (or the items of an expired auction) from your mailbox, it is added to the History page of the FarmWise AH tab, with what you earned, the average price and how much of what you posted was sold. Nothing is counted for what happened before this was switched on. Switched off, nothing is recorded and the page is not shown; what was recorded is kept.",
            },
            enabled = {
                label = "Add the FarmWise AH tab to the Auction House",
                tooltip = "Adds the FarmWise AH tab next to Buy, Sell and Auctions, where you sell the materials you farmed. Switched off, nothing of it is added to the Auction House (for example if you use another addon for selling), and the automatic scan follows the options of the Scanner page.",
            },
            durationTitle = "Post for:",
            durations = {
                { value = 1, label = "12 hours" },
                { value = 2, label = "24 hours" },
                { value = 3, label = "48 hours" },
            },
            priceStep = {
                title = "Each click on + or - changes the price by:",
                tooltip = "How much one click of + or - changes the price of an item, as a part of its lowest price now. A small step is for fine work, a bigger step goes faster. The price check still stops - at the lowest usual price.",
            },
            averageFloor = {
                label = "Never sell below my history average price",
                tooltip = "Uses what you got in your last sales of an item (from the History: at least 3 sales and 20 pieces). The price starts at the higher of the lowest price now and your average, and the - button and Post stop at your average. If the market is under your average, the item waits unsold. An item can differ: right-click it in the tab. It needs the sales history to be on.",
            },
            priceCheck = {
                label = "Turn on the price check for all items",
                tooltip = "Post waits while the price to post is unusually low against where most of the listings are, and the first + goes straight to the lowest usual price. An item can differ: right-click it in the tab.",
            },
            priceAutoFix = {
                label = "Set the right price by itself",
                tooltip = "With the price check on, a price that is unusually low is raised at once to the lowest usual price, so there is no need to press + on every item before Post. The prices that were corrected this way are written in green in the Sell list. A price you changed yourself with + or - is left as it is.",
            },
            tooltips = {
                label = "Show tooltips in the FarmWise AH tab",
                tooltip = "The small windows that explain what you point at in the FarmWise AH tab (the price, the trend, Post, the filters of an item). Off: none of them is shown.",
            },
            vendorCoin = {
                label = "Gold coin on items a vendor pays more for",
                tooltip = "A small gold coin on the corner of the items in your bags that the FarmWise AH tab leaves out of the Sell list because a vendor pays more than the Auction House. The tooltip of the item tells how much each one pays. Off: no coin is drawn.",
            },
            openFirst = {
                label = "Open the FarmWise AH tab first",
                tooltip = "The FarmWise AH tab is shown at once when you open the Auction House, instead of the game's first page. Off: the game's page is shown, and the tab is one click away.",
            },
            wheel = {
                label = "Use the mouse wheel to post the next item",
                tooltip = "While the FarmWise AH tab is open, the mouse wheel (up or down) posts the next item, as one click does. The game accepts one post for each click or scroll. The wheel is its own again when the tab is closed.",
            },
            wheelShift = {
                label = "Post only while Shift is held down",
                tooltip = "The wheel posts only while Shift is held, so a scroll by accident (to look at the list, for example) never posts. Without Shift the wheel only scrolls the list.",
            },
            showTrend = {
                label = "Show the Trend column",
                tooltip = "An arrow for each item: going up, going down or steady, from the prices of the last days. A change of this option is made when the game is reloaded (/reload).",
            },
            showValue = {
                label = "Show the Value column",
                tooltip = "What you receive for the whole amount after the 5% cut of the Auction House. A change of this option is made when the game is reloaded (/reload).",
            },
        },

        data = {
            erase = {
                note = "Erase all saved FarmWise data: the main window data and the statistics the Advisor uses. Settings stay as they are. This cannot be undone.",
                noteX = 0,
                noteY = -2,
                label = "Erase Data",
                labelOffsetY = -16,
                buttonText = "Erase",
                buttonWidth = 110,
                buttonHeight = 24,
                buttonOffsetX = 36,
            },
        },

        info = {
            title = { text = "Quick Commands", x = 0, y = -2 },
            body = {
                x = 0,
                y = -10,
                rightInset = 18,
                text = "/fw advisor - open the Advisor (best zones for an item or for gold)\n"
                    .. "/fw scan - scan the Auction House prices now (Auction House must be open)\n"
                    .. "/fw ui - show or hide the main frame\n"
                    .. "/fw options - open the control panel\n"
                    .. "/fw status - print storage status in chat\n\n"
                    .. "The launcher icon can also show or hide the main frame.",
            },
        },
    },
}
