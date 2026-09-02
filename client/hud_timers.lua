-- HUD: large, clearly visible countdown (readable for phone viewers too).
-- Driven by server/spawn_timers.lua

local vehDeadline, enemyDeadline

addEvent("tiktok:spawnTimers", true)
addEventHandler("tiktok:spawnTimers", resourceRoot, function(vehRemain, enemyRemain)
    local now = getTickCount()
    vehDeadline   = now + (tonumber(vehRemain)   or 0)
    enemyDeadline = now + (tonumber(enemyRemain) or 0)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("tiktok:spawnTimersReq", localPlayer)
end)

local function fmt(ms)
    if not ms or ms < 0 then ms = 0 end
    local s = math.floor(ms / 1000)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local sw, sh   = guiGetScreenSize()
local REF      = sh / 1080
local FONT     = "default-bold"
local SCALE    = REF * 3.4            -- LARGE
local MARGIN   = 24 * REF

-- black outline + color so it's readable on any background
local function bigText(text, y, r, g, b)
    local o = math.max(2, 3 * REF)
    for _, d in ipairs({ {-o,0},{o,0},{0,-o},{0,o},{-o,-o},{o,o},{-o,o},{o,-o} }) do
        dxDrawText(text, d[1], y + d[2], sw + d[1], y + d[2], tocolor(0, 0, 0, 235),
            SCALE, FONT, "center", "top")
    end
    dxDrawText(text, 0, y, sw, y, tocolor(r, g, b, 255), SCALE, FONT, "center", "top")
end

addEventHandler("onClientRender", root, function()
    if not vehDeadline then return end
    local now = getTickCount()
    local lh  = dxGetFontHeight(SCALE, FONT)

    -- bottom-center
    local y = sh - lh * 1.95 - MARGIN

    bigText("TANK SPAWN  "  .. fmt(vehDeadline - now),   y,             120, 220, 255)
    bigText("ENEMY WAVE  " .. fmt(enemyDeadline - now), y + lh * 0.95, 255, 200, 110)
end)
