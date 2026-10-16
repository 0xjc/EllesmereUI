if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EUI_GroupFinder_Applications.lua: M+ applications bar in the rail, counts per
-- session, character and account.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local CM = EllesmereUI

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function PlainString(v)
    if type(v) == "string" and not IsSecret(v) and v ~= "" then return v end
end
-- Realm the way UnitFullName returns it.
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
local SESSION_GAP = 300  -- relogging within 5 min keeps the session

local STATUS_KEY = {
    applied = "applied",
    declined = "declined", declined_full = "declined", timedout = "declined",
    declined_delisted = "delisted",
    cancelled = "cancelled",
    invited = "invited",
    inviteaccepted = "accepted",
}

-- Bar segments. Invites aren't shown, every invite counts as accepted.
local SEGMENTS = {
    { key = "accepted",  label = "Accepted",  cfg = "showAccepted",  r = 0.35, g = 0.85, b = 0.40 },
    { key = "declined",  label = "Declined",  cfg = "showDeclined",  r = 0.95, g = 0.30, b = 0.30 },
    { key = "delisted",  label = "Delisted",  cfg = "showDelisted",  r = 1.00, g = 0.60, b = 0.20 },
    { key = "cancelled", label = "Cancelled", cfg = "showCancelled", r = 0.55, g = 0.55, b = 0.55 },
}
local SCOPES = { "session", "character", "account" }
local SCOPE_LABEL = { session = "Session", character = "Character", account = "Account" }

-- Built-in bar textures plus SharedMedia's.
local barTextures, barTexNames, barTexOrder = {}, {}, {}
if CM.BuildBarTextureTables then
    barTextures, barTexNames, barTexOrder = CM.BuildBarTextureTables()
    if CM.AppendSharedMediaTextures then CM.AppendSharedMediaTextures(barTexNames, barTexOrder, nil, barTextures) end
end
ns.BarTextureTables = function() return barTextures, barTexNames, barTexOrder end

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
-- Card
-------------------------------------------------------------------------------
local card
local TITLE_SIZE = 12

local function FontPath() return (CM.GetFontPath and CM.GetFontPath()) or STANDARD_TEXT_FONT end

local function Scope()
    local s = Get("scope", "character")
    return SCOPE_LABEL[s] and s or "character"
end

-- Counts use the search box font (12 until it's set).
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

-- Where the search rows sit, in PVEFrame coordinates.
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

local function Layout()
    if not card then return end
    local path = FontPath()
    local npath, nsize = CountFont()
    card.title:SetFont(path, TITLE_SIZE, "")
    -- The Premade Groups title, same size and colour as ours.
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
        card.empty:SetFont(npath, nsize, "OUTLINE")
    end
    Place()
end

local function Refresh()
    if not (card and card:IsShown()) then return end
    local c = Counts(Scope())
    -- Split the bar between the shown outcomes so it always fills.
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
        -- Each segment shows its slice of the texture so it reads as one bar.
        if textured and w > 0 then tex:SetTexCoord(x / w, (x + sw) / w, 0, 1) end
        tex:SetShown(sw >= 0.5)
        num:SetText(tostring(c[seg.key]))
        num:ClearAllPoints()
        num:SetPoint("CENTER", tex, "CENTER", 0, 0)
        num:SetShown(sw >= 0.5 and (num:GetStringWidth() or 0) + 4 <= sw)
        x = x + sw
    end
    card.empty:SetShown(total == 0)  -- nothing counted yet
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

    -- Build into a local first so a failure never leaves half a card.
    local card = CreateFrame("Frame", nil, host)
    card:SetAllPoints(host)
    card:SetFrameLevel(host:GetFrameLevel() + 5)
    local function NewText(parent)
        local fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetFont(FontPath(), 12, "")
        return fs
    end

    card.title = NewText(card)
    card.title:SetTextColor(1, 0.82, 0, 1)
    card.title:SetText("M+ Applications")


    local box = CreateFrame("Frame", nil, card)
    box:EnableMouse(true)
    box:SetScript("OnEnter", ShowTip)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 1)
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
    card.empty = bar:CreateFontString(nil, "OVERLAY")
    card.empty:SetFont(FontPath(), 12, "OUTLINE")
    card.empty:SetTextColor(1, 1, 1, 0.6)
    card.empty:SetPoint("CENTER", bar, "CENTER", 0, 0)
    card.empty:SetText("N/A")
    card.empty:Hide()
    bar:SetScript("OnSizeChanged", function() Refresh() end)
    return card
end

-- Only shown on the Dungeons search, the only thing it counts.
local function InDungeonSearch()
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    return sp and sp:IsShown() and sp.categoryID == (GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2) or false
end

local function Apply()
    local on = On()
    local want = on and InDungeonSearch()
    if want then BuildCard() end
    if card then
        card:SetShown(want)
        if want then
            Layout()
        elseif not on and card.lblSize then
            -- Off: title back to its own size.
            local lbl = _G.LFGListFrame and _G.LFGListFrame.CategorySelection and _G.LFGListFrame.CategorySelection.Label
            local lpath, _, lflags = lbl and lbl:GetFont()
            if lpath then lbl:SetFont(lpath, card.lblSize, lflags) end
        end
    end
    Refresh()
end
ns.ApplyApplications = Apply
-- Follow the search rows when they resize.
if ns.Search_Layout then
    hooksecurefunc(ns, "Search_Layout", function() Apply() end)
end

-------------------------------------------------------------------------------
-- Counting
-------------------------------------------------------------------------------
local DUNGEONS = GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2
local isDungeon = {}  -- resultID -> is a dungeon group
local function LookUpDungeon(id)
    local info = C_LFGList.GetSearchResultInfo(id)
    if type(info) ~= "table" or IsSecret(info) or (canaccesstable and not canaccesstable(info)) then return nil end
    local acts = info.activityIDs
    local aid = (type(acts) == "table" and not IsSecret(acts)) and acts[1] or info.activityID
    if type(aid) ~= "number" or IsSecret(aid) then return nil end
    local ai = C_LFGList.GetActivityInfoTable(aid)
    local cat = type(ai) == "table" and ai.categoryID
    if type(cat) ~= "number" or IsSecret(cat) then return nil end
    return cat == DUNGEONS
end

local function Count(status, oldStatus, resultID)
    local key = STATUS_KEY[status]
    if type(resultID) ~= "number" or IsSecret(resultID) then return end
    if status == "applied" then
        if oldStatus == "applied" then return end
        isDungeon[resultID] = LookUpDungeon(resultID)
    elseif isDungeon[resultID] == nil then
        isDungeon[resultID] = LookUpDungeon(resultID)
    end
    local dungeon = isDungeon[resultID]
    if status ~= "applied" and status ~= "invited" then isDungeon[resultID] = nil end
    if not key or status == oldStatus or dungeon ~= true then return end
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
    -- Next frame, after the skin lays the window out.
    pve:HookScript("OnShow", function() C_Timer.After(0, Apply) end)
    if pve:IsShown() then C_Timer.After(0, Apply) end
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    if sp then
        sp:HookScript("OnShow", function() C_Timer.After(0, Apply) end)
        sp:HookScript("OnHide", Apply)
    end
end

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
                local id, status, oldStatus = ...
                Count(PlainString(status), PlainString(oldStatus), id)
            end
        elseif event == "ADDON_LOADED" then
            if (...) == "Blizzard_GroupFinder" then HookPVE() end
        elseif event == "PLAYER_LOGOUT" then
            Store().session.t = time()
        end
    end)
end
