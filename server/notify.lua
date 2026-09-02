--[[
    notify.lua
    ----------
    TikTok events -> ui_core notifications.

    ui_core client export:  exports.ui_core:addNotification(title, text)
    A server can't call a client export directly, so client/notify.lua receives
    the "tiktok:notify" event and calls it.
]]

-- Which event types trigger a notification.
local NOTIFY = {
    gift   = true,
    follow = true,
    share  = true,
    like   = true,  -- can be noisy
    status = true,
}

--- Send a notification.
-- @param title  string
-- @param text   string
-- @param target element|nil  target player; nil = everyone
function TikTok.notify(title, text, target)
    triggerClientEvent(target or root, "tiktok:notify", resourceRoot,
        tostring(title or ""), tostring(text or ""))
end

local function senderName(data)
    local u = data.user or {}
    return u.nickname or u.uniqueId or "Someone"
end

-- ---------------------------------------------------------------------------

if NOTIFY.gift then
    addEventHandler("onTikTokGift", resourceRoot, function(data)
        if not data.final then return end
        local coins  = tonumber(data.totalDiamondCount) or 0
        local repeats = tonumber(data.repeatCount) or 1
        local amount = (repeats > 1) and (" x" .. repeats) or ""
        TikTok.notify(
            senderName(data),
            ("%s%s  (%d coins)"):format(tostring(data.giftName or "gift"), amount, coins)
        )
    end)
end

if NOTIFY.follow then
    addEventHandler("onTikTokFollow", resourceRoot, function(data)
        TikTok.notify("New Follower", senderName(data))
    end)
end

if NOTIFY.share then
    addEventHandler("onTikTokShare", resourceRoot, function(data)
        TikTok.notify("Share", senderName(data) .. " shared the live")
    end)
end

if NOTIFY.like then
    addEventHandler("onTikTokLike", resourceRoot, function(data)
        local n = tonumber(data.likeCount) or 1
        local total = tonumber(data.totalLikeCount) or n
        TikTok.notify(senderName(data), ("+%d likes (%d total)"):format(n, total))
    end)
end

if NOTIFY.status then
    addEventHandler("onTikTokStatus", resourceRoot, function(data)
        TikTok.notify("TikTok", "Status: " .. tostring(data.state))
    end)
end
