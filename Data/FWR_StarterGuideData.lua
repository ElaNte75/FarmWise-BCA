local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

-- Starter guide: a few well-known farming suggestions for new users, until the Advisor has
-- farming data of their own. This is only data; Core/FWR_AdvisorStore.lua picks what fits the
-- character's professions. Edit this file when the game changes.
--
--   requires  professions the character needs, all of them (empty = any character):
--             herbalism, mining, skinning, tailoring, fishing
--   title     short heading
--   place     where to go
--   materials names of the materials gained (prices are shown when the Auction House was scanned;
--             every name needs its item IDs in STARTER_GUIDE.itemIds at the end of this file)
--   note      one short reason (keep it under about 65 characters)
--
-- Content: classic The Burning Crusade farming spots (Outland).

FWR.STARTER_GUIDE = {
    version = "TBC Anniversary, community guides",
    entries = {
        -- Herbalism + Mining
        {
            requires = { "herbalism", "mining" },
            title = "Herbs and ore together: Hellfire Peninsula",
            place = "Hellfire Peninsula, along the ridges and roads",
            materials = { "Fel Iron Ore", "Dreamfoil", "Mountain Silversage" },
            note = "The beginner choice: both on one loop, easy mobs.",
        },
        {
            requires = { "herbalism", "mining" },
            title = "Herbs and ore together: Zangarmarsh",
            place = "Zangarmarsh, around the lakes",
            materials = { "Fel Iron Ore", "Ragveil", "Dreaming Glory" },
            note = "Dense herbs around the water, ore on the edges.",
        },
        {
            requires = { "herbalism", "mining" },
            title = "Herbs and ore together: Nagrand",
            place = "Nagrand, the open plains",
            materials = { "Fel Iron Ore", "Adamantite Ore", "Dreaming Glory" },
            note = "Guides' favourite: rich in both, gentle terrain.",
        },

        -- Mining + Skinning / Herbalism + Skinning
        {
            requires = { "mining", "skinning" },
            title = "Ore and leather: Nagrand",
            place = "Nagrand, clefthoof herds and hills",
            materials = { "Knothide Leather", "Thick Clefthoof Leather", "Fel Iron Ore" },
            note = "Beasts and ore share the same loops.",
        },
        {
            requires = { "herbalism", "skinning" },
            title = "Herbs and leather: Terokkar",
            place = "Terokkar Forest, east of Shattrath",
            materials = { "Knothide Leather", "Terocone", "Dreaming Glory" },
            note = "Beasts by the rivers, herbs beside them.",
        },

        -- Herbalism
        {
            requires = { "herbalism" },
            title = "Zangarmarsh herbs",
            place = "Zangarmarsh, lake shores",
            materials = { "Ragveil", "Dreaming Glory", "Felweed" },
            note = "The most beginner-friendly herb zone.",
        },
        {
            requires = { "herbalism" },
            title = "Terokkar herbs",
            place = "Terokkar Forest",
            materials = { "Terocone", "Dreaming Glory", "Mana Thistle" },
            note = "Terocone sells well for flasks.",
        },
        {
            requires = { "herbalism" },
            title = "Netherstorm herbs",
            place = "Netherstorm, the purple fields",
            materials = { "Netherbloom", "Mana Thistle", "Felweed" },
            note = "Best zone for Mana Thistle.",
        },

        -- Mining
        {
            requires = { "mining" },
            title = "Nagrand ore",
            place = "Nagrand, around the edges",
            materials = { "Fel Iron Ore", "Adamantite Ore", "Mote of Earth" },
            note = "Often called the best mining zone.",
        },
        {
            requires = { "mining" },
            title = "Shadowmoon ore",
            place = "Shadowmoon Valley",
            materials = { "Adamantite Ore", "Khorium Ore", "Eternium Ore" },
            note = "Rich veins; watch the elite paths.",
        },
        {
            requires = { "mining" },
            title = "Netherstorm ore",
            place = "Netherstorm, along the crags",
            materials = { "Adamantite Ore", "Khorium Ore" },
            note = "Less crowded than Nagrand most hours.",
        },

        -- Skinning
        {
            requires = { "skinning" },
            title = "Clefthoof leather in Nagrand",
            place = "Nagrand, the plains herds",
            materials = { "Knothide Leather", "Thick Clefthoof Leather" },
            note = "Huge herds; the classic leather farm.",
        },
        {
            requires = { "skinning" },
            title = "Nether dragons in Netherstorm",
            place = "Netherstorm, Netherwing fields",
            materials = { "Nether Dragonscales", "Knothide Leather" },
            note = "Scales sell to leatherworkers.",
        },
        {
            requires = { "skinning" },
            title = "Fel boars in Hellfire",
            place = "Hellfire Peninsula, the boar fields",
            materials = { "Fel Scales", "Knothide Leather" },
            note = "Low level, always busy but simple.",
        },

        -- Tailoring
        {
            requires = { "tailoring" },
            title = "Netherweave from humanoids",
            place = "Nagrand and Terokkar humanoid camps",
            materials = { "Netherweave Cloth" },
            note = "Cloth only drops for tailors.",
        },
        {
            requires = { "tailoring" },
            title = "Sunfury cloth farming",
            place = "Netherstorm, Sunfury camps",
            materials = { "Netherweave Cloth" },
            note = "Dense packs of caster mobs.",
        },

        -- Fishing
        {
            requires = { "fishing" },
            title = "Zangarmarsh pools",
            place = "Zangarmarsh, the fishing pools",
            materials = { "Zangarian Sporefish", "Spotted Feltail" },
            note = "Easy pools; the fish sell for food buffs.",
        },
        {
            requires = { "fishing" },
            title = "Terokkar and Nagrand pools",
            place = "Terokkar rivers and Nagrand lakes",
            materials = { "Golden Darter", "Icefin Bluefish", "Figluster's Mudfish" },
            note = "Buff food fish; check Auction House prices.",
        },

        -- Any character
        {
            requires = {},
            title = "Motes and primals",
            place = "Elemental Plateau, Nagrand",
            materials = { "Mote of Fire", "Mote of Water", "Mote of Air" },
            note = "Elementals drop motes; ten motes make a primal.",
        },
        {
            requires = {},
            title = "Tradable gear drops",
            place = "Mobs in any Outland zone",
            materials = {},
            note = "Gear that drops can sell on the Auction House.",
        },
    },
}

