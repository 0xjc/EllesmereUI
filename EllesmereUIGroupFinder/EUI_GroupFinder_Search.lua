if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EUI_GroupFinder_Search.lua: the premade search panel (rows, menus, filters,
-- list tweaks, bottom buttons).
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local CM = EllesmereUI

local DUNGEONS = GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2
local DELVES   = GROUP_FINDER_CATEGORY_ID_DELVES or 121
local RAIDS    = GROUP_FINDER_CATEGORY_ID_RAIDS or 3
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0
local MEDIA    = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
local COG_TEX  = MEDIA .. "cogs.png"
local X_TEX    = MEDIA .. "eui-close.png"
local RAID_TEX = MEDIA .. "raid-tools.png"

local ROW1_Y   = -42  -- row 1 centre
local ROW1_H    = 24
local BTN       = 28  -- row 2 square size (Layout resizes it)
local DIFF_W    = 110
local SQ_GAP    = 3  -- gap between everything
local ROW2_Y    = ROW1_Y - ROW1_H / 2 - SQ_GAP
local CD_SEARCH = 2
-- Bottom buttons sit this far up (Blizzard uses 4).
local BOTTOM_Y = 8
local CD_FAILED = 6

local FFD = setmetatable({}, { __mode = "k" })
-- Shared helpers (Lua 5.1 caps a chunk at 200 locals).
local XF = {}
-- Grey for our white glyphs, about what Blizzard's refresh icon reads at.
XF.GLYPH = 0.78
-- Plain-text tooltip; extra lines are dimmed.
function XF.Tip(owner, title, ...)
    local text = title
    for i = 1, select("#", ...) do
        local line = select(i, ...)
        if line then
            -- lines with their own colour keep it
            if line:sub(1, 2) == "|c" then text = text .. "\n" .. line
            else text = text .. "\n|cffb3b3b3" .. line .. "|r" end
        end
    end
    XF.tipOwner = owner
    if CM.ShowWidgetTooltip then
        CM.ShowWidgetTooltip(owner, text)
    else
        GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end
end
function XF.ClassLine(classFile, text)
    local c = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile)
    return c and c:WrapTextInColorCode(text) or text
end
function XF.Untip()
    XF.tipOwner = nil
    if CM.HideWidgetTooltip then CM.HideWidgetTooltip() else GameTooltip:Hide() end
end
XF.PERSON_ATLAS = "groupfinder-icon-friend"

local SP
local row, diffBtn, menu, resetBtn, refreshBtn, gfFont
local pending = false  -- filters changed since the last search
local cdUntil = 0
local squares = {}
local dungeons  -- this season's dungeons
local delves  -- Delves category
local delveByActivity  -- activityID -> groupID, tier
local bountiful = {}  -- delve name -> bountiful this week
local delveSquares = {}
local tierBtn, tierMenu
local bosses  -- current raid bosses
local raidByActivity  -- activityID -> journal instance
local bossSquares = {}
local raidList  -- current raids, Blizzard's order
local raidBtn, raidMenu
local raidDiffMenu

local DIFFS = {
    { key = "difficultyNormal",     label = PLAYER_DIFFICULTY1 or "Normal" },
    { key = "difficultyHeroic",     label = PLAYER_DIFFICULTY2 or "Heroic" },
    { key = "difficultyMythic",     label = PLAYER_DIFFICULTY6 or "Mythic" },
    { key = "difficultyMythicPlus", label = PLAYER_DIFFICULTY_MYTHIC_PLUS or "Mythic+" },
}

local function Cfg() return ns.Cfg and ns.Cfg() or {} end
local function Accent()
    local a = CM.ELLESMERE_GREEN
    if a then return a.r, a.g, a.b end
    return 0.89, 0.83, 0.69
end
local function Font() return (CM.GetFontPath and CM.GetFontPath()) or STANDARD_TEXT_FONT end
-- The Blizzard Skin's window engine, so our buttons follow its theme.
local function Skin()
    local m = CM._ModuleNS and CM._ModuleNS.EllesmereUIBlizzardSkin
    return m and m.WSkin
end
local function ThemeBorder()
    local S = Skin()
    local T = S and S.Theme
    if T and T.brdR then return T.brdR, T.brdG, T.brdB, T.brdA end
    return 0.2, 0.2, 0.2, 1
end
ns.Skin, ns.ThemeBorder = Skin, ThemeBorder  -- the Applications card uses these too
ns.BOTTOM_Y = BOTTOM_Y
local function SetBorderColor(frame, r, g, b, a)
    local PP = CM.PanelPP or CM.PP
    if PP and PP.SetBorderColor then PP.SetBorderColor(frame, r, g, b, a) end
end

-------------------------------------------------------------------------------
-- Season dungeons and the advanced filter
-------------------------------------------------------------------------------
local function GroupsFor(filter)
    local ok, groups = pcall(C_LFGList.GetAvailableActivityGroups, DUNGEONS, filter)
    return (ok and type(groups) == "table") and groups or {}
end

local function SeasonFilter()
    local F = Enum.LFGListFilter
    return bit.bor(F.CurrentSeason, F.PvE)
end

