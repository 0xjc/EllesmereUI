if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local ns = EllesmereUI._ModuleNS["EllesmereUIUnitFrames"]
if not ns then return end

local MOVE_KEYS = { "X", "Y", "WidthPct", "ClassColor", "ColorR", "ColorG", "ColorB",
    "NameFormat", "TargetSep", "TargetPrefix", "TargetSepColor", "TargetSepClassColor", "CustomFormat" }

-- False for content a slot keeps to itself: "none", and "custom", whose format
-- is stored per slot, so several slots may use it and none is picked for them.
function ns.UF_IsUniqueContent(v)
    return v ~= "none" and v ~= "custom"
end

-- Level coloring is shared by the unit, and edited from its level-text cogs.
function ns.UF_CoreTextRows(prefix, contentDefault, get, set, rows)
    rows = ns.UF_NameFormatRows(prefix, contentDefault, get, set, rows)
    local content = get(prefix .. "Content", contentDefault)
    local parsed = content == "custom" and ns.UF_TextTags
        and EllesmereUI.TextTags.Parse(ns.UF_TextTags, get(prefix .. "CustomFormat"))
    local hasLevel = content == "level" or content == "levelname" or content == "namelevel"
        or (parsed and parsed.has.level)
    if not hasLevel then return rows end
    rows[#rows + 1] = { type="toggle", label="Level Text: Difficulty Color",
        tooltip="Colors level text by difficulty, from grey (trivial) through green, yellow and orange to red (5+ levels above you).",
        get=function() return get("levelDifficultyColor", false) == true end,
        set=function(v)
            set("levelDifficultyColor", v)
            ns._UFO_OptEnv.UpdatePreview()
        end }
    rows[#rows + 1] = { type="toggle", label="Level Text: Include Friendly",
        tooltip="Friendly units get their level's color too, instead of gold.",
        disabled=function() return get("levelDifficultyColor", false) ~= true end,
        disabledTooltip="Level Text: Difficulty Color",
        get=function() return get("levelDifficultyColorFriendly", false) == true end,
        set=function(v)
            set("levelDifficultyColorFriendly", v)
            ns._UFO_OptEnv.UpdatePreview()
        end }
    return rows
end

