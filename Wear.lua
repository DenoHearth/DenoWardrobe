-- Wearing an outfit for real, two ways:
--   Equip     puts on the outfit's items you have in your bags (out of combat). The game asks
--             itself before an item binds.
--   Transmog  at a transmogrifier with its window open: every collected look of the outfit is
--             set on the game's own transmog window; you check it there and press its Apply
--             (that is where the gold is paid). Weapons are left out: the game's weapon options
--             (one hand, two hand) are not set from here.

local ADDON, ns = ...

local function Name(itemID)
    return (C_Item.GetItemInfo(itemID)) or ("item " .. itemID)
end

function ns.EquipOutfit(outfit)
    if InCombatLockdown() then ns.Print("not in a fight.") return end
    local put, worn, lacking, tooHigh = 0, 0, {}, {}
    local level = UnitLevel("player")
    for key, itemID in pairs(outfit.items) do
        local needs = select(5, C_Item.GetItemInfo(itemID))
        if C_Item.IsEquippedItem(itemID) then
            worn = worn + 1
        elseif (C_Item.GetItemCount(itemID) or 0) > 0 and needs and needs > level then
            tooHigh[#tooHigh + 1] = Name(itemID) .. " (" .. needs .. ")"
        elseif (C_Item.GetItemCount(itemID) or 0) > 0 then
            local slot = ns.SLOT_BY_KEY[key]
            local invSlot = slot and GetInventorySlotInfo(slot.inv)
            if key == "OFF" and invSlot then
                C_Item.EquipItemByName(itemID, invSlot)
            else
                C_Item.EquipItemByName(itemID)
            end
            put = put + 1
        else
            lacking[#lacking + 1] = Name(itemID)
        end
    end
    local text = string.format("%s: put on %d, already wearing %d.", outfit.name, put, worn)
    if #tooHigh > 0 then text = text .. " Needs a higher level: " .. table.concat(tooHigh, ", ") .. "." end
    if #lacking > 0 then text = text .. " Not in your bags: " .. table.concat(lacking, ", ") .. "." end
    ns.Print(text)
end

function ns.AtTransmogrifier()
    return C_Transmog.IsAtTransmogNPC() and true or false
end

function ns.TransmogOutfit(outfit)
    if not ns.AtTransmogrifier() then
        ns.Print("talk to a transmogrifier first, so its window is open.")
        return
    end
    local set, notCollected, weapons, bare, blocked = 0, {}, 0, {}, {}
    for key, itemID in pairs(outfit.items) do
        local slot = ns.SLOT_BY_KEY[key]
        if key == "MAIN" or key == "OFF" then
            weapons = weapons + 1
        elseif slot and not GetInventoryItemID("player", (GetInventorySlotInfo(slot.inv))) then
            -- the game only takes a look on a slot where something is worn
            bare[#bare + 1] = slot.name
        elseif slot then
            local _, sourceID = ns.LookOf(itemID)
            -- the game's own reason a collected look cannot be used yet (a level, a class)
            local info = sourceID and C_TransmogCollection.GetSourceInfo(sourceID)
            local useError = info and info.useError
            if useError and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID) then
                blocked[#blocked + 1] = Name(itemID) .. " (" .. useError .. ")"
            elseif sourceID and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID) then
                -- the transmog slot comes from the look's own inventory type (a robe and a chest
                -- piece are told apart there), measured in client 70374; the option is the one the
                -- worn item in that slot has
                local transmogSlot = info and info.invType and C_TransmogOutfitInfo.GetTransmogOutfitSlotForInventoryType(info.invType)
                if transmogSlot then
                    local option = C_TransmogOutfitInfo.GetEquippedSlotOptionFromTransmogSlot(transmogSlot) or Enum.TransmogOutfitSlotOption.None
                    C_TransmogOutfitInfo.SetPendingTransmog(transmogSlot, Enum.TransmogType.Appearance,
                        option, sourceID, Enum.TransmogOutfitDisplayType.Assigned)
                    set = set + 1
                end
            else
                notCollected[#notCollected + 1] = Name(itemID)
            end
        end
    end
    local text = string.format("%s: %d looks set on the transmogrifier, press its Apply.", outfit.name, set)
    if #notCollected > 0 then text = text .. " Not collected yet: " .. table.concat(notCollected, ", ") .. "." end
    if #blocked > 0 then text = text .. " Not usable yet: " .. table.concat(blocked, ", ") .. "." end
    if #bare > 0 then text = text .. " Nothing worn on: " .. table.concat(bare, ", ") .. " (put something on there first)." end
    if weapons > 0 then text = text .. " Weapons: choose them in the game's window." end
    ns.Print(text)
end