-- Every dungeon group Blizzard's own 'all dungeons' filter holds.
local function AllDungeonGroups()
    local F = Enum.LFGListFilter
    local all = {}
    for _, g in ipairs(GroupsFor(SeasonFilter())) do all[#all + 1] = g end
    for _, g in ipairs(GroupsFor(bit.bor(F.CurrentExpansion, F.NotCurrentSeason, F.PvE))) do all[#all + 1] = g end
    return all
end

local function BuildDungeons()
    local CMode = C_ChallengeMode
    local maps = CMode and CMode.GetMapTable and CMode.GetMapTable()
    if type(maps) ~= "table" or #maps == 0 then return nil end
    local byMap, byName = {}, {}
    for _, gid in ipairs(GroupsFor(SeasonFilter())) do
        local gname = C_LFGList.GetActivityGroupInfo(gid)
        if gname then byName[gname] = gid end
        for _, aid in ipairs(C_LFGList.GetAvailableActivities(DUNGEONS, gid) or {}) do
            local info = C_LFGList.GetActivityInfoTable(aid)
            if info and info.mapID then byMap[info.mapID] = gid end
        end
    end
    local out = {}
    for _, cmID in ipairs(maps) do
        local name, _, _, tex, _, mapID = CMode.GetMapUIInfo(cmID)
        local gid = (mapID and byMap[mapID]) or (name and byName[name])
        if gid then out[#out + 1] = { cmID = cmID, name = name, icon = tex, groupID = gid } end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return #out > 0 and out or nil
end

local function Contains(list, v)
    for i = 1, #list do if list[i] == v then return i end end
    return nil
end

-- No dungeon restriction: empty list or every season dungeon.
local function DungeonsDefault(f)
    local acts = f.activities or {}
    if #acts == 0 or not dungeons then return true end
    for _, d in ipairs(dungeons) do
        if not Contains(acts, d.groupID) then return false end
    end
    return true
end

local function DiffAllOrNone(f)
    local n = 0
    for _, d in ipairs(DIFFS) do if f[d.key] then n = n + 1 end end
    return n == 0 or n == #DIFFS, n
end

-- Same check Blizzard uses for its red reset X.
local function FilterDefault(f)
    return DungeonsDefault(f) and DiffAllOrNone(f)
        and not (f.needsTank or f.needsHealer or f.needsDamage or f.needsMyClass or f.hasTank or f.hasHealer
            or (f.minimumRating or 0) ~= 0)
end

local Paint, PaintRefresh

-- Filter changes only save; the search waits for Search Again so picking a few
-- dungeons is one search.
local function Apply(f)
    C_LFGList.SaveAdvancedFilter(f)
    pending = true
    Paint()
    PaintRefresh()
end

local function ToggleDungeon(gid)
    local f = C_LFGList.GetAdvancedFilter()
    if DungeonsDefault(f) then
        f.activities = { gid }
    else
        local acts = f.activities
        local at = Contains(acts, gid)
        if at then table.remove(acts, at) else acts[#acts + 1] = gid end
        -- Nothing or everything picked means all dungeons.
        if #acts == 0 or DungeonsDefault(f) then f.activities = AllDungeonGroups() end
    end
    Apply(f)
end

local function SetDifficulty(key, on)
    local f = C_LFGList.GetAdvancedFilter()
    local _, n = DiffAllOrNone(f)
    if n == 0 then for _, d in ipairs(DIFFS) do f[d.key] = true end end
    if key then f[key] = on else for _, d in ipairs(DIFFS) do f[d.key] = true end end
    local _, after = DiffAllOrNone(f)
    if after == 0 then for _, d in ipairs(DIFFS) do f[d.key] = true end end
    Apply(f)
end

-------------------------------------------------------------------------------
-- Difficulty menu
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Region filter (US region only)
-------------------------------------------------------------------------------
local REGIONS = {
    { key = "na",  label = "North America" },
    { key = "oce", label = "Oceanic" },
    { key = "la",  label = "Latin America" },
    { key = "br",  label = "Brazil" },
}
local REALM_REGION = {}
for region, list in pairs({
    oce = { "amanthul", "barthilas", "caelestrasz", "dathremar", "dreadmaul", "frostmourne",
            "gundrak", "jubeithos", "khazgoroth", "nagrand", "saurfang", "thaurissan" },
    br  = { "azralon", "gallywix", "goldrinn", "nemesis", "tolbarad" },
    la  = { "drakkari", "quelthalas", "ragnaros" },
}) do
    for _, realm in ipairs(list) do REALM_REGION[realm] = region end
end

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end
local function RegionsAvailable() return GetCurrentRegion and GetCurrentRegion() == 1 end

local function ChosenRegions()
    local c = Cfg()
    return type(c.regions) == "table" and c.regions or nil
end

local function RegionFilterActive()
    local r = RegionsAvailable() and ChosenRegions()
    if not r then return false end
    local n = 0
    for _, d in ipairs(REGIONS) do if r[d.key] then n = n + 1 end end
    return n > 0 and n < #REGIONS
end

local function ResultInfo(resultID)
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info or IsSecret(info) or (canaccesstable and not canaccesstable(info)) then return nil end
    return info
end

local function LeaderRegion(resultID)
    local info = ResultInfo(resultID)
    local leader = info and info.leaderName
    if not leader or IsSecret(leader) then return nil end
    local realm = leader:match("%-(.+)$") or (GetNormalizedRealmName and GetNormalizedRealmName())
    if not realm or IsSecret(realm) then return nil end
    return REALM_REGION[(realm:gsub("[^%a]", "")):lower()] or "na"
end

-------------------------------------------------------------------------------
-- Delves: a square per delve, gold underline for Bountiful ones, plus a Tier
-- menu.
-------------------------------------------------------------------------------
local SKIP_WORDS = { the = true, of = true, a = true, an = true }

-- Up to 3 letters: word initials ('The Gulf of Memory' -> GM), or the first
-- three letters of a single word.
local function Abbrev(name)
    local initials = {}
    for word in name:gmatch("[^%s%-'\226\128\153:]+") do
        if not SKIP_WORDS[word:lower()] then
            initials[#initials + 1] = word
        end
    end
    local firstChar = function(w) return w:match("^[%z\1-\127\194-\244][\128-\191]*") or "" end
    if #initials == 1 then
        local w, out, n = initials[1], {}, 0
        for ch in w:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            n = n + 1
            out[n] = (n == 1) and ch:upper() or ch:lower()
            if n == 3 then break end
        end
        return table.concat(out)
    end
    local out = {}
    for i = 1, math.min(3, #initials) do out[i] = firstChar(initials[i]):upper() end
    return table.concat(out)
end

-- Tier from the activity name; '?' is 12 and '??' is 13.
function XF.TierOf(fullName)
    if type(fullName) ~= "string" or IsSecret(fullName) then return nil end
    local n = tonumber(fullName:match("(%d+)%D*$"))
    if n then return n end
    local q = fullName:match("(%?+)[^%?]*$")
    if q == "??" then return 13 elseif q == "?" then return 12 end
    return nil
end
XF.TierLabel = function(t)
    if t == 12 then return "Tier ?" elseif t == 13 then return "Tier ??" end
    return "Tier " .. t
end

local function BuildDelves()
    local F = Enum.LFGListFilter
    local seen, list, byAct = {}, {}, {}
    for _, filter in ipairs({ bit.bor(F.CurrentExpansion, F.PvE), bit.bor(F.CurrentSeason, F.PvE) }) do
        local ok, groups = pcall(C_LFGList.GetAvailableActivityGroups, DELVES, filter)
        for _, gid in ipairs(ok and type(groups) == "table" and groups or {}) do
            if not seen[gid] then
                seen[gid] = true
                local name = C_LFGList.GetActivityGroupInfo(gid)
                if name then
                    list[#list + 1] = { groupID = gid, name = name, abbr = Abbrev(name) }
                    for _, aid in ipairs(C_LFGList.GetAvailableActivities(DELVES, gid) or {}) do
                        local info = C_LFGList.GetActivityInfoTable(aid)
                        local tier = XF.TierOf(info and info.fullName)
                        byAct[aid] = { groupID = gid, tier = tier }
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    if #list == 0 then return nil end
    return list, byAct
end

-- Bountiful delves this week: walk every zone under the world map, check its
-- delve pins for the bountiful art. Only this season's delves count. At most
-- once a minute.
XF.bountifulScanAt = nil
local function ScanBountiful()
    local now = GetTime()
    if XF.bountifulScanAt and now - XF.bountifulScanAt < 60 then return end
    local POI, MAP = C_AreaPoiInfo, C_Map
    if not (POI and POI.GetDelvesForMap and POI.GetAreaPOIInfo and MAP and MAP.GetMapChildrenInfo) then return end
    local season = {}
    for _, d in ipairs(delves or {}) do season[d.name] = true end
    if not next(season) then return end
    XF.bountifulScanAt = now
    wipe(bountiful)
    local okZones, zones = pcall(MAP.GetMapChildrenInfo, 946, Enum.UIMapType.Zone, true)
    for _, zone in ipairs(okZones and type(zones) == "table" and zones or {}) do
        local okPins, pins = pcall(POI.GetDelvesForMap, zone.mapID)
        for _, poiID in ipairs(okPins and type(pins) == "table" and pins or {}) do
            local pin = POI.GetAreaPOIInfo(zone.mapID, poiID)
            local name, art = pin and pin.name, pin and pin.atlasName
            if name and season[name] and type(art) == "string" and art:find("bountiful", 1, true) then
                bountiful[name] = true
            end
        end
    end
end

local function ChosenDelves()
    local c = Cfg()
    return type(c.delves) == "table" and next(c.delves) and c.delves or nil
end

local MAX_TIER = 13  -- 1-11, then ? and ??

local function ChosenTiers()
    local t = Cfg().delveTiers
    if type(t) ~= "table" then return nil end
    local n = 0
    for i = 1, MAX_TIER do if t[i] then n = n + 1 end end
    return (n > 0 and n < MAX_TIER) and t or nil, n
end

local function DelveFilterActive()
    return SP and SP.categoryID == DELVES and (ChosenDelves() ~= nil or ChosenTiers() ~= nil) or false
end

-- Delve / tier filter (unknown activity passes).
local function DelveKeep(resultID)
    local info = ResultInfo(resultID)
    local acts = info and info.activityIDs
    local act = type(acts) == "table" and not IsSecret(acts) and acts[1]
    local d = act and not IsSecret(act) and delveByActivity and delveByActivity[act]
    if not d then return true end
    local chosen = ChosenDelves()
    if chosen and not chosen[d.groupID] then return false end
    local tiers = ChosenTiers()
    if tiers and d.tier and not tiers[d.tier] then return false end
    return true
end

-------------------------------------------------------------------------------
-- Raid bosses: a square per boss with its journal portrait.
-------------------------------------------------------------------------------
local function RaidsCurrent()
    local f = SP and SP.filters
    return SP and SP.categoryID == RAIDS and type(f) == "number"
        and bit.band(f, Enum.LFGListFilter.Recommended) ~= 0 or false
end

-- Fallback: newest tier's journal raids by name.
local function JournalRaidsByName()
    local out = {}
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then return out end
    local prev = EJ_GetCurrentTier and EJ_GetCurrentTier()
    EJ_SelectTier(EJ_GetNumTiers())
    for i = 1, 20 do
        local jid, name = EJ_GetInstanceByIndex(i, true)
        if not jid then break end
        out[name] = jid
    end
    if prev then EJ_SelectTier(prev) end
    return out
end

local function RaidGroups()
    local F = Enum.LFGListFilter
    local ok, groups = pcall(C_LFGList.GetAvailableActivityGroups, RAIDS, bit.bor(F.Recommended, F.PvE))
    return ok and type(groups) == "table" and groups or {}
end

local function JournalInstance(info, groupName, byName)
    local CEJ = C_EncounterJournal
    local jid = info and info.mapID and CEJ and CEJ.GetInstanceForGameMap and CEJ.GetInstanceForGameMap(info.mapID)
    if jid then return jid end
    return groupName and byName()[groupName] or nil
end

-- A journal raid's bosses.
local RAID_DIFFS = { 14, 15, 16, 17 }
local function Encounters(jid)
    local out = {}
    if not (EJ_SelectInstance and EJ_GetEncounterInfoByIndex) then return out end
    local EJ = EncounterJournal
    local prevInst = EJ and EJ.instanceID
    local prevDiff = EJ_GetDifficulty and EJ_GetDifficulty()
    EJ_SelectInstance(jid)
    for _, diff in ipairs(RAID_DIFFS) do
        if EJ_SetDifficulty and EJ_IsValidInstanceDifficulty and EJ_IsValidInstanceDifficulty(diff) then
            EJ_SetDifficulty(diff)
            break
        end
    end
    for i = 1, 30 do
        local name, _, encID = EJ_GetEncounterInfoByIndex(i)
        if not name then break end
        local icon = EJ_GetCreatureInfo and select(5, EJ_GetCreatureInfo(1, encID))
        out[#out + 1] = { key = encID, name = name, icon = icon }
    end
    if prevInst then EJ_SelectInstance(prevInst) end
    if prevDiff and EJ_SetDifficulty then EJ_SetDifficulty(prevDiff) end
    return out
end

-- Current raid bosses in Blizzard's raid order. Nil until the journal has data.
local function BuildBosses()
    if not (EJ_SelectInstance and EJ_GetEncounterInfoByIndex) then return nil end
    local list, byAct, seen, raids = {}, {}, {}, {}
    local names
    local function byName() names = names or JournalRaidsByName(); return names end
    for _, gid in ipairs(RaidGroups()) do
        local groupName = C_LFGList.GetActivityGroupInfo(gid)
        for _, aid in ipairs(C_LFGList.GetAvailableActivities(RAIDS, gid) or {}) do
            local info = C_LFGList.GetActivityInfoTable(aid)
            local jid = JournalInstance(info, groupName, byName)
            if jid then
                byAct[aid] = jid
                if not seen[jid] then
                    seen[jid] = true
                    local raidName = EJ_GetInstanceInfo and EJ_GetInstanceInfo(jid)
                    local n = #list
                    for _, b in ipairs(Encounters(jid)) do
                        b.raid, b.raidName = jid, raidName
                        list[#list + 1] = b
                    end
                    if #list > n then raids[#raids + 1] = { jid = jid, name = raidName or groupName or "?" } end
                end
            end
        end
    end
    if #list == 0 then return nil end
    return list, byAct, raids
end

-- Raids are shown unless hidden in the raid menu, so new raids show up by
-- default.
local function RaidShown(jid)
    local h = Cfg().raidsHidden
    if not (type(h) == "table" and h[jid]) then return true end
    for _, raid in ipairs(raidList or {}) do
        if not h[raid.jid] then return false end
    end
    return true
end

function XF.AnyRaidHidden()
    for _, raid in ipairs(raidList or {}) do
        if not RaidShown(raid.jid) then return true end
    end
    return false
end

local function ChosenBosses()
    local c = Cfg()
    return type(c.bosses) == "table" and next(c.bosses) and c.bosses or nil
end

local function BossFilterActive()
    return RaidsCurrent() and ChosenBosses() ~= nil or false
end

local function BossKeep(resultID)
    local info = ResultInfo(resultID)
    local acts = info and info.activityIDs
    local act = type(acts) == "table" and not IsSecret(acts) and acts[1]
    local raid = act and not IsSecret(act) and raidByActivity and raidByActivity[act]
    if not raid then return true end
    local done = C_LFGList.GetSearchResultEncounterInfo(resultID)
    if done and (IsSecret(done) or (canaccesstable and not canaccesstable(done))) then return true end
    local dead = {}
    for _, name in ipairs(done or {}) do
        if IsSecret(name) then return true end
        dead[name] = true
    end
    local chosen, wanted = ChosenBosses(), false
    for _, b in ipairs(bosses or {}) do
        if b.raid == raid and chosen[b.key] then
            if dead[b.name] then return false end
            wanted = true
        end
    end
    return wanted
end

-------------------------------------------------------------------------------
-- Raids: difficulty and world bosses
-------------------------------------------------------------------------------
local RAID_DIFFS_MENU = {
    { key = "normal", label = PLAYER_DIFFICULTY1 or "Normal" },
    { key = "heroic", label = PLAYER_DIFFICULTY2 or "Heroic" },
    { key = "mythic", label = PLAYER_DIFFICULTY6 or "Mythic" },
}

local function ChosenRaidDiffs()
    local t = Cfg().raidDiffs
    if type(t) ~= "table" then return nil, 0 end
    local n = 0
    for _, d in ipairs(RAID_DIFFS_MENU) do if t[d.key] then n = n + 1 end end
    return (n > 0 and n < #RAID_DIFFS_MENU) and t or nil, n
end

local function HideWorldBosses() return Cfg().hideWorldBosses == true end

-- Playstyles (generalPlaystyle 1-4).
local PLAYSTYLES = {
    GROUP_FINDER_GENERAL_PLAYSTYLE1 or "Learning",
    GROUP_FINDER_GENERAL_PLAYSTYLE2 or "Relaxed",
    GROUP_FINDER_GENERAL_PLAYSTYLE3 or "Competitive",
    GROUP_FINDER_GENERAL_PLAYSTYLE4 or "Carry Offered",
}

local function ChosenRaidPlaystyles()
    local t = Cfg().raidPlaystyles
    if type(t) ~= "table" then return nil, 0 end
    local n = 0
    for i = 1, #PLAYSTYLES do if t[i] then n = n + 1 end end
    return (n > 0 and n < #PLAYSTYLES) and t or nil, n
end

-- Dungeon playstyles from the advanced filter; nil when all or none.
local function DungeonPlaystyles(f)
    local n = 0
    for i = 1, #PLAYSTYLES do if f["generalPlaystyle" .. i] then n = n + 1 end end
    return (n > 0 and n < #PLAYSTYLES) and f or nil, n
end

-- Roles (the advanced filter's needs* keys).
local ROLES = {
    { key = "needsTank",   label = "Tank Available" },
    { key = "needsHealer", label = "Healer Available" },
    { key = "needsDamage", label = "Damage Available" },
}

local function ChosenRaidRoles()
    local t = Cfg().raidRoles
    return type(t) == "table" and next(t) and t or nil
end

local function DungeonRolesSet(f)
    for _, r in ipairs(ROLES) do if f[r.key] then return true end end
    return false
end

local function RaidListFilterActive()
    return SP and SP.categoryID == RAIDS
        and (ChosenRaidDiffs() ~= nil or HideWorldBosses() or ChosenRaidPlaystyles() ~= nil or ChosenRaidRoles() ~= nil
            or XF.AnyRaidHidden()) or false
end

-- difficultyID first since the is*Activity flags aren't reliable on raids.
local RAID_DIFF_BY_ID = { [14] = "normal", [15] = "heroic", [16] = "mythic", [3] = "normal", [4] = "normal", [5] = "heroic", [6] = "heroic", [9] = "normal" }
local function ActivityDiffKey(ai)
    local byID = RAID_DIFF_BY_ID[ai.difficultyID] or RAID_DIFF_BY_ID[ai.redirectedDifficultyID]
    if byID then return byID end
    if ai.isMythicActivity then return "mythic" end
    if ai.isHeroicActivity then return "heroic" end
    if ai.isNormalActivity then return "normal" end
    -- Last resort: the difficulty word in the name.
    local name = ai.fullName
    if type(name) == "string" and not IsSecret(name) then
        for key, word in pairs({ mythic = PLAYER_DIFFICULTY6 or "Mythic", heroic = PLAYER_DIFFICULTY2 or "Heroic", normal = PLAYER_DIFFICULTY1 or "Normal" }) do
            if name:find(word, 1, true) then return key end
        end
    end
    return nil
end

local function IsWorldBoss(ai)
    local g = ai and ai.groupFinderActivityGroupID
    return ai and ai.categoryID == RAIDS and (g == nil or g == 0) or false
end

local function RaidListKeep(resultID)
    local info = ResultInfo(resultID)
    local acts = info and info.activityIDs
    local act = type(acts) == "table" and not IsSecret(acts) and acts[1]
    local ai = act and not IsSecret(act) and C_LFGList.GetActivityInfoTable(act)
    if not ai then return true end
    if HideWorldBosses() and IsWorldBoss(ai) then return false end
    local jid = raidByActivity and raidByActivity[act]
    if jid and not RaidShown(jid) then return false end
    local diffs = ChosenRaidDiffs()
    local key = diffs and ActivityDiffKey(ai)
    if key and not diffs[key] then return false end
    local styles = ChosenRaidPlaystyles()
    local ps = styles and info.generalPlaystyle
    if type(ps) == "number" and not IsSecret(ps) and ps >= 1 and ps <= #PLAYSTYLES and not styles[ps] then return false end
    local roles = ChosenRaidRoles()
    if roles then
        local c = C_LFGList.GetSearchResultMemberCounts(resultID)
        if type(c) == "table" and not IsSecret(c) then
            local function num(k) local v = c[k]; return (type(v) == "number" and not IsSecret(v)) and v or nil end
            if roles.needsTank and (num("TANK_REMAINING") or 1) <= 0 then return false end
            if roles.needsHealer and (num("HEALER_REMAINING") or 1) <= 0 then return false end
            if roles.needsDamage and (num("DAMAGER_REMAINING") or 1) <= 0 then return false end
        end
    end
    return true
end

-------------------------------------------------------------------------------
-- Extra filters (Filters menu, client side)
-------------------------------------------------------------------------------
XF.LUST_CLASSES = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
XF.BREZ_CLASSES = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }
XF.COUNT_ROLES = {
    { key = "TANK",    label = "Tanks" },
    { key = "HEALER",  label = "Healers" },
    { key = "DAMAGER", label = "DPS" },
}
XF.COUNT_OPS = {
    { key = "lt", label = "<  Less Than" },
    { key = "gt", label = ">  More Than" },
    { key = "eq", label = "=  Equal To" },
}
XF.COUNT_OP_LABEL = { lt = "<", gt = ">", eq = "=" }

function XF.CountRule(role)
    local t = Cfg().roleCounts
    local r = type(t) == "table" and t[role]
    local n = type(r) == "table" and r.on and tonumber(r.n)
    if n then return r.op or "lt", n end
    return nil
end

function XF.ExtraFilterActive()
    if not SP or (SP.categoryID ~= DUNGEONS and SP.categoryID ~= RAIDS) then return false end
    local c = Cfg()
    if c.partyFit or c.notDeclined or c.hasLust or c.hasBrez then return true end
    for _, r in ipairs(XF.COUNT_ROLES) do if XF.CountRule(r.key) then return true end end
    return false
end

function XF.IsDeclinedResult(id)
    local _, status = C_LFGList.GetApplicationInfo(id)
    if IsSecret(status) then return false end
    if status == "declined" or status == "declined_full" or status == "declined_delisted" then return true end
    local info = ResultInfo(id)
    local guid = info and info.partyGUID
    local declines = LFGListFrame and LFGListFrame.declines
    return (declines and guid and not IsSecret(guid) and declines[guid]) and true or false
end

-- Your spec's role (the old GetSpecialization globals are gone).
function XF.MySpecRole()
    local SI = C_SpecializationInfo
    local spec = SI and SI.GetSpecialization and SI.GetSpecialization()
    if not spec and GetSpecialization then spec = GetSpecialization() end
    if not spec or spec == 0 then return nil end
    if SI and SI.GetSpecializationInfo then
        local _, _, _, _, role = SI.GetSpecializationInfo(spec)
        if role then return role end
    end
    return GetSpecializationRole and GetSpecializationRole(spec) or nil
end

-- Your party's roles; your spec's role if you're unassigned.
function XF.PartyNeeds()
    local need = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    local function Add(unit, isPlayer)
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
        if (not role or role == "NONE") and isPlayer then role = XF.MySpecRole() end
        if need[role] then need[role] = need[role] + 1 else need.DAMAGER = need.DAMAGER + 1 end
    end
    Add("player", true)
    if not (IsInRaid and IsInRaid()) then
        for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do Add("party" .. i) end
    end
    return need
end

function XF.ExtraKeep(id, need)
    local c = Cfg()
    if c.notDeclined and XF.IsDeclinedResult(id) then return false end
    local counts = C_LFGList.GetSearchResultMemberCounts(id)
    if type(counts) == "table" and not IsSecret(counts) then
        local function num(k)
            local v = counts[k]
            return (type(v) == "number" and not IsSecret(v)) and v or nil
        end
        if c.partyFit and need then
            for role, n in pairs(need) do
                local left = num(role .. "_REMAINING")
                if left and left < n then return false end
            end
        end
        for _, r in ipairs(XF.COUNT_ROLES) do
            local op, n = XF.CountRule(r.key)
            local have = op and num(r.key)
            if have then
                if op == "lt" and not (have < n) then return false end
                if op == "gt" and not (have > n) then return false end
                if op == "eq" and have ~= n then return false end
            end
        end
    end
    if c.hasLust or c.hasBrez then
        local info = ResultInfo(id)
        local n = info and info.numMembers
        if type(n) == "number" and not IsSecret(n) then
            local lust, brez = false, false
            for i = 1, n do
                local p = C_LFGList.GetSearchResultPlayerInfo(id, i)
                local cls = p and p.classFilename
                if cls and not IsSecret(cls) then
                    if XF.LUST_CLASSES[cls] then lust = true end
                    if XF.BREZ_CLASSES[cls] then brez = true end
                end
            end
            if c.hasLust and not lust then return false end
            if c.hasBrez and not brez then return false end
        end
    end
    return true
end

-- Results are secret in restricted content: filters stay out of it.
function XF.ResultsSecret()
    local res = SP and SP.results
    local first = type(res) == "table" and res[1]
    if not first then return false end
    if IsSecret(first) then return true end
    local info = C_LFGList.GetSearchResultInfo(first)
    if not info then return false end
    if IsSecret(info) or (canaccesstable and not canaccesstable(info)) then return true end
    return IsSecret(info.activityIDs) and true or false
end

-- Does a group pass the client-side filters? We never touch Blizzard's list,
-- groups that fail just get faded.
function XF.PassesFilters(id)
    if not SP or XF.ResultsSecret() then return true end
    local regions, delveOn, bossOn = RegionFilterActive(), DelveFilterActive(), BossFilterActive()
    local raidOn, extraOn = RaidListFilterActive(), XF.ExtraFilterActive()
    if not (regions or delveOn or bossOn or raidOn or extraOn) then return true end
    local c = Cfg()
    local _, appStatus = C_LFGList.GetApplicationInfo(id)
    if IsSecret(appStatus) then return true end
    if appStatus and appStatus ~= "none" then
        -- Applied groups stay lit, unless declined with Not Declined on.
        return not (extraOn and c.notDeclined and XF.IsDeclinedResult(id))
    end
    if regions then
        local region = LeaderRegion(id)
        if region ~= nil and not ChosenRegions()[region] then return false end
    end
    if delveOn and not DelveKeep(id) then return false end
    if bossOn and not BossKeep(id) then return false end
    if raidOn and not RaidListKeep(id) then return false end
    if extraOn and not XF.ExtraKeep(id, c.partyFit and XF.PartyNeeds() or nil) then return false end
    return true
end

-- Filters changed: redecorate the visible rows, no search.
local function Refilter()
    if not (SP and SP:IsShown()) or XF.ResultsSecret() then return end
    local box = SP.ScrollBox
    if box and box.ForEachFrame and XF.DecorateEntry then
        box:ForEachFrame(function(entry) XF.DecorateEntry(entry) end)
    end
end

-------------------------------------------------------------------------------
-- Result rows and tooltip
-------------------------------------------------------------------------------
local function Opt(key)
    local v = Cfg()[key]
    if v == nil then return true end
    return v and true or false
end

local seenResults, prevResults = {}, nil  -- latest / previous search's result IDs
local prevCategory

-- Spec icons by class + spec name (the search API only gives names).
local specIcon, specIconAny
local function SpecIcon(classFile, specName)
    if not specName then return nil end
    if not specIcon then
        specIcon, specIconAny = {}, {}
        for c = 1, (GetNumClasses and GetNumClasses() or 0) do
            local _, file, classID = GetClassInfo(c)
            if file and classID then
                specIcon[file] = {}
                for sx = 1, 5 do
                    local id, name, _, icon = GetSpecializationInfoForClassID(classID, sx)
                    if not id then break end
                    if name then
                        specIcon[file][name] = icon
                        specIconAny[name] = specIconAny[name] or icon
                    end
                end
            end
        end
    end
    return (specIcon[classFile] and specIcon[classFile][specName]) or specIconAny[specName]
end

-- Locked to this activity's instance and difficulty?
local function LockedOut(ai, resultID)
    if not (ai and ai.mapID and GetNumSavedInstances) then return false end
    for i = 1, GetNumSavedInstances() do
        local _, _, _, diffID, locked, _, _, _, _, _, numBosses, _, _, instanceID = GetSavedInstanceInfo(i)
        if locked and instanceID == ai.mapID and diffID == ai.difficultyID then
            local perBoss = (ai.maxNumPlayers or 5) > 5 and diffID ~= 16
            if not perBoss then return true end
            if not (GetSavedInstanceEncounterInfo and resultID) then return false end
            local done = C_LFGList.GetSearchResultEncounterInfo(resultID)
            if done and (IsSecret(done) or (canaccesstable and not canaccesstable(done))) then return false end
            local dead = {}
            for _, name in ipairs(done or {}) do
                if IsSecret(name) then return false end
                dead[name] = true
            end
            local anyAlive = false
            for j = 1, (tonumber(numBosses) or 0) do
                local boss, _, killed = GetSavedInstanceEncounterInfo(i, j)
                if boss and not dead[boss] then
                    anyAlive = true
                    if not killed then return false end
                end
            end
            return anyAlive
        end
    end
    return false
end

local function RatingColor(score)
    if Opt("nameColors") and RaiderIO and RaiderIO.GetScoreColor then
        local ok, r, g, b = pcall(RaiderIO.GetScoreColor, score)
        if ok and type(r) == "number" then return r, g, b end
    end
    local c = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local ROLE_BY_ATLAS
local function AtlasRole(atlas)
    if not ROLE_BY_ATLAS then
        ROLE_BY_ATLAS = {
            ["groupfinder-icon-role-micro-tank"] = "TANK",
            ["groupfinder-icon-role-micro-heal"] = "HEALER",
            ["groupfinder-icon-role-micro-dps"] = "DAMAGER",
        }
        for role, a in pairs(LFG_LIST_GROUP_DATA_ATLASES or {}) do
            if role == "TANK" or role == "HEALER" or role == "DAMAGER" then ROLE_BY_ATLAS[a] = role end
        end
    end
    return atlas and ROLE_BY_ATLAS[atlas]
end
local MISSING_ATLAS = { TANK = "groupfinder-icon-role-micro-tank", HEALER = "groupfinder-icon-role-micro-heal", DAMAGER = "groupfinder-icon-role-micro-dps" }

-- Our own drawing over one of Blizzard's role icons.
local function IconLayer(icon)
    local d = FFD[icon]
    if d then return d end
    d = {}
    FFD[icon] = d
    local f = CreateFrame("Frame", nil, icon)
    f:SetAllPoints(icon)
    f:SetFrameLevel(icon:GetFrameLevel() + 2)
    f:EnableMouse(false)
    d.frame = f
    d.circle = f:CreateTexture(nil, "ARTWORK", nil, 1)
    d.circle:SetSize(16, 16)
    d.circle:SetPoint("CENTER")
    -- Round spec icon on a 1px theme-coloured ring.
    d.ring = f:CreateTexture(nil, "ARTWORK", nil, 1)
    d.ring:SetSize(18, 18)
    d.ring:SetPoint("CENTER")
    d.spec = f:CreateTexture(nil, "ARTWORK", nil, 2)
    d.spec:SetSize(16, 16)
    d.spec:SetPoint("CENTER")
    for _, tex in ipairs({ d.ring, d.spec }) do
        local mask = f.CreateMaskTexture and f:CreateMaskTexture()
        if mask then
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(tex)
            tex:AddMaskTexture(mask)
        end
    end
    d.role = f:CreateTexture(nil, "ARTWORK", nil, 3)
    d.role:SetSize(12, 12)
    d.role:SetPoint("CENTER")
    d.full = f:CreateTexture(nil, "ARTWORK", nil, 1)
    d.full:SetAllPoints(f)
    d.crown = f:CreateTexture(nil, "OVERLAY")
    d.crown:SetAtlas("groupfinder-icon-leader", false)
    d.crown:SetSize(10, 6)
    d.crown:SetPoint("BOTTOM", icon, "TOP", 0, 1)
    return d
end

local function ClearLayer(d)
    d.circle:Hide(); d.ring:Hide(); d.spec:Hide(); d.role:Hide(); d.full:Hide(); d.crown:Hide()
end

local function DecorateIcons(entry, resultID, info, ai)
    local enum = entry.DataDisplay and entry.DataDisplay.Enumerate
    local icons = enum and enum.Icons
    if not icons then return end
    local shown = enum:IsShown()
    local crownOn, specOn, missOn = Opt("leaderCrown"), Opt("specIcons"), Opt("missingRoles")
    local disabled = (not IsSecret(info.isDelisted) and info.isDelisted) and true or false
    -- Sort members like Blizzard fills its icons (role, then class).
    local members = {}
    local n = info.numMembers
    if shown and (crownOn or specOn) and type(n) == "number" and not IsSecret(n) then
        for i = 1, n do
            local p = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
            if p and not IsSecret(p.classFilename) and not IsSecret(p.assignedRole) then
                members[#members + 1] = p
            end
        end
        -- Fallback order when an icon's role/class can't be read.
        local RANK = { TANK = 1, HEALER = 2, DAMAGER = 3 }
        for k, p in ipairs(members) do p._cmOrder = (RANK[p.assignedRole] or 4) * 100 + k end
        table.sort(members, function(x, y) return x._cmOrder < y._cmOrder end)
    end
    local maxN = ai and ai.maxNumPlayers or 0
    local counts = shown and missOn and maxN == 5 and C_LFGList.GetSearchResultMemberCounts(resultID)
    local missing
    if counts then
        missing = {}
        for _, rc in ipairs({ { "TANK", 1 }, { "HEALER", 1 }, { "DAMAGER", 3 } }) do
            for _ = 1, math.max(0, rc[2] - (counts[rc[1]] or 0)) do missing[#missing + 1] = rc[1] end
        end
    end
    local used, mi = {}, 0
    -- Right to left like Blizzard; empty slots end up leftmost.
    for i = #icons, 1, -1 do
        local icon = icons[i]
        local d = IconLayer(icon)
        ClearLayer(d)
        if shown and icon:IsShown() then
            local cc, ri, bg = icon.ClassCircle, icon.RoleIcon, icon.RoleIconWithBackground
            local ccAtlas = cc and cc:IsShown() and cc:GetAtlas()
            local riAtlas = ri and ri:IsShown() and ri:GetAtlas()
            local bgAtlas = bg and bg:IsShown() and bg:GetAtlas()
            -- Hide Blizzard's art, ours draws the icon.
            if cc then cc:SetAlpha(0) end
            if ri then ri:SetAlpha(0) end
            if bg then bg:SetAlpha(0) end
            if bgAtlas == "groupfinder-icon-emptyslot" then
                mi = mi + 1
                local role = missing and missing[mi]
                if role then
                    d.role:SetAtlas(MISSING_ATLAS[role], false)
                    d.role:SetDesaturated(true)
                    d.role:SetAlpha(0.6)
                    d.role:Show()
                else
                    d.full:SetAtlas(bgAtlas, false)
                    d.full:SetDesaturated(disabled)
                    d.full:SetAlpha(disabled and 0.5 or 1)
                    d.full:Show()
                end
            else
                local role, class
                if ccAtlas then
                    class = ccAtlas:match("^groupfinder%-icon%-class%-color%-(.+)$")
                    role = AtlasRole(riAtlas)
                else
                    role = AtlasRole(bgAtlas)
                end
                -- Match role + class, then role, then whoever's next.
                local m
                for pass = 1, 3 do
                    for k, p in ipairs(members) do
                        if not used[k] and (pass == 3 or (p.assignedRole == role
                            and (pass == 2 or not class or p.classFilename == class))) then
                            used[k] = true
                            m = p
                            break
                        end
                    end
                    if m then break end
                end
                local spec = m and specOn and m.specName and not IsSecret(m.specName) and SpecIcon(m.classFilename, m.specName)
                if ccAtlas then
                    d.circle:SetAtlas(ccAtlas, false)
                    d.circle:SetDesaturated(disabled)
                    d.circle:SetAlpha(disabled and 0.5 or 1)
                    d.circle:Show()
                    if spec then
                        d.circle:Hide()
                        local r, g, b = ThemeBorder()
                        d.ring:SetColorTexture(r, g, b, disabled and 0.5 or 1)
                        d.ring:Show()
                        d.spec:SetTexture(spec)
                        d.spec:SetDesaturated(disabled)
                        d.spec:SetAlpha(disabled and 0.5 or 1)
                        d.spec:Show()
                    elseif riAtlas then
                        d.role:SetAtlas(riAtlas, false)
                        d.role:SetDesaturated(disabled)
                        d.role:SetAlpha(disabled and 0.5 or 1)
                        d.role:Show()
                    end
                elseif bgAtlas then
                    -- Role-only icons: Blizzard's art or the spec icon.
                    if spec then
                        d.circle:Hide()
                        local r, g, b = ThemeBorder()
                        d.ring:SetColorTexture(r, g, b, disabled and 0.5 or 1)
                        d.ring:Show()
                        d.spec:SetTexture(spec)
                        d.spec:SetDesaturated(disabled)
                        d.spec:SetAlpha(disabled and 0.5 or 1)
                        d.spec:Show()
                    else
                        d.full:SetAtlas(bgAtlas, false)
                        d.full:SetDesaturated(disabled)
                        d.full:SetAlpha(disabled and 0.5 or 1)
                        d.full:Show()
                    end
                end
                if m and crownOn and m.isLeader then
                    d.crown:SetDesaturated(disabled)
                    d.crown:Show()
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Cancel Oldest Application
-------------------------------------------------------------------------------
-- The pending application closest to timing out.
function XF.OldestApplication()
    local oldest, left = nil, math.huge
    for _, id in ipairs(C_LFGList.GetApplications() or {}) do
        local _, status, pendingStatus, duration = C_LFGList.GetApplicationInfo(id)
        if status == "applied" and not pendingStatus and type(duration) == "number" and duration < left then
            oldest, left = id, duration
        end
    end
    return oldest
end

-- At the limit and hovering a group you could sign up to.
function XF.ShouldCancelOldest(resultID)
    if not Cfg().cancelOldest or not resultID or XF.ResultsSecret() then return false end
    local _, active = C_LFGList.GetNumApplications()
    if type(active) ~= "number" or active < (MAX_LFG_LIST_APPLICATIONS or 5) then return false end
    local _, status, pendingStatus = C_LFGList.GetApplicationInfo(resultID)
    if status ~= "none" or pendingStatus then return false end
    local info = ResultInfo(resultID)
    return info ~= nil and not IsSecret(info.isDelisted) and not info.isDelisted
end


local function DecorateEntry(entry)
    local resultID = entry and entry.resultID
    if not resultID or not SP then return end
    local fd = FFD[entry]
    if not fd then
        fd = {}
        FFD[entry] = fd
        local f = CreateFrame("Frame", nil, entry)
        f:SetAllPoints(entry)
        f:SetFrameLevel(entry:GetFrameLevel() + 3)
        f:EnableMouse(false)
        fd.rating = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fd.rating:SetJustifyH("RIGHT")
        -- At the application limit a left click cancels the oldest pending one.
        entry:HookScript("OnClick", function(self, button)
            if button ~= "LeftButton" or not XF.ShouldCancelOldest(self.resultID) then return end
            local oldest = XF.OldestApplication()
            if oldest then C_LFGList.CancelApplication(oldest) end
        end)
    end
    fd.rating:Hide()
    entry:SetAlpha(1)
    if XF.CancelLook then XF.CancelLook(entry) end
    -- Secret results: leave the row alone.
    if XF.ResultsSecret() then return end
    -- Filtered out: faded like the list behind an open Filters menu.
    if not XF.PassesFilters(resultID) then entry:SetAlpha(XF.DIM_ALPHA) end
    local info = ResultInfo(resultID)
    if not info then return end
    local acts = info.activityIDs
    local act = type(acts) == "table" and not IsSecret(acts) and acts[1]
    local ai = act and not IsSecret(act) and C_LFGList.GetActivityInfoTable(act)

    -- Name colour (Blizzard already reds declined ones).
    local delisted, censored = info.isDelisted, info.censored
    if IsSecret(delisted) or IsSecret(censored) then return end
    if Opt("nameColors") and entry.Name and not delisted and not censored then
        local _, appStatus = C_LFGList.GetApplicationInfo(resultID)
        local declined = appStatus == "declined" or appStatus == "declined_full" or appStatus == "declined_delisted"
        if declined or LockedOut(ai, resultID) then
            entry.Name:SetTextColor(1, 0.25, 0.25)
        elseif prevResults and not prevResults[resultID] and (appStatus == "none" or appStatus == nil) then
            entry.Name:SetTextColor(0.3, 1, 0.3)
        end
    end

    local enum = entry.DataDisplay and entry.DataDisplay.Enumerate
    local score = info.leaderOverallDungeonScore
    if Opt("leaderRating") and enum and enum:IsShown() and entry.DataDisplay:IsShown()
        and type(score) == "number" and not IsSecret(score) and score > 0 then
        local n = ai and ai.maxNumPlayers or 5
        local left = enum.Icons and enum.Icons[math.min(n, #enum.Icons)]
        if left then
            fd.rating:ClearAllPoints()
            fd.rating:SetPoint("RIGHT", left, "LEFT", -4, 0)
            fd.rating:SetText(tostring(math.floor(score)))
            fd.rating:SetTextColor(RatingColor(score))
            fd.rating:Show()
        end
    end

    -- Scale the icon strip from its right edge and trim the names by the extra
    -- width.
    local scale = math.max(1, math.min(2, (tonumber(Cfg().iconSize) or 125) / 100))
    if enum and enum.SetScale then
        enum:SetScale(scale)
        local extra = math.floor((scale - 1) * 102 + 0.5)  -- 5 icons 18 apart + 12 gap
        if extra > 0 then
            local actName = entry.ActivityName
            if actName then actName:SetWidth(176 - extra) end
            local name = entry.Name
            if name and not censored then
                local ok, w = pcall(name.GetWidth, name)
                local cap = (entry.isApplication and 165 or 176) - extra
                if ok and type(w) == "number" and not IsSecret(w) and w > cap then name:SetWidth(cap) end
            end
        end
    end

    DecorateIcons(entry, resultID, info, ai)
end
XF.DecorateEntry = DecorateEntry

-- Tooltip hint while a click would cancel your oldest application.
function XF.CancelHint(tooltip, resultID)
    if not (tooltip and tooltip.IsShown and tooltip:IsShown()) or not XF.ShouldCancelOldest(resultID) then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("Click: cancel your oldest application to sign up here", 1, 0.35, 0.35, true)
    tooltip:Show()
end

-- Member list in the tooltip, tanks then healers then dps.
local ROLE_ICON = { TANK = "groupfinder-icon-role-micro-tank", HEALER = "groupfinder-icon-role-micro-heal", DAMAGER = "groupfinder-icon-role-micro-dps" }
local function AddClassesByRole(tooltip, resultID)
    if not Opt("classTooltip") or not (tooltip and tooltip.IsShown and tooltip:IsShown()) then return end
    if XF.ResultsSecret() then return end
    local info = ResultInfo(resultID)
    if not info or IsSecret(info.isDelisted) or info.isDelisted then return end
    local acts = info.activityIDs
    local act = type(acts) == "table" and not IsSecret(acts) and acts[1]
    local ai = act and not IsSecret(act) and C_LFGList.GetActivityInfoTable(act)
    if not ai then return end
    local n = info.numMembers
    if type(n) ~= "number" or IsSecret(n) or n < 1 then return end
    local byRole = { TANK = {}, HEALER = {}, DAMAGER = {} }
    for i = 1, n do
        local p = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
        local role, class = p and p.assignedRole, p and p.classFilename
        if role and class and not IsSecret(role) and not IsSecret(class) and byRole[role] then
            local list = byRole[role]
            list[#list + 1] = p
        end
    end
    -- Dungeons/arenas already list roles and classes, so just add the names.
    local DT = Enum.LFGListDisplayType
    if DT and (ai.displayType == DT.RoleEnumerate or ai.displayType == DT.ClassEnumerate) then
        local names = {}
        for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
            for _, p in ipairs(byRole[role]) do
                local name = p.name and not IsSecret(p.name) and p.name
                if name then
                    local col = RAID_CLASS_COLORS[p.classFilename]
                    names[#names + 1] = (col and col.colorStr) and ("|c" .. col.colorStr .. name .. "|r") or name
                end
            end
        end
        if #names == 0 then return end
        tooltip:AddLine(" ")
        tooltip:AddLine("Names: " .. table.concat(names, "|cffb3b3b3,|r "), 1, 0.82, 0, true)
        tooltip:Show()
        return
    end
    local added = false
    for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        for _, p in ipairs(byRole[role]) do
            if not added then tooltip:AddLine(" "); added = true end
            local col = RAID_CLASS_COLORS[p.classFilename] or NORMAL_FONT_COLOR
            local className = (not IsSecret(p.className) and p.className)
                or (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[p.classFilename]) or p.classFilename
            local spec = p.specName and not IsSecret(p.specName) and p.specName
            local icon = CreateAtlasMarkup and CreateAtlasMarkup(ROLE_ICON[role], 12, 12) or ""
            local crown = (p.isLeader and CreateAtlasMarkup) and (" " .. CreateAtlasMarkup("groupfinder-icon-leader", 12, 8)) or ""
            local left = icon .. " " .. (spec and (spec .. " ") or "") .. className .. crown
            local name = p.name and not IsSecret(p.name) and p.name or ""
            tooltip:AddDoubleLine(left, name, col.r, col.g, col.b, col.r, col.g, col.b)
        end
    end
    if added then tooltip:Show() end
end

local ITEM_H, CHECK_SZ, ITEM_FONT = 20, 12, 9

local function ThemeFill()
    local S = Skin()
    local T = S and S.Theme
    if T and T.bgR then return T.bgR, T.bgG, T.bgB end
    return 0.08, 0.08, 0.08
end

local function MenuItem(parent, y, text, onClick)
    local item = CreateFrame("Button", nil, parent)
    item:SetHeight(ITEM_H)
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -y)
    item:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -y)
    local ar, ag, ab = Accent()
    local cb = CreateFrame("Frame", nil, item)
    cb:SetSize(CHECK_SZ, CHECK_SZ)
    cb:SetPoint("LEFT", item, "LEFT", 8, 0)
    local cbBg = cb:CreateTexture(nil, "BACKGROUND")
    cbBg:SetAllPoints()
    cbBg:SetColorTexture(0.12, 0.12, 0.12, 1)
    item.ring = CM.MakeBorder(cb, 0.25, 0.25, 0.25, 0.6, CM.PanelPP)
    item.fill = cb:CreateTexture(nil, "ARTWORK")
    item.fill:SetPoint("TOPLEFT", cb, "TOPLEFT", 3, -3)
    item.fill:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -3, 3)
    item.fill:SetColorTexture(ar, ag, ab, 1)
    local tR, tG, tB, tA = CM.TEXT_DIM_R or 0.7, CM.TEXT_DIM_G or 0.7, CM.TEXT_DIM_B or 0.7, CM.TEXT_DIM_A or 0.85
    item.label = item:CreateFontString(nil, "OVERLAY")
    item.label:SetFont(Font(), ITEM_FONT, "")
    item.label:SetPoint("LEFT", cb, "RIGHT", 7, 0)
    item.label:SetPoint("RIGHT", item, "RIGHT", -4, 0)
    item.label:SetJustifyH("LEFT")
    item.label:SetWordWrap(false)
    item.label:SetText(text)
    item.label:SetTextColor(tR, tG, tB, tA)
    local hl = item:CreateTexture(nil, "ARTWORK", nil, -1)
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0)
    item:SetScript("OnEnter", function() item.label:SetTextColor(1, 1, 1, 1); hl:SetColorTexture(1, 1, 1, CM.DD_ITEM_HL_A or 0.08) end)
    item:SetScript("OnLeave", function() item.label:SetTextColor(tR, tG, tB, tA); hl:SetColorTexture(1, 1, 1, 0) end)
    item:SetScript("OnClick", onClick)
    function item:SetChecked(on)
        local r, g, b = Accent()
        self.fill:SetShown(on)
        if on then self.ring:SetColor(r, g, b, 0.8) else self.ring:SetColor(0.25, 0.25, 0.25, 0.6) end
    end
    return item
end

-- Region section: a divider, then a toggle per region.
local function AddSection(m, y, title)
    if y > 4 then
        local div = m:CreateTexture(nil, "ARTWORK")
        div:SetHeight((CM.PP and CM.PP.mult) or 1)
        div:SetColorTexture(1, 1, 1, 0.10)
        div:SetPoint("TOPLEFT", m, "TOPLEFT", 10, -y - 3)
        div:SetPoint("TOPRIGHT", m, "TOPRIGHT", -10, -y - 3)
        y = y + 7
    else
        y = y + 2
    end
    local fs = m:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Font(), ITEM_FONT, "")
    fs:SetTextColor(0.55, 0.55, 0.55, 1)
    fs:SetJustifyH("LEFT")
    fs:SetPoint("TOPLEFT", m, "TOPLEFT", 9, -y - 2)
    fs:SetText(title)
    return y + 14
end

-- Playstyle section. Dungeons go through the advanced filter (on Search Again),
-- raids apply right away.
local function AddPlaystyleItems(m, y, raids)
    y = AddSection(m, y, "Playstyle")
    for i, label in ipairs(PLAYSTYLES) do
        m.items["style_" .. i] = MenuItem(m, y, label, function()
            if raids then
                local c = Cfg()
                if type(c.raidPlaystyles) ~= "table" then c.raidPlaystyles = {} end
                c.raidPlaystyles[i] = (not c.raidPlaystyles[i]) or nil
                local _, n = ChosenRaidPlaystyles()
                if n == #PLAYSTYLES then wipe(c.raidPlaystyles) end
                Refilter()
                Paint()
            else
                local f = C_LFGList.GetAdvancedFilter()
                local key = "generalPlaystyle" .. i
                if DungeonPlaystyles(f) == nil then
                    for k = 1, #PLAYSTYLES do f["generalPlaystyle" .. k] = (k == i) end
                else
                    f[key] = not f[key]
                    local _, n = DungeonPlaystyles(f)
                    if n == 0 or n == #PLAYSTYLES then
                        for k = 1, #PLAYSTYLES do f["generalPlaystyle" .. k] = true end
                    end
                end
                Apply(f)
            end
        end)
        y = y + ITEM_H
    end
    return y
end

local function PaintPlaystyleItems(m, raids)
    local chosen
    if raids then chosen = ChosenRaidPlaystyles() else chosen = DungeonPlaystyles(C_LFGList.GetAdvancedFilter()) end
    for i = 1, #PLAYSTYLES do
        local item = m.items["style_" .. i]
        if item then
            local on
            if raids then on = chosen ~= nil and chosen[i] == true else on = chosen ~= nil and chosen["generalPlaystyle" .. i] == true end
            item:SetChecked(on)
        end
    end
end

local function AddRoleItems(m, y, raids)
    y = AddSection(m, y, "Roles")
    for _, r in ipairs(ROLES) do
        local key = r.key
        m.items["role_" .. key] = MenuItem(m, y, r.label, function()
            if raids then
                local c = Cfg()
                if type(c.raidRoles) ~= "table" then c.raidRoles = {} end
                c.raidRoles[key] = (not c.raidRoles[key]) or nil
                Refilter()
                Paint()
            else
                local f = C_LFGList.GetAdvancedFilter()
                f[key] = not f[key]
                Apply(f)
            end
        end)
        y = y + ITEM_H
    end
    y = XF.AddFlagItem(m, y, "hasLust", "Has Bloodlust", {
        "A member whose class has one of these spells:",
        XF.ClassLine("SHAMAN", "Bloodlust / Heroism (Shaman)"), XF.ClassLine("MAGE", "Time Warp (Mage)"),
        XF.ClassLine("HUNTER", "Primal Rage (Hunter pet)"), XF.ClassLine("EVOKER", "Fury of the Aspects (Evoker)"),
        "Drums and other items don't count." })
    y = XF.AddFlagItem(m, y, "hasBrez", "Has Battle Res", {
        "A member whose class has one of these spells:",
        XF.ClassLine("DRUID", "Rebirth (Druid)"), XF.ClassLine("DEATHKNIGHT", "Raise Ally (Death Knight)"),
        XF.ClassLine("WARLOCK", "Soulstone (Warlock)"), XF.ClassLine("PALADIN", "Intercession (Paladin)"),
        "Engineering and other items don't count." })
    for _, r in ipairs(XF.COUNT_ROLES) do y = XF.AddCountRow(m, y, r.key, r.label) end
    return y
end

-- Shared Less Than / More Than / Equal To list.
function XF.OpenOpList(btn, role)
    local L = XF.opList
    if not L then
        L = CreateFrame("Frame", nil, SP)
        XF.opList = L
        L:SetFrameStrata("FULLSCREEN_DIALOG")
        L:SetFrameLevel(330)
        L:SetClampedToScreen(true)
        L:EnableMouse(true)
        L:SetWidth(92)
        local bg = L:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 1)
        CM.MakeBorder(L, ThemeBorder())
        L.items = {}
        for i, o in ipairs(XF.COUNT_OPS) do
            local it = CreateFrame("Button", nil, L)
            it:SetHeight(ITEM_H)
            it:SetPoint("TOPLEFT", L, "TOPLEFT", 1, -(2 + (i - 1) * ITEM_H))
            it:SetPoint("TOPRIGHT", L, "TOPRIGHT", -1, -(2 + (i - 1) * ITEM_H))
            it.text = it:CreateFontString(nil, "OVERLAY")
            it.text:SetFont(Font(), ITEM_FONT, "")
            it.text:SetPoint("LEFT", it, "LEFT", 8, 0)
            it.text:SetText(o.label)
            local hl = it:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, CM.DD_ITEM_HL_A or 0.08)
            it.opKey = o.key
            it:SetScript("OnClick", function()
                local c = Cfg()
                if type(c.roleCounts) ~= "table" then c.roleCounts = {} end
                local r = c.roleCounts[L.role] or {}
                r.op = o.key
                c.roleCounts[L.role] = r
                L:Hide()
                Refilter()
                Paint()
            end)
            L.items[i] = it
        end
        L:SetHeight(4 + #XF.COUNT_OPS * ITEM_H)
        L:SetScript("OnUpdate", function(self)
            if IsMouseButtonDown("LeftButton") and not self:IsMouseOver()
                and not (self.owner and self.owner:IsMouseOver()) then
                self:Hide()
            end
        end)
        L:Hide()
    end
    if L:IsShown() and L.owner == btn then L:Hide(); return end
    L.owner, L.role = btn, role
    local rule = (Cfg().roleCounts or {})[role]
    local cur = (type(rule) == "table" and rule.op) or "lt"
    local ar, ag, ab = Accent()
    local tR, tG, tB, tA = CM.TEXT_DIM_R or 0.7, CM.TEXT_DIM_G or 0.7, CM.TEXT_DIM_B or 0.7, CM.TEXT_DIM_A or 0.85
    for _, it in ipairs(L.items) do
        if it.opKey == cur then it.text:SetTextColor(ar, ag, ab, 1) else it.text:SetTextColor(tR, tG, tB, tA) end
    end
    L:ClearAllPoints()
    L:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    L:Show()
end

-- Small black input box.
function XF.MenuBox(parent, w, letters)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(w, 16)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(letters)
    box:SetFont(Font(), ITEM_FONT, "")
    box:SetTextColor(1, 1, 1, 1)
    box:SetJustifyH("CENTER")
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)
    CM.MakeBorder(box, ThemeBorder())
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

function XF.MenuLabel(row, text)
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(Font(), ITEM_FONT, "")
    label:SetTextColor(CM.TEXT_DIM_R or 0.7, CM.TEXT_DIM_G or 0.7, CM.TEXT_DIM_B or 0.7, CM.TEXT_DIM_A or 0.85)
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetText(text)
    return label
end

-- 'Tanks [Less Than] [n]' row; empty box means no check.
function XF.AddCountRow(m, y, role, text)
    local function Rule()
        local c = Cfg()
        if type(c.roleCounts) ~= "table" then c.roleCounts = {} end
        local r = c.roleCounts[role] or {}
        c.roleCounts[role] = r
        return r
    end
    local rowF = CreateFrame("Frame", nil, m)
    rowF:SetHeight(ITEM_H + 2)
    rowF:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -y)
    rowF:SetPoint("TOPRIGHT", m, "TOPRIGHT", -1, -y)
    local sw = CreateFrame("Button", nil, rowF)
    sw:SetSize(CHECK_SZ, CHECK_SZ)
    sw:SetPoint("LEFT", rowF, "LEFT", 8, 0)
    local sbg = sw:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetColorTexture(0.12, 0.12, 0.12, 1)
    sw.ring = CM.MakeBorder(sw, 0.25, 0.25, 0.25, 0.6, CM.PanelPP)
    sw.fill = sw:CreateTexture(nil, "ARTWORK")
    sw.fill:SetPoint("TOPLEFT", sw, "TOPLEFT", 3, -3)
    sw.fill:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", -3, 3)
    sw:SetScript("OnClick", function()
        local r = Rule()
        r.on = (not r.on) or nil
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Refilter()
        Paint()
        if r.on and m.counts and m.counts[role] then m.counts[role].box:SetFocus() end
    end)
    local op = CreateFrame("Button", nil, rowF)
    op:SetSize(20, 16)
    op:SetPoint("LEFT", sw, "RIGHT", 7, 0)
    local obg = op:CreateTexture(nil, "BACKGROUND")
    obg:SetAllPoints()
    obg:SetColorTexture(0, 0, 0, 1)
    CM.MakeBorder(op, ThemeBorder())
    op.text = op:CreateFontString(nil, "OVERLAY")
    op.text:SetFont(Font(), ITEM_FONT + 1, "")
    op.text:SetTextColor(CM.TEXT_DIM_R or 0.7, CM.TEXT_DIM_G or 0.7, CM.TEXT_DIM_B or 0.7, CM.TEXT_DIM_A or 0.85)
    op.text:SetPoint("CENTER", 0, 1)
    local hl = op:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    op:SetScript("OnClick", function(self) XF.OpenOpList(self, role) end)
    local box = XF.MenuBox(rowF, 22, 2)
    box:SetPoint("LEFT", op, "RIGHT", 3, 0)
    box:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        Rule().n = tonumber(self:GetText())
        Refilter()
        Paint()
    end)
    local label = rowF:CreateFontString(nil, "OVERLAY")
    label:SetFont(Font(), ITEM_FONT, "")
    label:SetTextColor(CM.TEXT_DIM_R or 0.7, CM.TEXT_DIM_G or 0.7, CM.TEXT_DIM_B or 0.7, CM.TEXT_DIM_A or 0.85)
    label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    label:SetText(text)
    m.counts = m.counts or {}
    m.counts[role] = { box = box, op = op, sw = sw, label = label }
    return y + ITEM_H + 2
end

function XF.PaintCountRows(m)
    for _, r in ipairs(XF.COUNT_ROLES) do
        local row = m.counts and m.counts[r.key]
        if row then
            local rule = (Cfg().roleCounts or {})[r.key]
            local on = type(rule) == "table" and rule.on == true
            row.op.text:SetText(XF.COUNT_OP_LABEL[(type(rule) == "table" and rule.op) or "lt"])
            if not row.box:HasFocus() then
                local n = type(rule) == "table" and tonumber(rule.n)
                row.box:SetText(n and tostring(n) or "")
            end
            local sw = row.sw
            local ar, ag, ab = Accent()
            sw.fill:SetColorTexture(ar, ag, ab, 1)
            sw.fill:SetShown(on)
            if on then sw.ring:SetColor(ar, ag, ab, 0.8) else sw.ring:SetColor(0.25, 0.25, 0.25, 0.6) end
            local a = on and 1 or 0.4
            row.op:SetAlpha(a)
            row.box:SetAlpha(a)
            if not on and row.box:HasFocus() then row.box:ClearFocus() end
            row.box:SetEnabled(on)
            row.label:SetAlpha(a)
        end
    end
end

-- Our toggles shared by both menus (Party Fit, Not Declined, Bloodlust, Battle
-- Res).
function XF.AddFlagItem(m, y, key, text, tip)
    local item = MenuItem(m, y, text, function()
        local c = Cfg()
        c[key] = (not c[key]) or nil
        Refilter()
        Paint()
    end)
    m.items["flag_" .. key] = item
    if tip then
        item:HookScript("OnEnter", function(self)
            if type(tip) == "table" then XF.Tip(self, text, unpack(tip)) else XF.Tip(self, text, tip) end
        end)
        item:HookScript("OnLeave", XF.Untip)
    end
    return y + ITEM_H
end

function XF.PaintFlagItems(m)
    local c = Cfg()
    for _, key in ipairs({ "partyFit", "notDeclined", "hasLust", "hasBrez" }) do
        local item = m.items["flag_" .. key]
        if item then item:SetChecked(c[key] == true) end
    end
end

local function PaintRoleItems(m, raids)
    local src = raids and (ChosenRaidRoles() or {}) or C_LFGList.GetAdvancedFilter()
    for _, r in ipairs(ROLES) do
        local item = m.items["role_" .. r.key]
        if item then item:SetChecked(src[r.key] == true) end
    end
    XF.PaintFlagItems(m)
    XF.PaintCountRows(m)
end

-- Min. Rating row: the advanced filter's minimumRating (leader's M+ rating),
-- applied on Search Again.
local function AddRatingRow(m, y)
    local function Send()
        local c = Cfg()
        local v = c.ratingOn and (tonumber(c.ratingValue) or 0) or 0
        local f = C_LFGList.GetAdvancedFilter()
        if (f.minimumRating or 0) ~= v then
            f.minimumRating = v
            Apply(f)
        end
    end
    local rowF = CreateFrame("Frame", nil, m)
    rowF:SetHeight(ITEM_H + 4)
    rowF:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -y)
    rowF:SetPoint("TOPRIGHT", m, "TOPRIGHT", -1, -y)
    local RATING_TIP = "Only groups whose leader has at least this Mythic+ rating. Applied on Search Again."
    rowF:EnableMouse(true)
    rowF:SetScript("OnEnter", function(self) XF.Tip(self, "Min. Rating", RATING_TIP) end)
    rowF:SetScript("OnLeave", XF.Untip)
    local cb = CreateFrame("Button", nil, rowF)
    cb:SetSize(CHECK_SZ, CHECK_SZ)
    cb:SetPoint("LEFT", rowF, "LEFT", 8, 0)
    cb:SetScript("OnEnter", function(self) XF.Tip(self, "Min. Rating", RATING_TIP) end)
    cb:SetScript("OnLeave", XF.Untip)
    local cbg = cb:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints()
    cbg:SetColorTexture(0.12, 0.12, 0.12, 1)
    cb.ring = CM.MakeBorder(cb, 0.25, 0.25, 0.25, 0.6, CM.PanelPP)
    cb.fill = cb:CreateTexture(nil, "ARTWORK")
    cb.fill:SetPoint("TOPLEFT", cb, "TOPLEFT", 3, -3)
    cb.fill:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -3, 3)
    cb:SetScript("OnClick", function()
        local c = Cfg()
        c.ratingOn = (not c.ratingOn) or nil
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Send()
        Paint()
        if c.ratingOn and m.rating then m.rating.box:SetFocus() end
    end)
    local label = rowF:CreateFontString(nil, "OVERLAY")
    label:SetFont(Font(), ITEM_FONT, "")
    label:SetTextColor(CM.TEXT_DIM_R or 0.7, CM.TEXT_DIM_G or 0.7, CM.TEXT_DIM_B or 0.7, CM.TEXT_DIM_A or 0.85)
    label:SetPoint("LEFT", cb, "RIGHT", 7, 0)
    label:SetText("Min. Rating")
    local box = XF.MenuBox(rowF, 44, 4)
    box:SetPoint("RIGHT", rowF, "RIGHT", -7, 0)
    box:SetScript("OnEditFocusLost", function(self)
        Cfg().ratingValue = tonumber(self:GetText())
        Send()
        Paint()
    end)
    m.rating = { box = box, cb = cb, label = label }
    return y + ITEM_H + 4
end

-- Restore the saved rating when ticked again.
function XF.AdoptRating()
    local c = Cfg()
    if c.ratingOn ~= nil or c.ratingValue ~= nil then return end
    local f = C_LFGList.GetAdvancedFilter and C_LFGList.GetAdvancedFilter()
    local v = f and tonumber(f.minimumRating) or 0
    if v > 0 then c.ratingOn, c.ratingValue = true, v end
end

function XF.PaintRating(m)
    local r = m and m.rating
    if not r then return end
    local c = Cfg()
    local on = c.ratingOn == true
    local ar, ag, ab = Accent()
    r.cb.fill:SetColorTexture(ar, ag, ab, 1)
    r.cb.fill:SetShown(on)
    if on then r.cb.ring:SetColor(ar, ag, ab, 0.8) else r.cb.ring:SetColor(0.25, 0.25, 0.25, 0.6) end
    if not r.box:HasFocus() then
        local v = tonumber(c.ratingValue)
        r.box:SetText(v and v > 0 and tostring(v) or "")
    end
    local a = on and 1 or 0.4
    r.label:SetAlpha(a)
    r.box:SetAlpha(a)
    if not on and r.box:HasFocus() then r.box:ClearFocus() end
    r.box:SetEnabled(on)
end

local function AddRegionItems(m, y)
    if not RegionsAvailable() then return y end
    y = AddSection(m, y, "Region")
    for _, r in ipairs(REGIONS) do
        local key = r.key
        m.items["region_" .. key] = MenuItem(m, y, r.label, function()
            local c = Cfg()
            if type(c.regions) ~= "table" then c.regions = {} end
            c.regions[key] = (not c.regions[key]) or nil
            -- All regions ticked = no restriction.
            local n = 0
            for _, o in ipairs(REGIONS) do if c.regions[o.key] then n = n + 1 end end
            if n == #REGIONS then wipe(c.regions) end
            Refilter()
            Paint()
        end)
        y = y + ITEM_H
    end
    return y
end

local function PaintRegionItems(m)
    local chosen = RegionFilterActive() and ChosenRegions()
    for _, r in ipairs(REGIONS) do
        local item = m.items["region_" .. r.key]
        if item then item:SetChecked(chosen and chosen[r.key] == true or false) end
    end
end

local function PaintMenu()
    if raidDiffMenu and raidDiffMenu:IsShown() then
        local chosen = ChosenRaidDiffs()
        for _, d in ipairs(RAID_DIFFS_MENU) do
            raidDiffMenu.items[d.key]:SetChecked(chosen ~= nil and chosen[d.key] == true)
        end
        PaintRoleItems(raidDiffMenu, true)
        XF.PaintFlagItems(raidDiffMenu.side)
        PaintRegionItems(raidDiffMenu.side)
        PaintPlaystyleItems(raidDiffMenu.side, true)
    end
    if not (menu and menu:IsShown()) then return end
    local f = C_LFGList.GetAdvancedFilter()
    local all = DiffAllOrNone(f)
    for _, d in ipairs(DIFFS) do
        menu.items[d.key]:SetChecked(not all and f[d.key] == true)
    end
    XF.PaintRating(menu.side)
    PaintRoleItems(menu, false)
    XF.PaintFlagItems(menu.side)
    PaintRegionItems(menu.side)
    PaintPlaystyleItems(menu.side, false)
end

-- Filters menu side panel: Region, Playstyle, then the extra toggles.
XF.DIM_ALPHA = 0.35
local function DimForMenu(on)
    local a = on and XF.DIM_ALPHA or 1
    if row then row:SetAlpha(a) end
    if SP.FilterButton then SP.FilterButton:SetAlpha(a) end
    if SP.ScrollBox then SP.ScrollBox:SetAlpha(a) end
    if SP.ScrollBar then SP.ScrollBar:SetAlpha(a) end
end

local function BuildSidePanel(m, raids)
    local side = CreateFrame("Frame", nil, SP)
    side:SetFrameStrata("FULLSCREEN_DIALOG")
    side:EnableMouse(true)
    side:SetFrameLevel(300)
    side:SetClampedToScreen(true)
    side:SetWidth(140)
    side:SetPoint("TOPRIGHT", m, "TOPLEFT", 0, 0)
    local bg = side:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = ThemeFill()
    bg:SetColorTexture(r, g, b, 0.98)
    local S = Skin()
    side.items = {}
    local y = 3
    y = AddRegionItems(side, y)
    y = AddPlaystyleItems(side, y, raids)
    y = AddSection(side, y, "Misc")
    y = XF.AddFlagItem(side, y, "partyFit", "Party Fit", "Only groups with open slots for your role, or for your whole party's roles.")
    y = XF.AddFlagItem(side, y, "notDeclined", "Not Declined", "Hides groups that have declined you this session.")
    if not raids then y = AddRatingRow(side, y) end
    -- Both columns the same height with one border around them.
    local h = math.max(y + 3, m:GetHeight() or 0)
    side:SetHeight(h)
    m:SetHeight(h)
    local edge = CreateFrame("Frame", nil, side)
    edge:SetPoint("TOPLEFT", side, "TOPLEFT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 0, 0)
    edge:SetFrameLevel(m:GetFrameLevel() + 10)
    edge:EnableMouse(false)
    local S = Skin()
    if S and S.AddBorder then S.AddBorder(edge) else CM.MakeBorder(edge, ThemeBorder()) end
    side:Hide()
    m.side = side
    m:SetScript("OnShow", function() side:Show(); DimForMenu(true) end)
    m:SetScript("OnHide", function()
        side:Hide()
        DimForMenu(false)
        if XF.opList then XF.opList:Hide() end
    end)
    return side
end

-- Filters menu, as wide as its button.
local function BuildMenu()
    menu = CreateFrame("Frame", nil, SP)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:EnableMouse(true)
    menu:SetFrameLevel(300)
    menu:SetClampedToScreen(true)
    local bg = menu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = ThemeFill()
    bg:SetColorTexture(r, g, b, 0.98)
    local S = Skin()
    local _ = S  -- border goes around menu + side panel
    menu.items = {}
    local y = 3
    y = AddSection(menu, y, "Difficulty")
    for _, d in ipairs(DIFFS) do
        local key = d.key
        menu.items[key] = MenuItem(menu, y, d.label, function()
            local f = C_LFGList.GetAdvancedFilter()
            local all = DiffAllOrNone(f)
            if all then
                for _, o in ipairs(DIFFS) do f[o.key] = (o.key == key) end
                Apply(f)
            else
                SetDifficulty(key, not f[key])
            end
        end)
        y = y + ITEM_H
    end
    y = AddRoleItems(menu, y, false)
    menu:SetHeight(y + 3)
    BuildSidePanel(menu, false)
    menu:SetScript("OnUpdate", function(m)
        if IsMouseButtonDown("LeftButton") and not m:IsMouseOver() and not (diffBtn and diffBtn:IsMouseOver())
            and not m.side:IsMouseOver()
            and not (XF.opList and XF.opList:IsShown() and XF.opList:IsMouseOver()) then
            m:Hide()
        end
    end)
    menu:Hide()
end

-- Raids version of the Filters menu (no Mythic+), applies right away.
local function BuildRaidDiffMenu()
    local m = CreateFrame("Frame", nil, SP)
    raidDiffMenu = m
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:EnableMouse(true)
    m:SetFrameLevel(300)
    m:SetClampedToScreen(true)
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = ThemeFill()
    bg:SetColorTexture(r, g, b, 0.98)
    local S = Skin()
    local _ = S  -- border goes around menu + side panel
    local function Diffs()
        local c = Cfg()
        if type(c.raidDiffs) ~= "table" then c.raidDiffs = {} end
        return c.raidDiffs
    end
    m.items = {}
    local y = 3
    y = AddSection(m, y, "Difficulty")
    for _, d in ipairs(RAID_DIFFS_MENU) do
        local key = d.key
        m.items[key] = MenuItem(m, y, d.label, function()
            local t = Diffs()
            t[key] = (not t[key]) or nil
            local _, n = ChosenRaidDiffs()
            if n == #RAID_DIFFS_MENU then wipe(t) end
            Refilter()
            Paint()
        end)
        y = y + ITEM_H
    end
    y = AddRoleItems(m, y, true)
    m:SetHeight(y + 3)
    BuildSidePanel(m, true)
    m:SetScript("OnUpdate", function(self)
        if IsMouseButtonDown("LeftButton") and not self:IsMouseOver() and not (diffBtn and diffBtn:IsMouseOver())
            and not self.side:IsMouseOver()
            and not (XF.opList and XF.opList:IsShown() and XF.opList:IsMouseOver()) then
            self:Hide()
        end
    end)
    m:Hide()
end

-- Group Settings menu (person button): list look and sign-up options.
XF.GROUP_MENU = {
    { title = "Listing" },
    { key = "nameColors",     label = "Colored Group Names",
      tip = "Green name when a group is new, Red name when you were declined or instance locked. Uses Raider.IO colors when loaded." },
    { key = "leaderRating",   label = "Leader Rating",
      tip = "Shows the group leader's Mythic+ rating next to the role icons." },
    { key = "missingRoles",   label = "Show Missing Roles",
      tip = "Empty slots in 5-player groups show the role the group still needs." },
    { key = "specIcons",      label = "Show Specialization",
      tip = "Shows each member's specialization icon in place of the class icon." },
    { key = "leaderCrown",    label = "Show Group Leader",
      tip = "Puts a small crown above the group leader's icon." },
    { key = "classTooltip",   label = "Members in Tooltip",
      tip = "Group tooltips add each member's name (dungeons and arenas, where Blizzard already lists the roles and classes), or a line per member with role, specialization, class and name (other groups)." },
    { title = "Sign Up" },
    { key = "cancelOldest",   label = "Cancel Oldest Application",
      tip = "At the application limit, clicking a group cancels your oldest pending application so you can sign up." },
    -- These two drive QoL's Persistent Signup Note and Quick Signup.
    { key = "persistSignupNote", label = "Keep Sign Up Note", core = "_applyPersistSignupNote",
      tip = "Keeps your note to the group leader filled in between sign-ups." },
    { key = "quickSignup",    label = "Quick Sign Up", core = "_applyQuickSignup",
      tip = "Double-click a group to sign up straight away. Hold Shift to keep the sign-up dialog open, e.g. to type a note." },
    { title = "Misc" },
    { key = "dungeonAbbr",    label = "Dungeon Names",
      tip = "Each dungeon square shows the dungeon's short name (e.g. KR for King's Rest, AoF for Altar of Fangs).",
      onToggle = function() if ns.Search_Layout then ns.Search_Layout() end end },
    { key = "iconSize",       label = "Role Icon Size", stepper = { min = 100, max = 160, step = 5 },
      tip = "Size of the role and specialization icons in the group list." },
}
XF.MENU_SW_W, XF.MENU_SW_H = 22, 12

function XF.GroupOpt(key, default)
    local v = Cfg()[key]
    if v == nil then v = ns.DEFAULTS and ns.DEFAULTS[key] end
    if v == nil then v = default end
    return v and true or false
end

function XF.ItemOn(spec)
    if spec.core then return EllesmereUIDB and EllesmereUIDB[spec.key] and true or false end
    return XF.GroupOpt(spec.key, spec.default)
end

-- QoL rows are greyed out without QoL.
function XF.ItemAvailable(spec)
    return not spec.core or type(CM[spec.core]) == "function"
end

-- Menu row with a small switch; click anywhere to flip it.
function XF.SwitchItem(m, y, spec)
    local item = CreateFrame("Button", nil, m)
    item:SetHeight(ITEM_H)
    item:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -y)
    item:SetPoint("TOPRIGHT", m, "TOPRIGHT", -1, -y)
    local sw = CreateFrame("Frame", nil, item)
    sw:SetSize(XF.MENU_SW_W, XF.MENU_SW_H)
    sw:SetPoint("LEFT", item, "LEFT", 8, 0)
    sw:EnableMouse(false)
    sw.track = sw:CreateTexture(nil, "BACKGROUND")
    sw.track:SetAllPoints()
    sw.knob = sw:CreateTexture(nil, "ARTWORK")
    sw.knob:SetSize(XF.MENU_SW_H - 4, XF.MENU_SW_H - 4)
    item.sw = sw
    local tR, tG, tB, tA = CM.TEXT_DIM_R or 0.7, CM.TEXT_DIM_G or 0.7, CM.TEXT_DIM_B or 0.7, CM.TEXT_DIM_A or 0.85
    item.label = item:CreateFontString(nil, "OVERLAY")
    item.label:SetFont(Font(), ITEM_FONT, "")
    item.label:SetPoint("LEFT", sw, "RIGHT", 7, 0)
    item.label:SetPoint("RIGHT", item, "RIGHT", -6, 0)
    item.label:SetJustifyH("LEFT")
    item.label:SetWordWrap(false)
    item.label:SetText(spec.label)
    item.label:SetTextColor(tR, tG, tB, tA)
    local hl = item:CreateTexture(nil, "ARTWORK", nil, -1)
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0)
    item:SetScript("OnEnter", function(self)
        self.label:SetTextColor(1, 1, 1, 1)
        hl:SetColorTexture(1, 1, 1, CM.DD_ITEM_HL_A or 0.08)
        if spec.tip then
            XF.Tip(self, spec.label, spec.tip,
                not XF.ItemAvailable(spec) and "Needs the Quality of Life module" or nil)
        end
    end)
    item:SetScript("OnLeave", function(self)
        self.label:SetTextColor(tR, tG, tB, tA)
        hl:SetColorTexture(1, 1, 1, 0)
        XF.Untip()
    end)
    function item:Paint()
        local on = XF.ItemOn(spec)
        self:SetAlpha(XF.ItemAvailable(spec) and 1 or 0.4)
        self.sw.knob:ClearAllPoints()
        if on then
            local r, g, b = Accent()
            self.sw.track:SetColorTexture(r, g, b, 0.75)
            self.sw.knob:SetColorTexture(1, 1, 1, 1)
            self.sw.knob:SetPoint("RIGHT", self.sw, "RIGHT", -2, 0)
        else
            self.sw.track:SetColorTexture(0.267, 0.267, 0.267, 0.65)
            self.sw.knob:SetColorTexture(1, 1, 1, 0.5)
            self.sw.knob:SetPoint("LEFT", self.sw, "LEFT", 2, 0)
        end
    end
    item:SetScript("OnClick", function(self)
        if spec.core then
            local apply = CM[spec.core]
            if type(apply) ~= "function" or not EllesmereUIDB then return end
            EllesmereUIDB[spec.key] = not XF.ItemOn(spec)
            apply()
        else
            Cfg()[spec.key] = not XF.GroupOpt(spec.key, spec.default)
        end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        self:Paint()
        if spec.onToggle then spec.onToggle() else Refilter() end
    end)
    item:Paint()
    return item
end

-- Menu row with - / + buttons (Role Icon Size).
function XF.StepperItem(m, y, spec)
    local st = spec.stepper
    local item = CreateFrame("Frame", nil, m)
    item:SetHeight(ITEM_H)
    item:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -y)
    item:SetPoint("TOPRIGHT", m, "TOPRIGHT", -1, -y)
    local tR, tG, tB, tA = CM.TEXT_DIM_R or 0.7, CM.TEXT_DIM_G or 0.7, CM.TEXT_DIM_B or 0.7, CM.TEXT_DIM_A or 0.85
    item.label = item:CreateFontString(nil, "OVERLAY")
    item.label:SetFont(Font(), ITEM_FONT, "")
    item.label:SetPoint("LEFT", item, "LEFT", 8, 0)
    item.label:SetJustifyH("LEFT")
    item.label:SetTextColor(tR, tG, tB, tA)
    item.label:SetText(spec.label)
    if spec.tip then
        item:EnableMouse(true)
        item:SetScript("OnEnter", function(self) XF.Tip(self, spec.label, spec.tip) end)
        item:SetScript("OnLeave", XF.Untip)
    end
    local function Step(text, dir)
        local b = CreateFrame("Button", nil, item)
        b:SetSize(16, 16)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.12, 0.12, 0.12, 1)
        b.ring = CM.MakeBorder(b, 0.25, 0.25, 0.25, 0.6, CM.PanelPP)
        b.t = b:CreateFontString(nil, "OVERLAY")
        b.t:SetFont(Font(), ITEM_FONT + 2, "")
        b.t:SetPoint("CENTER")
        b.t:SetText(text)
        b.t:SetTextColor(tR, tG, tB, tA)
        b:SetScript("OnEnter", function(self)
            self.t:SetTextColor(1, 1, 1, 1)
            if self.ring and self.ring.SetColor then self.ring:SetColor(1, 1, 1, 0.8) end
        end)
        b:SetScript("OnLeave", function(self)
            self.t:SetTextColor(tR, tG, tB, tA)
            if self.ring and self.ring.SetColor then self.ring:SetColor(0.25, 0.25, 0.25, 0.6) end
        end)
        b:SetScript("OnClick", function()
            local c = Cfg()
            local v = tonumber(c[spec.key]) or (ns.DEFAULTS and ns.DEFAULTS[spec.key]) or st.min
            v = math.max(st.min, math.min(st.max, v + dir * st.step))
            c[spec.key] = v
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            item:Paint()
            Refilter()
        end)
        return b
    end
    local plus = Step("+", 1)
    plus:SetPoint("RIGHT", item, "RIGHT", -6, 0)
    item.value = item:CreateFontString(nil, "OVERLAY")
    item.value:SetFont(Font(), ITEM_FONT, "")
    item.value:SetTextColor(1, 1, 1, 1)
    item.value:SetJustifyH("CENTER")
    item.value:SetWidth(34)
    item.value:SetPoint("RIGHT", plus, "LEFT", -3, 0)
    local minus = Step("-", -1)
    minus:SetPoint("RIGHT", item.value, "LEFT", -3, 0)
    function item:Paint()
        local v = tonumber(Cfg()[spec.key]) or (ns.DEFAULTS and ns.DEFAULTS[spec.key]) or st.min
        self.value:SetText(v .. "%")
    end
    item:Paint()
    return item
end

function XF.BuildGroupMenu()
    local m = CreateFrame("Frame", nil, SP)
    XF.groupMenu = m
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:EnableMouse(true)
    m:SetFrameLevel(300)
    m:SetClampedToScreen(true)
    m:SetWidth(200)
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = ThemeFill()
    bg:SetColorTexture(r, g, b, 0.98)
    local S = Skin()
    if S and S.AddBorder then S.AddBorder(m) else CM.MakeBorder(m, ThemeBorder()) end
    m.items = {}
    local y = 3
    for _, spec in ipairs(XF.GROUP_MENU) do
        if spec.title then
            y = AddSection(m, y, spec.title)
        else
            m.items[#m.items + 1] = spec.stepper and XF.StepperItem(m, y, spec) or XF.SwitchItem(m, y, spec)
            y = y + ITEM_H
        end
    end
    m:SetHeight(y + 3)
    m:SetScript("OnShow", function(self)
        for _, it in ipairs(self.items) do it:Paint() end
        DimForMenu(true)
        if SP.FilterButton then SP.FilterButton:SetAlpha(1) end
    end)
    m:SetScript("OnHide", function() DimForMenu(false) end)
    m:SetScript("OnUpdate", function(self)
        if IsMouseButtonDown("LeftButton") and not self:IsMouseOver()
            and not (self.owner and self.owner:IsMouseOver()) then
            self:Hide()
        end
    end)
    m:Hide()
end

function XF.ToggleGroupMenu(owner)
    if not XF.groupMenu then XF.BuildGroupMenu() end
    local m = XF.groupMenu
    if m:IsShown() then m:Hide(); return end
    m.owner = owner
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -SQ_GAP)
    m:Show()
end

local function ToggleMenu()
    if SP.categoryID == RAIDS then
        if not raidDiffMenu then BuildRaidDiffMenu() end
        if raidDiffMenu:IsShown() then raidDiffMenu:Hide(); return end
        raidDiffMenu:ClearAllPoints()
        raidDiffMenu:SetPoint("TOPLEFT", diffBtn, "BOTTOMLEFT", 0, -SQ_GAP)
        raidDiffMenu:SetPoint("TOPRIGHT", refreshBtn or diffBtn, "BOTTOMRIGHT", 0, -SQ_GAP)
        raidDiffMenu:Show()
        PaintMenu()
        return
    end
    if not menu then BuildMenu() end
    if menu:IsShown() then menu:Hide(); return end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", diffBtn, "BOTTOMLEFT", 0, -SQ_GAP)
    menu:SetPoint("TOPRIGHT", refreshBtn or diffBtn, "BOTTOMRIGHT", 0, -SQ_GAP)
    menu:Show()
    PaintMenu()
end

-------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------
-- Button in the skin's look (WSkin.Button).
local function SkinnedButton(parent, w, h, keepKeys, decorate)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b:SetNormalFontObject("GameFontHighlight")
    b:SetHighlightFontObject("GameFontHighlight")
    b:SetDisabledFontObject("GameFontDisable")
    b:SetText(" ")
    if decorate then decorate(b) end
    local S = Skin()
    if S and S.Button then
        S.Button(b, keepKeys)
    else
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        CM.MakeBorder(b, 0.25, 0.25, 0.25, 1, CM.PanelPP)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)
    end
    return b
end

local function DropButton(parent, w, h)
    local b = SkinnedButton(parent, w, h, { "Arrow" }, function(btn)
        btn.Arrow = btn:CreateTexture(nil, "OVERLAY")
        btn.Arrow:SetAtlas("Azerite-PointingArrow")
        btn.Arrow:SetDesaturated(true)
        btn.Arrow:SetVertexColor(1, 1, 1, 0.8)
        btn.Arrow:SetSize(11, 8)
        btn.Arrow:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    end)
    local fs = b:GetFontString()
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", b, "LEFT", 9, 0)
    fs:SetPoint("RIGHT", b.Arrow, "LEFT", -4, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    b.label = fs
    return b
end

-- Square glyph button; atlas = true means tex is an atlas.
local function GlyphButton(parent, size, tex, atlas)
    return SkinnedButton(parent, size, size, { "Glyph" }, function(btn)
        btn:SetText("")
        btn.Glyph = btn:CreateTexture(nil, "OVERLAY")
        if atlas then
            btn.Glyph:SetAtlas(tex, false)
            btn.Glyph:SetDesaturated(true)
        else
            btn.Glyph:SetTexture(tex)
        end
        btn.Glyph:SetPoint("CENTER")
        btn.Glyph:SetAlpha(0.8)
    end)
end

-- Blizzard's Cancel Application X restyled: its art faded, our X on top (no
-- mouse), so Blizzard's button still gets the click.
function XF.CancelLook(entry)
    local cb = entry and entry.CancelButton
    if type(cb) ~= "table" or not cb.GetRegions then return end
    local d = FFD[cb]
    if not d then
        d = {}
        FFD[cb] = d
        for _, r in ipairs({ cb:GetRegions() }) do r:SetAlpha(0) end
        local hl = cb.GetHighlightTexture and cb:GetHighlightTexture()
        if hl then hl:SetAlpha(0) end
        local look = GlyphButton(cb, ROW1_H - 4, X_TEX)
        look:EnableMouse(false)
        look:SetPoint("CENTER", cb, "CENTER", 0, 0)
        look:SetFrameLevel(cb:GetFrameLevel() + 1)
        look.Glyph:SetSize(11, 11)
        look.Glyph:SetVertexColor(XF.GLYPH, XF.GLYPH, XF.GLYPH, 1)
        d.look = look
        cb:HookScript("OnEnter", function(self)
            if not self:IsEnabled() then return end
            SetBorderColor(d.look, 1, 0.15, 0.15, 1)
            d.look.Glyph:SetVertexColor(1, 0.15, 0.15, 1)
            d.look.Glyph:SetAlpha(1)
        end)
        cb:HookScript("OnLeave", function(self)
            SetBorderColor(d.look, ThemeBorder())
            d.look.Glyph:SetVertexColor(XF.GLYPH, XF.GLYPH, XF.GLYPH, 1)
            d.look.Glyph:SetAlpha(self:IsEnabled() and 0.8 or 0.35)
        end)
    end
    d.look.Glyph:SetAlpha(cb:IsEnabled() and 0.8 or 0.35)
end

ns.GlyphButton = GlyphButton
XF.GlyphButton = GlyphButton
ns.GLYPH = XF.GLYPH

local function SquareEnter(self)
    local d = self.dungeon
    if not d then return end
    XF.Tip(self, d.name or "?", "Click to toggle")
end

-- Dungeon square: a skinned button with the icon inset 1px.
local function MakeSquare(parent)
    local px = (CM.PP and CM.PP.mult) or 1
    local b = SkinnedButton(parent, BTN, BTN, { "Icon" }, function(btn)
        btn:SetText("")
        btn.Icon = btn:CreateTexture(nil, "ARTWORK")
        btn.Icon:SetPoint("TOPLEFT", btn, "TOPLEFT", px, -px)
        btn.Icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -px, px)
        btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end)
    b.icon = b.Icon
    b:SetScript("OnEnter", SquareEnter)
    b:SetScript("OnLeave", XF.Untip)
    b:SetScript("OnClick", function(self)
        if self.dungeon then ToggleDungeon(self.dungeon.groupID) end
        if XF.tipOwner == self then SquareEnter(self) end
    end)
    return b
end

local function DelveEnter(self)
    local d = self.delve
    if not d then return end
    XF.Tip(self, d.name or "?", bountiful[d.name] and "|cffffd100Bountiful this week|r" or nil, "Click to toggle")
end

-- Delve square: same button with the short name.
local function MakeDelveSquare(parent)
    local b = SkinnedButton(parent, BTN, BTN, nil, function(btn) btn:SetText("") end)
    local fs = b:GetFontString()
    fs:ClearAllPoints()
    fs:SetPoint("CENTER")
    fs:SetWordWrap(false)
    -- 1px edge (white when picked) and a gold underline for Bountiful.
    local PP = CM.PanelPP or CM.PP
    local function Layer(level)
        local f = CreateFrame("Frame", nil, b)
        f:SetAllPoints(b)
        f:SetFrameLevel(b:GetFrameLevel() + level)
        f:EnableMouse(false)
        return f
    end
    b.gold = Layer(2)
    b.edge = Layer(3)
    local line = b.gold:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -1)
    line:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -1)
    line:SetHeight(2)
    if PP and PP.CreateBorder then
        local r, g, bl, a = ThemeBorder()
        PP.CreateBorder(b.edge, r, g, bl, a, 1, "OVERLAY", 7)
    end
    b.gold:Hide()
    b:SetScript("OnEnter", DelveEnter)
    b:SetScript("OnLeave", XF.Untip)
    b:SetScript("OnClick", function(self)
        local d = self.delve
        if not d then return end
        local c = Cfg()
        if type(c.delves) ~= "table" then c.delves = {} end
        c.delves[d.groupID] = (not c.delves[d.groupID]) or nil
        local n = 0
        for _, o in ipairs(delves or {}) do if c.delves[o.groupID] then n = n + 1 end end
        if n == #(delves or {}) then wipe(c.delves) end
        Refilter()
        Paint()
        if XF.tipOwner == self then DelveEnter(self) end
    end)
    return b
