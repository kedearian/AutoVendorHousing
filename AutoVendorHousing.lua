local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")

-- Local references are a tiny perf win in hot loops and keep globals out of lookups.
local C_Container = C_Container
local C_Item = C_Item
local Enum = Enum
local _G = _G
local type = type
local select = select
local tostring = tostring
local print = print
local CursorHasItem = CursorHasItem
local ClearCursor = ClearCursor
local DeleteCursorItem = DeleteCursorItem
local InCombatLockdown = InCombatLockdown
local GetCoinTextureString = GetCoinTextureString

local MAX_BAG_INDEX = NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4
local ITEM_CLASS = Enum and Enum.ItemClass
local MISC_CLASS_ID = (ITEM_CLASS and ITEM_CLASS.Miscellaneous) or 15
local HOUSING_CLASS_ID = ITEM_CLASS and ITEM_CLASS.Housing
local DELETE_CONFIRM_TEXT = _G.DELETE or "DELETE"

-- Set when we hit a merchant in combat and need to retry on combat end.
local pendingMerchantProcess = false

-- Reused per merchant interaction to avoid creating throwaway tables every run.
local itemMetaCache = {}

-- StaticPopup can use a few delete variants; these are the ones we can auto-confirm safely.
local DELETE_POPUP_TYPES = {
    DELETE_ITEM = true,
    DELETE_GOOD_ITEM = true,
    DELETE_GOOD_QUEST_ITEM = true,
}

local function MerchantCanBuyItems()
    local sellTab = _G.MerchantFrameTab2
    return sellTab and sellTab:IsEnabled() and sellTab:IsShown()
end

local function IsItemSellabilityKnown(itemInfo, sellPrice)
    -- `hasNoValue` is authoritative when present.
    if itemInfo and itemInfo.hasNoValue ~= nil then
        return true
    end

    -- Fallback for items where only classic item info is available.
    return type(sellPrice) == "number"
end

local function GetCachedItemMeta(itemID, cache)
    local meta = cache[itemID]
    if meta then
        return meta
    end

    -- Class data is available instantly; price can still be nil if not cached yet.
    local _, _, _, _, _, itemClassID, itemSubClassID = C_Item.GetItemInfoInstant(itemID)
    local sellPrice = select(11, C_Item.GetItemInfo(itemID))
    meta = {
        itemClassID = itemClassID,
        itemSubClassID = itemSubClassID,
        sellPrice = sellPrice,
    }
    cache[itemID] = meta
    return meta
end

local function ClearTable(t)
    -- Faster than replacing the table: keeps one allocation and clears keys in-place.
    for k in pairs(t) do
        t[k] = nil
    end
end

local function ConfirmDeletePopups()
    -- WoW can show up to 4 static popups at once.
    for i = 1, 4 do
        local popup = _G["StaticPopup" .. i]
        if popup and popup:IsShown() then
            local which = popup.which
            if DELETE_POPUP_TYPES[which] then
                local editBox = _G[popup:GetName() .. "EditBox"]
                if editBox and editBox:IsShown() and editBox:IsEnabled() then
                    -- Use localized delete text so this works outside enUS clients.
                    editBox:SetText(DELETE_CONFIRM_TEXT)
                end

                local confirmButton = _G[popup:GetName() .. "Button1"]
                if confirmButton and confirmButton:IsEnabled() then
                    confirmButton:Click()
                end
            end
        end
    end
end

local function DestroyBagItem(bag, slot)
    -- Keep cursor state clean so we do not accidentally drop or overwrite another item.
    if CursorHasItem() then
        ClearCursor()
    end

    C_Container.PickupContainerItem(bag, slot)
    if not CursorHasItem() then
        return false
    end

    DeleteCursorItem()
    ConfirmDeletePopups()

    local stillThere = C_Container.GetContainerItemInfo(bag, slot) ~= nil
    if CursorHasItem() then
        ClearCursor()
    end

    return not stillThere
end

local function ProcessMerchantItems()
    -- Don't do bag work in combat; queue it for the first safe frame after combat.
    if InCombatLockdown and InCombatLockdown() then
        pendingMerchantProcess = true
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        print("|cFFFF0000[AutoVendor]|r In combat. Deferring auto-sell/auto-destroy until combat ends.")
        return
    end

    pendingMerchantProcess = false
    -- We only listen for regen while there is deferred work pending.
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")

    if not MerchantCanBuyItems() then
        print("|cFFFF0000[AutoVendor]|r This vendor does not buy items. Skipping auto-sell/auto-destroy.")
        return
    end

    local soldItemCount = 0
    local soldCopper = 0

    -- Fresh per-run cache contents, same table instance.
    ClearTable(itemMetaCache)

    -- Loop through all equipped bags, including reagent bag when available.
    for bag = 0, MAX_BAG_INDEX do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
                if itemInfo and itemInfo.itemID and not itemInfo.isLocked then

                    -- Cache per-item metadata within this merchant interaction to reduce repeated API calls.
                    local itemMeta = GetCachedItemMeta(itemInfo.itemID, itemMetaCache)
                    local sellPrice = itemMeta.sellPrice
                    local itemClassID = itemMeta.itemClassID
                    local itemSubClassID = itemMeta.itemSubClassID

                    local isLegacyHousing = itemClassID == MISC_CLASS_ID and itemSubClassID == 6
                    local isHousingClass = HOUSING_CLASS_ID and itemClassID == HOUSING_CLASS_ID

                    if isLegacyHousing or isHousingClass then
                        local hasNoValue = itemInfo.hasNoValue
                        local hasPrice = type(sellPrice) == "number"

                        -- Sell when we know it has value.
                        local isSellable = (hasNoValue == false) or (hasPrice and sellPrice > 0)

                        -- Destroy only when we know it has no value; unknown values are never destroyed.
                        local isExplicitlyUnsellable = (hasNoValue == true) or (hasPrice and sellPrice == 0)

                        if isSellable then
                            local stackCount = itemInfo.stackCount or 1
                            soldItemCount = soldItemCount + stackCount
                            soldCopper = soldCopper + ((sellPrice or 0) * stackCount)
                            C_Container.UseContainerItem(bag, slot)
                        elseif isExplicitlyUnsellable then
                            local itemText = itemInfo.hyperlink or ("item:" .. itemInfo.itemID)
                            local destroyed = DestroyBagItem(bag, slot)
                            if destroyed then
                                print("|cFFFF0000[AutoVendor]|r Destroyed unsellable housing item: " .. itemText)
                            else
                                print("|cFFFF0000[AutoVendor]|r Could not destroy housing item: " .. itemText)
                            end
                        elseif not IsItemSellabilityKnown(itemInfo, sellPrice) then
                            -- Item data not fully cached yet; safer to skip this pass.
                            local itemText = itemInfo.hyperlink or ("item:" .. itemInfo.itemID)
                            print("|cFFFF0000[AutoVendor]|r Skipped housing item with unknown sell value (item data not cached yet): " .. itemText)
                        end
                    end

                end
            end
        end
    -- End of bag loops
    end

    if soldItemCount > 0 then
        local valueText = GetCoinTextureString and GetCoinTextureString(soldCopper) or tostring(soldCopper)
        print("|cFFFF0000[AutoVendor]|r Sold " .. soldItemCount .. " housing items for " .. valueText)
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        ProcessMerchantItems()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Retry only if we still have deferred work and merchant is still open.
        if pendingMerchantProcess and MerchantFrame and MerchantFrame:IsShown() then
            ProcessMerchantItems()
        else
            pendingMerchantProcess = false
            frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    end
end)
