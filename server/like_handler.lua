--[[
    like_handler.lua
    ----------------
    Like reactions: per like-event batch size, and per total-like milestone.

    ACT SYSTEM
    ----------
    Actions live in server/actions.lua (TikTok.actions). Reference them here:
         MILESTONE_ACTS[<value>] = { A.act_something, ... }  -- ONCE, at an exact total
         INTERVAL_ACTS[<step>]   = { A.act_something, ... }   -- REPEATING, every <step> likes
       Table values are always a LIST -> the code picks one at random.

    ctx fields: milestone, total, likeCount, rawTotal, senderName, senderId,
                player (TikTok.getTargetPlayer()), test

    A single LIKE EVENT's batch size (data.likeCount) also triggers a reaction:
      LIKE_BURST_ACTS (see below)

    Test commands:
      /tiktoklike <n>        - jump the like counter to n (milestones)
      /tiktoklikeadd <n>     - add n
      /tiktoklikeburst <n>   - one like-event with batch size n (burst acts)
      /tiktoklikereset       - reset the counter + fired milestones
]]

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
-- "session"  : likes counted from when the resource connected (first event = 0)
-- "absolute" : the TikTok room's raw total like count
local COUNT_MODE       = "session"
local MAX_CATCHUP      = 50      -- max repeating milestones fired at once (big-jump guard)
local NOTIFY_MILESTONE = true    -- automatic ui_core notification on every milestone

-- ===========================================================================
--  ACTS   -  all live in server/actions.lua now (TikTok.actions)
-- ===========================================================================

local A = TikTok.actions or {}

-- ===========================================================================
--  MILESTONE TABLES   ([value] = { act, act, ... })
-- ===========================================================================

-- By a single LIKE EVENT's batch size (data.likeCount). First match wins.
-- (TikTok batches likes; a batch this big is rare but happens.)
local LIKE_BURST_ACTS = {
    --{ min = 1,  max = 4,  acts = { A.act_randomVehicleColor } },
    --{ min = 5,  max = 10, acts = { A.act_smokeGrenades } },
    --{ min = 11, max = 20, acts = { A.act_spawnEnemy } },
    { min = 1,  max = 4,  acts = { A.act_train_spawnVeh_Avg,   A.act_train_spawnPed } },
    { min = 5,  max = 9,  acts = { A.act_train_spawnVeh_Heavy, A.act_train_spawnPed_5 } },
    { min = 10, max = 19, acts = { A.act_train_spawnVeh_Tank,  A.act_train_spawnPed_10 } },
}

-- Fired once, at EXACT total-like values:
local MILESTONE_ACTS = {
    -- [1000] = { A.act_spawnVehiclesAround },
    -- [5000]  = { ... },
    -- [10000] = { ... },
}

-- REPEATING, every N likes:
local INTERVAL_ACTS = {
    [100]  = { A.act_train_spawnPed },
    [1000]  = { A.act_spawnVehiclesAround },
    [5000]  = { A.act_train_spawnVeh_Tank_5 },
    --[5000]  = { A.act_launchVehicleOrKill },
    --[10000] = { A.act_explodeVehicle },   -- in a vehicle -> explodes
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local baseline  = nil    -- session mode: the first raw total-like value seen
local lastCount = 0      -- last processed value (mode-adjusted)
local firedOnce = {}     -- [milestone] = true

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function pickRandom(list)
    if type(list) ~= "table" or #list == 0 then
        return nil
    end
    return list[math.random(1, #list)]
end

local function modeCount(rawTotal)
    if COUNT_MODE == "absolute" then
        return rawTotal
    end
    if not baseline then
        baseline = rawTotal
    end
    return math.max(0, rawTotal - baseline)
end

local function makeCtx(milestone, info)
    local u = info and info.user or nil
    return {
        milestone  = milestone,
        total      = lastCount,
        likeCount  = (info and info.likeCount) or 0,
        rawTotal   = (info and info.raw) or lastCount,
        senderName = u and (u.nickname or u.uniqueId) or nil,
        senderId   = u and u.userId or nil,
        player     = TikTok.getTargetPlayer(),
        test       = (info and info.test) or false,
    }
end

local function runAct(fn, ctx)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ctx)
    if not ok then
        outputServerLog("[tiktok] like act error (milestone " .. tostring(ctx.milestone) .. "): " .. tostring(err))
    end
end

addEvent("onTikTokLikeMilestone", true) -- other resources may listen (on root)

local function fireMilestone(milestone, fn, info)
    local ctx = makeCtx(milestone, info)

    if NOTIFY_MILESTONE then
        TikTok.notify("Like milestone reached", milestone .. " likes")
    end

    triggerEvent("onTikTokLikeMilestone", resourceRoot, milestone, ctx)
    runAct(fn, ctx)

    TikTok.log("like milestone %d (total=%d, act=%s)", milestone, lastCount, tostring(fn))
end

-- ---------------------------------------------------------------------------
-- Advance the counter and fire milestones
-- ---------------------------------------------------------------------------
local function processLikeCount(count, info)
    count = tonumber(count)
    if not count or count <= lastCount then
        return -- counter did not grow
    end

    local from = lastCount
    lastCount = count

    -- 1) exact, one-time milestones in the (from, count] range
    for value, acts in pairs(MILESTONE_ACTS) do
        if value > from and value <= count and not firedOnce[value] then
            firedOnce[value] = true
            fireMilestone(value, pickRandom(acts), info)
        end
    end

    -- 2) repeating intervals
    for step, acts in pairs(INTERVAL_ACTS) do
        if type(step) == "number" and step > 0 then
            local a = math.floor(from / step)
            local b = math.floor(count / step)
            if b - a > MAX_CATCHUP then
                TikTok.log("like jump too big (%d -> %d, step %d)", from, count, step)
                a = b - MAX_CATCHUP
            end
            for k = a + 1, b do
                fireMilestone(k * step, pickRandom(acts), info)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Incoming like event
