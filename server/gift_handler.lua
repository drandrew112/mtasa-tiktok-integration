--[[
    gift_handler.lua
    ----------------
    Incoming TikTok gift -> a SPECIFIC action based on the gift TYPE.
    No categories, no random routing. Each action has its own gift (see GIFT_ACTIONS).

    Actions are `function(ctx)`. The affected player is ctx.player
    (the TARGET_PLAYER_NAME player - the streamer - NOT the gift sender).

    Test command:  /tiktokgift <gift_name>     e.g. /tiktokgift rose
                   /tiktokgiftall              runs every mapped gift once
]]

-- Target player: TikTok.getTargetPlayer() / TikTok.TARGET_PLAYER_NAME (config.lua)
local getTargetPlayer     = TikTok.getTargetPlayer
local TARGET_PLAYER_NAME  = TikTok.TARGET_PLAYER_NAME

-- Data lists live in shared/lists.lua
local randomVehicleModel = TikTok.randomVehicleModel
local BLACKHOLE_MODELS   = TikTok.BLACKHOLE_MODELS
local PLANE_MODELS       = TikTok.PLANE_MODELS
local AIRPORTS           = TikTok.AIRPORTS

-- Black hole tuning
local BLACKHOLE_HEIGHT   = 250     -- units above the player
local BLACKHOLE_DURATION = 9000    -- ms
local BLACKHOLE_PULL     = 0.10    -- 0..1, how much it pulls per tick

-- Plane crash tuning
local PLANE_IMPACT_DIST  = 22      -- units in front of the player

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function playerVehicle(player)
    local v = getPedOccupiedVehicle(player)
    return isElement(v) and v or nil
end

-- ---------------------------------------------------------------------------
-- Actions  (all: function(ctx))
-- ---------------------------------------------------------------------------

-- Replace the player's vehicle with a random one, seat them as driver.
-- If on foot, just spawns one at their position and puts them in it.
local function act_replaceVehicle(ctx)
    local player = ctx.player
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
local function act_dropVehicle(ctx)
    local player = ctx.player
    local x, y, z = getElementPosition(player)
    local veh = createVehicle(randomVehicleModel(), x, y, z + 12, 0, 0, math.random(0, 359))
    if isElement(veh) then
        setTimer(function()
            if isElement(veh) then destroyElement(veh) end
        end, 60000, 1)
    end
end

-- Teleport the player's vehicle (or the player) 5 units up.
local function act_liftVehicle(ctx)
    local el = playerVehicle(ctx.player) or ctx.player
    local x, y, z = getElementPosition(el)
    setElementPosition(el, x, y, z + 5)
end

-- Shared with follower_handler: 1 chasing enemy ped (enemies.lua), named after the sender.
local function act_spawnEnemy(ctx)
    TikTok.spawnEnemies(ctx.player, 1, ctx.senderName)
end

-- Chasing "enemy car" (enemy_cars.lua) - disappears after 2 minutes.
local function act_spawnEnemyCar(ctx)
    TikTok.spawnEnemyCar(ctx.player, ctx.senderName)
end

-- Small plane dives in from a random direction and ALWAYS explodes in front of the player.
local function act_planeCrash(ctx)
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
local function act_teleportAirport(ctx)
    local player = ctx.player
    if not isElement(player) then return end
    if #AIRPORTS == 0 then
        return act_planeCrash(ctx)
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
local function act_blackhole(ctx)
    local player = ctx.player
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

-- ---------------------------------------------------------------------------
-- GIFT -> ACTION  (gift name, lowercased)
-- A value is either  function(ctx)  OR  { fn1, fn2 } (random one of the two).
-- If the live gift names differ, the server log shows "unmapped gift: ...".
-- ---------------------------------------------------------------------------
local GIFT_ACTIONS = {
    ["rose"]         = act_replaceVehicle,                     -- Rose (1)          -> swap vehicle
    ["gg"]           = { act_dropVehicle, act_liftVehicle },   -- GG (1)            -> drop on head OR lift +5
    ["finger heart"] = { act_spawnEnemy, act_spawnEnemyCar },  -- Finger Heart (5)  -> enemy ped OR chase car
    ["fingerheart"]  = { act_spawnEnemy, act_spawnEnemyCar },  -- (name variant without space)
    ["perfume"]      = act_planeCrash,                         -- Perfume (20)      -> plane crash
    ["doughnut"]     = act_teleportAirport,                    -- Doughnut (30)     -> random airport teleport
    ["corgi"]        = act_blackhole,                          -- Corgi (299)       -> black hole
}

-- Alternative: match by gift ID (fill from the log if names are unstable)
local GIFT_ACTIONS_BY_ID = {
    -- [5655] = act_replaceVehicle,
}

