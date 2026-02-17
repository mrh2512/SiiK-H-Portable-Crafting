local QBCore = exports['qb-core']:GetCoreObject()

local function xpToNext(level)
    local fn = Config.XP.XPToNextLevel
    if type(fn) == 'function' then return math.max(1, fn(level)) end
    return 250 + ((level - 1) * 125)
end

local XP = {}

function XP.EnsureRow(citizenid)
    MySQL.insert.await([[
        INSERT IGNORE INTO siik_portablecrafting_xp (citizenid, xp, level, crafts)
        VALUES (?, ?, ?, 0)
    ]], { citizenid, Config.XP.StartXP or 0, Config.XP.StartLevel or 1 })
end

function XP.Get(citizenid)
    XP.EnsureRow(citizenid)
    local row = MySQL.single.await('SELECT xp, level, crafts FROM siik_portablecrafting_xp WHERE citizenid = ?', { citizenid })
    if not row then return { xp = 0, level = 1, crafts = 0 } end
    return { xp = tonumber(row.xp) or 0, level = tonumber(row.level) or 1, crafts = tonumber(row.crafts) or 0 }
end

function XP.Add(citizenid, amount)
    XP.EnsureRow(citizenid)
    local data = XP.Get(citizenid)
    local xp = data.xp + (amount or 0)
    local level = data.level
    local leveledUp = false

    while true do
        if Config.XP.MaxLevel and level >= Config.XP.MaxLevel then break end
        local need = xpToNext(level)
        if xp >= need then
            xp = xp - need
            level = level + 1
            leveledUp = true
        else
            break
        end
    end

    if Config.XP.MaxLevel and level > Config.XP.MaxLevel then level = Config.XP.MaxLevel end

    MySQL.update.await('UPDATE siik_portablecrafting_xp SET xp=?, level=? WHERE citizenid=?', { xp, level, citizenid })
    return { xp = xp, level = level, leveledUp = leveledUp }
end

function XP.AddCraftCount(citizenid, count)
    XP.EnsureRow(citizenid)
    MySQL.update.await('UPDATE siik_portablecrafting_xp SET crafts = crafts + ? WHERE citizenid = ?', { count or 1, citizenid })
end

_G.SIIK_CRAFT_XP = XP
