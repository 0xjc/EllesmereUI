if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Shared dot art and passive connection endpoints. Nothing is built until used.
local _, ns = ...
ns = ns.__euiCoreNS or ns
local visuals = {}
ns.PointVisuals = visuals
local DOT_MASK = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_mask.tga"
visuals.idleSize, visuals.hoverSize = 8, 12

function visuals.CreateDot(parent)
    local art = CreateFrame("Frame", nil, parent)
    art:EnableMouse(false)
    local fill = art:CreateTexture(nil, "OVERLAY")
    fill:SetAllPoints(art)
    fill:SetColorTexture(1, 1, 1, 1)
    fill:SetVertexColor(1, 0.2, 0.2, 1)
    fill:SetSnapToPixelGrid(false)
    fill:SetTexelSnappingBias(0)
    local mask = art:CreateMaskTexture()
    mask:SetTexture(DOT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
    -- The portrait mask pads the circle by 12 transparent texels on each edge.
    mask:SetTexCoord(12 / 128, 116 / 128, 12 / 128, 116 / 128)
    mask:SetAllPoints(art)
    mask:SetSnapToPixelGrid(false)
    mask:SetTexelSnappingBias(0)
    fill:AddMaskTexture(mask)
    art.fill = fill
    return art
end

local markers
local function ShowPoint(index, mover, point, alpha)
    local marker = markers[index]
    if not marker then
        marker = visuals.CreateDot(mover)
        markers[index] = marker
    end
    if marker:GetParent() ~= mover then marker:SetParent(mover) end
    local level = mover:GetFrameLevel() + 25
    if marker:GetFrameLevel() ~= level then marker:SetFrameLevel(level) end
    if marker.point ~= point or marker.mover ~= mover then
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", mover, point)
        marker.point, marker.mover = point, mover
    end
    local pp = EllesmereUI.PP
    local size = visuals.idleSize * ((pp and pp.perfect) or 1) / marker:GetEffectiveScale()
    if marker:GetWidth() ~= size then marker:SetSize(size, size) end
    marker:SetAlpha(alpha)
    marker:Show()
end

function visuals.Connection(index, source, sourcePoint, target, targetPoint, alpha)
    markers = markers or {}
    ShowPoint(index * 2 - 1, source, sourcePoint, alpha)
    ShowPoint(index * 2, target, targetPoint, alpha)
end

function visuals.TrimConnections(count)
    if not markers then return end
    for i = count * 2 + 1, #markers do markers[i]:Hide() end
end
