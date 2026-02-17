local QBCore = exports['qb-core']:GetCoreObject()
-- Module loader (FiveM doesn't support plain Lua require() for resource files)
local function LoadModule(relPath)
    local res = GetCurrentResourceName()
    local code = LoadResourceFile(res, relPath)
    if not code then
        error(('Failed to load module %s'):format(relPath))
    end
    local chunk, err = load(code, ('@@%s/%s'):format(res, relPath))
    if not chunk then
        error(err)
    end
    return chunk()
end

local Inventory = LoadModule('server/inventory.lua')
local XP = _G.SIIK_CRAFT_XP

local function dbg(...)
    if Config.Debug then
        print('[SiiK-H-portable-crafting][SERVER]', ...)
    end
end

-- Persistent tables keyed by dbId
local Tables = {}

-- Anti-dupe: placement state (server-authoritative)
local Placing = {} -- [src] = { tableType='items'|'weapons', startedAt=os.time() }

-- Busy lock / cancel
local BusyCrafting = {} -- [src] = { cancel=false, dbId=..., endAt=..., recipeKey=..., amount=..., token=..., craftTime=... }

-- Rate limits
local Rate = {} -- [src] = { craft=ms, place=ms, pickup=ms }

-- Weapon preview token cache
local WeaponPreviewCache = {} -- [src] = { token, expires, recipeKey, serials, amount }

local function tooFast(src, key, cooldownMs)
    Rate[src] = Rate[src] or {}
    local now = GetGameTimer()
    local last = Rate[src][key] or 0
    if (now - last) < cooldownMs then return true end
    Rate[src][key] = now
    return false
end

local function makeToken()
    return tostring(os.time()) .. '-' .. QBCore.Shared.RandomInt(6) .. QBCore.Shared.RandomStr(6)
end

local function makeSerial()
    return QBCore.Shared.RandomInt(2) .. QBCore.Shared.RandomStr(3) .. QBCore.Shared.RandomInt(1) .. QBCore.Shared.RandomStr(2) .. QBCore.Shared.RandomInt(3)
end

local function clearBusy(src)
    BusyCrafting[src] = nil
end

AddEventHandler('playerDropped', function()
    local src = source
    clearBusy(src)
    Placing[src] = nil
    WeaponPreviewCache[src] = nil
end)

RegisterNetEvent('SiiK-H-portable-crafting:server:CancelPlacement', function()
    Placing[source] = nil
end)

RegisterNetEvent('SiiK-H-portable-crafting:server:CancelCraft', function(reason)
    local src = source
    if BusyCrafting[src] then
        BusyCrafting[src].cancel = true
        BusyCrafting[src].cancelReason = reason or 'Canceled'
    end
end)

local function distance(a, b)
    local dx = (a.x - b.x)
    local dy = (a.y - b.y)
    local dz = (a.z - b.z)
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function isWeaponItem(itemName)
    return itemName and string.sub(itemName, 1, 7) == 'weapon_'
end

local function getRecipe(tableType, key)
    if not Recipes or not Recipes[tableType] then return nil end
    for _, r in ipairs(Recipes[tableType]) do
        if r.key == key then return r end
    end
    return nil
end

local function getCraftTimeMs(recipeKey, recipe)
    local t = (recipe and recipe.timeMs) or Config.Crafting.CraftTimeMs or 1500
    if recipeKey and string.sub(recipeKey, 1, 7) == 'weapon_' then
        t = math.max(t, Config.Crafting.MinWeaponTimeMs or 6000)
    end
    return t
end

local function hasIngredients(Player, recipe, amount)
    for item, count in pairs(recipe.ingredients or {}) do
        local need = (count or 0) * amount
        local have = Inventory.GetItemAmount(Player.PlayerData.source, item)
        if have < need then
            return false, item, need, have
        end
    end
    return true
end

local function takeIngredients(Player, recipe, amount)
    for item, count in pairs(recipe.ingredients or {}) do
        local need = (count or 0) * amount
        Inventory.RemoveItem(Player.PlayerData.source, item, need)
        Inventory.ItemBox(Player.PlayerData.source, item, 'remove', need)
    end
end

local function refundIngredients(Player, recipe, amount)
    for item, count in pairs(recipe.ingredients or {}) do
        local giveBack = (count or 0) * amount
        Inventory.AddItem(Player.PlayerData.source, item, giveBack)
        Inventory.ItemBox(Player.PlayerData.source, item, 'add', giveBack)
    end
end

local function canAddItem(Player, itemName, amount, info)
    return Inventory.AddItem(Player.PlayerData.source, itemName, amount, info)
end

local function giveOutput(Player, itemName, amount, previewToken)
    if isWeaponItem(itemName) then
        local src = Player.PlayerData.source
        local cache = WeaponPreviewCache[src]
        local serialsToUse = nil

        if cache and cache.token == previewToken and cache.recipeKey == itemName and cache.expires >= os.time() then
            serialsToUse = cache.serials
        end
        WeaponPreviewCache[src] = nil

        for i = 1, amount do
            local serial = (serialsToUse and serialsToUse[i]) or makeSerial()
            local info = { serial = serial }
            if not canAddItem(Player, itemName, 1, info) then
                return false
            end
            Inventory.ItemBox(src, itemName, 'add', 1)
        end
        return true
    else
        if not canAddItem(Player, itemName, amount) then return false end
        Inventory.ItemBox(Player.PlayerData.source, itemName, 'add', amount)
        return true
    end
end

-- Usable placement items (server-authoritative)
CreateThread(function()
    for t, data in pairs(Config.Tables) do
        Inventory.CreateUsableItem(data.item, function(source)
            local Player = QBCore.Functions.GetPlayer(source)
            if not Player then return end
            if not Inventory.HasItem(source, data.item, 1) then
                TriggerClientEvent('QBCore:Notify', source, 'You do not have that item.', 'error')
                return
            end

            if Placing[source] then
                TriggerClientEvent('QBCore:Notify', source, 'You are already placing a table.', 'error')
                return
            end

            Placing[source] = { tableType = t, startedAt = os.time() }
            TriggerClientEvent('SiiK-H-portable-crafting:client:PlaceTable', source, t)
        end)
    end
end)

-- Persistence: load tables on start and broadcast
CreateThread(function()
    Wait(750)
    local rows = MySQL.query.await('SELECT * FROM siik_portablecrafting_tables', {})
    if not rows then rows = {} end

    for _, r in ipairs(rows) do
        local dbId = tonumber(r.id)
        Tables[dbId] = {
            owner = r.owner_citizenid,
            type = r.table_type,
            coords = vector3(tonumber(r.x), tonumber(r.y), tonumber(r.z)),
            heading = tonumber(r.h) or 0.0,
            netId = nil
        }
    end

    TriggerClientEvent('SiiK-H-portable-crafting:client:SpawnSavedTables', -1, Tables)
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    TriggerClientEvent('SiiK-H-portable-crafting:client:SpawnSavedTables', src, Tables)
end)

-- Save placed table (ONLY if placement was initiated server-side)
RegisterNetEvent('SiiK-H-portable-crafting:server:RegisterTable', function(tableType, coords, heading)
    local src = source
    if tooFast(src, 'place', Config.Crafting.PlaceRateLimitMs or 1500) then return end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    if not Config.Tables[tableType] then return end
    if not coords or not coords.x then return end

    -- Must be in placing state
    if not Placing[src] or Placing[src].tableType ~= tableType then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid placement request.', 'error')
        return
    end
    Placing[src] = nil

    local citizenid = Player.PlayerData.citizenid

    -- Per-player limit
    local owned = 0
    for _, t in pairs(Tables) do
        if t.owner == citizenid then owned = owned + 1 end
    end
    if Config.TablesPerPlayer and owned >= Config.TablesPerPlayer then
        TriggerClientEvent('QBCore:Notify', src, 'You have reached your table limit.', 'error')
        return
    end

    -- Prevent stacking near other tables
    for _, t in pairs(Tables) do
        if t and t.coords then
            local d = #(vector3(coords.x, coords.y, coords.z) - t.coords)
            if d < 0.75 then
                TriggerClientEvent('QBCore:Notify', src, 'Too close to another table.', 'error')
                return
            end
        end
    end

    -- Remove the item ONLY now (confirmed placement)
    local itemName = Config.Tables[tableType].item
    if not Inventory.HasItem(src, itemName, 1) then
        TriggerClientEvent('QBCore:Notify', src, 'You do not have the table item.', 'error')
        return
    end

    local removed = Inventory.RemoveItem(src, itemName, 1)
    if not removed then
        TriggerClientEvent('QBCore:Notify', src, 'Failed to remove item.', 'error')
        return
    end
    Inventory.ItemBox(src, itemName, 'remove', 1)

    local h = tonumber(heading) or 0.0

    local insertId = MySQL.insert.await([[
        INSERT INTO siik_portablecrafting_tables (owner_citizenid, table_type, x, y, z, h)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { citizenid, tableType, coords.x, coords.y, coords.z, h })

    insertId = tonumber(insertId)
    if not insertId then
        -- refund item if db insert fails
        Inventory.AddItem(src, itemName, 1)
        Inventory.ItemBox(src, itemName, 'add', 1)
        TriggerClientEvent('QBCore:Notify', src, 'Failed to save crafting table.', 'error')
        return
    end

    Tables[insertId] = {
        owner = citizenid,
        type = tableType,
        coords = vector3(coords.x, coords.y, coords.z),
        heading = h,
        netId = nil
    }

    TriggerClientEvent('SiiK-H-portable-crafting:client:SpawnOneSavedTable', -1, insertId, Tables[insertId])
end)

RegisterNetEvent('SiiK-H-portable-crafting:server:SetTableNetId', function(dbId, netId)
    dbId = tonumber(dbId)
    netId = tonumber(netId)
    if not dbId or not netId then return end
    if not Tables[dbId] then return end
    Tables[dbId].netId = netId
end)

RegisterNetEvent('SiiK-H-portable-crafting:server:PickupTable', function(dbId)
    local src = source
    if tooFast(src, 'pickup', Config.Crafting.PickupRateLimitMs or 1000) then return end

    dbId = tonumber(dbId)
    if not dbId then return end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local entry = Tables[dbId]
    if not entry then return end

    if entry.owner ~= Player.PlayerData.citizenid then
        TriggerClientEvent('QBCore:Notify', src, 'This is not your table.', 'error')
        return
    end

    local tableType = entry.type
    local itemName = Config.Tables[tableType].item

    -- Delete from DB and memory
    MySQL.update.await('DELETE FROM siik_portablecrafting_tables WHERE id = ?', { dbId })
    Tables[dbId] = nil

    -- Give item back (if inventory full, drop it at feet as fallback)
    local ok = Inventory.AddItem(src, itemName, 1)
    if ok == false then
        TriggerClientEvent('QBCore:Notify', src, 'Inventory full, dropped on ground.', 'error')
        TriggerEvent('qb-log:server:CreateLog', 'default', 'PortableCrafting', 'red', ('%s pickup item dropped due to full inventory'):format(Player.PlayerData.citizenid))
        -- no generic drop handler here; still attempt to add
        Inventory.AddItem(src, itemName, 1)
    end
    Inventory.ItemBox(src, itemName, 'add', 1)

    TriggerClientEvent('SiiK-H-portable-crafting:client:RemoveSavedTable', -1, dbId)
end)

-- XP + counts callbacks
QBCore.Functions.CreateCallback('SiiK-H-portable-crafting:server:GetXP', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(nil) return end
    cb(XP.Get(Player.PlayerData.citizenid))
end)

QBCore.Functions.CreateCallback('SiiK-H-portable-crafting:server:GetIngredientCounts', function(source, cb, ingredients, craftAmount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({}) return end

    craftAmount = tonumber(craftAmount) or 1
    craftAmount = math.floor(craftAmount)
    if craftAmount < 1 then craftAmount = 1 end
    if craftAmount > Config.Crafting.MaxCraftAmount then craftAmount = Config.Crafting.MaxCraftAmount end

    local result = {}
    ingredients = ingredients or {}

    for item, perCraft in pairs(ingredients) do
        local have = Inventory.GetItemAmount(Player.PlayerData.source, item)
        local need = (tonumber(perCraft) or 0) * craftAmount
        result[item] = { have = have, need = need }
    end

    cb(result)
end)

QBCore.Functions.CreateCallback('SiiK-H-portable-crafting:server:GetWeaponPreview', function(source, cb, recipeKey, _amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(nil) return end

    if not recipeKey or string.sub(recipeKey, 1, 7) ~= 'weapon_' then
        cb(nil); return
    end

    local token = makeToken()
    local serials = { makeSerial() } -- weapons craft 1 at a time

    WeaponPreviewCache[source] = {
        token = token,
        expires = os.time() + 90,
        recipeKey = recipeKey,
        serials = serials,
        amount = 1
    }

    cb({ token = token, serials = serials })
end)

RegisterNetEvent('SiiK-H-portable-crafting:server:Craft', function(dbId, recipeKey, amount, previewToken)
    local src = source
    if tooFast(src, 'craft', Config.Crafting.CraftRateLimitMs or 600) then return end

    dbId = tonumber(dbId)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if BusyCrafting[src] then
        TriggerClientEvent('QBCore:Notify', src, 'You are already crafting.', 'error')
        return
    end

    amount = tonumber(amount) or 1
    amount = math.floor(amount)
    if amount < 1 then amount = 1 end
    if amount > Config.Crafting.MaxCraftAmount then amount = Config.Crafting.MaxCraftAmount end

    -- Hard cap weapons to 1 craft per action
    if recipeKey and string.sub(recipeKey, 1, 7) == 'weapon_' then
        amount = 1
    end

    local entry = Tables[dbId]
    if not entry then
        TriggerClientEvent('QBCore:Notify', src, 'Crafting table not found.', 'error')
        return
    end

    local tableType = entry.type
    local recipe = getRecipe(tableType, recipeKey)
    if not recipe then
        TriggerClientEvent('QBCore:Notify', src, 'Recipe not found.', 'error')
        return
    end

    local xpData = XP.Get(Player.PlayerData.citizenid)
    if (xpData.level or 1) < (recipe.levelRequired or 1) then
        TriggerClientEvent('QBCore:Notify', src, ('Level %d required.'):format(recipe.levelRequired or 1), 'error')
        return
    end

    local ok, missingItem, need, have = hasIngredients(Player, recipe, amount)
    if not ok then
        TriggerClientEvent('QBCore:Notify', src, ('Missing %s (%d/%d)'):format(missingItem, have, need), 'error')
        return
    end

    local craftTime = getCraftTimeMs(recipeKey, recipe)
    local endAt = GetGameTimer() + craftTime

    BusyCrafting[src] = {
        cancel = false,
        dbId = dbId,
        endAt = endAt,
        recipeKey = recipeKey,
        amount = amount,
        token = previewToken,
        craftTime = craftTime,
    }

    TriggerClientEvent('SiiK-H-portable-crafting:client:CraftingStarted', src, {
        dbId = dbId,
        craftTime = craftTime,
        maxDistance = Config.Crafting.MaxInteractDistance or 2.8
    })

    -- Cancel if moved away / flagged / etc.
    while BusyCrafting[src] and GetGameTimer() < endAt do
        if BusyCrafting[src].cancel then
            local reason = BusyCrafting[src].cancelReason or 'Canceled'
            clearBusy(src)
            TriggerClientEvent('SiiK-H-portable-crafting:client:CraftingCanceled', src, reason)
            TriggerClientEvent('QBCore:Notify', src, ('Craft canceled: %s'):format(reason), 'error')
            return
        end

        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local p = GetEntityCoords(ped)
            if distance(p, entry.coords) > (Config.Crafting.MaxInteractDistance or 2.8) then
                clearBusy(src)
                TriggerClientEvent('SiiK-H-portable-crafting:client:CraftingCanceled', src, 'Moved away')
                TriggerClientEvent('QBCore:Notify', src, 'Craft canceled: you moved away.', 'error')
                return
            end
        end

        Wait(250)
    end

    -- Re-check
    Player = QBCore.Functions.GetPlayer(src)
    if not Player then clearBusy(src) return end

    entry = Tables[dbId]
    if not entry then
        clearBusy(src)
        TriggerClientEvent('QBCore:Notify', src, 'Crafting table no longer exists.', 'error')
        TriggerClientEvent('SiiK-H-portable-crafting:client:CraftingCanceled', src, 'Table removed')
        return
    end

    local ok2 = hasIngredients(Player, recipe, amount)
    if not ok2 then
        clearBusy(src)
        TriggerClientEvent('QBCore:Notify', src, 'Craft canceled (missing items).', 'error')
        TriggerClientEvent('SiiK-H-portable-crafting:client:CraftingCanceled', src, 'Missing items')
        return
    end

    takeIngredients(Player, recipe, amount)

    -- Final output amount
    local outCount = (recipe.amountOut or 1) * amount
    -- Safety: weapons output exactly 1
    if recipeKey and string.sub(recipeKey, 1, 7) == 'weapon_' then
        outCount = 1
    end

    local success = giveOutput(Player, recipe.key, outCount, previewToken)
    if not success then
        -- refund ingredients if output failed (inventory full)
        refundIngredients(Player, recipe, amount)
        clearBusy(src)
        TriggerClientEvent('QBCore:Notify', src, 'Inventory full (craft refunded).', 'error')
        TriggerClientEvent('SiiK-H-portable-crafting:client:CraftingCanceled', src, 'Inventory full')
        return
    end

    XP.AddCraftCount(Player.PlayerData.citizenid, amount)
    local gained = (recipe.xp or 0) * amount
    local res = XP.Add(Player.PlayerData.citizenid, gained)

    TriggerClientEvent('SiiK-H-portable-crafting:client:CraftResult', src, {
        gained = gained,
        level = res.level,
        xp = res.xp,
        leveledUp = res.leveledUp
    })

    clearBusy(src)
    dbg('Craft', src, recipe.key, 'x', amount, 'xp+', gained)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    TriggerClientEvent('SiiK-H-portable-crafting:client:CleanupAll', -1)
end)
