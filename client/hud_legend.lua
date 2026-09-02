-- HUD: what the gift / like events do (for viewers). Top-left corner.
-- Toggle with `enableLegend`.

local enableLegend = false
local sw, sh = guiGetScreenSize()
local REF    = sh / 1080
local FONT   = "default-bold"
local SCALE  = REF * 2.3
local X      = 24 * REF
local Y      = 24 * REF

-- { text, isHeader? }   (mirrors the gift_handler / like_handler tables)
local LINES = {
    { "Gifts", true },
    { "Rose: swap vehicle" },
    { "GG: drop vehicle or jump" },
    { "Finger Heart: enemy or chase car" },
    { "Perfume: plane crash" },
    { "Doughnut: airport teleport" },
    { "Corgi: black hole" },
    { "" },
    { "Likes (single burst)", true },
    { "1-4: random vehicle color / skin" },
    { "5-10: smoke grenades" },
    { "11-20: spawn enemy" },
    { "" },
    { "Likes (total)", true },
    { "every 1k: spawn 4 vehicles around" },
    { "every 5k: launch vehicle or kill" },
    { "every 10k: explode vehicle" },
}

local function line(text, y, r, g, b)
    local o = math.max(2, 3 * REF)
    for _, d in ipairs({ {-o,0},{o,0},{0,-o},{0,o},{-o,-o},{o,o},{-o,o},{o,-o} }) do
        dxDrawText(text, X + d[1], y + d[2], 0, 0, tocolor(0, 0, 0, 235), SCALE, FONT)
    end
    dxDrawText(text, X, y, 0, 0, tocolor(r, g, b, 255), SCALE, FONT)
end

addEventHandler("onClientRender", root, function()
    if enableLegend then
        local lh   = dxGetFontHeight(SCALE, FONT)
        local step = lh * 0.92
        local y    = Y
        for _, l in ipairs(LINES) do
            if l[1] ~= "" then
                line(l[1], y, l[2] and 120 or 255, l[2] and 220 or 255, 255)
            end
            y = y + step
        end
    end
end)
