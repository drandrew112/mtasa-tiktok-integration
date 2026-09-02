--[[
    enemy_cars.lua  (server)
    ------------------------
    "Enemy car" - a car (with a driver) that continuously chases the target
    player and disappears after LIFETIME.

    Movement (speed/steering) runs client-side (like enemies.lua), because the
    server can't reliably drive a vehicle with AI.

    TikTok.spawnEnemyCar(player, name)
    TikTok.clearEnemyCars()

    Test:  /tiktokenemycar   /tiktokclearcars
]]

-- Models / names: shared/lists.lua
local CAR_MODELS   = TikTok.CAR_MODELS
local DRIVER_MODEL = TikTok.CAR_DRIVER_MODEL
local LIFETIME         = 2 * 60 * 1000
local MAX_CARS         = 4
local SPAWN_MIN        = 15
local SPAWN_MAX        = 30
local FALLBACK_ENEMIES = 3   -- when the car limit is full, spawn this many enemy peds instead

local cars = {}   -- [veh] = { target = player, driver = ped }

local function carCount()
    local n = 0
    for _ in pairs(cars) do n = n + 1 end
    return n
end

local function removeCar(veh)
    local c = cars[veh]
    cars[veh] = nil
    if c and isElement(c.target) then
        triggerClientEvent(c.target, "tiktok:enemyCarRemove", resourceRoot, veh)
    end
    if c and isElement(c.driver) then destroyElement(c.driver) end
    if isElement(veh) then destroyElement(veh) end
end

local function removeCarsOf(player)
    for veh, c in pairs(cars) do
        if c.target == player then removeCar(veh) end
    end
end

function TikTok.spawnEnemyCar(player, name)
    if not isElement(player) then return false end

    if carCount() >= MAX_CARS then
        -- car limit full -> spawn a few enemy peds instead
        if TikTok.spawnEnemies then
            TikTok.spawnEnemies(player, FALLBACK_ENEMIES, name)
        end
        return false
    end

    local px, py, pz = getElementPosition(player)
    local ang = math.random() * math.pi * 2
    local d   = math.random(SPAWN_MIN, SPAWN_MAX)

    local veh = createVehicle(CAR_MODELS[math.random(1, #CAR_MODELS)],
                              px + math.cos(ang) * d, py + math.sin(ang) * d, pz + 1)
    if not isElement(veh) then return false end
    setVehicleColor(veh, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    setVehicleDamageProof(veh, true)   -- don't blow up; only disappears at end of lifetime

    local driver = createPed(DRIVER_MODEL, px, py, pz)
    if isElement(driver) then
        warpPedIntoVehicle(driver, veh)
        -- the nametag lives on the DRIVER; nil/"" -> random name
        local drvName = (name ~= nil and name ~= "") and tostring(name) or TikTok.randomName()
        setElementData(driver, "name", drvName)
    end

    setElementSyncer(veh, player)
    if isElement(driver) then setElementSyncer(driver, player) end

    cars[veh] = { target = player, driver = driver }

    local theVeh, theTarget = veh, player
    setTimer(function()
        if isElement(theVeh) and isElement(theTarget) then
            triggerClientEvent(theTarget, "tiktok:enemyCarAdd", resourceRoot, theVeh)
        end
    end, 350, 1)

    setTimer(function()
        if isElement(theVeh) then removeCar(theVeh) end
    end, LIFETIME, 1)

    TikTok.log("spawnEnemyCar (%s) total %d", tostring(name or "?"), carCount())
    return true
end

function TikTok.clearEnemyCars()
    local n = carCount()
    for veh in pairs(cars) do
        removeCar(veh)
    end
    if n > 0 then TikTok.log("clearEnemyCars: %d", n) end
    return n
end

addEventHandler("onVehicleExplode", root, function()
    if cars[source] then removeCar(source) end
end)
addEventHandler("onPlayerWasted", root, function()
    removeCarsOf(source)
end)
addEventHandler("onPlayerQuit", root, function()
    removeCarsOf(source)
end)

-- ---------------------------------------------------------------------------
addCommandHandler("tiktokenemycar", function(player)
    local console = not isElement(player) or getElementType(player) ~= "player"
    local target  = TikTok.getTargetPlayer()
    if not isElement(target) then
        if console then outputServerLog("[tiktok] no target player") end
        return
    end
    TikTok.spawnEnemyCar(target)   -- nil -> random name
    if not console then outputChatBox("[tiktok] enemy car", player, 0, 255, 0) end
end)

addCommandHandler("tiktokclearcars", function(player)
    local n = TikTok.clearEnemyCars()
    local console = not isElement(player) or getElementType(player) ~= "player"
    local msg = ("[tiktok] %d enemy cars removed"):format(n)
    if console then outputServerLog(msg) else outputChatBox(msg, player, 0, 255, 0) end
end)
