-- Client-side gift effects (driven by server/gift_handler.lua + like_handler.lua).

addEvent("tiktok:blackholeStart", true)
addEvent("tiktok:blackholeEnd", true)

local saved = nil          -- original gravity values
local restoreTimer = nil

local function restoreGravity()
    if not saved then return end
    setPedGravity(localPlayer, saved.ped)
    local v = getPedOccupiedVehicle(localPlayer)
    if isElement(v) and saved.veh then
        setVehicleGravity(v, saved.veh.x, saved.veh.y, saved.veh.z)
    end
    saved = nil
end

addEventHandler("tiktok:blackholeStart", resourceRoot, function(duration)
    -- save original gravity, then null it
    saved = { ped = getPedGravity(localPlayer) }
    local v = getPedOccupiedVehicle(localPlayer)
    if isElement(v) then
        local gx, gy, gz = getVehicleGravity(v)
        saved.veh = { x = gx, y = gy, z = gz }
        setVehicleGravity(v, 0, 0, 0)
    end
    setPedGravity(localPlayer, 0)

    if isTimer(restoreTimer) then killTimer(restoreTimer) end
    restoreTimer = setTimer(restoreGravity, (tonumber(duration) or 9000) + 750, 1)
end)

addEventHandler("tiktok:blackholeEnd", resourceRoot, function()
    if isTimer(restoreTimer) then killTimer(restoreTimer) end
    -- small delay so the player falls after the server "lets go"
    restoreTimer = setTimer(restoreGravity, 400, 1)
end)

-- don't leave gravity stuck at 0 if the player dies / the resource stops
addEventHandler("onClientPlayerWasted", localPlayer, restoreGravity)
addEventHandler("onClientResourceStop", resourceRoot, restoreGravity)

-- ---------------------------------------------------------------------------
-- Smoke / teargas grenades (like burst). createProjectile works reliably
-- client-side and the gas cloud renders.
-- ---------------------------------------------------------------------------
addEvent("tiktok:smokeGrenades", true)
addEventHandler("tiktok:smokeGrenades", resourceRoot, function(count)
    count = tonumber(count) or 5
    for i = 1, count do
        local ox = math.random(-40, 40) / 10
        local oy = math.random(-40, 40) / 10
        setTimer(function()
            if isElement(localPlayer) then
                local cx, cy, cz = getElementPosition(localPlayer)
                createProjectile(localPlayer, 17, cx + ox, cy + oy, cz + 6, 1.0)  -- 17 = teargas
            end
        end, i * 50, 1)
    end
end)
