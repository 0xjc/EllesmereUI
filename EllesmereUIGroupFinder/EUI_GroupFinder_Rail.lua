if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_GroupFinder_Rail.lua
--
--  The Dungeons & Raids rail entries (Dungeon Finder, Raid Finder, Premade
--  Groups) in the look of the panel's other buttons: a box (dark fill, the
--  theme border of the skinned buttons, their hover wash) inset from the
--  rail's sides by the side padding and BOX_H tall, centred in Blizzard's
--  button, with our art for the entry over the fill (media/rail, 772x300 =
--  4x the box; the picture on its right). Blizzard's icon and ring are faded
--  and its name moved to the box's left.
--
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local CM = EllesmereUI

local FFD = setmetatable({}, { __mode = "k" })
local ART = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\rail\\"
local BOX_H = 75      -- the box's height (the art's 300 px / 4); a little taller than Blizzard's 72
local NAME_X = 12    -- the name's inset from the box's left
-- Art per entry, by the name Blizzard gives it (the entries move around:
-- Scenarios, when shown, takes slot 2).
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

-- The host skin re-strips these buttons whenever Blizzard repaints them,
-- fading every texture on them it does not know (alpha 0), ours included: ours
-- go straight back to full alpha (our own textures, so hooking them is safe).
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

local PaintBorder   -- below

local function Style(btn, i)
    if not btn or (btn.IsForbidden and btn:IsForbidden()) or FFD[btn] then return end
    local d = {}
    FFD[btn] = d
    -- The drawn box: inset from the rail's sides by the search panel's side
    -- padding, as the Premade Groups category buttons (Questing ... Custom).
    -- A frame of ours carries the border (edges only, so it may sit above the
    -- icon and name); fill, art and hover wash are on the button, under them.
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
    -- A white border while hovered or selected (the theme's otherwise).
    d.index = i
    btn:HookScript("OnEnter", function(self) FFD[self].hovered = true; PaintBorder(self) end)
    btn:HookScript("OnLeave", function(self) FFD[self].hovered = nil; PaintBorder(self) end)
end

-- Selected = Blizzard's GroupFinderFrame.selectionIndex (set by
-- GroupFinderFrame_SelectGroupButton, post-hooked below).
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

-- The full-width backgrounds behind our box: Blizzard's own (bg,
-- "bluemenu-main") and the host skin's card ("Ui-Dialog-New-Background",
-- which the skin re-fades to its own alpha on theme changes). Held at alpha 0.
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
    -- The host skin's selected-entry wash hangs off that card (full width):
    -- moved onto our box instead (it is only ever anchored once).
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

-- The box (side padding, BOX_H centred), the entry's art, Blizzard's icon
-- and ring faded and its name at the box's left; re-done on every show.
local function Place(btn)
    local d = btn and FFD[btn]
    if not d then return end
    local pad = tonumber(ns.Cfg and ns.Cfg().padding) or 12
    local h = btn:GetHeight() or BOX_H
    local dy = (h - BOX_H) / 2   -- negative: the box reaches past the button
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

-- The window's bottom tab row (Dungeons & Raids / Player vs. Player /
-- Mythic+ Dungeons ...) flush with the window's left edge, tabs touching
-- (Blizzard starts it 19px in, the host skin leaves a pixel between tabs).
-- Shown tabs only; positions only, out of combat.
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
    -- Next frame: the host's skin lays the rail out on the same show.
    pve:HookScript("OnShow", function() C_Timer.After(0, StyleAll) end)
    if GroupFinderFrame_SelectGroupButton then
        hooksecurefunc("GroupFinderFrame_SelectGroupButton", function()
            for i = 1, 4 do PaintBorder(RailButton(i)) end
        end)
    end
    if pve:IsShown() then C_Timer.After(0, StyleAll) end
end

-- Started by the module's OnEnable while the module is on.
function ns.Rail_Enable() Hook() end
