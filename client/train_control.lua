--[[
    client/train_control.lua
    ------------------------
    Bridges the server-side act_train_speed_150 action (server/actions.lua) to the
    CLIENT-side ai_autoplayer export:

        exports.ai_autoplayer:setTrainAutoSpeed(kmh)

    Runs on the target player's client only (the server triggers it there).
    (act_train_chgDirection stays server-side - it calls setTrainDirection, which
    ai_autoplayer's train.lua follows on its own.)
]]

local function autoplayer()
    return getResourceFromName and getResourceFromName("ai_autoplayer")
end

local function setSpeed(kmh)
    local ok, err = pcall(function() exports.ai_autoplayer:setTrainAutoSpeed(kmh) end)
    if not ok then
        outputDebugString("[tiktok] setTrainAutoSpeed failed: " .. tostring(err), 2)
    end
    return ok
end

-- boost -> hold for `dur` ms -> back to `normal`
addEvent("tiktok:trainAutoSpeed", true)
addEventHandler("tiktok:trainAutoSpeed", resourceRoot, function(boost, normal, dur)
    boost  = tonumber(boost)  or 150
    normal = tonumber(normal) or 80
    dur    = tonumber(dur)    or 10000

    if not autoplayer() then return end
    if not setSpeed(boost) then return end

    setTimer(function() setSpeed(normal) end, dur, 1)
end)
