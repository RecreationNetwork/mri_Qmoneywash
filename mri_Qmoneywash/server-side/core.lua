local machines = json.decode(GetResourceKvpString('machines') or '{}') or {}
local sessions, busy = {}, {}

local function save()
    SetResourceKvp('machines', json.encode(machines))
end

local function public(machine)
    local data = {}
    for key, value in pairs(machine) do if key ~= 'Password' then data[key] = value end end
    data.Locked = machine.Password ~= nil
    return data
end

local function snapshot()
    local result = {}
    for id, machine in pairs(machines) do result[id] = public(machine) end
    return result
end

local function update(id)
    save()
    TriggerClientEvent('moneywash:Update', -1, id, public(machines[id]))
end

local function nearby(source, machine)
    local ped = GetPlayerPed(source)
    if ped == 0 or GetPlayerRoutingBucket(source) ~= machine.Route then return false end
    local c = machine.Coords
    return #(GetEntityCoords(ped) - vec3(c[1], c[2], c[3])) <= Config.InteractionDistance
end

local function access(source, id)
    if type(id) ~= 'string' then return end
    local p = exports.qbx_core:GetPlayer(source)
    local machine = machines[id]
    if not p or not machine or not nearby(source, machine) then return end
    local citizenid = p.PlayerData.citizenid
    if machine.Passport ~= citizenid and not (sessions[source] and sessions[source][id]) then return end
    return machine, citizenid
end

lib.callback.register('mri_Qmoneywash:List', function() return snapshot() end)
lib.callback.register('mri_Qmoneywash:Bucket', function(source) return GetPlayerRoutingBucket(source) end)

lib.callback.register('mri_Qmoneywash:Information', function(source, id, password)
    if type(id) ~= 'string' then return false end
    local machine = machines[id]
    local p = exports.qbx_core:GetPlayer(source)
    if not p or not machine or not nearby(source, machine) then return false end
    local owner = machine.Passport == p.PlayerData.citizenid
    if not owner and not (sessions[source] and sessions[source][id]) then
        if not machine.Password or type(password) ~= 'string' or password ~= machine.Password then
            return { Restricted = true, Locked = machine.Password ~= nil }
        end
        sessions[source] = sessions[source] or {}
        sessions[source][id] = true
    end
    local data = public(machine)
    data.Owner, data.Now = owner, os.time()
    return data
end)

local function create(citizenid, item, hash, coords, route)
    local id
    repeat id = ('%08x%04x'):format(os.time(), math.random(0, 65535)) until not machines[id]
    machines[id] = { Passport = citizenid, Item = item, Hash = hash, Coords = coords, Route = route,
        Money = 0, Washed = 0, Timer = 0, Bleach = 0, Last = 0 }
    update(id)
    return id
end

lib.callback.register('mri_Qmoneywash:Place', function(source, slot)
    if type(slot) ~= 'number' or slot % 1 ~= 0 then return false end
    local p = exports.qbx_core:GetPlayer(source)
    if not p then return false end
    local count = 0
    for _, machine in pairs(machines) do if machine.Passport == p.PlayerData.citizenid then count = count + 1 end end
    if count >= Config.MaxMachinesPerPlayer then return false end
    local item = exports.ox_inventory:GetSlot(source, slot)
    local ped = GetPlayerPed(source)
    if not item or item.name ~= Config.MachineItem or ped == 0 or GetVehiclePedIsIn(ped, false) ~= 0 then return false end
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local angle = math.rad(heading)
    local position = { coords.x - math.sin(angle) * 1.2, coords.y + math.cos(angle) * 1.2, coords.z - 1.0, heading }
    for _, machine in pairs(machines) do
        if machine.Route == GetPlayerRoutingBucket(source) then
            local c = machine.Coords
            if #(vec3(position[1], position[2], position[3]) - vec3(c[1], c[2], c[3])) < 1.5 then return false end
        end
    end
    if not exports.ox_inventory:RemoveItem(source, Config.MachineItem, 1, nil, slot) then return false end
    return create(p.PlayerData.citizenid, Config.MachineItem, Config.MachineModel, position, GetPlayerRoutingBucket(source))
end)

