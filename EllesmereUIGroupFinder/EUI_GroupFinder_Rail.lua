if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EUI_GroupFinder_Rail.lua: rail entries in the house button look with their
-- art, bottom tabs flush left.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local CM = EllesmereUI

local FFD = setmetatable({}, { __mode = "k" })
local ART = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\rail\\"
local BOX_H = 75  -- art is 300px / 4
local NAME_X = 12
-- Art per entry by name (entries move around, e.g. Scenarios takes slot 2).
local function ArtFor(btn)
    local name = btn.name and btn.name:GetText()
    if not name then return nil end
    if name == LOOKING_FOR_DUNGEON_PVEFRAME then return "dungeon-finder.png" end
    if name == RAID_FINDER_PVEFRAME then return "raid-finder.png" end
    if name == LFGLIST_NAME then return "premade-groups.png" end
    return nil
end

local function RailButton(i)
    local gf = _G.GroupFinderFrame
    return gf and (gf["groupButton" .. i] or _G["GroupFinderFrameGroupButton" .. i])
end

-- The skin fades unknown textures on these buttons, ours included, so put ours
-- back to full alpha.
local function Keep(tex)
    hooksecurefunc(tex, "SetAlpha", function(t, a)
        if a ~= 1 and not FFD[t] then
            FFD[t] = true
            t:SetAlpha(1)
            FFD[t] = nil
        end
    end)
    return tex
end

local PaintBorder

local function Style(btn, i)
    if not btn or (btn.IsForbidden and btn:IsForbidden()) or FFD[btn] then return end
    local d = {}
    FFD[btn] = d
    -- Drawn box, inset like the Premade Groups category buttons.
    d.box = CreateFrame("Frame", nil, btn)
    d.box:EnableMouse(false)
    d.bg = Keep(btn:CreateTexture(nil, "BACKGROUND", nil, 7))
    d.bg:SetAllPoints(d.box)
    d.bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
    d.art = Keep(btn:CreateTexture(nil, "BORDER", nil, -8))
    d.art:SetAllPoints(d.box)
    local S = ns.Skin and ns.Skin()
    if S and S.AddBorder then
        S.AddBorder(d.box)
    elseif CM.MakeBorder then
        local r, g, b, a = 0.2, 0.2, 0.2, 1
        if ns.ThemeBorder then r, g, b, a = ns.ThemeBorder() end
        CM.MakeBorder(d.box, r, g, b, a, CM.PanelPP)
    end
    d.hover = Keep(btn:CreateTexture(nil, "HIGHLIGHT"))
    d.hover:SetAllPoints(d.box)
    d.hover:SetColorTexture(1, 1, 1, 0.1)
    -- White border on hover or select.
    d.index = i
    btn:HookScript("OnEnter", function(self) FFD[self].hovered = true; PaintBorder(self) end)
    btn:HookScript("OnLeave", function(self) FFD[self].hovered = nil; PaintBorder(self) end)
end

-- Selected = GroupFinderFrame.selectionIndex.
PaintBorder = function(btn)
    local d = btn and FFD[btn]
    local PP = CM.PanelPP or CM.PP
    if not (d and d.box and PP and PP.SetBorderColor) then return end
    local gf = _G.GroupFinderFrame
    if d.hovered or (gf and gf.selectionIndex == d.index) then
        PP.SetBorderColor(d.box, 1, 1, 1, 1)
    else
        local r, g, b, a = 0.2, 0.2, 0.2, 1
        if ns.ThemeBorder then r, g, b, a = ns.ThemeBorder() end
        PP.SetBorderColor(d.box, r, g, b, a)
    end
end

-- Hide the backgrounds behind our box (Blizzard's and the skin's card).
local CARD_ATLAS = "Ui-Dialog-New-Background"
local function Hide(tex)
    if not tex or FFD[tex] ~= nil then return end
    FFD[tex] = false
    tex:SetAlpha(0)
    hooksecurefunc(tex, "SetAlpha", function(t, a)
        if a ~= 0 and FFD[t] == false then
            FFD[t] = 0
            t:SetAlpha(0)
            FFD[t] = false
        end
    end)
end
local function HideBackgrounds(btn)
    Hide(btn.bg)
    local regions = { btn:GetRegions() }
    local card
    for _, r in ipairs(regions) do
        if r.GetAtlas and r:GetAtlas() == CARD_ATLAS then
            card = r
            Hide(r)
        end
    end
    -- Move the skin's selected wash onto our box.
    local d = FFD[btn]
    if card and d and not d.selMoved then
        for _, r in ipairs(regions) do
            local _, rel = r:GetPoint(1)
            if rel == card and r ~= card then
                r:ClearAllPoints()
                r:SetAllPoints(d.box)
                d.selMoved = true
            end
        end
    end
end

-- Box, art and name; Blizzard's icon and ring faded. Redone every show.
local function Place(btn)
    local d = btn and FFD[btn]
    if not d then return end
    local pad = tonumber(ns.Cfg and ns.Cfg().padding) or 12
    local h = btn:GetHeight() or BOX_H
    local dy = (h - BOX_H) / 2  -- negative = box reaches past the button
    d.box:ClearAllPoints()
    d.box:SetPoint("TOPLEFT", btn, "TOPLEFT", pad, -dy)
    d.box:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -pad, dy)
    local art = ArtFor(btn)
    if art then d.art:SetTexture(ART .. art) end
    d.art:SetShown(art ~= nil)
    if art then
        Hide(btn.icon)
        Hide(btn.ring)
        local name = btn.name
        if name then
            name:ClearAllPoints()
            name:SetPoint("LEFT", d.box, "LEFT", NAME_X, 0)
            name:SetJustifyH("LEFT")
        end
    end
end

-- Bottom tab row flush left with no gaps.
local function AlignTabs()
    local pve = _G.PVEFrame
    if not pve or InCombatLockdown() then return end
    local prev
    for i = 1, 4 do
        local t = _G["PVEFrameTab" .. i]
        if t and t:IsShown() then
            t:ClearAllPoints()
            if prev then
                t:SetPoint("LEFT", prev, "RIGHT", 0, 0)
            else
                t:SetPoint("BOTTOMLEFT", pve, "BOTTOMLEFT", 0, -30)
            end
            prev = t
        end
    end
end

local function StyleAll()
    AlignTabs()
    for i = 1, 4 do
        local b = RailButton(i)
        Style(b, i)
        Place(b)
        if b then HideBackgrounds(b); PaintBorder(b) end
    end
end

local hooked
local function Hook()
    local pve = _G.PVEFrame
    if hooked or not pve then return end
    hooked = true
    -- Next frame, after the skin lays the rail out.
    pve:HookScript("OnShow", function() C_Timer.After(0, StyleAll) end)
    if GroupFinderFrame_SelectGroupButton then
        hooksecurefunc("GroupFinderFrame_SelectGroupButton", function()
            for i = 1, 4 do PaintBorder(RailButton(i)) end
        end)
    end
    if pve:IsShown() then C_Timer.After(0, StyleAll) end
end

function ns.Rail_Enable() Hook() end
