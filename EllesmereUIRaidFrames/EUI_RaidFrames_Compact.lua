if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local _, ns = ...
local I = ns._internals
if not I or I.broken then return end
I.broken = true

local EUI = ns.EllesmereUI
local CreateFrame, C_Timer = CreateFrame, C_Timer
local db, container
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
I.containerFrameSetters[#I.containerFrameSetters + 1] = function(v) container = v end

function ns.RF_CompactEligible(s)
    return s and (s.borderTexture == "pixels" or s.borderTexture == "pixels-textured")
        and not ns.RF_Stock() and (s.borderSize or 1) > 0
end

function ns.RF_CompactOn(s, party)
    if not s or not (party and s.partyCompactMode == true or not party and s.raidCompactMode == true) then return false end
    local style = s
    if party and s == db.profile then style = ns._partyProxy
    elseif party and s == ns._pvOverlayProxy then style = ns._scaledPartyProxy end
    if not ns.RF_CompactEligible(style) then return false end
    return not party or (not ns.RF_PartyKit()
        and not ns.PT_AlongStack(s, s.partyShowTargets == true))
end

function ns.RF_GridOn(s)
    return s.raidGridMode == true and ns.RF_CompactOn(s, false)
end

function ns.RF_OnePixel(party)
    local frame = party and ns._partyContainerFrame or container
    return EUI.PP.perfect / (frame and frame:GetEffectiveScale() or UIParent:GetEffectiveScale())
end

function ns.RF_CellSpacing(s, party)
    if ns.RF_CompactOn(s, party) then return ns.RF_OnePixel(party) end
    return I.PixelSnap(party and (s.partyCellSpacing or s.cellSpacing or 2) or (s.cellSpacing or 2))
end

function ns.RF_GroupSpacing(s)
    return ns.RF_GridOn(s) and ns.RF_OnePixel(false) or I.PixelSnap(s.groupSpacing or 8)
end

function ns.RF_ButtonCompact(d, s)
    return not d._isExtra and ns.RF_CompactOn(s, d._isParty == true)
end

function ns.RF_PetCompactOn(button, s)
    local d = I.FFD[button]
    if not d then return false end
    if d._petGroupedPreview then return ns.RF_CompactOn(s, d._petPreviewParty) end
    local pf = ns._PF
    return d._petHeader and pf and pf.active and ns.RF_CompactOn(s, pf.styleCtx == "party") or false
end

function ns.RF_PetCompactHighlight(button, s)
    local d = I.GetFFD(button)
    d._hovered, d._isTarget = ns._FB.hov[button], ns._FB.tgt[button]
    ns.RF_CompactHighlight(button._borderFrame, d, s, button)
end

function ns.RF_InsetRing(frame, anchor, pixels)
    local inset = pixels * EUI.PP.perfect / frame:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset)
    frame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, inset)
end

function ns.RF_CompactHighlight(frame, d, s, button)
    local c, a
    if d._hovered and s.hoverBorderEnabled ~= false then
        c, a = s.hoverBorderColor, s.hoverBorderAlpha or 1
    elseif d._isTarget and s.targetBorderEnabled ~= false then
        c, a = s.targetBorderColor, s.targetBorderAlpha or 1
    end
    if c then
        local r, g, b = ns.RF_VisibleHighlight(s, c.r, c.g, c.b)
        if not d._compactHighlight then
            frame:SetFrameLevel(button:GetFrameLevel() + ns.LVL_AURA + 2)
            EUI.ApplyBorderStyle(frame, 2, r, g, b, a, "solid", nil, nil, nil, nil, nil, nil, nil, 2)
            local strips = EUI.PP.GetBorders(frame)
            if strips then strips:SetFrameLevel(frame:GetFrameLevel() + 1) end
            d._compactHighlight = true
        else
            EUI.SetBorderStyleColor(frame, r, g, b, a)
            frame:Show()
        end
    elseif d._compactHighlight then
        EUI.ApplyBorderStyle(frame, 0, 0, 0, 0, 0, "solid")
        d._compactHighlight = nil
    end
