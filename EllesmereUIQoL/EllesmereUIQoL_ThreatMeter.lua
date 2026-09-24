if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ThreatMeter.lua  (WoW Forever only)
--  Threat on your target for everyone in the group, one bar each, sorted, with
--  an optional pull aggro bar and a warning sound. Forever hands the threat API
--  over readable (C_Secrets.ShouldUnitThreatValuesBeSecret is false there); a
--  value that does come back secret skips that unit rather than erroring.
-------------------------------------------------------------------------------
local UPDATE_DELAY = 0.2
local FOLLOW_INTERVAL = 0.5
local PREVIEW_SECONDS = 10
local TEXT_PAD = 4

-- Settings live in EllesmereUIDB.threatMeter; unset keys read these.
local DEFAULTS = {
    width = 220, barHeight = 18, spacing = 1, maxBars = 10,
    growUp = false, showHeader = true, ignorePets = false,
    texture = "none", barOpacity = 100, bgA = 0.6,
    borderSize = 1, borderR = 0, borderG = 0, borderB = 0,
    font = "__global", outlineMode = "__global", textSize = 12,
    showValue = true, showPercent = true,
    playerColorOn = false, playerR = 0.8, playerG = 0.1, playerB = 0.1,
    tankColorOn = false, tankR = 0.1, tankG = 0.6, tankB = 0.1,
    pullBar = true, pullR = 0.0, pullG = 0.55, pullB = 0.0,
    warnSound = false, warnSoundKey = "none", warnAt = 80, warnSkipTank = true,
}

local PET_COLOR = { r = 0.45, g = 0.6, b = 0.45 }
local FALLBACK_COLOR = { r = 0.6, g = 0.6, b = 0.6 }

local BAR_TEXTURES, BAR_TEXTURE_NAMES, BAR_TEXTURE_ORDER = EllesmereUI.BuildBarTextureTables()

local frame, events, pendingUpdate, previewUntil, followTicker
local rows = {}         -- bar widgets, created on demand
local entries = {}      -- reused threat entries, one per unit seen
local list = {}         -- the entries shown this update, sorted
local warned

-- Cfg() is the WRITE accessor (creates the table); Read() never creates it, so
-- a user who never touches the feature gets no saved table.
local function Cfg()
    if not EllesmereUIDB then return {} end
    EllesmereUIDB.threatMeter = EllesmereUIDB.threatMeter or {}
    return EllesmereUIDB.threatMeter
end

local _NOCFG = {}
local function Read()
    return EllesmereUIDB and EllesmereUIDB.threatMeter or _NOCFG
end

