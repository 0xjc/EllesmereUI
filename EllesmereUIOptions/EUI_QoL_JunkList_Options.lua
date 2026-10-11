if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_QoL_JunkList_Options.lua
--  Options section for the Junk Items window (registered under EllesmereUIQoL).
-------------------------------------------------------------------------------

if not EllesmereUI._ModuleNS["EllesmereUIQoL"] then return end  -- module disabled: no options page

local function P()
    local db = _G._EUI_JunkList_DB()
    return db and db.profile.junkList
end

local function Cfg(key, fallback)
    local p = P()
    if not p or p[key] == nil then return fallback end
    return p[key]
end

-- Every write re-applies the window.
local function Set(key, v)
    local p = P()
    if p then p[key] = v end
    _G._EUI_JunkList_Apply()
end

local function Off() return Cfg("enabled", false) ~= true end

local function ClearExclusions()
    EllesmereUI:ShowConfirmPopup({
        title       = EllesmereUI.L("Clear Excluded Items"),
        message     = EllesmereUI.L("Every item you middle-clicked away can show in the Junk Items window again."),
        confirmText = EllesmereUI.L("Clear"),
        cancelText  = CANCEL,
        onConfirm   = _G._EUI_JunkList_ClearExclusions,
    })
end

_G._EUI_BuildJunkListSection = function(parent, yOffset, W)
    local y = yOffset
    local _, h

    _, h = W:SectionHeader(parent, "JUNK ITEMS", y); y = y - h

    -- The rows after this one are built only while the window is on; the
    -- toggle rebuilds the page.
    _, h = EllesmereUI.BuildVisibilityRow(W, parent, y, {
        leftCfg = { type = "toggle", text = "Enable Junk Items Window",
            tooltip = "Shows your cheapest junk in a small window.",
            getValue = function() return not Off() end,
            setValue = EllesmereUI.SectionToggleSetValue(function(v) Set("enabled", v) end) },
        getStore = P,
        legacyKey = "visibility",
        caps = { partyIncludesRaid = false, luaDragonriding = true, noMouseover = true },
        disabledFn = Off, disabledTooltip = "Junk Items Window",
        onChanged = EllesmereUI.RequestVisibilityUpdate,
        onOptionChanged = EllesmereUI.RequestVisibilityUpdate,
    }); y = y - h

    if not Off() then
    _, h = W:DualRow(parent, y,
        { type    = "slider",
          text    = "Items Shown",
          min     = 1, max = 6, step = 1, isPercent = false,
          tooltip = "How many junk stacks the window lists.",
          getValue = function() return Cfg("itemCount", 4) end,
          setValue = function(v) Set("itemCount", v) end },
        { type    = "toggle",
          text    = "Include White Items",
          tooltip = "Lists white stacks as well as gray ones.",
          getValue = function() return Cfg("includeWhite", false) == true end,
          setValue = function(v) Set("includeWhite", v) end }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type    = "toggle",
          text    = "Skip Confirmation for White Items",
          tooltip = "White stacks delete without asking first.",
          getValue = function() return Cfg("skipWhiteConfirm", false) == true end,
          setValue = function(v) Set("skipWhiteConfirm", v) end },
        { type       = "labeledButton",
          text       = "Excluded Items",
          buttonText = "Clear",
          width      = 90,
          tooltip    = "Brings back items you middle-clicked away.",
          onClick    = ClearExclusions }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type    = "slider",
          text    = "Icon Size",
          min     = 16, max = 64, step = 1, isPercent = false,
          getValue = function() return Cfg("iconSize", 32) end,
          setValue = function(v) Set("iconSize", v) end },
        { type    = "slider",
          text    = "Icon Spacing",
          min     = 0, max = 30, step = 1, isPercent = false,
          getValue = function() return Cfg("iconSpacing", 6) end,
          setValue = function(v) Set("iconSpacing", v) end }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type    = "dropdown",
          text    = "Price Position",
          values  = { bottom = "Below Icon", top = "Above Icon" },
          order   = { "bottom", "top" },
          getValue = function() return Cfg("priceSide", "bottom") end,
          setValue = function(v) Set("priceSide", v) end },
        { type    = "toggle",
          text    = "Show Empty Bag Slots",
          tooltip = "Shows free and total bag slots as the title.",
          getValue = function() return Cfg("showFreeSlots", false) == true end,
          setValue = function(v) Set("showFreeSlots", v) end }
    ); y = y - h
    end   -- close hidden-while-disabled gate

    _, h = W:Spacer(parent, y, 20); y = y - h

    return math.abs(y - yOffset)
end
