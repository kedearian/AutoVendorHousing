-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2026 Zea

-- Local references keep hot-loop lookups cheap and make the API surface explicit.
local C_Container = C_Container
local C_Item = C_Item
local C_Timer = C_Timer
local type = type
local select = select
local tostring = tostring
local print = print
local wipe = wipe
local CursorHasItem = CursorHasItem
local ClearCursor = ClearCursor
local DeleteCursorItem = DeleteCursorItem
local InCombatLockdown = InCombatLockdown
-- The global GetCoinTextureString was deprecated in 10.2.6 and is removed in 12.1.5.
local GetCoinTextureString = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString

local PREFIX = "|cFFFF0000[AutoVendor]|r "

-- Backpack (0), the four equipped bags (1-4) and the reagent bag (5).
local MAX_BAG_INDEX = NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5

-- Housing items have their own item class since 12.0 (Enum.ItemClass.Housing == 20).
-- Every housing subclass is included: Decor, Dye, Room, RoomCustomization,
-- ExteriorCustomization and ServiceItem.
local HOUSING_CLASS_ID = (Enum and Enum.ItemClass and Enum.ItemClass.Housing) or 20

-- Selling many items in the same frame makes the server drop some of the requests,
-- so sales are spaced out. 0.2s per item is the commonly used safe interval.
local SELL_INTERVAL = 0.2
-- How long to wait for the server to confirm sales before printing the summary.
local SELL_CONFIRM_TIMEOUT = 5

local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")

local merchantOpen = false
-- Set when a merchant opens in combat; processing is retried when combat ends.
local pendingMerchantProcess = false

-- Items queued for sale at the current merchant, sold one per tick in bag order.
local sellQueue = {}
local sellQueueIndex = 0
-- Items whose sale was requested but not yet confirmed by the server.
local pendingSells = {}
local sellTicker
local confirmTimer
local sellBatch = 0
local soldCount = 0
local soldCopper = 0
local vendorRefused = false

local destroyButton

local function Print(msg)
    print(PREFIX .. msg)
end

local function ItemText(info)
    return info.hyperlink or ("item:" .. tostring(info.itemID))
end

local function FormatCopper(copper)
    if GetCoinTextureString then
        return GetCoinTextureString(copper)
    end
    return tostring(copper) .. "c"
end

local function IsHousingItem(itemID)
    -- Class data is available instantly, even for items that are not cached yet.
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    return classID == HOUSING_CLASS_ID
end

local function GetSellPrice(itemID)
    -- Can be nil if the item is not cached yet; only affects the printed total.
    local sellPrice = select(11, C_Item.GetItemInfo(itemID))
    if type(sellPrice) == "number" then
        return sellPrice
    end
    return 0
end

local function IsRefundable(bag, slot)
    -- Selling an item that is still refundable triggers a confirmation popup;
    -- those items are left alone until the refund window has expired.
    local info = C_Container.GetContainerItemPurchaseInfo(bag, slot, false)
    return info ~= nil and (info.refundSeconds or 0) > 0
end

-- Iterator over unlocked housing items in the equipped bags:
--   for bag, slot, info in HousingItems() do ... end
local function HousingItems()
    local bag = 0
    local slot = 0
    local numSlots = C_Container.GetContainerNumSlots(0) or 0
    return function()
        while bag <= MAX_BAG_INDEX do
            slot = slot + 1
            if slot > numSlots then
                bag = bag + 1
                slot = 0
                numSlots = (bag <= MAX_BAG_INDEX and C_Container.GetContainerNumSlots(bag)) or 0
            else
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID and not info.isLocked and IsHousingItem(info.itemID) then
                    return bag, slot, info
                end
            end
        end
        return nil
    end
end

-------------------------------------------------------------------------------
-- Destroying unsellable housing items
--
-- DeleteCursorItem only works inside a hardware event (a real click or key
-- press) and destroys at most one item per event, so unsellable items cannot be
-- removed automatically. Instead a button is attached to the merchant window and
-- each click destroys one item.
-------------------------------------------------------------------------------

