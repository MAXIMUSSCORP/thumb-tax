// WatchLock server, zero dependencies, Node 18+. Contract v2: the server is the bank.
// It holds balanceSec; the watch, the panel and iOS send transactions to /ledger.
// taxMinutes and creditMinutes are derived on every response, never stored.
//
//   GET  /health  -> {ok:true}
//   GET  /state   -> full state
//   POST /state   -> {activity, pendingChargeSec, source}, at least one of the first two
//   POST /ledger  -> {deltaSec, reason, source, session?, eventId?, activity?, pendingChargeSec?}
//   POST /usage   -> {usedMinutesToday 0..1440, day?, reset?}
//   POST /badge   -> {id}, demo: asks the watch to unlock a badge (badgeCommand)
//   GET  /        -> control panel
//
// Env: PORT (default 48217), API_KEY (default "group16"; header "x-api-key" or "?key=" on /state, /ledger and /usage;
// set it to "" to turn the key off),
// LOCAL_NO_KEY (default 1; 0 = loopback requests need the key too),
// DATA_FILE (default ./state.json, or /data/state.json on Railway when a volume is mounted).

const http = require("http");
const fs = require("fs");
const os = require("os");
const path = require("path");

const PORT = process.env.PORT || 48217;
// Defaults to the team key the watch sends; set API_KEY to override, or API_KEY="" to require no key.
const API_KEY = process.env.API_KEY ?? "group16";
const LOCAL_NO_KEY = process.env.LOCAL_NO_KEY !== "0"; // loopback requests skip the key; "0" turns that off
const RAILWAY = !!process.env.RAILWAY_ENVIRONMENT;
// On Railway, use a mounted volume at /data if present; otherwise state is ephemeral.
const DATA_FILE =
  process.env.DATA_FILE || (RAILWAY && fs.existsSync("/data") ? "/data/state.json" : path.join(__dirname, "state.json"));

const pad = (n) => String(n).padStart(2, "0");
function today() {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

// Real calendar date that is yesterday, today or tomorrow locally (phone clocks drift across midnight).
function nearToday(day) {
  const ok = [-1, 0, 1].map((o) => {
    const d = new Date();
    d.setDate(d.getDate() + o);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  });
  return ok.includes(day);
}

const newEpoch = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 6);

let state = {
  usageEpoch: newEpoch(), // changes only on reset:true; tells the watch to rebaseline
  balanceSec: 0, // signed: positive = credit, negative = debt
  pendingChargeSec: 0, // reported by the watch: counted but not yet charged
  history: [], // last 20, newest first
  ledgerSessions: {}, // {source: {session, lastEventId}}
  activity: null,
  badgeCommand: null, // {seq, id, at}: last demo unlock request; the watch acts when seq grows
  usedMinutesToday: 0,
  usageDay: today(),
  usageUpdatedAt: null,
  source: "default",
  updatedAt: new Date().toISOString(),
};

try {
  const saved = JSON.parse(fs.readFileSync(DATA_FILE, "utf8"));
  if (typeof saved.taxMinutes === "number" || typeof saved.balanceSec === "number") {
    state = { ...state, ...saved };
    if (typeof saved.balanceSec !== "number") state.balanceSec = ((saved.creditMinutes || 0) - (saved.taxMinutes || 0)) * 60;
    delete state.taxMinutes;
    delete state.creditMinutes;
    if (!Array.isArray(state.history)) state.history = [];
    if (!state.ledgerSessions || typeof state.ledgerSessions !== "object") state.ledgerSessions = {};
  }
} catch (e) {
  if (e.code !== "ENOENT") console.error("could not load", DATA_FILE, "starting from defaults:", e.message);
}

// Atomic write; on failure (OneDrive EBUSY/EPERM) keep serving from memory.
function save() {
  try {
    fs.writeFileSync(DATA_FILE + ".tmp", JSON.stringify(state));
    fs.renameSync(DATA_FILE + ".tmp", DATA_FILE);
  } catch (e) {
    console.error("save failed, serving from memory:", e.message);
  }
}

