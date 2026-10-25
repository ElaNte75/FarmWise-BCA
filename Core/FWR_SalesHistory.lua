local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local GetItemInfoInstant = GetItemInfoInstant
local GetItemInfo = GetItemInfo

-- Sales history of the Auction House.
--
-- What it keeps, per item and per realm (FarmWiseDB._sales[realm][key]):
--   sold       pieces sold (from the "Auction successful" mails)
--   net        gold received for them, after the 5% cut of the Auction House
--   gross      the same before the cut
--   sales      how many sale mails that was
--   returned   pieces that came back unsold (the "Auction expired" mails)
--   cancelled  pieces you took back yourself (the "Auction cancelled" mails)
--   posted     pieces posted (from the Auction House calls, whoever made them), posts = how many posts
--   last       time of the last sale
--
-- How it reads the mails: when the mailbox is open it keeps a list of the mails that can be taken (a sale with
-- its gold, an expired or cancelled auction with its items). A mail that is gone from the list a moment after
-- you took something is a mail you collected: it is counted then, once. Nothing is counted for what happened
-- before the history was switched on, and a sale that is still in the mailbox is not counted until you take it.
--
-- The mail of a sale tells the NAME of the item, not which quality it was. The quality is found from what is
-- known: the items you posted, farmed or carry that have that name; when that is not enough the sales are kept
-- under the name alone ("key" starts with "n:"), never guessed.

local TAKE_WINDOW_SECONDS = 60     -- a mail that leaves the list counts only if something was taken just before
local SAME_MAIL_SECONDS = 180      -- two looks at one mail give a time of expiry that differs by less than this
local POST_LOG_LIMIT = 300         -- the posts kept to tell qualities apart
local RECENT_SALES = 30            -- the last sales kept for each item, for the average price (the option uses 5 to 30)
local AVERAGE_MAX_AGE_DAYS = 30    -- sales older than this are not part of an average
local AVERAGE_MIN_SALES = 3        -- an average needs at least this many sales ...
local AVERAGE_MIN_PIECES = 20      -- ... and at least this many pieces
local MAX_ATTACHMENTS = _G.ATTACHMENTS_MAX_RECEIVE or 16

local lastTake = -1000
local snapshot            -- the units of the mailbox, as of the last look (nil: not looked at yet)
-- the list of the mailbox is in only after the game has said so (MAIL_INBOX_UPDATE) since the mailbox opened
local inboxLoaded = false
local looking = false     -- a look is already waiting
local pendingPost         -- the last post asked for, until the game says it was created

local function enabled()
    local settings = FWR.Settings and FWR.Settings.ah
    return not (type(settings) == "table" and settings.tabHistory == false)
end

function FWR:IsSalesHistoryEnabled()
    return enabled()
end

local function realmKey()
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
    if type(realm) ~= "string" or realm == "" then
        return nil
    end
    return realm
end

------------------------------------------------------------
-- The saved data
------------------------------------------------------------

local function records()
    local realm = realmKey()
    if not realm or type(FarmWiseDB) ~= "table" then
        return nil
    end
    if type(FarmWiseDB._sales) ~= "table" then
        FarmWiseDB._sales = {}
    end
    if type(FarmWiseDB._sales[realm]) ~= "table" then
        FarmWiseDB._sales[realm] = {}
    end
    return FarmWiseDB._sales[realm]
end

local function record(key, itemID, name)
    local all = records()
    if not all then
        return nil
    end
    local entry = all[key]
    if type(entry) ~= "table" then
        entry = { sold = 0, net = 0, gross = 0, sales = 0, returned = 0, cancelled = 0, posted = 0, posts = 0, last = 0 }
        all[key] = entry
    end
    entry.id = itemID or entry.id
    entry.name = name or entry.name
    return entry
end

-- names of the items that are known, to find the item behind the name in a sale mail: { [lowername] = { [itemID] = time } }
local function nameIndex()
    if type(FarmWiseDB) ~= "table" then
        return nil
    end
    if type(FarmWiseDB._salesNames) ~= "table" then
        FarmWiseDB._salesNames = {}
    end
    return FarmWiseDB._salesNames
