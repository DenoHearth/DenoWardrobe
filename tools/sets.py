"""The class sets for the Sets page, from the game's own ItemSet table (db2 cache of the foreverman
skill): which pieces make each set. Which class a set belongs to and where it comes from is set
down below by set id (the dungeon, raid and PvP sets of every class, the way the game's own
collection journal groups them); the items always come from the game, so a set Forever changes
is right after a rerun.

    py -3 sets.py        writes ../Sets.lua (newest cached build)

Refresh the table first when the client has a new build:
    py -3 ~/.claude/skills/foreverman/tools/db2.py fetch ItemSet
"""
import csv
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
CACHE = Path.home() / ".claude/skills/foreverman/tools/db2cache"

CLASSES = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"]
CLASS_BIT = {"WARRIOR": 1, "PALADIN": 2, "HUNTER": 4, "ROGUE": 8, "PRIEST": 16, "SHAMAN": 64,
             "MAGE": 128, "WARLOCK": 256, "DRUID": 1024}

# group key, name shown under the set, then the set id per class (cross-checked against the
# game's AllowableClass where the item table has the piece, see check() below)
CLASS_SETS = [
    ("D1", "Dungeon Set 1 (Tier 0)", {
        "WARLOCK": 183, "PRIEST": 182, "MAGE": 181, "ROGUE": 184, "DRUID": 185,
        "HUNTER": 186, "WARRIOR": 189, "SHAMAN": 187, "PALADIN": 188}),
    ("D2", "Dungeon Set 2 (Tier 0.5)", {
        "WARLOCK": 518, "PRIEST": 514, "MAGE": 517, "ROGUE": 512, "DRUID": 513,
        "HUNTER": 515, "WARRIOR": 511, "SHAMAN": 519, "PALADIN": 516}),
    ("T1", "Tier 1 - Molten Core", {
        "WARLOCK": 203, "PRIEST": 202, "MAGE": 201, "ROGUE": 204, "DRUID": 205,
        "HUNTER": 206, "WARRIOR": 209, "SHAMAN": 207, "PALADIN": 208}),
    ("T2", "Tier 2 - Blackwing Lair", {
        "WARLOCK": 212, "PRIEST": 211, "MAGE": 210, "ROGUE": 213, "DRUID": 214,
        "HUNTER": 215, "WARRIOR": 218, "SHAMAN": 216, "PALADIN": 217}),
    ("ZG", "Zul'Gurub", {
        "WARLOCK": 481, "PRIEST": 480, "MAGE": 482, "ROGUE": 478, "DRUID": 479,
        "HUNTER": 477, "WARRIOR": 474, "SHAMAN": 476, "PALADIN": 475}),
    ("AQ20", "Ruins of Ahn'Qiraj", {
        "WARLOCK": 500, "PRIEST": 508, "MAGE": 504, "ROGUE": 498, "DRUID": 494,
        "HUNTER": 510, "WARRIOR": 495, "SHAMAN": 502, "PALADIN": 506}),
    ("T25", "Tier 2.5 - Temple of Ahn'Qiraj", {
        "WARLOCK": 499, "PRIEST": 507, "MAGE": 503, "ROGUE": 497, "DRUID": 493,
        "HUNTER": 509, "WARRIOR": 496, "SHAMAN": 501, "PALADIN": 505}),
    ("T3", "Tier 3 - Naxxramas", {
        "WARLOCK": 529, "PRIEST": 525, "MAGE": 526, "ROGUE": 524, "DRUID": 521,
        "HUNTER": 530, "WARRIOR": 523, "SHAMAN": 527, "PALADIN": 528}),
    ("FT", "Forever raid set", {}),
    ("PVPRA", "PvP - Alliance Rare", {
        "WARLOCK": 547, "PRIEST": 549, "MAGE": 546, "ROGUE": 548, "DRUID": 551,
        "HUNTER": 550, "WARRIOR": 545, "PALADIN": 544}),
    ("PVPRH", "PvP - Horde Rare", {
        "WARLOCK": 541, "PRIEST": 540, "MAGE": 542, "ROGUE": 522, "DRUID": 539,
        "HUNTER": 543, "WARRIOR": 537, "SHAMAN": 538}),
    ("PVPEA", "PvP - Alliance Epic", {
        "WARLOCK": 392, "PRIEST": 389, "MAGE": 388, "ROGUE": 394, "DRUID": 397,
        "HUNTER": 395, "WARRIOR": 384, "PALADIN": 402}),
    ("PVPEH", "PvP - Horde Epic", {
        "WARLOCK": 391, "PRIEST": 390, "MAGE": 387, "ROGUE": 393, "DRUID": 398,
        "HUNTER": 396, "WARRIOR": 383, "SHAMAN": 386}),
]