local function Get(key)
    local v = Read()[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

local function Enabled()
    return Read().enabled == true
end

local function Readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- Blizzard's threat numbers are 100 per point of damage-equivalent threat.
local function ShortThreat(v)
    v = v / 100
    if v >= 1000000 then return string.format("%.1fm", v / 1000000) end
    if v >= 1000 then return string.format("%.1fk", v / 1000) end
    return tostring(math.floor(v + 0.5))
end

-- The mob whose threat table is shown: your target when you can attack it,
-- otherwise what your friendly target is fighting (a healer targeting the tank).
local function ThreatMob()
    if UnitExists("target") and UnitCanAttack("player", "target") then return "target" end
    if UnitExists("targettarget") and UnitCanAttack("player", "targettarget") then
        return "targettarget"
    end
end

-- A tank does not want to be warned about holding aggro: tank role, Bear or Dire
-- Bear Form, or Defensive Stance.
local function PlayerIsTank()
    if UnitGroupRolesAssigned("player") == "TANK" then return true end
    local form = GetShapeshiftFormID()
    return form == 5 or form == 8 or form == 18
end

-------------------------------------------------------------------------------
--  Appearance
-------------------------------------------------------------------------------
local function TextFont()
    local key = Get("font")
    local path = key ~= "__global" and EllesmereUI.ResolveFontName(key)
    return path or EllesmereUI.GetFontPath("extras")
end

local function TextOutline()
    local mode = Get("outlineMode")
    if mode == "outline" then return EllesmereUI.SlugFlag("OUTLINE, SLUG") end
    if mode == "thick" then return EllesmereUI.SlugFlag("THICKOUTLINE, SLUG") end
    if mode == "none" then return "" end
    return EllesmereUI.GetFontOutlineFlag("extras")
end

local function StyleFont(fs, font, flag)
    -- An empty flag means Drop Shadow, which only renders through the font object.
    EllesmereUI.PrimeFontShadow(fs, flag == "")
    fs:SetFont(font, Get("textSize"), flag)
end

local function HeaderHeight()
    return Get("showHeader") and Get("barHeight") or 0
end

local function StyleRow(row, font, flag, texture)
    row:SetStatusBarTexture(texture)
    StyleFont(row.name, font, flag)
    StyleFont(row.value, font, flag)
end

local function CreateRow(i)
    local row = CreateFrame("StatusBar", nil, frame)
    row:SetMinMaxValues(0, 1)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetPoint("LEFT", row, "LEFT", TEXT_PAD, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.value = row:CreateFontString(nil, "OVERLAY")
    row.value:SetPoint("RIGHT", row, "RIGHT", -TEXT_PAD, 0)
    row.value:SetJustifyH("RIGHT")
    row.name:SetPoint("RIGHT", row.value, "LEFT", -TEXT_PAD, 0)
    rows[i] = row
    StyleRow(row, TextFont(), TextOutline(),
        EllesmereUI.ResolveTexturePath(BAR_TEXTURES, Get("texture"), "Interface\\Buttons\\WHITE8x8"))
    return row
end

local function LayoutRows(count)
    local bh, gap, w = Get("barHeight"), Get("spacing"), Get("width")
    local top = HeaderHeight()
    frame:SetSize(w, math.max(top + count * (bh + gap) - (count > 0 and gap or 0), top, 1))
    for i = 1, count do
        local row = rows[i] or CreateRow(i)
        row:ClearAllPoints()
        local off = top + (i - 1) * (bh + gap)
        if Get("growUp") then
            row:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, off)
        else
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -off)
        end
        row:SetSize(w, bh)
        row:Show()
    end
    for i = count + 1, #rows do rows[i]:Hide() end
    frame.header:ClearAllPoints()
    frame.header:SetPoint(Get("growUp") and "BOTTOMLEFT" or "TOPLEFT")
    frame.header:SetSize(w, math.max(top, 1))
    frame.header:SetShown(top > 0)
end

local function ApplyStyle()
    if not frame then return end
    local PP = EllesmereUI.PP
    local font, flag = TextFont(), TextOutline()
    local texture = EllesmereUI.ResolveTexturePath(BAR_TEXTURES, Get("texture"), "Interface\\Buttons\\WHITE8x8")
    frame.bg:SetColorTexture(0, 0, 0, Get("bgA"))
    frame.header.bg:SetColorTexture(0, 0, 0, math.min(1, Get("bgA") + 0.2))
    StyleFont(frame.header.text, font, flag)
    for i = 1, #rows do StyleRow(rows[i], font, flag, texture) end
    local bs = Get("borderSize")
    if bs > 0 then
        PP.UpdateBorder(frame, bs, Get("borderR"), Get("borderG"), Get("borderB"), 1)
        PP.ShowBorder(frame)
    else
        PP.HideBorder(frame)
    end
end

local function ApplyPosition()
    local pos = Read().pos
    frame:ClearAllPoints()
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 400, -100)
    end
end

local function CreateMeter()
    if frame then return end
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(Get("width"), 1)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.header = CreateFrame("Frame", nil, frame)
    frame.header.bg = frame.header:CreateTexture(nil, "BACKGROUND")
    frame.header.bg:SetAllPoints()
    frame.header.text = frame.header:CreateFontString(nil, "OVERLAY")
    frame.header.text:SetPoint("LEFT", TEXT_PAD, 0)
    frame.header.text:SetPoint("RIGHT", -TEXT_PAD, 0)
    frame.header.text:SetJustifyH("LEFT")
    frame.header.text:SetWordWrap(false)
    EllesmereUI.PP.CreateBorder(frame, 0, 0, 0, 1, 1, "OVERLAY", 2)
    frame:Hide()
    ApplyStyle()
    ApplyPosition()
end

-------------------------------------------------------------------------------
--  Threat data
-------------------------------------------------------------------------------
local function ClassColor(unit)
    if not UnitIsPlayer(unit) then return PET_COLOR end
    local _, classFile = UnitClass(unit)
    return classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile] or FALLBACK_COLOR
end

local count = 0

