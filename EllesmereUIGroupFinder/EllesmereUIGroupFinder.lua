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
    oneClick         = false,
    keepNote         = false,
    cancelOldest     = false,
    signUpDeclined   = false,
    applicantColumns = true,
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

function ns.Enabled()
    local p = Profile()
    return p and p.enabled == true or false
end

function ns.SetEnabled(v)
    local p = Profile()
    if p then p.enabled = v and true or false end
end

function ns.Cfg()
    local p = Profile()
    return p and p.search or DEFAULTS
end

function ns.AppsCfg()
    local p = Profile()
    return p and p.apps
end

-- Application counts are account-wide and outside profiles.
function ns.AppCountsStore()
    if type(EllesmereUIGroupFinderAppsDB) ~= "table" then EllesmereUIGroupFinderAppsDB = {} end
    local sv = EllesmereUIGroupFinderAppsDB
    if type(sv.dungeon) ~= "table" then sv.dungeon = {} end
    return sv.dungeon
end

function ns.ApplyDefaults()
    local p = Profile()
    if not p then return end
    if type(p.search) ~= "table" then p.search = {} end
    if type(p.apps) ~= "table" then p.apps = {} end
    EllesmereUI.Lite.DeepMergeDefaults(p.search, DEFAULTS)
    EllesmereUI.Lite.DeepMergeDefaults(p.apps, APPS_DEFAULTS)
    p.search.padding = DEFAULTS.padding
end

function ns.ResetSettings()
    local p = Profile()
    if not p then return end
    p.search, p.apps = {}, {}
    ns.ApplyDefaults()
end

function GF:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIGroupFinderDB", { profile = { enabled = false } })
    ns.ApplyDefaults()
end

function GF:OnEnable()
    if not ns.Enabled() then return end
    ns.ApplyDefaults()
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
