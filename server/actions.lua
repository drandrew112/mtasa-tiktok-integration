--[[
    server/actions.lua
    ------------------
    Central ACTION registry. Every action this resource can perform lives here as

        TikTok.actions.<name> = function(ctx) ... end

    so the gift / like / follow handlers (and other resources) can all call the
    exact same set. Run one by name from anywhere:

        TikTok.runAction("act_dropVehicle", ctx)

    ctx is built by whichever handler fires the action; the fields an action may
    use are:
        ctx.player      - the affected player (TikTok.getTargetPlayer())
        ctx.senderName  - the TikTok user that triggered it (may be nil)
        ctx.test        - true when fired from a /tiktok* test command

    Tuning for the "train" actions (distance, vehicle / skin lists, speed) lives
    in shared/lists.lua : Tiktok.train
]]

TikTok = TikTok or {}
Tiktok = Tiktok or TikTok
TikTok.actions = TikTok.actions or {}

local A = TikTok.actions

-- ---------------------------------------------------------------------------
-- Tuning (moved here from gift_handler.lua / like_handler.lua)
-- ---------------------------------------------------------------------------
local BLACKHOLE_HEIGHT   = 250     -- units above the player
local BLACKHOLE_DURATION = 9000    -- ms
local BLACKHOLE_PULL     = 0.10    -- 0..1, how much it pulls per tick

local PLANE_IMPACT_DIST  = 22      -- units in front of the player

local SPAWN_AROUND_DIST    = 6      -- units from the player (act_spawnVehiclesAround)
local SPAWN_AROUND_CLEANUP = 120000 -- ms until removed (0 = keep)

local SMOKE_COUNT = 5

-- Data lists (shared/lists.lua)
local randomVehicleModel = TikTok.randomVehicleModel
local BLACKHOLE_MODELS   = TikTok.BLACKHOLE_MODELS
local PLANE_MODELS       = TikTok.PLANE_MODELS
local AIRPORTS           = TikTok.AIRPORTS

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function playerVehicle(player)
    local v = isElement(player) and getPedOccupiedVehicle(player)
    return isElement(v) and v or nil
end

-- Point `dist` units directly in front of an element (uses its Z rotation).
-- Returns x, y, z, rz.
local function frontPos(el, dist)
    local x, y, z = getElementPosition(el)
    local _, _, rz = getElementRotation(el)
    local r = math.rad(rz)
    return x - math.sin(r) * dist, y + math.cos(r) * dist, z, rz
end

local function trainCfg()
    return (Tiktok and Tiktok.train) or {}
end

-- ===========================================================================
--  GIFT ACTIONS  (were local in gift_handler.lua)
-- ===========================================================================

-- Replace the player's vehicle with a random one, seat them as driver.
-- If on foot, just spawns one at their position and puts them in it.
function A.act_replaceVehicle(ctx)
    local player = ctx.player
    if not isElement(player) then return end
    local px, py, pz = getElementPosition(player)
    local rz = 0

    local old = playerVehicle(player)
    if old then
        px, py, pz = getElementPosition(old)
        local _, _, orz = getElementRotation(old)
        rz = orz
        destroyElement(old)
    end

    local veh = createVehicle(randomVehicleModel(), px, py, pz + 1, 0, 0, rz)
    if isElement(veh) then
        warpPedIntoVehicle(player, veh)
    end
end

-- Drop a random vehicle 12 units above the player (obstacle). Auto-removed after 60s.
function A.act_dropVehicle(ctx)
    local player = ctx.player
    if not isElement(player) then return end
    local x, y, z = getElementPosition(player)
    local veh = createVehicle(randomVehicleModel(), x, y, z + 12, 0, 0, math.random(0, 359))
    if isElement(veh) then
        setTimer(function()
            if isElement(veh) then destroyElement(veh) end
        end, 60000, 1)
    end
end

-- Teleport the player's vehicle (or the player) 5 units up.
function A.act_liftVehicle(ctx)
    local el = playerVehicle(ctx.player) or ctx.player
    if not isElement(el) then return end
    local x, y, z = getElementPosition(el)
    setElementPosition(el, x, y, z + 5)
end

-- 1 chasing enemy ped (enemies.lua), named after the sender.
function A.act_spawnEnemy(ctx)
    TikTok.spawnEnemies(ctx.player, 1, ctx.senderName)