# Forever's own raid sets (ItemSet 2098-2115; not yet known to the live server on 2026-10-20,
# they show once it knows their pieces): group, class per set id from the set's name
FOREVER_TIER = {
    2098: "MAGE", 2099: "ROGUE", 2100: "WARLOCK", 2101: "HUNTER", 2102: "WARRIOR", 2103: "WARRIOR",
    2104: "PRIEST", 2105: "PRIEST", 2106: "PALADIN", 2107: "PALADIN", 2108: "PALADIN",
    2109: "SHAMAN", 2110: "SHAMAN", 2111: "SHAMAN", 2112: "DRUID", 2113: "DRUID", 2114: "DRUID", 2115: "DRUID",
}
# Every PvP class set of the table, old and Forever's spec versions; class from the pieces'
# AllowableClass, group from the rank in the name
PVP_SETS = list(range(281, 403)) + [522] + list(range(537, 552)) + list(range(2072, 2098))
PVP_GROUP = (("Lieutenant Commander's", "PVPRA"), ("Champion's", "PVPRH"),
             ("Field Marshal's", "PVPEA"), ("Warlord's", "PVPEH"))
# Forever's own dungeon and world armour sets: armour type from the pieces' item subclass
FOREVER_ARMOR = [1968, 1969, 1972, 2133, 2134, 2135, 2136]

# Armour sets any class of that armour type wears (ns.CLASS_ARMOR in Catalog.lua): armour type (1 cloth .. 4 plate), set id, source
ARMOR_SETS = [
    (1, 421, "Tailoring - Zul'Gurub"), (1, 520, "Dungeons"), (1, 122, "Scholomance"),
    (1, 81, "Stratholme"), (1, 492, "Silithus"), (1, 536, "Argent Dawn - Naxxramas"),
    (2, 442, "Leatherworking - Zul'Gurub"), (2, 441, "Leatherworking - Zul'Gurub"),
    (2, 121, "Scholomance"), (2, 142, "Leatherworking"), (2, 141, "Leatherworking"),
    (2, 143, "Leatherworking"), (2, 144, "Leatherworking"), (2, 534, "Argent Dawn - Naxxramas"),
    (2, 161, "The Deadmines"), (2, 162, "Wailing Caverns"), (2, 221, "Leatherworking"),
    (3, 443, "Leatherworking - Zul'Gurub"), (3, 123, "Scholomance"), (3, 489, "Leatherworking"),
    (3, 491, "Leatherworking"), (3, 1, "Blackrock Depths"), (3, 490, "Leatherworking"),
    (3, 163, "Scarlet Monastery"), (3, 535, "Argent Dawn - Naxxramas"),
    (4, 444, "Blacksmithing - Zul'Gurub"), (4, 124, "Scholomance"), (4, 321, "Blacksmithing"),
    (4, 533, "Argent Dawn - Naxxramas"),
]

# inventory type -> the wardrobe's slot key; neck, rings, trinkets, shirt and tabard change no look
SLOT = {1: "HEAD", 3: "SHOULDER", 16: "BACK", 5: "CHEST", 20: "CHEST", 9: "WRIST", 10: "HANDS",
        6: "WAIST", 7: "LEGS", 8: "FEET", 13: "MAIN", 17: "MAIN", 21: "MAIN", 14: "OFF", 22: "OFF", 23: "OFF"}


def newest(name):
    builds = sorted((p for p in CACHE.iterdir() if (p / name).exists()),
                    key=lambda p: [int(x) for x in p.name.split(".")], reverse=True)
    if not builds:
        raise SystemExit(f"{name} not cached: py -3 db2.py fetch {name[:-4]}")
    return builds[0] / name


def rows(name):
    with open(newest(name), encoding="utf-8") as f:
        yield from csv.DictReader(f)