end

local raid, party, pets, raidPreview, partyPreview, petPreview, events, eventsOn
local function HideState(st)
    if not st or not st.shown then return end
    for _, host in ipairs(st.hosts) do
        if host:IsShown() then
            EUI.HideBorderStyle(host)
            host:Hide()
        end
    end
    for _, f in ipairs(st.empty) do if f:IsShown() then f:Hide() end end
    for _, t in ipairs(st.seams) do if t:IsShown() then t:Hide() end end
    st.shown, st.dirty = false, true
end

local function NewState(owner, isParty)
    return { owner = owner, isParty = isParty,
        groups = {}, hosts = {}, empty = {}, seams = {}, style = {}, dirty = true }
end

local function PutStyle(st, key, value)
    if st.style[key] ~= value then st.style[key], st.dirty = value, true end
end

local function UpdateStyle(st, s)
    local c = s.borderColor or I.defaults.profile.borderColor
    local grid = not st.isParty and ns.RF_GridOn(s)
    local r, g, b, a
    if grid and not st.isPet then
        if s.healthColorMode == "dark" then r, g, b, a = EUI.GetDarkModeBg()
        else r, g, b, a = ns.GetBgColor(nil, s) end
    end
    PutStyle(st, "tex", s.borderTexture); PutStyle(st, "size", s.borderSize or 1)
    PutStyle(st, "px", EUI.BorderPx(s.borderSizePx, s.borderSize or 1, s.borderTexture))
    PutStyle(st, "offX", s.borderTextureOffset); PutStyle(st, "offY", s.borderTextureOffsetY)
    PutStyle(st, "shiftX", s.borderTextureShiftX); PutStyle(st, "shiftY", s.borderTextureShiftY)
    PutStyle(st, "behind", s.borderBehind); PutStyle(st, "r", c.r); PutStyle(st, "g", c.g); PutStyle(st, "b", c.b)
    PutStyle(st, "a", s.borderAlpha or 1); PutStyle(st, "bgR", r); PutStyle(st, "bgG", g); PutStyle(st, "bgB", b); PutStyle(st, "bgA", a)
    PutStyle(st, "one", EUI.PP.perfect / st.owner:GetEffectiveScale())
    PutStyle(st, "grid", grid)
end

local function Cell(st, gi, index, f)
    local group = st.groups[gi]
    if not group then group = { cells = {} }; st.groups[gi] = group end
    local cell = group.cells[index]
    if not cell then cell = {}; group.cells[index] = cell end
    local scale = f:GetEffectiveScale() / st.owner:GetEffectiveScale()
    local x, y, w, h = f:GetRect()
    if not x or not y then return false end
    x, y, w, h = x * scale, (y + h) * scale, w * scale, h * scale
    local level, strata = f:GetFrameLevel(), f:GetFrameStrata()
    if cell.frame ~= f or cell.x ~= x or cell.y ~= y or cell.w ~= w or cell.h ~= h
        or cell.level ~= level or cell.strata ~= strata then
        cell.frame, cell.x, cell.y, cell.w, cell.h = f, x, y, w, h
        cell.level, cell.strata = level, strata
        st.dirty = true
    end
    return true
end

local function Along(a, b)
    if a.x == b.x then return a.y > b.y end
    return a.x < b.x
end

local function FinishGroup(st, gi, count, growth)
    local group = st.groups[gi]
    if not group then group = { cells = {} }; st.groups[gi] = group end
    if group.count ~= count then group.count, st.dirty = count, true end
    if group.growth ~= growth then group.growth, st.dirty = growth, true end
end

local function Host(st, index, first, x, y, w, h)
    local host = st.hosts[index]
    if not host then host = CreateFrame("Frame", nil, st.owner); st.hosts[index] = host end
    local v = st.style
    host:SetFrameStrata(first.strata)
    host:SetFrameLevel(v.behind and math.max(0, first.level - 1) or first.level + 8)
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", first.frame, "TOPLEFT", x - first.x, y - first.y)
    host:SetSize(w, h)
    EUI.ApplyBorderStyle(host, v.size, v.r, v.g, v.b, v.a, v.tex,
        v.offX, v.offY, v.shiftX, v.shiftY, "unitframes", v.size, nil, v.px)
    host:Show()