save(); // persist a freshly generated usageEpoch (and a migration)

// What clients see: derived tax/credit, history capped at 10, no ledgerSessions.
function view() {
  const { ledgerSessions, ...rest } = state;
  const eff = state.balanceSec - state.pendingChargeSec;
  return {
    ...rest,
    effectiveSec: eff, // balanceSec minus pendingChargeSec; clients use this, not their own math
    taxMinutes: Math.ceil(Math.max(0, -eff) / 60),
    creditMinutes: Math.floor(Math.max(0, eff) / 60),
    history: state.history.slice(0, 10),
  };
}

function roll() {
  const t = today();
  if (t > state.usageDay) {
    state.usedMinutesToday = 0;
    state.usageDay = t;
    save();
  }
}

// Returns a number >= 0 (rounded), or null if absent or not numeric.
function num(v) {
  if (v === undefined || v === null || v === "" || typeof v === "boolean") return null;
  const n = Number(v);
  return Number.isFinite(n) ? Math.max(0, Math.round(n)) : null;
}

// Sets activity and pendingChargeSec when present; returns true if either was.
function setWatchFields(body) {
  const pending = num(body.pendingChargeSec);
  const hasActivity = typeof body.activity === "string" || body.activity === null;
  if (pending === null && !hasActivity) return false;
  if (pending !== null) state.pendingChargeSec = pending;
  if (hasActivity) state.activity = body.activity ? body.activity.slice(0, 120) : null;
  return true;
}

function applyUpdate(body) {
  if (!setWatchFields(body)) return null;
  state.source = typeof body.source === "string" && body.source ? body.source : "watch";
  state.updatedAt = new Date().toISOString();
  save();
  console.log(state.updatedAt, "pending =", state.pendingChargeSec, "activity =", state.activity, "from", state.source);
  return view();
}

const SOURCES = ["watch", "panel", "ios"];
function applyLedger(body) {
  const d = body.deltaSec;
  if (!Number.isInteger(d) || d === 0 || Math.abs(d) > 86400) return { code: 400, body: { error: "deltaSec must be a non-zero integer, at most 86400 either way" } };
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  if (reason.length < 1 || reason.length > 60) return { code: 400, body: { error: "reason must be 1..60 characters" } };
  const src = body.source;
  if (!SOURCES.includes(src)) return { code: 400, body: { error: "source must be watch, panel or ios" } };
  const last = () => (state.ledgerSessions[src] ? state.ledgerSessions[src].lastEventId : null);
  const dedupe = typeof body.session === "string" && body.session !== "" && Number.isInteger(body.eventId);
  if (dedupe) {
    const cur = state.ledgerSessions[src];
    if (cur && cur.session === body.session && body.eventId <= cur.lastEventId) {
      return { code: 200, body: { ...view(), applied: false, lastEventId: last() } };
    }
    state.ledgerSessions[src] = { session: body.session, lastEventId: body.eventId };
  }
  const now = new Date().toISOString();
  state.balanceSec += d;
  state.history = [{ t: now, deltaSec: d, reason, source: src }, ...state.history].slice(0, 20);
  setWatchFields(body);
  state.source = src;
  state.updatedAt = now;
  save();
  console.log(now, "ledger", d, "s", reason, "from", src, "balance =", state.balanceSec);
  return { code: 200, body: { ...view(), applied: true, lastEventId: last() } };
}

