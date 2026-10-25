local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local GetItemInfoInstant = GetItemInfoInstant

-- Auction House scan (Burning Crusade Anniversary client).
-- Reads the lowest buyout price per piece of every trade good (or of every item, when the
-- whole-Auction-House option is on) and stores it in FarmWiseDB._ah, which the Advisor uses for
-- gold per hour. It runs automatically when the Auction House opens if the "Scan automatically"
-- option is on and the last scan is older than the interval chosen in the options, and never
-- sooner than MIN_SECONDS_BETWEEN_SCANS (15 minutes) after the previous one.
--
-- Classic API facts this relies on:
--   QueryAuctionItems(text, minLevel, maxLevel, page, usable, rarity, getAll, exactMatch, filterData)
--     getAll downloads the whole Auction House in one answer and has a ~15 min server cooldown;
--     CanSendAuctionQuery() returns canSendQuery, canSendAllQuery.
--     filterData = { classID = n } restricts a normal (paged) query to an item class.
--   AUCTION_ITEM_LIST_UPDATE fires when a query's page arrives.
--   GetNumAuctionItems("list") -> numBatchAuctions, totalAuctions (50 per page).
--   GetAuctionItemInfo("list", i) -> name, texture, count, quality, canUse, level, levelColHeader,
--     minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName,
--     saleStatus, itemID, hasAllInfo.
--   There are no commodities on this client: every auction has a bid and a buyout. The scan price
--   of an item is the lowest buyoutPrice / count seen.

local PREFIX = "|cffd7be6aFarmWise|r "
local TRADEGOODS_CLASS_ID = 7   -- ItemClass.Tradegoods on this client

-- The scan levels. Trade materials are always read. "Commodities" adds the other classes that are
-- usually sold by amount; "full" reads the whole Auction House.
local COMMODITY_CLASS_IDS = {
    TRADEGOODS_CLASS_ID,
    0,  -- Consumable
    3,  -- Gem
    8,  -- ItemEnhancement
    5,  -- Reagent
}

local START_DELAY_SECONDS = 0.5
local MIN_SECONDS_BETWEEN_SCANS = 15 * 60
local RESULT_TIMEOUT_SECONDS = 8     -- waiting for the first answer
local BATCH_TIMEOUT_SECONDS = 15     -- waiting for the next page
local MAX_ATTEMPTS = 3
local PAGE_RETRY_SECONDS = 0.4       -- pause between page queries (server throttle is ~0.3 s)
local GETALL_WAIT_SECONDS = 20       -- getAll downloads can take a while

local auctionHouseOpen = false
local scan = {
    running = false,
    pendingStart = false,
    found = 0,
    expected = 0,        -- items found by the previous scan, used to estimate progress
    startedAt = 0,
    activity = 0,        -- grows with every sign of life; the watchdog compares against it
    attempt = 1,         -- the query is sent at most MAX_ATTEMPTS times
    gotResults = false,  -- real results of our query arrived
    classes = nil,       -- item classes read one after the other (nil: whole Auction House)
    classIndex = 1,
    prices = nil,        -- [itemID] = lowest unit price collected this scan
    page = 0,            -- current page of a paged class query
    totalPages = 0,      -- pages the current class query has
    useGetAll = false,   -- a single getAll query instead of paged class queries
}

local function say(message)
    print(PREFIX .. message)
end

local function playFinishedSound(settings)
    if settings.sound ~= false and type(PlaySound) == "function" and SOUNDKIT and SOUNDKIT.READY_CHECK then
        PlaySound(SOUNDKIT.READY_CHECK)
    end
end

local function getSettings(self)
    local settings = self.Settings and self.Settings.ah
    return type(settings) == "table" and settings or {}
end

function FWR:IsAuctionHouseOpen()
    return auctionHouseOpen == true
end

function FWR:IsAuctionScanRunning()
    return scan.running == true
end

