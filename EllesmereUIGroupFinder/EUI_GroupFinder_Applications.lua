if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_GroupFinder_Applications.lua
--
--  Group Finder application counter (the idea of the LFGDeclineCounter addon,
--  rebuilt): every application you send and how it ended -- invited and
--  accepted, declined (incl. full / timed out), delisted, or cancelled by you
--  -- counted for the session, the character and the account.
--
--  Shown at the top of the Dungeons & Raids left rail, in the free space
--  above its entries (see Card below): a title and a stacked outcome bar with
--  each count inside its segment. Its settings are at the end of the Premade
--  Groups settings page (the search panel's cog opens it): scope, texture,
--  font size, which outcomes show.
--
--  Only Dungeons category applications (Mythic+ and other dungeon groups)
--  are counted; raids, delves and the rest are left out.
--
--  Settings: the profile's apps table. Counts: EllesmereUIGroupFinderAppsDB
--  (account-wide, outside profiles).
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local CM = EllesmereUI

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function PlainString(v)
    if type(v) == "string" and not IsSecret(v) and v ~= "" then return v end
end
-- The realm form UnitFullName returns: no spaces or hyphens.
local function NormRealm(realm)
    realm = PlainString(realm)
    if not realm then return nil end
    realm = realm:gsub("[%s%-]", "")
    return realm ~= "" and realm or nil
end
local function MyRealm()
    return NormRealm(GetNormalizedRealmName and GetNormalizedRealmName()) or NormRealm(GetRealmName()) or "?"
end

local KEYS = { "applied", "accepted", "declined", "delisted", "cancelled", "invited" }
local SESSION_GAP = 300   -- a relog within 5 minutes keeps the session

-- newStatus -> counter (LFG_LIST_APPLICATION_STATUS_UPDATED)
local STATUS_KEY = {
    applied = "applied",
    declined = "declined", declined_full = "declined", timedout = "declined",
    declined_delisted = "delisted",
    cancelled = "cancelled",
    invited = "invited",
    inviteaccepted = "accepted",
}

-- Bar segments, in order. Invites are still counted but not shown: every
-- invite is taken as accepted, so Accepted covers them.
local SEGMENTS = {
    { key = "accepted",  label = "Accepted",  cfg = "showAccepted",  r = 0.35, g = 0.85, b = 0.40 },
    { key = "declined",  label = "Declined",  cfg = "showDeclined",  r = 0.95, g = 0.30, b = 0.30 },
    { key = "delisted",  label = "Delisted",  cfg = "showDelisted",  r = 1.00, g = 0.60, b = 0.20 },
    { key = "cancelled", label = "Cancelled", cfg = "showCancelled", r = 0.55, g = 0.55, b = 0.55 },
}
local SCOPES = { "session", "character", "account" }
local SCOPE_LABEL = { session = "Session", character = "Character", account = "Account" }

local barTextures = CM.BuildBarTextureTables and CM.BuildBarTextureTables() or {}

local function Cfg() return ns.AppsCfg() end

local function Get(key, default)
    local c = Cfg()
    local v = c and c[key]
    if v == nil then return default end
    return v
end

local function On() return Get("enabled", true) ~= false end

local function Blank()
    local t = {}
    for _, k in ipairs(KEYS) do t[k] = 0 end
    return t
end

local function Fill(t)
    for _, k in ipairs(KEYS) do t[k] = tonumber(t[k]) or 0 end
    return t
end

local myKey
local function Store()
    local a = ns.AppCountsStore()
    if type(a.account) ~= "table" then a.account = Blank() end
    if type(a.chars) ~= "table" then a.chars = {} end
    if type(a.session) ~= "table" then a.session = Blank() end
    return a
end

local function Counts(scope)
    local a = Store()
    if scope == "account" then return Fill(a.account) end
    if scope == "session" then return Fill(a.session) end
    if not myKey then return Blank() end
    a.chars[myKey] = Fill(a.chars[myKey] or Blank())
    return a.chars[myKey]
end

-------------------------------------------------------------------------------
--  Card
--  At the top of the Dungeons & Raids left rail, above its entries: the
--  "Applications" title (in the Premade Groups title's yellow, which takes
--  the same size), level with the Premade Groups search row, and below
--  it a box as tall as that panel's second row (cog, reset, dungeons) and
--  level with it, spanning the rail less a margin each side. The box holds
--  the stacked outcome bar; each outcome's count sits centred in its own
--  segment, in white (left out when the segment is too narrow for it).
-------------------------------------------------------------------------------
local card
local TITLE_SIZE = 12   -- the title (and the Premade Groups title); the Font Size setting is the counts' only

local function FontPath() return (CM.GetFontPath and CM.GetFontPath()) or STANDARD_TEXT_FONT end

local function Scope()
    local s = Get("scope", "character")
    return SCOPE_LABEL[s] and s or "character"
end

-- The counts use the search box's font and size (Search.lua sets it from
-- the panel's Back button); the host's font at 12 until it is there.
local function CountFont()
    local sb = _G.LFGListFrame and _G.LFGListFrame.SearchPanel and _G.LFGListFrame.SearchPanel.SearchBox
    local path, size
    if type(sb) == "table" and sb.GetFont then path, size = sb:GetFont() end
    if path and size and size > 0 then return path, size end
    return FontPath(), 12
end

local function ShowTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("M+ Applications (Dungeons only)")
    for _, scope in ipairs(SCOPES) do
        local c = Counts(scope)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(SCOPE_LABEL[scope], ("%d applied"):format(c.applied), 1, 0.82, 0.3, 1, 1, 1)
        for _, seg in ipairs(SEGMENTS) do
            GameTooltip:AddDoubleLine("   " .. seg.label, tostring(c[seg.key]), seg.r, seg.g, seg.b, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

-- Where the Premade Groups search rows sit (Search.lua), in PVEFrame's
-- coordinates: row 1's centre, row 2's top and height. The rail column is
-- Blizzard's left inset (PVEFrame.Inset); sideways it matches the rail
-- entries' boxes (Rail.lua: the first entry's rect less the side padding).
local function Place()
    local pve = _G.PVEFrame
    local inset = pve and pve.Inset
    if not (card and inset) then return end
    local r1, r2, size = -42, -57, 28
    if ns.Search_Rows then r1, r2, size = ns.Search_Rows() end
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    local st, pt = sp and sp:GetTop(), pve:GetTop()
    local dy = (st and pt) and (st - pt) or 0
    local ref = _G.GroupFinderFrame and _G.GroupFinderFrame.groupButton1
    if type(ref) ~= "table" or not ref.GetLeft then ref = inset end
    local il, ir, pl = ref:GetLeft(), ref:GetRight(), pve:GetLeft()
    if not (il and ir and pl) then il, ir = inset:GetLeft(), inset:GetRight() end
    if not (il and ir and pl) then return end
    local pad = tonumber(ns.Cfg and ns.Cfg().padding) or 12
    local x1, x2 = il - pl + pad, ir - pl - pad
    card.box:ClearAllPoints()
    card.box:SetPoint("TOPLEFT", pve, "TOPLEFT", x1, dy + r2)
    card.box:SetPoint("TOPRIGHT", pve, "TOPLEFT", x2, dy + r2)
    card.box:SetHeight(size)
    card.title:ClearAllPoints()
    card.title:SetPoint("LEFT", pve, "TOPLEFT", x1, dy + r1)
end

-- Fonts and sizes from the settings.
local function Layout()
    if not card then return end
    local path = FontPath()
    local npath, nsize = CountFont()
    card.title:SetFont(path, TITLE_SIZE, "")
    -- The Premade Groups screen's title ("Premade Groups", top of its
    -- category list) at the same size, and its yellow for ours.
    local lbl = _G.LFGListFrame and _G.LFGListFrame.CategorySelection and _G.LFGListFrame.CategorySelection.Label
    if lbl and lbl.GetFont then
        local lpath, lsize, lflags = lbl:GetFont()
        if not card.lblSize then card.lblSize = lsize end
        if lpath then lbl:SetFont(lpath, TITLE_SIZE, lflags) end
        local r, g, b = lbl:GetTextColor()
        if r then card.title:SetTextColor(r, g, b, 1) end
    end
    local texPath = CM.ResolveTexturePath and CM.ResolveTexturePath(barTextures, Get("texture", "none"))
    for i, seg in ipairs(SEGMENTS) do
        local t = card.segs[i]
        if texPath then
            t:SetTexture(texPath)
            t:SetVertexColor(seg.r, seg.g, seg.b, 1)
        else
            t:SetColorTexture(seg.r, seg.g, seg.b, 1)
            t:SetVertexColor(1, 1, 1, 1)
            t:SetTexCoord(0, 1, 0, 1)
        end
        card.nums[i]:SetFont(npath, nsize, "OUTLINE")
    end
    Place()
