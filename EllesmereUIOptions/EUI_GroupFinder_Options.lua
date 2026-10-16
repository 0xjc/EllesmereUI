if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EUI_GroupFinder_Options.lua: Group Finder settings page
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUIGroupFinder"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]
if not ns then return end  -- module off: no page
local EUI = EllesmereUI

local PAGE_SEARCH = "Premade Search"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EUI.RegisterModule then return end
    local function Cfg() return ns.Cfg() end
    local function Get(key, fallback)
        local c = Cfg()
        local v = c and c[key]
        if v == nil then return fallback end
        return v
    end
    local function Set(key, val, relayout)
        local c = Cfg()
        if c then c[key] = val end
        if relayout and ns.Search_Layout then ns.Search_Layout() end
    end

    local AddAppsSections

    local function BuildSearchPage(pageName, parent, yOffset)
        local W = EUI.Widgets
        local y = yOffset
        local _, h

        if EUI.ClearContentHeader then EUI:ClearContentHeader() end
        parent._showRowDivider = true

        -- Off until enabled; toggling reloads.
        local function PGFLoaded() return C_AddOns.IsAddOnLoaded("PremadeGroupsFilter") end
        local pgfNote = PGFLoaded()
            and { type = "label", text = "|cffff6060Premade Groups Filter is loaded. Disable it to use the Group Finder.|r" }
            or EUI.BlankRowCfg()
        _, h = W:SectionHeader(parent, "GROUP FINDER", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Group Finder",
              disabled = function() return PGFLoaded() and not ns.Enabled() end,
              disabledTooltip = "Premade Groups Filter", requireState = "disabled",
              tooltip = "Premade Groups search filters, group list and applicant tools, the M+ applications bar and the Dungeon Finder / Raid Finder layout in the Dungeons & Raids window. Requires a reload.",
              getValue = function() return ns.Enabled() end,
              setValue = function(v)
                  v = v and true or false
                  if v == ns.Enabled() then return end
                  -- Only saved once the reload is confirmed.
                  EUI:ShowConfirmPopup({
                      title       = v and "Enable Group Finder" or "Disable Group Finder",
                      message     = v and "Your UI will reload to turn on the Group Finder."
                                      or "Your UI will reload to turn off the Group Finder.",
                      confirmText = "Reload Now",
                      cancelText  = "Cancel",
                      reload      = true,
                      onConfirm   = function() ns.SetEnabled(v) end,
                      onCancel    = function() EUI:RefreshPage() end,
                  })
              end },
            pgfNote);  y = y - h

        -- List look, sign-up options and icon size live in the Group Settings
        -- menu on the panel.
        y = AddAppsSections(parent, y)

        _, h = W:Spacer(parent, y, 20); y = y - h
        parent:SetHeight(math.abs(y - yOffset))
        return math.abs(y - yOffset)
    end

    -----------------------------------------------------------------------
    -- Applications settings
    -----------------------------------------------------------------------
    local function APCfg() return ns.AppsCfg() end
    local function APGet(key, default)
        local c = APCfg()
        local v = c and c[key]
        if v == nil then return default end
        return v
    end
    local function APSet(key, val)
        local c = APCfg()
        if c then c[key] = val end
        if ns.ApplyApplications then ns.ApplyApplications() end
    end
    local function APOff() return APGet("enabled", true) == false end
    local function APToggle(text, key, default, tooltip)
        return { type="toggle", text=text, tooltip=tooltip,
                 disabled=APOff, disabledTooltip="Show in Group Finder",
                 getValue=function() return APGet(key, default) == true end,
                 setValue=function(v) APSet(key, v and true or false) end }
    end

    AddAppsSections = function(parent, y)
        local W = EUI.Widgets
        local row, h

        row, h = W:SectionHeader(parent, "APPLICATIONS", y); y = y - h

        local scopeValues = { session = "Session", character = "Character", account = "Account" }
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show in Group Finder",
              tooltip="A bar at the top of the Dungeons & Raids sidebar counting your Mythic+ (Dungeons) Group Finder applications and how they ended, each count inside its part of the bar. Raids, delves and other groups are not counted.",
              getValue=function() return APGet("enabled", true) ~= false end,
              setValue=function(v) APSet("enabled", v and true or false); EUI:RefreshPage() end },
            { type="dropdown", text="Counts Shown",
              tooltip="Which totals the card shows. Hover the card for all three.",
              values=scopeValues, order={ "session", "character", "account" },
              disabled=APOff, disabledTooltip="Show in Group Finder",
              getValue=function() return APGet("scope", "character") end,
              setValue=function(v) APSet("scope", v) end });  y = y - h

        -- Built-in textures, then SharedMedia's.
        local tex, names, order = ns.BarTextureTables()
        local texValues, texOrder = {}, {}
        for _, key in ipairs(order) do
            if key ~= "---" then texValues[key] = names[key] or key end
            texOrder[#texOrder + 1] = key
        end
        texValues._menuOpts = { itemHeight = 28, background = function(key) return tex[key] end }
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Bar Texture", values=texValues, order=texOrder,
              disabled=APOff, disabledTooltip="Show in Group Finder",
              getValue=function() return APGet("texture", "none") end,
              setValue=function(v) APSet("texture", v) end },
            EUI.BlankRowCfg());  y = y - h

        row, h = W:SectionHeader(parent, "APPLICATION VISIBILITY", y); y = y - h
        row, h = W:DualRow(parent, y,
            APToggle("Accepted", "showAccepted", true, "Invites you accepted."),
            APToggle("Declined", "showDeclined", true, "Declined by the leader, the group filled, or the application timed out."));  y = y - h
        row, h = W:DualRow(parent, y,
            APToggle("Delisted", "showDelisted", true, "The group was delisted before answering."),
            APToggle("Cancelled", "showCancelled", true, "You cancelled the application."));  y = y - h

        row, h = W:SectionHeader(parent, "RESET APPLICATION COUNTS", y); y = y - h
        local function Reset(label, scope)
            return function()
                EUI:ShowConfirmPopup({
                    title = label,
                    message = ("Reset the %s application counts to zero?"):format(scope),
                    confirmText = "Reset", cancelText = "Cancel",
                    onConfirm = function()
                        if ns.ResetApplications then ns.ResetApplications(scope) end
                    end,
                })
            end
        end
        row, h = W:WideTripleButton(parent, "Reset Session", "Reset Character", "Reset Account", y,
            Reset("Reset Session", "session"), Reset("Reset Character", "character"), Reset("Reset Account", "account"))
        y = y - h
        return y
    end

    EUI:RegisterModule(ADDON_NAME, {
        title       = "Group Finder",
        description = "Premade Groups search filters, group list and applicant tools in the Dungeons & Raids window.",
        pages       = { PAGE_SEARCH },
        buildPage   = BuildSearchPage,
        onReset     = function()
            ns.ResetSettings()
            if ns.Search_Layout then ns.Search_Layout() end
            if ns.ApplyApplications then ns.ApplyApplications() end
        end,
    })
end)
-- LoadOnDemand: PLAYER_LOGIN already fired, so run it now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