end

local function noteName(itemID, name)
    local index = nameIndex()
    if not index or not itemID or type(name) ~= "string" or name == "" then
        return
    end
    local lower = string.lower(name)
    local ids = index[lower]
    if type(ids) ~= "table" then
        ids = {}
        index[lower] = ids
    end
    ids[tostring(itemID)] = time()
end

-- the last posts (item, price of one, amount), to tell the quality of a sold item by the price it was posted at
local function postLog()
    if type(FarmWiseDB) ~= "table" then
        return nil
    end
    if type(FarmWiseDB._salesPosts) ~= "table" then
        FarmWiseDB._salesPosts = {}
    end
    return FarmWiseDB._salesPosts
end

------------------------------------------------------------
-- Which item is behind a name
------------------------------------------------------------

local function itemName(itemID)
    if GetItemInfo then
        return GetItemInfo(itemID)
    end
    return GetItemInfo and (GetItemInfo(itemID)) or nil
end

-- what is carried and what is farmed is learned when the mailbox opens
local function learnNames()
    local lastBag = (tonumber(NUM_BAG_SLOTS) or 4) + (tonumber(NUM_REAGENTBAG_SLOTS) or 1)
    if GetContainerItemID then
        for bag = 0, lastBag do
            local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
            for slot = 1, slots do
                local itemID = GetContainerItemID(bag, slot)
                if itemID then
                    noteName(itemID, itemName(itemID))
                end
            end
        end
    end
    if FWR.GetFarmedItemIDs then
        for itemID in pairs(FWR:GetFarmedItemIDs()) do
            noteName(itemID, itemName(itemID))
        end
    end
end