end

local function Refresh()
    if not (card and card:IsShown()) then return end
    local c = Counts(Scope())
    -- Bar share per shown outcome. The bar is
    -- split between the shown outcomes only, so it always fills.
    local shares, total = {}, 0
    for i, seg in ipairs(SEGMENTS) do
        local v = c[seg.key]
        shares[i] = Get(seg.cfg, true) and v or 0
        total = total + shares[i]
    end
    local bar = card.bar
    local w = bar:GetWidth() or 0
    local textured = CM.ResolveTexturePath and CM.ResolveTexturePath(barTextures, Get("texture", "none"))
    local x = 0
    for i, seg in ipairs(SEGMENTS) do
        local tex, num = card.segs[i], card.nums[i]
        local sw = (total > 0) and (w * shares[i] / total) or 0
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
        tex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
        tex:SetWidth(math.max(sw, 0.01))
        -- Each segment shows its own slice of the texture, so a textured bar
        -- reads as one continuous bar split by colour.
        if textured and w > 0 then tex:SetTexCoord(x / w, (x + sw) / w, 0, 1) end
        tex:SetShown(sw >= 0.5)
        -- The count, centred in its segment (the shown count, as on the bar).
        num:SetText(tostring(c[seg.key]))
        num:ClearAllPoints()
        num:SetPoint("CENTER", tex, "CENTER", 0, 0)
        num:SetShown(sw >= 0.5 and (num:GetStringWidth() or 0) + 4 <= sw)
        x = x + sw
    end