def lua(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    sets = {int(r["ID"]): r for r in rows("ItemSet.csv")}
    inv = {int(r["ID"]): int(r["InventoryType"] or 0) for r in rows("Item.csv")}
    armor_of = {int(r["ID"]): int(r["SubclassID"] or 0) for r in rows("Item.csv") if r["ClassID"] == "4"}
    allow = {int(r["ID"]): int(r["AllowableClass"] or -1) for r in rows("ItemSparse.csv")}
    looks = set(int(m) for m in re.findall(r"^\[(\d+)\]=", (HERE.parent / "Looks.lua").read_text(encoding="utf-8"), re.M))

    def pieces(set_id):
        r = sets[set_id]
        out = {}
        for i in range(17):
            item = int(r[f"ItemID_{i}"])
            slot = SLOT.get(inv.get(item, 0))
            if item and slot and item in looks and slot not in out:
                out[slot] = item
        return out

    problems = []

    def check(set_id, cls):
        # the game says which class may wear a piece, where the item table has it
        for item in pieces(set_id).values():
            mask = allow.get(item, -1)
            if mask not in (-1, 0, 32767) and not mask & CLASS_BIT[cls]:
                problems.append(f"set {set_id} piece {item}: class mask {mask} has no {cls}")

    build = newest("ItemSet.csv").parent.name
    out = [f"-- Generated by tools/sets.py from the game's ItemSet table, build {build}. Do not edit.",
           "-- groups: { key, name }; sets: { setID, class or false, group key or armour type, name, source, { SLOT = itemID } }",
           "local _, ns = ...",
           "ns.SET_GROUPS = {"]
    out += [f"    {{ {lua(key)}, {lua(label)} }}," for key, label, _ in CLASS_SETS]
    out.append("}")
    out.append("ns.SETS = {")
    count = 0
    for key, label, per_class in CLASS_SETS:
        for cls in CLASSES:
            set_id = per_class.get(cls)
            if not set_id:
                continue
            p = pieces(set_id)
            if len(p) < 2:
                problems.append(f"set {set_id} has {len(p)} pieces with a look")
                continue
            check(set_id, cls)
            body = ", ".join(f"{s} = {i}" for s, i in sorted(p.items()))
            out.append(f"    {{ {set_id}, {lua(cls)}, {lua(key)}, {lua(sets[set_id]['Name_lang'])}, {lua(label)}, {{ {body} }} }},")
            count += 1
    written = {s for _, _, per in CLASS_SETS for s in per.values()}
    for set_id, cls in FOREVER_TIER.items():
        p = pieces(set_id)
        if len(p) < 2:
            continue
        body = ", ".join(f"{s} = {i}" for s, i in sorted(p.items()))
        out.append(f"    {{ {set_id}, {lua(cls)}, \"FT\", {lua(sets[set_id]['Name_lang'])}, \"Forever raid set\", {{ {body} }} }},")
        count += 1
    labels = dict((k, l) for k, l, _ in CLASS_SETS)
    for set_id in PVP_SETS:
        if set_id in written or set_id not in sets:
            continue
        name = sets[set_id]["Name_lang"]
        group = next((g for prefix, g in PVP_GROUP if name.startswith(prefix)), None)
        p = pieces(set_id)
        masks = {allow.get(i, -1) for i in p.values()} - {-1, 0, 32767}
        classes = [c for c in CLASSES if any(m & CLASS_BIT[c] for m in masks)]
        if not group or len(p) < 2 or len(classes) != 1:
            continue
        body = ", ".join(f"{s} = {i}" for s, i in sorted(p.items()))
        out.append(f"    {{ {set_id}, {lua(classes[0])}, {lua(group)}, {lua(name)}, {lua(labels[group])}, {{ {body} }} }},")
        count += 1
    extra = [(None, set_id, "") for set_id in FOREVER_ARMOR]
    for armor, set_id, source in ARMOR_SETS + extra:
        if armor is None:
            kinds = [armor_of.get(i) for i in pieces(set_id).values() if armor_of.get(i) in (1, 2, 3, 4)]
            if not kinds:
                continue
            armor = max(set(kinds), key=kinds.count)
        p = pieces(set_id)
        if len(p) < 2:
            problems.append(f"armour set {set_id} has {len(p)} pieces with a look")
            continue
        body = ", ".join(f"{s} = {i}" for s, i in sorted(p.items()))
        out.append(f"    {{ {set_id}, false, {armor}, {lua(sets[set_id]['Name_lang'])}, {lua(source)}, {{ {body} }} }},")
        count += 1
    out.append("}")
    (HERE.parent / "Sets.lua").write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
    print(f"build {build}: {count} sets written")
    for p in problems:
        print("CHECK:", p)


if __name__ == "__main__":
    main()
