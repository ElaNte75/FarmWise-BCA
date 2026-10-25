local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- What is going on with my auctions, for the "Actions" page of the FarmWise tab: one line for each
-- post, kept until the gold (or the returned items) is taken from the mailbox.
--
-- Burning Crusade Anniversary version. The classic owner list has no auction ids: a post is known by
-- its signature (itemID + stack size + unit price). A stack sells whole or not at all here - there are
-- no partial sales. Time left comes as a coarse bucket from GetAuctionItemTimeLeft (1 short <30 min,
-- 2 medium <2 h, 3 long <12 h, 4 very long <=48 h), so an exact end time is only known when the post
-- was made by the addon (its chosen duration is remembered).
--
-- States:
--   active    -> still in the Auction House
--   sold      -> sold, the gold is not taken yet
--   ended     -> not in the Auction House any more and the end is not known (it was sold while I was
--                away, or it ran out): the mail tells, when the mailbox is opened
--   expired   -> ran out, the items are in the mail (known from the mail)
--   cancelled -> taken back by me, the items are in the mail
-- A line goes away when the History counts its mail as taken (the "auctionUnitCollected" event).

local SOLD = 1                                 -- saleStatus of GetAuctionItemInfo("owner")
local KEEP_SECONDS = 31 * 86400                -- a mail stays 30 days in the mailbox
local MAIL_LATE_SECONDS = 90 * 60              -- a sale mail comes within the hour
local CANCEL_KEEP_SECONDS = 600                -- a cancelled post is hidden at once, forgotten later
local EXPIRY_SLACK = 120                       -- seconds: a post that vanishes this close to its end expired

