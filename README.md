# Deno Wardrobe

A wardrobe for WoW: Forever on its own tab of the character screen. Browse thousands of looks with your own character in every preview, try them on a turnable model, filter by armour or weapon type, and save named outfits to equip or send to the transmogrifier. Looks come live from AtlasLoot Forever, Forever Dungeon Journal and Questie when installed, plus the world and what you find.

[![Latest release](https://img.shields.io/github/v/release/DenoHearth/DenoWardrobe?label=download&style=for-the-badge)](https://github.com/DenoHearth/DenoWardrobe/releases/latest)

A World of Warcraft: Forever addon (interface 16001).

## What it does

- **A wardrobe tab on the character screen.** Pick a slot, then an armour type (Cloth, Leather, Mail, Plate) or, for Main Hand and Off Hand, a weapon type (1H/2H Sword, Axe, Mace, Dagger, Shield, Bow and more). Search every slot by name or by where an item comes from.
- **Your own character in every preview.** Each tile shows the look on you; the large model on the right is turnable (drag), zoomable (wheel) and can be moved (right-drag).
- **Try on, then save.** Pieces go on over your own gear, or on a bare model after Undress. The strip under the model shows what is on it; a button takes a piece off. Save named outfits, Equip the pieces you own, or send a whole outfit to the transmogrifier.
- **Collected and owned marks** from the game's own appearance collection.
- **Previews without waiting for the server.** The look of every item comes from the game's own item tables, so tiles are dressed straight away, also right after a login. Item names and quality are remembered between sessions.
- **Junk left out:** placeholder, deprecated and test items and anything above level 60.

## Where the looks come from

Read live each session from the addons you have installed, so their updates show up here at the next login. Nothing of theirs is copied into this addon.

| Addon | What it adds |
|---|---|
| AtlasLoot Forever | dungeon, raid, crafting, PvP and faction loot |
| Forever Dungeon Journal | Forever's own dungeon loot, dungeon quest rewards, shared drops |
| Questie | drops, vendors and quest rewards for every item it knows |

Without any of them the wardrobe still has the world list that ships with it, and every wearable item you meet in game (bags, loot, vendors, quest rewards) joins it by itself.

## Install

1. Download the zip from the [latest release](https://github.com/DenoHearth/DenoWardrobe/releases/latest).
2. Extract the `DenoWardrobe` folder into your client's `Interface\AddOns\` directory.
3. Restart the client, or type `/reload` if it is already running.

## Commands

- `/denowardrobe`
- `/wardrobe`

## Compatibility

- World of Warcraft: Forever, interface version **16001**.
- Forever only. It uses that client's API and will not load on retail or the Classic clients.

## Changelog

What changed in each version: [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE). `ServerLooks.lua` is a list of item ids with where each one drops, is sold or is given, compiled from a VMaNGOS-based world database (GPL); `Looks.lua` and `Names.lua` are item facts read from the game client's own tables.  Current version: 0.7.0.
