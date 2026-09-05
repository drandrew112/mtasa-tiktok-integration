--[[
    gift_handler.lua
    ----------------
    Incoming TikTok gift -> an action from the central registry (server/actions.lua).

    TWO matching modes, chosen by  Tiktok.giftHandlerType  (shared/lists.lua):
      "giftname"  -> match by gift NAME   (GIFT_ACTIONS / GIFT_ACTIONS_BY_ID)
      "coin"      -> match by COIN worth  (GIFT_ACTIONS_BY_COIN - highest tier <= worth)

    A mapped value is any of:
      - an action function            A.act_dropVehicle
      - a list of them (random one)   { A.act_spawnEnemy, A.act_spawnEnemyCar }
      - an action NAME string         "act_dropVehicle"

    The affected player is ctx.player (the TARGET_PLAYER_NAME player - the
    streamer - NOT the gift sender).

    Test commands:
      /tiktokgift <gift_name>     e.g. /tiktokgift rose
      /tiktokgiftcoin <coins>     fake a gift worth <coins> (coin mode)
      /tiktokgiftall              runs every mapped gift once
]]

local getTargetPlayer     = TikTok.getTargetPlayer
local TARGET_PLAYER_NAME  = TikTok.TARGET_PLAYER_NAME

local A = TikTok.actions or {}

-- ---------------------------------------------------------------------------
-- GIFT NAME MODE  (Tiktok.giftHandlerType == "giftname", the default)
-- Gift name is lowercased/trimmed before lookup.
-- ---------------------------------------------------------------------------
local GIFT_ACTIONS = {
    ["rose"] = A.act_train_spawnVeh_Avg_5,
    ["gg"]   = A.act_train_chgDirection,
    ["rocket"] = A.act_train_spawnVeh_Heavy_5,
    ["perfume"] = A.act_train_spawnVeh_Tank,
    ["doughnut"] = A.act_train_spawnVeh_Tank_5,
    ["corgi"] = A.act_train_chaos,

    -- examples:
    -- ["finger heart"] = { A.act_spawnEnemy, A.act_spawnEnemyCar },
    -- ["fingerheart"]  = { A.act_spawnEnemy, A.act_spawnEnemyCar },
    -- ["perfume"]      = A.act_planeCrash,
    -- ["doughnut"]     = A.act_teleportAirport,
    -- ["corgi"]        = A.act_blackhole,
}

-- Match by gift ID (fill from the log if names are unstable).
local GIFT_ACTIONS_BY_ID = {
    -- [5655] = A.act_replaceVehicle,
}

-- ---------------------------------------------------------------------------
-- COIN MODE  (Tiktok.giftHandlerType == "coin")
-- The tier with the highest `coins` value <= the gift's coin worth wins;
-- one entry from `acts` is picked at random. Order does not matter.
-- ---------------------------------------------------------------------------
local GIFT_ACTIONS_BY_COIN = {
    -- { coins = 1,   acts = { A.act_dropVehicle } },
    -- { coins = 5,   acts = { A.act_spawnEnemy, A.act_spawnEnemyCar } },
    -- { coins = 20,  acts = { A.act_planeCrash } },
    -- { coins = 50,  acts = { A.act_train_spawnVeh_Heavy } },
    -- { coins = 100, acts = { A.act_train_spawnVeh_Tank } },
    -- { coins = 299, acts = { A.act_blackhole } },
}

-- ---------------------------------------------------------------------------
-- Resolve a mapped value to a single action function.
-- ---------------------------------------------------------------------------
local function toFn(v)
    if type(v) == "function" then return v end
    if type(v) == "string" then return TikTok.actions[v] end
    return nil
end

local function pickAction(entry)
    if type(entry) == "table" and not toFn(entry) then
        if #entry == 0 then return nil end
        return toFn(entry[math.random(1, #entry)])
    end
    return toFn(entry)
end

local function coinWorthOf(data)
    local total = tonumber(data.totalDiamondCount)
    if total and total > 0 then return total end
    return (tonumber(data.diamondCount) or 0) * (tonumber(data.repeatCount) or 1)
end

local function resolveByCoin(worth)
    local best, bestCoins = nil, -1
    for _, tier in ipairs(GIFT_ACTIONS_BY_COIN) do
        local c = tonumber(tier.coins) or 0
        if worth >= c and c > bestCoins then
            best, bestCoins = tier.acts, c
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Main handler (the event and the test commands all call this)
-- ---------------------------------------------------------------------------
addEvent("onTikTokGiftAction", true) -- other resources may listen (on root)

function TikTok.handleGift(data)
    if type(data) ~= "table" or not data.final then
        return
    end

    local giftName = tostring(data.giftName or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local giftId   = tonumber(data.giftId)
    local worth    = coinWorthOf(data)
    local mode     = (Tiktok.giftHandlerType == "coin") and "coin" or "giftname"

    local entry
    if mode == "coin" then
        entry = resolveByCoin(worth)
    else
        entry = GIFT_ACTIONS[giftName] or (giftId and GIFT_ACTIONS_BY_ID[giftId])
    end

    if not entry then
        TikTok.log("unmapped gift: '%s' (id=%s, coins=%s, mode=%s)",
            tostring(data.giftName), tostring(data.giftId), tostring(worth), mode)
        return
    end

    local action = pickAction(entry)
    if type(action) ~= "function" then
        TikTok.log("gift '%s' mapped to a non-action value", giftName)
        return
    end

    local ctx = {
        giftName     = data.giftName,
        giftId       = data.giftId,
        coins        = tonumber(data.diamondCount) or 0,
        coinWorth    = worth,
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

    TikTok.log("gift '%s' (id=%s, coins=%s, mode=%s) -> action",
        tostring(data.giftName), tostring(data.giftId), tostring(worth), mode)
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

local function fakeGift(fields, nick)
    local data = {
        final = true, test = true,
        diamondCount = 1, repeatCount = 1, totalDiamondCount = 1,
        giftId = 0, giftName = "", streakable = false,
        user = { userId = "0", uniqueId = "test", nickname = nick or TikTok.randomName(), profilePicture = nil },
    }
    for k, v in pairs(fields or {}) do data[k] = v end
    TikTok.handleGift(data)
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
        if Tiktok.giftHandlerType == "coin" then
            tell(player, "(gift handler is in COIN mode - use /tiktokgiftcoin <coins>)", 255, 200, 0)
        end
        return
    end
    local nick = (isElement(player) and getPlayerName(player)) or nil
    tell(player, "[tiktok] TEST gift: " .. arg, 0, 255, 0)
    fakeGift({ giftName = arg }, nick)
end)

addCommandHandler("tiktokgiftcoin", function(player, _, arg)
    if not isAllowed(player) then
        tell(player, "You are not allowed to use this command.", 255, 80, 80)
        return
    end
    local n = math.floor(tonumber(arg) or 0)
    if n <= 0 then
        tell(player, "Usage: /tiktokgiftcoin <coins>", 255, 200, 0)
        return
    end
    local nick = (isElement(player) and getPlayerName(player)) or nil
    tell(player, ("[tiktok] TEST gift worth %d coins"):format(n), 0, 255, 0)
    fakeGift({ giftName = "coin_test", diamondCount = n, totalDiamondCount = n }, nick)
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
        setTimer(function() fakeGift({ giftName = g }) end, delay + 100, 1)
        delay = delay + 12000  -- 12s apart (black hole runs ~9s)
    end
    tell(player, "[tiktok] Testing every mapped gift.", 0, 255, 0)
end)