end

local function Seam(st, index, first, x, y, length, vertical)
    local t = st.seams[index]
    if not t then
        if not st.seamHost then st.seamHost = CreateFrame("Frame", nil, st.owner) end
        t = st.seamHost:CreateTexture(nil, "OVERLAY")
        EUI.PP.DisablePixelSnap(t)
        st.seams[index] = t
    end
    local v = st.style
    local host = st.seamHost
    host:SetFrameStrata(first.strata)
    host:SetFrameLevel(v.behind and math.max(0, first.level - 1) or first.level + 8)
    t:ClearAllPoints()
    t:SetTexture(vertical and v.sepV or v.sepH)
    t:SetTexCoord(0, 1, 0, 1)
    t:SetPoint("TOPLEFT", first.frame, "TOPLEFT", x - first.x - (vertical and v.lead or 0), y - first.y + (vertical and 0 or v.lead))
    t:SetSize(vertical and v.thick or length, vertical and length or v.thick)
    t:SetVertexColor(v.r, v.g, v.b, v.a)
    t:Show()
end

local function Draw(st)
    if not st.dirty then return end
    local v = st.style
    local scale = st.owner:GetEffectiveScale()
    v.thick = EUI.BorderCompanionThickness(v.tex, v.size, v.px, scale)
    -- Both separator textures put their bright line at texel 5 of 32.
    v.lead = EUI.PP.SnapForES(v.thick * 5 / 32, scale)
    v.sepV, v.sepH = EUI.GetBorderCompanion(v.tex, "sepV"), EUI.GetBorderCompanion(v.tex, "sepH")
    local gap = st.layoutPixel or v.one
    local hostCount, emptyCount, seamCount = 0, 0, 0
    local minX, maxY, maxX, minY, area, first = nil, nil, nil, nil, 0, nil
    for gi = 1, st.count do
        local group = st.groups[gi]
        local cells, n = group.cells, group.count
        if n > 0 then
            -- Keep the capture order stable so an unchanged UP/LEFT stack stays cached.
            group.sorted = group.sorted or {}
            for i = 1, n do group.sorted[i] = cells[i] end
            for i = #group.sorted, n + 1, -1 do group.sorted[i] = nil end
            table.sort(group.sorted, Along)
            cells = group.sorted
            local c = cells[1]
            local horizontal = group.growth == "LEFT" or group.growth == "RIGHT"
            local x, y = c.x, c.y
            local w = horizontal and (n * c.w + (n - 1) * gap) or c.w
            local h = horizontal and c.h or (n * c.h + (n - 1) * gap)
            if v.grid and not st.isPet and n < 5 then
                local missing = 5 - n
                if group.growth == "LEFT" then x = x - missing * (c.w + gap) end
                if group.growth == "UP" then y = y + missing * (c.h + gap) end
                w = horizontal and (5 * c.w + 4 * gap) or c.w
                h = horizontal and c.h or (5 * c.h + 4 * gap)
                for i = n + 1, 5 do
                    emptyCount = emptyCount + 1
                    local f = st.empty[emptyCount]
                    if not f then
                        f = CreateFrame("Frame", nil, st.owner)
                        f.bg = f:CreateTexture(nil, "BACKGROUND")
                        f.bg:SetAllPoints(); EUI.PP.DisablePixelSnap(f.bg)
                        st.empty[emptyCount] = f
                    end
                    local offset = i - n
                    local endCell = (group.growth == "UP" or group.growth == "LEFT") and cells[1] or cells[n]
                    local dx = horizontal and offset * (c.w + gap) * (group.growth == "LEFT" and -1 or 1) or 0
                    local dy = not horizontal and offset * (c.h + gap) * (group.growth == "UP" and 1 or -1) or 0
                    f:ClearAllPoints(); f:SetPoint("TOPLEFT", endCell.frame, "TOPLEFT", dx, dy)
                    f:SetSize(c.w, c.h); f:SetFrameStrata(c.strata); f:SetFrameLevel(c.level)
                    f.bg:SetColorTexture(v.bgR, v.bgG, v.bgB, v.bgA); f:Show()
                end
                n = 5
            end
            group.x, group.y, group.w, group.h = x, y, w, h
            minX, maxY = math.min(minX or x, x), math.max(maxY or y, y)
            maxX, minY = math.max(maxX or (x + w), x + w), math.min(minY or (y - h), y - h)
            area = area + (w + gap) * (h + gap)
            first = first or c
            for i = 1, n - 1 do
                seamCount = seamCount + 1
                Seam(st, seamCount, c, horizontal and x + i * (c.w + gap) or x,
                    horizontal and y or y - i * (c.h + gap), horizontal and h or w, horizontal)
            end
        end
    end
    local rectangular = first and v.grid and math.abs(area - (maxX - minX + gap) * (maxY - minY + gap)) < gap * gap / 2
    if rectangular then
        hostCount = 1
        Host(st, 1, first, minX, maxY, maxX - minX, maxY - minY)
    end
    for gi = 1, st.count do
        local group = st.groups[gi]
        if group.count > 0 then
            if not rectangular then
                hostCount = hostCount + 1
                Host(st, hostCount, group.sorted[1], group.x, group.y, group.w, group.h)
            else
                for gj = gi + 1, st.count do
                    local other = st.groups[gj]
                    if other.count > 0 then
                        local x = math.max(group.x, other.x)
                        local y = math.min(group.y, other.y)
                        local width = math.min(group.x + group.w, other.x + other.w) - x
                        local height = y - math.max(group.y - group.h, other.y - other.h)
                        if height > 0 and (math.abs(group.x + group.w + gap - other.x) < gap / 2
                            or math.abs(other.x + other.w + gap - group.x) < gap / 2) then
                            seamCount = seamCount + 1
                            Seam(st, seamCount, first, x, y, height, true)
                        elseif width > 0 and (math.abs(group.y - group.h - gap - other.y) < gap / 2
                            or math.abs(other.y - other.h - gap - group.y) < gap / 2) then
                            seamCount = seamCount + 1
                            Seam(st, seamCount, first, x, y, width, false)
                        end
                    end
                end
            end
        end
    end
    for i = hostCount + 1, #st.hosts do
        if st.hosts[i]:IsShown() then EUI.HideBorderStyle(st.hosts[i]); st.hosts[i]:Hide() end
    end
    for i = emptyCount + 1, #st.empty do if st.empty[i]:IsShown() then st.empty[i]:Hide() end end
    for i = seamCount + 1, #st.seams do if st.seams[i]:IsShown() then st.seams[i]:Hide() end end
    st.shown, st.dirty = first ~= nil, false