-- Item IDs of the materials above (checked in the game). Prices are found by ID,
-- so the game never has to load item names.
FWR.STARTER_GUIDE.itemIds = {
    ["Adamantite Ore"] = { 23425 },
    ["Dreamfoil"] = { 13463 },
    ["Dreaming Glory"] = { 22786 },
    ["Eternium Ore"] = { 23427 },
    ["Fel Iron Ore"] = { 23424 },
    ["Fel Scales"] = { 25700 },
    ["Felweed"] = { 22785 },
    ["Figluster's Mudfish"] = { 27435 },
    ["Golden Darter"] = { 27438 },
    ["Icefin Bluefish"] = { 27437 },
    ["Khorium Ore"] = { 23426 },
    ["Knothide Leather"] = { 21887 },
    ["Mana Thistle"] = { 22793 },
    ["Mote of Air"] = { 22572 },
    ["Mote of Earth"] = { 22573 },
    ["Mote of Fire"] = { 22574 },
    ["Mote of Water"] = { 22578 },
    ["Mountain Silversage"] = { 13465 },
    ["Nether Dragonscales"] = { 29548 },
    ["Netherbloom"] = { 22791 },
    ["Netherweave Cloth"] = { 21877 },
    ["Ragveil"] = { 22787 },
    ["Spotted Feltail"] = { 27425 },
    ["Terocone"] = { 22789 },
    ["Thick Clefthoof Leather"] = { 23793 },
    ["Zangarian Sporefish"] = { 27516 },
}