function FWR:GetAuctionDataStore()
    local db = self:EnsureAdvisorStore()
    db._ah = type(db._ah) == "table" and db._ah or {}
    db._ah.items = type(db._ah.items) == "table" and db._ah.items or {}
    return db._ah
end

function FWR:GetAuctionFreshnessMinutes()
    return tonumber(getSettings(self).freshnessMinutes) or 30
end

-- Seconds until a new scan is allowed. Only a finished scan locks, a failed one never does.
function FWR:GetAuctionScanCooldownSeconds()
    local age = self:GetAuctionSyncAgeSeconds()
    if not age then
        return 0
    end
    -- a different scan level than the one that made the prices: the prices are not what is wanted now
    local settings = getSettings(self)
    local level = settings.fullScan == true and "full" or (settings.scanCommodities ~= false and "commodities" or "trade")
    if (self:GetAuctionDataStore().lastScanLevel or "trade") ~= level then
        return 0
    end
    return math.max(0, MIN_SECONDS_BETWEEN_SCANS - age)
end

-- "about 40 seconds" from the previous scan, or a general warning before the first one.
function FWR:GetAuctionScanEstimateText()
    local seconds = tonumber(self:GetAuctionDataStore().lastScanSeconds)
    if seconds then
        return string.format("It usually takes about %d seconds.", math.max(5, seconds))
    end
    return "The first scan can take up to a minute."
end

-- Seconds since the last completed scan, or nil when there never was one.
function FWR:GetAuctionSyncAgeSeconds()
    local store = self:GetAuctionDataStore()
    local lastSync = tonumber(store.lastSyncTime)
    if not lastSync or (tonumber(store.lastSyncCount) or 0) <= 0 then
        return nil
    end
    return math.max(0, time() - lastSync)
end

-- Text and colour for the scanner indicator:
--   blue    scanning, with progress
--   green   prices are newer than the update interval
--   yellow  older than the interval, up to twice the interval
--   red     older than that, or never scanned
function FWR:GetAuctionSyncAgeText()
    if scan.running then
        if scan.expected > 0 then
            local percent = math.min(99, math.floor((scan.found / scan.expected) * 100))
            return string.format("Now scanning... %d%%", percent), 0.4, 0.8, 1
        end
        return string.format("Now scanning... %d items", scan.found), 0.4, 0.8, 1
    end

    local age = self:GetAuctionSyncAgeSeconds()
    if not age then
        return "AH prices: not scanned yet", 1, 0.3, 0.3
    end

    local minutes = math.floor(age / 60)
    local hours = math.floor(minutes / 60)
    local text
    if hours >= 24 then
        text = string.format("AH prices: %dd %dh old", math.floor(hours / 24), hours % 24)
    elseif hours > 0 then
        text = string.format("AH prices: %dh %02dm old", hours, minutes % 60)
    else
        text = string.format("AH prices: %dm old", minutes)
    end

    local limit = self:GetAuctionFreshnessMinutes() * 60
    if age <= limit then
        return text, 0.3, 1, 0.3
    elseif age <= limit * 2 then
        return text, 1, 0.85, 0.2
    end
    return text, 1, 0.3, 0.3
end

-- Whether a scan is running, how far it is (0-99, or nil when the size is not known yet) and how
-- many priced items it has found so far.
function FWR:GetAuctionScanProgress()
    if not scan.running then
        return false, nil, 0
    end
    if scan.expected > 0 then
        return true, math.min(99, math.floor((scan.found / scan.expected) * 100)), scan.found
    end
    return true, nil, scan.found
end

function FWR:GetAuctionScanMinimumMinutes()
    return math.floor(MIN_SECONDS_BETWEEN_SCANS / 60)
end

-- "trade", "commodities" or "full"
local function scanLevel(self)
    local settings = getSettings(self)
    if settings.fullScan == true then
        return "full"
    elseif settings.scanCommodities ~= false then
        return "commodities"
    end
    return "trade"
end

local LEVEL_TEXT = {
    trade = "trade materials only",
    commodities = "trade materials and everything sold by amount",
    full = "whole Auction House",
}

