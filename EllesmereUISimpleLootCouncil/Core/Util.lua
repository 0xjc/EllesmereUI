if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil


local issecretvalue = issecretvalue


function addon.IsSecret(...)
    if not issecretvalue then return false end
    local n = select("#", ...)
    if n == 1 then return issecretvalue((...)) and true or false end
    for i = 1, n do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end



function addon.DateText(epoch, utc, short)
    if utc then return short and date("!%d/%m/%y", epoch) or date("!%d/%m/%Y", epoch) end
    return short and date("%d/%m/%y", epoch) or date("%d/%m/%Y", epoch)
end


function addon.StoredDateText(text, short)
    local y, m, d = tostring(text):match("^(%d%d%d%d)/(%d%d)/(%d%d)$")
    if not y then return text end
    return ("%s/%s/%s"):format(d, m, short and y:sub(3) or y)
end
