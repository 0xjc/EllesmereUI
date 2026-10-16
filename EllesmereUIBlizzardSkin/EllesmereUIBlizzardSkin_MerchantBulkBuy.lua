if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local ADDON_NAME, ns = ...
local WSkin = ns.WSkin
if not WSkin then return end

local EUI = EllesmereUI
local Theme = WSkin.Theme
local floor, min, max = math.floor, math.min, math.max
local band = bit.band

local BAGS = { BACKPACK_CONTAINER }
for bag = 1, NUM_BAG_SLOTS do BAGS[#BAGS + 1] = bag end
local REAGENT_BAG = Enum.BagIndex and Enum.BagIndex.ReagentBag
if REAGENT_BAG then BAGS[#BAGS + 1] = REAGENT_BAG end

local events = CreateFrame("Frame")
local dialog, job, hooked

local function Enabled()
    return EllesmereUIDB and EllesmereUIDB.merchantBulkBuy == true
end

local function Font(fs, size)
    EUI.PrimeFontShadow(fs, Theme.fontShadow)
    fs:SetFont(Theme.fontPath, size, Theme.fontFlag or "")
end

local function BagRoom(itemID)
    local stackSize = C_Item.GetItemMaxStackSizeByID(itemID) or 1
    local family = C_Item.GetItemFamily(itemID) or 0
    local isReagent = select(17, C_Item.GetItemInfo(itemID))
    local room = 0
    for _, bag in ipairs(BAGS) do
        local fits
        if bag == REAGENT_BAG then
            fits = isReagent
        else
            local _, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
            fits = not bagFamily or bagFamily == 0 or band(bagFamily, family) ~= 0
        end
        if fits then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local id = C_Container.GetContainerItemID(bag, slot)
                if not id then
                    room = room + stackSize
                elseif id == itemID then
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    room = room + max(stackSize - (info and info.stackCount or stackSize), 0)
                end
            end
        end
    end
    return room
end

local function MaxBundles(index, info, itemID, step)
    local n = floor(min(BagRoom(itemID), 999999) / step)
    if info.numAvailable >= 0 then n = min(n, info.numAvailable) end
    if info.price > 0 then n = min(n, floor(GetMoney() / info.price)) end
    for i = 1, GetMerchantItemCostInfo(index) or 0 do
        local _, value, link, currencyName = GetMerchantItemCostItem(index, i)
        if link and value and value > 0 then
            local have
            if currencyName then
                local c = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
                have = c and c.quantity
            else
                have = C_Item.GetItemCount(link, false, false, true)
            end
            if have then n = min(n, floor(have / value)) end
        end
    end
    return max(n, 0)
end

local function CostText(index, info, bundles)
    local parts = {}
    if info.price > 0 then
        parts[#parts + 1] = C_CurrencyInfo.GetCoinTextureString(info.price * bundles)
    end
    for i = 1, GetMerchantItemCostInfo(index) or 0 do
        local texture, value = GetMerchantItemCostItem(index, i)
        if texture and value and value > 0 then
            parts[#parts + 1] = (value * bundles) .. " |T" .. texture .. ":0|t"
        end
    end
    return table.concat(parts, "  ")
end

local function SyncEvents()
    if job or (dialog and dialog:IsShown()) then
        events:RegisterEvent("MERCHANT_CLOSED")
    else
        events:UnregisterEvent("MERCHANT_CLOSED")
    end
    if job then
        events:RegisterEvent("BAG_UPDATE_DELAYED")
        events:RegisterEvent("UI_ERROR_MESSAGE")
    else
        events:UnregisterEvent("BAG_UPDATE_DELAYED")
        events:UnregisterEvent("UI_ERROR_MESSAGE")
    end
end

local function StopJob()
    job = nil
    SyncEvents()
end

local function StepJob()
    local j = job
    if not j then return end
    local count = C_Item.GetItemCount(j.itemID)
    if count < j.last then StopJob(); return end
    j.last = count
    local got = count - j.base
    if got < j.issued then return end
    local n = floor(min(j.chunk, j.target - got) / j.step) * j.step
    if n <= 0 or GetMerchantItemID(j.index) ~= j.itemID then StopJob(); return end
    j.issued = got + n
    BuyMerchantItem(j.index, n)
end

local function StartJob(index, itemID, qty, step, chunk)
    if GetMerchantItemID(index) ~= itemID then return end
    local count = C_Item.GetItemCount(itemID)
    job = { index = index, itemID = itemID, target = qty, step = step, chunk = chunk,
            base = count, last = count, issued = 0 }
    SyncEvents()
    StepJob()
end

local function Current()
    local d = dialog
    local n = floor((d._eb:GetNumber() or 0) / d._step) * d._step
    return min(max(n, d._step), d._max)
end

local function ShowCost(qty)
    local d = dialog
    d._cost:SetText(EllesmereUI.Lf("Total: %s", CostText(d._index, d._info, qty / d._step)))
    d._buy:SetEnabled(qty > 0)
    d._buy:SetAlpha(qty > 0 and 1 or 0.3)
end

local function SetValue(n)
    local d = dialog
    n = floor(n / d._step) * d._step
    n = min(max(n, d._step), d._max)
    d._eb:SetText(tostring(n))
    d._eb:SetCursorPosition(#d._eb:GetText())
    ShowCost(n)
end

local function Refresh()
    local d = dialog
    local index, owner = d._index, d._owner
    local info = (MerchantFrame.selectedTab or 1) == 1 and C_MerchantFrame.GetItemInfo(index)
    if not info or GetMerchantItemID(index) ~= d._itemID or not owner:IsVisible() or owner:GetID() ~= index then
        d:Hide()
        return
    end
    d._info = info
    d._step = max(info.stackCount, 1)
    d._max = MaxBundles(index, info, d._itemID, d._step) * d._step
    d._maxLbl:SetText("/ " .. d._max)
    if d._eb:HasFocus() and d._eb:GetNumber() <= d._max then
        ShowCost(Current())
    else
        SetValue(Current())
    end
end

local function DoBuy()
    local d = dialog
    local qty = Current()
    local index, itemID, step, chunk, info = d._index, d._itemID, d._step, d._chunk, d._info
    d:Hide()
    if qty < step then return end
    local bundles = qty / step
    local function start() StartJob(index, itemID, qty, step, chunk) end
    if info.hasExtendedCost or info.price * bundles >= (MERCHANT_HIGH_PRICE_COST or 1500000) then
        EUI:ShowConfirmPopup({
            title       = "Bulk Buy",
            message     = EllesmereUI.Lf("Buy %1$d x %2$s for %3$s?", qty,
                              GetMerchantItemLink(index) or info.name or "", CostText(index, info, bundles)),
            confirmText = "Buy",
            cancelText  = "Cancel",
            onConfirm   = start,
        })
    else
        start()
    end
end

local function AddStack()
    local d = dialog
    local cur = Current()
    local n = (floor(cur / d._stackSize) + 1) * d._stackSize
    if floor(n / d._step) * d._step <= cur then n = cur + d._step end
    SetValue(n)
end

local function Nudge(dir)
    local d = dialog
    SetValue(Current() + dir * (IsShiftKeyDown() and d._chunk or d._step))
end

local function MakeButton(parent, w, h, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    WSkin.Button(b)
    local fs = b:CreateFontString(nil, "OVERLAY")
    Font(fs, 12)
    fs:SetPoint("CENTER", 0, 0)
    fs:SetTextColor(1, 1, 1, 0.9)
    fs:SetText(label)
    return b
end

local function CreateDialog()
    if not Theme.fontPath then WSkin.ResolveTheme() end
    local d = CreateFrame("Frame", "EUI_MerchantBulkBuyFrame", UIParent)
    d:SetFrameStrata("DIALOG")
    d:SetSize(232, 121)
    d:SetClampedToScreen(true)
    d:EnableMouse(true)
    d:EnableMouseWheel(true)
    d:Hide()
    WSkin.SolidTex(d, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, 1):SetAllPoints()
    WSkin.AddBorder(d)

    local title = d:CreateFontString(nil, "OVERLAY")
    Font(title, 13)
    title:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -9)
    title:SetTextColor(1, 1, 1, 0.9)
    title:SetText(EllesmereUI.L("Bulk Buy"))

    local close = CreateFrame("Button", nil, d)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", d, "TOPRIGHT", -4, -5)
    WSkin.CloseButton(close)
    close:SetScript("OnClick", function() d:Hide() end)
    if EUI.PadCP() then d.CloseButton = close end

    local minus = MakeButton(d, 22, 22, "-")
    minus:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -30)
    minus:SetScript("OnClick", function() Nudge(-1) end)

    local eb = CreateFrame("EditBox", nil, d)
    eb:SetSize(64, 22)
    eb:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(6)
    eb:SetFont(Theme.fontPath, 12, "")
    eb:SetTextColor(1, 1, 1, 1)
    eb:SetJustifyH("CENTER")
    eb:SetTextInsets(4, 4, 0, 0)
    WSkin.EditBox(eb)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        if self:GetNumber() > d._max then SetValue(d._max) else ShowCost(Current()) end
    end)
    eb:SetScript("OnEditFocusLost", function()
        if d:IsShown() then SetValue(Current()) end
    end)
    eb:SetScript("OnEnterPressed", DoBuy)
    eb:SetScript("OnEscapePressed", function() d:Hide() end)
    EUI.PadHint(eb, "hidekeyboard")
    d._eb = eb

    local plus = MakeButton(d, 22, 22, "+")
    plus:SetPoint("LEFT", eb, "RIGHT", 4, 0)
    plus:SetScript("OnClick", function() Nudge(1) end)

    local maxLbl = d:CreateFontString(nil, "OVERLAY")
    Font(maxLbl, 12)
    maxLbl:SetPoint("LEFT", plus, "RIGHT", 8, 0)
    maxLbl:SetTextColor(0.7, 0.7, 0.7, 1)
    d._maxLbl = maxLbl

    local cost = d:CreateFontString(nil, "OVERLAY")
    Font(cost, 12)
    cost:SetPoint("TOPLEFT", minus, "BOTTOMLEFT", 0, -9)
    cost:SetPoint("RIGHT", d, "RIGHT", -10, 0)
    cost:SetJustifyH("LEFT")
    cost:SetWordWrap(false)
    cost:SetTextColor(1, 1, 1, 0.9)
    d._cost = cost

    local stackBtn = EUI.MakePopupButton(d, "BOTTOMLEFT", d, "BOTTOMLEFT", 10, 10,
        1, 1, 1, 0.7, 1, 1, 1, 0.9, 1, 1, 1, 0.5, 1, 1, 1, 0.6)
    stackBtn:SetSize(66, 27)
    stackBtn._lbl:SetText(EllesmereUI.L("+1 Stack"))
    stackBtn:SetScript("OnClick", AddStack)
    d._stackBtn = stackBtn

    local maxBtn = EUI.MakePopupButton(d, "BOTTOM", d, "BOTTOM", 0, 10,
        1, 1, 1, 0.7, 1, 1, 1, 0.9, 1, 1, 1, 0.5, 1, 1, 1, 0.6)
    maxBtn:SetSize(66, 27)
    maxBtn._lbl:SetText(EllesmereUI.L("Max"))
    maxBtn:SetScript("OnClick", function() SetValue(d._max) end)
    d._maxBtn = maxBtn

    local buy = EUI.MakePopupButton(d, "BOTTOMRIGHT", d, "BOTTOMRIGHT", -10, 10,
        1, 1, 1, 0.9, 1, 1, 1, 1, 1, 1, 1, 0.9, 1, 1, 1, 1)
    buy:SetSize(66, 27)
    buy._lbl:SetText(EllesmereUI.L("Buy"))
    buy:SetScript("OnClick", DoBuy)
    d._buy = buy

    d:SetScript("OnMouseWheel", function(_, delta) Nudge(delta > 0 and 1 or -1) end)
    d:SetScript("OnShow", SyncEvents)
    d:SetScript("OnHide", function()
        eb:ClearFocus()
        SyncEvents()
    end)
    EllesmereUI.RegisterEscapeClose(d)
    return d
end

local function Validate()
    if dialog and dialog:IsShown() then Refresh() end
end

local function TakeOver(button)
    if not Enabled() then return end
    local ssf = StackSplitFrame
    if not ssf or not ssf:IsShown() or ssf.owner ~= button then return end
    local index = button:GetID()
    local itemID = index and GetMerchantItemID(index)
    local info = itemID and C_MerchantFrame.GetItemInfo(index)
    if not info or info.currencyID then return end
    ssf:Hide()
    dialog = dialog or CreateDialog()
    local step = max(info.stackCount, 1)
    dialog._owner, dialog._index, dialog._itemID = button, index, itemID
    dialog._chunk = max(floor((GetMerchantItemMaxStack(index) or step) / step) * step, step)
    dialog._stackSize = max(C_Item.GetItemMaxStackSizeByID(itemID) or step, 1)
    dialog._eb:SetText(tostring(step))
    local EG = EUI.ELLESMERE_GREEN
    dialog._buy._setColors(EG.r, EG.g, EG.b, 0.9, EG.r, EG.g, EG.b, 1, EG.r, EG.g, EG.b, 0.9, EG.r, EG.g, EG.b, 1)
    dialog._buy._resetAnim()
    dialog._maxBtn._resetAnim()
    dialog._stackBtn._resetAnim()
    dialog:ClearAllPoints()
    dialog:SetPoint("BOTTOMLEFT", button, "TOPLEFT", -4, 6)
    dialog:Show()
    Refresh()
    if not dialog:IsShown() then return end
    if EUI.PadCursorShown() then
        EUI.PadFocus(dialog._buy)
    else
        dialog._eb:SetFocus()
        dialog._eb:HighlightText()
    end
end

local function Install()
    if hooked then return end
    hooked = true
    if type(MerchantItemButton_OnModifiedClick) == "function" then
        hooksecurefunc("MerchantItemButton_OnModifiedClick", TakeOver)
    end
    if type(MerchantItemButton_BuyMultipleStacks) == "function" then
        hooksecurefunc("MerchantItemButton_BuyMultipleStacks", TakeOver)
    end
    if type(MerchantFrame_Update) == "function" then
        hooksecurefunc("MerchantFrame_Update", Validate)
    end
end

EllesmereUI._Merchant_RefreshBulkBuy = function()
    if Enabled() then
        Install()
        return
    end
    if dialog then dialog:Hide() end
    StopJob()
end

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        if Enabled() then Install() end
    elseif event == "BAG_UPDATE_DELAYED" then
        StepJob()
    elseif event == "MERCHANT_CLOSED" then
        if dialog then dialog:Hide() end
        StopJob()
    else
        StopJob()
    end
end)
events:RegisterEvent("ADDON_LOADED")
