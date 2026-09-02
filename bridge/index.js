'use strict';

/*
 * TikTok LIVE -> MTA:SA bridge
 * ---------------------------------
 * - Connects to a TikTok LIVE room via tiktok-live-connector.
 * - Normalizes gift / follow / like / share events into small plain objects.
 * - Keeps them in an in-memory ring buffer, each with an increasing `id`.
 * - Exposes an HTTP API the MTA resource polls once per second:
 *     GET /health                 -> status + current lastId (cursor sync)
 *     GET /events?after=<id>       -> events with id > after   (requires X-Bridge-Secret)
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const {
  TikTokLiveConnection,
  WebcastEvent,
  ControlEvent,
  SignConfig,
} = require('tiktok-live-connector');

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

let fileCfg = {};
try {
  fileCfg = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
} catch (err) {
  console.warn('[bridge] config.json not found or invalid, using defaults/env only:', err.message);
}

const config = {
  tiktokUsername: process.env.TIKTOK_USERNAME || fileCfg.tiktokUsername || 'drandrew112',
  httpHost: process.env.BRIDGE_HOST || fileCfg.httpHost || '127.0.0.1',
  httpPort: parseInt(process.env.BRIDGE_PORT || fileCfg.httpPort || 8085, 10),
  sharedSecret: process.env.BRIDGE_SECRET || fileCfg.sharedSecret || '',
  bufferSize: parseInt(fileCfg.bufferSize || 1000, 10),
  reconnectDelayMs: parseInt(fileCfg.reconnectDelayMs || 5000, 10),
  // EulerStream sign key: SIGN_API_KEY env var first, then config.json "signApiKey".
  signApiKey: process.env.SIGN_API_KEY || fileCfg.signApiKey || '',
  debugSamples: fileCfg.debugSamples === true,
  // Fetching the room gift list on connect requires signing an extra webcast URL,
  // which needs an EulerStream Business plan. Off by default; gift name + diamond
  // count still arrive via each gift message's `giftDetails` field.
  enableExtendedGiftInfo: fileCfg.enableExtendedGiftInfo === true,
};

if (config.signApiKey) {
  SignConfig.apiKey = config.signApiKey;
}

function log(...args) {
  console.log(`[bridge ${new Date().toISOString()}]`, ...args);
}

// ---------------------------------------------------------------------------
// Value helpers (protobuf objects can contain BigInt / huge ids)
// ---------------------------------------------------------------------------

const asString = (v) => (v === undefined || v === null || v === '' ? null : String(v));

const asNumber = (v) => {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};

const asBool = (v) => v === true || v === 1 || v === '1';

function pickImageUrl(img) {
  if (!img) return null;
  const list = img.url || img.urlList || img.urlListList || img.urls;
  if (Array.isArray(list) && list.length) return String(list[list.length - 1]);
  if (typeof img === 'string') return img;
  return null;
}

function extractUser(d) {
  const u = (d && d.user) || {};
  return {
    userId: asString(u.userId || u.id),
    uniqueId: u.uniqueId || u.displayId || null,
    nickname: u.nickname || null,
    profilePicture: pickImageUrl(u.profilePicture || u.profilePictureMedium || u.avatarThumb || u.profilePictureLarge),
  };
}

// ---------------------------------------------------------------------------
// Event queue (ring buffer with monotonically increasing id)
// ---------------------------------------------------------------------------

let seq = 0;
const queue = [];

function enqueue(type, payload) {
  seq += 1;
  const evt = Object.assign({ id: seq, type, ts: Date.now() }, payload);
  queue.push(evt);
  while (queue.length > config.bufferSize) queue.shift();
  state.lastEventAt = evt.ts;
  if (config.debugSamples) dumpSample(type, payload);
  return evt;
}

const state = {
  live: false,
  connectionState: 'idle',
  roomId: null,
  connectedSince: null,
  lastEventAt: null,
  startedAt: Date.now(),
};

// One raw sample per event type, for figuring out real field shapes.
const seenSamples = new Set();
function dumpSample(type, payload) {
  if (seenSamples.has(type)) return;
  seenSamples.add(type);
  try {
    fs.appendFileSync(
      path.join(__dirname, 'debug-samples.json'),
      JSON.stringify({ type, payload }, (k, v) => (typeof v === 'bigint' ? v.toString() : v), 2) + '\n',
    );
  } catch (_) { /* ignore */ }
}

// ---------------------------------------------------------------------------
// TikTok connection
// ---------------------------------------------------------------------------

const connection = new TikTokLiveConnection(config.tiktokUsername, {
  processInitialData: false,      // don't replay the backlog burst on connect
  fetchRoomInfoOnConnect: true,   // throw UserOfflineError if not live
  enableExtendedGiftInfo: config.enableExtendedGiftInfo, // needs EulerStream Business plan
  signApiKey: config.signApiKey || undefined,
});

const firstDefined = (...vals) => vals.find((v) => v !== undefined && v !== null);

connection.on(WebcastEvent.GIFT, (d) => {
  const details = d.giftDetails || d.gift || d.extendedGiftInfo || {};
  const giftType = asNumber(firstDefined(d.giftType, details.giftType, details.gift_type));
  const repeatCount = asNumber(d.repeatCount) || 1;
  const repeatEnd = asBool(d.repeatEnd);
  const streakable = giftType === 1;
  const isFinal = !streakable || repeatEnd;
  const diamondCount = asNumber(firstDefined(details.diamondCount, details.diamond_count, d.diamondCount));

  enqueue('gift', {
    user: extractUser(d),
    giftId: asNumber(firstDefined(d.giftId, details.id)),
    giftName: firstDefined(details.giftName, details.name, d.giftName) || null,
    diamondCount,
    repeatCount,
    repeatEnd,
    giftType,
    streakable,
    // true only for the settled gift (non-streak, or the last tick of a combo).
    // Consumers that only want to reward once should check `final`.
    final: isFinal,
    totalDiamondCount: diamondCount != null ? diamondCount * repeatCount : null,
    toUserId: d.toUser ? asString(d.toUser.userId) : null,
  });
});

