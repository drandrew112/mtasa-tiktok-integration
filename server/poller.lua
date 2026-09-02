local cfg = TikTok.config

local lastId  = 0      -- highest processed event id (the cursor)
local busy    = false  -- true while a fetchRemote request is in flight
local synced  = false  -- false until we've pulled the starting cursor from /health

local function requestOptions()
    return {
        queueName          = "tiktok",
        method             = "GET",
        connectionAttempts = 1,
        connectTimeout     = 3000,
        headers            = { ["X-Bridge-Secret"] = cfg.bridgeSecret },
    }
end

-- Accepts both fetchRemote callback shapes:
--   new: (responseData, responseInfo{success, statusCode})
--   old: (responseData, errno)  where errno == 0 means success
local function requestFailed(info)
    if type(info) == "table" then
        return info.success == false
    end
    if type(info) == "number" then
        return info ~= 0
    end
    return false
end

local function onHealth(responseData, info)
    busy = false
    if requestFailed(info) then
        TikTok.log("health request failed, will retry")
        return
    end
    local data = responseData and fromJSON(responseData)
    if type(data) == "table" and tonumber(data.lastId) then
        lastId = tonumber(data.lastId)
        synced = true
        TikTok.live = data.live and true or false
        TikTok.log("cursor synced to %d (live=%s)", lastId, tostring(TikTok.live))
    else
        TikTok.log("health payload invalid, will retry")
    end
end

local function onEvents(responseData, info)
    busy = false
    if requestFailed(info) then
        TikTok.log("events request failed (cursor kept at %d)", lastId)
        return
    end

    local data = responseData and fromJSON(responseData)
    if type(data) ~= "table" or not data.ok then
        TikTok.log("events payload invalid (cursor kept at %d)", lastId)
        return
    end

    TikTok.live = data.live and true or false

    if type(data.events) == "table" then
        for _, item in ipairs(data.events) do
            TikTok.dispatch(item)
        end
    end

    -- Only advance the cursor on a fully successful response, so a failed
    -- request just retries the same range next tick (bridge keeps a buffer).
    local newLast = tonumber(data.lastId)
    if newLast and newLast > lastId then
        lastId = newLast
    end
end

local function tick()
    if busy then
        return
    end
    busy = true

    if not synced then
        fetchRemote(cfg.bridgeUrl .. "/health", requestOptions(), onHealth)
        return
    end

    fetchRemote(cfg.bridgeUrl .. "/events?after=" .. lastId, requestOptions(), onEvents)
end

function showVersion(player)
    -- We use a for loop to dump the output into player chatbox
    outputChatBox("Version information (Server):", player, 0, 255, 0)
    for ind, dat in pairs(getVersion()) do
        -- Uppercasing first letter too
        outputChatBox(string.upper(string.sub(ind, 1, 1))..string.sub(ind, 2)..": "..dat, player, 0, 255, 0)
    end
end
addCommandHandler("version", showVersion)

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(tick, cfg.pollInterval, 0)
    outputServerLog(("[tiktok] poller started -> %s (every %dms)")
        :format(cfg.bridgeUrl, cfg.pollInterval))
    if cfg.bridgeSecret == "" then
        outputServerLog("[tiktok] WARNING: bridge_secret is empty")
    end
end)
