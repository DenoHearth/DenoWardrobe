-- Deno Wardrobe: shared bits. The look matches Raid Recruiter and Deno AH.

local ADDON, ns = ...

ns.ADDON = ADDON

ns.COLOR = {
    accent    = { 0.52, 0.80, 1.00 },
    accentDim = { 0.15, 0.15, 0.16 },
    good      = { 0.25, 0.85, 0.42 },
    warn      = { 1.00, 0.76, 0.24 },
    bad       = { 0.93, 0.32, 0.32 },
    text      = { 0.95, 0.95, 0.96 },
    textDim   = { 0.60, 0.62, 0.68 },
    panel     = { 0.10, 0.10, 0.11 },
    section   = { 0.065, 0.075, 0.10 },
    inset     = { 0.045, 0.05, 0.065 },
    border    = { 0.38, 0.38, 0.40 },
    edge      = { 0.28, 0.29, 0.32 },
    line      = { 0.20, 0.24, 0.31 },
    hover     = { 0.58, 0.80, 1.00 },
}

ns.defaults = {
    outfits = {},       -- { { name = "...", items = { HEAD = itemID, ... } }, ... }
    names = {},         -- [itemID] = name, for search: names the game has loaded
    found = {},         -- [itemID] = where it was met: looks AtlasLoot and the world list do not have
    quality = {},       -- [itemID] = quality the game told us, shown at once next session
    unknown = {},       -- [itemID] = true: the server said there is no such item (this game build)
    favSets = {},       -- [setID] = true: sets marked Favourite on the Sets page, listed first
}

function ns.Print(fmt, ...)
    local msg = select("#", ...) > 0 and fmt:format(...) or fmt
    local c = ns.COLOR.accent
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff%02x%02x%02xDeno Wardrobe|r: %s", c[1] * 255, c[2] * 255, c[3] * 255, msg))
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        DenoWardrobeDB = DenoWardrobeDB or {}
        for key, value in pairs(ns.defaults) do
            if DenoWardrobeDB[key] == nil then DenoWardrobeDB[key] = value end
        end
        ns.db = DenoWardrobeDB
        ns.LoadUnknown()
    else
        -- not inside PLAYER_LOGIN itself: the game runs its own login work in the same pass
        C_Timer.After(0, ns.MakeCharacterTab)
    end
end)

SLASH_DENOWARDROBE1 = "/wardrobe"
SLASH_DENOWARDROBE2 = "/denowardrobe"
SlashCmdList.DENOWARDROBE = function()
    if ns.Toggle then ns.Toggle() end
end
