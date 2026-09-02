--[[
    enemies.lua  (server)
    ---------------------
    Enemy peds. Ped CONTROL (movement/aim/fire) only works client-side
    (setPedControlState is client-only), so the server just:
      - creates the ped, gives it a weapon + max weapon skill + a "name" data value
      - makes the target player the syncer (that client drives the ped)
      - tells the target's client (tiktok:enemyAdd / enemyRemove)
      - handles death / disconnect / cleanup

    DAMAGE: only the ped's REAL bullets hurt the player (GTA handles it).
            The script does NOT subtract health.

    The actual AI: client/enemy_ai.lua

    TikTok.spawnEnemies(player, howMany, name)
    TikTok.clearEnemies()

    Test:  /tiktokenemy [count]   /tiktokclearenemy
]]

-- Models / weapons / names: shared/lists.lua
local ENEMY_MODELS   = TikTok.ENEMY_MODELS
local ENEMY_WEAPONS  = TikTok.ENEMY_WEAPONS
local SPAWN_MIN      = 6
local SPAWN_MAX      = 12
local MAX_ENEMIES    = 20   -- a full wave (3x5) + a bit of leftover fits
local CORPSE_LINGER  = 6000
local ENEMY_LIFETIME = 3 * 60 * 1000   -- dies on its own after this long

local enemies = {}   -- [ped] = { target = player }

local function enemyCount()
    local n = 0
    for _ in pairs(enemies) do n = n + 1 end
    return n
end

local function removeEnemy(ped, linger)
    local e = enemies[ped]
    enemies[ped] = nil
    if e and isElement(e.target) then
        triggerClientEvent(e.target, "tiktok:enemyRemove", resourceRoot, ped)
    end
    if isElement(ped) then
        if linger and linger > 0 then
            setTimer(function() if isElement(ped) then destroyElement(ped) end end, linger, 1)
        else
            destroyElement(ped)
        end
    end
end

local function removeEnemiesOf(player)
    for ped, e in pairs(enemies) do
        if e.target == player then
            removeEnemy(ped, 0)
        end
    end
end

--- N chasing enemy peds around the player.
-- @param name string|nil  the ped's "name" data; nil/"" -> a random name per ped
function TikTok.spawnEnemies(player, howMany, name)
    if not isElement(player) then return 0 end
    howMany = tonumber(howMany) or 1

    local px, py, pz = getElementPosition(player)
    local made = 0

    for _ = 1, howMany do
        if enemyCount() >= MAX_ENEMIES then break end
        local ang = math.random() * math.pi * 2
        local d   = math.random(SPAWN_MIN, SPAWN_MAX)
        local ped = createPed(ENEMY_MODELS[math.random(1, #ENEMY_MODELS)],
                              px + math.cos(ang) * d, py + math.sin(ang) * d, pz + 0.5)
        if isElement(ped) then
            giveWeapon(ped, ENEMY_WEAPONS[math.random(1, #ENEMY_WEAPONS)], 9999, true)
            setElementFrozen(ped, false)
            for stat = 69, 79 do            -- max weapon skills (accurate, low spread)
                pcall(setPedStat, ped, stat, 999)
            end
            local pedName = (name ~= nil and name ~= "") and tostring(name) or TikTok.randomName()
            setElementData(ped, "name", pedName)

            setElementSyncer(ped, player)   -- the target's client drives it

            enemies[ped] = { target = player }
            made = made + 1

            local thePed, theTarget = ped, player
            setTimer(function()
                if isElement(thePed) and isElement(theTarget) then
                    triggerClientEvent(theTarget, "tiktok:enemyAdd", resourceRoot, thePed)
                end
            end, 350, 1)  -- small delay so the ped definitely exists on the client

            -- lifetime: dies on its own after ENEMY_LIFETIME
            setTimer(function()
                if isElement(thePed) and getElementHealth(thePed) > 0 then
                    killPed(thePed)   -- -> onPedWasted -> removeEnemy
                end
            end, ENEMY_LIFETIME, 1)
        end
    end

    if made > 0 then
        TikTok.log("spawnEnemies: +%d ped (%s) total %d", made, tostring(name or "?"), enemyCount())
    end
    return made
end

--- Remove every enemy ped.
function TikTok.clearEnemies()
    local n = enemyCount()
    for ped, e in pairs(enemies) do
        enemies[ped] = nil
        if e and isElement(e.target) then
            triggerClientEvent(e.target, "tiktok:enemyRemove", resourceRoot, ped)
        end
        if isElement(ped) then destroyElement(ped) end
    end
    if n > 0 then
        TikTok.log("clearEnemies: %d peds removed", n)
    end
    return n
end

-- enemy death
addEventHandler("onPedWasted", root, function()
    if enemies[source] then
        removeEnemy(source, CORPSE_LINGER)
    end
end)

-- target player dies / disconnects -> peds attacking them disappear
addEventHandler("onPlayerWasted", root, function()
    removeEnemiesOf(source)
end)
addEventHandler("onPlayerQuit", root, function()
    removeEnemiesOf(source)
end)

-- ---------------------------------------------------------------------------
-- Test commands
-- ---------------------------------------------------------------------------
addCommandHandler("tiktokenemy", function(player, _, arg)
    local console = not isElement(player) or getElementType(player) ~= "player"
    local target  = TikTok.getTargetPlayer()
    if not isElement(target) then
        if console then outputServerLog("[tiktok] no target player") end
        return
    end
    local n = TikTok.spawnEnemies(target, tonumber(arg) or 1)   -- nil -> random names
    local msg = ("[tiktok] %d enemies spawned"):format(n)
    if console then outputServerLog(msg) else outputChatBox(msg, player, 0, 255, 0) end
end)

addCommandHandler("tiktokclearenemy", function(player)
    local console = not isElement(player) or getElementType(player) ~= "player"
    local n = TikTok.clearEnemies()
    local msg = ("[tiktok] %d enemies removed"):format(n)
    if console then outputServerLog(msg) else outputChatBox(msg, player, 0, 255, 0) end
end)
