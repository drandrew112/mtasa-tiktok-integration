# tiktok

TikTok LIVE → MTA:SA. Gifts / likes / follows in a TikTok live trigger in‑game
events on one specific player (the streamer's character).

```
TikTok LIVE ──ws──▶ Node.js bridge (bridge/) ──HTTP──▶ MTA resource ──▶ onTikTok* events + actions
                    queue + ring buffer        1s poll / cursor
```

The **bridge** is a small standalone Node.js process that connects to the TikTok
live feed and exposes the events over local HTTP. The **MTA resource** polls that
HTTP endpoint once per second and turns the events into gameplay.

---

## Requirements

- **Node.js 18+** (for the bridge)
- **MTA:SA server 1.5.9+** (server‑side `createProjectile` and `setElementAngularVelocity` are used)
- The **`ui_core`** resource (for on‑screen notifications) — the meta declares
  `<include resource="ui_core" />`
- A machine that runs the bridge next to the MTA server (they talk over `127.0.0.1`)
- Optional but recommended: an [EulerStream](https://www.eulerstream.com/) sign
  API key for a stable TikTok connection

---

## 1. Bridge setup (`bridge/`)

### 1.1 Install

```bash
cd bridge
npm install
```

### 1.2 Create the config

`bridge/config.json` is **git‑ignored**. Copy the template and edit it:

```bash
cp config.example.json config.json      # Windows: copy config.example.json config.json
```

| Key | Meaning |
|---|---|
| `tiktokUsername` | **Which live to watch** (e.g. `drandrew112`). This is the only place the TikTok username lives. |
| `httpHost` / `httpPort` | Where the bridge HTTP API listens. Keep `127.0.0.1` (same machine as MTA). |
| `sharedSecret` | Any random string. Must match the `*bridge_secret` setting in `meta.xml`. |
| `bufferSize` | Max events kept in memory (oldest dropped first). |
| `reconnectDelayMs` | Wait before reconnecting when the live is offline / ends. |
| `signApiKey` | EulerStream sign key. **Leave empty** and use the env var instead (below), or paste it here for a quick local test. |
| `debugSamples` | `true` writes one raw sample per event type to `bridge/debug-samples.json` (useful for checking gift names). |
| `enableExtendedGiftInfo` | Keep `false` (see Troubleshooting). |

### 1.3 EulerStream API key (env)

The key is read from the `SIGN_API_KEY` environment variable first, then from
`config.json`. Recommended: keep `"signApiKey": ""` in the config and set the env var.

**PowerShell – persistent (applies to new processes / `start.bat`):**

```powershell
[Environment]::SetEnvironmentVariable('SIGN_API_KEY', 'euler_YOUR_KEY_HERE', 'User')
```

**PowerShell – current session only:**

```powershell
$env:SIGN_API_KEY = 'euler_YOUR_KEY_HERE'
```

After the persistent variant you must open a **new** terminal / restart `start.bat`.

### 1.4 Run

```bat
bridge\start.bat
```

`start.bat` restarts the bridge if it crashes. Or run it directly:

```bash
node bridge/index.js
```

For production, use a service wrapper (nssm, pm2, Windows Task Scheduler).

The bridge log tells you whether it connected:

```
[bridge ...] HTTP API on http://127.0.0.1:8085  (username=@drandrew112)
[bridge ...] Connected. roomId=...
```

`UserOfflineError` just means the streamer isn't live right now; it keeps retrying.

### HTTP API

- `GET /health` → `{ ok, live, connectionState, roomId, lastId, bufferedEvents, ... }`
- `GET /events?after=<id>` → `{ ok, live, lastId, count, events: [...] }`
  Requires header `X-Bridge-Secret: <sharedSecret>`. Returns only events with `id > after`.

---

## 2. Resource setup

### 2.1 Settings (`meta.xml`)

```xml
<setting name="*bridge_url"    value="http://127.0.0.1:8085" />
<setting name="*bridge_secret" value="..." />   <!-- must equal bridge/config.json sharedSecret -->
<setting name="*poll_interval" value="1000" />
<setting name="*debug"         value="false" />  <!-- true: verbose log + example.lua handlers -->
```

### 2.2 Target player (`server/config.lua`)

```lua
TikTok.TARGET_PLAYER_NAME = "DrAndrew112"   -- MTA player name (NOT the TikTok username)
```

This is the in‑game player that every gift / like / follow action affects. If no
player with that name is online, it falls back to the first connected player
(handy for testing).

### 2.3 Start

```
start tiktok
```

in the MTA server console (make sure `ui_core` is also running).

### How the poller works

1. On start it calls `/health` once to sync its cursor to the bridge's current
   `lastId` (so it doesn't replay old buffered events).
2. Every `poll_interval` ms it calls `/events?after=<cursor>`, dispatches each
   event, and advances the cursor **only** on a fully successful response. A
   failed request just retries the same range next tick — nothing is lost while
   the bridge buffer hasn't rolled over.
3. It skips a tick if the previous request is still in flight (no overlap).

---

## 3. Files

| File | Role |
|---|---|
| `shared/lists.lua` | shared data lists (loads first): `TikTok.NAMES`/`randomName()`, `VEHICLE_MODELS`/`randomVehicleModel()`, `ENEMY_MODELS`, `ENEMY_WEAPONS`, `CAR_MODELS`, `PLANE_MODELS`, `BLACKHOLE_MODELS`, `AIRPORTS`, `BAD_SKINS`/`randomSkin()` |
| `server/config.lua` | settings, `TikTok.log`, `TikTok.getTargetPlayer()`, `TARGET_PLAYER_NAME` |
| `server/poller.lua` | HTTP poll → `TikTok.dispatch` |
| `server/dispatch.lua` | event → `onTikTok*` trigger |
| `server/gift_handler.lua` | **gift → action** (`GIFT_ACTIONS`) |
| `server/like_handler.lua` | like burst + milestone actions |
| `server/follower_handler.lua` | follow → action |
| `server/enemies.lua` | `TikTok.spawnEnemies` / `clearEnemies` (ped AI is client‑side: `client/enemy_ai.lua`) |
| `server/enemy_cars.lua` | `TikTok.spawnEnemyCar` / `clearEnemyCars` (AI: `client/enemy_car_ai.lua`) |
| `server/spawn_timers.lua` | every 10 min a tank, every 5 min an enemy wave |
| `server/loadout.lua` | gives players an MP5 (spawn + resource start) |
| `server/cleanup.lua` | `TikTok.cleanupAll()` when the target dies (vehicles + peds + enemy AI stop) |
| `server/notify.lua` → `client/notify.lua` | notifications via `ui_core` |
| `client/hud_timers.lua` | bottom‑center: "TANK SPAWN" / "ENEMY WAVE" countdown |
| `client/hud_legend.lua` | top‑left: what each gift/like does (viewer overlay). Off by default (`enableLegend`). |
| `client/gift_effects.lua` | black hole gravity + smoke grenades (client) |
| `server/example.lua` | logs events when `*debug` is `true`; safe to delete |

---

## 4. What the events do

### Gift → action (`server/gift_handler.lua` : `GIFT_ACTIONS`)

The **gift name** (lowercased) decides. No categories. A value can be one
function or `{ fn1, fn2 }` (random one of the two).

| Gift | ~coins | Action |
|---|---|---|
| **Rose** | 1 | swap the player's vehicle for a random one (seat as driver) |
| **GG** | 1 | drop a random vehicle on their head **OR** lift vehicle/player +5 (random) |
| **Finger Heart** | 5 | 1 chasing enemy ped **OR** 1 chasing enemy car (random) |
| **Perfume** | 20 | small plane crashes ~22 units in front of the player |
| **Doughnut** | 30 | teleport to a random airport (`TikTok.AIRPORTS`) |
| **Corgi** | 299 | black hole: 9s of being sucked up, then explosion + **death** |

Unknown gift → only logged: `unmapped gift: '<name>' (id=X)`. Adjust the
`GIFT_ACTIONS` keys to the real names, or fill in `GIFT_ACTIONS_BY_ID`.

### Like

**Burst** — by a single like‑event's batch size (`data.likeCount`), `LIKE_BURST_ACTS`:

| batch | action |
|---|---|
| 1–4 | randomize all 4 vehicle colors; on foot → random player skin |
| 5–10 | smoke / teargas grenades on the player |
| 11–20 | 1 chasing enemy ped |

**Milestones** — by total likes (`INTERVAL_ACTS`, `COUNT_MODE = "session"` → counted
from when the resource connected):

| every | action |
|---|---|
| 1 000 | 4 random vehicles around the player |
| 5 000 | launch the player's vehicle up; no vehicle → the player dies |
| 10 000 | if in a vehicle → the vehicle explodes; on foot → the player dies |

Exact one‑time milestones: `MILESTONE_ACTS` (empty by default).

### Follow (`server/follower_handler.lua`)

Every follow → random: **1 chasing enemy ped** or **1 enemy car** (named after the follower).

### Periodic (`server/spawn_timers.lua`)

- **every 10 minutes:** a Rhino tank for the target player (seats them, deletes their old vehicle)
- **every 5 minutes:** an enemy wave → 3 sub‑waves 5s apart, 5 enemies per sub‑wave

### Loadout (`server/loadout.lua`)

Every player gets an **MP5** on resource start and on every respawn.

### Enemy peds / enemy cars

- **Ped:** spawns 6–12 units away, armed; the target's client makes it chase to 3
  units and shoot (`client/enemy_ai.lua`). Nametag = the event sender's name
  (nil → random). Dies on its own after 3 minutes. `MAX_ENEMIES = 20`.
- **Car:** black fast car + driver, damage‑proof, chases continuously, eases to a
  stop near the player. Disappears after 2 minutes. `MAX_CARS = 4`; when full it
  spawns 3 peds instead.
- When the target dies / disconnects, all peds + cars belonging to them are removed.

---

## 5. Events for other resources

They bubble from the `tiktok` resource, so you can also listen on `root`:

```lua
addEventHandler("onTikTokGift", root, function(data) ... end)
```

| Event | Extra fields |
|---|---|
| `onTikTokGift` | `giftId`, `giftName`, `diamondCount`, `repeatCount`, `repeatEnd`, `giftType`, `streakable`, `final`, `totalDiamondCount`, `toUserId` |
| `onTikTokFollow` | – |
| `onTikTokLike` | `likeCount` (batch), `totalLikeCount` (room total) |
| `onTikTokShare` | `shareCount` |
| `onTikTokStatus` | `state` = `connected` / `disconnected` / `streamEnd` / `error`, `roomId`, `message` |
| `onTikTokEvent` | firehose: `(eventType, data)` |
| `onTikTokGiftAction` | `(giftName, ctx)` — when a mapped action runs |
| `onTikTokLikeMilestone` | `(milestone, ctx)` |
| `onTikTokFollowAct` | `(ctx)` |

Every `data.user` = `{ userId, uniqueId, nickname, profilePicture }`.

**Gift streaks:** a streakable gift (`giftType == 1`) fires multiple times;
`final == true` only on the settled event. For a one‑time reward:
`if not data.final then return end`.

### Exports

```lua
exports.tiktok:isTikTokLive()      -- boolean
exports.tiktok:getTikTokStatus()   -- { live, bridgeUrl, pollInterval, debug }
```

---

## 6. Test commands (admin / server console)

| Command | What |
|---|---|
| `/tiktokgift <name>` | fake gift (e.g. `/tiktokgift rose`); no argument lists the mapped gifts |
| `/tiktokgiftall` | run every mapped gift, one after another |
| `/tiktoklike <n>` | jump total likes to n (milestones) |
| `/tiktoklikeadd <n>` | add n likes |
| `/tiktoklikeburst <n>` | one like event with batch size n (burst acts) |
| `/tiktoklikereset` | reset the like counter + fired milestones |
| `/tiktokfollow` | fake follow |
| `/tiktokenemy [count]` | spawn enemy ped(s) |
| `/tiktokenemycar` | spawn an enemy car |
| `/tiktokclearenemy` / `/tiktokclearcars` / `/tiktokclear` | cleanup |
| `/tiktokenemydebug` | client: toggle enemy‑AI debug output |

---

## 7. Tuning reference

| What | Where |
|---|---|
| Gift → action mapping | `server/gift_handler.lua` : `GIFT_ACTIONS` / `GIFT_ACTIONS_BY_ID` |
| Black hole height / duration / pull | `server/gift_handler.lua` top |
| Plane impact distance | `server/gift_handler.lua` : `PLANE_IMPACT_DIST` |
| Like burst ranges / milestones | `server/like_handler.lua` : `LIKE_BURST_ACTS`, `INTERVAL_ACTS`, `MILESTONE_ACTS` |
| Like counting mode | `server/like_handler.lua` : `COUNT_MODE` (`session` / `absolute`) |
| Enemy count cap / lifetime / spawn radius | `server/enemies.lua` top |
| Enemy chase distance / range / speed | `client/enemy_ai.lua` top |
| Enemy car count / lifetime / fallback | `server/enemy_cars.lua` top |
| Enemy car speed / accel / turn | `client/enemy_car_ai.lua` top |
| Timer intervals / wave size | `server/spawn_timers.lua` top |
| Tank model | `server/spawn_timers.lua` : `VEHICLE_MODEL` |
| Loadout weapon / ammo | `server/loadout.lua` top |
| Notification toggles | `server/notify.lua` : `NOTIFY` |
| HUD size / position | `client/hud_timers.lua` / `client/hud_legend.lua` top |
| Model / name / airport lists | `shared/lists.lua` |

---

## 8. Troubleshooting

- **`UserOfflineError` in the bridge log** — the streamer isn't live; the bridge
  keeps retrying every `reconnectDelayMs`.
- **`onTikTokStatus` never becomes `connected`** — is the bridge running? Do
  `*bridge_url` / `*bridge_secret` match `bridge/config.json`?
- **MTA log: fetchRemote errors** — check the port and that MTA can reach `127.0.0.1`.
- **Unknown gift names** — set `debugSamples: true`, capture a live session, check
  `bridge/debug-samples.json`, then adjust the `GIFT_ACTIONS` keys (or `index.js`
  extractors).
- **`SignatureMissingTokensError ... requires a Business plan`** — caused by
  `enableExtendedGiftInfo`. Keep it `false` (gift name + coins still arrive via
  `giftDetails` on each gift message).

---

## 9. Known limitations

- **Enemy ped shooting:** an MTA `createPed` ped doesn't enter combat mode on its
  own, so the "fire" control doesn't always deal real damage (visuals + sound are
  there). A hitscan pass is planned.
- **Client‑only MTA functions** (`setPedControlState`, `createProjectile`,
  `isLineOfSightClear`, `fxAdd*`) are why the enemy/car AI and the smoke grenades
  run on the client.
- **Enemy car / plane crash** use a forced velocity vector, so on slopes they can
  look a bit "floaty" — but they always reach the target.
- The `*bridge_secret` / `sharedSecret` is a **localhost** handshake token — low
  risk, but you can rotate it.

---

## 10. Git

- `.gitignore` is in the resource root.
- **Not committed:** `bridge/node_modules/`, `bridge/config.json` (has your secret),
  `bridge/debug-samples.json`, `*.log`, `*.zip`.
- **Committed:** `bridge/config.example.json` as the template.
- The EulerStream key comes from the `SIGN_API_KEY` env var — it is never in the repo.

After cloning:

```bash
cd bridge && npm install
cp config.example.json config.json      # then edit tiktokUsername + sharedSecret
```

set `SIGN_API_KEY` (section 1.3), set `*bridge_secret` in `meta.xml` to match, and
`start tiktok`.