end

local BuildCardInto
local function BuildCard()
    if card then return card end
    local ok, built = pcall(BuildCardInto)
    if ok and built then card = built end
    if not ok then geterrorhandler()(built) end
    return card
end

BuildCardInto = function()
    local host = _G.GroupFinderFrame
    local pve = _G.PVEFrame
    if not (host and pve and pve.Inset) then return nil end

    -- Built into a local and published at the end, so a failure part-way can
    -- never leave a half-built card for Layout/Refresh to trip over. Every
    -- FontString gets a font before any SetText (unset fonts error). The
    -- pieces are placed against PVEFrame (Place); the card frame only holds
    -- them, so they show and hide with the Dungeons & Raids tab.
    local card = CreateFrame("Frame", nil, host)
    card:SetAllPoints(host)
    card:SetFrameLevel(host:GetFrameLevel() + 5)
    local function NewText(parent)
        local fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetFont(FontPath(), 12, "")
        return fs
    end

    card.title = NewText(card)
    card.title:SetTextColor(1, 0.82, 0, 1)   -- until the Premade Groups title's colour is read (Layout)
    card.title:SetText("M+ Applications")


    -- The box: the theme border of the panel's buttons around the bar.
    local box = CreateFrame("Frame", nil, card)
    box:EnableMouse(true)
    box:SetScript("OnEnter", ShowTip)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 1)   -- the empty bar
    local S = ns.Skin and ns.Skin()
    if S and S.AddBorder then
        S.AddBorder(box)
    elseif CM.MakeBorder then
        local r, g, b, a = 0.2, 0.2, 0.2, 1
        if ns.ThemeBorder then r, g, b, a = ns.ThemeBorder() end
        CM.MakeBorder(box, r, g, b, a)
    end
    card.box = box
    local px = (CM.PP and CM.PP.mult) or 1
    local bar = CreateFrame("Frame", nil, box)
    bar:SetPoint("TOPLEFT", box, "TOPLEFT", px, -px)
    bar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -px, px)
    card.bar = bar
    card.segs, card.nums = {}, {}
    for i = 1, #SEGMENTS do
        card.segs[i] = bar:CreateTexture(nil, "ARTWORK", nil, 1)
        local num = bar:CreateFontString(nil, "OVERLAY")
        num:SetFont(FontPath(), 12, "OUTLINE")
        num:SetTextColor(1, 1, 1, 1)
        num:SetJustifyH("CENTER")
        num:SetJustifyV("MIDDLE")
        card.nums[i] = num
    end
    bar:SetScript("OnSizeChanged", function() Refresh() end)
    return card
