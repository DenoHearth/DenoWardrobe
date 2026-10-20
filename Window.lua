-- The wardrobe window, built like the game's own collections and transmog windows: Blizzard's
-- window frame, tabs, buttons and search box, and the game's wardrobe art (tile borders, slot
-- icons, the race backdrop behind the try-on model). Opened from its own side tab on the
-- character screen. Every action is a visible button (no right-click, no click-on-a-picture).

local ADDON, ns = ...

local COLS, ROWS = 5, 2
local PER_PAGE = COLS * ROWS
-- The game's wardrobe tile: a 78 x 104 model inside 96 x 122 border art (102 x 128 for the
-- selection glow), here 1.18 times as large. The art's opening is the model's size: a model
-- larger than the opening draws over the frame's edge.
local MODEL_W, MODEL_H = 92, 122
local BORDER_W, BORDER_H = math.floor(MODEL_W * 96 / 78 + 0.5), math.floor(MODEL_H * 122 / 104 + 0.5)
local GLOW_W, GLOW_H = math.floor(MODEL_W * 102 / 78 + 0.5), math.floor(MODEL_H * 128 / 104 + 0.5)
local TILE_W, TILE_H = 118, 196
local LEFT_W = COLS * TILE_W + 16

local OUTFITS_PER_PAGE = 8

local window, tabs = nil, {}
local pages = {}
local slotButtons, armorButtons, tiles, wornButtons = {}, {}, {}, {}
local weaponButtons = {}
local scene, pageText, countText, emptyText, searchBox, nameBox, outfitRows = nil, nil, nil, nil, nil, nil, {}
local outfitPageText
-- bare: the try-on model starts from nothing instead of the gear the character wears
-- weapon: the chosen weapon type per hand slot (nil = every type)
local state = { slot = "CHEST", armor = nil, page = 1, outfitPage = 1, wearing = {}, search = "", bare = false, weapon = {} }

local NAV = {
    HEAD = "head", SHOULDER = "shoulder", BACK = "back", CHEST = "chest", WRIST = "wrist", HANDS = "hands",
    WAIST = "waist", LEGS = "legs", FEET = "feet", MAIN = "mainhand", OFF = "secondaryhand",
}

-- Blizzard's red panel button.
local function Button(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height or 22)
    button:SetText(text)
    return button
end

local function Text(parent, font, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

-- Models -----------------------------------------------------------------------

-- Weapons go to the hand they were picked for (an off-hand one-hander would land in the main hand).
local HAND = { MAIN = "MAINHANDSLOT", OFF = "SECONDARYHANDSLOT" }

-- The best thing to hand TryOn: the look's own source (what the game's wardrobe uses), else a link.
local function TryOnID(itemID)
    local _, sourceID = ns.LookOf(itemID)
    return sourceID or ("item:" .. itemID)
end

local function NativeForm()
    if PlayerUtil and PlayerUtil.ShouldUseNativeFormInModelScene then
        return PlayerUtil.ShouldUseNativeFormInModelScene()
    end
    return true
end

-- The try-on stage is the game's own turnable model scene, set up as the game's transmog window
-- sets up its own (Blizzard_Transmog.lua, TransmogCharacterMixin: model scene 290, the player
-- actor by SetModelByUnit; BetterWardrobe and Narcissus use the same scene): drag to turn, wheel
-- to zoom, right-drag to move, plus the game's zoom / turn / reset buttons on top.
local TRYON_SCENE = 290

local function DressStage(resetCamera)
    if not scene then return end
    if resetCamera or not scene:GetActiveCamera() then
        scene:TransitionToModelSceneID(TRYON_SCENE, CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
        scene.ControlFrame:UpdateLayout()
    end
    local actor = scene:GetPlayerActor()
    if not actor then return end
    -- A look tried on before the character has loaded is dropped (seen 2026-10-20: the first
    -- Try on showed nothing until My Gear reloaded the model). So the looks go on again once
    -- the model is there, the way Blizzard's PaperDollFrame waits with SetOnModelLoadedCallback.
    local function dress(a)
        if state.bare then a:Undress() end
        for key, id in pairs(state.wearing) do a:TryOn(TryOnID(id), HAND[key]) end
    end
    actor:SetOnModelLoadedCallback(dress)
    actor:SetModelByUnit("player", false, true, false, NativeForm())
    dress(actor)
end

-- The wardrobe tiles: a DressUpModel each, dressed as the game's own wardrobe dresses its tiles
-- (Blizzard_TransmogShared.lua, ItemModelBaseMixin:Reload and WARDROBE_MODEL_SETUP): the bare
-- character with a few plain pieces so the look reads on its own. The game's dark "transmog
-- skin" is off on every slot: he wants his own character in the tiles, skin, face and hair
-- (2026-10-20: "why an empty man"). Weapons are shown alone.
local PLAIN = { CHEST = 78420, LEGS = 78425, FEET = 78427, HANDS = 78426, HEAD = 78416 }
local SETUP = {
    HEAD  = { skin = false, choices = false, obey = false, plain = { CHEST = true } },
    HANDS = { skin = false, choices = true,  obey = true,  plain = { CHEST = true, LEGS = true, FEET = true, HEAD = true } },
    FEET  = { skin = false, choices = true,  obey = true,  plain = { CHEST = true, HANDS = true, LEGS = true, HEAD = true } },
    other = { skin = false, choices = true,  obey = true,  plain = { HEAD = true } },
}
-- Armour is framed by the model's own portrait camera, the same way on every tile. The game's
-- per-look cameras (Model_ApplyUICamera) left some tiles black in game (seen 2026-10-20: helms
-- with a camera of their own showed nothing), and a tile that once had a portrait zoom carried
-- it into the next look's camera. Weapons, shown alone, keep the game's camera.
local ZOOM = { HEAD = 0.75, SHOULDER = 0.55 }
local FACING = { BACK = math.pi }

local function TileCamera(model)
    model:RefreshCamera()
    if model.cameraID then
        model:SetPortraitZoom(0)
        Model_ApplyUICamera(model, model.cameraID)
    else
        -- undo what a weapon's camera left on this tile (Model_ApplyUICamera sets pitch, roll,
        -- model-centre mode and a frozen pose): those left tiles tilted (seen 2026-10-20)
        model:SetPosition(0, 0, 0)
        model:SetPitch(0)
        model:SetRoll(0)
        model:UseModelCenterToTransform(false)
        model:SetAnimation(0, 0)
        model:SetPortraitZoom(ZOOM[model.slot] or 0)
        model:SetFacing(FACING[model.slot] or 0.35)
    end