end

-- Grid slot i after the reset, right-aligned, wrapping.
local function PlaceGrid(list, i, size, after, cols, slots)
    local sq = list[i]
    sq:SetSize(size, size)
    sq:ClearAllPoints()
    if i == 1 then
        sq:SetPoint("LEFT", after, "RIGHT", SQ_GAP + (slots - cols) * (size + SQ_GAP), 0)
    elseif (i - 1) % cols == 0 then
        sq:SetPoint("TOPLEFT", list[i - cols], "BOTTOMLEFT", 0, -SQ_GAP)
    else
        sq:SetPoint("LEFT", list[i - 1], "RIGHT", SQ_GAP, 0)
    end
    sq:Show()
end

-- Delve squares in that grid.
local function LayoutDelves(size, after, show, cols, slots)
    local list = delves or {}
    local font = gfFont or "GameFontHighlight"
    for i = 1, math.max(#list, #delveSquares) do
        local d = list[i]
        local sq = delveSquares[i]
        if d and show then
            if not sq then sq = MakeDelveSquare(row); delveSquares[i] = sq end
            sq.delve = d
            sq:SetNormalFontObject(font)
            sq:SetHighlightFontObject(font)
            sq:SetText(d.abbr)
            PlaceGrid(delveSquares, i, size, after, cols, slots)
        elseif sq then
            sq.delve = nil
            sq:Hide()
        end
    end
    return (show and #list > 0) and math.ceil(#list / cols) or 1
end

local function BossEnter(self)
    local b = self.boss
    if not b then return end
    XF.Tip(self, b.name or "?", b.raidName, "Click to toggle: groups with this boss still alive")
end

-- Boss square with the journal portrait cropped to the middle.
local function MakeBossSquare(parent)
    local b = MakeSquare(parent)
    b.icon:SetTexCoord(0.25, 0.75, 0, 1)
    b:SetScript("OnEnter", BossEnter)
    b:SetScript("OnClick", function(self)
        local d = self.boss
        if not d then return end
        local c = Cfg()
        if type(c.bosses) ~= "table" then c.bosses = {} end
        c.bosses[d.key] = (not c.bosses[d.key]) or nil
        Refilter()
        Paint()
        if XF.tipOwner == self then BossEnter(self) end
    end)
    return b
end

local function LayoutBosses(size, after, show, cols, slots)
    local list = {}
    for _, b in ipairs(bosses or {}) do
        if RaidShown(b.raid) then list[#list + 1] = b end
    end
    for i = 1, math.max(#list, #bossSquares) do
        local d = list[i]
        local sq = bossSquares[i]
        if d and show then
            if not sq then sq = MakeBossSquare(row); bossSquares[i] = sq end
            sq.boss = d
            sq.icon:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            PlaceGrid(bossSquares, i, size, after, cols, slots)
        elseif sq then
            sq.boss = nil
            sq:Hide()
        end
    end
    return (show and #list > 0) and math.ceil(#list / cols) or 1
end

-- Raid menu (map button): a toggle per current raid.
local function BuildRaidMenu()
    raidMenu = CreateFrame("Frame", nil, SP)
    raidMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    raidMenu:EnableMouse(true)
    raidMenu:SetFrameLevel(300)
    raidMenu:SetClampedToScreen(true)
    raidMenu:SetWidth(190)
    local bg = raidMenu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = ThemeFill()
    bg:SetColorTexture(r, g, b, 0.98)
    local S = Skin()
    if S and S.AddBorder then S.AddBorder(raidMenu) else CM.MakeBorder(raidMenu, ThemeBorder()) end
    raidMenu.items = {}
    local y = 3
    for _, raid in ipairs(raidList or {}) do
        local jid = raid.jid
        raidMenu.items[jid] = MenuItem(raidMenu, y, raid.name, function()
            local c = Cfg()
            if type(c.raidsHidden) ~= "table" then c.raidsHidden = {} end
            if RaidShown(jid) then
                -- Keep at least one raid ticked.
                local shown = 0
                for _, o in ipairs(raidList or {}) do if RaidShown(o.jid) then shown = shown + 1 end end
                if shown <= 1 then return end
            end
            c.raidsHidden[jid] = (not c.raidsHidden[jid]) or nil
            if c.raidsHidden[jid] and type(c.bosses) == "table" then
                for _, bo in ipairs(bosses or {}) do
                    if bo.raid == jid then c.bosses[bo.key] = nil end
                end
            end
            if ns.Search_Layout then ns.Search_Layout() end
            Refilter()
        end)
        y = y + ITEM_H
    end
    local div = raidMenu:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetColorTexture(1, 1, 1, 0.10)
    div:SetPoint("TOPLEFT", raidMenu, "TOPLEFT", 1, -y - 3)
    div:SetPoint("TOPRIGHT", raidMenu, "TOPRIGHT", -1, -y - 3)
    y = y + 7
    raidMenu.items.worldBosses = MenuItem(raidMenu, y, "World Bosses", function()
        local c = Cfg()
        c.hideWorldBosses = (not c.hideWorldBosses) or nil
        Refilter()
        Paint()
    end)
    y = y + ITEM_H
    raidMenu:SetHeight(y + 3)
    raidMenu:SetScript("OnUpdate", function(m)
        if IsMouseButtonDown("LeftButton") and not m:IsMouseOver() and not (raidBtn and raidBtn:IsMouseOver()) then
            m:Hide()
        end
    end)
    raidMenu:Hide()
end

local function PaintRaidMenu()
    if not (raidMenu and raidMenu:IsShown()) then return end
    for _, raid in ipairs(raidList or {}) do
        local item = raidMenu.items[raid.jid]
        if item then item:SetChecked(RaidShown(raid.jid)) end
    end
    if raidMenu.items.worldBosses then raidMenu.items.worldBosses:SetChecked(not HideWorldBosses()) end
end

local function ToggleRaidMenu()
    if not raidMenu then BuildRaidMenu() end
    if raidMenu:IsShown() then raidMenu:Hide(); return end
    raidMenu:ClearAllPoints()
    raidMenu:SetPoint("TOPLEFT", raidBtn, "BOTTOMLEFT", 0, -SQ_GAP)
    raidMenu:Show()
    PaintRaidMenu()
end

-- Tier menu: All + tiers, applies right away.
local function BuildTierMenu()
    tierMenu = CreateFrame("Frame", nil, SP)
    tierMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    tierMenu:EnableMouse(true)
    tierMenu:SetFrameLevel(300)
    tierMenu:SetClampedToScreen(true)
    local bg = tierMenu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = ThemeFill()
    bg:SetColorTexture(r, g, b, 0.98)
    local S = Skin()
    if S and S.AddBorder then S.AddBorder(tierMenu) else CM.MakeBorder(tierMenu, ThemeBorder()) end
    local function Tiers()
        local c = Cfg()
        if type(c.delveTiers) ~= "table" then c.delveTiers = {} end
        return c.delveTiers
    end
    tierMenu.items = {}
    local y = 3
    tierMenu.items.all = MenuItem(tierMenu, y, ALL or "All", function()
        wipe(Tiers())
        Refilter()
        Paint()
    end)
    y = y + ITEM_H
    local div = tierMenu:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetColorTexture(1, 1, 1, 0.10)
    div:SetPoint("TOPLEFT", tierMenu, "TOPLEFT", 1, -y - 3)
    div:SetPoint("TOPRIGHT", tierMenu, "TOPRIGHT", -1, -y - 3)
    y = y + 7
    for tier = 1, MAX_TIER do
        tierMenu.items[tier] = MenuItem(tierMenu, y, XF.TierLabel(tier), function()
            local t = Tiers()
            t[tier] = (not t[tier]) or nil
            local _, n = ChosenTiers()
            if n == MAX_TIER then wipe(t) end
            Refilter()
            Paint()
        end)
        y = y + ITEM_H
    end
    tierMenu:SetHeight(y + 3)
    tierMenu:SetScript("OnUpdate", function(m)
        if IsMouseButtonDown("LeftButton") and not m:IsMouseOver() and not (tierBtn and tierBtn:IsMouseOver()) then
            m:Hide()
        end
    end)
    -- Fade the rest of the panel while it's open.
    tierMenu:SetScript("OnShow", function() DimForMenu(true) end)
    tierMenu:SetScript("OnHide", function() DimForMenu(false) end)
    tierMenu:Hide()
end

local function PaintTierMenu()
    if not (tierMenu and tierMenu:IsShown()) then return end
    local chosen = ChosenTiers()
    tierMenu.items.all:SetChecked(chosen == nil)
    for tier = 1, MAX_TIER do
        tierMenu.items[tier]:SetChecked(chosen ~= nil and chosen[tier] == true)
    end
end

local function ToggleTierMenu()
    if not tierMenu then BuildTierMenu() end
    if tierMenu:IsShown() then tierMenu:Hide(); return end
    tierMenu:ClearAllPoints()
    tierMenu:SetPoint("TOPLEFT", tierBtn, "BOTTOMLEFT", 0, -SQ_GAP)
    tierMenu:SetPoint("TOPRIGHT", refreshBtn or tierBtn, "BOTTOMRIGHT", 0, -SQ_GAP)
    tierMenu:Show()
    PaintTierMenu()
end

local function BuildRow()
    row = CreateFrame("Frame", nil, SP)
    row:SetHeight(BTN)
    row:SetFrameLevel(SP:GetFrameLevel() + 5)
    diffBtn = DropButton(SP, DIFF_W, ROW1_H)
    diffBtn:SetFrameLevel(SP:GetFrameLevel() + 5)
    diffBtn:SetScript("OnClick", ToggleMenu)
    diffBtn:SetScript("OnHide", function() if menu then menu:Hide() end end)
    diffBtn:SetScript("OnLeave", function() Paint() end)
    tierBtn = DropButton(SP, DIFF_W, ROW1_H)
    tierBtn:SetFrameLevel(SP:GetFrameLevel() + 5)
    tierBtn:SetScript("OnClick", ToggleTierMenu)
    tierBtn:SetScript("OnHide", function() if tierMenu then tierMenu:Hide() end end)
    tierBtn:SetScript("OnLeave", function() Paint() end)
end

-- Repaint everything from the current filters.
Paint = function()
    if not SP then return end
    local f = C_LFGList.GetAdvancedFilter()
    if not f then return end
    -- Filters button goes accent while anything's set.
    if diffBtn then
        local active
        if SP.categoryID == RAIDS then
            active = ChosenRaidDiffs() or ChosenRaidPlaystyles() or ChosenRaidRoles()
        else
            active = not DiffAllOrNone(f) or DungeonPlaystyles(f) or DungeonRolesSet(f) or (f.minimumRating or 0) ~= 0
        end
        active = active or RegionFilterActive() or XF.ExtraFilterActive()
        diffBtn:SetText("Filters")
        if active then diffBtn.label:SetTextColor(Accent()) else diffBtn.label:SetTextColor(1, 1, 1, 1) end
    end
    if tierBtn then
        local chosen, n = ChosenTiers()
        if chosen then
            local text = ("Tier (%d)"):format(n)
            if n == 1 then for i = 1, MAX_TIER do if chosen[i] then text = XF.TierLabel(i) end end end
            tierBtn:SetText(text)
            tierBtn.label:SetTextColor(Accent())
        else
            tierBtn:SetText("Tier")
            tierBtn.label:SetTextColor(1, 1, 1, 1)
        end
    end
    -- Delve text stays dim until one's picked.
    local chosenDelves = ChosenDelves()
    for _, sq in ipairs(delveSquares) do
        if sq:IsShown() and sq.delve then
            local on = chosenDelves and chosenDelves[sq.delve.groupID] == true or false
            sq.on = on
            sq:GetFontString():SetAlpha(on and 1 or 0.4)
            if on then SetBorderColor(sq.edge, 1, 1, 1, 1) else SetBorderColor(sq.edge, ThemeBorder()) end
            sq.gold:SetShown(bountiful[sq.delve.name] == true)
        end
    end
    PaintTierMenu()
    PaintRaidMenu()
    if raidBtn then
        local hidden = false
        for _, raid in ipairs(raidList or {}) do if not RaidShown(raid.jid) then hidden = true end end
        if HideWorldBosses() then hidden = true end
        if hidden then raidBtn.Glyph:SetVertexColor(Accent()) else raidBtn.Glyph:SetVertexColor(1, 1, 1) end
    end
    -- Bosses: all coloured until one's picked, then the rest grey out.
    local chosenBosses = ChosenBosses()
    for _, sq in ipairs(bossSquares) do
        if sq:IsShown() and sq.boss then
            local on = chosenBosses and chosenBosses[sq.boss.key] == true or false
            sq.on = on
            sq.icon:SetDesaturated(chosenBosses ~= nil and not on)
            sq.icon:SetAlpha((chosenBosses == nil or on) and 1 or 0.45)
            if on then SetBorderColor(sq, 1, 1, 1, 1) else SetBorderColor(sq, ThemeBorder()) end
        end
    end
    local def = DungeonsDefault(f)
    for _, sq in ipairs(squares) do
        if sq:IsShown() and sq.dungeon then
            local on = not def and Contains(f.activities, sq.dungeon.groupID) ~= nil
            sq.on = on
            sq.icon:SetDesaturated(not def and not on)
            sq.icon:SetAlpha((def or on) and 1 or 0.45)
            if on then SetBorderColor(sq, 1, 1, 1, 1) else SetBorderColor(sq, ThemeBorder()) end
        end
    end
    local filter = SP.FilterButton
    local fd = filter and FFD[filter]
    if fd then
        local cb = filter.isDefaultCallback
        local isDefault = true
        if cb then
            local ok, v = pcall(cb)
            isDefault = (not ok) or (v and true or false)
        end
        if RegionFilterActive() or DelveFilterActive() or BossFilterActive() or (ChosenRaidDiffs() or ChosenRaidPlaystyles() or ChosenRaidRoles()) and SP.categoryID == RAIDS or XF.ExtraFilterActive() then isDefault = false end
        if resetBtn then
            resetBtn.active = not isDefault
            resetBtn.Glyph:SetAlpha(isDefault and 0.35 or 0.9)
        end
    end
    PaintMenu()
end

-- Search Again glyph: dim on cooldown, accent when filters changed.
PaintRefresh = function()
    if not refreshBtn then return end
    if refreshBtn.cover then refreshBtn.cover:SetShown(GetTime() < cdUntil) end
    local g = refreshBtn.Glyph
    if GetTime() < cdUntil then
        g:SetVertexColor(1, 1, 1)
        g:SetAlpha(0.3)
    elseif pending then
        g:SetVertexColor(Accent())
        g:SetAlpha(1)
    else
        g:SetVertexColor(1, 1, 1)
        g:SetAlpha(refreshBtn.hover and 1 or 0.8)
    end
end

-- Start the cooldown sweep after any search.
local function StartCooldown(sec)
    local now = GetTime()
    if now + sec <= cdUntil then return end
    cdUntil = now + sec
    if refreshBtn and refreshBtn.cd then refreshBtn.cd:SetCooldown(now, sec) end
    PaintRefresh()
    C_Timer.After(sec, PaintRefresh)
end

-------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------
-- Blizzard's Filter dropdown becomes our cog.
local function CogFilterButton(btn)
    if not btn or FFD[btn] then return end
    local d = { size = BTN }
    FFD[btn] = d
    if btn.Text then btn.Text:SetAlpha(0) end
    if btn.Background then btn.Background:SetAlpha(0) end
    d.cogFrame = CreateFrame("Frame", nil, btn)
    d.cogFrame:SetAllPoints(btn)
    d.cogFrame:SetFrameLevel(btn:GetFrameLevel() + 3)
    d.cogFrame:EnableMouse(false)
    d.cog = d.cogFrame:CreateTexture(nil, "OVERLAY")
    d.cog:SetAtlas(XF.PERSON_ATLAS, false)
    d.cog:SetDesaturated(true)
    d.cog:SetVertexColor(XF.GLYPH, XF.GLYPH, XF.GLYPH)
    d.cog:SetPoint("CENTER")
    d.cog:SetAlpha(0.8)
    if btn.ResetButton then
        btn.ResetButton:SetAlpha(0)
        btn.ResetButton:EnableMouse(false)
    end
    hooksecurefunc(btn, "UpdateText", function(self)
        local fd = FFD[self]
        if fd then self:SetSize(fd.size, fd.size) end
    end)
    -- It opens our Group Settings menu instead; a click catcher sits over
    -- Blizzard's button.
    btn:EnableMouse(false)
    local catcher = CreateFrame("Button", nil, row)
    catcher:SetAllPoints(btn)
    catcher:SetFrameLevel(btn:GetFrameLevel() + 6)
    local wash = catcher:CreateTexture(nil, "HIGHLIGHT")
    wash:SetAllPoints()
    wash:SetColorTexture(1, 1, 1, 0.1)
    catcher:SetScript("OnEnter", function(self)
        d.cog:SetAlpha(1)
        XF.Tip(self, "Group Settings")
    end)
    catcher:SetScript("OnLeave", function()
        d.cog:SetAlpha(0.8)
        XF.Untip()
    end)
    catcher:SetScript("OnClick", function(self)
        XF.Untip()
        XF.ToggleGroupMenu(self)
    end)
    catcher:SetScript("OnHide", function() if XF.groupMenu then XF.groupMenu:Hide() end end)
    d.catcher = catcher

    -- Reset uses Blizzard's own defaults.
    resetBtn = GlyphButton(row, BTN, X_TEX)
    resetBtn.Glyph:SetVertexColor(XF.GLYPH, XF.GLYPH, XF.GLYPH)
    resetBtn:SetScript("OnClick", function()
        -- Same defaults as Blizzard's reset, minus the auto-search.
        local f = C_LFGList.GetAdvancedFilter()
        f.needsTank, f.needsHealer, f.needsDamage, f.needsMyClass = false, false, false, false
        f.hasTank, f.hasHealer = false, false
        f.minimumRating = 0
        Cfg().ratingOn = nil
        for i = 1, 4 do f["generalPlaystyle" .. i] = true end
        for _, d in ipairs(DIFFS) do f[d.key] = true end
        f.activities = AllDungeonGroups()
        local c = Cfg()
        if type(c.regions) == "table" then wipe(c.regions) end
        if type(c.delves) == "table" then wipe(c.delves) end
        if type(c.delveTiers) == "table" then wipe(c.delveTiers) end
        if type(c.bosses) == "table" then wipe(c.bosses) end
        if type(c.raidDiffs) == "table" then wipe(c.raidDiffs) end
        if type(c.raidPlaystyles) == "table" then wipe(c.raidPlaystyles) end
        if type(c.raidRoles) == "table" then wipe(c.raidRoles) end
        c.partyFit, c.notDeclined, c.hasLust, c.hasBrez = nil, nil, nil, nil
        if type(c.roleCounts) == "table" then wipe(c.roleCounts) end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Apply(f)
        Refilter()
    end)
    resetBtn:SetScript("OnEnter", function(self)
        self.Glyph:SetAlpha(1)
        XF.Tip(self, "Reset Filters", not self.active and "No filters set" or nil)
    end)
    resetBtn:SetScript("OnLeave", function(self)
        XF.Untip()
        Paint()
    end)
end

-- Short dungeon name ('Altar of Fangs' -> AoF, 'Ara-Kara, City of Echoes' ->
-- AK).
XF.SMALL_WORDS = { of = true, the = true, ["and"] = true, to = true, ["in"] = true, on = true, at = true }
function XF.Abbr(name)
    if type(name) ~= "string" then return "" end
    name = name:match("^([^,:]+)") or name
    local out = {}
    for word in name:gmatch("[^%s%-]+") do
        local w = word:gsub("[^%a]", "")
        if w ~= "" then
            local c = w:sub(1, 1)
            if #out > 0 and XF.SMALL_WORDS[w:lower()] then c = c:lower() else c = c:upper() end
            out[#out + 1] = c
        end
    end
    return table.concat(out)
end

-- Short name on a square (Dungeon Names setting).
function XF.SquareAbbr(sq, d, size)
    local on = Cfg().dungeonAbbr == true and d ~= nil
    if on and not sq.abbr then
        local f = CreateFrame("Frame", nil, sq)
        f:SetAllPoints(sq)
        f:SetFrameLevel(sq:GetFrameLevel() + 3)
        f:EnableMouse(false)
        sq.abbr = f:CreateFontString(nil, "OVERLAY")
        -- Anchor both sides so it centres properly.
        sq.abbr:SetPoint("LEFT", sq, "LEFT", -4, 0)
        sq.abbr:SetPoint("RIGHT", sq, "RIGHT", 4, 0)
        sq.abbr:SetJustifyH("CENTER")
        sq.abbr:SetJustifyV("MIDDLE")
        sq.abbr:SetWordWrap(false)
    end
    if not sq.abbr then return end
    if on then
        -- Shrink until it fits.
        local fs = math.max(8, math.floor(size * 0.36))
        sq.abbr:SetFont(Font(), fs, "OUTLINE")
        sq.abbr:SetTextColor(1, 1, 1, 1)
        sq.abbr:SetText(XF.Abbr(d.name))
        while fs > 8 and ((sq.abbr.GetUnboundedStringWidth and sq.abbr:GetUnboundedStringWidth()) or 0) > size - 4 do
            fs = fs - 1
            sq.abbr:SetFont(Font(), fs, "OUTLINE")
        end
    end
    sq.abbr:SetShown(on)
end

-- Dungeon squares after the reset.
local function LayoutSquares(size, after, show)
    local list = dungeons or {}
    local prev = after
    for i = 1, math.max(#list, #squares) do
        local d = list[i]
        local sq = squares[i]
        if d and show then
            if not sq then sq = MakeSquare(row); squares[i] = sq end
            sq.dungeon = d
            sq:SetSize(size, size)
            sq:ClearAllPoints()
            sq:SetPoint("LEFT", prev, "RIGHT", SQ_GAP, 0)
            sq.icon:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            XF.SquareAbbr(sq, d, size)
            sq:Show()
            prev = sq
        elseif sq then
            sq.dungeon = nil
            sq:Hide()
        end
    end
end

-- Our row uses the same font as Back / Sign Up.
local function MatchButtonFont(box)
    local src = SP.BackButton or SP.SignUpButton
    local fs = src and src.GetFontString and src:GetFontString()
    local path, size, flags
    if fs then path, size, flags = fs:GetFont() end
    if not path then return end
    if not gfFont then gfFont = CreateFont("EUIGroupFinderButtonFont") end
    gfFont:SetFont(path, math.max(8, size - 1), flags or "")
    gfFont:SetTextColor(1, 1, 1)
    diffBtn:SetNormalFontObject(gfFont)
    diffBtn:SetHighlightFontObject(gfFont)
    tierBtn:SetNormalFontObject(gfFont)
    tierBtn:SetHighlightFontObject(gfFont)
    if box then
        box:SetFontObject(gfFont)
        if box.Instructions then
            box.Instructions:SetFontObject(gfFont)
            box.Instructions:SetTextColor(0.4, 0.4, 0.4)
        end
    end
end

-- Row positions, for the Applications card.
function ns.Search_Rows()
    local pad = tonumber(Cfg().padding) or 12
    local w = SP and SP:GetWidth()
    if not w or w < 100 then w = 338 end
    local n = (dungeons and #dungeons > 0) and #dungeons or 8
    return ROW1_Y, ROW2_Y, math.max(18, (w - pad * 2 - (n + 1) * SQ_GAP) / (n + 2)), ROW1_H
end

local function Layout()
    if not SP then return end
    local c = Cfg()
    local pad = tonumber(c.padding) or 12
    local showFilters = SP.categoryID == DUNGEONS
    local showDiff = SP.categoryID == DUNGEONS or SP.categoryID == RAIDS
    local showDelves = SP.categoryID == DELVES
    local showBosses = RaidsCurrent()
    if not row then BuildRow() end
    if not dungeons then dungeons = BuildDungeons() end
    if showDelves then
        if not delves then delves, delveByActivity = BuildDelves() end
        ScanBountiful()
    end
    if showBosses and not bosses then bosses, raidByActivity, raidList = BuildBosses() end

    -- One square size that fills row 2 exactly.
    local rowW = (SP:GetWidth() or 338) - pad * 2
    local n = (dungeons and #dungeons > 0) and #dungeons or 8
    local size = math.max(18, (rowW - (n + 1) * SQ_GAP) / (n + 2))

    -- Row 1: search box, Filters, Search Again.
    local filter, box, title = SP.FilterButton, SP.SearchBox, SP.CategoryName
    if title then title:SetAlpha(0) end
    if not refreshBtn then
        local blz = SP.RefreshButton
        refreshBtn = GlyphButton(SP, ROW1_H, "UI-RefreshButton", true)
        refreshBtn:SetFrameLevel(SP:GetFrameLevel() + 5)
        refreshBtn:EnableMouse(false)  -- Blizzard's button underneath takes the click
        refreshBtn.Glyph:SetSize(14, 14)
        local px = (CM.PP and CM.PP.mult) or 1
        local cd = CreateFrame("Cooldown", nil, refreshBtn, "CooldownFrameTemplate")
        cd:SetPoint("TOPLEFT", refreshBtn, "TOPLEFT", px, -px)
        cd:SetPoint("BOTTOMRIGHT", refreshBtn, "BOTTOMRIGHT", -px, px)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.65) end
        refreshBtn.cd = cd
        local function Tip(owner)
            refreshBtn.hover = true
            refreshBtn:LockHighlight()
            PaintRefresh()
            XF.Tip(owner, LFG_LIST_SEARCH_AGAIN or "Search Again",
                ("Limited to every %d seconds to prevent lock-out"):format(CD_SEARCH),
                pending and "Filters changed: search to update the list" or nil)
        end
        local function Untip()
            refreshBtn.hover = nil
            refreshBtn:UnlockHighlight()
            PaintRefresh()
            XF.Untip()
        end
        if blz then
            blz:SetAlpha(0)
            blz:EnableMouse(true)
            blz:HookScript("OnEnter", Tip)
            blz:HookScript("OnLeave", Untip)
        end
        -- Eats clicks while on cooldown.
        local cover = CreateFrame("Button", nil, SP)
        cover:SetAllPoints(refreshBtn)
        cover:SetFrameLevel(refreshBtn:GetFrameLevel() + 8)
        cover:SetScript("OnEnter", Tip)
        cover:SetScript("OnLeave", Untip)
        cover:Hide()
        refreshBtn.cover = cover
        PaintRefresh()
    end
    refreshBtn:ClearAllPoints()
    refreshBtn:SetPoint("RIGHT", SP, "TOPRIGHT", -pad, ROW1_Y)
    local blzRefresh = SP.RefreshButton
    if blzRefresh then
        blzRefresh:ClearAllPoints()
        blzRefresh:SetAllPoints(refreshBtn)
        blzRefresh:SetFrameLevel(refreshBtn:GetFrameLevel() + 4)
    end
    diffBtn:ClearAllPoints()
    diffBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -SQ_GAP, 0)
    diffBtn:SetShown(showDiff)
    if not showDiff or SP.categoryID ~= RAIDS then if raidDiffMenu then raidDiffMenu:Hide() end end
    if SP.categoryID ~= DUNGEONS and menu then menu:Hide() end
    tierBtn:ClearAllPoints()
    tierBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -SQ_GAP, 0)
    tierBtn:SetShown(showDelves)
    if box then
        box:ClearAllPoints()
        box:SetPoint("LEFT", SP, "TOPLEFT", pad, ROW1_Y)
        box:SetPoint("RIGHT", (showDiff and diffBtn) or (showDelves and tierBtn) or refreshBtn, "LEFT", -SQ_GAP, 0)
        box:SetHeight(ROW1_H)
        SetBorderColor(box, ThemeBorder())
        -- Shorter prompt (runs after Blizzard sets its own).
        if box.Instructions then box.Instructions:SetText((SEARCH or "Search") .. " (e.g. 10-12)") end
    end
    MatchButtonFont(box)

    -- Row 2: cog, reset, dungeon squares.
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", SP, "TOPLEFT", pad, ROW2_Y)
    row:SetPoint("TOPRIGHT", SP, "TOPRIGHT", -pad, ROW2_Y)
    row:SetHeight(size)
    row:Show()
    if filter then
        CogFilterButton(filter)
        local fd = FFD[filter]
        fd.size = size
        fd.cog:SetSize(math.floor(size * 0.55), math.floor(size * 0.55))
        filter:SetSize(size, size)
        filter:ClearAllPoints()
        filter:SetPoint("LEFT", row, "LEFT", 0, 0)
    end
    if resetBtn then
        resetBtn:SetSize(size, size)
        resetBtn.Glyph:SetSize(math.floor(size * 0.5), math.floor(size * 0.5))
        resetBtn:ClearAllPoints()
        if filter then resetBtn:SetPoint("LEFT", filter, "RIGHT", SQ_GAP, 0)
        else resetBtn:SetPoint("LEFT", row, "LEFT", 0, 0) end
        resetBtn:Show()
    end
    LayoutSquares(size, resetBtn or filter, showFilters)
    -- Delves: right-aligned grid, list moves down for extra lines.
    local lines = LayoutDelves(size, resetBtn or filter, showDelves, math.max(1, n - 1), n)
    -- Raids: map button after the reset, bosses in the grid.
    if showBosses and not raidBtn then
        raidBtn = GlyphButton(row, BTN, RAID_TEX)
        raidBtn:SetScript("OnClick", ToggleRaidMenu)
        raidBtn:SetScript("OnHide", function() if raidMenu then raidMenu:Hide() end end)
        raidBtn:SetScript("OnEnter", function(self)
            self.Glyph:SetAlpha(1)
            XF.Tip(self, "Raids", "Choose which raids' bosses are shown")
        end)
        raidBtn:SetScript("OnLeave", function(self)
            self.Glyph:SetAlpha(0.8)
            XF.Untip()
        end)
    end
    if raidBtn then
        raidBtn:SetShown(showBosses and raidList ~= nil)
        raidBtn:SetSize(size, size)
        raidBtn.Glyph:SetSize(math.floor(size * 0.6), math.floor(size * 0.6))
        raidBtn:ClearAllPoints()
        local after = resetBtn or filter
        if after then raidBtn:SetPoint("LEFT", after, "RIGHT", SQ_GAP, 0)
        else raidBtn:SetPoint("LEFT", row, "LEFT", 0, 0) end
    end
    lines = math.max(lines, LayoutBosses(size, resetBtn or filter, showBosses, math.max(1, n - 1), n))

    -- Result list fills the space between row 2 and the bottom buttons.
    local ROW_INSET = 3
    local top = ROW2_Y - lines * size - (lines - 1) * SQ_GAP - SQ_GAP
    local bottom = BOTTOM_Y + 22 + SQ_GAP
    local scroll, bar, inset = SP.ScrollBox, SP.ScrollBar, SP.ResultsInset
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOP", SP, "TOPRIGHT", -pad / 2, top)
        bar:SetPoint("BOTTOM", SP, "BOTTOMRIGHT", -pad / 2, bottom)
    end
    if scroll then
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", SP, "TOPLEFT", pad - ROW_INSET, top)
        scroll:SetPoint("BOTTOMRIGHT", SP, "BOTTOMRIGHT", -pad + ROW_INSET, bottom)
    end
    if inset then
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", SP, "TOPLEFT", pad, top)
        inset:SetPoint("BOTTOMRIGHT", SP, "BOTTOMRIGHT", -pad, bottom)
    end
    XF.PinBottomButtons(SP, { "BackButton", "BackToGroupButton" }, "SignUpButton")
    Paint()
end
ns.Search_Layout = Layout

-- Bottom rows
XF.COG_H = 22
function XF.SettingsCog(panel)
    if not (panel and LFGListFrame) then return nil end
    local cog = XF.cog
    if not cog then
        cog = GlyphButton(LFGListFrame, XF.COG_H, COG_TEX)
        cog.Glyph:SetSize(13, 13)
        cog.Glyph:SetVertexColor(XF.GLYPH, XF.GLYPH, XF.GLYPH)
        cog:SetScript("OnEnter", function(self)
            self.Glyph:SetAlpha(1)
            XF.Tip(self, "Group Filters Settings")
        end)
        cog:SetScript("OnLeave", function(self) self.Glyph:SetAlpha(0.8); XF.Untip() end)
        cog:SetScript("OnClick", function()
            XF.Untip()
            if InCombatLockdown() then
                if CM.PrintError then CM.PrintError("Cannot open options during combat.") end
                return
            end
            CM:ShowModule(ADDON_NAME)
        end)
        XF.cog = cog
    end
    local pad = tonumber(Cfg().padding) or 12
    -- Parented to the panel so it hides with it.
    if cog:GetParent() ~= panel then cog:SetParent(panel) end
    cog:ClearAllPoints()
    cog:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", pad, BOTTOM_Y)
    cog:SetFrameLevel(panel:GetFrameLevel() + 10)
    return cog
end

-- Bottom row: cog, then the buttons split the rest of the width.
local function PinBottomButtons(panel, lefts, right)
    if not panel or InCombatLockdown() then return end
    if type(lefts) ~= "table" then lefts = { lefts } end
    local pad = tonumber(Cfg().padding) or 12
    local cog = XF.SettingsCog(panel)
    local x0 = pad + (cog and (XF.COG_H + SQ_GAP) or 0)
    local pw = panel:GetWidth()
    local w = (type(pw) == "number" and pw > 0) and (pw - pad - x0 - SQ_GAP) / 2 or nil
    for _, k in ipairs(lefts) do
        local b = panel[k]
        if type(b) == "table" then
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x0, BOTTOM_Y)
            if w then b:SetWidth(w) end
        end
    end
    local rb = panel[right]
    if type(rb) == "table" then
        rb:ClearAllPoints()
        rb:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -pad, BOTTOM_Y)
        if w then rb:SetWidth(w) end
    end
end
XF.PinBottomButtons = PinBottomButtons

-- Category list spans the side padding.
local function LayoutCategoryList()
    local CS = LFGListFrame and LFGListFrame.CategorySelection
    local c = Cfg()
    if not (CS and type(CS.CategoryButtons) == "table") then return end
    local pad = tonumber(c.padding) or 12
    for i, b in ipairs(CS.CategoryButtons) do
        b:ClearAllPoints()
        if i == 1 then
            b:SetPoint("TOPLEFT", CS, "TOPLEFT", pad, -77)
            b:SetPoint("TOPRIGHT", CS, "TOPRIGHT", -pad, -77)
        else
            local prev = CS.CategoryButtons[i - 1]
            b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -3)
            b:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -3)
        end
    end
end

local function LayoutCategoryButtons()
    PinBottomButtons(LFGListFrame and LFGListFrame.CategorySelection, { "StartGroupButton" }, "FindGroupButton")
    LayoutCategoryList()
end

-- Blizzard dropdown in our Filters button look.
local function EnsureButtonFont()
    if gfFont then return gfFont end
    local src = SP and (SP.BackButton or SP.SignUpButton)
    local fs = src and src.GetFontString and src:GetFontString()
    local path, size, flags
    if fs then path, size, flags = fs:GetFont() end
    if not path then return nil end
    gfFont = CreateFont("EUIGroupFinderButtonFont")
    gfFont:SetFont(path, math.max(8, size - 1), flags or "")
    gfFont:SetTextColor(1, 1, 1)
    return gfFont
end

local function StyleEntryDropdown(dd)
    if not dd then return end
    SetBorderColor(dd, ThemeBorder())
    local label = dd.Text
    local font = EnsureButtonFont()
    if label and font then
        label:SetFontObject(font)
        label:SetTextColor(1, 1, 1, 1)
        label:ClearAllPoints()
        label:SetPoint("LEFT", dd, "LEFT", 9, 0)
        label:SetPoint("RIGHT", dd, "RIGHT", -24, 0)
        label:SetJustifyH("LEFT")
    end
    for _, r in ipairs({ dd:GetRegions() }) do
        if r.GetAtlas and r:GetAtlas() == "Azerite-PointingArrow" then
            r:SetDesaturated(true)
            r:SetVertexColor(1, 1, 1, 0.8)
            r:SetSize(11, 8)
            r:ClearAllPoints()
            r:SetPoint("RIGHT", dd, "RIGHT", -8, 0)
        end
    end
end

-- Start a Group: dropdowns, Title / Details and playstyle on the same padding
-- lines as the bottom buttons.
local function LayoutEntryFields()
    local EC = LFGListFrame and LFGListFrame.EntryCreation
    local c = Cfg()
    if not EC then return end
    local pad = tonumber(c.padding) or 12
    local W = EC:GetWidth()
    if type(W) ~= "number" or W <= 0 then return end
    local inner = W - pad * 2
    local group, act = EC.GroupDropdown, EC.ActivityDropdown
    if group then
        group:ClearAllPoints()
        group:SetPoint("TOPLEFT", EC, "TOPLEFT", pad, -76)
        if act and act:IsShown() then
            local half = (inner - SQ_GAP) / 2
            group:SetWidth(half)
            act:ClearAllPoints()
            act:SetPoint("LEFT", group, "RIGHT", SQ_GAP, 0)
            act:SetWidth(half)
        else
            group:SetWidth(inner)
        end
    end
    local nameLabel, descLabel = EC.NameLabel, EC.DescriptionLabel
    if nameLabel then
        nameLabel:ClearAllPoints()
        nameLabel:SetPoint("TOPLEFT", EC, "TOPLEFT", pad, -120)
    end
    local name = EC.Name
    if name and nameLabel then
        name:ClearAllPoints()
        name:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -5)
        name:SetPoint("TOPRIGHT", nameLabel, "BOTTOMLEFT", inner, -5)
    end
    local desc = EC.Description
    if desc and descLabel then
        desc:ClearAllPoints()
        desc:SetPoint("TOPLEFT", descLabel, "BOTTOMLEFT", 0, -10)
        desc:SetPoint("TOPRIGHT", descLabel, "BOTTOMLEFT", inner, -10)
        if desc.EditBox then desc.EditBox:SetWidth(inner - 18) end
    end
    -- Some text padding inside the boxes.
    local TXT_X, TXT_Y = 6, 4
    if name and name.SetTextInsets then
        pcall(name.SetTextInsets, name, TXT_X, TXT_X, 0, 0)
        local ins = name.Instructions
        if type(ins) == "table" then
            ins:ClearAllPoints()
            ins:SetPoint("TOPLEFT", name, "TOPLEFT", TXT_X, 0)
            ins:SetPoint("BOTTOMRIGHT", name, "BOTTOMRIGHT", -TXT_X, 0)
        end
    end
    local deb = desc and desc.EditBox
    if deb and deb.SetTextInsets then
        pcall(deb.SetTextInsets, deb, TXT_X, TXT_X, TXT_Y, TXT_Y)
        if type(deb.Instructions) == "table" then
            deb.Instructions:ClearAllPoints()
            deb.Instructions:SetPoint("TOPLEFT", deb, "TOPLEFT", TXT_X, -TXT_Y)
            deb.Instructions:SetWidth(inner - TXT_X * 2)
        end
    end
    -- Shorter placeholders (Voice Chat says Discord).
    local vc = EC.VoiceChat and EC.VoiceChat.EditBox
    if vc and type(vc.Instructions) == "table" then vc.Instructions:SetText("Discord") end
    local il = EC.ItemLevel and EC.ItemLevel.EditBox
    if il and type(il.Instructions) == "table" then il.Instructions:SetAlpha(0) end
    local style = EC.PlayStyleDropdown
    if style and desc then
        style:ClearAllPoints()
        style:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
        style:SetPoint("TOPRIGHT", desc, "BOTTOMRIGHT", 0, -20)
    end
    for _, dd in ipairs({ group, act, style }) do StyleEntryDropdown(dd) end
    -- Option row boxes line up with the playstyle dropdown.
    C_Timer.After(0, function()
        local sr = style and style:GetRight()
        if not sr then return end
        local lg = EC.ListGroupButton
        local bw = type(lg) == "table" and lg:GetWidth()
        for _, k in ipairs({ "MythicPlusRating", "PVPRating", "ItemLevel", "PvpItemLevel", "VoiceChat" }) do
            local row = EC[k]
            local box = type(row) == "table" and row.EditBox
            local rr = type(row) == "table" and row.GetRight and row:GetRight()
            if box and rr then
                local off = sr - rr
                box:ClearAllPoints()
                box:SetPoint("RIGHT", row, "RIGHT", off, 0)
                box:SetWidth((type(bw) == "number" and bw > 0) and bw or (125 + 5 + off))
                if box.SetTextInsets then pcall(box.SetTextInsets, box, TXT_X, TXT_X, 0, 0) end
                local ins = box.Instructions
                if type(ins) == "table" then
                    ins:ClearAllPoints()
                    ins:SetPoint("LEFT", box, "LEFT", TXT_X, 0)
                    ins:SetPoint("RIGHT", box, "RIGHT", -TXT_X, 0)
                end
            end
        end
        -- Switches line up with the dropdowns; Private's lines up with the
        -- boxes.
        local sl = style and style:GetLeft()
        for _, k in ipairs({ "MythicPlusRating", "PVPRating", "ItemLevel", "PvpItemLevel", "VoiceChat", "CrossFactionGroup" }) do
            local row = EC[k]
            local cb = type(row) == "table" and row.CheckButton
            local rl = type(row) == "table" and row.GetLeft and row:GetLeft()
            if type(cb) == "table" and sl and rl then
                cb:ClearAllPoints()
                cb:SetPoint("LEFT", row, "LEFT", sl - rl, 0)
                if row.Label then
                    row.Label:ClearAllPoints()
                    row.Label:SetPoint("LEFT", cb, "LEFT", 30 + 6, 0)  -- switch width + 6
                end
            end
        end
        local vbox = EC.VoiceChat and EC.VoiceChat.EditBox
        local prow = EC.PrivateGroup
        local pcb = type(prow) == "table" and prow.CheckButton
        local bl = type(vbox) == "table" and vbox:GetLeft()
        local pl = type(prow) == "table" and prow.GetLeft and prow:GetLeft()
        if type(pcb) == "table" and bl and pl then
            pcb:ClearAllPoints()
            pcb:SetPoint("LEFT", prow, "LEFT", bl - pl, 0)
            if prow.Label then
                prow.Label:ClearAllPoints()
                prow.Label:SetPoint("LEFT", pcb, "LEFT", 30 + 6, 0)  -- switch width + 6
            end
        end
    end)
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Start a Group options (Min. iLvl, Min. Rating, Voice Chat, ...) as switches
-------------------------------------------------------------------------------
local SW_W, SW_H, SW_PAD = 30, 16, 2

-- Checked state; it can be secret (e.g. editing a listing mid-encounter), then
-- returns nil, true.
local function CheckedState(cb)
    local v = cb:GetChecked()
    if IsSecret(v) then return nil, true end
    return v and true or false, false
end

local function PaintSwitch(cb)
    local d = FFD[cb]
    if not d then return end
    local raw = cb:GetChecked()
    local enabled = cb:IsEnabled()
    local sw = d.switch
    local r, g, b = Accent()
    sw.trackOn:SetColorTexture(r, g, b, 0.75)
    if IsSecret(raw) then
        -- Secret: draw both looks and let the value pick one.
        sw.trackOn:SetAlphaFromBoolean(raw, 1, 0)
        sw.knobOn:SetAlphaFromBoolean(raw, 1, 0)
        sw.trackOff:SetAlphaFromBoolean(raw, 0, 1)
        sw.knobOff:SetAlphaFromBoolean(raw, 0, 1)
        sw:SetAlpha(enabled and 1 or 0.4)
        return
    end
    local on = raw and true or false
    sw.trackOn:SetAlpha(on and 1 or 0)
    sw.knobOn:SetAlpha(on and 1 or 0)
    sw.trackOff:SetAlpha(on and 0 or 1)
    sw.knobOff:SetAlpha(on and 0 or 1)
    sw:SetAlpha(enabled and 1 or 0.4)
    local row = d.row
    local dim = (on and enabled) and 1 or 0.45
    if row and row.Label then row.Label:SetAlpha(dim) end
    local box = row and row.EditBox
    if box then
        box:SetAlpha(dim)
        -- No typing while it's off.
        if not (on and enabled) and box.HasFocus and box:HasFocus() then box:ClearFocus() end
        if box.SetEnabled then box:SetEnabled(on and enabled) end
    end
end

local function SwitchCheckbox(row)
    if type(row) ~= "table" then return end
    local cb = row.CheckButton
    if type(cb) ~= "table" then return end
    if not FFD[cb] then
        local d = { row = row }
        FFD[cb] = d
        for _, child in ipairs({ cb:GetChildren() }) do child:SetAlpha(0) end
        local sw = CreateFrame("Frame", nil, cb)
        sw:SetSize(SW_W, SW_H)
        sw:SetPoint("LEFT", cb, "LEFT", 0, 0)
        sw:SetFrameLevel(cb:GetFrameLevel() + 3)
        sw:EnableMouse(false)
        -- On and off looks, built once.
        sw.trackOff = sw:CreateTexture(nil, "BACKGROUND")
        sw.trackOff:SetAllPoints()
        sw.trackOff:SetColorTexture(0.267, 0.267, 0.267, 0.65)
        sw.trackOn = sw:CreateTexture(nil, "BACKGROUND", nil, 1)
        sw.trackOn:SetAllPoints()
        sw.knobOff = sw:CreateTexture(nil, "ARTWORK")
        sw.knobOff:SetSize(SW_H - SW_PAD * 2, SW_H - SW_PAD * 2)
        sw.knobOff:SetPoint("LEFT", sw, "LEFT", SW_PAD, 0)
        sw.knobOff:SetColorTexture(1, 1, 1, 0.5)
        sw.knobOn = sw:CreateTexture(nil, "ARTWORK", nil, 1)
        sw.knobOn:SetSize(SW_H - SW_PAD * 2, SW_H - SW_PAD * 2)
        sw.knobOn:SetPoint("RIGHT", sw, "RIGHT", -SW_PAD, 0)
        sw.knobOn:SetColorTexture(1, 1, 1, 1)
        d.switch = sw
        -- The whole switch is clickable.
        local w = cb:GetWidth()
        if type(w) == "number" and w > 0 then cb:SetHitRectInsets(0, -(SW_W - w), 0, 0) end
        if row.Label then
            row.Label:ClearAllPoints()
            row.Label:SetPoint("LEFT", row, "LEFT", SW_W + 6, 0)
        end
        d.curOn = CheckedState(cb)
        hooksecurefunc(cb, "SetChecked", function(self, v)
            local fd = FFD[self]
            if fd then
                -- Don't remember secret values.
                local now = nil
                if not IsSecret(v) then now = v and true or false end
                fd.prevOn, fd.curOn, fd.setAt = fd.curOn, now, GetTime()
            end
            PaintSwitch(self)
        end)
        if cb.SetEnabled then hooksecurefunc(cb, "SetEnabled", PaintSwitch) end
        cb:HookScript("OnClick", function(self)
            local fd = FFD[self]
            local on = CheckedState(self)
            if fd then fd.curOn = on end
            PaintSwitch(self)
            -- Blizzard focuses the box before we enable it.
            local box = fd and fd.row and fd.row.EditBox
            if box and on and box.SetFocus then box:SetFocus() end
        end)
        if row.EditBox and row.EditBox.HookScript then
            -- Blizzard re-enables these boxes on its own, so refuse focus while
            -- off.
            row.EditBox:HookScript("OnEditFocusGained", function(box)
                if CheckedState(cb) == false then box:ClearFocus() end
            end)
            if row.EditBox.SetEnabled then
                hooksecurefunc(row.EditBox, "SetEnabled", function(box, v)
                    if not IsSecret(v) and v and CheckedState(cb) == false and not FFD[cb].reEnable then
                        FFD[cb].reEnable = true
                        box:SetEnabled(false)
                        FFD[cb].reEnable = nil
                    end
                end)
            end
            row.EditBox:HookScript("OnEditFocusLost", function()
                local fd = FFD[cb]
                if fd and fd.prevOn and fd.curOn == false and fd.setAt == GetTime() then
                    cb:SetChecked(true)
                end
            end)
        end
    end
    PaintSwitch(cb)
end

local function LayoutEntrySwitches()
    local EC = LFGListFrame and LFGListFrame.EntryCreation
    if not EC then return end
    for _, k in ipairs({ "MythicPlusRating", "PVPRating", "ItemLevel", "PvpItemLevel", "VoiceChat", "CrossFactionGroup", "PrivateGroup" }) do
        SwitchCheckbox(EC[k])
    end
end

local function LayoutEntryButtons()
    PinBottomButtons(LFGListFrame and LFGListFrame.EntryCreation, { "CancelButton" }, "ListGroupButton")
    LayoutEntryFields()
    LayoutEntrySwitches()
end
ns.Search_LayoutEntry = LayoutEntryButtons

-------------------------------------------------------------------------------
-- Boot
-------------------------------------------------------------------------------
local function Init()
    SP = LFGListFrame and LFGListFrame.SearchPanel
    if not SP then return end
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
    SP:HookScript("OnShow", Layout)
    local CS = LFGListFrame.CategorySelection
    if CS then
        CS:HookScript("OnShow", LayoutCategoryButtons)
        if LFGListCategorySelection_AddButton then
            hooksecurefunc("LFGListCategorySelection_AddButton", LayoutCategoryList)
        end
        if CS:IsShown() then LayoutCategoryButtons() end
    end
    local EC = LFGListFrame.EntryCreation
    if EC then
        EC:HookScript("OnShow", LayoutEntryButtons)
        if LFGListEntryCreation_Select then
            hooksecurefunc("LFGListEntryCreation_Select", function()
                if EC:IsShown() then LayoutEntryFields(); LayoutEntrySwitches() end
            end)
        end
        if EC:IsShown() then LayoutEntryButtons() end
    end
    hooksecurefunc("LFGListSearchPanel_SetCategory", Layout)
    -- Repaint after every result update (also Blizzard's own filter / reset).
    hooksecurefunc("LFGListSearchPanel_UpdateResultList", function()
        -- Remember this search's results for the 'new group' colour.
        if not SP.searching and type(SP.results) == "table" and #SP.results > 0 then
            seenResults = {}
            for _, id in ipairs(SP.results) do seenResults[id] = true end
        end
        if SP:IsShown() then Paint() end
    end)
    if LFGListUtil_SetSearchEntryTooltip then
        hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", AddClassesByRole)
        hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", XF.CancelHint)
    end
    if LFGListSearchEntry_Update then hooksecurefunc("LFGListSearchEntry_Update", DecorateEntry) end
    -- Every search clears the 'filters changed' hint and starts the sweep.
    hooksecurefunc("LFGListSearchPanel_DoSearch", function()
        -- Previous search, same category only.
        prevResults = (prevCategory == SP.categoryID) and seenResults or nil
        prevCategory = SP.categoryID
        seenResults = {}
        pending = false
        StartCooldown(CD_SEARCH)
    end)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    ev:RegisterEvent("LFG_LIST_SEARCH_FAILED")
    XF.AdoptRating()
    ev:SetScript("OnEvent", function(_, event)
        if event == "LFG_LIST_SEARCH_FAILED" then
            -- Server refused a search: wait longer.
            pending = true
            StartCooldown(CD_FAILED)
            return
        end
        dungeons = BuildDungeons() or dungeons
        if SP:IsShown() then Layout() end
    end)
    if SP:IsShown() then Layout() end
end

function ns.Search_OnEnable()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("PremadeGroupsFilter") then
        print("|cff0cd29fEllesmereUI|r Group Finder is off while the Premade Groups Filter addon is loaded.")
        return
    end
    if C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder") and LFGListFrame then
        Init()
        return
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        if name == "Blizzard_GroupFinder" then
            self:UnregisterEvent("ADDON_LOADED")
            Init()
        end
    end)
end
