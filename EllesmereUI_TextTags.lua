if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_TextTags.lua
--  Custom text templates ("[hp:abr] | [hp:pct]%"): shared tag schema, parser,
--  preview and help text. Pure string logic: no frames, events or units.
--  A module binds the schema keys it draws to its own pieces (Bind) and paints
--  the parse through its own path: fmt has one %s per tag, keys names each one.
--  Secret values, DEAD/OFFLINE and abbreviation stay in the module's pieces.
--------------------------------------------------------------------------------
EllesmereUI = EllesmereUI or {}
local EllesmereUI = EllesmereUI

local type, pairs, error, tostring = type, pairs, error, tostring
local sfind, ssub, slower, sgsub, sformat = string.find, string.sub, string.lower, string.gsub, string.format
local tconcat, unpack = table.concat, unpack

local TextTags = {}
EllesmereUI.TextTags = TextTags

-------------------------------------------------------------------------------
--  Unit schema
--  reads: the value a key shows -- "hp", "pp", "abs", "habs", "id" (name or
--  level, changes on identity events only), "tgt" (the unit's target),
--  "roster" (group membership). width: estimated pixels. sample: preview value.
-------------------------------------------------------------------------------
TextTags.UNIT = {
    mods = { "max", "abr", "pct" },  -- order of the modifiers inside a key
    modAliases = { percent = "pct" },
    tags = {  -- order of the help text
        { tag = "hp", aliases = { "health" }, keys = { "hp", "hp:abr", "hp:max", "hp:max:abr", "hp:pct" } },
        { tag = "pp", aliases = { "power" }, keys = { "pp", "pp:abr", "pp:max", "pp:max:abr", "pp:pct" } },
        { tag = "absorb", keys = { "absorb", "absorb:abr" } },
        { tag = "healabsorb", keys = { "healabsorb", "healabsorb:abr" } },
        { tag = "name", keys = { "name" } },
        { tag = "target", keys = { "target" } },
        { tag = "level", keys = { "level" } },
        { tag = "group", keys = { "group" } },
    },
    keys = {
        ["hp"]             = { reads = "hp", width = 45, sample = "132456" },
        ["hp:abr"]         = { reads = "hp", width = 38, sample = "132 K" },
        ["hp:max"]         = { reads = "hp", width = 45, sample = "150000" },
        ["hp:max:abr"]     = { reads = "hp", width = 38, sample = "150 K" },
        ["hp:pct"]         = { reads = "hp", width = 30, sample = "88" },
        ["pp"]             = { reads = "pp", width = 45, sample = "31250" },
        ["pp:abr"]         = { reads = "pp", width = 38, sample = "31 K" },
        ["pp:max"]         = { reads = "pp", width = 45, sample = "50000" },
        ["pp:max:abr"]     = { reads = "pp", width = 38, sample = "50 K" },
        ["pp:pct"]         = { reads = "pp", width = 30, sample = "62" },
        ["absorb"]         = { reads = "abs", width = 45, sample = "12345" },
        ["absorb:abr"]     = { reads = "abs", width = 38, sample = "12 K" },
        ["healabsorb"]     = { reads = "habs", width = 45, sample = "4200" },
        ["healabsorb:abr"] = { reads = "habs", width = 38, sample = "4 K" },
        ["name"]           = { reads = "id", width = 80, sample = "Thrall" },
        ["target"]         = { reads = "tgt", width = 80, sample = "Jaina" },
        ["level"]          = { reads = "id", width = 24, sample = "80" },
        ["group"]          = { reads = "roster", width = 10, sample = "3" },
    },
    -- Built on demand: the active locale is resolved only at ADDON_LOADED.
    descs = function()
        return {
            ["hp"] = EllesmereUI.L("Current health"),
            ["hp:abr"] = EllesmereUI.L("Current health, abbreviated"),
            ["hp:max"] = EllesmereUI.L("Maximum health"),
            ["hp:max:abr"] = EllesmereUI.L("Maximum health, abbreviated"),
            ["hp:pct"] = EllesmereUI.L("Health percent, number only"),
            ["pp"] = EllesmereUI.L("Current power"),
            ["pp:abr"] = EllesmereUI.L("Current power, abbreviated"),
            ["pp:max"] = EllesmereUI.L("Maximum power"),
            ["pp:max:abr"] = EllesmereUI.L("Maximum power, abbreviated"),
            ["pp:pct"] = EllesmereUI.L("Power percent, number only"),
            ["absorb"] = EllesmereUI.L("Absorb shield"),
            ["absorb:abr"] = EllesmereUI.L("Absorb shield, abbreviated"),
            ["healabsorb"] = EllesmereUI.L("Heal absorb"),
            ["healabsorb:abr"] = EllesmereUI.L("Heal absorb, abbreviated"),
            ["name"] = EllesmereUI.L("Unit name"),
            ["target"] = EllesmereUI.L("Name of the unit's target"),
            ["level"] = EllesmereUI.L("Unit level"),
            ["group"] = EllesmereUI.L("Raid group number"),
        }
    end,
    examples = { "[hp:abr] | [hp:pct]%", "[name] [level]", "[pp]/[pp:max]", "[hp:max:abr]" },
}

-------------------------------------------------------------------------------
--  Bind: a catalog is the schema narrowed to the keys a module draws. map is
--  { schema key = the module's own piece }; the core never looks at the values.
--  A key the module leaves out is unknown to that catalog.
-------------------------------------------------------------------------------
function TextTags.Bind(schema, map)
    local cat = { schema = schema, map = {}, keys = {}, tags = {}, names = {}, mods = {}, cache = {}, count = 0 }
    for key, v in pairs(map) do
        if not schema.keys[key] then error("TextTags.Bind: unknown key " .. tostring(key), 2) end
        cat.map[key] = v
    end
    for i = 1, #schema.tags do
        local def, bound = schema.tags[i], {}
        for k = 1, #def.keys do
            local key = def.keys[k]
            if cat.map[key] ~= nil then
                bound[#bound + 1] = key
                cat.keys[#cat.keys + 1] = key
            end
        end
        if #bound > 0 then
            cat.tags[#cat.tags + 1] = { tag = def.tag, aliases = def.aliases, keys = bound }
            cat.names[def.tag] = def.tag
            if def.aliases then
                for a = 1, #def.aliases do cat.names[def.aliases[a]] = def.tag end
            end
        end
    end
    for i = 1, #schema.mods do cat.mods[schema.mods[i]] = schema.mods[i] end
    if schema.modAliases then
        for alias, mod in pairs(schema.modAliases) do cat.mods[alias] = mod end
    end
    return cat
end

-------------------------------------------------------------------------------
--  Parse
-------------------------------------------------------------------------------
local function Escape(s)
    return (sgsub(sgsub(s, "%%", "%%%%"), "|", "||"))
end

-- "hp:ABR:max" -> "hp:max:abr" when the catalog binds it, else nil. Modifier
-- order is free; an empty part, an unknown or a repeated modifier is no key.
local modSeen = {}
local function ResolveKey(cat, inner)
    inner = slower(inner)
    local s, e = sfind(inner, ":", 1, true)
    local tag = cat.names[s and ssub(inner, 1, s - 1) or inner]
    if not tag then return nil end
    if not s then return cat.map[tag] ~= nil and tag or nil end
    for k in pairs(modSeen) do modSeen[k] = nil end
    local pos = e + 1
    while true do
        local ns = sfind(inner, ":", pos, true)
        local mod = cat.mods[ssub(inner, pos, (ns or 0) - 1)]
        if not mod or modSeen[mod] then return nil end
        modSeen[mod] = true
        if not ns then break end
        pos = ns + 1
    end
    local order, key = cat.schema.mods, tag
    for i = 1, #order do
        if modSeen[order[i]] then key = key .. ":" .. order[i] end
    end
    return cat.map[key] ~= nil and key or nil
end

local strlen = strlenutf8 or string.len

--- Parses a template against a catalog: nil for an empty or non-string one,
--- else { fmt, keys, has, reads, literalChars, unknown }. fmt is escaped with
--- one %s per tag, keys the schema key of each, has / reads sets of the keys
--- and value classes used, literalChars the UTF-8 length outside the tags,
--- unknown the bracketed text that is no bound key (left as typed, no repeats).
--- "%" is escaped and "|" doubled: no colour or texture escape can be typed.
--- The result is cached and shared by every reader: read-only by contract.
function TextTags.Parse(cat, template)
    if type(template) ~= "string" or template == "" then return nil end
    local hit = cat.cache[template]
    if hit then return hit end
    local fmt, literal, keys, has, reads, unknown, seen = {}, {}, {}, {}, {}, {}, {}
    local pos = 1
    while true do
        local s, e, inner = sfind(template, "%[([%w:]+)%]", pos)
        local lit = ssub(template, pos, (s or 0) - 1)
        local key = s and ResolveKey(cat, inner)
        if s and not key then
            local raw = ssub(template, s, e)
            lit = lit .. raw
            if not seen[raw] then
                seen[raw] = true
                unknown[#unknown + 1] = raw
            end
        end
        fmt[#fmt + 1] = Escape(lit)
        literal[#literal + 1] = lit
        if key then
            fmt[#fmt + 1] = "%s"
            keys[#keys + 1] = key
            has[key] = true
            reads[cat.schema.keys[key].reads] = true
        end
        if not s then break end
        pos = e + 1
    end
    hit = {
        fmt = tconcat(fmt), keys = keys, has = has, reads = reads,
        literalChars = strlen(tconcat(literal)), unknown = unknown,
    }
    if cat.count >= 64 then cat.cache, cat.count = {}, 0 end
    cat.cache[template] = hit
    cat.count = cat.count + 1
    return hit
end

-------------------------------------------------------------------------------
--  Preview, width, help
-------------------------------------------------------------------------------
local scratch = {}

--- The parse filled with the schema's samples.
function TextTags.Preview(cat, parsed)
    local keys, defs = parsed.keys, cat.schema.keys
    for i = 1, #keys do scratch[i] = defs[keys[i]].sample end
    return sformat(parsed.fmt, unpack(scratch, 1, #keys))
end

--- Estimated pixel width: each key's schema width, 5 per literal character.
--- override(key), when given, may return a number to replace a key's width.
function TextTags.EstimateWidth(cat, parsed, override)
    local keys, defs = parsed.keys, cat.schema.keys
    local w = parsed.literalChars * 5
    for i = 1, #keys do
        local key = keys[i]
        w = w + (override and override(key) or defs[key].width)
    end
    return w
end

--- The info text for the popup: syntax, the bound tags with their variants,
--- aliases, and examples with their result. opts (optional):
---   examples  templates to show instead of the schema's; any that use an
---             unbound key are skipped
---   notes     extra lines appended at the end (already localized)
function TextTags.HelpText(cat, opts)
    local descs = cat.schema.descs and cat.schema.descs() or {}
    local lines = {
        EllesmereUI.L("Tags go in square brackets, everything else is shown as typed."),
        EllesmereUI.L("Add modifiers with a colon, in any order: [hp:max:abr]"),
        "",
    }
    local aliases = {}
    for i = 1, #cat.tags do
        local t = cat.tags[i]
        for k = 1, #t.keys do
            local key = t.keys[k]
            lines[#lines + 1] = descs[key] and ("[" .. key .. "]  " .. descs[key]) or ("[" .. key .. "]")
        end
        if t.aliases then
            for a = 1, #t.aliases do aliases[#aliases + 1] = "[" .. t.aliases[a] .. "] = [" .. t.tag .. "]" end
        end
    end
    local modAliases = cat.schema.modAliases
    if modAliases then
        for alias, mod in pairs(modAliases) do aliases[#aliases + 1] = alias .. " = " .. mod end
    end
    if #aliases > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = EllesmereUI.Lf("Also accepted: %s", tconcat(aliases, ", "))
    end
    local examples = opts and opts.examples or cat.schema.examples
    local shown = 0
    for i = 1, #(examples or {}) do
        local parsed = TextTags.Parse(cat, examples[i])
        if parsed and #parsed.unknown == 0 then
            if shown == 0 then
                lines[#lines + 1] = ""
                lines[#lines + 1] = EllesmereUI.L("Examples:")
            end
            shown = shown + 1
            lines[#lines + 1] = sgsub(examples[i], "|", "||") .. "  ->  " .. TextTags.Preview(cat, parsed)
        end
    end
    local notes = opts and opts.notes
    if notes and #notes > 0 then
        lines[#lines + 1] = ""
        for i = 1, #notes do lines[#lines + 1] = notes[i] end
    end
    return tconcat(lines, "\n")
end

--- Fills the options of EllesmereUI:ShowInputPopup for a template field and
--- returns them: preview (the sample line and a hint naming unknown tags),
--- infoTooltip (the help text, built on hover) and infoTooltipOpts. helpOpts
--- goes to TextTags.HelpText.
function TextTags.PopupOpts(cat, opts, helpOpts)
    opts = opts or {}
    opts.preview = function(text)
        local parsed = TextTags.Parse(cat, text)
        if not parsed then return nil, nil end
        local hint
        if #parsed.unknown > 0 then
            hint = EllesmereUI.Lf("Unknown tags, shown as typed: %s", tconcat(parsed.unknown, ", "))
        end
        return EllesmereUI.Lf("Preview: %s", TextTags.Preview(cat, parsed)), hint
    end
    opts.infoTooltip = function() return TextTags.HelpText(cat, helpOpts) end
    opts.infoTooltipOpts = { width = 360, justify = "LEFT", anchorPoint = "TOPLEFT", anchorTo = "TOPRIGHT", anchorX = 8 }
    return opts
end