connection.on(WebcastEvent.LIKE, (d) => {
  enqueue('like', {
    user: extractUser(d),
    // decoded proto uses `count` / `total` (not the d.ts names likeCount/totalLikeCount)
    likeCount: asNumber(firstDefined(d.count, d.likeCount)),        // likes in this batch
    totalLikeCount: asNumber(firstDefined(d.total, d.totalLikeCount)), // running room total
  });
});

connection.on(WebcastEvent.FOLLOW, (d) => {
  enqueue('follow', { user: extractUser(d) });
});

connection.on(WebcastEvent.SHARE, (d) => {
  enqueue('share', {
    user: extractUser(d),
    shareCount: asNumber(d.shareCount),
  });
});

// ---- connection lifecycle ----

let reconnectTimer = null;

function scheduleReconnect(reason) {
  if (reconnectTimer) return;
  log(`Reconnecting in ${config.reconnectDelayMs}ms (${reason})`);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, config.reconnectDelayMs);
}

async function connect() {
  state.connectionState = 'connecting';
  try {
    log(`Connecting to @${config.tiktokUsername} ...`);
    const s = await connection.connect();
    state.live = true;
    state.connectionState = 'connected';
    state.roomId = asString(s && (s.roomId || s.roomInfo && s.roomInfo.roomId)) || state.roomId;
    state.connectedSince = Date.now();
    log(`Connected. roomId=${state.roomId}`);
    enqueue('status', { state: 'connected', roomId: state.roomId });
  } catch (err) {
    state.live = false;
    state.connectionState = 'error';
    const msg = (err && err.message) || String(err);
    log(`Connect failed: ${msg}`);
    enqueue('status', { state: 'error', message: msg });
    scheduleReconnect('connect failed');
  }
}

connection.on(ControlEvent.DISCONNECTED, () => {
  state.live = false;
  state.connectionState = 'disconnected';
  log('Disconnected.');
  enqueue('status', { state: 'disconnected' });
  scheduleReconnect('disconnected');
});

connection.on(WebcastEvent.STREAM_END, () => {
  state.live = false;
  state.connectionState = 'streamEnd';
  log('Stream ended.');
  enqueue('status', { state: 'streamEnd' });
  scheduleReconnect('stream ended');
});

connection.on(ControlEvent.ERROR, (err) => {
  log('Connection error:', (err && err.message) || err);
});

// ---------------------------------------------------------------------------
// HTTP API
// ---------------------------------------------------------------------------

function sendJson(res, status, body) {
  const text = JSON.stringify(body, (k, v) => (typeof v === 'bigint' ? v.toString() : v));
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(text);
}

const server = http.createServer((req, res) => {
  let url;
  try {
    url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  } catch (_) {
    return sendJson(res, 400, { ok: false, error: 'bad request' });
  }

  if (req.method !== 'GET') {
    return sendJson(res, 405, { ok: false, error: 'method not allowed' });
  }

  if (url.pathname === '/health') {
    return sendJson(res, 200, {
      ok: true,
      live: state.live,
      connectionState: state.connectionState,
      username: config.tiktokUsername,
      roomId: state.roomId,
      bufferedEvents: queue.length,
      lastId: seq,
      connectedSince: state.connectedSince,
      lastEventAt: state.lastEventAt,
      uptimeSec: Math.floor((Date.now() - state.startedAt) / 1000),
    });
  }

  if (url.pathname === '/events') {
    if (config.sharedSecret && req.headers['x-bridge-secret'] !== config.sharedSecret) {
      return sendJson(res, 401, { ok: false, error: 'unauthorized' });
    }
    const after = parseInt(url.searchParams.get('after') || '0', 10) || 0;
    const events = queue.filter((e) => e.id > after);
    return sendJson(res, 200, {
      ok: true,
      live: state.live,
      serverTime: Date.now(),
      lastId: seq,
      count: events.length,
      events,
    });
  }

  return sendJson(res, 404, { ok: false, error: 'not found' });
});

server.on('error', (err) => {
  log('HTTP server error:', err.message);
  process.exit(1);
});

server.listen(config.httpPort, config.httpHost, () => {
  log(`HTTP API on http://${config.httpHost}:${config.httpPort}  (username=@${config.tiktokUsername})`);
  if (!config.sharedSecret) log('WARNING: sharedSecret is empty - /events is unauthenticated.');
  if (!config.signApiKey) log('WARNING: no signApiKey set - connection may be rate limited / unreliable.');
  connect();
});

// ---------------------------------------------------------------------------
// Shutdown
// ---------------------------------------------------------------------------

function shutdown() {
  log('Shutting down...');
  try { connection.disconnect(); } catch (_) { /* ignore */ }
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 2000).unref();
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
process.on('uncaughtException', (err) => {
  log('uncaughtException:', err && err.stack ? err.stack : err);
});
process.on('unhandledRejection', (err) => {
  log('unhandledRejection:', err && err.stack ? err.stack : err);
});
