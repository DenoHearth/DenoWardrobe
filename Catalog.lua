-- The list of looks.
--
-- 1. Every wearable item in AtlasLoot Forever's loot tables, read live from that addon when the
--    wardrobe opens. Nothing of theirs is copied into this addon, so when they add or fix a loot
--    table, the wardrobe has it at the next login.
--    AtlasLoot Forever (GPL v2) keeps its tables in AtlasLoot.ItemDB.Storage[module][content]:
--    content.name, content.items[boss] = { name = "...", [difficulty] = { { slot, itemID }, ... } }.
--    Its loot modules load on demand; they are loaded here, out of combat.
-- 2. What AtlasLoot does not list (world drops, vendors, quest rewards, chests): ServerLooks.lua,
--    made by tools/serverlooks.py from the local test server's world database.

local ADDON, ns = ...

local MODULES = {
    "AtlasLootClassic_DungeonsAndRaids",
    "AtlasLootClassic_Crafting",
    "AtlasLootClassic_PvP",
    "AtlasLootClassic_Factions",
}

-- Where an item shows on a character. Equip locations that change no look are left out.
ns.SLOTS = {
    { key = "HEAD",     name = "Head",      inv = "HeadSlot",          locs = { INVTYPE_HEAD = true } },
    { key = "SHOULDER", name = "Shoulders", inv = "ShoulderSlot",      locs = { INVTYPE_SHOULDER = true } },
    { key = "BACK",     name = "Back",      inv = "BackSlot",          locs = { INVTYPE_CLOAK = true } },
    { key = "CHEST",    name = "Chest",     inv = "ChestSlot",         locs = { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
    { key = "WRIST",    name = "Wrists",    inv = "WristSlot",         locs = { INVTYPE_WRIST = true } },
    { key = "HANDS",    name = "Hands",     inv = "HandsSlot",         locs = { INVTYPE_HAND = true } },
    { key = "WAIST",    name = "Waist",     inv = "WaistSlot",         locs = { INVTYPE_WAIST = true } },
    { key = "LEGS",     name = "Legs",      inv = "LegsSlot",          locs = { INVTYPE_LEGS = true } },
    { key = "FEET",     name = "Feet",      inv = "FeetSlot",          locs = { INVTYPE_FEET = true } },
    { key = "MAIN",     name = "Main Hand", inv = "MainHandSlot",      locs = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true } },
    { key = "OFF",      name = "Off Hand",  inv = "SecondaryHandSlot", locs = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true } },
}
ns.SLOT_BY_KEY = {}
local SLOT_OF = {}
for _, slot in ipairs(ns.SLOTS) do
    ns.SLOT_BY_KEY[slot.key] = slot
    for loc in pairs(slot.locs) do SLOT_OF[loc] = slot.key end
end

local ARMOR = 4         -- item class: armour; its subclasses 1-4 are cloth, leather, mail, plate
local WEAPON = 2        -- item class: weapon; the subclass says which kind
ns.ARMOR_TYPES = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }

