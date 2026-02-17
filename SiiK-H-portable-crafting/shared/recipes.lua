Recipes = {}

Recipes.items = {
    {
        key = 'bandage',
        label = 'Bandage',
        amountOut = 1,
        timeMs = 1800,
        xp = 20,
        levelRequired = 1,
        category = 'Medical',
        ingredients = { ['plastic'] = 2 }
    },
    {
        key = 'lockpick',
        label = 'Lockpick',
        amountOut = 1,
        timeMs = 2500,
        xp = 35,
        levelRequired = 1,
        category = 'Tools',
        ingredients = { ['metalscrap'] = 10, ['plastic'] = 5 }
    },
    {
        key = 'repairkit',
        label = 'Repair Kit',
        amountOut = 1,
        timeMs = 4500,
        xp = 60,
        levelRequired = 1,
        category = 'Tools',
        ingredients = { ['metalscrap'] = 25, ['steel'] = 10, ['rubber'] = 10 }
    }
}

Recipes.weapons = {
    {
        key = 'weapon_knife',
        label = 'Knife',
        amountOut = 1,
        timeMs = 6500,
        xp = 120,
        levelRequired = 1,
        category = 'Melee',
        ingredients = { ['steel'] = 20, ['metalscrap'] = 15 }
    },
    {
        key = 'weapon_pistol',
        label = 'Pistol',
        amountOut = 1,
        timeMs = 9000,
        xp = 250,
        levelRequired = 1,
        category = 'Handguns',
        ingredients = { ['steel'] = 60, ['metalscrap'] = 80, ['plastic'] = 30 }
    }
}

Recipes.CategoryOrder = { 'Medical', 'Tools', 'Melee', 'Handguns' }
