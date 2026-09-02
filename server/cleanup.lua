--[[
    cleanup.lua
    -----------
    Removes elements created by this resource.

    Automatic: when the target player (TikTok.getTargetPlayer) dies, every
    vehicle AND ped belonging to this resource is removed + the enemy AI stops.

    Manual:  /tiktokclear   (admin / console)

    Note: `resourceRoot` is the resource's dynamic element root, so
    getElementsByType(..., resourceRoot) only returns elements created HERE.
]]

--- Remove every vehicle created by this resource.
-- @param exceptVehicle vehicle|nil  keep this one (optional)
-- @return number
function TikTok.clearVehicles(exceptVehicle)
    local removed = 0
    for _, veh in ipairs(getElementsByType("vehicle", resourceRoot)) do
        if isElement(veh) and veh ~= exceptVehicle then
            destroyElement(veh)
            removed = removed + 1
        end
    end
    if removed > 0 then
        TikTok.log("clearVehicles: %d vehicles removed", removed)
    end
    return removed
end

--- Remove every ped created by this resource (backstop alongside enemies.lua).
-- @return number
function TikTok.clearResourcePeds()
    local removed = 0
    for _, ped in ipairs(getElementsByType("ped", resourceRoot)) do
        if isElement(ped) then
            destroyElement(ped)
            removed = removed + 1
        end
    end
    if removed > 0 then
        TikTok.log("clearResourcePeds: %d peds removed", removed)
    end
    return removed
end

--- Full cleanup: stop enemy AI + peds + vehicles.
-- @return number, number  (vehicles, peds)
function TikTok.cleanupAll()
    if TikTok.clearEnemies then
        TikTok.clearEnemies()          -- stops the AI timer + removes tracked peds
    end
    if TikTok.clearEnemyCars then
        TikTok.clearEnemyCars()
    end
    local peds = TikTok.clearResourcePeds()  -- leftover / dead peds
    local veh  = TikTok.clearVehicles()
    return veh, peds
end

-- Clean up when the target player dies.
addEventHandler("onPlayerWasted", root, function()
    if source == TikTok.getTargetPlayer() then
        TikTok.cleanupAll()
    end
end)

-- Manual command for testing.
addCommandHandler("tiktokclear", function(player)
    local console = not isElement(player) or getElementType(player) ~= "player"
    local allowed = console
    if not allowed then
        local acc = getPlayerAccount(player)
        local g = acc and not isGuestAccount(acc) and aclGetGroup("Admin")
        allowed = (g and isObjectInACLGroup("user." .. getAccountName(acc), g)) or false
    end
    if not allowed then
        outputChatBox("You are not allowed to use this command.", player, 255, 80, 80)
        return
    end

    local veh, peds = TikTok.cleanupAll()
    local msg = ("[tiktok] cleanup: %d vehicles, %d peds."):format(veh, peds)
    if console then outputServerLog(msg) else outputChatBox(msg, player, 0, 255, 0) end
end)