-- Whether a class id is read at this scan level (used when a getAll answer is filtered afterwards).
local function classIsScanned(classID)
    if not scan.classes then
        return true
    end
    for _, id in ipairs(scan.classes) do
        if id == classID then
            return true
        end
    end
    return false
end

-- The Advisor works out all its places and items again when it is refreshed, which is a lot of work
-- while a scan sends a new page every fraction of a second. While a scan runs it is refreshed at most
-- once a second; the last state is always shown (a refresh is kept for the end of the pause).
local ADVISOR_REFRESH_SECONDS = 1
local advisorRefreshedAt = -100
local advisorRefreshWaiting = false

local function refreshAdvisorThrottled(self)
    if not self.RefreshAdvisorPanel then
        return
    end

    local waited = GetTime() - advisorRefreshedAt
    if not scan.running or waited >= ADVISOR_REFRESH_SECONDS then
        advisorRefreshedAt = GetTime()
        self:RefreshAdvisorPanel()
        return
    end

    if not advisorRefreshWaiting then
        advisorRefreshWaiting = true
        C_Timer.After(ADVISOR_REFRESH_SECONDS - waited, function()
            advisorRefreshWaiting = false
            advisorRefreshedAt = GetTime()
            if FWR.RefreshAdvisorPanel then
                FWR:RefreshAdvisorPanel()
            end
        end)
    end
end

local function refreshPanels(self)
    if self.Emit then
        self:Emit("auctionScanChanged")
    end
    refreshAdvisorThrottled(self)
    if self.RefreshMainWindowText then
        self:RefreshMainWindowText()
    end
end

local function abortScan(self, message)
    scan.running = false
    scan.pendingStart = false
    say(message)
    refreshPanels(self)
end

local sendQuery
local sendNextPage

-- Watchdog: every sign of life re-arms it. If nothing happens in time the scan is retried, up to
-- MAX_ATTEMPTS times, then it gives up with a message that says how far it got.
local function watch(self, seconds)
    scan.activity = scan.activity + 1
    local seen = scan.activity

    C_Timer.After(seconds or RESULT_TIMEOUT_SECONDS, function()
        if not scan.running or scan.activity ~= seen then
            return
        end

        if scan.attempt < MAX_ATTEMPTS then
            scan.attempt = scan.attempt + 1
            sendQuery(FWR)
        elseif scan.gotResults then
            abortScan(FWR, string.format("The Auction House stopped answering after %d items. Prices were not updated (/fw scan to try again).", scan.found))
        else
            abortScan(FWR, "The Auction House returned no items. Try again in a moment (/fw scan).")
        end
    end)
end

-- Sends the query that is being run right now: a whole-Auction-House getAll download, or the next
-- page of the class being read.
sendQuery = function(self)
    scan.gotResults = false

    local ok, err
    if scan.useGetAll then
        ok, err = pcall(QueryAuctionItems, "", nil, nil, 0, false, nil, true)
    else
        local classID = scan.classes[scan.classIndex]
        ok, err = pcall(QueryAuctionItems, "", nil, nil, scan.page, false, nil, false, false,
                        { classID = classID })
    end

    if not ok then
        abortScan(self, "The Auction House scan could not start: " .. tostring(err))
        return false
    end

    watch(self, scan.useGetAll and GETALL_WAIT_SECONDS or RESULT_TIMEOUT_SECONDS)
    return true
end

-- Reads the current page's auctions into scan.prices (lowest buyout per piece per item id).
local function collectCurrentPage()
    local numBatch, total = GetNumAuctionItems("list")
    if not numBatch or numBatch <= 0 then
        return 0, total or 0
    end

    local added = 0
    for index = 1, numBatch do
        local _, _, count, _, _, _, _, _, _, buyoutPrice, _, _, _, _, _, _, itemID =
            GetAuctionItemInfo("list", index)
        count = tonumber(count) or 0
        buyoutPrice = tonumber(buyoutPrice) or 0
        itemID = tonumber(itemID)
        if itemID and buyoutPrice > 0 and count > 0 then
            local unit = math.floor(buyoutPrice / count)
            if unit > 0 then
                local best = scan.prices[itemID]
                if not best or unit < best then
                    scan.prices[itemID] = unit
                    if not best then
                        added = added + 1
                    end
                end
            end
        end
    end
    return added, total or 0