end

-- Returns false when the character model is not ready yet (just logged in): tried again later.
local function DressTile(model, look)
    local appearanceID = ns.LookOf(look.id)
    model.slot = look.slot
    model.noAppearance = appearanceID == nil
    model.cameraID = nil
    if HAND[look.slot] and appearanceID then
        local cameraID = C_TransmogCollection.GetAppearanceCameraID(appearanceID)
        model.cameraID = cameraID and cameraID ~= 0 and cameraID or nil
        model.setupFor = nil
        model:SetItemAppearance(appearanceID)          -- the weapon alone; OnModelLoaded frames it
        return true
    end
    if not IsUnitModelReadyForUI("player") then return false end
    if model.setupFor ~= look.slot then
        local setup = SETUP[look.slot] or SETUP.other
        model.setupFor = look.slot
        model:SetUseTransmogSkin(setup.skin)
        model:SetUseTransmogChoices(setup.choices)
        model:SetObeyHideInTransmogFlag(setup.obey)
        model:SetUnit("player", false, NativeForm())  -- OnModelLoaded frames it
        -- the game's filler pieces, where this game has them (Forever has none of them today)
        for key in pairs(setup.plain) do
            if ns.LOOKS and ns.LOOKS[PLAIN[key]] then model:TryOn(ns.LOOKS[PLAIN[key]][1]) end
        end
    else
        TileCamera(model)
    end
    -- tried on now, and again when the model has finished loading (OnModelLoaded): a look
    -- tried on while the character is still loading is dropped, and the tile stayed empty
    model.want, model.wantHand, model.wantDone = TryOnID(look.id), HAND[look.slot], false
    model:TryOn(model.want, model.wantHand)
    return true
end

-- the tile's model has loaded: frame it, then put the look on (again)
local function TileLoaded(model)
    TileCamera(model)
    -- once per look: should a TryOn ever reload the model, this does not go round in circles
    if model.want and model.setupFor and not model.wantDone then
        model.wantDone = true
        model:TryOn(model.want, model.wantHand)
    end
end

-- Collection page ----------------------------------------------------------------

local Refresh, RefreshWorn
local retryQueued

local function TryOn(look)
    state.wearing[look.slot] = look.id
    local actor = scene and scene:GetPlayerActor()
    if actor and actor:IsLoaded() then actor:TryOn(TryOnID(look.id), HAND[look.slot]) else DressStage() end
    Refresh()
end

local function ShowTile(tile, look)
    tile.look = look
    if not look then tile.dressed = nil tile:Hide() return end
    tile:Show()
    local name, quality = ns.ItemInfo(look.id)
    if not C_Item.GetItemInfo(look.id) then
        -- asked once (the name and quality come back for the tooltip and for next session).
        -- No answer at all after a while, and no name ever seen: the game has no such item.
        if not look.asked then
            look.asked = GetTime()
            C_Item.RequestLoadItemDataByID(look.id)
        end
        if not name and GetTime() - look.asked > 6 then
            ns.Missing(look.id)
        elseif not name and not look.recheck then
            look.recheck = true
            C_Timer.After(6.5, function() Refresh() end)
        end
    end
    local r, g, b = C_Item.GetItemQualityColor(quality or 1)
    tile.name:SetText(name or ("item " .. look.id))
    tile.name:SetTextColor(r, g, b)
    -- dressed again only when the look changes (names arriving redraw the page often), or when
    -- the game's appearance for it has arrived since it was drawn without one
    if tile.dressed ~= look.id or (tile.model.noAppearance and ns.LookOf(look.id)) then
        tile.dressed = DressTile(tile.model, look) and look.id or nil
        if not tile.dressed and not retryQueued then
            -- the character model is not ready yet (just logged in): dress the page again shortly
            retryQueued = true
            C_Timer.After(0.5, function() retryQueued = false Refresh() end)
        end
    end
    local _, sourceID = ns.LookOf(look.id)
    local info = sourceID and C_TransmogCollection.GetSourceInfo(sourceID)
    tile.noShow:SetShown(info ~= nil and info.canDisplayOnPlayer == false)
    -- the game's wardrobe borders: gold for collected, plain for not yet, the selection glow on top
    local collected = ns.IsCollected(look.id)
    tile.border:SetAtlas(collected and "transmog-wardrobe-border-collected" or "transmog-wardrobe-border-uncollected")
    local on = state.wearing[look.slot] == look.id
    tile.selected:SetShown(on)
    tile.owned:SetShown(not collected and ns.IsOwned(look.id))
    tile.button:SetText(on and "Wearing" or "Try on")
    tile.button:SetEnabled(not on)