-- GetAuctionItemTimeLeft("owner", index) answer -> its upper bound in seconds (the bucket means the
-- time left is less than this but more than the previous bucket's bound)
local TIME_LEFT_SECONDS = { 30 * 60, 2 * 3600, 12 * 3600, 48 * 3600 }

local ahOpen = false                          -- the Auction House window is open
local loaded = false                           -- the list of the game is known (since it opened)
local sessionStart = 0                         -- when this visit to the Auction House began

local function owner()
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    return (UnitName and UnitName("player") or "?") .. "-" .. realm
end

local migrated = false

local function list()
    if type(FarmWiseDB) ~= "table" then
        return nil
    end
    if type(FarmWiseDB._actions) ~= "table" then
        FarmWiseDB._actions = {}
    end
    local key = owner()
    if type(FarmWiseDB._actions[key]) ~= "table" then
        FarmWiseDB._actions[key] = {}
    end
    if not migrated then
        migrated = true
        for _, record in ipairs(FarmWiseDB._actions[key]) do
            if record.state == "expired" and record.soldKnown == false then
                record.state = "ended"
            end
        end
    end
    return FarmWiseDB._actions[key]
end

-- The signature a post is known by on this client (there is no auction id).
local function signature(itemID, qty, unit)
    return tostring(itemID) .. "|" .. tostring(qty) .. "|" .. tostring(unit)
end

local function signatureOf(record)
    return signature(record.itemID, record.qty, record.unit)
end

-- Reads the game's "owner" list: { sig, itemID, qty, unit, sold, leftBucket, index }.
local function readOwned()
    local owned = {}
    if type(GetNumAuctionItems) ~= "function" or type(GetAuctionItemInfo) ~= "function" then
        return owned
    end

    local count = GetNumAuctionItems("owner") or 0
    for index = 1, count do
        local name, _, qty, _, _, _, _, _, _, buyoutPrice, _, _, _, _, _, saleStatus, itemID =
            GetAuctionItemInfo("owner", index)
        itemID = tonumber(itemID)
        qty = tonumber(qty) or 0
        buyoutPrice = tonumber(buyoutPrice) or 0
        local sold = saleStatus == SOLD
        -- (a sold line can report count 0: keep a sane stack size anyway - a post sold is the whole post)
        if itemID and (qty > 0 or sold) and buyoutPrice > 0 then
            local unit = qty > 0 and math.floor(buyoutPrice / qty + 0.5) or buyoutPrice
            owned[#owned + 1] = {
                index = index,
                itemID = itemID,
                name = name,
                qty = math.max(qty, 1),
                unit = unit,
                sold = sold,
                leftBucket = GetAuctionItemTimeLeft and tonumber(GetAuctionItemTimeLeft("owner", index)) or nil,
            }
        end
    end
    return owned
end

local function changed()
    if FWR.Emit then
        FWR:Emit("actionsChanged")
    end
end

-- compares the game's list with what is remembered. Two posts with the same signature cannot be told
-- apart: they are paired in order (it does not matter which line is which - they are the same post).
local function sync()
    local records = list()
    if not records or not loaded then
        return
    end
    local now = time()

    -- group active-ish records by signature
    local bySig = {}
    for _, record in ipairs(records) do
        local sig = signatureOf(record)
        bySig[sig] = bySig[sig] or {}
        bySig[sig][#bySig[sig] + 1] = record
    end

    local seenGame = {}
    for _, info in ipairs(readOwned()) do
        local qty = info.qty
        local sig = signature(info.itemID, qty, info.unit)
        seenGame[sig] = (seenGame[sig] or 0) + 1

        -- the first not-yet-matched record of this signature
        local record
        if bySig[sig] then
            for _, candidate in ipairs(bySig[sig]) do
                if not candidate.__seen then
                    record = candidate
                    break
                end
            end
        end
        if not record then
            record = { itemID = info.itemID, qty = qty, unit = info.unit, since = now, name = info.name,
                       index = info.index }
            records[#records + 1] = record
            bySig[sig] = bySig[sig] or {}
            bySig[sig][#bySig[sig] + 1] = record
        end
        record.__seen = true
        record.index = info.index
        record.name = record.name or info.name

        if record.cancelling or record.state == "cancelled" then
            if record.state ~= "cancelled" then
                record.since = now
            end
            record.state = "cancelled"
            record.expires = nil
        elseif info.sold then
            if record.state ~= "sold" then
                record.since = now
                record.soldKnown = true
            end
            record.state = "sold"
            record.expires = nil
        else
            record.state = "active"
            record.soldAt = nil
            -- an expiry estimate from the bucket (upper bound), unless the duration is known
            if record.expires == nil and info.leftBucket and TIME_LEFT_SECONDS[info.leftBucket] then
                record.expires = now + TIME_LEFT_SECONDS[info.leftBucket]
            end
        end
    end

    -- a post the game does not list any more
    for _, record in ipairs(records) do
        if record.state == "active" or record.state == nil then
            if not record.__seen then
                if record.cancelling then
                    record.state = "cancelled"
                elseif record.expires and now >= record.expires - EXPIRY_SLACK then
                    if record.seen == sessionStart then
                        record.state = "expired"
                    else
                        record.state = "ended"
                    end
                else
                    record.state = "sold"
                    record.soldKnown = record.seen == sessionStart
                end
                record.since = now
                record.index = nil
            else
                record.seen = sessionStart
            end
        end
    end

    for _, record in ipairs(records) do
        record.__seen = nil
    end

    for position = #records, 1, -1 do
        local record = records[position]
        if record.state == "expired" or (record.state == "cancelled" and now - (record.since or now) > CANCEL_KEEP_SECONDS)
            or (record.state ~= "active" and now - (record.since or now) > KEEP_SECONDS) then
            table.remove(records, position)
        end
    end
    changed()
end

-- What a mail says about a post, and in which states a line may be that post, the best guess first.
local SEARCH_ORDER = {
    sale = { "sold", "ended", "expired", "cancelled" },
    expired = { "expired", "ended", "sold" },
    cancelled = { "cancelled", "ended", "sold" },
}
local MAIL_STATE = { sale = "sold", expired = "expired", cancelled = "cancelled" }

local function sameItem(record, unit)
    if unit.itemID then
        return record.itemID == unit.itemID
    end
    if not unit.name then
        return false
    end
    local name = record.name or (GetItemInfo(record.itemID))
    return name ~= nil and string.lower(name) == string.lower(unit.name)
end

local function endOf(record)
    return record.expires or record.since or 0
end

-- Takes `left` pieces from the lines in this state that are of the item of the unit: a line with
-- exactly that amount first, else the oldest lines one after the other. Returns what is still left.
local function takeFrom(records, state, unit, left, only)
    local candidates = {}
    for _, record in ipairs(records) do
        if record.state == state and sameItem(record, unit) and (not only or only(record)) then
            candidates[#candidates + 1] = record
        end
    end
    table.sort(candidates, function(a, b)
        return endOf(a) < endOf(b)
    end)

    local function remove(record)
        for position, other in ipairs(records) do
            if other == record then
                table.remove(records, position)
                return
            end
        end
    end

    for _, record in ipairs(candidates) do
        if record.qty == left then
            remove(record)
            return 0
        end
    end
    for _, record in ipairs(candidates) do
        if left <= 0 then
            break
        end
        if record.qty > left then
            record.qty = record.qty - left
            left = 0
        else
            left = left - record.qty
            remove(record)
        end
    end
    return left
end

local function collected(unit)
    local records = list()
    local order = type(unit) == "table" and SEARCH_ORDER[unit.kind]
    if not records or not order then
        return
    end
    local left = tonumber(unit.count) or 0
    if left <= 0 then
        return
    end

    for _, state in ipairs(order) do
        left = takeFrom(records, state, unit, left)
        if left <= 0 then
            changed()
            return
        end
    end

    if (unit.kind == "sale" or unit.kind == "expired") and not ahOpen then
        local now = time()
        left = takeFrom(records, "active", unit, left, function(record)
            return unit.kind == "sale" or (record.expires and record.expires <= now + EXPIRY_SLACK)
        end)
    end
    changed()
end

-- The mailbox was looked at: the mails that are in it tell how the posts ended.
local function mailSeen(units, inboxLoaded)
    local records = list()
    if not records or type(units) ~= "table" then
        return
    end
    local used = {}
    local unitUsed = {}
    local touched = false
    for _, unit in ipairs(units) do
        local state = MAIL_STATE[unit.kind]
        local count = tonumber(unit.count)
        if state and count and count > 0 then
            local found
            for index, record in ipairs(records) do
                if not used[index] and record.state == state and record.qty == count and sameItem(record, unit) then
                    found = index
                    break
                end
            end
            if not found then
                for _, from in ipairs(SEARCH_ORDER[unit.kind]) do
                    if from ~= state then
                        for index, record in ipairs(records) do
                            if not used[index] and record.state == from and record.qty == count
                                and sameItem(record, unit)
                                and not (from == "sold" and record.soldKnown == true) then
                                record.state = state
                                found = index
                                touched = true
                                break
                            end
                        end
                    end
                    if found then
                        break
                    end
                end
            end
            if found then
                used[found] = true
                unitUsed[unit] = true
            elseif unit.kind == "sale" then
                local candidates = {}
                for index, record in ipairs(records) do
                    if not used[index] and record.state == "ended" and sameItem(record, unit) then
                        candidates[#candidates + 1] = { index = index, record = record }
                    end
                end
                table.sort(candidates, function(x, y)
                    return endOf(x.record) < endOf(y.record)
                end)
                local sum, taken = 0, {}
                for _, candidate in ipairs(candidates) do
                    if sum + candidate.record.qty <= count then
                        sum = sum + candidate.record.qty
                        taken[#taken + 1] = candidate
                    end
                    if sum == count then
                        break
                    end
                end
                if sum == count and #taken > 1 then
                    for _, candidate in ipairs(taken) do
                        candidate.record.state = state
                        used[candidate.index] = true
                    end
                    unitUsed[unit] = true
                    touched = true
                end
            end
        end
    end
    for index, record in ipairs(records) do
        if record.state == "sold" and not used[index] then
            local remaining = record.qty
            for _, unit in ipairs(units) do
                local count = tonumber(unit.count)
                if unit.kind == "sale" and not unitUsed[unit] and count and count > 0 and count <= remaining
                    and sameItem(record, unit) then
                    remaining = remaining - count
                    unitUsed[unit] = true
                    used[index] = true
                end
            end
        end
    end
    local count, total = 0, 0
    if GetInboxNumItems then
        count, total = GetInboxNumItems()
    end
    if inboxLoaded == true and tonumber(total) == tonumber(count) then
        local now = time()
        for position = #records, 1, -1 do
            local record = records[position]
            local ended = math.min(record.since or now, record.expires or now)
            if record.state ~= "active" and not used[position] and now - ended > MAIL_LATE_SECONDS then
                table.remove(records, position)
                touched = true
            end
        end
    end
    for position = #records, 1, -1 do
        if records[position].state == "expired" then
            table.remove(records, position)
            touched = true
        end
    end
    if touched then
        changed()
    end
end

-- The game gives the name of an item only when it has it loaded: it is asked for (a plain
-- GetItemInfo call does that on this client), and the page is made again when it comes.
local askedFor = {}

local function nameOf(record)
    local name = GetItemInfo(record.itemID)
    if name then
        record.name = name
        return name
    end
    if record.itemID and not askedFor[record.itemID] then
        askedFor[record.itemID] = true
        pcall(GetItemInfo, record.itemID)   -- asking is what loads it
    end
    return record.name
end

-- When a post was sold, as far as the ledger knows, for the History.
function FWR:GetActionSaleMoment(itemID, name, count)
    local records = list()
    if not records then
        return nil
    end
    local now = time()
    local wanted = { itemID = itemID, name = name }
    local bestMoment
    for _, record in ipairs(records) do
        if sameItem(record, wanted) and record.qty >= (count or 0) then
            local moment
            if record.state == "sold" and record.soldKnown == true then
                moment = record.since
            elseif record.state == "ended" and record.expires then
                moment = math.min(record.expires, now)
            end
            if moment and (not bestMoment or moment < bestMoment) then
                bestMoment = moment
            end
        end
    end
    return bestMoment
end

-- The lines to show for this character: { sig, index, itemID, name, qty, unit, net, state, left }.
function FWR:GetActionRows()
    local records = list() or {}
    local now = time()
    local cut = tonumber(FWR.AUCTION_HOUSE_CUT) or 0.05
    local rows = {}
    for _, record in ipairs(records) do
        if record.state ~= "cancelled" and record.state ~= "expired" then
            local name = nameOf(record)
            rows[#rows + 1] = {
                id = signatureOf(record),
                index = record.index,
                itemID = record.itemID,
                name = name or ("item " .. tostring(record.itemID)),
                qty = record.qty,
                unit = record.unit,
                net = math.floor((record.unit or 0) * record.qty * (1 - cut)),
                state = record.state or "active",
                left = record.expires and math.max(0, record.expires - now) or nil,
                since = record.since or 0,
            }
        end
    end
    return rows
end

-- The game's owner list refreshes by itself while the Auction House is open; this just nudges a sync.
function FWR:RefreshOwnedAuctions()
    if ahOpen then
        pcall(sync)
    end
end

-- Lets go of the lines of the posts that were taken back (their items stay in the mailbox).
function FWR:ClearCancelledPosts()
    local records = list()
    if not records then
        return
    end
    for position = #records, 1, -1 do
        if records[position].state == "cancelled" then
            table.remove(records, position)
        end
    end
    changed()
end

-- Takes an active post back by its signature (the Auction House must be open). The game answers with
-- the items in the mail.
function FWR:CancelPost(sig)
    if not ahOpen or type(CancelAuction) ~= "function" then
        return
    end
    local itemID, qty, unit = tostring(sig):match("^(%d+)|(%d+)|(%d+)$")
    if not itemID then
        return
    end
    for _, info in ipairs(readOwned()) do
        if not info.sold and signature(info.itemID, info.qty, info.unit) == sig then
            CancelAuction(info.index)
            return
        end
    end
end

------------------------------------------------------------
-- Events
------------------------------------------------------------

FWR:Subscribe("auctionUnitCollected", collected)
FWR:Subscribe("auctionMailSeen", mailSeen)

-- A post taken back: the game lists it as "sold" for a short while, so the cancel is remembered and
-- the sync keeps it "cancelled".
if type(CancelAuction) == "function" then
    pcall(hooksecurefunc, "CancelAuction", function(index)
        local info
        for _, entry in ipairs(readOwned()) do
            if entry.index == index then
                info = entry
                break
            end
        end
        if not info then
            return
        end
        local sig = signature(info.itemID, info.qty, info.unit)
        for _, record in ipairs(list() or {}) do
            if signatureOf(record) == sig then
                record.cancelling = true
            end
        end
    end)
end

-- The game tells in the chat when a post is sold or runs out, but its list of my auctions does not
-- always change by itself: the message is the signal to ask for the list again.
local function patternOf(message)
    if type(message) ~= "string" then
        return nil
    end
    return "^" .. message:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"):gsub("%%%%s", "(.+)") .. "$"
end
local CHAT_PATTERNS = {
    { pattern = patternOf(_G.ERR_AUCTION_SOLD_S), kind = "sold" },
    { pattern = patternOf(_G.ERR_AUCTION_EXPIRED_S), kind = "expired" },
    { pattern = patternOf(_G.ERR_AUCTION_REMOVED) },
}

local function chatNameOf(text)
    if type(text) ~= "string" then
        return nil
    end
    return string.lower(text:match("|h%[(.-)%]|h") or text:match("^%[(.-)%]$") or text)
end

local function chatSeen(kind, text)
    local records = list()
    local wanted = chatNameOf(text)
    if not records or not wanted then
        return
    end
    local pick
    for _, record in ipairs(records) do
        if record.state == "active" then
            local name = record.name or (GetItemInfo(record.itemID))
            if name and string.lower(name) == wanted
                and (not pick or (record.expires or math.huge) < (pick.expires or math.huge)) then
                pick = record
            end
        end
    end
    if not pick then
        return
    end
    local now = time()
    if kind == "sold" then
        pick.state = "sold"
        pick.since = now
        pick.soldKnown = true
        pick.soldAt = now
        pick.expires = nil
    else
        for position, record in ipairs(records) do
            if record == pick then
                table.remove(records, position)
                break
            end
        end
    end
    changed()
end

local function askAgainSoon()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function()
            FWR:RefreshOwnedAuctions()
        end)
    end
end

local frame = CreateFrame("Frame")
for _, name in ipairs({ "AUCTION_OWNED_LIST_UPDATE", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "GET_ITEM_INFO_RECEIVED", "CHAT_MSG_SYSTEM" }) do
    pcall(frame.RegisterEvent, frame, name)
end
frame:SetScript("OnEvent", function(_, event, arg)
    if event == "CHAT_MSG_SYSTEM" then
        local text = arg
        if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
            return
        end
        for _, entry in ipairs(CHAT_PATTERNS) do
            if entry.pattern then
                local captured = text:match(entry.pattern)
                if captured then
                    if entry.kind and not ahOpen then
                        pcall(chatSeen, entry.kind, captured)
                    end
                    askAgainSoon()
                    return
                end
            end
        end
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        local itemID = arg
        if itemID and askedFor[itemID] == true then
            askedFor[itemID] = "answered"
            changed()
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        ahOpen = true
        loaded = false
        sessionStart = time()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahOpen = false
        loaded = false
    else
        -- AUCTION_OWNED_LIST_UPDATE: the game's list changed, it is the truth
        loaded = true
        pcall(sync)
    end
end)