end

local RefreshLive
local function Queue(st)
    if not st.on or st.pending then return end
    st.pending = true
    C_Timer.After(0, st.flush)
end

local function Hook(st, f)
    if st.hooked[f] then return end
    st.hooked[f] = true
    f:HookScript("OnShow", st.queue)
    f:HookScript("OnHide", st.queue)
    f:HookScript("OnSizeChanged", st.queue)
    f:HookScript("OnAttributeChanged", st.assigned)
end

local function RefreshButtonBorders(st, on)
    local changed = false
    for _, f in ipairs(st.isParty and ns._partyAllButtons or I.allButtons) do
        local d = I.GetFFD(f)
        if not d._isExtra and d.UpdateBorder and (on or d._compactBorder) and d._compactBorder ~= on then
            d.UpdateBorder()
            changed = true
            local unit = f:GetAttribute("unit")
            if unit then ns.RF_PaintThreat(d, st.isParty and ns._scaledPartyProxy or ns._scaledProfile, unit) end
        end
    end
    if changed and ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
end

local function CollectGroup(st, frames, start, limit, gi, growth)
    local n = 0
    for i = start, limit do
        local f = frames and frames[i]
        if f then
            Hook(st, f)
            if f:IsVisible() and f:GetAttribute("unit") and Cell(st, gi, n + 1, f) then
                n = n + 1
            end
        end
    end
    FinishGroup(st, gi, n, growth)
