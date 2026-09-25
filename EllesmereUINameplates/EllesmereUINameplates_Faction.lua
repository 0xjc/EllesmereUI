-------------------------------------------------------------------------------
--  EllesmereUINameplates_Faction.lua
--  Faction badge (Horde/Alliance) on friendly nameplates. Enemy plates carry it
--  as a Core Positions slot element (NameplateFrame:UpdateFaction); friendly
--  plates have no slots, so the badge sits just left of the FriendlyFrame's
--  name (full plates only: name-only plates stay just the name). This matters
--  most for unflagged opposite-faction players, who cannot be attacked and so
--  get friendly plates. Which badge (if any) and whether it is dimmed come from
--  ns.NP_FactionBadge, shared with enemy plates; the badge shows while the
--  faction slot is set (not "None").
-------------------------------------------------------------------------------
local _, ns = ...

local badges = {} -- nameplate -> badge frame (reused with the nameplate)

local function GetBadge(nameplate)
    local b = badges[nameplate]
    if not b then
        b = CreateFrame("Frame", nil, nameplate)
        b:SetFrameStrata("MEDIUM")
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b:Hide()
        badges[nameplate] = b
    end
    return b
end

-- The full friendly plate's name text, or nil (name-only plates get no badge).
local function VisibleName(unit)
    local fp = ns.friendlyPlates and ns.friendlyPlates[unit]
    if fp and fp.name and fp.name:IsVisible() then return fp.name end
end

local function Refresh(unit)
    local nameplate = ns.pendingUnits and ns.pendingUnits[unit]
    if not nameplate then return end
    local b = badges[nameplate]
    -- Promoted to an enemy plate (duel, flag): that plate draws its own badge.
    local enemy = ns.plates and ns.plates[unit]
    local atlas, dim
    if not enemy then atlas, dim = ns.NP_FactionBadge(unit) end
    local fs = atlas and VisibleName(unit)
    if not fs then
        if b then b:Hide() end
        return
    end
    b = b or GetBadge(nameplate)
    local sz = ns.NP_GetFactionIconSize()
    b:SetSize(sz, sz)
    b:SetFrameLevel(nameplate:GetFrameLevel() + 5)
    b:ClearAllPoints()
    b:SetPoint("RIGHT", fs, "LEFT", -2, 0)
    EllesmereUI.SetFactionArt(b.tex, ns.NP_GetFactionStyle(), atlas)
    b.tex:SetDesaturated(dim)
    b.tex:SetAlpha(dim and 0.6 or 1)
    b:Show()
end

local function HideFor(nameplate)
    local b = nameplate and badges[nameplate]
    if b then b:Hide() end
end

local ev = CreateFrame("Frame")

-- Events only while the faction slot is in use: UNIT_FLAGS is a global firehose.
local function Arm()
    ev:UnregisterAllEvents()
    pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
    if not (ns.NP_GetFactionSlot and ns.NP_GetFactionSlot() ~= "none") then return end
    -- pcall'd: on the Forever beta an unknown event name throws and aborts the file.
    for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_FACTION", "UNIT_FLAGS" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
end

-- Every visible friendly plate; the options page calls this after a settings change.
function ns.NP_RefreshFriendlyFaction()
    Arm()
    for _, b in pairs(badges) do b:Hide() end
    if not ns.pendingUnits then return end
    for unit in pairs(ns.pendingUnits) do Refresh(unit) end
end

ev:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        -- The profile is loaded by now: arm for the saved slot and draw.
        C_Timer.After(0, ns.NP_RefreshFriendlyFaction)
        return
    end
    if not unit then return end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        HideFor(C_NamePlate.GetNamePlateForUnit(unit))
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        -- After the main file has sorted the unit into enemy or friendly and
        -- built (or suppressed) the name this anchors to.
        C_Timer.After(0, function() Refresh(unit) end)
        return
    end
    -- Only nameplate units have a badge; UNIT_FLAGS also fires for party, target...
    if not unit:find("^nameplate") then return end
    -- UNIT_FACTION / UNIT_FLAGS: faction, PvP flag or attackability changed. One
    -- frame later, so the main file's own watchers have already moved the unit
    -- between friendly and enemy plates (duel start/end) before this looks.
    C_Timer.After(0, function()
        if ns.pendingUnits and ns.pendingUnits[unit] then
            Refresh(unit)
        else
            HideFor(C_NamePlate.GetNamePlateForUnit(unit))
        end
    end)
end)

Arm()