function applyUsage(body) {
  roll();
  const v = body.usedMinutesToday;
  const n = typeof v === "number" || (typeof v === "string" && v.trim() !== "") ? Number(v) : NaN;
  if (!Number.isFinite(n) || n < 0 || n > 1440) return { code: 400, body: { error: "usedMinutesToday must be a number 0..1440" } };
  const day = body.day === undefined || body.day === null ? today() : body.day;
  if (typeof day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(day)) return { code: 400, body: { error: "day must be YYYY-MM-DD" } };
  if (!nearToday(day)) return { code: 400, body: { error: "bad day" } };
  const used = Math.round(n);
  const conflict = (error) => ({ code: 409, body: { error, usageDay: state.usageDay, usedMinutesToday: state.usedMinutesToday } });
  if (day < state.usageDay) return conflict("stale day");
  if (day === state.usageDay && used < state.usedMinutesToday && body.reset !== true) return conflict("decrease");
  if (body.reset === true) state.usageEpoch = newEpoch();
  state.usageDay = day;
  state.usedMinutesToday = used;
  state.usageUpdatedAt = new Date().toISOString();
  save();
  return { code: 200, body: view() };
}

// Same id strings and names as the watch's Badges.mc (STRS and DEFS), in the same order.
const BADGE_IDS = {
  fc: "First Clean Close", pw: "Perfect Week", ls: "Longest Streak", d1: "100 Clean Days", d3: "365 Clean Days",
  d5: "500 Clean Days", dk: "1,000 Clean Days", sm: "Screen-Free Morning", ds: "Digital Sunset", pa: "Perfect Analog Week",
  dw: "Deep Work 100", af: "Analog Fondo", wo: "Weekend Off-Grid", r1: "Time Reclaimed: 10 h", r2: "Time Reclaimed: 25 h",
  r5: "Time Reclaimed: 50 h", ll: "Local Legend", dd: "Dopamine Detour", fu: "The Festive Unplug", sr: "Sunday Reset",
};

function applyBadge(body) {
  const id = body.id;
  if (typeof id !== "string" || !Object.hasOwn(BADGE_IDS, id)) return { code: 400, body: { error: "unknown badge" } };
  state.badgeCommand = { seq: (state.badgeCommand ? state.badgeCommand.seq : 0) + 1, id, at: new Date().toISOString() };
  save();
  console.log(state.badgeCommand.at, "badge request", id, "#" + state.badgeCommand.seq);
  return { code: 200, body: view() };
}

function send(res, code, body, type = "application/json") {
  if (code >= 400) console.warn(res.req.method, res.req.url, code, body && body.error);
  res.writeHead(code, {
    "Content-Type": type,
    "Cache-Control": "no-store",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "content-type,x-api-key",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  });
  res.end(code === 204 ? undefined : type === "application/json" ? JSON.stringify(body) : body);
}

// cloudflared reaches us over loopback too, but always adds one of these headers.
const PROXY_HEADERS = ["cf-connecting-ip", "cf-ray", "x-forwarded-for", "x-real-ip", "forwarded"];
function isLocal(req) {
  const a = req.socket.remoteAddress;
  return (a === "127.0.0.1" || a === "::1" || a === "::ffff:127.0.0.1") && !PROXY_HEADERS.some((h) => h in req.headers);
}

function authorized(req, url) {
  if (!API_KEY) return true;
  if (LOCAL_NO_KEY && isLocal(req)) return true;
  return req.headers["x-api-key"] === API_KEY || url.searchParams.get("key") === API_KEY;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = "";
    let big = false;
    req.on("error", reject);
    req.on("data", (c) => {
      if (big) return;
      raw += c;
      if (raw.length > 1e5) {
        big = true;
        raw = "";
        reject(Object.assign(new Error("body too large"), { code: 413 }));
      }
    });
    req.on("end", () => {
      if (big) return;
      if (!raw) return resolve({});
      try {
        const j = JSON.parse(raw);
        resolve(j && typeof j === "object" ? j : {});
      } catch (_) {
        console.warn("invalid JSON body, parsing as form data");
        resolve(Object.fromEntries(new URLSearchParams(raw))); // form-encoded fallback
      }
    });
  });
}

process.on("unhandledRejection", (e) => console.error("unhandledRejection:", e));
process.on("uncaughtException", (e) => console.error("uncaughtException:", e));

