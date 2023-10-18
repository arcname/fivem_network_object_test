local QBCore = exports['qb-core']:GetCoreObject()

local myTest = false
local netObjects = nil
local localObjects = nil
local othersObjects = {}

RegisterCommand('startnettest', function(src, args)
    TriggerServerEvent("sutogura_networktest:server:StartNetTest", GetEntityCoords(PlayerPedId()), args[1] or 10)
end)

RegisterCommand('stopnettest', function(src, args)
    TriggerServerEvent("sutogura_networktest:server:StopNetTest")
end)


local poolNames = { 'CObject', 'CPed' }
RegisterCommand('findnetobj', function(src, args)
    local cullRangeSq= ((args[1] and tonumber(args[1])) or 500)^2

    print("findnetobj: Start test with culling range of " .. tostring(math.sqrt(cullRangeSq)))

    for i=1, #poolNames do
        print("  " .. poolNames[i] .. ":")
        local pool = GetGamePool(poolNames[i])
        for j = 1, #pool do
            local obj = pool[j]
            local distSq = Vdist2(GetEntityCoords(obj))
            local netid = NetworkGetNetworkIdFromEntity(obj)
            if netid ~= obj and distSq > cullRangeSq then
                print(string.format("  Found object outside of range: %d | model: %s | networkID: %d | owner: %d | distance: %.2f",
                    obj,
                    GetEntityModel(obj),
                    netid,
                    NetworkGetEntityOwner(obj),
                    math.sqrt(distSq)
                    )
                )
            end
        end
        print("----")
    end

    print("findnetobj: Test complete")
end)

RegisterCommand('startobjtest', function(src, args)
    -- potential race condition but w/e it's a quick test and i'm the only one calling this
    if netObjects then
        print("Already running test! (use /stopobjtest to end it)")
        return
    end

    netObjects = {}
    localObjects = {}

    -- Create a bunch of network objects, try to get their net IDs, then pass the list to the server to be checked by other clients
    local ped = PlayerPedId()
    local fwd = GetEntityForwardVector(ped)
    local pos = GetEntityCoords(ped)

    local mainX = pos.x + fwd.x * 5
    local mainY = pos.y + fwd.y * 5

    if not HasModelLoaded("imp_prop_bomb_ball") then
        while not HasModelLoaded(joaat("imp_prop_bomb_ball")) do
            RequestModel(joaat("imp_prop_bomb_ball"))
            Wait(10)
        end
    end

    local amount = (args[1] and tonumber(args[1])) or 10
    local wait = (args[2] and tonumber(args[2])) or 1
    local getNetIdTimeout = (args[3] and tonumber(args[3])) or 10
    local isMissionObj = (args[4] and tonumber(args[4])) or 1

    if CanRegisterMissionObjects(amount) then
        print("CanRegisterMissionObjects succeeded for amount: " .. tostring(amount))
    else
        print("CanRegisterMissionObjects failed for amount: " .. tostring(amount))
    end

    for i = 1, amount do
        local x = mainX + ((i - 1) % 10) * 1.4
        local y = mainY + math.floor((i - 1) / 10) * 1.4

        local obj = CreateObject(joaat("imp_prop_bomb_ball"), x, y, pos.z, 1, isMissionObj, 0)
        FreezeEntityPosition(obj, true)
        SetEntityCollision(obj, false, false)
        local netid = NetworkGetNetworkIdFromEntity(obj)

        local timeout = getNetIdTimeout
        while netid == obj do
            NetworkRegisterEntityAsNetworked(obj)
            netid = NetworkGetNetworkIdFromEntity(obj)

            Wait(10)
            timeout = timeout - 10
            if timeout <= 0 then
                print("Warning: failed to get net ID for entity: " .. tostring(obj))
                SetEntityAlpha(obj, 154, true)
                SetEntityRenderScorched(obj, true)
                netid = -1
                break
            end
        end

        if netid > 0 then
            SetNetworkIdCanMigrate(netid, true)
            SetNetworkIdExistsOnAllMachines(netid, true)

            table.insert(netObjects, netid)
        end

        localObjects[i] = obj
        Wait(wait)
    end

    Wait(1000)
    print("Start test")
    myTest = true
    TriggerServerEvent("sutogura_networktest:server:ReceiveNetIds", netObjects)
end)
TriggerEvent("chat:addSuggestion", "/startobjtest", "[amount] [delayBetweenEach] [timeout] [isNetMissionEntity]")

RegisterCommand('stopobjtest', function(src, args)
    EndTest((args[1] and tonumber(args[1])) or 0)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    EndTest(0)
end)


CreateThread(function()
    local errors = {}

    while true do
        if othersObjects then
            local newErrors = {}

            for k, objects in pairs(othersObjects) do
                for i = 1, #objects do
                    local netid = objects[i]

                    if netid > 0 then
                        if not NetworkDoesNetworkIdExist(netid) then
                            if not errors[netid] then
                                errors[netid] = true
                                newErrors[#newErrors + 1] = { netid, 1 }
                            end
                        elseif not NetworkDoesEntityExistWithNetworkId(netid) then
                            if not errors[netid] then
                                errors[netid] = true
                                newErrors[#newErrors + 1] = { netid, 2 }
                            end
                        else
                            errors[netid]= nil
                        end
                    end
                end

                if #newErrors > 0 then
                    TriggerServerEvent("sutogura_networktest:server:NotifyError", newErrors)
                end
            end
        end

        Wait(20000)
    end
end)


function EndTest(delay)
    if not (myTest and netObjects) then
        print(tostring(GetGameTimer()) .. ": No tests are running")
        return
    end

    TriggerServerEvent("sutogura_networktest:server:ReceiveNetIds", nil)

    print("Cleaning up test")

    local errors = {}
    local undeleted = {}

    for i = 1, #localObjects do
        local netid = netObjects[i]
        local obj

        if netid and netid > 0 then
            obj = NetworkGetEntityFromNetworkId(netid)
            if obj <= 0 then
                errors[#errors+1] = { netid, 1 }
                table.insert(undeleted, localObjects[i])
            else
                SetEntityAsMissionEntity(obj, true, true)
                DeleteObject(obj)
                if DoesEntityExist(obj) then
                    print("Failed to delete " .. tostring(obj))
                    errors[#errors+1] = { netid, 3 }
                end
            end
        else
            table.insert(undeleted, localObjects[i])
        end
    end

    Wait(delay)

    for i = 1, #undeleted do
        local obj = undeleted[i]
        SetEntityAsMissionEntity(obj, true, true)
        DeleteObject(obj)
        if DoesEntityExist(obj) then
            print("Failed to delete " .. tostring(obj))
            errors[#errors+1] = { netid, 3 }
        end
    end

    netObjects = nil
    localObjects = nil
    myTest = false
    print("Ending test")

    if #errors > 0 then
        TriggerServerEvent("sutogura_networktest:server:NotifyError", errors)
    end
end

RegisterNetEvent('sutogura_networktest:client:ReceiveNetIds', function(src, netIds)
    othersObjects[tostring(src)] = netIds
    if othersObjects[tostring(src)] then
        TriggerServerEvent("sutogura_networktest:server:Message", string.format("Received %d netIDs", #othersObjects[tostring(src)]))
    end
end)