local function FindNextUnsellableHousingItem()
    for bag, slot, info in HousingItems() do
        if info.hasNoValue then
            return bag, slot, info
        end
    end
    return nil
end

local function CountUnsellableHousingItems()
    local count = 0
    for _, _, info in HousingItems() do
        if info.hasNoValue then
            count = count + 1
        end
    end
    return count
end

local function UpdateDestroyButton()
    if not destroyButton then
        return
    end
    local count = 0
    if merchantOpen then
        count = CountUnsellableHousingItems()
    end
    if count > 0 then
        destroyButton:SetText(("Destroy Housing (%d)"):format(count))
        destroyButton:Show()
    else
        destroyButton:Hide()
    end
end

local function DestroyNextUnsellableHousingItem()
    local bag, slot, info = FindNextUnsellableHousingItem()
    if not bag then
        Print("No unsellable housing items to destroy.")
        UpdateDestroyButton()
        return
    end

    local itemText = ItemText(info)
    -- Keep cursor state clean so we do not drop or overwrite another item.
    if CursorHasItem() then
        ClearCursor()
    end
    C_Container.PickupContainerItem(bag, slot)
    if not CursorHasItem() then
        Print("Could not pick up housing item: " .. itemText)
        return
    end

    DeleteCursorItem()
    if CursorHasItem() then
        -- The client refused the deletion; put the item back where it was.
        ClearCursor()
        Print("Could not destroy housing item: " .. itemText)
    else
        Print("Destroyed unsellable housing item: " .. itemText)
    end
    UpdateDestroyButton()
end

local function DestroyButton_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Destroy unsellable housing items")
    GameTooltip:AddLine("The game only allows one item deletion per click, so click once per item.", 1, 1, 1, true)
    local _, _, info = FindNextUnsellableHousingItem()
    if info then
        GameTooltip:AddLine("Next: " .. ItemText(info), 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function DestroyButton_OnLeave()
    GameTooltip:Hide()
end

local function CreateDestroyButton()
    if destroyButton or not MerchantFrame then
        return
    end
    destroyButton = CreateFrame("Button", "AutoVendorHousingDestroyButton", MerchantFrame, "UIPanelButtonTemplate")
    destroyButton:SetSize(170, 22)
    destroyButton:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 4, -4)
    destroyButton:SetScript("OnClick", DestroyNextUnsellableHousingItem)
    destroyButton:SetScript("OnEnter", DestroyButton_OnEnter)
    destroyButton:SetScript("OnLeave", DestroyButton_OnLeave)
    destroyButton:Hide()
end

-------------------------------------------------------------------------------
-- Selling housing items
-------------------------------------------------------------------------------

local function StopSellTicker()
    if sellTicker then
        sellTicker:Cancel()
        sellTicker = nil
    end
    wipe(sellQueue)
    sellQueueIndex = 0
end

local function StopConfirmTimer()
    if confirmTimer then
        confirmTimer:Cancel()
        confirmTimer = nil
    end
end

-- Prints the summary for the current batch and resets state. Runs once every
-- requested sale is confirmed, the confirmation window expires, or the vendor
-- refuses to buy.
local function FinishSelling()
    StopSellTicker()
    StopConfirmTimer()
    sellBatch = sellBatch + 1

    local unsold = #pendingSells
    wipe(pendingSells)

    if soldCount > 0 then
        Print(("Sold %d housing items for %s"):format(soldCount, FormatCopper(soldCopper)))
    end
    if vendorRefused then
        Print("This vendor does not buy items. Housing items were not sold.")
    elseif unsold > 0 then
        Print(("%d housing items were not sold."):format(unsold))
    end

    soldCount = 0
    soldCopper = 0
    vendorRefused = false
    frame:UnregisterEvent("UI_ERROR_MESSAGE")
    if not merchantOpen then
        frame:UnregisterEvent("BAG_UPDATE_DELAYED")
    end
end