end

local function finishScan(self)
    local items = {}
    local priced = 0
    local now = time()

    for itemID, unitPrice in pairs(scan.prices) do
        items[tostring(itemID)] = { itemID = itemID, unitPrice = unitPrice, lastSeen = now }
        priced = priced + 1
    end

    if priced == 0 then
        abortScan(self, "The Auction House scan found no prices. Try again in a moment (/fw scan).")
        return
    end

    local seconds = math.max(1, math.floor(GetTime() - scan.startedAt))
    local store = self:GetAuctionDataStore()
    store.items = items
    store.lastSyncTime = now
    store.lastSyncCount = priced
    store.lastScanSeconds = seconds
    store.lastScanLevel = scanLevel(self)

    scan.running = false
    if self.Emit then
        self:Emit("auctionScanFinished", items, now)
    end
    say(string.format("Auction House scan complete: %d items priced in %d seconds.", priced, seconds))

    playFinishedSound(getSettings(self))
    refreshPanels(self)
end

local function advanceClass(self)
    if scan.classes and scan.classIndex < #scan.classes then
        scan.classIndex = scan.classIndex + 1
        scan.page = 0
        scan.totalPages = 0
        scan.attempt = 1
        sendNextPage(self)
        return true
    end
    return false
end

-- Sends the next page query for the current class (or finishes / moves to the next class).
sendNextPage = function(self)
    if not scan.running then
        return
    end

    if scan.totalPages > 0 and scan.page >= scan.totalPages - 1 then
        -- this class is fully read
        if not advanceClass(self) then
            finishScan(self)
        end
        return
    end

    scan.page = scan.page + 1
    C_Timer.After(PAGE_RETRY_SECONDS, function()
        if scan.running then
            sendQuery(FWR)
        end
    end)
end

local function handleBrowseResults(self)
    if not scan.running then
        return
    end

    local added, total = collectCurrentPage()
    scan.gotResults = true

    if scan.useGetAll then
        -- getAll brings everything in one answer; keep only the classes this level reads
        if scan.classes then
            local kept = {}
            for itemID, unitPrice in pairs(scan.prices) do
                local classID = select(6, GetItemInfoInstant(itemID))
                if classID and classIsScanned(classID) then
                    kept[itemID] = unitPrice
                end
            end
            scan.prices = kept
        end
        scan.found = 0
        for _ in pairs(scan.prices) do
            scan.found = scan.found + 1
        end
        finishScan(self)
        return
    end

    scan.found = scan.found + added

    -- total pages of this class query (first answer sets it)
    if scan.totalPages <= 0 and total > 0 then
        scan.totalPages = math.ceil(total / 50)
    end

    if total <= 0 then
        -- a class with nothing for sale
        if not advanceClass(self) then
            finishScan(self)
        end
        return
    end

    watch(self, BATCH_TIMEOUT_SECONDS)
    sendNextPage(self)
    refreshPanels(self)
end

local function startNow(self)
    scan.pendingStart = false
    scan.running = true
    scan.found = 0
    scan.expected = tonumber(self:GetAuctionDataStore().lastSyncCount) or 0
    scan.startedAt = GetTime()
    scan.attempt = 1
    scan.prices = {}
    scan.page = 0
    scan.totalPages = 0
    scan.classIndex = 1

    local level = scanLevel(self)
    if level == "full" then
        scan.classes = nil
    elseif level == "commodities" then
        scan.classes = COMMODITY_CLASS_IDS
    else
        scan.classes = { TRADEGOODS_CLASS_ID }
    end
    -- the size of the last scan only helps when it was a scan of this level
    if self:GetAuctionDataStore().lastScanLevel ~= level then
        scan.expected = 0
    end

    -- a getAll download is one query for the whole house and covers every level; use it whenever
    -- the server allows it
    local _, canSendAll = CanSendAuctionQuery()
    scan.useGetAll = canSendAll == true

    if sendQuery(self) then
        say("Auction House scan started (" .. LEVEL_TEXT[level] .. "). Keep the Auction House open until it finishes. " .. self:GetAuctionScanEstimateText())
        refreshPanels(self)
    end