end

local function HeaderGrowth(header)
    local point = header and header:GetAttribute("point")
    return point == "BOTTOM" and "UP" or point == "LEFT" and "RIGHT" or point == "RIGHT" and "LEFT" or "DOWN"
end

local function CollectLive(st, s)
    local count = 0
    if st.isPet then
        local pf = ns._PF
        local growth = HeaderGrowth(pf.container)
        for gi = 1, math.ceil(#pf.buttons / 5) do
            CollectGroup(st, pf.buttons, (gi - 1) * 5 + 1, math.min(gi * 5, #pf.buttons), gi, growth)
            count = gi
        end
    elseif st.isParty then
        CollectGroup(st, ns._partyAllButtons, 1, #ns._partyAllButtons, 1, ns._PartyGrowth(s))
        count = 1
    elseif s.mergeGroups then
        st.flat = st.flat or {}
        local limit = 0
        for i = 1, 40 do
            local f = ns._flatHeader and ns._flatHeader[i]
            if f then
                Hook(st, f)
                if f:IsVisible() and f:GetAttribute("unit") then
                    limit = limit + 1
                    st.flat[limit] = f
                end
            end
        end
        local growth = HeaderGrowth(ns._flatHeader)
        for gi = 1, math.ceil(limit / 5) do
            local n = 0
            for i = (gi - 1) * 5 + 1, math.min(gi * 5, limit) do
                if Cell(st, gi, n + 1, st.flat[i]) then n = n + 1 end
            end
            FinishGroup(st, gi, n, growth); count = gi
        end
    else
        for gi = 1, 8 do
            local hdr = I.separatedHdrs[gi]
            CollectGroup(st, hdr, 1, 5, gi, HeaderGrowth(hdr))
        end
        count = 8
    end
    if st.count ~= count then st.count, st.dirty = count, true end
end

RefreshLive = function(st)
    st.pending = nil
    if not st.on then return end
    local s = st.isPet and ns._PF.StyleSource() or (st.isParty and ns._partyProxy or db.profile)
    UpdateStyle(st, s)
    CollectLive(st, s)
    Draw(st)
end

local function NewLiveState(owner, isParty)
    local st = NewState(owner, isParty)
    st.hooked = setmetatable({}, { __mode = "k" })
    st.flush = function() RefreshLive(st) end
    st.queue = function() Queue(st) end
    st.assigned = function(_, name) if name == "unit" then Queue(st) end end
    return st
end

local function ScaleState(st)
    if not st or not st.on or not ns.RF_CompactOn(st.isParty and ns._partyProxy or db.profile, st.isParty)
        or st.layoutPixel == ns.RF_OnePixel(st.isParty) then return end
    ns.CombatQueue.Defer(st.isParty and "compact-party-scale" or "compact-raid-scale", function()
        if not st.on or not ns.RF_CompactOn(st.isParty and ns._partyProxy or db.profile, st.isParty)
            or st.layoutPixel == ns.RF_OnePixel(st.isParty) then return end
        if st.isParty then ns._LayoutPartyFrames() else I.LayoutGroups() end
        for f in pairs(st.hooked) do
            local d = I.GetFFD(f)
            if d._compactThreat and d.threatFrame then ns.RF_InsetRing(d.threatFrame, f, 2) end
        end
        if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
    end)
end

local function ScalePets()
    local st = pets
    local pf = ns._PF
    if not st or not st.on or not pf.active or not ns.RF_CompactOn(pf.StyleSource(), st.isParty)
        or st.layoutPixel == ns.RF_OnePixel(st.isParty) then return end
    ns.CombatQueue.Defer("compact-pet-scale", function()
        if not st.on or not pf.active or not ns.RF_CompactOn(pf.StyleSource(), st.isParty)
            or st.layoutPixel == ns.RF_OnePixel(st.isParty) then return end
        pf.Layout()
    end)
end

local function ScaleChanged()
    ScaleState(raid)
    ScaleState(party)
    ScalePets()
end

local function SyncEvents()
    local active = ((raid and raid.on) or (party and party.on) or (pets and pets.on)) and true or false
    if active and not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", ScaleChanged)
    end
    if events and active ~= eventsOn then
        eventsOn = active
        if active then
            events:RegisterEvent("UI_SCALE_CHANGED"); events:RegisterEvent("DISPLAY_SIZE_CHANGED")
        else events:UnregisterAllEvents() end
    end
end

function ns.RF_SyncCompact(isParty)
    local s = isParty and ns._partyProxy or db.profile
    local on = ns.RF_CompactOn(s, isParty)
    local st
    if isParty then st = party else st = raid end
    if not on and not st then return end
    if on and not st then
        st = NewLiveState(isParty and ns._partyContainerFrame or container, isParty)
        if isParty then party = st else raid = st end
    end
    local wasOn = st.on
    st.on = on
    if wasOn ~= on then RefreshButtonBorders(st, on) end
    if on then st.layoutPixel = ns.RF_OnePixel(isParty); Queue(st) else HideState(st) end
    SyncEvents()
end

function ns.RF_SyncPetCompact()
    local pf = ns._PF
    local isParty = pf and pf.styleCtx == "party"
    local on = pf and pf.active and ns.RF_CompactOn(pf.StyleSource(), isParty) or false
    local st = pets
    if not on and not st then return end
    if not st then
        st = NewLiveState(pf.container, isParty)
        st.isPet = true
        pets = st
    end
    if st.on ~= on then
        st.on = on
        for _, f in ipairs(pf.buttons) do
            local d = I.GetFFD(f)
            if f._borderFrame and (on or d._petCompactBorder) and d._petCompactBorder ~= on then
                ns._FB.StyleBorder(f)
            end
        end
    end
    st.isParty = isParty
    if on then st.layoutPixel = ns.RF_OnePixel(isParty); Queue(st) else HideState(st) end
    SyncEvents()
end

local function PreviewCompact(st, frames, s, isParty, growth, isPet)
    if not frames or not ns.RF_CompactOn(s, isParty) then HideState(st); return st end
    local owner
    for _, f in ipairs(frames) do
        if f:IsShown() then owner = f:GetParent(); break end
    end
    if not owner then HideState(st); return st end
    if not st then
        st = NewState(owner, isParty)
    end
    st.isPet, st.isParty = isPet, isParty
    if st.owner ~= owner then
        st.owner, st.dirty = owner, true
        for _, f in ipairs(st.hosts) do f:SetParent(owner) end
        for _, f in ipairs(st.empty) do f:SetParent(owner) end
        if st.seamHost then st.seamHost:SetParent(owner) end
    end
    UpdateStyle(st, s)
    local count = isParty and 1 or math.ceil(#frames / 5)
    for gi = 1, count do
        local n = 0
        for i = (gi - 1) * 5 + 1, math.min(gi * 5, #frames) do
            local f = frames[i]
            if f:IsShown() and Cell(st, gi, n + 1, f) then n = n + 1 end
        end
        FinishGroup(st, gi, n, growth)
    end
    if st.count ~= count then st.count, st.dirty = count, true end
    Draw(st)
    return st
end

function ns.RF_PreviewCompact(frames, s, isParty, growth)
    if isParty then partyPreview = PreviewCompact(partyPreview, frames, s, true, growth)
    else raidPreview = PreviewCompact(raidPreview, frames, s, false, growth) end
end

function ns.RF_PreviewPetCompact(frames, s, isParty, growth)
    petPreview = PreviewCompact(petPreview, frames, s, isParty, growth, true)
end

I.broken = false
