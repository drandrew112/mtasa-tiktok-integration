--[[
    enemy_car_ai.lua  (client)
    --------------------------
    The server (enemy_cars.lua) creates the car + driver and makes the local
    player the syncer. We drive the car toward the player here.

    Velocity vector toward the player, LERPed (more realistic accel/braking).
    Within FOLLOW_DIST the target speed is 0 -> it eases to a stop next to the player.

    Server -> client:  tiktok:enemyCarAdd (veh) / tiktok:enemyCarRemove (veh)
]]

local FOLLOW_DIST = 5        -- within this it stops trying to move closer
local TICK_MS     = 80
local SPEED_MIN   = 0.35     -- units / tick when close
local SPEED_MAX   = 2.6      -- units / tick when far (catch-up)
local ACCEL       = 0.09     -- 0..1  how fast it approaches target speed per tick (lower = more sluggish)
local TURN        = 0.18     -- 0..1  steering smoothing

local myCars = {}   -- [veh] = true
local carTimer
local carTick

local function stopIfEmpty()
    if next(myCars) == nil and isTimer(carTimer) then
        killTimer(carTimer)
        carTimer = nil
    end
end

local function addCar(veh, tries)
    if not isElement(veh) then
        tries = (tries or 0) + 1
        if tries <= 12 then setTimer(addCar, 200, 1, veh, tries) end
        return
    end
    myCars[veh] = true
    if not isTimer(carTimer) then
        carTimer = setTimer(carTick, TICK_MS, 0)
    end
end

carTick = function()
    if not isElement(localPlayer) then return end
    local px, py = getElementPosition(localPlayer)

    for veh in pairs(myCars) do
        if not isElement(veh) then
            myCars[veh] = nil
        else
            local vx, vy, vz = getElementPosition(veh)
            local dx, dy = px - vx, py - vy
            local dist = math.sqrt(dx * dx + dy * dy)
            local dirx, diry = 0, 0
            if dist > 0.001 then dirx, diry = dx / dist, dy / dist end

            -- target speed: 0 within FOLLOW_DIST (stop), otherwise grows with distance
            local desired = 0
            if dist > FOLLOW_DIST then
                desired = math.min(SPEED_MIN + (dist - FOLLOW_DIST) * 0.05, SPEED_MAX)
            end

            -- LERP the current horizontal velocity toward the target (accel / brake)
            local cvx, cvy, cvz = getElementVelocity(veh)
            local tvx, tvy = dirx * desired, diry * desired
            local nvx = cvx + (tvx - cvx) * ACCEL
            local nvy = cvy + (tvy - cvy) * ACCEL
            setElementVelocity(veh, nvx, nvy, cvz)

            -- turn toward the movement direction, smoothed (only while it wants to move)
            if desired > 0.05 then
                local _, _, curH = getElementRotation(veh)
                local wantH = math.deg(math.atan2(-dirx, diry)) % 360
                local dh = ((wantH - curH + 180) % 360) - 180
                setElementRotation(veh, 0, 0, (curH + dh * TURN) % 360)
            end
        end
    end

    stopIfEmpty()
end

addEvent("tiktok:enemyCarAdd", true)
addEventHandler("tiktok:enemyCarAdd", resourceRoot, function(veh)
    addCar(veh)
end)

addEvent("tiktok:enemyCarRemove", true)
addEventHandler("tiktok:enemyCarRemove", resourceRoot, function(veh)
    myCars[veh] = nil
    stopIfEmpty()
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    myCars = {}
end)
