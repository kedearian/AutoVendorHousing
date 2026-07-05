local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")

local MAX_BAG_INDEX = NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4
local MISC_CLASS_ID = (Enum and Enum.ItemClass and Enum.ItemClass.Miscellaneous) or 15
local HOUSING_CLASS_ID = Enum and Enum.ItemClass and Enum.ItemClass.Housing

local function DestroyBagItem(bag, slot)
    C_Container.PickupContainerItem(bag, slot)
    DeleteCursorItem()
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        local soldItemCount = 0
        local soldCopper = 0

        -- Loop through all equipped bags, including reagent bag when available.
        for bag = 0, MAX_BAG_INDEX do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            if numSlots and numSlots > 0 then
                for slot = 1, numSlots do
                    local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
                    if itemInfo and itemInfo.itemID and not itemInfo.isLocked then

                        -- Instant info returns class/subclass reliably without waiting for item cache.
                        local _, _, _, _, _, itemClassID, itemSubClassID = C_Item.GetItemInfoInstant(itemInfo.itemID)
                        local sellPrice = select(11, C_Item.GetItemInfo(itemInfo.itemID))

                        local isLegacyHousing = itemClassID == MISC_CLASS_ID and itemSubClassID == 6
                        local isHousingClass = HOUSING_CLASS_ID and itemClassID == HOUSING_CLASS_ID

                        if isLegacyHousing or isHousingClass then
                            local itemText = itemInfo.hyperlink or ("item:" .. itemInfo.itemID)
                            local isSellable = (itemInfo.hasNoValue ~= nil and not itemInfo.hasNoValue) or (sellPrice and sellPrice > 0)

                            if isSellable then
                                local stackCount = itemInfo.stackCount or 1
                                soldItemCount = soldItemCount + stackCount
                                soldCopper = soldCopper + ((sellPrice or 0) * stackCount)
                                C_Container.UseContainerItem(bag, slot)
                            else
                                DestroyBagItem(bag, slot)
                                print("|cFFFF0000[AutoVendor]|r Destroyed unsellable housing item: " .. itemText)
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
end)
