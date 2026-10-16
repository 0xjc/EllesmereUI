-------------------------------------------------------------------------------
--  Hooks + events
-------------------------------------------------------------------------------
-- Golden borders + watcher seed-absorption on page changes. RefreshPage only
-- rebuilds rows when forced; the fast path neither seeds nor re-rows.
if EllesmereUI.SelectModule then
    hooksecurefunc(EllesmereUI, "SelectModule", OnPageRebuilt)
end
if EllesmereUI.SelectPage then
    hooksecurefunc(EllesmereUI, "SelectPage", OnPageRebuilt)
end
if EllesmereUI.RefreshPage then
    hooksecurefunc(EllesmereUI, "RefreshPage", function(_, force)
        if force then
            _watchResync = true
        end
        RequestGoldWalk()
    end)
end


local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("PLAYER_LOGIN")
evFrame:RegisterEvent("PLAYER_LOGOUT")
evFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
evFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- De-alias repair for stores that banked live TABLE references, which aliased
        -- the store to the live profile (any later live edit silently mutated the
        -- stored "override"). DeepCopy every table-typed value once so stores own their
        -- data. Harvests skip table values, so it cannot recur.
        local function DeAlias(store)
            for _, e in ipairs(store or {}) do
                if e.values then
                    for _, m in pairs(e.values) do
                        if type(m) == "table" then
                            for fkey, v in pairs(m) do
                                if type(v) == "table" then m[fkey] = DeepCopy(v) end
                            end
                        end
                    end
                end
            end
        end
        DeAlias(GetStore())
        if EllesmereUI._CondOv then DeAlias(EllesmereUI._CondOv.GetStore()) end
        -- One-time tidy: drop orphaned entries plus fkeys no group holds a value for.
        PruneOrphanEntries()
        PruneRedundantValues()
        if EllesmereUI._CondOv then
            EllesmereUI._CondOv.PruneEntries()
            EllesmereUI._CondOv.PruneRedundant()
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Keep the current spec's stored values in sync with live edits so a
        -- shared profile opened on another character applies fresh data. Also
        -- banks + restores an active Editing-as session.
        EllesmereUI.SpecOverrides_HarvestCurrent()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if _combatFolders then
            local fl = _combatFolders
            _combatFolders = nil
            RunRefreshers(fl)
        end
    end
end)


