--[[
    spawn_timers.lua  (server)
    --------------------------
    Periodic "rewards" for the target player:
      - every 10 min: a tank (Rhino) -> seats them, deletes their old vehicle
      - every  5 min: an enemy wave -> 3 sub-waves 5s apart, 5 enemies per sub-wave

    The remaining time is drawn by client/hud_timers.lua.
]]

local VEHICLE_EVERY = 10 * 60 * 1000   -- 10 min (ms)
local ENEMY_EVERY   = 5  * 60 * 1000   -- 5 min  (ms)

local VEHICLE_MODEL = 432   -- Rhino (tank)

-- enemy wave: ENEMY_WAVES sub-waves, ENEMY_WAVE_GAP apart, ENEMY_PER_WAVE enemies each
local ENEMY_WAVES    = 3
local ENEMY_PER_WAVE = 5
local ENEMY_WAVE_GAP = 5000   -- ms

local nextVehicle = getTickCount() + VEHICLE_EVERY
local nextEnemy   = getTickCount() + ENEMY_EVERY

local function broadcast(toWho)
    local now = getTickCount()
    triggerClientEvent(toWho or root, "tiktok:spawnTimers", resourceRoot,
        math.max(0, nextVehicle - now), math.max(0, nextEnemy - now))
end

local function giveVehicle()
    nextVehicle = getTickCount() + VEHICLE_EVERY

    local p = TikTok.getTargetPlayer()
    if isElement(p) then
        local old = getPedOccupiedVehicle(p)
        local x, y, z = getElementPosition(p)
        local rz = 0
        if isElement(old) then
            x, y, z = getElementPosition(old)
            local _, _, orz = getElementRotation(old)
            rz = orz
        end
        local veh = createVehicle(VEHICLE_MODEL, x, y, z + 1, 0, 0, rz)
        if isElement(veh) then
            warpPedIntoVehicle(p, veh)
            if isElement(old) then destroyElement(old) end
            TikTok.notify("Tank", "10 minute reward")
        end
    end

    broadcast()
end

local function spawnWave()
    local p = TikTok.getTargetPlayer()
    if not isElement(p) then return end
    for _ = 1, ENEMY_PER_WAVE do
        TikTok.spawnEnemies(p, 1)   -- nil -> random name
    end
end

local function giveEnemies()
    nextEnemy = getTickCount() + ENEMY_EVERY

    if isElement(TikTok.getTargetPlayer()) then
        for w = 0, ENEMY_WAVES - 1 do
            setTimer(spawnWave, w * ENEMY_WAVE_GAP + 50, 1)
        end
        TikTok.notify("Enemy wave", ENEMY_WAVES .. " x " .. ENEMY_PER_WAVE .. " enemies")
    end

    broadcast()
end

setTimer(giveVehicle, VEHICLE_EVERY, 0)
setTimer(giveEnemies, ENEMY_EVERY, 0)
setTimer(broadcast, 30000, 0)   -- safety re-send for the HUD

-- client asks for the current state on connect
addEvent("tiktok:spawnTimersReq", true)
addEventHandler("tiktok:spawnTimersReq", root, function()
    if client then broadcast(client) end
end)
