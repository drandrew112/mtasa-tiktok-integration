--[[
    loadout.lua  (server)
    ---------------------
    Base weapon for players: MP5.
      - on resource start  -> every alive player
      - after respawn      -> that player
]]

local WEAPON = 29     -- MP5
local AMMO   = 500

local function giveLoadout(player)
    if isElement(player) and getElementType(player) == "player" then
        giveWeapon(player, WEAPON, AMMO, true)
    end
end

addEventHandler("onPlayerSpawn", root, function()
    giveLoadout(source)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, p in ipairs(getElementsByType("player")) do
        if getElementHealth(p) > 0 then
            giveLoadout(p)
        end
    end
end)
