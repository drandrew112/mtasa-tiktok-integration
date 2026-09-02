--- Whether the bridge currently reports an active TikTok LIVE connection.
-- @return boolean
function isTikTokLive()
    return TikTok.live and true or false
end

--- Current bridge/poller status.
-- @return table
function getTikTokStatus()
    return {
        live         = TikTok.live and true or false,
        bridgeUrl    = TikTok.config.bridgeUrl,
        pollInterval = TikTok.config.pollInterval,
        debug        = TikTok.config.debug,
    }
end
