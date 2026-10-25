local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- A small gold coin (the picture the game uses for what a vendor takes) in the top right corner of the items in the bags that
-- the FarmWise tab marked as "a vendor pays more than the Auction House". The tooltip of the item says it (see the
-- price tooltip). The mark stays while the item is in the bags, whether the Auction House is open or not, and after a
-- reload. When the item leaves the bags it is forgotten: it is marked again only when the tab looks at it again.
-- The pouch is a picture of our own, drawn over the item button: nothing is written into the game's button (it is
-- only read).

local COIN_ATLAS = "bags-junkcoin"              -- the gold coin the game puts on items a vendor takes
local COIN_ICON = "Interface/Icons/INV_Misc_Coin_01"
local COIN_SIZE = 18

local pouchOf = setmetatable({}, { __mode = "k" })   -- [item button] = its picture (kept here, not in the button)

local function marked()
    if type(FarmWiseDB) ~= "table" then
        return {}
    end
    if type(FarmWiseDB._vendorMarked) ~= "table" then
        FarmWiseDB._vendorMarked = {}
    end
    return FarmWiseDB._vendorMarked
end

local function bagFrames()
    local frames = {}
    if _G.ContainerFrameCombinedBags then
        frames[#frames + 1] = _G.ContainerFrameCombinedBags
    end
    for index = 1, 13 do
        local frame = _G["ContainerFrame" .. index]
        if frame then
            frames[#frames + 1] = frame
        end
    end
    return frames
end

local function pouchFor(button)
    local pouch = pouchOf[button]
    if not pouch then
        pouch = button:CreateTexture(nil, "OVERLAY", nil, 7)
        pouch:SetSize(COIN_SIZE, COIN_SIZE)
        pouch:SetPoint("CENTER", button, "TOPRIGHT", -6, -6)
        if not pcall(pouch.SetAtlas, pouch, COIN_ATLAS) then
            -- the gold coin of the game's icons, without the frame of the icon
            pouch:SetTexture(COIN_ICON)
            pouch:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        pouchOf[button] = pouch
    end
    return pouch
end

local function itemOfButton(button)
    local bag, slot
    pcall(function()
        bag = button.GetBagID and button:GetBagID() or button:GetParent():GetID()
        slot = button:GetID()
    end)
    if not bag or not slot then
        return nil
    end
    local info = GetContainerItemInfo(bag, slot)
    return info and tonumber(info.itemID) or nil
end

local function refreshPouches()
    local items = marked()
    local settings = FWR.GetSellTabSettings and FWR:GetSellTabSettings()
    if settings and settings.vendorCoin == false then
        items = {}      -- switched off in the options: no coin is drawn (the marks are kept)
    end
    for _, frame in ipairs(bagFrames()) do
        if frame:IsShown() then
            if frame.EnumerateValidItems then
                pcall(function()
                    for _, button in frame:EnumerateValidItems() do
                        local itemID = next(items) and itemOfButton(button)
                        if itemID and items[itemID] then
                            pouchFor(button):Show()
                        elseif pouchOf[button] then
                            pouchOf[button]:Hide()
                        end
                    end
                end)
            else
                -- this client's bag frames have no enumerator: the item buttons are named
                for slot = 1, (tonumber(frame.size) or 36) do
                    local button = _G[frame:GetName() .. "Item" .. slot]
                    if button then
                        local itemID = next(items) and itemOfButton(button)
                        if itemID and items[itemID] then
                            pouchFor(button):Show()
                        elseif pouchOf[button] then
                            pouchOf[button]:Hide()
                        end
                    end
                end
            end
        end
    end
end

-- what is in the bags now: { [itemID] = true }
local function itemsInBags()
    local present = {}
    local total = (tonumber(NUM_BAG_SLOTS) or 4) + (tonumber(NUM_REAGENTBAG_SLOTS) or 1)
    for bag = 0, total do
        for slot = 1, GetContainerNumSlots(bag) do
            local info = GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                present[tonumber(info.itemID)] = true
            end
        end
    end
    return present
end

-- Called by the Sell tab each time it has made its list: the items of the bags that stay out because a vendor pays
-- more. This is the mark: it replaces what was marked before.
function FWR:SetBagVendorCoins(items)
    local store = marked()
    for itemID in pairs(store) do
        store[itemID] = nil
    end
    for itemID in pairs(type(items) == "table" and items or {}) do
        store[itemID] = true
    end
    refreshPouches()
end

-- An item that is not in the bags any more (sold, posted, thrown away) loses its mark
local function forgetWhatLeft()
    local store = marked()
    if not next(store) then
        return
    end
    local present = itemsInBags()
    for itemID in pairs(store) do
        if not present[itemID] then
            store[itemID] = nil
        end
    end
end

local hooked = {}
local function hookBagFrames()
    for _, frame in ipairs(bagFrames()) do
        if not hooked[frame] and frame.HookScript then
            hooked[frame] = true
            frame:HookScript("OnShow", function()
                C_Timer.After(0, refreshPouches)
            end)
        end
    end
end

FWR:Subscribe("sellTabVendorCoinChanged", refreshPouches)

local events = CreateFrame("Frame")

-- Wrap RegisterEvent in pcall for WoW Forever compatibility
local function safeRegisterEvent(event)
    pcall(events.RegisterEvent, events, event)
end

safeRegisterEvent("BAG_UPDATE_DELAYED")
safeRegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event)
    hookBagFrames()
    if event == "BAG_UPDATE_DELAYED" then
        pcall(forgetWhatLeft)
    end
    C_Timer.After(0.2, refreshPouches)
end)