-- The weapon filter of the two hand slots (his words: "I am unable to filter for what I am
-- looking for, is it a 2h swords or shields"): weapon subclasses of the game's item tables,
-- plus shields (armour subclass 6) and held-in-off-hand items for the off hand.
ns.WEAPON_TYPES = {
    MAIN = {
        { 7, "1H Sword" }, { 8, "2H Sword" }, { 0, "1H Axe" }, { 1, "2H Axe" },
        { 4, "1H Mace" }, { 5, "2H Mace" }, { 15, "Dagger" }, { 13, "Fist" },
        { 6, "Polearm" }, { 10, "Staff" }, { 2, "Bow" }, { 3, "Gun" },
        { 18, "Crossbow" }, { 19, "Wand" }, { 16, "Thrown" },
    },
    OFF = {
        { "shield", "Shield" }, { "held", "Off-hand" }, { 7, "Sword" }, { 0, "Axe" },
        { 4, "Mace" }, { 15, "Dagger" }, { 13, "Fist" },
    },
}

local function WeaponType(loc, classID, subClassID)
    if classID == WEAPON then return subClassID end
    if loc == "INVTYPE_SHIELD" then return "shield" end
    if loc == "INVTYPE_HOLDABLE" then return "held" end
end

-- Visible text only: AtlasLoot puts small pictures and colour codes into some names.
local function Plain(text)
    text = tostring(text or "")
    text = text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return strtrim(text)
end

local catalog          -- [slotKey] = { { id = itemID, slot = key, source = "...", armor = 1..4 or nil }, ... }
ns.catalogSize, ns.countAtlas, ns.countServer, ns.countFound = 0, 0, 0, 0
local seenAll = {}

-- The look of an item: its appearance source and appearance. From Looks.lua (the game's own
-- tables, no server needed) first; the live answer covers items newer than that table.
-- C_TransmogCollection.GetItemInfo answers nothing for an item the client has not loaded yet,
-- which is why tiles stayed empty before the table.
function ns.LookOf(itemID)
    local known = ns.LOOKS and ns.LOOKS[itemID]
    if known then return known[2], known[1] end
    return C_TransmogCollection.GetItemInfo(itemID)  -- appearance, source
end

-- Name and quality, remembered across sessions: what the game has told us before is shown at
-- once after /reload or a new login instead of "item 1234" while the server answers again.
function ns.ItemInfo(itemID)
    local name, _, quality = C_Item.GetItemInfo(itemID)
    local db = ns.db
    if name then
        if quality and db.quality[itemID] ~= quality then db.quality[itemID] = quality end
        return name, quality
    end
    local known = ns.LOOKS and ns.LOOKS[itemID]
    name = (ns.NAMES and ns.NAMES[itemID]) or db.names[itemID]
    return name, db.quality[itemID] or (known and known[3])
end

-- Items nobody can have: the game's tables mark them (ns.JUNK from tools/looks.py); a name the
-- game gives later is checked the same way, as is a level above the cap.
local LEVEL_CAP = 60
local JUNK_NAMES = { "%[PH%]", "DEPRECATED", "^Deprecated ", "^Test ", "%f[%w]TEST%f[%W]", "^Monster %- ", "^QA " }
local junkKnown = {}         -- [itemID] = true / false once the game has told us the item
function ns.IsJunk(itemID)
    if ns.JUNK and ns.JUNK[itemID] then return true end
    local known = junkKnown[itemID]
    if known ~= nil then return known end
    local name, _, _, _, minLevel = C_Item.GetItemInfo(itemID)
    local loaded = name ~= nil
    local junk = (minLevel and minLevel > LEVEL_CAP) or false
    name = name or (ns.NAMES and ns.NAMES[itemID]) or (ns.db and ns.db.names[itemID])
    if name and not junk then
        for _, pattern in ipairs(JUNK_NAMES) do
            if name:find(pattern) then junk = true break end
        end
    end
    if loaded or junk then junkKnown[itemID] = junk end
    return junk
end

local function Add(seen, itemID, source)
    if type(itemID) ~= "number" or seen[itemID] then return false end
    if ns.IsJunk(itemID) then return false end
    local id, _, _, loc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not id then return false end                 -- not an item of this game
    -- an item of this build without any look: nothing to show on a model. An item the table
    -- does not know at all is newer than it (AtlasLoot or the game added it since): kept, and
    -- its look comes from the game (ns.LookOf)
    if ns.NOLOOK and ns.NOLOOK[itemID] then return false end
    local slot = SLOT_OF[loc]
    if not slot then return false end
    seen[itemID] = true
    local list = catalog[slot]
    list[#list + 1] = { id = itemID, slot = slot, source = source,
        armor = (classID == ARMOR and ns.ARMOR_TYPES[subClassID]) and subClassID or nil,
        weapon = WeaponType(loc, classID, subClassID) }
    ns.catalogSize = ns.catalogSize + 1
    return true
end

-- Other addons' item lists, read live when the wardrobe is first opened each session. Nothing
-- of theirs is copied into this addon: when their authors add items, the wardrobe has them at
-- the next login. Each reader is skipped when its addon is not installed, and a reader that
-- fails (its addon changed the shape of its data) only loses that one source.
-- To take in another addon: one more entry here, { name, label, read = function(add) }, where
-- add(itemID, source) offers one item (source is text, or a function that makes the text;
-- it is only called for an item that is new to the wardrobe).
-- Not read on purpose: Alex Atlas Loot (its licence forbids using its tables), ItemTree (its
-- public API answers one item at a time; it has no list).
ns.SOURCES = {
    {
        -- AtlasLoot Forever (GPL v2): AtlasLoot.ItemDB.Storage[module][content].items[boss][difficulty]
        name = "AtlasLoot", label = "AtlasLoot Forever",
        read = function(add)
            local AL = _G.AtlasLoot
            if not (AL and AL.ItemDB and AL.ItemDB.Storage) then return end
            for _, module in ipairs(MODULES) do
                if C_AddOns.DoesAddOnExist(module) and not C_AddOns.IsAddOnLoaded(module) then
                    C_AddOns.LoadAddOn(module)
                end
            end
            for _, module in ipairs(MODULES) do
                local data = AL.ItemDB.Storage[module]
                if type(data) == "table" then
                    for _, content in pairs(data) do
                        if type(content) == "table" and type(content.items) == "table" then
                            local place = Plain(content.name)
                            for _, boss in ipairs(content.items) do
                                if type(boss) == "table" then
                                    local source = boss.name and (Plain(boss.name) .. " - " .. place) or place
                                    for key, list in pairs(boss) do
                                        if type(key) == "number" and type(list) == "table" then
                                            for _, entry in ipairs(list) do
                                                if type(entry) == "table" then add(entry[2], source) end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end,
    },
    {
        -- Forever Dungeon Journal (by Exehn): Forever's own dungeons, bosses and quest rewards,
        -- many of them items new to Forever. ForeverDungeonJournal_NS.DB[dungeon].bosses[i].loot
        -- and .quests[i].rewardItems = { { itemID, name, ... } }.
        name = "ForeverDungeonJournal", label = "Dungeon Journal",
        read = function(add)
            local fdj = _G.ForeverDungeonJournal_NS
            if not (fdj and type(fdj.DB) == "table") then return end
            for dungeon, info in pairs(fdj.DB) do
                if type(info) == "table" then
                    for _, boss in ipairs(type(info.bosses) == "table" and info.bosses or {}) do
                        if type(boss) == "table" and type(boss.loot) == "table" then
                            local source = (boss.name and (boss.name .. " - ") or "") .. dungeon
                            for _, entry in ipairs(boss.loot) do
                                if type(entry) == "table" then add(entry[1], source) end
                            end
                        end
                    end
                    for _, quest in ipairs(type(info.quests) == "table" and info.quests or {}) do
                        if type(quest) == "table" and type(quest.rewardItems) == "table" then
                            local source = "Quest: " .. tostring(quest.name or "?") .. " (" .. dungeon .. ")"
                            for _, entry in ipairs(quest.rewardItems) do
                                if type(entry) == "table" then add(entry[1], source) end
                            end
                        end
                    end
                end
            end
            if type(fdj.SHARED_LOOT_IDS) == "table" then
                for itemID in pairs(fdj.SHARED_LOOT_IDS) do add(itemID, "Shared dungeon loot") end
            end
        end,
    },
    {
        -- Questie's database (QuestieDB, GPL): every item with where it drops, who sells it and
        -- which quest gives it. LibQuestieDB.Item.GetAllIds() and one getter per field.
        name = "QuestieDB", label = "Questie",
        read = function(add)
            local db = _G.LibQuestieDB
            local items = db and db.Item
            if not (items and items.GetAllIds) then return end
            local function first(list) return type(list) == "table" and list[1] or nil end
            local function npcName(npcID)
                local ok, name = pcall(db.Npc.name, npcID)
                return ok and name or nil
            end
            for _, itemID in ipairs(items.GetAllIds()) do
                add(itemID, function()
                    local npc = first(items.npcDrops(itemID))
                    if npc then return "Drop: " .. (npcName(npc) or ("creature " .. npc)) end
                    local vendor = first(items.vendors(itemID))
                    if vendor then return "Vendor: " .. (npcName(vendor) or ("vendor " .. vendor)) end
                    local quest = first(items.questRewards(itemID))
                    if quest then
                        local ok, title = pcall(db.Quest.name, quest)
                        return "Quest: " .. ((ok and title) or ("quest " .. quest))
                    end
                    if first(items.objectDrops(itemID)) then return "Chest or object" end
                    return "Questie"
                end)
            end
        end,
    },
}

-- Where a look comes from, as text. A reader may hand a function instead (Questie: making the
-- text reads several of its tables, too much for 20,000 items at once); it is made the first
-- time it is shown or searched, and kept.
function ns.SourceText(look)
    local source = look.source
    if type(source) == "function" then
        local ok, text = pcall(source)
        source = ok and text or nil
        look.source = source
    end
    return source
end

function ns.BuildCatalog()
    if catalog then return catalog end
    if InCombatLockdown() then
        local empty = {}
        for _, slot in ipairs(ns.SLOTS) do empty[slot.key] = {} end
        return empty
    end
    catalog = {}
    for _, slot in ipairs(ns.SLOTS) do catalog[slot.key] = {} end
    local seen, sources = seenAll, {}
    ns.sourceCounts = {}
    for _, source in ipairs(ns.SOURCES) do
        local count = 0
        local function add(itemID, text)
            if type(itemID) ~= "number" or seen[itemID] then return end
            if Add(seen, itemID, text) then count = count + 1 end
        end
        local ok, err = pcall(source.read, add)
        if not ok then ns.Print("could not read %s (%s); the other lists are fine.", source.label, tostring(err)) end
        ns.sourceCounts[source.name] = count
        if count > 0 then sources[#sources + 1] = source.label end
    end
    ns.countAtlas = ns.sourceCounts.AtlasLoot or 0
    if type(ns.SERVER_LOOKS) == "table" then
        for itemID, source in pairs(ns.SERVER_LOOKS) do
            if Add(seen, itemID, source) then ns.countServer = ns.countServer + 1 end
        end
        if ns.countServer > 0 then sources[#sources + 1] = "the world" end
    end
    -- looks met in the game that no list has (Found.lua keeps them); a find a list already has
    -- (met before the lists were read, or added to one since) is dropped
    for itemID, source in pairs(ns.db.found) do
        if seen[itemID] then
            ns.db.found[itemID] = nil
        elseif Add(seen, itemID, source) then
            ns.countFound = ns.countFound + 1
        end
    end
    if ns.countFound > 0 then sources[#sources + 1] = "your own finds" end
    ns.source = #sources > 0 and table.concat(sources, ", ") or nil
    return catalog
end

-- A look met in the game. Returns true when it joined the open wardrobe. Before the wardrobe
-- has been opened, AtlasLoot's lists are not read yet: the find is only kept, and BuildCatalog
-- drops it if a list has it after all.
function ns.AddFound(itemID, source)
    if type(itemID) ~= "number" or seenAll[itemID] or ns.db.found[itemID] then return false end
    if ns.SERVER_LOOKS and ns.SERVER_LOOKS[itemID] then return false end
    local _, _, _, loc = C_Item.GetItemInfoInstant(itemID)
    if not (loc and SLOT_OF[loc]) then return false end
    ns.db.found[itemID] = source
    if not (catalog and Add(seenAll, itemID, source)) then return false end
    ns.countFound = ns.countFound + 1
    if not (ns.source or ""):find("your own finds", 1, true) then
        ns.source = ns.source and (ns.source .. " and your own finds") or "your own finds"
    end
    return true
end

-- Items the game answered "unknown" for: not shown. The server's own "no such item"
-- (GET_ITEM_INFO_RECEIVED success false) is kept for this game build, so those are not asked
-- again at every login; a few seconds of silence counts only for this session.
local missing = {}
function ns.Missing(itemID, confirmed)
    if type(itemID) ~= "number" then return end
    missing[itemID] = true
    if confirmed then ns.db.unknown[itemID] = true end
end

function ns.LoadUnknown()
    local version, build = GetBuildInfo()
    version = tostring(version) .. "." .. tostring(build)
    if ns.db.unknownBuild ~= version then
        ns.db.unknown, ns.db.unknownBuild = {}, version
    end
    for itemID in pairs(ns.db.unknown) do missing[itemID] = true end
end

-- Collected: the game's own appearance collection knows this look.
function ns.IsCollected(itemID)
    local _, sourceID = ns.LookOf(itemID)
    if not sourceID then return false end
    return C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID) and true or false
end

-- Owned: in the bags, the bank or worn.
function ns.IsOwned(itemID)
    return (C_Item.GetItemCount(itemID, true) or 0) > 0 or C_Item.IsEquippedItem(itemID)
end

-- Search matches the name (from the game's item tables, Names.lua, or what the game has already
-- loaded) or the source. Nothing is asked of the server here: thousands of looks are searched.
-- Names the game loads are kept in the saved settings (DenoWardrobeDB.names), so search knows
-- more every session; ns.WarmNames asks for a few missing ones at a time while the window is open.
local lowerNames = {}
local function NameOf(itemID)
    local name = lowerNames[itemID]
    if name == nil then
        name = (ns.NAMES and ns.NAMES[itemID]) or (ns.db.names and ns.db.names[itemID]) or C_Item.GetItemInfo(itemID)
        if name and not (ns.NAMES and ns.NAMES[itemID]) then ns.db.names[itemID] = name end
        name = name and name:lower() or false
        if name then lowerNames[itemID] = name end
    end
    return name
end

function ns.RememberName(itemID)
    ns.ItemInfo(itemID)                              -- keeps the quality for next session
    local name = C_Item.GetItemInfo(itemID)
    if name and not (ns.NAMES and ns.NAMES[itemID]) then ns.db.names[itemID] = name end
    if name then lowerNames[itemID] = name:lower() end
end

-- Up to `count` looks without a known name are asked for; returns false when none is left.
local warmList, warmAt
function ns.WarmNames(count)
    if not warmList then
        warmList, warmAt = {}, 1
        for _, list in pairs(ns.BuildCatalog()) do
            for _, look in ipairs(list) do warmList[#warmList + 1] = look.id end
        end
    end
    local asked = 0
    while asked < count and warmAt <= #warmList do
        local id = warmList[warmAt]
        warmAt = warmAt + 1
        if not missing[id] and not NameOf(id) then
            C_Item.RequestLoadItemDataByID(id)
            asked = asked + 1
        end
    end
    return warmAt <= #warmList
end

local function Matches(look, text)
    if not text then return true end
    local name = NameOf(look.id)
    local source = ns.SourceText(look)
    return (name and name:find(text, 1, true)) or (source and source:lower():find(text, 1, true))
end

-- The looks for one slot (or every slot while searching), cut to one armour type (nil = every
-- type) and, in the hand slots, to one weapon type (nil = every type).
function ns.Looks(slotKey, armor, search, weapon)
    local all = ns.BuildCatalog()
    local text = search and search ~= "" and search:lower() or nil
    local out = {}
    for _, slot in ipairs(ns.SLOTS) do
        if text or slot.key == slotKey then
            for _, look in ipairs(all[slot.key]) do
                if not missing[look.id] and not ns.IsJunk(look.id) and (not armor or look.armor == nil or look.armor == armor)
                    and (weapon == nil or look.weapon == weapon) and Matches(look, text) then
                    out[#out + 1] = look
                end
            end
        end
    end
    return out
end

-- The armour a class wears from level 40 (the most it can).
local CLASS_ARMOR = {
    MAGE = 1, PRIEST = 1, WARLOCK = 1, ROGUE = 2, DRUID = 2,
    HUNTER = 3, SHAMAN = 3, WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
}
function ns.PlayerArmor()
    local _, class = UnitClass("player")
    return CLASS_ARMOR[class] or 1
end
