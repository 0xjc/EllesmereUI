if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIGroupFinder.lua
--  Premade Groups search filters, group list and applicant tools in the
--  Dungeons & Raids window, the M+ applications bar and the Dungeon Finder /
--  Raid Finder layout. Off until enabled (nothing is hooked or built before);
--  the settings page is EUI_GroupFinder_Options.lua.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.Lite) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- LOD options file reads this module ns via the registry

local GF = EllesmereUI.Lite.NewAddon(ADDON_NAME)

local DEFAULTS = {
    padding          = 12,
    nameColors       = true,
    classTooltip     = true,
    leaderRating     = true,
    leaderCrown      = true,
    missingRoles     = true,
    specIcons        = true,
    iconSize         = 125,
    cancelOldest     = false,
}
ns.DEFAULTS = DEFAULTS

local APPS_DEFAULTS = {
    enabled       = true,
    scope         = "character",   -- session | character | account
    texture       = "none",
    showAccepted  = true,
    showDeclined  = true,
    showDelisted  = true,
    showCancelled = true,
}
ns.APPS_DEFAULTS = APPS_DEFAULTS

local db

local function Profile() return db and db.profile end

-- Account-wide data under EllesmereUIDB.<key> (outside profiles).
local function Account(key)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    local t = EllesmereUIDB[key]
    if type(t) ~= "table" then
        t = {}
        EllesmereUIDB[key] = t
    end
    return t
end

-- The on/off switch is account-wide, so a profile switch, a spec profile or
-- an import never turns the module on or off.
function ns.Enabled()
    local t = EllesmereUIDB and EllesmereUIDB.groupFinder
    return type(t) == "table" and t.enabled == true or false
end

function ns.SetEnabled(v)
    Account("groupFinder").enabled = v and true or false
end

-- Before the profile is open: the defaults, read-only (writes never reach
-- the shared DEFAULTS table).
local readOnly = { search = setmetatable({}, { __index = DEFAULTS, __newindex = function() end }),
                   apps   = setmetatable({}, { __index = APPS_DEFAULTS, __newindex = function() end }) }

function ns.Cfg()
    local p = Profile()
    return p and p.search or readOnly.search
end

function ns.AppsCfg()
    local p = Profile()
    return p and p.apps or readOnly.apps
end

-- Application counts are account-wide and outside profiles.
function ns.AppCountsStore()
    local t = Account("groupFinderApps")
    if type(t.dungeon) ~= "table" then t.dungeon = {} end
    return t.dungeon
end

function ns.ResetSettings()
    if db then db:ResetProfile() end
end

function GF:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIGroupFinderDB", { profile = { search = DEFAULTS, apps = APPS_DEFAULTS } })
end

function GF:OnEnable()
    if not ns.Enabled() then return end
    -- Premade Groups Filter works the same panel: with it loaded the module
    -- switches itself off (and stays off until turned on again).
    if C_AddOns.IsAddOnLoaded("PremadeGroupsFilter") then
        ns.SetEnabled(false)
        print("|cff0cd29fEllesmereUI|r Group Finder has been turned off because Premade Groups Filter is loaded.")
        return
    end

    if ns.Apps_Enable then ns.Apps_Enable() end
    local function Start()
        if ns.Search_OnEnable then ns.Search_OnEnable() end
        if ns.Rail_Enable then ns.Rail_Enable() end
        if ns.Finder_Enable then ns.Finder_Enable() end
    end
    if C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder") and PVEFrame then
        Start()
        return
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        if name == "Blizzard_GroupFinder" then
            self:UnregisterEvent("ADDON_LOADED")
            Start()
        end
    end)
end