-- Returns the item ID, or nil when it cannot be told (the sale is then kept under the name).
local function resolveItem(name, count, gross)
    local lower = string.lower(name)
    local candidates = {}
    local index = nameIndex()
    local known = index and index[lower]
    if type(known) == "table" then
        for id in pairs(known) do
            candidates[#candidates + 1] = tonumber(id)
        end
    end
    if #candidates == 0 and GetItemInfoInstant then
        local id = GetItemInfoInstant(name)
        if id then
            candidates[1] = id
        end
    end
    if #candidates == 0 then
        return nil
    end
    if #candidates == 1 then
        return candidates[1]
    end

    -- several qualities have this name: the one that was posted at this price (the newest post wins)
    local unit = (count and count > 0 and gross) and gross / count or nil
    local log = postLog()
    if unit and log then
        local wanted = {}
        for _, id in ipairs(candidates) do
            wanted[id] = true
        end
        for position = #log, 1, -1 do
            local post = log[position]
            if wanted[post.id] and math.abs((post.unit or 0) - unit) < 1 then
                return post.id
            end
        end
    end
    return nil
end

------------------------------------------------------------
-- What the mailbox shows
------------------------------------------------------------

local EXPIRED_TEXT = (_G.AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s"):gsub("%%s", "")
local CANCELLED_TEXT = (_G.AUCTION_REMOVED_MAIL_SUBJECT or "Auction cancelled: %s"):gsub("%%s", "")
local SOLD_TEXT = (_G.AUCTION_SOLD_MAIL_SUBJECT or "Auction successful: %s"):gsub("%%s", "")

-- A "unit" is something that can be taken from the mailbox: the gold of a sale, or one attachment of an
-- expired or cancelled auction. { kind, key, expiry, ... what it is worth }
-- What a unit IS comes from the header of the mail (its subject), which is always there; what it is worth (the
-- amount, the price, the cut) comes from the invoice, which the game may give a moment later. A unit that has
-- no worth yet gets it from an earlier look, or from the moment it was taken.

-- the units of one mail
local function readMail(index, now)
    local units = {}
    local _, _, sender, subject, money, _, daysLeft, _, _, _, _, canReply = GetInboxHeaderInfo(index)
    if not subject then
        return units
    end
    -- A mail from a player can be answered; the mails of the Auction House cannot. Only those can be sales.
    local fromSystem = canReply ~= true
    local expiry = (now or time()) + math.floor((tonumber(daysLeft) or 0) * 86400)
    sender = sender or ""

    local invoiceType, name, _, bid, _, _, consignment, _, _, _, count
    if GetInboxInvoiceInfo then
        invoiceType, name, _, bid, _, _, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
    end

    -- A sale is something to take only while its mail still holds the gold: the moment the gold is taken the game
    -- shows the mail with no money, a little before it is deleted. A mail with no money is not a sale to count.
    local hasGold = (tonumber(money) or 0) > 0
    local isSale = hasGold and (invoiceType == "seller"
        or (fromSystem and invoiceType == nil and subject ~= "" and string.find(subject, SOLD_TEXT, 1, true) == 1))
    if isSale then
        if not name and subject ~= "" and string.find(subject, SOLD_TEXT, 1, true) == 1 then
            name = string.sub(subject, #SOLD_TEXT + 1)
        end
        units[#units + 1] = {
            kind = "sale",
            key = "S|" .. sender .. "|" .. subject .. "|" .. tostring(money or 0),
            expiry = expiry,
            name = name,
            count = tonumber(count),
            gross = tonumber(bid),
            cut = tonumber(consignment) or 0,
        }
    elseif fromSystem and (invoiceType == nil or invoiceType == "") then
        local kind
        if subject ~= "" and string.find(subject, EXPIRED_TEXT, 1, true) then
            kind = "expired"
        elseif subject ~= "" and string.find(subject, CANCELLED_TEXT, 1, true) then
            kind = "cancelled"
        end
        if kind then
            for attachment = 1, MAX_ATTACHMENTS do
                local itemName, itemID, _, itemCount = GetInboxItem(index, attachment)
                if itemName then
                    units[#units + 1] = {
                        kind = kind,
                        key = "A|" .. sender .. "|" .. subject .. "|" .. attachment .. "|" .. tostring(itemID) .. "|" .. tostring(itemCount),
                        expiry = expiry,
                        name = itemName,
                        itemID = tonumber(itemID),
                        count = tonumber(itemCount) or 1,
                    }
                end
            end
        end
    end
    return units
end

local function readMailbox()
    local units = {}
    local numItems = GetInboxNumItems and GetInboxNumItems() or 0
    local now = time()
    for index = 1, numItems do
        for _, unit in ipairs(readMail(index, now)) do
            units[#units + 1] = unit
        end
    end
    return units
end

local function sameUnit(first, second)
    return first.key == second.key and math.abs(first.expiry - second.expiry) <= SAME_MAIL_SECONDS
end

-- What was seen at the moment it was taken (the mail is still there at that moment, with all its information).
-- A unit that is seen leaving the mailbox is counted once: when it is counted from the list of the mailbox, its
-- entry here is used up (one for one, so two equal sales are two sales).
local captured = {}

local function useUpCaptured(unit)
    for position, other in ipairs(captured) do
        if sameUnit(unit, other) then
            table.remove(captured, position)
            return
        end
    end
end

-- When a sale happened. The mail of a sale lives 30 days from the moment it came (within an hour of the sale), so
-- the days it has left tell when it came: taking the gold the next day does not make it a sale of the next day.
local MAIL_LIFE_SECONDS = 30 * 86400

local function saleMoment(unit, now)
    if unit.expiry then
        local arrived = unit.expiry - MAIL_LIFE_SECONDS
        if arrived <= now and arrived > now - 31 * 86400 then
            return arrived
        end
    end
    return now
end

local function countUnit(unit)
    local when = time()
    if unit.kind == "sale" then
        if not unit.name or not unit.count or unit.count < 1 or not unit.gross then
            return false
        end
        local itemID = resolveItem(unit.name, unit.count, unit.gross)
        local key = itemID and tostring(itemID) or ("n:" .. string.lower(unit.name))
        local entry = record(key, itemID, unit.name)
        if not entry then
            return false
        end
        entry.sold = entry.sold + unit.count
        entry.gross = entry.gross + unit.gross
        -- the price check: the pieces of a post that it made dearer, once they are sold, are what it saved (net)
        if itemID then
            local log = postLog()
            local unitPrice = unit.gross / unit.count
            local remaining = unit.count
            for _, post in ipairs(log or {}) do
                if remaining > 0 and post.id == itemID and post.gain and (post.left or 0) > 0
                    and math.abs((post.unit or 0) - unitPrice) < 1 then
                    local take = math.min(remaining, post.left)
                    -- (after the 5% the Auction House keeps: what is really earned)
                    entry.saved = (entry.saved or 0) + math.floor(take * post.gain * (1 - (tonumber(FWR.AUCTION_HOUSE_CUT) or 0.05)))
                    entry.savedPieces = (entry.savedPieces or 0) + take
                    post.left = post.left - take
                    remaining = remaining - take
                end
            end
        end
        entry.net = entry.net + math.max(0, unit.gross - unit.cut)
        entry.sales = entry.sales + 1
        -- when it really happened: what the Actions ledger saw, else the age of the mail, else now
        local soldAt = (FWR.GetActionSaleMoment and FWR:GetActionSaleMoment(itemID, unit.name, unit.count))
            or saleMoment(unit, when)
        entry.last = math.max(entry.last or 0, soldAt)
        -- the last sales (time, pieces, gold before the cut) are what the average price is made of
        if type(entry.recent) ~= "table" then
            entry.recent = {}
        end
        entry.recent[#entry.recent + 1] = { t = soldAt, q = unit.count, g = unit.gross }
        while #entry.recent > RECENT_SALES do
            table.remove(entry.recent, 1)
        end
        -- the Actions page clears its line when the gold is taken
        FWR:Emit("auctionUnitCollected", { kind = "sale", itemID = itemID, name = unit.name, count = unit.count })
        return true
    elseif unit.itemID then
        noteName(unit.itemID, unit.name)
        local entry = record(tostring(unit.itemID), unit.itemID, unit.name)
        if not entry then
            return false
        end
        if unit.kind == "expired" then
            entry.returned = entry.returned + unit.count
        else
            entry.cancelled = entry.cancelled + unit.count
        end
        FWR:Emit("auctionUnitCollected", { kind = unit.kind, itemID = unit.itemID, name = unit.name, count = unit.count })
        return true
    end
    return false
end

-- the unit, with what is known of it from the moment it was taken
local function withCaptured(unit)
    if unit.kind == "sale" and (not unit.count or not unit.gross) then
        for _, other in ipairs(captured) do
            if sameUnit(unit, other) then
                unit.name = unit.name or other.name
                unit.count = unit.count or other.count
                unit.gross = unit.gross or other.gross
                unit.cut = unit.cut or other.cut
                break
            end
        end
    end
    return unit
end

-- Looks at the mailbox again and counts what left it since the last look.
local function look()
    looking = false
    if not enabled() or not records() then
        snapshot = nil
        return
    end

    local current = readMailbox()
    local previous = snapshot
    snapshot = current

    local changed = false

    -- 1. what was there at the last look and is gone now (only when something was taken a moment ago)
    if previous and (GetTime() - lastTake) <= TAKE_WINDOW_SECONDS then
        local used = {}
        for _, old in ipairs(previous) do
            local found
            for position, unit in ipairs(current) do
                if not used[position] and sameUnit(unit, old) then
                    found = position
                    break
                end
            end
            if found then
                used[found] = true
                -- what was not known yet may be known now, and what was known is not lost
                local unit = current[found]
                unit.name = unit.name or old.name
                unit.count = unit.count or old.count
                unit.gross = unit.gross or old.gross
                unit.cut = unit.cut or old.cut
            else
                if countUnit(withCaptured(old)) then
                    changed = true
                end
            end
        end
    elseif previous then
        -- nothing was taken: only carry over what is known
        for _, unit in ipairs(current) do
            for _, old in ipairs(previous) do
                if sameUnit(unit, old) then
                    unit.name = unit.name or old.name
                    unit.count = unit.count or old.count
                    unit.gross = unit.gross or old.gross
                    unit.cut = unit.cut or old.cut
                    break
                end
            end
        end
    end

    -- 2. what was seen at the moment it was taken. A mail is counted ONCE, and the list of the mailbox decides:
    --    - still in the mailbox: wait (the take may not be done yet)
    --    - it was in the list at the last look: it was counted above, so this entry is only thrown away (the
    --      same mail can be taken by several calls, one for each place it had in the list)
    --    - it was never in the list (a mail addon took it before the first look): it is counted here, once
    for position = #captured, 1, -1 do
        local unit = captured[position]
        local stillThere = false
        for _, other in ipairs(current) do
            if sameUnit(unit, other) then
                stillThere = true
                break
            end
        end
        if not stillThere then
            table.remove(captured, position)
            local seenBefore = false
            for _, old in ipairs(previous or {}) do
                if sameUnit(unit, old) then
                    seenBefore = true
                    break
                end
            end
            if not seenBefore then
                -- every other entry of the same mail goes with it
                for other = #captured, 1, -1 do
                    if sameUnit(unit, captured[other]) then
                        table.remove(captured, other)
                    end
                end
                if countUnit(unit) then
                    changed = true
                end
            end
        end
    end

    if changed and FWR.Emit then
        FWR:Emit("salesHistoryChanged")
    end

    -- the Actions page learns from the mails how its posts ended (after the counting above: it still needs its
    -- lines to date the sales that were counted)
    FWR:Emit("auctionMailSeen", current, inboxLoaded)
end

local function lookSoon()
    if looking then
        return
    end
    looking = true
    C_Timer.After(0.1, look)
end

-- what is known of the mail at the moment it is taken (called from the calls that take it)
local function captureMail(index)
    if not enabled() or type(index) ~= "number" then
        return
    end
    local now = GetTime()
    for _, unit in ipairs(readMail(index)) do
        -- the same mail taken by two calls in a row (for example "take the gold" and "take everything")
        local duplicate = false
        for position, other in ipairs(captured) do
            if other.capIndex == index and sameUnit(unit, other) and now - other.capAt < 5 then
                if (unit.count and unit.gross) and not (other.count and other.gross) then
                    unit.capIndex, unit.capAt = index, now
                    captured[position] = unit
                end
                duplicate = true
                break
            end
        end
        if not duplicate then
            unit.capIndex, unit.capAt = index, now
            captured[#captured + 1] = unit
        end
    end
end

------------------------------------------------------------
-- The posts
------------------------------------------------------------

local function logPost(post)
    local itemID = post.itemID
    if not itemID or not post.quantity or post.quantity < 1 then
        return
    end
    if not enabled() then
        return
    end
    local entry = record(tostring(itemID), itemID, post.name)
    if entry then
        entry.posted = entry.posted + post.quantity
        entry.posts = entry.posts + 1
    end
    noteName(itemID, post.name)

    local log = postLog()
    if log then
        -- gain: what the price check added to the price of one piece (see GetPriceCheckSavings); left: how many
        -- of this post are not credited yet
        log[#log + 1] = { id = itemID, unit = post.unit, qty = post.quantity, t = time(), gain = post.gain,
            left = post.gain and post.quantity or nil }
        while #log > POST_LOG_LIMIT do
            table.remove(log, 1)
        end
    end
    if FWR.Emit then
        FWR:Emit("salesHistoryChanged")
    end
end

-- every post asked for through the game's own call, whichever addon or window it came from
-- (on this client a post is StartAuction(minBid, buyoutPrice, runTime) of whatever is in the sell slot)
if type(StartAuction) == "function" then
    pcall(hooksecurefunc, "StartAuction", function(_, buyoutPrice)
        local name, _, count
        if type(GetAuctionSellItemInfo) == "function" then
            name, _, count = GetAuctionSellItemInfo()
        end
        count = tonumber(count)
        local unit = tonumber(buyoutPrice)
        if unit and count and count > 0 then
            unit = math.floor(unit / count + 0.5)   -- the buyout is for the whole stack: the price of one piece
        end
        -- the FarmWise tab tells what its price check added to this post (before it asks for the post)
        local note = FWR.PostGainNote
        FWR.PostGainNote = nil
        local itemID = note and note.itemID or nil
        local gain = note and tonumber(note.perPiece) or nil
        pendingPost = {
            gain = gain and gain > 0 and gain or nil,
            itemID = itemID,
            name = name or (itemID and itemName(itemID)) or nil,
            quantity = count,
            unit = unit,
            at = GetTime(),
        }
    end)
end

------------------------------------------------------------
-- Events
------------------------------------------------------------

-- the game's calls that take gold or items out of a mail (called by its own mailbox, and by mail addons)
local function tookSomething(index)
    lastTake = GetTime()
    pcall(captureMail, index)
    lookSoon()
end
for _, name in ipairs({ "TakeInboxMoney", "TakeInboxItem", "AutoLootMailItem" }) do
    if type(_G[name]) == "function" then
        pcall(hooksecurefunc, name, tookSomething)
    end
end

-- the mailbox is open now / how many times it was opened (to leave what was taken in the books for a while after
-- it is closed: the game still answers the takes of the last moment)
local mailOpen = false
local mailVisit = 0

local events = CreateFrame("Frame")

-- Wrap RegisterEvent in pcall for WoW Forever compatibility
local function safeRegisterEvent(event)
    pcall(events.RegisterEvent, events, event)
end

safeRegisterEvent("MAIL_SHOW")
safeRegisterEvent("MAIL_INBOX_UPDATE")
safeRegisterEvent("MAIL_CLOSED")
safeRegisterEvent("NEW_AUCTION_UPDATE")
events:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SHOW" then
        mailOpen = true
        mailVisit = mailVisit + 1
        inboxLoaded = false
        snapshot = nil
        wipe(captured)
        if enabled() then
            pcall(learnNames)
            lookSoon()
            -- an empty mailbox may not say MAIL_INBOX_UPDATE: a moment later the list is known all the same
            C_Timer.After(1.5, function()
                if not inboxLoaded and _G.MailFrame and _G.MailFrame:IsShown() then
                    inboxLoaded = true
                    lookSoon()
                end
            end)
        end
    elseif event == "MAIL_INBOX_UPDATE" then
        if mailOpen then
            inboxLoaded = true
        end
        if enabled() then
            lookSoon()
        end
    elseif event == "MAIL_CLOSED" then
        mailOpen = false
        inboxLoaded = false
        -- Gold taken a moment before the mailbox was closed is still being answered by the game (the mail
        -- leaves the list a little later): the looks go on, and the books are cleared only after a while, if the
        -- mailbox was not opened again.
        local visit = mailVisit
        C_Timer.After(20, function()
            if not mailOpen and visit == mailVisit then
                snapshot = nil
                wipe(captured)
            end
        end)
    elseif event == "NEW_AUCTION_UPDATE" then
        if pendingPost and GetTime() - pendingPost.at < 60 then
            local post = pendingPost
            pendingPost = nil
            pcall(logPost, post)
        end
    end
end)

------------------------------------------------------------
-- What the window of the history asks for
------------------------------------------------------------

-- What the price check made you earn: for each post it made dearer (the price you would have posted without it, up to
-- the lowest usual price), the difference for each piece that was sold. Only what is sold counts. Copper.
-- Returns the copper, the pieces that were sold with a price made higher by the check, and how many different items
-- they were.
function FWR:GetPriceCheckSavings()
    local total, pieces, items = 0, 0, 0
    local log
    for _, entry in pairs(records() or {}) do
        if type(entry) == "table" and (tonumber(entry.saved) or 0) > 0 then
            if entry.savedPieces == nil then
                -- what was counted before the pieces were: they are told by the posts that are still in the log
                log = log or postLog() or {}
                local counted = 0
                for _, post in ipairs(log) do
                    if post.id == entry.id and post.gain and post.qty then
                        counted = counted + math.max(0, post.qty - (post.left or 0))
                    end
                end
                entry.savedPieces = counted
            end
            total = total + entry.saved
            pieces = pieces + (tonumber(entry.savedPieces) or 0)
            items = items + 1
        end
    end
    return total, pieces, items
end

-- The items behind the total of the price check, the biggest first: { itemID, name, saved (copper), pieces }
function FWR:GetPriceCheckBreakdown()
    local list = {}
    for key, entry in pairs(records() or {}) do
        if type(entry) == "table" and (tonumber(entry.saved) or 0) > 0 then
            local name = entry.name
            if (not name or name == "") and entry.id then
                name = itemName(entry.id)
            end
            list[#list + 1] = { itemID = entry.id, name = name or key, saved = entry.saved,
                pieces = tonumber(entry.savedPieces) or 0 }
        end
    end
    table.sort(list, function(a, b)
        if a.saved ~= b.saved then
            return a.saved > b.saved
        end
        return tostring(a.name) < tostring(b.name)
    end)
    return list
end

-- A list of lines, one per item: { key, itemID, name, sold, net, gross, sales, returned, cancelled, posted, last,
-- rate (0-1 of what was settled, nil when nothing was), average (net of one piece) }
function FWR:GetSalesHistoryRows()
    local rows = {}
    local all = records()
    if not all then
        return rows
    end
    for key, entry in pairs(all) do
        if type(entry) == "table" then
            local settled = (entry.sold or 0) + (entry.returned or 0)
            local name = entry.name
            if (not name or name == "") and entry.id then
                name = itemName(entry.id)
            end
            rows[#rows + 1] = {
                key = key,
                itemID = entry.id,
                name = name or key,
                sold = entry.sold or 0,
                net = entry.net or 0,
                gross = entry.gross or 0,
                sales = entry.sales or 0,
                returned = entry.returned or 0,
                cancelled = entry.cancelled or 0,
                posted = entry.posted or 0,
                posts = entry.posts or 0,
                last = entry.last or 0,
                rate = settled > 0 and (entry.sold or 0) / settled or nil,
                average = (entry.sold or 0) > 0 and (entry.net or 0) / entry.sold or nil,
            }
        end
    end
    return rows
end

-- The average price at which this item was posted and sold (copper for one piece, before the 5% cut, up to the
-- next whole silver, because that is what a post is made of). It is made of the last sales; nil while there are
-- fewer than 3 sales or 20 pieces. Also returns the pieces and sales it is made of.
function FWR:GetMyAveragePrice(itemID)
    local all = records()
    local entry = all and itemID and all[tostring(itemID)]
    if type(entry) ~= "table" then
        return nil
    end

    -- the newest sales first, as many as the option says, and none older than 30 days
    local wanted = 10
    if self.GetSellTabSettings then
        wanted = self:GetSellTabSettings().averageSales or wanted
    end
    local oldest = time() - AVERAGE_MAX_AGE_DAYS * 86400

    local pieces, gross, sales = 0, 0, 0
    if type(entry.recent) == "table" and #entry.recent > 0 then
        for position = #entry.recent, 1, -1 do
            local sale = entry.recent[position]
            if sales >= wanted then
                break
            end
            if (tonumber(sale.t) or 0) >= oldest or (tonumber(sale.t) or 0) == 0 then
                pieces = pieces + (tonumber(sale.q) or 0)
                gross = gross + (tonumber(sale.g) or 0)
                sales = sales + 1
            end
        end
    elseif (tonumber(entry.last) or 0) >= oldest then
        -- sales saved before the last ones were kept: the totals of the item
        pieces, gross, sales = entry.sold or 0, entry.gross or 0, entry.sales or 0
    end

    if sales < AVERAGE_MIN_SALES or pieces < AVERAGE_MIN_PIECES or gross <= 0 then
        return nil, pieces, sales
    end
    return math.ceil(gross / pieces / 100) * 100, pieces, sales
end

function FWR:ClearSalesHistory()
    local realm = realmKey()
    if realm and type(FarmWiseDB) == "table" and type(FarmWiseDB._sales) == "table" then
        FarmWiseDB._sales[realm] = nil
    end
    if FWR.Emit then
        FWR:Emit("salesHistoryChanged")
    end
end
