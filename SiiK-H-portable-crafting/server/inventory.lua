local QBCore = exports['qb-core']:GetCoreObject()

local Inventory = {}

local function invType()
    return (Config and Config.Inventory) or 'qb'
end

local function itemBoxEvent()
    if not Config or not Config.ItemBoxEvents then return nil end
    return Config.ItemBoxEvents[invType()]
end

function Inventory.ItemBox(src, itemName, action, amount)
    local ev = itemBoxEvent()
    if not ev then return end

    local itemData = (QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[itemName]) or { name = itemName, label = itemName }
    TriggerClientEvent(ev, src, itemData, action, amount or 1)
end

function Inventory.GetItemAmount(src, itemName)
    if invType() == 'qs' then
        return exports['qs-inventory']:GetItemTotalAmount(src, itemName) or 0
    end
    -- qb-inventory v2+ has GetItemCount(source, items)
    local ok, count = pcall(function()
        return exports['qb-inventory']:GetItemCount(src, itemName)
    end)
    if ok and type(count) == 'number' then return count end

    -- fallback (should still work on qb-core)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return 0 end
    local item = Player.Functions.GetItemByName(itemName)
    return (item and item.amount) or 0
end

function Inventory.HasItem(src, itemName, amount)
    amount = amount or 1
    if invType() == 'qs' then
        return (Inventory.GetItemAmount(src, itemName) or 0) >= amount
    end
    local ok, has = pcall(function()
        return exports['qb-inventory']:HasItem(src, itemName, amount)
    end)
    if ok then return has == true end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    local item = Player.Functions.GetItemByName(itemName)
    return (item and item.amount or 0) >= amount
end

function Inventory.CanCarryItem(src, itemName, amount)
    amount = amount or 1
    if invType() == 'qs' then
        return exports['qs-inventory']:CanCarryItem(src, itemName, amount) == true
    end
    local ok, can = pcall(function()
        return exports['qb-inventory']:CanAddItem(src, itemName, amount)
    end)
    if ok then return can == true end
    return true -- fallback: let AddItem handle it
end

function Inventory.AddItem(src, itemName, amount, info, slot)
    amount = amount or 1
    if invType() == 'qs' then
        -- signature: AddItem(source, item, count, slot?, metadata?)
        return exports['qs-inventory']:AddItem(src, itemName, amount, slot or nil, info or nil) == true
    end
    -- qb-inventory v2 signature: AddItem(identifier, item, amount, slot, info, reason)
    local ok, res = pcall(function()
        return exports['qb-inventory']:AddItem(src, itemName, amount, slot or false, info or false, 'portable-crafting')
    end)
    if ok then return res == true end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    local added = Player.Functions.AddItem(itemName, amount, slot or false, info)
    return added ~= false
end

function Inventory.RemoveItem(src, itemName, amount, slot, info)
    amount = amount or 1
    if invType() == 'qs' then
        -- signature: RemoveItem(source, item, count, slot?, metadata?)
        return exports['qs-inventory']:RemoveItem(src, itemName, amount, slot or nil, info or nil) == true
    end
    local ok, res = pcall(function()
        return exports['qb-inventory']:RemoveItem(src, itemName, amount, slot or false, 'portable-crafting')
    end)
    if ok then return res == true end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    return Player.Functions.RemoveItem(itemName, amount, slot or false) == true
end

function Inventory.CreateUsableItem(itemName, cb)
    if invType() == 'qs' then
        -- Quasar supports CreateUsableItem export
        local ok = pcall(function()
            exports['qs-inventory']:CreateUsableItem(itemName, function(source, item)
                cb(source, item)
            end)
        end)
        if ok then return end
    end

    -- Default QB way
    QBCore.Functions.CreateUseableItem(itemName, function(source, item)
        cb(source, item)
    end)
end

return Inventory