-- Keep the unit-frame settings and inline controls; only the list changes.
function ns.UFO_BuildTextSlots(W, parent, y, opts)
    local header, headerH = W:SectionHeader(parent, "CORE TEXT POSITIONS", y)
    y = y - headerH
    parent._ufTextHeader = header
    local slots, order, values = opts.slots, {}, {}
    local byKey, cells, targets = {}, {}, {}
    local textValues = CopyTable(opts.values)
    -- Remove in the house BAD red with the close X at the row's right edge: 12px,
    -- at the list delete buttons' 0.75 alpha; both brighten on hover. Custom
    -- gets the house edit pencil in white (per slot below).
    textValues.none = "Remove"
    textValues._menuOpts = {
        icon = function(key)
            if key == "none" then return "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png" end
            if key == "custom" then return "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-edit.png" end
        end,
        iconSize = function() return 12 end,
        iconColor = function() return 1, 0.35, 0.35, 0.75 end,
        labelColor = function(key)
            if key == "none" then return 1, 0.35, 0.35, 0.8 end
        end,
    }
    local function Notify(key)
        ns._ufTextNotify = { unit = opts.unit, key = key }
    end
    -- Custom is an action entry: it opens the format popup, and a saved
    -- format selects it for the slot.
    local EditCustom
    function EditCustom(s, warning)
        local key = s.key .. "CustomFormat"
        local cur = opts.db()[key]
        if type(cur) ~= "string" then cur = nil end
        -- 120 letters for new input; a longer stored format (import) keeps its length.
        local maxLen = math.max(120, cur and (strlenutf8 and strlenutf8(cur) or #cur) or 0)
        -- The preview in the slot's text colour, as the unit preview shows it.
        local db, color = opts.db(), nil
        if db[s.key .. "ClassColor"] then
            if opts.unit == "player" then
                local _, cls = UnitClass("player")
                color = cls and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[cls]
            else
                color = { r = 0.9, g = 0.3, b = 0.3 }
            end
        else
            color = { r = db[s.key .. "ColorR"] or 1, g = db[s.key .. "ColorG"] or 1, b = db[s.key .. "ColorB"] or 1 }
        end
        -- Preview, suggestions, unknown-tag hint and tag help come from the engine's catalog.
        local popupOpts = {
            title = EllesmereUI.L("Custom Text"),
            message = EllesmereUI.L("Tags in [brackets] show live values, other text stays as typed.") .. "\n"
                .. EllesmereUI.L("Type [ for suggestions, the (i) lists every tag."),
            messageSize = 10,
            previewColor = color,
            placeholder = "[name] - [hp:pct]%",
            initialText = (not warning and cur) or "",
            maxLetters = maxLen,
            showCount = true,
            warning = warning,
            onConfirm = function(txt)
                -- Stored with single pipes; the engine escapes them for display.
                txt = tostring(txt or ""):gsub("||", "|"):gsub("^%s+", ""):gsub("%s+$", "")
                -- Spaces only: show the popup again instead of closing unsaved.
                if txt == "" then EditCustom(s, EllesmereUI.L("Enter at least one tag or character.")); return end
                opts.db()[key] = txt
                Notify(s.key)
                s.cfg.setValue("custom")
            end,
        }
        if ns.UF_TextTags then
            EllesmereUI.TextTags.PopupOpts(ns.UF_TextTags, popupOpts, {
                tagNotes = { hp = EllesmereUI.L("shows DEAD or OFFLINE") },
            })
        end
        EllesmereUI:ShowInputPopup(popupOpts)
    end
    for i = 1, #slots do
        local s = slots[i]
        order[i], values[s.key], byKey[s.key] = s.key, s.position, s
        if textValues.custom then
            local v = CopyTable(textValues)
            v.custom = { text = "Custom", action = function() EditCustom(s) end }
            -- The pencil at full alpha while Custom is this slot's content; a
            -- selection rebuilds the page, so the menu is read fresh.
            v._menuOpts.iconColor = function(key)
                if key ~= "custom" then return 1, 0.35, 0.35, 0.75 end
                return 1, 1, 1, s.cfg.getValue() == "custom" and 1 or 0.75
            end
            s.cfg.values = v
        else
            s.cfg.values = textValues
        end
        if s.cfg.getValue() ~= "none" then cells[#cells + 1] = s end
    end
    local function Assigned(key)
        local s = byKey[key]
        return s and s.cfg.getValue() ~= "none"
    end
    local function Full()
        for i = 1, #slots do
            if not Assigned(slots[i].key) then return false end
        end
        return true
    end
    local function Candidate()
        for i = 1, #opts.contentOrder do
            local v = opts.contentOrder[i]
            if v ~= "---" and ns.UF_IsUniqueContent(v) then
                local used = false
                for j = 1, #slots do
                    if slots[j].cfg.getValue() == v then used = true; break end
                end
                if not used then return v end
            end
        end
    end
    local function Add(key)
        local v = Candidate()
        if Assigned(key) or not byKey[key] or not v then
            EllesmereUI:RefreshPage(true); return
        end
        Notify(key)
        byKey[key].cfg.setValue(v)
    end
    local function Move(source, dest)
        if source == dest then return end
        if not Assigned(source) or not byKey[dest] or Assigned(dest) then
            EllesmereUI:RefreshPage(true); return
        end
        local db = opts.db()
        local content = byKey[source].cfg.getValue()
        local size = db[source .. "Size"] or db.textSize or 12
        for i = 1, #MOVE_KEYS do
            local suffix = MOVE_KEYS[i]
            local v = db[source .. suffix]
            if type(v) == "table" then v = CopyTable(v) end
            db[dest .. suffix] = v
        end
        db[dest .. "Size"] = size
        if dest == "extraText" then
            db.extraTextAlign = source == "rightText" and "right" or source == "centerText" and "center" or "left"
        end
        db[dest .. "Content"], db[source .. "Content"] = content, "none"
        Notify(dest)
        opts.apply()
        EllesmereUI:RefreshPage(true)
    end

    local addOpen
    local addCfg = { type="button", text="+ Add Text Slot", width=220,
        onClick=function() if addOpen then addOpen() end end,
        disabled=function() return Full() or Candidate() == nil end,
        disabledTooltip="Every text position is full." }
    cells[#cells + 1] = addCfg
    local function Config(c)
        if not c then return EllesmereUI.BlankRowCfg() end
        return c.cfg or c
    end
    local firstRow
    local function Finish(row, side, cell)
        if not cell then return end
        firstRow = firstRow or row
        local rgn = row[side]
        if cell == addCfg then
            if not EllesmereUI._prebuilding then
                addOpen = EllesmereUI.AttachButtonMenu(rgn._control, { width=220,
                    order=order, values=values, setValue=Add,
                    itemDisabled=function(v) return Assigned(v) or Candidate() == nil end })
            end
            return
        end
        if not cell.key then return end
        targets[cell.key] = { row=row, side=side }
        if EllesmereUI._prebuilding then return end
        EllesmereUI.BuildRowLabelMenu(rgn, { order=order, values=values,
            getValue=function() return cell.key end,
            setValue=function(v) Move(cell.key, v) end,
            itemDisabled=function(v)
                if not Assigned(cell.key) then return true end
                if v ~= cell.key and Assigned(v) then return true end
            end,
            tooltip="Choose this text's slot position." })
        cell.decorate(rgn)
        -- The popup writes the format directly, so Spec Overrides needs an accessor:
        -- on a Custom slot, or one holding a format an override may switch back to.
        local fk = cell.key .. "CustomFormat"
        if EllesmereUI.AddCaptureAccessor and cell.cfg.values and cell.cfg.values.custom
           and (cell.cfg.getValue() == "custom" or type(opts.db()[fk]) == "string") then
            EllesmereUI.AddCaptureAccessor(rgn, {
                type = "input", text = cell.position .. " Custom Format",
                getValue = function() return opts.db()[fk] or "" end,
                setValue = function(v)
                    opts.db()[fk] = (v ~= "" and v) or nil
                    opts.apply()
                end,
            })
        end
        local pending = ns._ufTextNotify
        if pending and pending.unit == opts.unit and pending.key == cell.key then
            ns._ufTextNotify = nil
            -- The slot read now, while this build's cell is its dress.
            local snap = EllesmereUI._SOAttribution(rgn)
            EllesmereUI._NotifySettingWrite(rgn, snap)
        end
    end
    for i = 1, #cells, 2 do
        local row, h = W:DualRow(parent, y, Config(cells[i]), Config(cells[i + 1]))
        y = y - h
        Finish(row, "_leftRegion", cells[i])
        Finish(row, "_rightRegion", cells[i + 1])
    end
    parent._ufTextCells = targets
    if not EllesmereUI._prebuilding then
        -- Presets/spec changes can alter the list while the page is cached.
        local saved = {}
        for i = 1, #slots do saved[i] = slots[i].cfg.getValue() end
        ns._ufTextChecks = ns._ufTextChecks or {}
        ns._ufTextChecks[opts.page] = function()
            local db = opts.liveDB()
            for i = 1, #slots do
                if (db[slots[i].key .. "Content"] or slots[i].default) ~= saved[i] then return true end
            end
            return false
        end
    end
    return y, firstRow
end

function ns.UFO_TextClickTarget(parent, key, section, fallback)
    local c = parent._ufTextCells and parent._ufTextCells[key]
    return { section=c and parent._ufTextHeader or section, target=c and c.row or fallback,
        slotSide=c and (c.side == "_leftRegion" and "left" or "right") or nil }
end
