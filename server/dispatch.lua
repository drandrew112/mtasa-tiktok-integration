-- Maps a bridge event "type" to the MTA event name triggered for it.
local EVENT_MAP = {
    gift   = "onTikTokGift",
    follow = "onTikTokFollow",
    like   = "onTikTokLike",
    share  = "onTikTokShare",
    status = "onTikTokStatus",
}

-- Per-type events. Each handler receives a single `data` table (see README).
for _, eventName in pairs(EVENT_MAP) do
    addEvent(eventName, true)
end

-- Generic firehose: triggered for every event as (eventType, data).
addEvent("onTikTokEvent", true)

--- Dispatch one normalized event coming from the bridge.
-- @param item table  { id, type, ts, ... }
function TikTok.dispatch(item)
    if type(item) ~= "table" or type(item.type) ~= "string" then
        return
    end

    triggerEvent("onTikTokEvent", resourceRoot, item.type, item)

    local eventName = EVENT_MAP[item.type]
    if eventName then
        triggerEvent(eventName, resourceRoot, item)
    end

    TikTok.log("dispatch %s (id=%s)", item.type, tostring(item.id))
end
