local machines, objects, points = {}, {}, {}

local function clear(id)
    if points[id] then exports.mri_Qinteract:removeCoords(points[id]) points[id] = nil end
    if objects[id] and DoesEntityExist(objects[id]) then DeleteEntity(objects[id]) end
    objects[id] = nil
end

local function operate(id, operation)
    local value
    if operation == 'Add' then
        local input = lib.inputDialog('Adicionar dinheiro sujo', {
            { type = 'number', label = 'Quantidade', min = 1, max = Config.MaxDeposit, required = true, precision = 0 },
        })
        if not input then return end
        value = input[1]
    elseif operation == 'Password' then
        local input = lib.inputDialog('Senha da máquina', {
            { type = 'input', label = 'Nova senha (vazia remove o acesso compartilhado)', password = true, max = 32 },
        })
        if not input then return end
        value = input[1] or ''
    end
    local ok, message = lib.callback.await('mri_Qmoneywash:Action', false, id, operation, value)
    lib.notify({ description = message or (ok and 'Operação concluída.' or 'Não foi possível concluir a operação.'),
        type = ok and 'success' or 'error' })
end

local function information(id)
    local data = lib.callback.await('mri_Qmoneywash:Information', false, id)
    if not data then return end
    if data.Restricted then
        if not data.Locked then lib.notify({ description = 'Somente o proprietário tem acesso.', type = 'error' }) return end
        local input = lib.inputDialog('Acesso à máquina', { { type = 'input', label = 'Senha', password = true, required = true } })
        if not input then return end
        data = lib.callback.await('mri_Qmoneywash:Information', false, id, input[1])
        if not data or data.Restricted then lib.notify({ description = 'Senha incorreta.', type = 'error' }) return end
    end
    local function remaining(expiry)
        return ('%d min restantes'):format(math.max(0, math.ceil((expiry - data.Now) / 60)))
    end
    local options = {
        { title = ('Sujo: $%s | Lavado: $%s'):format(data.Money, data.Washed), disabled = true },
        { title = 'Adicionar dinheiro sujo', onSelect = function() operate(id, 'Add') end },
        { title = 'Retirar dinheiro sujo', onSelect = function() operate(id, 'Money') end },
        { title = 'Retirar dinheiro lavado', onSelect = function() operate(id, 'Washed') end },
        { title = 'Bateria', description = remaining(data.Timer), onSelect = function() operate(id, 'Battery') end },
        { title = 'Alvejante', description = remaining(data.Bleach), onSelect = function() operate(id, 'Bleach') end },
    }
    if data.Owner then
        options[#options + 1] = { title = 'Alterar senha', onSelect = function() operate(id, 'Password') end }
        options[#options + 1] = { title = 'Guardar máquina', onSelect = function() operate(id, 'StoreObjects') end }
    end
    lib.registerContext({ id = 'mri_moneywash', title = 'Lavagem de dinheiro', options = options })
    lib.showContext('mri_moneywash')
end

exports('UseMachine', function(data, slot)
    exports.ox_inventory:useItem(data, function(used)
        if not used then return end
        local result = lib.callback.await('mri_Qmoneywash:Place', false, used.slot or (type(slot) == 'table' and slot.slot) or slot)
        lib.notify({ description = result and 'Máquina instalada.' or 'Não foi possível instalar a máquina neste local.',
            type = result and 'success' or 'error' })
    end)
end)

local function sync()
    machines = lib.callback.await('mri_Qmoneywash:List', false) or {}
    for id in pairs(objects) do clear(id) end
end
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', sync)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    for id in pairs(objects) do clear(id) end
    machines = {}
end)
RegisterNetEvent('moneywash:Table', function(data)
    for id in pairs(objects) do clear(id) end
    machines = data
end)
RegisterNetEvent('moneywash:Update', function(id, data) machines[id] = data end)
RegisterNetEvent('moneywash:New', function(id, data) machines[id] = data end)
RegisterNetEvent('moneywash:Remove', function(id) clear(id) machines[id] = nil end)

CreateThread(function()
    sync()
    while true do
        local coords = GetEntityCoords(PlayerPedId())
        -- Consulta o bucket real do servidor, inclusive ao trocar de instância.
        local bucket = lib.callback.await('mri_Qmoneywash:Bucket', false)
        for id, machine in pairs(machines) do
            local c = machine.Coords
            if machine.Route == bucket and #(coords - vec3(c[1], c[2], c[3])) < 50 then
                if not objects[id] then
                    local hash = type(machine.Hash) == 'number' and machine.Hash or joaat(machine.Hash)
                    if IsModelInCdimage(hash) and IsModelValid(hash) then
                        local ok = pcall(lib.requestModel, hash, 5000)
                        if ok and machines[id] == machine then
                            local entity = CreateObjectNoOffset(hash, c[1], c[2], c[3], false, false, false)
                            SetEntityHeading(entity, c[4])
                            PlaceObjectOnGroundProperly(entity)
                            FreezeEntityPosition(entity, true)
                            objects[id] = entity
                            points[id] = exports.mri_Qinteract:addCoords(vec3(c[1], c[2], c[3] + 1.0), {
                                { name = 'moneywash_' .. id, label = 'Máquina de lavagem', icon = 'fas fa-money-bill',
                                    distance = 2.0, onSelect = function() information(id) end },
                            })
                            SetModelAsNoLongerNeeded(hash)
                        end
                    end
                end
            elseif objects[id] then clear(id) end
        end
        Wait(2000)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(objects) do clear(id) end
end)
