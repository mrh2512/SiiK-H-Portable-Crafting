local QBCore = exports['qb-core']:GetCoreObject()

local function dbg(...)
    if Config.Debug then
        print('[SiiK-H-portable-crafting][CLIENT]', ...)
    end
end

-- Placed tables keyed by dbId:
-- Placed[dbId] = { entity=ent, type='items'|'weapons', owner=citizenid, heading=number }
local Placed = {}

local nuiOpen = false

-- Craft cancel monitor
local craftingActive = false
local craftingDbId = nil
local craftingMaxDist = 2.8
local startHealth = nil
local craftCancelSent = false

local function cancelCraft(reason)
    if craftCancelSent then return end
    craftCancelSent = true
    TriggerServerEvent('SiiK-H-portable-crafting:server:CancelCraft', reason or 'Canceled')
end

local function xpToNext(level)
    local fn = Config.XP.XPToNextLevel
    if type(fn) == 'function' then
        return math.max(1, fn(level))
    end
    return 250 + ((level - 1) * 125)
end

local function ensureModel(model)
    local hash = joaat(model)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(0) end
    return true
end

local function rotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function raycastFromCamera(dist)
    local camRot = GetGameplayCamRot(2)
    local camPos = GetGameplayCamCoord()
    local dir = rotationToDirection(camRot)
    local dest = camPos + (dir * dist)

    local handle = StartShapeTestRay(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, -1, PlayerPedId(), 0)
    local _, hit, endCoords, _, entityHit = GetShapeTestResult(handle)
    return hit == 1, endCoords, entityHit
end

local function DrawText2D(msg)
    SetTextFont(4)
    SetTextScale(0.45, 0.45)
    SetTextColour(255, 255, 255, 215)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayText(0.5, 0.92)
end

local function addTargetForEntity(entity, dbId, tableType, ownerCid)
    if not entity or entity == 0 then return end

    local label = Config.Tables[tableType].label or 'Crafting'
    local icon = Config.Tables[tableType].icon or 'fa-solid fa-hammer'

    exports[Config.TargetResource]:AddTargetEntity(entity, {
        options = {
            {
                icon = icon,
                label = ('Open %s'):format(label),
                action = function()
                    TriggerEvent('SiiK-H-portable-crafting:client:OpenCraftMenu', dbId)
                end
            },
            {
                icon = 'fa-solid fa-box',
                label = 'Pick Up (Owner Only)',
                action = function()
                    TriggerServerEvent('SiiK-H-portable-crafting:server:PickupTable', dbId)
                end,
                canInteract = function()
                    local pdata = QBCore.Functions.GetPlayerData()
                    return pdata and pdata.citizenid and pdata.citizenid == ownerCid
                end
            }
        },
        distance = 2.0,
    })
end

local function removeTargetForEntity(entity)
    if not entity or entity == 0 then return end
    exports[Config.TargetResource]:RemoveTargetEntity(entity)
end

local function spawnTableEntity(dbId, data)
    if not data or not data.coords then return end
    if Placed[dbId] and Placed[dbId].entity and DoesEntityExist(Placed[dbId].entity) then
        return
    end

    local t = Config.Tables[data.type]
    if not t then return end

    if not ensureModel(t.prop) then return end

    local ent = CreateObject(joaat(t.prop), data.coords.x, data.coords.y, data.coords.z - 1.0, true, true, false)
    SetEntityHeading(ent, data.heading or 0.0)
    FreezeEntityPosition(ent, true)

    local netId = NetworkGetNetworkIdFromEntity(ent)
    SetNetworkIdCanMigrate(netId, true)

    Placed[dbId] = {
        entity = ent,
        type = data.type,
        owner = data.owner,
        heading = data.heading or 0.0,
    }

    addTargetForEntity(ent, dbId, data.type, data.owner)
    TriggerServerEvent('SiiK-H-portable-crafting:server:SetTableNetId', dbId, netId)
end

RegisterNetEvent('SiiK-H-portable-crafting:client:SpawnSavedTables', function(all)
    if not all then return end
    for id, data in pairs(all) do
        spawnTableEntity(tonumber(id), data)
    end
end)

RegisterNetEvent('SiiK-H-portable-crafting:client:SpawnOneSavedTable', function(dbId, data)
    spawnTableEntity(tonumber(dbId), data)
end)

