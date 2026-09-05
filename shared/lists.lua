--[[
    shared/lists.lua
    ----------------
    Shared data lists (client + server). Loads BEFORE every other script.

    Names:      TikTok.NAMES            TikTok.randomName()
    Vehicles:   TikTok.VEHICLE_MODELS   TikTok.randomVehicleModel()
    Enemies:    TikTok.ENEMY_MODELS     TikTok.ENEMY_WEAPONS
    Enemy car:  TikTok.CAR_MODELS       TikTok.CAR_DRIVER_MODEL
    Planes:     TikTok.PLANE_MODELS
    Black hole: TikTok.BLACKHOLE_MODELS
    Airports:   TikTok.AIRPORTS         { x, y, z [, heading] }
    Skins:      TikTok.BAD_SKINS        TikTok.randomSkin()
]]

TikTok = TikTok or {}
Tiktok = Tiktok or TikTok   -- alias: some scripts use the lowercase-k spelling

Tiktok.enableTimers = false   -- set to false to disable the vehicle / enemy timers (for testing)

-- Which gift -> action mapping the gift handler uses:
--   "giftname" -> match by gift NAME   (server/gift_handler.lua : GIFT_ACTIONS)
--   "coin"     -> match by COIN worth  (server/gift_handler.lua : GIFT_ACTIONS_BY_COIN)
Tiktok.giftHandlerType = "giftname"

-- ---------------------------------------------------------------------------
-- Random names (enemy peds / enemy car driver)
-- ---------------------------------------------------------------------------
TikTok.NAMES = {
    "Zarex", "Velko", "Nimra", "Kavor", "Lunex", "Rivon", "Tarek", "Zorin",
    "Mavik", "Elron", "Varek", "Nerix", "Solven", "Kirel", "Davor", "Ruvan",
    "Melko", "Ziven", "Torik", "Veyra", "Narek", "Lavor", "Sirex", "Kelvo",
    "Raxon", "Mirven", "Zelor", "Tavik", "Viron", "Nexar", "Korven", "Elvik",
    "Rovel", "Zarik", "Miren", "Valex", "Korin", "Saven", "Tervik", "Navor",
    "Zevin", "Lerox", "Milon", "Riven", "Kavon", "Zerik", "Torven", "Velar",
    "Nirox", "Norton", "Kevin", "Bryan", "Ethen", "Tyler", "Carter", "Nox",
    "Hunter"
}

function TikTok.randomName()
    return TikTok.NAMES[math.random(1, #TikTok.NAMES)]
end

-- ---------------------------------------------------------------------------
-- Random vehicle models (gift / like / spawn_timers)
-- ---------------------------------------------------------------------------
TikTok.VEHICLE_MODELS = {
    592, 577, 511, 512, 593, 460, 548, 417, 488, 563, 447, 469,
    602, 496, 401, 518, 527, 589, 419, 587, 533, 526, 474, 545, 517, 410, 600, 436, 439, 549, 491,
    431, 525, 408, 552,
    433, 528, 407, 544, 599, 601,
    499, 524, 578, 573, 455, 403, 423, 414, 443, 515, 514, 456,
    422, 605, 543, 478, 554,
    489, 505, 442,
    536, 575, 534, 535, 576, 412,
    402, 542, 603, 475,
    429, 541, 415, 480, 562, 565, 434, 494, 502, 503, 411, 559, 506, 451, 558, 555, 477,
    538, 537,
    424, 504, 483, 508, 500, 444, 556, 557, 495,
}

function TikTok.randomVehicleModel()
    return TikTok.VEHICLE_MODELS[math.random(1, #TikTok.VEHICLE_MODELS)]
end

-- ---------------------------------------------------------------------------
-- Enemy peds (enemies.lua)
--  IMPORTANT: one gang only, otherwise the peds shoot each other
--  (rival gangs -> GTA relationship -> friendly fire). 102-104 = Ballas.
-- ---------------------------------------------------------------------------
TikTok.ENEMY_MODELS  = { 101, 102, 103, 104 }
TikTok.ENEMY_WEAPONS = { 28, 29, 32 }   -- Uzi, MP5, Tec9 (full-auto -> continuous fire)

-- ---------------------------------------------------------------------------
-- Enemy car (enemy_cars.lua)
-- ---------------------------------------------------------------------------
TikTok.CAR_MODELS       = { 415, 429, 541, 451, 411, 480 }   -- fast cars
TikTok.CAR_DRIVER_MODEL = 102

-- ---------------------------------------------------------------------------
-- Plane crash (Perfume gift) - small planes
-- ---------------------------------------------------------------------------
TikTok.PLANE_MODELS = { 476, 512, 513, 593 }   -- Rustler, Cropduster, Stuntplane, Dodo

-- ---------------------------------------------------------------------------
-- Black hole object models (Corgi gift)
-- ---------------------------------------------------------------------------
TikTok.BLACKHOLE_MODELS = { 1337, 2905, 3059, 3067, 1649, 2985 }

-- ---------------------------------------------------------------------------
-- Airport coordinates (Doughnut gift teleport):  { x, y, z [, heading] }
-- ---------------------------------------------------------------------------
TikTok.AIRPORTS = {
    { -1329.3575439453, -154.06324768066, 14.1484375, 300 }, -- SF
    { 1852.9873046875, -2456.607421875, 13.5546875, 20 },    -- LS
    { 1473.3919677734, 1620.5258789062, 10.8125, 160 },      -- LV
}

-- ---------------------------------------------------------------------------
-- Skins (like burst - random skin when the player has no vehicle)
-- ---------------------------------------------------------------------------
TikTok.BAD_SKINS = {
    [74] = true, [150] = true, [265] = true, [266] = true, [267] = true,
    [268] = true, [269] = true, [270] = true, [271] = true, [272] = true,
}

function TikTok.randomSkin()
    local s
    repeat s = math.random(0, 312) until not TikTok.BAD_SKINS[s]
    return s
end

-- ---------------------------------------------------------------------------
-- "Train" actions (server/actions.lua : act_train_*)
--   Obstacles dropped a fixed distance in FRONT of the player's vehicle.
--   None of these are wired to an event yet - fire them with /tiktokaction.
-- ---------------------------------------------------------------------------
Tiktok.train = {
    -- units in front of the player per spawn step; the _5 / _10 variants place
    -- each successive vehicle/ped one more `distance` further ahead.
    distance = 10,

    -- average sized vehicles for act_train_spawnVeh_Avg*
    avg_vehicles = {
        445, 466, 492, 546, 547, 405, 550, 566, 517, 507,
        585, 419, 526, 491, 421, 529, 458, 542, 518, 527,
    },

    -- heavy vehicles for act_train_spawnVeh_Heavy* (NO tank here - the tank
    -- actions use `tank` below).
    heavy_vehicles = {
        403, 514, 515, 455, 456, 433, 578, 406, 408, 443, 431, 437, 524,
    },

    tank = 432,   -- Rhino (act_train_spawnVeh_Tank*)

    -- ped skins for act_train_spawnPed*
    skins = { 0, 7, 23, 29, 60, 105, 126, 162, 230, 249 },

    -- ms until a train-spawned vehicle / ped is auto-removed (0 = keep forever)
    cleanup = 30000,

    -- act_train_speed_150 (exports.ai_autoplayer:setTrainAutoSpeed)
    speedBoost         = 150,
    speedNormal        = 80,
    speedBoostDuration = 10000,   -- ms before it drops back to speedNormal
}
