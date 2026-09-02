-- Receives server-side TikTok notifications and shows them via ui_core.
-- ui_core client export:  exports.ui_core:addNotification(title, text)

addEvent("tiktok:notify", true)

addEventHandler("tiktok:notify", resourceRoot, function(title, text)
    local ok, err = pcall(function()
        exports.ui_core:addNotification(title, text)
        outputChatBox("[tiktok] " .. tostring(title) .. ": " .. tostring(text), root, 0, 255, 0)
    end)
    if not ok then
        outputDebugString("[tiktok] notify failed: " .. tostring(err), 2)
    end
end)