local function action(source, id, operation, value)
    local machine, citizenid = access(source, id)
    if not machine then return false, 'Sem acesso à máquina.' end
    local now = os.time()
    if operation == 'Add' then
        local amount = tonumber(value)
        if not amount or amount ~= amount or amount % 1 ~= 0 or amount < 1 or amount > Config.MaxDeposit then return false end
        if machine.Timer <= now then return false, 'Adicione uma bateria primeiro.' end
        if machine.Money + amount > Config.MaxDeposit then return false, 'Compartimento cheio.' end
        if not exports.ox_inventory:RemoveItem(source, Config.DirtyMoney, amount) then return false, 'Dinheiro sujo insuficiente.' end
        machine.Money = machine.Money + amount
    elseif operation == 'Money' then
        if machine.Money <= 0 then return false end
        if not exports.ox_inventory:AddItem(source, Config.DirtyMoney, machine.Money) then return false, 'Inventário sem espaço.' end
        machine.Money = 0
    elseif operation == 'Washed' then
        if machine.Washed <= 0 then return false end
        if not exports.qbx_core:AddMoney(source, Config.Account, machine.Washed, 'moneywash-withdraw') then return false end
        machine.Washed = 0
    elseif operation == 'Battery' or operation == 'Bleach' then
        local key = operation == 'Battery' and 'Timer' or 'Bleach'
        local item = operation == 'Battery' and Config.BatteryItem or Config.BleachItem
        local duration = operation == 'Battery' and Config.BatteryDuration or Config.BleachDuration
        if machine[key] > now then return false, 'Este insumo ainda está ativo.' end
        if not exports.ox_inventory:RemoveItem(source, item, 1) then return false, 'Você não possui o insumo necessário.' end
        machine[key] = now + duration
    elseif operation == 'Password' then
        if machine.Passport ~= citizenid or type(value) ~= 'string' or #value > 32 then return false end
        machine.Password = value ~= '' and value or nil
        for _, session in pairs(sessions) do session[id] = nil end
    elseif operation == 'StoreObjects' then
        if machine.Passport ~= citizenid then return false end
        if machine.Money > 0 or machine.Washed > 0 then return false, 'Esvazie os dois compartimentos primeiro.' end
        if not exports.ox_inventory:AddItem(source, machine.Item, 1) then return false, 'Inventário sem espaço.' end
        machines[id] = nil
        for _, session in pairs(sessions) do session[id] = nil end
        save()
        TriggerClientEvent('moneywash:Remove', -1, id)
        return true
    else
        return false
    end
    update(id)
    return true
end

lib.callback.register('mri_Qmoneywash:Action', function(source, id, operation, value)
    if type(id) ~= 'string' or busy[id] then return false end
    busy[id] = true
    local ok, result, message = pcall(action, source, id, operation, value)
    busy[id] = nil
    if not ok then print(('[mri_Qmoneywash] %s'):format(result)) return false end
    return result, message
end)

CreateThread(function()
    while true do
        Wait(Config.Interval * 1000)
        local now, changed = os.time(), false
        for id, machine in pairs(machines) do
            if not busy[id] and machine.Timer > now and machine.Bleach > now and machine.Money > 0 then
                local amount = math.min(machine.Money, math.max(1, math.floor(machine.Money * (Config.BaseEfficiency + Config.BleachPercentage))))
                machine.Money = machine.Money - amount
                machine.Washed = machine.Washed + amount
                machine.Last = now
                changed = true
                TriggerClientEvent('moneywash:Update', -1, id, public(machine))
            end
        end
        if changed then save() end
    end
end)

-- Integração exclusivamente servidor: os identificadores agora são citizenids Qbox.
exports('Wash', function(citizenid, item, hash, coords, route)
    if type(citizenid) ~= 'string' or item ~= Config.MachineItem or not coords then return false end
    return create(citizenid, item, hash or Config.MachineModel,
        { coords[1] or coords.x, coords[2] or coords.y, coords[3] or coords.z, coords[4] or coords.w or 0 }, route or 0)
end)
exports('UpdateObjects', function(oldCitizenid, newCitizenid)
    if type(newCitizenid) ~= 'string' then return false end
    for id, machine in pairs(machines) do
        if machine.Passport == oldCitizenid then machine.Passport = newCitizenid update(id) end
    end
    sessions = {}
    return true
end)

AddEventHandler('playerDropped', function() sessions[source] = nil end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(source) sessions[source] = nil end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then save() end
end)
