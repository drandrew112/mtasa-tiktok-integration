-- Shared namespace for the resource.
TikTok = TikTok or {}

-- Runtime state (updated by the poller).
TikTok.live = false

local function readSetting(name, default)
    local ok, value = pcall(get, name)
    if not ok or value == nil or value == false then
        return default
    end
    return value
end

local bridgeUrl = tostring(readSetting("*bridge_url", "http://127.0.0.1:8085"))
bridgeUrl = bridgeUrl:gsub("%s+", ""):gsub("/+$", "")

TikTok.config = {
    bridgeUrl    = bridgeUrl,
    bridgeSecret = tostring(readSetting("*bridge_secret", "")),
    pollInterval = math.max(250, tonumber(readSetting("*poll_interval", 1000)) or 1000),
    debug        = tostring(readSetting("*debug", "false")) == "true",
}

function TikTok.log(fmt, ...)
    if TikTok.config.debug then
        outputServerLog("[tiktok] " .. string.format(tostring(fmt), ...))
    end
end

-- ---------------------------------------------------------------------------
-- Who the gift / like actions affect (the streamer's in-game character).
-- This is an MTA player name, NOT the TikTok username (that lives in the bridge).
-- ---------------------------------------------------------------------------
TikTok.TARGET_PLAYER_NAME = "DrAndrew112"

function TikTok.getTargetPlayer()
    local p = getPlayerFromName(TikTok.TARGET_PLAYER_NAME)
    if isElement(p) then
        return p
    end
    -- fallback: the first connected player (handy for testing)
    local players = getElementsByType("player")
    return players[1]
end

-- Vehicle models + random names live in shared/lists.lua
--   TikTok.VEHICLE_MODELS / TikTok.randomVehicleModel() / TikTok.randomName() ...
