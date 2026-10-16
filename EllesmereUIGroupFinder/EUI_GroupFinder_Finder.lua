if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EUI_GroupFinder_Finder.lua: Dungeon / Raid Finder layout. Centred dropdown
-- and roles, rewards as a centred table, our checkboxes. Positions and our own
-- textures only, out of combat.
-------------------------------------------------------------------------------
local _, ns = ...
local EUI = EllesmereUI

local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

function ns.Finder_Enable()
    if not PVEFrame or InCombatLockdown() then return end
    local DropdownIcons
    local FINDERS = {
        { frame = "LFDQueueFrame", dropdown = "LFDQueueFrameTypeDropdown", dropY = 287, roleY = 334,
          rewards = "LFDQueueFrameRandomScrollFrameChildFrame" },
        { frame = "RaidFinderQueueFrame", dropdown = "RaidFinderQueueFrameSelectionDropdown", dropY = 289, roleY = 336,
          rewards = "RaidFinderQueueFrameScrollFrameChildFrame" },
    }
    local DD_W = 270  -- Blizzard's menu is at least as wide as the button
    local function LayoutFinder(f)
        local q = _G[f.frame]
        if not q or (InCombatLockdown() and q:IsProtected()) then return end
        local dd = _G[f.dropdown]
        if dd then
            dd:SetWidth(DD_W)
            dd:ClearAllPoints()
            dd:SetPoint("BOTTOM", q, "BOTTOM", 0, f.dropY)
            local label = _G[f.dropdown .. "Name"]
            if label then label:SetAlpha(0) end
            local text = dd.Text
            if text and text.GetFont then
                local d = GetFFD(dd)
                local path, size, flags = text:GetFont()
                if not d.gfTextSize then d.gfTextSize = size end
                if path and d.gfTextSize then text:SetFont(path, d.gfTextSize - 1, flags) end
            end
        end
        local tank, heal, dps = _G[f.frame .. "RoleButtonTank"], _G[f.frame .. "RoleButtonHealer"], _G[f.frame .. "RoleButtonDPS"]
        if tank and heal and dps then
            heal:ClearAllPoints()
            heal:SetPoint("BOTTOM", q, "BOTTOM", 0, f.roleY)
            tank:ClearAllPoints()
            tank:SetPoint("RIGHT", heal, "LEFT", -24, 0)
            dps:ClearAllPoints()
            dps:SetPoint("LEFT", heal, "RIGHT", 24, 0)
        end
        local guide = _G[f.frame .. "RoleButtonLeader"]
        if guide and dps then
            local sc = 0.7
            guide:SetScale(sc)
            guide:ClearAllPoints()
            -- Scaled frame, so offsets get divided by the scale.
            local midY = f.roleY + (dps:GetHeight() or 0) / 2
            guide:SetPoint("RIGHT", q, "BOTTOMRIGHT", -14 / sc, midY / sc)
        end
    end
    -- The dice / killed-bosses icons live in the clipping rewards frame, so we
    -- show our own copies by the dropdown.
    local DD_ICONS = {
        { key = "randomList",    tex = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",          tip = "LFGRandomList_OnEnter" },
        { key = "encounterList", tex = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew", tip = "LFGRewardsFrameEncounterList_OnEnter" },
    }
    DropdownIcons = function(f, parentFrame)
        local q, dd = _G[f.frame], _G[f.dropdown]
        if not (q and dd) then return end
        local d = GetFFD(q)
        d.gfIcons = d.gfIcons or {}
        local prev = dd
        for _, spec in ipairs(DD_ICONS) do
            local src = parentFrame[spec.key]
            if src then
                local b = d.gfIcons[spec.key]
                if not b then
                    b = CreateFrame("Frame", nil, q)
                    b:SetSize(18, 18)
                    local t = b:CreateTexture(nil, "ARTWORK")
                    t:SetAllPoints()
                    t:SetTexture(spec.tex)
                    b:EnableMouse(true)
                    b:SetScript("OnEnter", function(self)
                        self.randomID, self.dungeonID = src.randomID, src.dungeonID
                        local fn = _G[spec.tip]
                        if fn then fn(self) end
                    end)
                    b:SetScript("OnLeave", GameTooltip_Hide)
                    d.gfIcons[spec.key] = b
                end
                src:SetAlpha(0)
                src:EnableMouse(false)
                local on = src:IsShown()
                b:SetShown(on)
                if on then
                    b:ClearAllPoints()
                    b:SetPoint("LEFT", prev, "RIGHT", prev == dd and 8 or 4, 0)
                    prev = b
                end
            end
        end
    end
    local gfNameOff  -- name offset inside a reward button
    local gfLineX  -- panel centre line in rewards-frame x
    local function LayoutRewards(parentFrame)
        if not parentFrame or InCombatLockdown() then return end
        local name = parentFrame.GetName and parentFrame:GetName()
        local q, fin
        for _, f in ipairs(FINDERS) do if name == f.rewards then q, fin = _G[f.frame], f end end
        if not q then return end
        DropdownIcons(fin, parentFrame)
        -- Everything centres on the queue panel's centre line.
        local qc = q.GetCenter and q:GetCenter()
        local cl = parentFrame.GetLeft and parentFrame:GetLeft()
        if qc and cl then gfLineX = qc - cl end
        local lineX = gfLineX or 163
        -- Fade the title and description; centre 'Rewards' and its line.
        if parentFrame.title then parentFrame.title:SetAlpha(0) end
        if parentFrame.description then parentFrame.description:SetAlpha(0) end
        local prev
        for _, k in ipairs({ "rewardsLabel", "rewardsDescription" }) do
            local fs = parentFrame[k]
            if fs then
                fs:SetJustifyH("CENTER")
                fs:SetWidth(280)
                fs:ClearAllPoints()
                if prev then
                    fs:SetPoint("TOP", prev, "BOTTOM", 0, k == "rewardsLabel" and -10 or -5)
                else
                    fs:SetPoint("TOP", parentFrame, "TOPLEFT", lineX, -8)
                end
                prev = fs
            end
        end
        -- Rewards as a centred two-column table: icon, then name.
        local rows = {}
        for i = 1, 20 do
            local it = _G[name .. "Item" .. i]
            if not (it and it:IsShown()) then break end
            rows[#rows + 1] = it
        end
        if parentFrame.MoneyReward and parentFrame.MoneyReward:IsShown() then rows[#rows + 1] = parentFrame.MoneyReward end
        if #rows == 0 then return end
        local desc = parentFrame.rewardsDescription
        local over = (desc and desc:IsShown()) and desc or parentFrame.rewardsLabel
        if not over then return end
        local function NameOf(b)
            return b.Name or (b.GetName and b:GetName() and _G[b:GetName() .. "Name"])
        end
        local function Place()
            -- Name offset in the button, measured once (~43 until then).
            local off = gfNameOff or 43
            local tableW = 0
            for _, b in ipairs(rows) do
                local fs = NameOf(b)
                if fs and fs.SetWidth then
                    fs:SetWidth(180)  -- keep it on one line
                    if fs.SetWordWrap then fs:SetWordWrap(false) end
                end
                -- Text width, 0 until the client measures it.
                local tw = 0
                if fs and fs.GetUnboundedStringWidth then tw = fs:GetUnboundedStringWidth() or 0
                elseif fs and fs.GetStringWidth then tw = fs:GetStringWidth() or 0 end
                tableW = math.max(tableW, off + math.min(tw, 180))
            end
            local x = 140 - tableW / 2
            for i, b in ipairs(rows) do
                b:ClearAllPoints()
                if i == 1 then
                    b:SetPoint("TOPLEFT", over, "BOTTOMLEFT", x, -14)
                else
                    b:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -6)
                end
            end
            -- Experience under the last row.
            local xp = parentFrame.xpLabel
            if xp and xp:IsShown() then
                xp:ClearAllPoints()
                xp:SetPoint("TOPLEFT", rows[#rows], "BOTTOMLEFT", 0, -10)
            end
        end
        Place()
        -- Again next frame, once the names are measured (otherwise it lands off
        -- centre).
        local probe = NameOf(rows[1])
        C_Timer.After(0, function()
            if InCombatLockdown() then return end
            if not gfNameOff and probe and probe.GetLeft then
                local l, nlft = rows[1]:GetLeft(), probe:GetLeft()
                if l and nlft and nlft > l then gfNameOff = nlft - l end
            end
            Place()
        end)
    end
    -- Role checkboxes in our checkbox look.
    local function PaintRoleCheck(cb)
        local d = FFD[cb]
        if not d or not d.gfBox then return end
        local a = EUI.ELLESMERE_GREEN or { r = 0.89, g = 0.83, b = 0.69 }
        local on, enabled = cb:GetChecked() and true or false, cb:IsEnabled()
        d.gfFill:SetShown(on)
        if on then d.gfRing:SetColor(a.r, a.g, a.b, 0.8) else d.gfRing:SetColor(0.25, 0.25, 0.25, 0.6) end
        d.gfBox:SetAlpha(enabled and 1 or 0.4)
    end
    local function SkinRoleCheck(btn)
        local cb = btn and btn.checkButton
        if not cb or GetFFD(cb).gfBox then return end
        local d = GetFFD(cb)
        for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetCheckedTexture", "GetDisabledCheckedTexture", "GetHighlightTexture" }) do
            local t = cb[g] and cb[g](cb)
            if t then t:SetAlpha(0) end
        end
        local box = CreateFrame("Frame", nil, cb)
        box:SetSize(24, 24)  -- about 17 on screen at 0.7 scale
        box:SetPoint("CENTER")
        box:SetFrameLevel(cb:GetFrameLevel() + 2)
        box:EnableMouse(false)
        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.12, 0.12, 0.12, 1)
        d.gfRing = EUI.MakeBorder(box, 0.25, 0.25, 0.25, 0.6, EUI.PanelPP)
        local a = EUI.ELLESMERE_GREEN or { r = 0.89, g = 0.83, b = 0.69 }
        d.gfFill = box:CreateTexture(nil, "ARTWORK")
        d.gfFill:SetPoint("TOPLEFT", box, "TOPLEFT", 5, -5)
        d.gfFill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -5, 5)
        d.gfFill:SetColorTexture(a.r, a.g, a.b, 1)
        d.gfBox = box
        hooksecurefunc(cb, "SetChecked", PaintRoleCheck)
        if cb.SetEnabled then hooksecurefunc(cb, "SetEnabled", PaintRoleCheck) end
        if cb.Enable then hooksecurefunc(cb, "Enable", PaintRoleCheck) end
        if cb.Disable then hooksecurefunc(cb, "Disable", PaintRoleCheck) end
        cb:HookScript("OnClick", PaintRoleCheck)
        PaintRoleCheck(cb)
    end
    for _, f in ipairs(FINDERS) do
        LayoutFinder(f)
        for _, role in ipairs({ "Tank", "Healer", "DPS", "Leader" }) do
            SkinRoleCheck(_G[f.frame .. "RoleButton" .. role])
        end
    end
    if not GetFFD(PVEFrame).gfLFD then
        GetFFD(PVEFrame).gfLFD = true
        for _, f in ipairs(FINDERS) do
            local q = _G[f.frame]
            if q then q:HookScript("OnShow", function() LayoutFinder(f) end) end
            LayoutRewards(_G[f.rewards])
        end
        if LFGRewardsFrame_UpdateFrame then hooksecurefunc("LFGRewardsFrame_UpdateFrame", LayoutRewards) end
    end
end
