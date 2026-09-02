--[[
    follower_handler.lua
    --------------------
    TikTok follow (onTikTokFollow) -> act.

    ACT SYSTEM (same as the gift/like handler): FOLLOW_ACTS list, one picked at random.
    Default: spawn 1 chasing enemy ped OR 1 chasing enemy car.

    ctx fields: player, senderName, senderId, raw, test

    Test:  /tiktokfollow
]]

local ENEMIES_PER_FOLLOW = 1

-- ---------------------------------------------------------------------------
-- Acts
-- ---------------------------------------------------------------------------
local function act_spawnEnemy(ctx)
    TikTok.spawnEnemies(ctx.player, ENEMIES_PER_FOLLOW, ctx.senderName)
end

local function act_spawnEnemyCar(ctx)
    TikTok.spawnEnemyCar(ctx.player, ctx.senderName)
end

local FOLLOW_ACTS = {
    act_spawnEnemy,
    act_spawnEnemyCar,
    -- add more acts here...
}

-- ---------------------------------------------------------------------------
local function pickRandom(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    return list[math.random(1, #list)]
end

addEvent("onTikTokFollowAct", true) -- other resources may listen (on root)

function TikTok.handleFollow(data)
    local u = data and data.user or nil
    local ctx = {
        player     = TikTok.getTargetPlayer(),
        senderName = u and (u.nickname or u.uniqueId) or nil,
        senderId   = u and u.userId or nil,
        raw        = data,
        test       = (data and data.test) or false,
    }

    local act = pickRandom(FOLLOW_ACTS)
    ctx.act = act

    triggerEvent("onTikTokFollowAct", resourceRoot, ctx)

    if type(act) == "function" then
        if isElement(ctx.player) then
            local ok, err = pcall(act, ctx)
            if not ok then
                outputServerLog("[tiktok] follow act error: " .. tostring(err))
            end
        else
            TikTok.log("follow: no target player, act skipped")
        end
    end

    TikTok.log("follow -> act (%s)", tostring(ctx.senderName))
end

addEventHandler("onTikTokFollow", resourceRoot, function(data)
    TikTok.handleFollow(data)
end)

-- ---------------------------------------------------------------------------
-- Test command
-- ---------------------------------------------------------------------------
addCommandHandler("tiktokfollow", function(player)
    local console = not isElement(player) or getElementType(player) ~= "player"
    TikTok.handleFollow({ test = true, user = { uniqueId = "test", nickname = TikTok.randomName() } })
    local msg = "[tiktok] TEST follow"
    if console then outputServerLog(msg) else outputChatBox(msg, player, 0, 255, 0) end
end)