const server = http.createServer(async (req, res) => {
  try {
    await handle(req, res);
  } catch (e) {
    if (e && e.code === 413) return send(res, 413, { error: "body too large" });
    console.error("handler error:", e);
    if (!res.headersSent) send(res, 500, { error: "internal" });
    else res.end();
  }
});

async function handle(req, res) {
  const url = new URL(req.url, "http://localhost");
  const p = url.pathname.replace(/\/+$/, "") || "/";

  if (req.method === "OPTIONS") return send(res, 204);
  if (p === "/health") return send(res, 200, { ok: true });
  if (p === "/" && req.method === "GET") return send(res, 200, PANEL_HTML, "text/html; charset=utf-8");

  if (!authorized(req, url)) return send(res, 401, { error: "bad or missing API key" });

  if (p === "/state" && req.method === "GET") {
    roll();
    return send(res, 200, view());
  }
  if (p === "/state" && req.method === "POST") {
    const result = applyUpdate(await readBody(req));
    if (!result) return send(res, 400, { error: "send activity and/or pendingChargeSec" });
    return send(res, 200, result);
  }
  if (p === "/ledger" && req.method === "POST") {
    const r = applyLedger(await readBody(req));
    return send(res, r.code, r.body);
  }
  if (p === "/usage" && req.method === "POST") {
    const r = applyUsage(await readBody(req));
    return send(res, r.code, r.body);
  }

  if (p === "/badge" && req.method === "POST") {
    const r = applyBadge(await readBody(req));
    return send(res, r.code, r.body);
  }

  send(res, 404, { error: "not found" });
}

server.listen(PORT, "0.0.0.0", () => {
  if (RAILWAY) {
    const d = process.env.RAILWAY_PUBLIC_DOMAIN;
    console.log(d ? `Railway: https://${d}` : "Railway: no public domain yet");
    if (!API_KEY) console.warn("WARNING: no API_KEY set on a public server");
  } else {
    console.log(`http://127.0.0.1:${PORT}  (watch simulator)`);
    for (const list of Object.values(os.networkInterfaces()))
      for (const a of list || [])
        if (a.family === "IPv4" && !a.internal) console.log(`http://${a.address}:${PORT}  (iPhone on the same Wi-Fi)`);
  }
  console.log(API_KEY ? "API key required (x-api-key header or ?key=)" : "No API key required");
});

