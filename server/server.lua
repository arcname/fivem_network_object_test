RegisterServerEvent('sutogura_networktest:server:ReceiveNetIds')
AddEventHandler('sutogura_networktest:server:ReceiveNetIds', function(netIds)
  if netIds then
    print("Start test: " .. tostring(source))
  else
    print("Stop test: "  .. tostring(source))
  end
  TriggerClientEvent("sutogura_networktest:client:ReceiveNetIds", -1, source, netIds)
end)


RegisterServerEvent('sutogura_networktest:server:NotifyError')
AddEventHandler('sutogura_networktest:server:NotifyError', function(errors)
  local src = source
  print("Received errors: ")
  for i = 1, #errors do
    print("==================================================")
    print(string.format("Player %d has error for entity with net ID %d: %s", src, errors[i][1], Messages[errors[i][2]]))
    print("==================================================")
  end
end)

RegisterServerEvent('sutogura_networktest:server:Message')
AddEventHandler('sutogura_networktest:server:Message', function(msg)
  local src = source
  print("==================================================")
  print(string.format("Player %d sent message: %s", src, msg))
  print("==================================================")
end)



local netTestOwner = nil
local netObjects = nil
local localObjects = nil

RegisterServerEvent('sutogura_networktest:server:StartNetTest')
AddEventHandler('sutogura_networktest:server:StartNetTest', function(pos, amount)
  local src = source

  if netTestOwner then
      print("Already running test")
      return
  end

  netObjects = {}
  localObjects = {}

  -- Create a bunch of network objects and give the netids to clients
  for i = 1, amount do
      local x = pos.x + ((i - 1) % 10) * 1.4
      local y = pos.y + math.floor((i - 1) / 10) * 1.4

      local obj = CreateObject(joaat("imp_prop_bomb_ball"), x, y, pos.z, true, true, true)

      local timeTaken = 0

      while obj ~= 0 and not DoesEntityExist(obj) do
        Wait(10)
        timeTaken = timeTaken + 10
        if timeTaken > 100 then
          print("Failed to confirm entity after 10s")
          break
        end
      end

      if DoesEntityExist(obj) then
        print("Milliseconds taken to confirm entity: ~" .. tostring(timeTaken))
        FreezeEntityPosition(obj, true)
        local netid = NetworkGetNetworkIdFromEntity(obj)

        local timeout = 50
        while netid == obj do
            netid = NetworkGetNetworkIdFromEntity(obj)

            Wait(10)
            timeout = timeout - 10
            if timeout <= 0 then
                print("Warning: failed to get net ID for entity: " .. tostring(obj))
                netid = -1
                break
            end
        end

        if netid > 0 then
            table.insert(netObjects, netid)
        end

      else
        print("Failed to create entity: invalid ID " .. tostring(obj))
      end

      localObjects[i] = obj
      Wait(100)
  end

  Wait(1000)
  print("Start test: server")
  netTestOwner = src
  TriggerEvent("sutogura_networktest:server:ReceiveNetIds", netObjects)
end)


RegisterServerEvent('sutogura_networktest:server:StopNetTest')
AddEventHandler('sutogura_networktest:server:StopNetTest', function()
  local src = source
  if not (netTestOwner and netTestOwner == src and netObjects) then
      print(tostring(GetGameTimer()) .. ": No tests are running")
      return
  end

  TriggerEvent("sutogura_networktest:server:ReceiveNetIds", nil)

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
              DeleteEntity(obj)
          end
      else
          table.insert(undeleted, localObjects[i])
      end
  end

  Wait(delay)

  for i = 1, #undeleted do
      local obj = undeleted[i]
      DeleteEntity(obj)
  end

  netObjects = nil
  localObjects = nil
  netTestOwner = nil
  print("Ending test")
end)