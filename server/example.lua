--[[
    Example event consumers.

    This file only logs, and only when the "*debug" setting is "true".
    It is safe to delete this file entirely (also remove its <script> line
    from meta.xml). It exists to show the event payload shapes.

    From ANOTHER resource you would attach the same way, using `root`
    (the events bubble up from the tiktok resource):

        addEventHandler("onTikTokGift", root, function(data)
            -- data.user.uniqueId, data.giftName, data.diamondCount, ...
        end)
]]

if not TikTok.config.debug then
    return
end

local function who(data)
    local u = data.user or {}
    return u.uniqueId or u.nickname or ("id:" .. tostring(u.userId))
end

addEventHandler("onTikTokGift", resourceRoot, function(data)
    outputServerLog(("[tiktok] GIFT  %s  %s x%d  (%s diamonds each, final=%s)")
        :format(who(data), tostring(data.giftName), data.repeatCount or 1,
                tostring(data.diamondCount), tostring(data.final)))
end)

addEventHandler("onTikTokFollow", resourceRoot, function(data)
    outputServerLog(("[tiktok] FOLLOW %s"):format(who(data)))
end)

addEventHandler("onTikTokLike", resourceRoot, function(data)
    outputServerLog(("[tiktok] LIKE  %s  +%s  (room total %s)")
        :format(who(data), tostring(data.likeCount), tostring(data.totalLikeCount)))
end)

addEventHandler("onTikTokShare", resourceRoot, function(data)
    outputServerLog(("[tiktok] SHARE %s"):format(who(data)))
end)

addEventHandler("onTikTokStatus", resourceRoot, function(data)
    outputServerLog(("[tiktok] STATUS %s"):format(tostring(data.state)))
end)