const PANEL_HTML = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>WatchLock control panel</title>
<style>
 body{font-family:-apple-system,system-ui,sans-serif;max-width:420px;margin:32px auto;padding:0 16px;color:#222}
 h1{font-size:20px;font-weight:600}
 .big{font-size:64px;font-weight:700;margin:8px 0 0;line-height:1}
 .label{font-size:16px;margin-bottom:8px}
 .due{color:#c0392b}.clear{color:#27ae60}
 button{font-size:16px;padding:10px 16px;margin:4px 4px 4px 0;border-radius:8px;border:1px solid #ccc;background:#f7f7f7;cursor:pointer}
 label{display:block;margin:16px 0 4px;font-size:14px;color:#555}
 input{font-size:16px;padding:8px;width:100px;border:1px solid #ccc;border-radius:6px}
 .muted{color:#888;font-size:13px}
</style></head><body>
<h1>WatchLock control panel</h1>
<div id="num" class="big">…</div>
<div id="label" class="label"></div>
<div id="split" class="muted"></div>
<p><button onclick="bank(300,'panel +5 min')">+5 min</button><button onclick="bank(900,'panel +15 min')">+15 min</button><button onclick="bank(-300,'panel -5 min')">-5 min</button><button onclick="bank(-900,'panel -15 min')">-15 min</button><button id="clr" onclick="bank(debt,'panel clear debt')">Clear debt</button></p>
<p class="muted">The watch and the panel both move the same balance.</p>
<div id="meta" class="muted"></div>
<h1>Recent</h1>
<div id="recent" class="muted"></div>
<label>Activity suggestion (optional, shown on the phone's blocked screen)</label><input id="act" style="width:240px"> <button onclick="setAct(act.value)">Send</button> <button onclick="setAct(null)">Clear</button>
<h1>Phone usage (stand-in for iOS)</h1>
<div id="usage" class="label"></div>
<p><button onclick="addUse(1)">+1</button><button onclick="addUse(5)">+5</button><button onclick="resetUse()">Reset day</button></p>
<h1>Badges (demo)</h1>
<p><select id="badge" style="font-size:16px;padding:8px"></select> <button onclick="unlock()">Unlock on watch</button></p>
<div id="badgeLast" class="muted"></div>
<p class="muted">The watch unlocks it within a few seconds and shows its new-badge screen.</p>
<label>API key (only if the server has one)</label><input id="key" style="width:200px">
<script>
let debt=0,used=0;
const BADGES=${JSON.stringify(BADGE_IDS)};
for(const id in BADGES){const o=document.createElement('option');o.value=id;o.textContent=BADGES[id];badge.appendChild(o)}
const keyEl=document.getElementById('key');keyEl.value=localStorage.getItem('wl_key')||'';
keyEl.onchange=()=>{localStorage.setItem('wl_key',keyEl.value);refresh()};
function hdr(){return {'Content-Type':'application/json','x-api-key':keyEl.value}}
async function refresh(){
  const r=await fetch('/state',{headers:hdr()});if(!r.ok){num.textContent='–';label.textContent='Auth error: enter the API key';return}
  const s=await r.json();const e=s.effectiveSec;debt=Math.max(0,-e);used=s.usedMinutesToday;
  num.textContent=e<0?'-'+s.taxMinutes+' min debt':s.creditMinutes>0?'+'+s.creditMinutes+' min credit':'0 min';num.className='big '+(e<0?'due':'clear');
  label.textContent=s.taxMinutes>0?'apps blocked':'apps open';
  split.textContent='Tax minutes: '+s.taxMinutes+' · Credit minutes: '+s.creditMinutes;
  clr.disabled=debt===0;
  usage.textContent=s.usedMinutesToday+' min used on '+s.usageDay;
  meta.textContent=(s.activity?'Activity: '+s.activity+' · ':'')+'from '+s.source+' · '+new Date(s.updatedAt).toLocaleTimeString();
  recent.textContent='';
  for(const h of s.history){const d=document.createElement('div');const x=Math.round(h.deltaSec/60*10)/10;
    d.textContent=new Date(h.t).toLocaleTimeString()+'  '+(x>0?'+':'')+x+' min  '+h.reason+'  ('+h.source+')';recent.appendChild(d)}
  if(!s.history.length)recent.textContent='Nothing yet';
  const b=s.badgeCommand;badgeLast.textContent=b?'Last request: '+(BADGES[b.id]||b.id)+' #'+b.seq+' at '+new Date(b.at).toLocaleTimeString():'No request yet';
}
async function unlock(){
  await fetch('/badge',{method:'POST',headers:hdr(),body:JSON.stringify({id:badge.value})});refresh()
}
async function bank(sec,reason){
  if(!sec)return;
  await fetch('/ledger',{method:'POST',headers:hdr(),body:JSON.stringify({deltaSec:sec,reason:reason,source:'panel'})});refresh()
}
async function setAct(a){
  await fetch('/state',{method:'POST',headers:hdr(),body:JSON.stringify({activity:a,source:'panel'})});refresh()
}
async function addUse(n){
  await fetch('/usage',{method:'POST',headers:hdr(),body:JSON.stringify({usedMinutesToday:used+n})});refresh()
}
async function resetUse(){
  await fetch('/usage',{method:'POST',headers:hdr(),body:JSON.stringify({usedMinutesToday:0,reset:true})});refresh()
}
refresh();setInterval(refresh,2000);
</script></body></html>`;