local function Add(unit, mob)
    if not UnitExists(unit) then return end
    local tanking, _, scaled, _, raw = UnitDetailedThreatSituation(unit, mob)
    if not (Readable(raw) and Readable(scaled) and Readable(tanking)) or raw <= 0 then return end
    count = count + 1
    local e = entries[count]
    if not e then e = {}; entries[count] = e end
    e.unit, e.name, e.raw, e.scaled, e.tanking = unit, UnitName(unit), raw, scaled, tanking
    e.isPlayer, e.pull = UnitIsUnit(unit, "player"), nil
    list[#list + 1] = e
end

local function Collect(mob)
    count = 0
    for i = #list, 1, -1 do list[i] = nil end
    local pets = not Get("ignorePets")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            Add("raid" .. i, mob)
            if pets then Add("raidpet" .. i, mob) end
        end
    else
        Add("player", mob)
        if pets then Add("pet", mob) end
        for i = 1, GetNumSubgroupMembers() do
            Add("party" .. i, mob)
            if pets then Add("partypet" .. i, mob) end
        end
    end
end

local function ByThreat(a, b) return a.raw > b.raw end

-- Where you pull aggro: scaled percent is threat against your own pull line
-- (100 = you take it), so the line is your threat scaled up to 100.
local function AddPullEntry(me)
    if not (me and not me.tanking and me.scaled > 0) then return end
    count = count + 1
    local e = entries[count]
    if not e then e = {}; entries[count] = e end
    e.unit, e.name, e.raw, e.scaled, e.tanking = nil, EllesmereUI.L("Pull Aggro"), me.raw * 100 / me.scaled, 100, false
    e.isPlayer, e.pull = false, true
    list[#list + 1] = e
end

-------------------------------------------------------------------------------
--  Display
-------------------------------------------------------------------------------
local function RowColor(e)
    if e.pull then return Get("pullR"), Get("pullG"), Get("pullB") end
    if e.isPlayer and Get("playerColorOn") then return Get("playerR"), Get("playerG"), Get("playerB") end
    if e.tanking and Get("tankColorOn") then return Get("tankR"), Get("tankG"), Get("tankB") end
    local c = ClassColor(e.unit)
    return c.r, c.g, c.b
end

local function ValueText(e)
    local v, p = Get("showValue"), Get("showPercent") and not e.pull
    if v and p then return string.format("%s  %d%%", ShortThreat(e.raw), e.scaled) end
    if v then return ShortThreat(e.raw) end
    if p then return string.format("%d%%", e.scaled) end
    return ""
end

local function Render(shown, top, title)
    LayoutRows(shown)
    -- Names go straight to SetText: a name can come back secret, and a secret
    -- cannot be tested for nil.
    frame.header.text:SetText(title)
    local alpha = Get("barOpacity") / 100
    for i = 1, shown do
        local e, row = list[i], rows[i]
        local r, g, b = RowColor(e)
        row:SetStatusBarColor(r, g, b, alpha)
        row.bg:SetColorTexture(r * 0.25, g * 0.25, b * 0.25, alpha * 0.6)
        row:SetValue(top > 0 and e.raw / top or 0)
        row.name:SetText(e.name)
        row.value:SetText(ValueText(e))
    end
end

local function CheckWarning(me)
    if not Get("warnSound") then return end
    local over = me and not me.tanking and me.scaled >= Get("warnAt")
        and not (Get("warnSkipTank") and PlayerIsTank())
    if over and not warned then
        local paths = EllesmereUI._groupDeathSoundPaths
        local key = Get("warnSoundKey")
        if paths and paths[key] and EllesmereUI._PlayLSMSound then EllesmereUI._PlayLSMSound(paths[key]) end
    end
    warned = over
end

local function SamplePreview()
    count = 0
    for i = #list, 1, -1 do list[i] = nil end
    local samples = { { "player", 1000000, 100, true }, { "player", 820000, 82 }, { "player", 610000, 61 },
        { "player", 340000, 34 } }
    for i, s in ipairs(samples) do
        count = count + 1
        local e = entries[count] or {}
        entries[count] = e
        e.unit, e.name, e.raw, e.scaled, e.tanking = s[1], i == 1 and EllesmereUI.L("Tank") or UnitName("player"),
            s[2], s[3], s[4] == true
        e.isPlayer, e.pull = i == 2, false
        list[#list + 1] = e
    end
    AddPullEntry(list[2])
    table.sort(list, ByThreat)
    Render(math.min(#list, Get("maxBars")), list[1].raw, EllesmereUI.L("Threat Meter"))
end

local Update

-- UNIT_THREAT_LIST_UPDATE names a real unit token (target, a nameplate, a boss),
-- never targettarget, so while the meter follows a friendly target's enemy
-- nothing reports that mob's threat moving. Re-read on a short interval in that
-- one case, and only in combat.
local function SetFollow(on)
    if on and not followTicker then
        followTicker = C_Timer.NewTicker(FOLLOW_INTERVAL, function() Update() end)
    elseif not on and followTicker then
        followTicker:Cancel()
        followTicker = nil
    end
end

function Update()
    pendingUpdate = false
    if not frame then return end
    if not Enabled() then
        SetFollow(false)
        frame:Hide()
        return
    end
    if previewUntil then
        if GetTime() < previewUntil then
            SetFollow(false)
            SamplePreview()
            frame:Show()
            return
        end
        previewUntil = nil
    end
    local vis = EllesmereUI.EvalVisibility(Read())
    local mob = vis == true and ThreatMob()
    SetFollow(mob == "targettarget" and InCombatLockdown())
    if mob then Collect(mob) end
    if not mob or #list == 0 then
        warned = false
        frame:Hide()
        return
    end
    local me
    for i = 1, #list do
        if list[i].isPlayer then me = list[i] break end
    end
    CheckWarning(me)
    if Get("pullBar") then AddPullEntry(me) end
    table.sort(list, ByThreat)
    Render(math.min(#list, Get("maxBars")), list[1].raw, UnitName(mob))
    frame:Show()
end

-- Threat updates arrive per unit, so a raid pull is a burst; one redraw per
-- short window covers the whole burst.
local function RequestUpdate()
    if pendingUpdate then return end
    pendingUpdate = true
    C_Timer.After(UPDATE_DELAY, Update)
end

local function Apply()
    if Enabled() then
        CreateMeter()
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", RequestUpdate)
        end
        events:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
        events:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterUnitEvent("UNIT_TARGET", "target")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        EllesmereUI.UnregisterVisibilityUpdater(RequestUpdate)
        EllesmereUI.RegisterVisibilityUpdater(RequestUpdate)
        ApplyStyle()
        RequestUpdate()
    else
        if events then events:UnregisterAllEvents() end
        EllesmereUI.UnregisterVisibilityUpdater(RequestUpdate)
        SetFollow(false)
        warned = false
        if frame then frame:Hide() end
    end
end

-- Options-page entry points.
EllesmereUI._ThreatMeter = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    ApplyStyle = function()
        ApplyStyle()
        if frame then Update() end
    end,
    ApplyPosition = function() if frame then ApplyPosition() end end,
    textures = { lookup = BAR_TEXTURES, names = BAR_TEXTURE_NAMES, order = BAR_TEXTURE_ORDER },
    Preview = function()
        CreateMeter()
        previewUntil = GetTime() + PREVIEW_SECONDS
        Update()
        C_Timer.After(PREVIEW_SECONDS, Update)
    end,
}

local function Resized()
    ApplyStyle()
    Update()
    if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
        EllesmereUI.RepositionBarToMover("EUI_ThreatMeter")
    end
end

local function RegisterUnlock()
    local MK = EllesmereUI.MakeUnlockElement
    local PPs = EllesmereUI.PP
    EllesmereUI:RegisterUnlockElements({
        MK({
            key      = "EUI_ThreatMeter",
            label    = "Threat Meter",
            group    = "Quality of Life",
            order    = 731,
            isHidden = function() return not Enabled() end,
            -- Nothing is built while the feature is off (the unlock core calls
            -- getFrame / applyPos for every element at each login).
            getFrame = function()
                if not Enabled() then return nil end
                CreateMeter()
                return frame
            end,
            getSize = function()
                local n = math.min(5, Get("maxBars"))
                return Get("width"), HeaderHeight() + n * (Get("barHeight") + Get("spacing")) - Get("spacing")
            end,
            setWidth = function(_, w)
                Cfg().width = math.max(80, PPs.Snap(w))
                Resized()
            end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                Cfg().pos = { point = point, relPoint = relPoint, x = x, y = y }
                if frame and not EllesmereUI._unlockActive then ApplyPosition() end
            end,
            loadPos = function()
                local pos = Read().pos
                if pos and pos.point then return pos end
                return { point = "CENTER", relPoint = "CENTER", x = 400, y = -100 }
            end,
            clearPos = function()
                Cfg().pos = nil
                if frame then ApplyPosition() end
            end,
            applyPos = function()
                if not Enabled() then return end
                CreateMeter()
                ApplyPosition()
            end,
        }),
    })
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
    RegisterUnlock()
end)