end

-- Shown only on the Premade Groups search for Dungeons (Find a Group in
-- Dungeons), the only category it counts.
local function InDungeonSearch()
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    return sp and sp:IsShown() and sp.categoryID == (GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2) or false
end

-- Show/hide the card, re-place and re-layout it from the settings.
local function Apply()
    local on = On()
    local want = on and InDungeonSearch()
    if want then BuildCard() end
    if card then
        card:SetShown(want)
        if want then
            Layout()
        elseif not on and card.lblSize then
            -- Off: the Premade Groups title back to its own size.
            local lbl = _G.LFGListFrame and _G.LFGListFrame.CategorySelection and _G.LFGListFrame.CategorySelection.Label
            local lpath, _, lflags = lbl and lbl:GetFont()
            if lpath then lbl:SetFont(lpath, card.lblSize, lflags) end
        end
    end
    Refresh()
end
ns.ApplyApplications = Apply
-- The search panel's rows can change size (side padding, the panel's width):
-- follow them.
if ns.Search_Layout then
    -- (also how a category change shows / hides it)
    hooksecurefunc(ns, "Search_Layout", function() Apply() end)
end

-------------------------------------------------------------------------------
--  Counting
-------------------------------------------------------------------------------
-- Whether a search result is a Dungeons category group, remembered per
-- result for the session (a delisted group's info can be gone by its last
-- status update). nil = cannot tell (unreadable or secret): not counted.
local DUNGEONS = GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2
local isDungeon = {}
local function IsDungeonResult(id)
    if type(id) ~= "number" or IsSecret(id) then return nil end
    if isDungeon[id] ~= nil then return isDungeon[id] end
    local info = C_LFGList.GetSearchResultInfo(id)
    if type(info) ~= "table" or IsSecret(info) or (canaccesstable and not canaccesstable(info)) then return nil end
    local acts = info.activityIDs
    local aid = (type(acts) == "table" and not IsSecret(acts)) and acts[1] or info.activityID
    if type(aid) ~= "number" or IsSecret(aid) then return nil end
    local ai = C_LFGList.GetActivityInfoTable(aid)
    local cat = type(ai) == "table" and ai.categoryID
    if type(cat) ~= "number" or IsSecret(cat) then return nil end
    isDungeon[id] = (cat == DUNGEONS)
    return isDungeon[id]
end

local function Count(status, resultID)
    local key = STATUS_KEY[status]
    if not key or IsDungeonResult(resultID) ~= true then return end
    local a = Store()
    for _, t in ipairs({ Fill(a.account), Fill(a.session), Counts("character") }) do
        t[key] = t[key] + 1
    end
    Refresh()
end

function ns.ResetApplications(scope)
    local a = Store()
    if scope == "account" then
        a.account = Blank()
    elseif scope == "session" then
        a.session = Blank()
    elseif myKey then
        a.chars[myKey] = Blank()
    end
    Refresh()
end

local hooked = false
local function HookPVE()
    local pve = _G.PVEFrame
    if hooked or not pve then return end
    hooked = true
    -- Next frame: the skin lays the window out on the same show.
    pve:HookScript("OnShow", function() C_Timer.After(0, Apply) end)
    if pve:IsShown() then C_Timer.After(0, Apply) end
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    if sp then
        sp:HookScript("OnShow", function() C_Timer.After(0, Apply) end)
        sp:HookScript("OnHide", Apply)
    end
end

-- Started by the module's OnEnable (PLAYER_LOGIN) while the module is on.
function ns.Apps_Enable()
    local name, realm = UnitFullName("player")
    name = PlainString(name)
    if name then myKey = name .. "-" .. (PlainString(realm) or MyRealm()) end
    local a = Store()
    if time() - (tonumber(a.session.t) or 0) > SESSION_GAP then a.session = Blank() end
    HookPVE()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ADDON_LOADED")
    ev:RegisterEvent("PLAYER_LOGOUT")
    ev:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
    ev:SetScript("OnEvent", function(_, event, ...)
        if event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
            if On() then
                local id, status = ...
                Count(PlainString(status), id)
            end
        elseif event == "ADDON_LOADED" then
            if (...) == "Blizzard_GroupFinder" then HookPVE() end
        elseif event == "PLAYER_LOGOUT" then
            Store().session.t = time()
        end
    end)
end
