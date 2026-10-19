if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local SharedSaved = {}
addon.SharedSaved = SharedSaved


local KEYED = { "history", "imported", "historySnapshots", "specs" }


local KINDS = { history = true, imported = true, nights = true, members = true }
local FORGET_AFTER = 365 * 24 * 60 * 60

local function Valid(n)
    return type(n) == "number" and n == n and n > 0 and n < math.huge
end


local function NightKey(night)
    local key = type(night) == "table" and night.startedAt
    return Valid(key) and key or nil
end
SharedSaved.NightKey = NightKey

local function MemberKey(nightKey, name)
    return tostring(nightKey) .. "|" .. tostring(name)
end
SharedSaved.MemberKey = MemberKey


function SharedSaved.Forget(db, kind, key, now)
    if type(db) ~= "table" or not KINDS[kind] or key == nil then return end
    if type(db.deleted) ~= "table" then db.deleted = {} end
    local list = db.deleted[kind]
    if type(list) ~= "table" then
        list = {}
        db.deleted[kind] = list
    end
    list[key] = now or GetServerTime()
end


function SharedSaved.Expire(db, now)
    local deleted = type(db) == "table" and db.deleted
    if type(deleted) ~= "table" then return end
    local cutoff = (now or GetServerTime()) - FORGET_AFTER
    for kind, list in pairs(deleted) do
        if not KINDS[kind] or type(list) ~= "table" then
            deleted[kind] = nil
        else
            for key, at in pairs(list) do
                if not Valid(at) or at < cutoff then list[key] = nil end
            end
        end
    end
end






local SESSION_START = "^%-%-%-%s(%d+)%-(%d+)%-(%d+)%s(%d+):(%d+):(%d+)%ssession%sstart"


local function LastActivity(db)
    local newest = 0
    if type(db.history) == "table" then
        for _, row in pairs(db.history) do
            local epoch = type(row) == "table" and row.epoch
            if Valid(epoch) and epoch > newest then newest = epoch end
        end
    end
    if type(db.log) == "table" then
        for i = #db.log, 1, -1 do
            local line = db.log[i]
            if type(line) == "string" then
                local y, mo, d, h, mi, s = line:match(SESSION_START)
                if y then
                    local ok, at = pcall(time, { year = tonumber(y), month = tonumber(mo),
                        day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
                    if ok and Valid(at) and at > newest then newest = at end
                    break
                end
            end
        end
    end
    return newest
end


local function MirrorIsNewer(own, mirror)
    local a = Valid(own.savedAt) and own.savedAt or nil
    local b = Valid(mirror.savedAt) and mirror.savedAt or nil
    if a and b then return b > a end
    if a or b then return b ~= nil end
    return LastActivity(mirror) > LastActivity(own)
end






local STAMPED = { history = true, imported = true }


local function EditedLater(a, b)
    local x = type(a) == "table" and Valid(a.editedAt) and a.editedAt or nil
    local y = type(b) == "table" and Valid(b.editedAt) and b.editedAt or nil
    if x and y then return x > y end
    return x ~= nil
end



local function MergeKeyed(winner, loser, field)
    local from = loser[field]
    if type(from) ~= "table" then return 0 end
    local into = winner[field]
    if type(into) ~= "table" then
        into = {}
        winner[field] = into
    end
    local added = 0
    for key, value in pairs(from) do
        if into[key] == nil or (STAMPED[field] and EditedLater(value, into[key])) then
            into[key] = value
            added = added + 1
        end
    end
    return added
end


local function Extends(a, b)
    if type(a.seen) ~= "table" or type(b.seen) ~= "table" then return false end
    for id in pairs(b.seen) do
        if not a.seen[id] then return false end
    end
    for id in pairs(a.seen) do
        if not b.seen[id] then return true end
    end
    return false
end


local function MergeNights(winner, loser)
    local from = type(loser.attendance) == "table" and loser.attendance.nights
    if type(from) ~= "table" or #from == 0 then return 0 end
    if type(winner.attendance) ~= "table" then winner.attendance = {} end
    local into = winner.attendance.nights
    if type(into) ~= "table" then
        into = {}
        winner.attendance.nights = into
    end

    local at = {}
    for i, night in ipairs(into) do
        local key = NightKey(night)
        if key then at[key] = i end
    end
    local changed = 0
    for _, night in ipairs(from) do
        local key = NightKey(night)
        local i = key and at[key]
        if key and not i then
            into[#into + 1] = night
            at[key] = #into
            changed = changed + 1
        elseif i and Extends(night, into[i]) then
            into[i] = night
            changed = changed + 1
        end
    end
    if changed > 0 then
        table.sort(into, function(a, b) return (NightKey(a) or 0) < (NightKey(b) or 0) end)
    end
    return changed
end


local function MergeDeleted(winner, loser)
    local from = type(loser.deleted) == "table" and loser.deleted or {}
    if type(winner.deleted) ~= "table" then winner.deleted = {} end
    local into = winner.deleted
    for kind in pairs(KINDS) do
        if type(from[kind]) == "table" then
            if type(into[kind]) ~= "table" then into[kind] = {} end
            local list = into[kind]
            for key, when in pairs(from[kind]) do
                if not Valid(list[key]) or (Valid(when) and when > list[key]) then list[key] = when end
            end
        end
    end
end


local function ApplyDeleted(db)
    local deleted, removed = db.deleted, 0
    if type(deleted) ~= "table" then return 0 end
    for _, kind in ipairs({ "history", "imported" }) do
        local store, gone = db[kind], deleted[kind]
        if type(store) == "table" and type(gone) == "table" then
            for key in pairs(gone) do
                if store[key] ~= nil then
                    store[key] = nil
                    removed = removed + 1
                end
            end
        end
    end

    local nights = type(db.attendance) == "table" and db.attendance.nights
    if type(nights) ~= "table" then return removed end
    local wholeGone = type(deleted.nights) == "table" and deleted.nights or {}
    local memberGone = type(deleted.members) == "table" and deleted.members or {}
    local kept = {}
    for _, night in ipairs(nights) do
        local key = NightKey(night)
        if key and wholeGone[key] then
            removed = removed + 1
        else
            if key and type(night.members) == "table" and next(memberGone) then
                for name in pairs(night.members) do
                    if memberGone[MemberKey(key, name)] then
                        night.members[name] = nil
                        if type(night.memberKills) == "table" then night.memberKills[name] = nil end
                        removed = removed + 1
                    end
                end
            end
            kept[#kept + 1] = night
        end
    end
    db.attendance.nights = kept
    return removed
end



function SharedSaved.Reconcile(own, mirror)
    if type(own) ~= "table" then own = {} end
    if type(mirror) ~= "table" or mirror == own then return own end

    local mirrorNewer = MirrorIsNewer(own, mirror)
    local winner, loser = own, mirror
    if mirrorNewer then winner, loser = mirror, own end

    if addon.RunMigrations then addon.RunMigrations(loser) end

    local merged = 0
    for _, field in ipairs(KEYED) do merged = merged + MergeKeyed(winner, loser, field) end
    merged = merged + MergeNights(winner, loser)
    MergeDeleted(winner, loser)
    local removed = ApplyDeleted(winner)

    winner.deleted = nil

    if addon.Log then
        addon.Log:I("Saved", "shared saved variables:", mirrorNewer and "the standalone's" or "the module's",
            "file is newer;", merged, "record(s) merged,", removed, "deleted")
    end
    return winner
end
