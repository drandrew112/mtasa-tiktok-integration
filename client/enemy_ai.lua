--[[
    enemy_ai.lua  (client)
    ----------------------
    The server (enemies.lua) creates the peds and makes the local player the
    syncer. The AI runs here (setPedControlState is client-only).

    - every tick the ped turns toward the target (continuous tracking)
    - if the player is in a VEHICLE -> the vehicle is the target
    - within range: aim + fire (while moving too)
    - one gang model (server) -> they don't shoot each other

    Note: an MTA createPed ped does not enter combat mode on its own, so hits
    are not always reliable; the visuals + sound are there. (Precise damage:
    hitscan later.)

    Server -> client:  tiktok:enemyAdd (ped) / tiktok:enemyRemove (ped)
]]

local FOLLOW_DIST  = 3
local SHOOT_RANGE  = 25
local SPRINT_RANGE = 15
local TICK_MS      = 120
local UNSTUCK_AFTER = 6

local myEnemies = {}   -- [ped] = { stuck, last }
local aiTimer
local aiTick
local DEBUG = false

local function stopIfEmpty()
    if next(myEnemies) == nil and isTimer(aiTimer) then
        killTimer(aiTimer)
        aiTimer = nil
    end
end

local function releaseControls(ped)
    if not isElement(ped) then return end
    setPedControlState(ped, "forwards", false)
    setPedControlState(ped, "sprint", false)
    setPedControlState(ped, "aim_weapon", false)
    setPedControlState(ped, "fire", false)
end

local function addEnemy(ped, tries)
    if not isElement(ped) then
        tries = (tries or 0) + 1
        if tries <= 12 then setTimer(addEnemy, 200, 1, ped, tries) end
        return
    end
    myEnemies[ped] = { stuck = 0 }
    if not isTimer(aiTimer) then
        aiTimer = setTimer(aiTick, TICK_MS, 0)
    end
end

local function currentTarget()
    local veh = getPedOccupiedVehicle(localPlayer)
    if isElement(veh) then return veh end
    return localPlayer
end

aiTick = function()
    if not isElement(localPlayer) or isPedDead(localPlayer) then
        for ped in pairs(myEnemies) do releaseControls(ped) end
        return
    end

    local tgt = currentTarget()
    local tx, ty, tz = getElementPosition(tgt)

    for ped, s in pairs(myEnemies) do
        if not isElement(ped) or isPedDead(ped) then
            myEnemies[ped] = nil
        else
            local ex, ey, ez = getElementPosition(ped)
            local dx, dy = tx - ex, ty - ey
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist > 0.05 then
                setPedRotation(ped, math.deg(math.atan2(-dx, dy)) % 360, true)
            end

            local moving   = dist > FOLLOW_DIST + 0.6
            local shooting  = dist <= SHOOT_RANGE

            setPedControlState(ped, "forwards", moving)
            setPedControlState(ped, "sprint", moving and not shooting and dist > SPRINT_RANGE)
            setPedControlState(ped, "aim_weapon", shooting)
            setPedControlState(ped, "fire", shooting)          -- full-auto weapon -> continuous fire

            if DEBUG and (not s.dbg or getTickCount() - s.dbg > 1000) then
                s.dbg = getTickCount()
                outputChatBox(("[enemy] dist=%.1f move=%s shoot=%s"):format(dist, tostring(moving), tostring(shooting)))
            end

            if moving and s.last then
                local delta = getDistanceBetweenPoints3D(ex, ey, ez, s.last.x, s.last.y, s.last.z)
                if delta < 0.12 then
                    s.stuck = s.stuck + 1
                    if s.stuck >= UNSTUCK_AFTER then
                        setElementPosition(ped, ex + dx / dist * 1.4, ey + dy / dist * 1.4, ez)
                        s.stuck = 0
                    end
                else
                    s.stuck = 0
                end
            else
                s.stuck = 0
            end

            s.last = { x = ex, y = ey, z = ez }
        end
    end

    stopIfEmpty()
end

-- ---------------------------------------------------------------------------
addEvent("tiktok:enemyAdd", true)
addEventHandler("tiktok:enemyAdd", resourceRoot, function(ped)
    addEnemy(ped)
end)

addEvent("tiktok:enemyRemove", true)
addEventHandler("tiktok:enemyRemove", resourceRoot, function(ped)
    releaseControls(ped)
    myEnemies[ped] = nil
    stopIfEmpty()
end)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    for ped in pairs(myEnemies) do releaseControls(ped) end
    myEnemies = {}
    stopIfEmpty()
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for ped in pairs(myEnemies) do releaseControls(ped) end
end)

addCommandHandler("tiktokenemydebug", function()
    DEBUG = not DEBUG
    outputChatBox("[enemy] debug: " .. tostring(DEBUG))
end)
