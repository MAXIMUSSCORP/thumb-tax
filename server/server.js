// WatchLock server, zero dependencies, Node 18+. Contract v1.
// Stores tax minutes (watch), credit minutes (watch) and phone usage (iOS or panel).
//
//   GET  /health  -> {ok:true}
//   GET  /state   -> full state
//   POST /state   -> {taxMinutes, creditMinutes, activity, source}, at least one of the first three
//   POST /usage   -> {usedMinutesToday 0..1440, day?, reset?}
//   GET  /        -> control panel
//
// Env: PORT (default 48217), API_KEY (optional; header "x-api-key" or "?key=" on /state and /usage),
// LOCAL_NO_KEY (default 1; 0 = loopback requests need the key too),
// DATA_FILE (default ./state.json, or /data/state.json on Railway when a volume is mounted).

const http = require("http");
const fs = require("fs");
const os = require("os");
const path = require("path");

const PORT = process.env.PORT || 48217;
const API_KEY = process.env.API_KEY || "";
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
  taxMinutes: 0,
  creditMinutes: 0,
  activity: null,
  usedMinutesToday: 0,
  usageDay: today(),
  usageUpdatedAt: null,
  source: "default",
  updatedAt: new Date().toISOString(),
};

try {
  const saved = JSON.parse(fs.readFileSync(DATA_FILE, "utf8"));
  if (typeof saved.taxMinutes === "number") state = { ...state, ...saved };
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

save(); // persist a freshly generated usageEpoch

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

function applyUpdate(body) {
  const tax = num(body.taxMinutes);
  const credit = num(body.creditMinutes);
  const hasActivity = typeof body.activity === "string" || body.activity === null;
  if (tax === null && credit === null && !hasActivity) return null;
  if (tax !== null) state.taxMinutes = tax;
  if (credit !== null) state.creditMinutes = credit;
  if (hasActivity) state.activity = body.activity ? body.activity.slice(0, 120) : null;
  state.source = typeof body.source === "string" && body.source ? body.source : "watch";
  state.updatedAt = new Date().toISOString();
  save();
  console.log(state.updatedAt, "tax =", state.taxMinutes, "credit =", state.creditMinutes, "activity =", state.activity, "from", state.source);
  return state;
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
  return { code: 200, body: state };
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
    return send(res, 200, state);
  }
  if (p === "/state" && req.method === "POST") {
    const result = applyUpdate(await readBody(req));
    if (!result) return send(res, 400, { error: "send taxMinutes, creditMinutes and/or activity" });
    return send(res, 200, result);
  }
  if (p === "/usage" && req.method === "POST") {
    const r = applyUsage(await readBody(req));
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
<p class="muted">Stand-in for the Fenix while you test. Setting tax minutes here is exactly what the watch does.</p>
<div id="num" class="big">…</div>
<div id="label" class="label"></div>
<div id="meta" class="muted"></div>
<p><button onclick="setTax(cur-1)">−1</button><button onclick="setTax(cur+1)">+1</button><button onclick="setTax(cur+5)">+5</button><button onclick="setTax(cur+15)">+15</button><button onclick="setTax(0)">Set 0</button></p>
<p class="muted">The watch overwrites these within 15 s when it is running.</p>
<div id="credit" class="muted"></div>
<label>Set tax minutes</label><input id="val" type="number" min="0"> <button onclick="setTax(Number(val.value))">Set</button>
<label>Activity suggestion (optional, shown on the phone's blocked screen)</label><input id="act" style="width:240px"> <button onclick="setAct(act.value)">Send</button> <button onclick="setAct(null)">Clear</button>
<h1>Phone usage (stand-in for iOS)</h1>
<div id="usage" class="label"></div>
<p><button onclick="addUse(1)">+1</button><button onclick="addUse(5)">+5</button><button onclick="resetUse()">Reset day</button></p>
<label>API key (only if the server has one)</label><input id="key" style="width:200px">
<script>
let cur=0,used=0;
const keyEl=document.getElementById('key');keyEl.value=localStorage.getItem('wl_key')||'';
keyEl.onchange=()=>{localStorage.setItem('wl_key',keyEl.value);refresh()};
function hdr(){return {'Content-Type':'application/json','x-api-key':keyEl.value}}
async function refresh(){
  const r=await fetch('/state',{headers:hdr()});if(!r.ok){num.textContent='–';label.textContent='Auth error: enter the API key';return}
  const s=await r.json();cur=s.taxMinutes;
  num.textContent=s.taxMinutes;num.className='big '+(s.taxMinutes>0?'due':'clear');
  label.textContent=s.taxMinutes>0?'tax minutes left, apps blocked':'tax minutes, apps open';
  credit.textContent='Credit minutes: '+s.creditMinutes;used=s.usedMinutesToday;
  usage.textContent=s.usedMinutesToday+' min used on '+s.usageDay;
  meta.textContent=(s.activity?'Activity: '+s.activity+' · ':'')+'from '+s.source+' · '+new Date(s.updatedAt).toLocaleTimeString();
}
async function setTax(n){
  await fetch('/state',{method:'POST',headers:hdr(),body:JSON.stringify({taxMinutes:Math.max(0,n),source:'panel'})});refresh()
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