end

-- Chasing "enemy car" (enemy_cars.lua) - disappears after 2 minutes.
function A.act_spawnEnemyCar(ctx)
    TikTok.spawnEnemyCar(ctx.player, ctx.senderName)
end

-- Small plane dives in from a random direction and ALWAYS explodes in front of the player.
function A.act_planeCrash(ctx)
    local player = ctx.player
    if not isElement(player) then return end

    local px, py, pz = getElementPosition(player)
    local ref = playerVehicle(player) or player
    local _, _, heading = getElementRotation(ref)
    local hrad = math.rad(heading)

    -- impact point: fixed distance in front of the player (always explodes HERE)
    local ix = px - math.sin(hrad) * PLANE_IMPACT_DIST
    local iy = py + math.cos(hrad) * PLANE_IMPACT_DIST
    local iz = pz

    -- spawn: random direction, medium height, diving toward the point
    local approach = math.random() * math.pi * 2
    local sx = ix + math.cos(approach) * 70
    local sy = iy + math.sin(approach) * 70
    local sz = iz + 55

    local dirx, diry, dirz = ix - sx, iy - sy, iz - sz
    local len = math.sqrt(dirx * dirx + diry * diry + dirz * dirz)
    local yaw = math.deg(math.atan2(-dirx, diry)) % 360

    local plane = createVehicle(PLANE_MODELS[math.random(1, #PLANE_MODELS)], sx, sy, sz, 0, 0, yaw)
    if not isElement(plane) then return end
    setVehicleDamageProof(plane, true)
    setElementCollisionsEnabled(plane, false)   -- don't snag on buildings -> always reaches

    local speed = 2.0
    setElementVelocity(plane, dirx / len * speed, diry / len * speed, dirz / len * speed)
    pcall(setElementAngularVelocity, plane, 0, 0, 0.05)

    local ttl = math.max(500, (len / speed) * 20)
    setTimer(function()
        if isElement(plane) then destroyElement(plane) end
        -- always explodes at the impact point (small)
        createExplosion(ix, iy, iz, 2)
        createExplosion(ix, iy, iz + 1.5, 6)
    end, ttl, 1)
end

-- Teleport to a random airport (falls back to plane crash if AIRPORTS is empty).
function A.act_teleportAirport(ctx)
    local player = ctx.player
    if not isElement(player) then return end
    if #AIRPORTS == 0 then
        return A.act_planeCrash(ctx)
    end
    local a  = AIRPORTS[math.random(1, #AIRPORTS)]
    local el = playerVehicle(player) or player
    setElementPosition(el, a[1], a[2], a[3])
    if a[4] then setElementRotation(el, 0, 0, a[4]) end
    setElementVelocity(el, 0, 0, 0)
end

-- Black hole above the player: sucks up the vehicle (or the player) for
-- BLACKHOLE_DURATION, then explosion + death. Gravity is nulled client-side
-- (client/gift_effects.lua), position is pulled server-side.
function A.act_blackhole(ctx)
    local player = ctx.player
    if not isElement(player) then return end
    local px, py, pz = getElementPosition(player)
    local hx, hy, hz = px, py, pz + BLACKHOLE_HEIGHT

    local hole = createObject(BLACKHOLE_MODELS[math.random(1, #BLACKHOLE_MODELS)], hx, hy, hz)
    if not isElement(hole) then return end
    setElementCollisionsEnabled(hole, false)
    pcall(setObjectScale, hole, 3)  -- fine if the build can't scale objects server-side

    triggerClientEvent(player, "tiktok:blackholeStart", resourceRoot, BLACKHOLE_DURATION)

    local startTick = getTickCount()
    local spinTimer
    spinTimer = setTimer(function()
        if not isElement(hole) then
            if isTimer(spinTimer) then killTimer(spinTimer) end
            return
        end

        local elapsed = getTickCount() - startTick

        -- visual: spinning hole
        setElementRotation(hole, (elapsed * 0.20) % 360, (elapsed * 0.30) % 360, (elapsed * 0.50) % 360)

        -- pull the vehicle if the player is in one, otherwise the player
        local pull = playerVehicle(player) or player
        if isElement(pull) then
            local ex, ey, ez = getElementPosition(pull)
            local dx, dy, dz = hx - ex, hy - ey, hz - ez
            setElementPosition(pull, ex + dx * BLACKHOLE_PULL, ey + dy * BLACKHOLE_PULL, ez + dz * BLACKHOLE_PULL)
            setElementVelocity(pull, dx * 0.03, dy * 0.03, dz * 0.03)
        end

        if elapsed >= BLACKHOLE_DURATION then
            if isTimer(spinTimer) then killTimer(spinTimer) end
            if isElement(hole) then destroyElement(hole) end
            triggerClientEvent(player, "tiktok:blackholeEnd", resourceRoot)

            -- the player dies at the end
            if isElement(player) then
                local ex2, ey2, ez2 = getElementPosition(player)
                createExplosion(ex2, ey2, ez2, 10)
                killPed(player)
            end
        end
    end, 50, 0)
end

-- ===========================================================================
--  LIKE ACTIONS  (were local in like_handler.lua)
-- ===========================================================================

-- Launch the player's vehicle up; if they have no vehicle, kill them.
function A.act_launchVehicleOrKill(ctx)
    local player = ctx.player
    if not isElement(player) then return end

    local veh = playerVehicle(player)
    if veh then
        local vx, vy, vz = getElementVelocity(veh)
        setElementVelocity(veh, vx, vy, vz + 0.75)                     -- upward shove
        local rx, ry, rz = getElementRotation(veh)
        setElementRotation(veh, rx, ry, rz + math.random(-30, 30))     -- small spin for looks
    else
        killPed(player)
    end
end

-- 4 random vehicles around the player (N/S/E/W).
function A.act_spawnVehiclesAround(ctx)
    local player = ctx.player
    if not isElement(player) then return end

    local x, y, z = getElementPosition(player)
    local offsets = {
        {  SPAWN_AROUND_DIST, 0 },
        { -SPAWN_AROUND_DIST, 0 },
        { 0,  SPAWN_AROUND_DIST },
        { 0, -SPAWN_AROUND_DIST },
    }

    for _, o in ipairs(offsets) do
        local veh = createVehicle(randomVehicleModel(), x + o[1], y + o[2], z + 1, 0, 0, math.random(0, 359))
        if isElement(veh) and SPAWN_AROUND_CLEANUP > 0 then
            setTimer(function()
                if isElement(veh) then destroyElement(veh) end
            end, SPAWN_AROUND_CLEANUP, 1)
        end
    end
end

-- In a vehicle -> all 4 vehicle colors random. On foot -> random player skin.
function A.act_randomVehicleColor(ctx)
    local player = ctx.player
    if not isElement(player) then return end

    local veh = playerVehicle(player)
    if veh then
        local function c() return math.random(0, 255) end
        setVehicleColor(veh, c(), c(), c(),  c(), c(), c(),  c(), c(), c(),  c(), c(), c())
    else
        setElementModel(player, TikTok.randomSkin())
    end
end

-- Smoke / teargas grenades on the player (client does it - see client/gift_effects.lua).
function A.act_smokeGrenades(ctx)
    local player = ctx.player
    if not isElement(player) then return end
    triggerClientEvent(player, "tiktok:smokeGrenades", resourceRoot, SMOKE_COUNT)
end

-- In a vehicle -> the vehicle explodes. On foot -> kill the player.
function A.act_explodeVehicle(ctx)
    local veh = playerVehicle(ctx.player)
    if veh then
        blowVehicle(veh)
    elseif isElement(ctx.player) then
        killPed(ctx.player)
    end
end

-- ===========================================================================
--  TRAIN ACTIONS  (new - NOT wired to any event yet)
--  Drop obstacles a fixed distance in FRONT of the player's vehicle.
--  Step distance: Tiktok.train.distance (default 10). The _5 / _10 variants
--  place that many, each one `distance` further ahead than the last.
-- ===========================================================================

local function trainStep()
    local d = tonumber(trainCfg().distance) or 10
    return (d > 0) and d or 10
end

local function trainTTL()
    local t = tonumber(trainCfg().cleanup)
    return t or 30000
end

local function randomFromList(list)
    if type(list) == "table" and #list > 0 then
        return list[math.random(1, #list)]
    end
    return nil
end

local function randomAvgModel()
    return randomFromList(trainCfg().avg_vehicles) or randomVehicleModel()
end

local function randomHeavyModel()
    return randomFromList(trainCfg().heavy_vehicles) or 403   -- Linerunner
end

local function tankModel()
    return tonumber(trainCfg().tank) or 432   -- Rhino
end

local function randomTrainSkin()
    return randomFromList(trainCfg().skins) or (TikTok.randomSkin and TikTok.randomSkin()) or 0
end

-- Spawn `count` vehicles in a line ahead of the player's vehicle (or the player
-- on foot). modelFn() -> a model id per vehicle.
local function trainSpawnVehicles(ctx, count, modelFn)
    local player = ctx.player
    if not isElement(player) then return end
    local ref  = playerVehicle(player) or player
    local step = trainStep()
    local ttl  = trainTTL()
    count = tonumber(count) or 1

    for i = 1, count do
        local fx, fy, fz, rz = frontPos(ref, step * i)
        local veh = createVehicle(modelFn(), fx, fy, fz + 2, 0, 0, rz)
        if isElement(veh) and ttl > 0 then
            setTimer(function()
                if isElement(veh) then destroyElement(veh) end
            end, ttl, 1)
        end
    end
end

local function trainSpawnPeds(ctx, count)
    local player = ctx.player
    if not isElement(player) then return end
    local ref  = playerVehicle(player) or player
    local step = trainStep()
    local ttl  = trainTTL()
    count = tonumber(count) or 1

    for i = 1, count do
        local fx, fy, fz, rz = frontPos(ref, step * i)
        local ped = createPed(randomTrainSkin(), fx, fy, fz + 1, (rz + 180) % 360)
        if isElement(ped) then
            setElementFrozen(ped, false)
            if ttl > 0 then
                setTimer(function()
                    if isElement(ped) then destroyElement(ped) end
                end, ttl, 1)
            end
        end
    end
end

-- average sized vehicle(s) - Tiktok.train.avg_vehicles
function A.act_train_spawnVeh_Avg(ctx)    trainSpawnVehicles(ctx, 1,  randomAvgModel) end
function A.act_train_spawnVeh_Avg_5(ctx)  trainSpawnVehicles(ctx, 5,  randomAvgModel) end
function A.act_train_spawnVeh_Avg_10(ctx) trainSpawnVehicles(ctx, 10, randomAvgModel) end

-- heavy vehicle(s) - Tiktok.train.heavy_vehicles (no tank)
function A.act_train_spawnVeh_Heavy(ctx)    trainSpawnVehicles(ctx, 1,  randomHeavyModel) end
function A.act_train_spawnVeh_Heavy_5(ctx)  trainSpawnVehicles(ctx, 5,  randomHeavyModel) end
function A.act_train_spawnVeh_Heavy_10(ctx) trainSpawnVehicles(ctx, 10, randomHeavyModel) end

-- tank(s) - Tiktok.train.tank
function A.act_train_spawnVeh_Tank(ctx)   trainSpawnVehicles(ctx, 1, tankModel) end
function A.act_train_spawnVeh_Tank_5(ctx) trainSpawnVehicles(ctx, 5, tankModel) end

-- ped(s) - Tiktok.train.skins
function A.act_train_spawnPed(ctx)    trainSpawnPeds(ctx, 1)  end
function A.act_train_spawnPed_5(ctx)  trainSpawnPeds(ctx, 5)  end
function A.act_train_spawnPed_10(ctx) trainSpawnPeds(ctx, 10) end

-- ai_autoplayer: boost the auto-train speed, then restore it after a delay.
-- The ai_autoplayer exports are CLIENT side, so this is routed to the target
-- player's client (client/train_control.lua).
function A.act_train_speed_150(ctx)
    local player = ctx.player
    if not isElement(player) then return end
    local c = trainCfg()
    triggerClientEvent(player, "tiktok:trainAutoSpeed", resourceRoot,
        tonumber(c.speedBoost) or 150,
        tonumber(c.speedNormal) or 80,
        tonumber(c.speedBoostDuration) or 10000)
end

-- ai_autoplayer: reverse the train's forward direction relative to its current one.
function A.act_train_chgDirection(ctx)
    local player = ctx.player
    if not isElement(player) then return end
    local train = playerVehicle(player)
    if not isElement(train) or getVehicleType(train) ~= "Train" then return end
    -- getTrainDirection returns a boolean; train.lua in ai_autoplayer follows this flip.
    setTrainDirection(train, not getTrainDirection(train))
end

-- chaos
function A.act_train_chaos(ctx)
    local player = ctx.player
    if not isElement(player) then return end
    A.act_train_spawnPed_10(ctx)
    A.act_train_spawnVeh_Avg_5(ctx)
    setTimer(function()
        A.act_train_spawnVeh_Heavy_5(ctx)
        A.act_train_spawnVeh_Tank_5(ctx)
    end, 1000, 1)
    setTimer(function()
        A.act_train_spawnPed_10(ctx)
    end, 2000, 1)
    setTimer(function()
        A.act_train_chgDirection(ctx)
        A.act_train_speed_150(ctx)
    end, 3000, 1)
    setTimer(function()
        A.act_train_spawnVeh_Tank_5(ctx)
    end, 6000, 1)
end

-- ===========================================================================
--  Registry helpers
-- ===========================================================================

--- Resolve an action name to a registered one. The "act_" prefix may be omitted
--- (so "dropVehicle" and "train_chaos" both work).
-- @return string  the resolved key (may not exist if unknown)
function TikTok.resolveActionName(name)
    name = tostring(name or "")
    if type(TikTok.actions[name]) == "function" then return name end
    local prefixed = "act_" .. name
    if type(TikTok.actions[prefixed]) == "function" then return prefixed end
    return name
end

--- Run an action by name (prefix optional). `ctx` defaults to {}.
-- @return boolean  ok
function TikTok.runAction(name, ctx)
    local key = TikTok.resolveActionName(name)
    local fn  = TikTok.actions[key]
    if type(fn) ~= "function" then
        TikTok.log("runAction: unknown action '%s'", tostring(name))
        return false
    end
    local ok, err = pcall(fn, ctx or {})
    if not ok then
        outputServerLog("[tiktok] action error (" .. tostring(key) .. "): " .. tostring(err))
    end
    return ok
end

--- Sorted list of every registered action name.
-- @param short boolean|nil  strip the "act_" prefix
function TikTok.actionNames(short)
    local list = {}
    for k in pairs(TikTok.actions) do
        list[#list + 1] = short and (k:gsub("^act_", "")) or k
    end
    table.sort(list)
    return list
end

-- ---------------------------------------------------------------------------
-- Test command:  /tiktokaction <name>   (admin / console)
--   no argument -> list every action name
-- ---------------------------------------------------------------------------
local function isConsole(player)
    return not isElement(player) or getElementType(player) ~= "player"
end

local function tell(player, msg, r, g, b)
    if isConsole(player) then outputServerLog(msg)
    else outputChatBox(msg, player, r or 255, g or 255, b or 255) end
end

local function isAllowed(player)
    if isConsole(player) then return true end
    local acc = getPlayerAccount(player)
    if not acc or isGuestAccount(acc) then return false end
    local g = aclGetGroup("Admin")
    return (g and isObjectInACLGroup("user." .. getAccountName(acc), g)) or false
end

addCommandHandler("tiktokaction", function(player, _, name)
    if not isAllowed(player) then
        tell(player, "You are not allowed to use this command.", 255, 80, 80)
        return
    end
    if not name then
        tell(player, "Actions (the act_ prefix is optional): "
            .. table.concat(TikTok.actionNames(true), ", "), 255, 200, 0)
        tell(player, "Usage: /tiktokaction <name>   e.g. /tiktokaction train_chaos", 255, 200, 0)
        return
    end
    local ctx = {
        player     = TikTok.getTargetPlayer(),
        senderName = (isElement(player) and getPlayerName(player)) or TikTok.randomName(),
        test       = true,
    }
    if not isElement(ctx.player) then
        tell(player, "[tiktok] no target player online.", 255, 80, 80)
        return
    end
    local key = TikTok.resolveActionName(name)
    local ok  = TikTok.runAction(name, ctx)
    tell(player, ok and ("[tiktok] action '" .. key .. "' fired.")
                     or ("[tiktok] action '" .. name .. "' unknown / failed."),
         ok and 0 or 255, ok and 255 or 80, 80)
end)