RegisterNetEvent('SiiK-H-portable-crafting:client:RemoveSavedTable', function(dbId)
    dbId = tonumber(dbId)
    local entry = Placed[dbId]
    if entry and entry.entity and DoesEntityExist(entry.entity) then
        removeTargetForEntity(entry.entity)
        DeleteEntity(entry.entity)
    end
    Placed[dbId] = nil
end)

local function SendBlueprintUI(dbId, entry, xpData)
    local cats = {}
    local byCat = {}

    for _, r in ipairs(Recipes[entry.type] or {}) do
        local cat = r.category or 'Other'
        byCat[cat] = byCat[cat] or {}

        local recipeTime = r.timeMs or Config.Crafting.CraftTimeMs
        if string.sub(r.key, 1, 7) == 'weapon_' then
            recipeTime = math.max(recipeTime, Config.Crafting.MinWeaponTimeMs or 6000)
        end

        table.insert(byCat[cat], {
            key = r.key,
            label = r.label or r.key,
            amountOut = r.amountOut or 1,
            timeMs = recipeTime,
            xp = r.xp or 0,
            levelRequired = r.levelRequired or 1,
            ingredients = r.ingredients or {},
        })
    end

    if Recipes.CategoryOrder then
        for _, c in ipairs(Recipes.CategoryOrder) do
            if byCat[c] then table.insert(cats, c) end
        end
        for c, _ in pairs(byCat) do
            local found = false
            for _, oc in ipairs(cats) do if oc == c then found = true break end end
            if not found then table.insert(cats, c) end
        end
    else
        for c, _ in pairs(byCat) do table.insert(cats, c) end
        table.sort(cats)
    end

    nuiOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    SendNUIMessage({
        action = 'open',
        dbId = dbId,
        tableType = entry.type,
        tableLabel = Config.Tables[entry.type].label or 'Blueprint Workbench',
        level = xpData.level or 1,
        xp = xpData.xp or 0,
        xpNext = xpToNext(xpData.level or 1),
        categories = cats,
        recipesByCat = byCat
    })
end

RegisterNetEvent('SiiK-H-portable-crafting:client:OpenCraftMenu', function(dbId)
    dbId = tonumber(dbId)
    local entry = Placed[dbId]
    if not entry then
        QBCore.Functions.Notify('Crafting table not found.', 'error')
        return
    end

    QBCore.Functions.TriggerCallback('SiiK-H-portable-crafting:server:GetXP', function(xpData)
        xpData = xpData or { xp = 0, level = 1, crafts = 0 }
        SendBlueprintUI(dbId, entry, xpData)
    end)
end)

-- NUI callbacks
RegisterNUICallback('close', function(_, cb)
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    cb({ ok = true })
end)

RegisterNUICallback('getCounts', function(data, cb)
    local ingredients = data and data.ingredients or {}
    local craftAmount = data and data.amount or 1

    QBCore.Functions.TriggerCallback('SiiK-H-portable-crafting:server:GetIngredientCounts', function(counts)
        cb({ ok = true, counts = counts or {} })
    end, ingredients, craftAmount)
end)

RegisterNUICallback('weaponPreview', function(data, cb)
    local recipeKey = data and data.recipeKey
    QBCore.Functions.TriggerCallback('SiiK-H-portable-crafting:server:GetWeaponPreview', function(res)
        cb({ ok = true, preview = res })
    end, recipeKey, 1)
end)

RegisterNUICallback('craft', function(data, cb)
    if not data or not data.dbId or not data.recipeKey then
        cb({ ok = false })
        return
    end

    local amt = tonumber(data.amount) or 1
    amt = math.floor(amt)
    if amt < 1 then amt = 1 end
    if amt > Config.Crafting.MaxCraftAmount then amt = Config.Crafting.MaxCraftAmount end

    TriggerServerEvent('SiiK-H-portable-crafting:server:Craft', tonumber(data.dbId), tostring(data.recipeKey), amt, data.previewToken)
    cb({ ok = true })
end)

RegisterNetEvent('SiiK-H-portable-crafting:client:CraftResult', function(res)
    if not res then return end

    -- stop local monitor
    craftingActive = false
    craftingDbId = nil
    startHealth = nil
    craftCancelSent = false

    if res.leveledUp then
        QBCore.Functions.Notify(('Craft XP +%d | Level Up! Now Level %d'):format(res.gained or 0, res.level or 1), 'success')
    else
        QBCore.Functions.Notify(('Craft XP +%d'):format(res.gained or 0), 'success')
    end

    if nuiOpen then
        SendNUIMessage({
            action = 'updateStats',
            level = res.level or 1,
            xp = res.xp or 0,
            xpNext = xpToNext(res.level or 1),
        })
    end
end)

