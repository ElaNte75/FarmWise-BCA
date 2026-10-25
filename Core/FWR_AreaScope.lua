local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- Where the player is, as far as the sub-zone goes. In the open world the name of the sub-zone is used (so the
-- Advisor can tell one place from the next). Inside something that is entered through a portal and left when it is
-- done - a dungeon, a raid, a delve and the other scenarios, a battleground, an arena - the sub-zone is left out:
-- there one cannot choose a part of it, the whole place is one area, and what is looted is counted for all of it.
function FWR:IsInWholeAreaInstance()
    if type(IsInInstance) ~= "function" then
        return false
    end
    local inInstance, kind = IsInInstance()
    return inInstance == true and kind ~= nil and kind ~= "none"
end

-- Gathering (herbalism, mining, fishing, skinning) is counted for the whole zone, not for the sub-zone you happen
-- to stand in: the next node is in the next sub-zone, and what is wanted is the zone where most is gathered. From
-- the moment a gathering action starts until a while after the last one, the area is the whole zone (the sub-zone
-- is left out, as in an instance). The session of that area is not reset by walking into another sub-zone.
local GATHER_WINDOW_SECONDS = 300
local gatheringUntil = 0

function FWR:IsGatheringArea()
    local tracking = self.Settings and self.Settings.tracking
    if type(tracking) == "table" and tracking.gatheringWholeZone == false then
        return false
    end
    return type(GetTime) == "function" and GetTime() < gatheringUntil
end

-- Called when a gathering action starts or succeeds (the idle system knows when).
function FWR:NoteGatheringActivity()
    -- (Options > Tracking: "Count gathering for the whole zone", on unless it was turned off)
    local tracking = self.Settings and self.Settings.tracking
    if type(tracking) == "table" and tracking.gatheringWholeZone == false then
        return
    end
    if type(GetTime) == "function" then
        gatheringUntil = GetTime() + GATHER_WINDOW_SECONDS
    end
end

function FWR:GetAreaSubZoneText()
    if self:IsInWholeAreaInstance() or self:IsGatheringArea() then
        return ""
    end
    return type(GetSubZoneText) == "function" and GetSubZoneText() or ""
end

-- When the window of the gathering is over, the area goes back to the sub-zone (the places are looked at again)
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(5, function()
        if gatheringUntil > 0 and not FWR:IsGatheringArea() then
            gatheringUntil = 0
            if FWR.RefreshIdleZoneInfo then
                FWR:RefreshIdleZoneInfo()
            end
        end
    end)
end