-- ---------------------------------------------------------------------------
-- Main handler (the event and the test command both call this)
-- ---------------------------------------------------------------------------
addEvent("onTikTokGiftAction", true) -- other resources may listen (on root)

function TikTok.handleGift(data)
    if type(data) ~= "table" or not data.final then
        return
    end

    local giftName = tostring(data.giftName or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local giftId   = tonumber(data.giftId)

    local entry = GIFT_ACTIONS[giftName] or (giftId and GIFT_ACTIONS_BY_ID[giftId])
    if not entry then
        TikTok.log("unmapped gift: '%s' (id=%s)", tostring(data.giftName), tostring(data.giftId))
        return
    end

    -- value can be a single function or { fn1, fn2 } -> pick one at random
    local action = entry
    if type(entry) == "table" then
        action = entry[math.random(1, #entry)]
    end
    if type(action) ~= "function" then
        return
    end

    local ctx = {
        giftName     = data.giftName,
        giftId       = data.giftId,
        coins        = tonumber(data.diamondCount) or 0,
        repeats      = tonumber(data.repeatCount) or 1,
        totalCoins   = tonumber(data.totalDiamondCount) or 0,
        senderName   = data.user and (data.user.nickname or data.user.uniqueId) or "?",
        senderId     = data.user and data.user.userId or nil,
        senderUnique = data.user and data.user.uniqueId or nil,
        avatarUrl    = data.user and data.user.profilePicture or nil,
        streakable   = data.streakable,
        player       = getTargetPlayer(),   -- who the action affects
        raw          = data,
        test         = data.test and true or false,
    }
    ctx.action = action

    triggerEvent("onTikTokGiftAction", resourceRoot, giftName, ctx)

    if isElement(ctx.player) then
        local ok, err = pcall(action, ctx)
        if not ok then
            outputServerLog("[tiktok] gift action error (" .. giftName .. "): " .. tostring(err))
        end
    else
        TikTok.log("no target player (%s), '%s' action skipped", tostring(TARGET_PLAYER_NAME), giftName)
    end

    TikTok.log("gift '%s' (id=%s) -> action", tostring(data.giftName), tostring(data.giftId))
end

addEventHandler("onTikTokGift", resourceRoot, function(data)
    TikTok.handleGift(data)
end)

-- ---------------------------------------------------------------------------
-- Test commands
-- ---------------------------------------------------------------------------
local function isConsole(player)
    return not isElement(player) or getElementType(player) ~= "player"
end

local function tell(player, msg, r, g, b)
    if isConsole(player) then
        outputServerLog(msg)
    else
        outputChatBox(msg, player, r or 255, g or 255, b or 255)
    end
end

local function isAllowed(player)
    if isConsole(player) then
        return true -- server console
    end
    local acc = getPlayerAccount(player)
    if not acc or isGuestAccount(acc) then
        return false
    end
    local adminGroup = aclGetGroup("Admin")
    if not adminGroup then
        return false
    end
    return isObjectInACLGroup("user." .. getAccountName(acc), adminGroup)
end

local function fakeGift(giftName, nick)
    TikTok.handleGift({
        final = true, test = true,
        diamondCount = 1, repeatCount = 1, totalDiamondCount = 1,
        giftId = 0, giftName = giftName, streakable = false,
        user = { userId = "0", uniqueId = "test", nickname = nick or TikTok.randomName(), profilePicture = nil },
    })
end

addCommandHandler("tiktokgift", function(player, _, arg)
    if not isAllowed(player) then
        tell(player, "You are not allowed to use this command.", 255, 80, 80)
        return
    end
    if not arg then
        local list = {}
        for name in pairs(GIFT_ACTIONS) do list[#list + 1] = name end
        table.sort(list)
        tell(player, "Usage: /tiktokgift <" .. table.concat(list, " | ") .. ">", 255, 200, 0)
        return
    end
    local nick = (isElement(player) and getPlayerName(player)) or nil
    tell(player, "[tiktok] TEST gift: " .. arg, 0, 255, 0)
    fakeGift(arg, nick)
end)

-- Convenience: run every mapped gift, one after another.
addCommandHandler("tiktokgiftall", function(player)
    if not isAllowed(player) then
        tell(player, "You are not allowed to use this command.", 255, 80, 80)
        return
    end
    local delay = 0
    for name in pairs(GIFT_ACTIONS) do
        local g = name
        setTimer(function() fakeGift(g) end, delay + 100, 1)
        delay = delay + 12000  -- 12s apart (black hole runs ~9s)
    end
    tell(player, "[tiktok] Testing every mapped gift.", 0, 255, 0)
end)