-- ---------------------------------------------------------------------------
function TikTok.handleLike(data)
    if type(data) ~= "table" then return end
    local raw = tonumber(data.totalLikeCount)
    local lc  = tonumber(data.likeCount) or 0

    -- 1) per-event "burst" reaction by batch size
    for _, r in ipairs(LIKE_BURST_ACTS) do
        if lc >= r.min and lc <= r.max then
            runAct(pickRandom(r.acts), makeCtx(nil, {
                likeCount = lc, user = data.user, raw = raw or lc,
            }))
            break
        end
    end

    -- 2) total-like milestones
    if raw then
        processLikeCount(modeCount(raw), {
            likeCount = lc,
            user      = data.user,
            raw       = raw,
        })
    end
end

addEventHandler("onTikTokLike", resourceRoot, function(data)
    TikTok.handleLike(data)
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
    if isConsole(player) then return true end
    local acc = getPlayerAccount(player)
    if not acc or isGuestAccount(acc) then return false end
    local g = aclGetGroup("Admin")
    return (g and isObjectInACLGroup("user." .. getAccountName(acc), g)) or false
end

addCommandHandler("tiktoklike", function(player, _, arg)
    if not isAllowed(player) then
        tell(player, "You are not allowed to use this command.", 255, 80, 80)
        return
    end
    local n = tonumber(arg)
    if not n then
        tell(player, "Usage: /tiktoklike <total_like_value>", 255, 200, 0)
        return
    end
    n = math.floor(n)
    tell(player, ("[tiktok] TEST like total -> %d"):format(n), 0, 255, 0)
    processLikeCount(n, { test = true })
end)

addCommandHandler("tiktoklikeadd", function(player, _, arg)
    if not isAllowed(player) then
        tell(player, "You are not allowed to use this command.", 255, 80, 80)
        return
    end
    local n = math.floor(tonumber(arg) or 1)
    local target = lastCount + n
    tell(player, ("[tiktok] TEST like +%d -> %d"):format(n, target), 0, 255, 0)
    processLikeCount(target, { test = true })
end)

-- Simulate one like event with a given batch size (for the burst acts).
addCommandHandler("tiktoklikeburst", function(player, _, arg)
    if not isAllowed(player) then
        tell(player, "You are not allowed to use this command.", 255, 80, 80)
        return
    end
    local n = math.floor(tonumber(arg) or 60)
    tell(player, ("[tiktok] TEST like burst: %d"):format(n), 0, 255, 0)
    TikTok.handleLike({ likeCount = n, user = { userId = "0", uniqueId = "test", nickname = TikTok.randomName() } })
end)

addCommandHandler("tiktoklikereset", function(player)
    if not isAllowed(player) then
        tell(player, "You are not allowed to use this command.", 255, 80, 80)
        return
    end
    baseline  = nil
    lastCount = 0
    firedOnce = {}
    tell(player, "[tiktok] like counter reset.", 0, 255, 0)
end)