end

-- The game only accepts a query when it says it is ready.
local function startWhenReady(self, attempt)
    if not auctionHouseOpen or scan.running then
        scan.pendingStart = false
        return
    end

    local canSend = CanSendAuctionQuery()
    if canSend then
        startNow(self)
        return
    end

    scan.pendingStart = true
    if attempt >= 10 then
        scan.pendingStart = false
        say("The Auction House is busy right now. Try the scan again in a moment.")
        return
    end

    C_Timer.After(1, function()
        startWhenReady(FWR, attempt + 1)
    end)
end

-- Starts a scan. Returns false when it cannot start (not at the Auction House, already running).
function FWR:StartAuctionScan()
    if scan.running then
        say("An Auction House scan is already running.")
        return false
    end

    local cooldown = self:GetAuctionScanCooldownSeconds()
    if cooldown > 0 then
        say(string.format("The prices are still fresh. A new scan is possible in %d minutes.", math.ceil(cooldown / 60)))
        return false
    end

    if not auctionHouseOpen or type(QueryAuctionItems) ~= "function" then
        say("Open the Auction House first, then start the scan.")
        return false
    end

    startWhenReady(self, 1)
    return true
end

function FWR:FinishAuctionScanFromCollected()
    if scan.running then
        finishScan(self or FWR)
    end
end

-- The options of the Scanner page decide: a scan is due when "Scan automatically" is on and the
-- prices are older than the chosen interval (or there never was one).
local function autoScanIsDue(self)
    if getSettings(self).autoScan == false then
        return false
    end
    local age = self:GetAuctionSyncAgeSeconds()
    return self:GetAuctionScanCooldownSeconds() == 0 and (age == nil or age >= self:GetAuctionFreshnessMinutes() * 60)
end

-- A scan is running, is about to start, or is due and will start by itself.
function FWR:IsAuctionScanComing()
    return scan.running == true or scan.pendingStart == true or autoScanIsDue(self)
end

-- While the Auction House stays open the prices get old: as soon as they are older than the chosen
-- interval a new scan starts by itself. Looked at every few seconds; after an attempt that did not
-- get to scan there is a pause before the next one.
local AUTO_CHECK_SECONDS = 5
local AUTO_RETRY_SECONDS = 30
local autoTicker
local lastAutoAttempt = -AUTO_RETRY_SECONDS

local function startAutoCheck()
    if autoTicker then
        return
    end
    autoTicker = C_Timer.NewTicker(AUTO_CHECK_SECONDS, function()
        if not auctionHouseOpen or scan.running or scan.pendingStart or not autoScanIsDue(FWR) then
            return
        end
        if GetTime() - lastAutoAttempt < AUTO_RETRY_SECONDS then
            return
        end
        lastAutoAttempt = GetTime()
        FWR:StartAuctionScan()
    end)
end

-- Single entry point for every Auction House event; the main file decides when it is called.
function FWR:HandleAuctionHouseEvent(event)
    if event == "AUCTION_HOUSE_SHOW" then
        auctionHouseOpen = true
        startAutoCheck()
        if autoScanIsDue(self) then
            C_Timer.After(START_DELAY_SECONDS, function()
                if auctionHouseOpen and not scan.running then
                    FWR:StartAuctionScan()
                end
            end)
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        auctionHouseOpen = false
        scan.pendingStart = false
        if scan.running then
            abortScan(self, "The Auction House was closed before the scan finished. Prices were not updated.")
            return
        end
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        handleBrowseResults(self)
    end

    refreshPanels(self)
end