local function StartConfirmTimer()
    if confirmTimer then
        return
    end
    local batch = sellBatch
    confirmTimer = C_Timer.NewTimer(SELL_CONFIRM_TIMEOUT, function()
        confirmTimer = nil
        if batch == sellBatch then
            FinishSelling()
        end
    end)
end

-- The server removes sold items from the bag; anything still in its slot is
-- either pending or was not bought.
local function ConfirmPendingSells()
    local total = #pendingSells
    local kept = 0
    for i = 1, total do
        local item = pendingSells[i]
        pendingSells[i] = nil
        local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
        if info and info.itemID == item.itemID then
            kept = kept + 1
            pendingSells[kept] = item
        else
            soldCount = soldCount + item.count
            soldCopper = soldCopper + item.copper
        end
    end
    if kept == 0 and not sellTicker then
        FinishSelling()
    end
end

local function SellNextItem()
    sellQueueIndex = sellQueueIndex + 1
    local item = sellQueue[sellQueueIndex]
    if not item then
        StopSellTicker()
        if #pendingSells == 0 then
            FinishSelling()
        else
            StartConfirmTimer()
        end
        return
    end

    -- Re-check the slot: bag contents can change between ticks.
    local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
    if info and info.itemID == item.itemID and not info.isLocked then
        C_Container.UseContainerItem(item.bag, item.slot)
        pendingSells[#pendingSells + 1] = item
    end
end

local function QueueHousingSales()
    local refundable = 0
    for bag, slot, info in HousingItems() do
        if not info.hasNoValue then
            if IsRefundable(bag, slot) then
                refundable = refundable + 1
            else
                local count = info.stackCount or 1
                sellQueue[#sellQueue + 1] = {
                    bag = bag,
                    slot = slot,
                    itemID = info.itemID,
                    count = count,
                    copper = GetSellPrice(info.itemID) * count,
                }
            end
        end
    end
    return refundable
end

local function ProcessMerchantItems()
    -- Don't do bag work in combat; retry on the first safe frame after combat.
    if InCombatLockdown and InCombatLockdown() then
        pendingMerchantProcess = true
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        Print("In combat. Deferring auto-sell until combat ends.")
        return
    end
    pendingMerchantProcess = false
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")

    -- Wrap up a previous vendor's batch that is still waiting on confirmations.
    if sellTicker or #pendingSells > 0 then
        FinishSelling()
    end

    local refundable = QueueHousingSales()
    if refundable > 0 then
        Print(("Skipped %d refundable housing item(s); they can be sold once the refund window ends."):format(refundable))
    end

    if #sellQueue > 0 then
        frame:RegisterEvent("UI_ERROR_MESSAGE")
        sellTicker = C_Timer.NewTicker(SELL_INTERVAL, SellNextItem)
    end

    UpdateDestroyButton()
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "MERCHANT_SHOW" then
        merchantOpen = true
        -- Bag updates confirm sales and keep the destroy button count current.
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        CreateDestroyButton()
        ProcessMerchantItems()
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        pendingMerchantProcess = false
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        StopSellTicker()
        if #pendingSells > 0 then
            StartConfirmTimer()
        elseif soldCount > 0 or vendorRefused then
            FinishSelling()
        else
            self:UnregisterEvent("BAG_UPDATE_DELAYED")
        end
        if destroyButton then
            destroyButton:Hide()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Retry only if we still have deferred work and the merchant is still open.
        if pendingMerchantProcess and merchantOpen then
            ProcessMerchantItems()
        else
            pendingMerchantProcess = false
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if #pendingSells > 0 then
            ConfirmPendingSells()
        end
        if merchantOpen then
            UpdateDestroyButton()
        end
    elseif event == "UI_ERROR_MESSAGE" then
        -- arg1 is the error type, arg2 the localized message.
        if arg2 ~= nil and arg2 == ERR_VENDOR_DOESNT_BUY and (sellTicker or #pendingSells > 0) then
            vendorRefused = true
            FinishSelling()
        end
    end
end)
