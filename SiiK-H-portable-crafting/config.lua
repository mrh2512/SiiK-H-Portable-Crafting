Config = {}

Config.Debug = false
Config.TargetResource = 'qb-target'


-- Inventory integration
-- Supported: 'qb' (qb-inventory v2+), 'qs' (qs-inventory / Quasar)
Config.Inventory = 'qb'

-- ItemBox notify events (set to false to disable)
Config.ItemBoxEvents = {
    qb = 'qb-inventory:client:ItemBox', -- qb-inventory v2.x
    qs = 'qs-inventory:client:ItemBox', -- if your qs-inventory uses a different event, change it here
}

-- Anti-dupe / limits
Config.TablesPerPlayer = 2

Config.Placement = {
    ConfirmHoldMs = 500,      -- Hold E for 0.5s to confirm placement
    MaxDistance = 6.0,        -- How far in front you can place
    AllowRotation = true,     -- Rotate with RIGHT ARROW
    RotationStep = 5.0,
}

Config.Tables = {
    items = {
        label = 'Portable Crafting Table',
        item = 'portable_crafting_table',
        prop = 'xm3_prop_xm3_bench_04b',
        icon = 'fa-solid fa-hammer',
    },
    weapons = {
        label = 'Portable Weapons Bench',
        item = 'portable_weapon_bench',
        prop = 'gr_prop_gr_bench_01b',
        icon = 'fa-solid fa-gun',
    }
}

Config.XP = {
    StartLevel = 1,
    StartXP = 0,

    XPToNextLevel = function(level)
        return 250 + ((level - 1) * 125)
    end,

    MaxLevel = 100,
}

Config.Crafting = {
    MaxCraftAmount = 50,
    CraftTimeMs = 1500,          -- default if recipe doesn't set timeMs
    MinWeaponTimeMs = 6000,      -- minimum time for weapon recipes
    MaxInteractDistance = 2.8,   -- cancel craft if player moves away
    CraftRateLimitMs = 600,      -- anti spam
    PlaceRateLimitMs = 1500,
    PickupRateLimitMs = 1000,
}
