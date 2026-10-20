-- Looks met in the game that AtlasLoot Forever and the world list do not have: items in your
-- bags or on you, in a loot window, sold by a vendor you talk to, offered as a quest reward.
-- Each is kept in DenoWardrobeDB.found with where it was met and shows in the collection from
-- then on. Quietly: no chat line (the count at the top of the window shows it).

local ADDON, ns = ...

local function Met(itemID, source)
    if not ns.db or not itemID then return end
    if ns.AddFound(itemID, source) and ns.OnFound then ns.OnFound() end
end

local function IDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function Bags()
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            Met(C_Container.GetContainerItemID(bag, slot), "In your bags")
        end
    end
    for slot = 1, 19 do Met(GetInventoryItemID("player", slot), "Worn by you") end
end

local function Loot()
    for i = 1, GetNumLootItems() or 0 do
        local link = GetLootSlotLink(i)
        if link and not issecretvalue(link) then Met(IDFromLink(link), "Looted") end
    end
end

local function Vendor()
    local who = UnitName("npc")
    who = (who and not issecretvalue(who)) and who or "a vendor"
    for i = 1, GetMerchantNumItems() or 0 do
        Met(GetMerchantItemID(i), "Vendor: " .. who)
    end
end

local function QuestRewards()
    local title = GetTitleText() or "a quest"
    for i = 1, GetNumQuestChoices() or 0 do Met(IDFromLink(GetQuestItemLink("choice", i)), "Quest: " .. title) end
    for i = 1, GetNumQuestRewards() or 0 do Met(IDFromLink(GetQuestItemLink("reward", i)), "Quest: " .. title) end
end

local pendingBags
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "LOOT_READY",
    "MERCHANT_SHOW", "QUEST_DETAIL", "QUEST_COMPLETE" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
    if InCombatLockdown() and event ~= "LOOT_READY" then return end
    if event == "LOOT_READY" then
        Loot()
    elseif event == "MERCHANT_SHOW" then
        Vendor()
    elseif event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
        QuestRewards()
    elseif not pendingBags then
        -- bags change in bursts: one look a second later
        pendingBags = true
        C_Timer.After(1, function() pendingBags = false Bags() end)
    end
end)