end

Refresh = function()
    if not window or not window:IsShown() or not pages.collection:IsShown() then return end
    local hands = ns.WEAPON_TYPES[state.slot] and state.search == ""
    local weapon = hands and state.weapon[state.slot] or nil
    local looks = ns.Looks(state.slot, state.armor, state.search, weapon)
    local pagesTotal = math.max(1, math.ceil(#looks / PER_PAGE))
    state.page = math.min(math.max(state.page, 1), pagesTotal)
    for i = 1, PER_PAGE do ShowTile(tiles[i], looks[(state.page - 1) * PER_PAGE + i]) end
    -- the next page is asked for now, so a look the game does not know leaves the list before
    -- that page is shown instead of disappearing from under the mouse
    for i = state.page * PER_PAGE + 1, math.min(#looks, (state.page + 1) * PER_PAGE) do
        local look = looks[i]
        if not look.asked and not C_Item.GetItemInfo(look.id) then
            look.asked = GetTime()
            C_Item.RequestLoadItemDataByID(look.id)
        end
    end
    pageText:SetFormattedText("Page %d/%d", state.page, pagesTotal)
    local collected = 0
    for _, look in ipairs(looks) do if ns.IsCollected(look.id) then collected = collected + 1 end end
    local what = state.search ~= "" and ('"' .. state.search .. '"') or ns.SLOT_BY_KEY[state.slot].name
    local kind = ""
    if hands then
        for _, entry in ipairs(ns.WEAPON_TYPES[state.slot]) do
            if entry[1] == weapon then kind = " (" .. entry[2] .. ")" end
        end
    elseif state.armor then
        kind = " in " .. ns.ARMOR_TYPES[state.armor]
    end
    countText:SetFormattedText("%s: %d looks%s  |cffffffff%d collected|r", what, #looks, kind, collected)
    -- the hand slots swap the armour buttons for weapon types; only types that have looks
    for _, button in pairs(armorButtons) do button:SetShown(not hands) end
    for _, button in ipairs(weaponButtons) do button:Hide() end
    countText:ClearAllPoints()
    if hands then
        local present = {}
        for _, look in ipairs(ns.Looks(state.slot, nil, "", nil)) do
            if look.weapon ~= nil then present[look.weapon] = true end
        end
        local shown = { { nil, "All" } }
        for _, entry in ipairs(ns.WEAPON_TYPES[state.slot]) do
            if present[entry[1]] then shown[#shown + 1] = entry end
        end
        for i, entry in ipairs(shown) do
            local button = weaponButtons[i]
            if not button then break end
            button.weapon = entry[1]
            button:SetText(entry[2])
            button:SetEnabled(entry[1] ~= weapon)
            button:Show()
        end
        -- the weapon rows fill the line: the count goes above the page arrows
        countText:SetPoint("BOTTOM", 0, 46)
    else
        countText:SetPoint("LEFT", armorButtons[0], "RIGHT", 12, 0)
    end
    emptyText:SetShown(#looks == 0)
    for key, button in pairs(slotButtons) do button.selected:SetShown(state.search == "" and key == state.slot) end
    for key, button in pairs(armorButtons) do button:SetEnabled(key ~= (state.armor or 0)) end
    RefreshWorn()
end

-- The pieces on the try-on model, one button per slot under it: a button takes its piece off.
RefreshWorn = function()
    for _, button in ipairs(wornButtons) do
        local id = state.wearing[button.slot.key]
        button.icon:SetTexture(id and C_Item.GetItemIconByID(id) or nil)
        button.icon:SetShown(id ~= nil)
        button.empty:SetShown(id == nil)
        local _, quality = id and ns.ItemInfo(id)
        if quality and quality >= 2 then
            local r, g, b = C_Item.GetItemQualityColor(quality)
            button.border:SetVertexColor(r, g, b)
            button.border:Show()
        else
            button.border:Hide()
        end
        button:SetEnabled(id ~= nil)
    end
end

local function BuildCollection(page)
    -- the game's wardrobe page backdrop
    local bg = page:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas("collections-background-c60")
    bg:SetAllPoints()

    -- the slots, with the transmog window's slot icons
    for i, slot in ipairs(ns.SLOTS) do
        local button = CreateFrame("Button", nil, page)
        button:SetSize(38, 40)
        button:SetPoint("TOPLEFT", 14 + (i - 1) * 46, -10)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAtlas("transmog-nav-slot-" .. NAV[slot.key])
        icon:SetSize(35, 37)
        icon:SetPoint("CENTER")
        button.selected = button:CreateTexture(nil, "OVERLAY")
        button.selected:SetAtlas("transmog-nav-slot-selected")
        button.selected:SetSize(45, 47)
        button.selected:SetPoint("CENTER")
        button:SetHighlightAtlas("transmog-nav-slot-selected", "ADD")
        button:SetScript("OnClick", function()
            state.slot, state.page = slot.key, 1
            if state.search ~= "" then searchBox:SetText("") end
            Refresh()
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(slot.name)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        slotButtons[slot.key] = button
    end

    -- armour types: the chosen one is greyed, as the game's own filter buttons are
    local labels = { "Cloth", "Leather", "Mail", "Plate", "All" }
    for key, label in ipairs(labels) do
        local button = Button(page, label, 70, 22)
        button:SetPoint("TOPLEFT", 14 + (key - 1) * 72, -58)
        local armor = key ~= 5 and key or nil
        button:SetScript("OnClick", function() state.armor, state.page = armor, 1 Refresh() end)
        armorButtons[armor or 0] = button
    end
    countText = Text(page, "GameFontNormal")
    countText:SetPoint("LEFT", armorButtons[0], "RIGHT", 12, 0)

    -- weapon types for Main Hand and Off Hand, in place of the armour buttons: two rows of
    -- eight under the slot icons; the chosen one is greyed like the armour buttons
    for i = 1, 16 do
        local button = Button(page, "", 70, 20)
        local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
        button:SetPoint("TOPLEFT", 14 + col * 72, -52 - row * 21)
        button:SetScript("OnClick", function(self)
            state.weapon[state.slot], state.page = self.weapon, 1
            Refresh()
        end)
        button:Hide()
        weaponButtons[i] = button
    end

    -- the looks
    for i = 1, PER_PAGE do
        local tile = CreateFrame("Frame", nil, page)
        tile:SetSize(TILE_W, TILE_H)
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        tile:SetPoint("TOPLEFT", 8 + col * TILE_W, -92 - row * (TILE_H + 6))
        tile.model = CreateFrame("DressUpModel", nil, tile)
        tile.model:SetSize(MODEL_W, MODEL_H)
        tile.model:SetPoint("TOP", 0, -(GLOW_H - MODEL_H) / 2 - 2)
        -- as the game's wardrobe tiles (ItemModelBaseMixin:OnLoad): no own gear, even light,
        -- and the model kept while hidden so a page shown again is not reloaded in worn gear
        tile.model:SetAutoDress(false)
        tile.model:SetKeepModelOnHide(true)
        tile.model:SetLight(true, {
            omnidirectional = false, point = CreateVector3D(-1, 1, -1),
            ambientIntensity = 1.05, ambientColor = CreateColor(1, 1, 1),
            diffuseIntensity = 0, diffuseColor = CreateColor(1, 1, 1),
        })
        tile.model:SetScript("OnModelLoaded", TileLoaded)
        local well = tile.model:CreateTexture(nil, "BACKGROUND")
        well:SetAllPoints()
        well:SetColorTexture(0, 0, 0, 0.55)
        tile.border = tile.model:CreateTexture(nil, "OVERLAY", nil, 1)
        tile.border:SetPoint("CENTER")
        tile.border:SetSize(BORDER_W, BORDER_H)
        tile.selected = tile.model:CreateTexture(nil, "OVERLAY", nil, 2)
        tile.selected:SetAtlas("transmog-wardrobe-border-selected")
        -- added light: the art's dark middle covered the model (the tile went black on Try on)
        tile.selected:SetBlendMode("ADD")
        tile.selected:SetPoint("CENTER")
        tile.selected:SetSize(GLOW_W, GLOW_H)
        -- a look the game cannot draw on this character (some helms on some races): said so,
        -- as the game's own wardrobe does, instead of an empty picture
        tile.noShow = tile.model:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tile.noShow:SetPoint("CENTER")
        tile.noShow:SetWidth(MODEL_W - 10)
        tile.noShow:SetText("Not shown on your character")
        tile.owned = tile.model:CreateTexture(nil, "OVERLAY", nil, 3)
        tile.owned:SetAtlas("transmog-icon-checkmark")
        tile.owned:SetSize(18, 18)
        tile.owned:SetPoint("TOPRIGHT", -6, -6)
        tile.name = Text(tile, "GameFontHighlightSmall")
        tile.name:SetPoint("TOP", tile.model, "BOTTOM", 0, -(GLOW_H - MODEL_H) / 2 - 2)
        tile.name:SetWidth(TILE_W - 6)
        tile.name:SetJustifyH("CENTER")
        tile.name:SetWordWrap(false)
        tile.button = Button(tile, "Try on", TILE_W - 18, 20)
        tile.button:SetPoint("TOP", tile.name, "BOTTOM", 0, -4)
        tile.button:SetScript("OnClick", function() if tile.look then TryOn(tile.look) end end)
        tile.model:EnableMouse(true)
        tile.model:SetScript("OnEnter", function()
            if not tile.look then return end
            GameTooltip:SetOwner(tile.model, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(tile.look.id)
            GameTooltip:AddLine("From: " .. (ns.SourceText(tile.look) or "?"), 0.6, 0.8, 1)
            if not ns.IsCollected(tile.look.id) and ns.IsOwned(tile.look.id) then
                GameTooltip:AddLine("In your bags", 0.25, 0.85, 0.42)
            end
            GameTooltip:Show()
        end)
        tile.model:SetScript("OnLeave", GameTooltip_Hide)
        tiles[i] = tile
    end
    emptyText = Text(page, "GameFontHighlight", "Nothing here. Install AtlasLoot Forever for the dungeon and raid loot.")
    emptyText:SetPoint("TOP", 0, -140)

    -- paging, at the bottom middle as in the game's wardrobe
    pageText = Text(page, "GameFontHighlight")
    pageText:SetPoint("BOTTOM", 0, 14)
    local prev = CreateFrame("Button", nil, page)
    prev:SetSize(32, 32)
    prev:SetPoint("RIGHT", pageText, "LEFT", -8, 0)
    prev:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    prev:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    prev:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    prev:SetScript("OnClick", function() state.page = state.page - 1 Refresh() end)
    local nextButton = CreateFrame("Button", nil, page)
    nextButton:SetSize(32, 32)
    nextButton:SetPoint("LEFT", pageText, "RIGHT", 8, 0)
    nextButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    nextButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    nextButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    nextButton:SetScript("OnClick", function() state.page = state.page + 1 Refresh() end)
end

-- Outfits page ---------------------------------------------------------------------

local function RefreshOutfits()
    if not window then return end
    local atTransmog = ns.AtTransmogrifier()
    local pagesTotal = math.max(1, math.ceil(#ns.db.outfits / OUTFITS_PER_PAGE))
    state.outfitPage = math.min(math.max(state.outfitPage, 1), pagesTotal)
    outfitPageText:SetFormattedText("Page %d/%d", state.outfitPage, pagesTotal)
    for i, row in ipairs(outfitRows) do
        row.index = (state.outfitPage - 1) * OUTFITS_PER_PAGE + i
        local outfit = ns.db.outfits[row.index]
        row:SetShown(outfit ~= nil)
        if outfit then
            row.name:SetText(outfit.name)
            local n, collected, total = 0, 0, 0
            for _, slot in ipairs(ns.SLOTS) do
                local id = outfit.items[slot.key]
                if id then
                    total = total + 1
                    if ns.IsCollected(id) then collected = collected + 1 end
                    if n < 9 then
                        n = n + 1
                        row.icons[n]:SetTexture(C_Item.GetItemIconByID(id))
                        row.icons[n]:Show()
                    end
                end
            end
            for k = n + 1, 9 do row.icons[k]:Hide() end
            row.count:SetFormattedText("%d of %d collected", collected, total)
            row.transmog:SetEnabled(atTransmog)
        end
    end
end

local function SelectPage(name)
    for key, page in pairs(pages) do page:SetShown(key == name) end
    PanelTemplates_SetTab(window, name == "collection" and 1 or 2)
    if name == "outfits" then RefreshOutfits() else Refresh() end
end

local function TypedName()
    local text = strtrim(nameBox:GetText() or "")
    return text ~= "" and text or nil
end

local function BuildOutfits(page)
    local bg = page:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas("collections-background-c60")
    bg:SetAllPoints()
    local heading = Text(page, "GameFontNormalLarge", "Saved Outfits")
    heading:SetPoint("TOPLEFT", 16, -14)
    local hint = Text(page, "GameFontHighlightSmall", "Equip puts on the pieces you have. Transmog, at a transmogrifier, sets the collected looks on its window.")
    hint:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
    for i = 1, OUTFITS_PER_PAGE do
        local row = CreateFrame("Frame", nil, page, "InsetFrameTemplate")
        row:SetSize(LEFT_W - 28, 52)
        row:SetPoint("TOPLEFT", 14, -48 - (i - 1) * 56)
        row.name = Text(row, "GameFontNormal")
        row.name:SetPoint("TOPLEFT", 10, -7)
        row.count = Text(row, "GameFontDisableSmall")
        row.count:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
        row.icons = {}
        for k = 1, 9 do
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20)
            icon:SetPoint("BOTTOMLEFT", 10 + (k - 1) * 23, 6)
            row.icons[k] = icon
        end
        local function Outfit() return row.index and ns.db.outfits[row.index] end
        local buttons = {
            { "Try on", 70, function(outfit)
                wipe(state.wearing)
                for key, id in pairs(outfit.items) do state.wearing[key] = id end
                state.bare = true
                nameBox:SetText(outfit.name)
                DressStage()
                SelectPage("collection")
            end },
            { "Equip", 62, function(outfit) ns.EquipOutfit(outfit) end },
            { "Transmog", 84, function(outfit) ns.TransmogOutfit(outfit) end, "transmog" },
            { "Rename", 72, function(outfit)
                local name = TypedName()
                if not name then ns.Print("type the new name in the box under the model first.") return end
                outfit.name = name
                nameBox:SetText("")
                RefreshOutfits()
            end },
            { "Delete", 66, function() table.remove(ns.db.outfits, row.index) RefreshOutfits() end },
        }
        local right = -8
        for b = #buttons, 1, -1 do
            local spec = buttons[b]
            local button = Button(row, spec[1], spec[2], 22)
            button:SetPoint("RIGHT", right, 0)
            button:SetScript("OnClick", function() local outfit = Outfit() if outfit then spec[3](outfit) end end)
            if spec[4] then row[spec[4]] = button end
            right = right - spec[2] - 2
        end
        outfitRows[i] = row
    end

    outfitPageText = Text(page, "GameFontHighlight")
    outfitPageText:SetPoint("BOTTOM", 0, 14)
    local function PageButton(dir, anchor, x)
        local button = CreateFrame("Button", nil, page)
        button:SetSize(32, 32)
        button:SetPoint(anchor, outfitPageText, anchor == "RIGHT" and "LEFT" or "RIGHT", x, 0)
        local art = dir < 0 and "PrevPage" or "NextPage"
        button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. art .. "-Up")
        button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. art .. "-Down")
        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        button:SetScript("OnClick", function() state.outfitPage = state.outfitPage + dir RefreshOutfits() end)
    end
    PageButton(-1, "RIGHT", -8)
    PageButton(1, "LEFT", 8)
end

-- Window -----------------------------------------------------------------------------

local function RaceBackdrop(texture)
    local _, race = UnitRace("player")
    local atlas = race and ("transmog-background-race-" .. race:lower())
    if atlas and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas)
    else
        texture:SetAtlas("collections-3d-character-background-c60")
    end
end

local function Build()
    window = CreateFrame("Frame", "DenoWardrobeFrame", UIParent, "ButtonFrameTemplate")
    window:SetSize(LEFT_W + 300, 662)
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:EnableMouse(true)
    window:SetTitle("Deno Wardrobe")
    window:SetPortraitToAsset("Interface/ICONS/INV_Chest_Cloth_17")
    ButtonFrameTemplate_HideButtonBar(window)
    window.Inset:Hide()
    window:Hide()

    window.sub = Text(window, "GameFontDisableSmall")
    window.sub:SetPoint("TOPRIGHT", -34, -32)
    window.sub:SetJustifyH("RIGHT")

    -- search every slot by name or by where it comes from (the game's search box)
    searchBox = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("TOPLEFT", 64, -30)
    searchBox.Instructions:SetText("Search name or source")
    -- searched a moment after the typing stops, from two letters on
    local pending
    searchBox:HookScript("OnTextChanged", function(self)
        local text = strtrim(self:GetText() or "")
        if #text == 1 then return end
        if pending then pending:Cancel() end
        pending = C_Timer.NewTimer(0.4, function()
            pending = nil
            if text ~= state.search then
                state.search, state.page = text, 1
                if not pages.collection:IsShown() then SelectPage("collection") else Refresh() end
            end
        end)
    end)

    for _, key in ipairs({ "collection", "outfits" }) do
        local page = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
        page:SetPoint("TOPLEFT", 6, -58)
        page:SetPoint("BOTTOMLEFT", 6, 8)
        page:SetWidth(LEFT_W)
        pages[key] = page
    end
    BuildCollection(pages.collection)
    BuildOutfits(pages.outfits)

    -- the game's bottom tabs (they size themselves on show from these two)
    window.minTabWidth, window.tabPadding = 110, 20
    local tabNames = { "Collection", "Outfits" }
    for i, label in ipairs(tabNames) do
        local tab = CreateFrame("Button", "DenoWardrobeFrameTab" .. i, window, "PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(label)
        if i == 1 then
            tab:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 12, 2)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -16, 0)
        end
        tab:SetScript("OnClick", function() SelectPage(i == 1 and "collection" or "outfits") end)
        tabs[i] = tab
    end
    window.Tabs = tabs
    PanelTemplates_SetNumTabs(window, #tabs)

    -- try-on: the player in what has been picked, before the race backdrop of the transmog window
    local stage = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
    stage:SetPoint("TOPLEFT", pages.collection, "TOPRIGHT", 4, 0)
    stage:SetPoint("BOTTOMRIGHT", -6, 8)
    local STAGE_BOTTOM = 222
    local backdrop = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
    backdrop:SetPoint("TOPLEFT", 3, -3)
    backdrop:SetPoint("BOTTOMRIGHT", -3, STAGE_BOTTOM)
    window:HookScript("OnShow", function() RaceBackdrop(backdrop) end)
    scene = CreateFrame("ModelScene", nil, stage, "PanningModelSceneMixinTemplate")
    scene:SetPoint("TOPLEFT", 3, -3)
    scene:SetPoint("BOTTOMRIGHT", -3, STAGE_BOTTOM)
    -- the game's zoom in / zoom out / turn left / turn right / reset buttons; kept in view
    -- (the game shows them only while the mouse is over the model)
    scene.ControlFrame = CreateFrame("Frame", nil, scene, "ModelSceneControlFrameTemplate")
    scene.ControlFrame:SetPoint("TOP", 0, -30)
    scene.ControlFrame:SetModelScene(scene)
    scene.ControlFrame:Show()
    scene:HookScript("OnLeave", function() scene.ControlFrame:Show() end)
    -- reachable for tests and other addons
    window.scene, window.tiles, window.slotButtons, window.wornButtons = scene, tiles, slotButtons, wornButtons
    local stageTitle = Text(stage, "GameFontNormal", "Try On")
    stageTitle:SetPoint("TOP", 0, -10)
    local moveHint = Text(stage, "GameFontDisableSmall", "Drag: turn   Wheel: zoom   Right-drag: move")
    moveHint:SetPoint("BOTTOM", scene, "BOTTOM", 0, 6)

    -- what is on the model, slot by slot; a button takes that piece off. 34 px buttons in two
    -- rows of six (they were 22 px in one row: too small to see the icons), the icon's dark
    -- edge cropped and a frame in the item's quality colour, as on the character screen
    local SIZE, GAP, PER_ROW = 34, 4, 6
    local rowW = PER_ROW * SIZE + (PER_ROW - 1) * GAP
    for i, slot in ipairs(ns.SLOTS) do
        local button = CreateFrame("Button", nil, stage)
        button:SetSize(SIZE, SIZE)
        local col, row = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
        button:SetPoint("TOPLEFT", stage, "BOTTOM", -rowW / 2 + col * (SIZE + GAP), STAGE_BOTTOM - 6 - row * (SIZE + GAP))
        button.slot = slot
        button.empty = button:CreateTexture(nil, "ARTWORK")
        button.empty:SetAtlas("transmog-nav-slot-" .. NAV[slot.key])
        button.empty:SetAllPoints()
        button.empty:SetDesaturated(true)
        button.empty:SetAlpha(0.45)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        button.border = button:CreateTexture(nil, "OVERLAY")
        button.border:SetTexture("Interface\\Common\\WhiteIconFrame")
        button.border:SetAllPoints()
        button.border:Hide()
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button:SetMotionScriptsWhileDisabled(true)
        button:SetScript("OnClick", function()
            state.wearing[slot.key] = nil
            DressStage()
            Refresh()
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local id = state.wearing[slot.key]
            if id then
                GameTooltip:SetItemByID(id)
                GameTooltip:AddLine("Click to take it off.", 0.6, 0.8, 1)
            else
                GameTooltip:SetText(slot.name)
                GameTooltip:AddLine("Nothing tried on here.", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        wornButtons[i] = button
    end
    nameBox = CreateFrame("EditBox", nil, stage, "InputBoxTemplate")
    nameBox:SetSize(250, 22)
    nameBox:SetAutoFocus(false)
    nameBox:SetPoint("BOTTOM", 4, 100)
    local nameLabel = Text(stage, "GameFontNormalSmall", "Outfit name")
    nameLabel:SetPoint("BOTTOMLEFT", nameBox, "TOPLEFT", -4, 2)
    nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local save = Button(stage, "Save as Outfit", 256, 24)
    save:SetPoint("BOTTOM", 0, 68)
    save:SetScript("OnClick", function()
        if not next(state.wearing) then ns.Print("try something on first.") return end
        local items = {}
        for key, id in pairs(state.wearing) do items[key] = id end
        local name = TypedName() or ("Outfit " .. (#ns.db.outfits + 1))
        -- newest first; outfits are never dropped, the Outfits page has pages
        table.insert(ns.db.outfits, 1, { name = name, items = items })
        state.outfitPage = 1
        nameBox:SetText("")
        ns.Print("saved %s.", name)
        if pages.outfits:IsShown() then RefreshOutfits() end
    end)
    local mine = Button(stage, "My Gear", 126, 22)
    mine:SetPoint("BOTTOMLEFT", 10, 40)
    mine:SetScript("OnClick", function()
        wipe(state.wearing)
        state.bare = false
        DressStage(true)
        Refresh()
    end)
    local bare = Button(stage, "Undress", 126, 22)
    bare:SetPoint("BOTTOMRIGHT", -10, 40)
    bare:SetScript("OnClick", function()
        wipe(state.wearing)
        state.bare = true
        DressStage()
        Refresh()
    end)
    local hint = Text(stage, "GameFontDisableSmall", "Looks go on over your own gear; Undress first to see them alone.")
    hint:SetPoint("BOTTOM", 0, 16)
    hint:SetWidth(270)
    hint:SetJustifyH("CENTER")

    window:SetScript("OnShow", function()
        window:ClearAllPoints()
        if window.atTransmog then
            -- the game's transmog window is wide and the character screen cannot open beside it:
            -- over its right part, where its item list is; close this to see the game's window again
            window:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -90)
        else
            -- right of the side tabs, which stand out of the character screen's right edge
            local modeTabs = CharacterFrame.ModeTabs
            window:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", (modeTabs and modeTabs:GetWidth() or 0) + 6, 0)
        end
        ns.BuildCatalog()
        if ns.source then
            window.sub:SetFormattedText("%d looks from %s", ns.catalogSize, ns.source)
        else
            window.sub:SetText("No loot lists found")
        end
        if not state.armor then state.armor = ns.PlayerArmor() end
        DressStage(true)
        SelectPage(window.atTransmog and "outfits" or "collection")
    end)
    CharacterFrame:HookScript("OnHide", function() if not window.atTransmog then window:Hide() end end)
    window:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    window:RegisterEvent("TRANSMOGRIFY_OPEN")
    window:RegisterEvent("TRANSMOGRIFY_CLOSE")
    window:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
    window:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    window:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
    -- names for search, a few at a time while the window is open
    local warming = 0
    window:HookScript("OnUpdate", function(_, elapsed)
        warming = warming + elapsed
        if warming < 0.25 or InCombatLockdown() then return end
        warming = 0
        ns.WarmNames(5)
    end)
    local refreshQueued
    window:SetScript("OnEvent", function(_, event, itemID, success)
        -- an item the game does not know (the loot list is ahead of or beside this game's data) is left out
        if event == "GET_ITEM_INFO_RECEIVED" then
            if success == false then ns.Missing(itemID, true) else ns.RememberName(itemID) end
            -- many names arrive while warming: draw again at most twice a second
            if refreshQueued or not window:IsShown() then return end
            refreshQueued = true
            C_Timer.After(0.5, function()
                refreshQueued = false
                if not window:IsShown() then return end
                if pages.collection:IsShown() then Refresh() else RefreshOutfits() end
            end)
            return
        end
        if event == "TRANSMOGRIFY_CLOSE" and window.atTransmog then window:Hide() return end
        if not window:IsShown() then return end
        -- the character model was not ready for the tiles yet, or the worn gear changed
        if event == "UNIT_MODEL_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
            for _, tile in ipairs(tiles) do tile.model.setupFor = nil tile.dressed = nil end
            if not state.bare then DressStage() end
        end
        if pages.collection:IsShown() then Refresh() else RefreshOutfits() end
    end)
end

-- a new find shows at once when the window is open
function ns.OnFound()
    if not window or not window:IsShown() then return end
    window.sub:SetFormattedText("%d looks from %s", ns.catalogSize, ns.source or "your own finds")
    if pages.collection:IsShown() then Refresh() end
end

function ns.Toggle()
    if InCombatLockdown() then ns.Print("not in a fight.") return end
    if not window then Build() end
    if window:IsShown() then window:Hide() return end
    window.atTransmog = ns.AtTransmogrifier() and TransmogFrame and TransmogFrame:IsShown() or false
    if not window.atTransmog and not CharacterFrame:IsShown() then ToggleCharacter("PaperDollFrame") end
    window:Show()
end

-- A button on the game's transmog window that opens the outfits there. The window belongs to
-- Blizzard_Transmog, which loads when a transmogrifier is first spoken to: the button is made
-- once that addon is there, and placed inside the window's top bar.
local transmogButton
local function MakeTransmogButton()
    if transmogButton or not TransmogFrame then return end
    transmogButton = Button(TransmogFrame, "Deno Wardrobe Outfits", 170, 22)
    transmogButton:SetFrameLevel(TransmogFrame:GetFrameLevel() + 50)
    transmogButton:SetPoint("TOPRIGHT", TransmogFrame, "TOPRIGHT", -34, -26)
    transmogButton:SetScript("OnClick", function()
        if window and window:IsShown() then window:Hide() end
        ns.Toggle()
    end)
end
local transmogWatch = CreateFrame("Frame")
transmogWatch:RegisterEvent("ADDON_LOADED")
transmogWatch:RegisterEvent("TRANSMOGRIFY_OPEN")
transmogWatch:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_Transmog" then return end
    MakeTransmogButton()
    if event == "TRANSMOGRIFY_OPEN" then C_Timer.After(0, MakeTransmogButton) end
end)
if C_AddOns.IsAddOnLoaded("Blizzard_Transmog") then MakeTransmogButton() end

-- The side tab, under the other side tabs of the character screen.
local tab
function ns.MakeCharacterTab()
    if tab or not (CharacterFrame and CharacterFrame.ModeTabs and CharacterFrame.ModeTabs.Tabs) then return end
    tab = CreateFrame("Frame", "DenoWardrobeCharacterTab", CharacterFrame.ModeTabs, "LargeSideTabButtonTemplate")
    if tab.Icon then
        tab.Icon:SetTexture("Interface/ICONS/INV_Chest_Cloth_17")
        -- without this the template draws the picture as a small square in the corner
        if tab.SetFillToInterior then tab:SetFillToInterior(true, 50) end
    end
    if tab.SetCustomOnMouseUpHandler then
        tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
            if button == "LeftButton" and upInside then
                ns.Toggle()
                if tab.SetChecked then tab:SetChecked(false) end
            end
        end)
    end
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Deno Wardrobe", 1, 0.82, 0)
        GameTooltip:AddLine("Try on every look, save outfits, wear them.", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", GameTooltip_Hide)
    -- Other addons (Talents Forever, Alex Atlas Loot) also hang a tab under the game's last one,
    -- all on the same spot: this one goes under them.
    local function Place()
        local last, own = nil, {}
        for _, t in ipairs(CharacterFrame.ModeTabs.Tabs) do
            own[t] = true
            if t:IsShown() then last = t end
        end
        for _, child in ipairs({ CharacterFrame.ModeTabs:GetChildren() }) do
            if child ~= tab and not own[child] and child:IsShown() then last = child break end
        end
        tab:ClearAllPoints()
        if last then
            tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2)
        else
            tab:SetPoint("TOPLEFT", CharacterFrame.ModeTabs, "TOPLEFT")
        end
    end
    -- the other tabs get their place only a moment after the screen opens: look again
    -- four times a second for two seconds
    local function PlaceSoon() C_Timer.NewTicker(0.25, Place, 8) end
    PlaceSoon()
    if CharacterFrame.UpdateTabLayout then hooksecurefunc(CharacterFrame, "UpdateTabLayout", PlaceSoon) end
    CharacterFrame:HookScript("OnShow", PlaceSoon)
    tab:Show()
end