RegisterNetEvent('SiiK-H-portable-crafting:client:CraftingStarted', function(data)
    craftingActive = true
    craftingDbId = data.dbId
    craftingMaxDist = data.maxDistance or (Config.Crafting.MaxInteractDistance or 2.8)
    startHealth = GetEntityHealth(PlayerPedId())
    craftCancelSent = false

    CreateThread(function()
        while craftingActive do
            Wait(150)
            local ped = PlayerPedId()
            if not ped or ped == 0 then
                cancelCraft('Player invalid')
                break
            end

            local hp = GetEntityHealth(ped)
            if startHealth and hp < startHealth then
                cancelCraft('Took damage')
                break
            end

            local entry = Placed[craftingDbId]
            if entry and entry.entity and DoesEntityExist(entry.entity) then
                local p = GetEntityCoords(ped)
                local t = GetEntityCoords(entry.entity)
                local dist = #(p - t)
                if dist > craftingMaxDist then
                    cancelCraft('Moved away')
                    break
                end
            end

            if IsEntityDead(ped) or IsPedRagdoll(ped) then
                cancelCraft('Interrupted')
                break
            end
        end
    end)
end)

RegisterNetEvent('SiiK-H-portable-crafting:client:CraftingCanceled', function(reason)
    craftingActive = false
    craftingDbId = nil
    startHealth = nil
    craftCancelSent = false

    SendNUIMessage({ action = 'craftCanceled', reason = reason or 'Canceled' })
end)

-- Placement
RegisterNetEvent('SiiK-H-portable-crafting:client:PlaceTable', function(tableType)
    local t = Config.Tables[tableType]
    if not t then return end

    local ped = PlayerPedId()

    if not ensureModel(t.prop) then
        QBCore.Functions.Notify('Prop model missing.', 'error')
        return
    end

    -- remove item immediately (server)
    
    local obj = CreateObject(joaat(t.prop), GetEntityCoords(ped), false, false, false)
    SetEntityAlpha(obj, 180, false)
    SetEntityCollision(obj, false, false)
    FreezeEntityPosition(obj, true)

    local heading = GetEntityHeading(ped)
    local holdStart = nil
    local placing = true

    while placing do
        Wait(0)

        local hit, pos = raycastFromCamera(Config.Placement.MaxDistance)
        if hit and pos then
            SetEntityCoords(obj, pos.x, pos.y, pos.z - 1.0, false, false, false, false)
        end

        if Config.Placement.AllowRotation then
            if IsControlPressed(0, 175) then -- RIGHT ARROW
                heading = heading + Config.Placement.RotationStep
            end
        end
        SetEntityHeading(obj, heading)

        DrawText2D(('Place %s | Hold [E] %.1fs to confirm | [X] cancel | [→] rotate'):format(
            t.label, (Config.Placement.ConfirmHoldMs / 1000.0)
        ))

        -- Cancel (X)
        if IsControlJustPressed(0, 73) then
            placing = false
            DeleteEntity(obj)
            TriggerServerEvent('SiiK-H-portable-crafting:server:CancelPlacement')
            return
        end

        -- Hold E (51 or 38) to confirm
        if IsControlPressed(0, 51) or IsControlPressed(0, 38) then
            if not holdStart then holdStart = GetGameTimer() end
            local held = GetGameTimer() - holdStart
            local pct = math.min(1.0, held / Config.Placement.ConfirmHoldMs)
            DrawText2D(('Confirming... %d%%'):format(math.floor(pct * 100)))

            if held >= Config.Placement.ConfirmHoldMs then
                placing = false
            end
        else
            holdStart = nil
        end
    end

    -- Finalize: save to server, then delete preview object (server will broadcast real one by dbId)
    local c = GetEntityCoords(obj)
    local h = GetEntityHeading(obj)
    DeleteEntity(obj)

    TriggerServerEvent('SiiK-H-portable-crafting:server:RegisterTable', tableType, { x = c.x, y = c.y, z = c.z }, h)

    QBCore.Functions.Notify(('Placed: %s'):format(t.label), 'success')
end)

RegisterNetEvent('SiiK-H-portable-crafting:client:CleanupAll', function()
    for dbId, entry in pairs(Placed) do
        if entry.entity and DoesEntityExist(entry.entity) then
            removeTargetForEntity(entry.entity)
            DeleteEntity(entry.entity)
        end
        Placed[dbId] = nil
    end
    nuiOpen = false
    SetNuiFocus(false, false)
end)
