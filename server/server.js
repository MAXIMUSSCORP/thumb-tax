// WatchLock MVP server — zero dependencies, Node 18+.
// Stores the tax minutes the watch reports and serves them to the iOS app.
// 0 tax minutes = guarded apps can open. Anything above 0 = blocked.
//
//   GET  /state   -> {taxMinutes, source, updatedAt}     (iOS app reads this)
//   POST /state   -> body {"taxMinutes": 12, "activity": "Walk 10 min"}  (watch writes this; both optional)
//   GET  /        -> control panel (stand-in for the watch while testing)
//   GET  /health
//
// Env: PORT (default 3000), API_KEY (optional; if set, required as header
// "x-api-key" or query "?key=" on every /state call).

const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY || "";
const DATA_FILE = process.env.DATA_FILE || path.join(__dirname, "state.json");

let state = {
  taxMinutes: 0,
  activity: null,
  source: "default",
  updatedAt: new Date().toISOString(),
};

try {
  const saved = JSON.parse(fs.readFileSync(DATA_FILE, "utf8"));
  if (typeof saved.taxMinutes === "number") state = { ...state, ...saved };
} catch (_) {
  /* first run */
}

function save() {
  fs.writeFile(DATA_FILE, JSON.stringify(state), () => {});
}

function applyUpdate(body, source) {
  const value = body.taxMinutes;
  const n = Number(value);
  const hasMinutes = !(value === undefined || value === null || value === "" || isNaN(n));
  const hasActivity = typeof body.activity === "string" || body.activity === null;
  if (!hasMinutes && !hasActivity) return null;
  if (hasMinutes) state.taxMinutes = Math.max(0, Math.round(n));
  if (hasActivity) state.activity = body.activity ? String(body.activity).slice(0, 120) : null;
  state.source = source || "unknown";
  state.updatedAt = new Date().toISOString();
  save();
  console.log(state.updatedAt, "taxMinutes =", state.taxMinutes, "activity =", state.activity, "from", state.source);
  return state;
}

function send(res, code, body, type = "application/json") {
  res.writeHead(code, { "Content-Type": type, "Cache-Control": "no-store" });
  res.end(type === "application/json" ? JSON.stringify(body) : body);
}

function authorized(req, url) {
  if (!API_KEY) return true;
  return req.headers["x-api-key"] === API_KEY || url.searchParams.get("key") === API_KEY;
}

function readBody(req) {
  return new Promise((resolve) => {
    let raw = "";
    req.on("data", (c) => {
      raw += c;
      if (raw.length > 1e5) req.destroy();
    });
    req.on("end", () => {
      if (!raw) return resolve({});
      try {
        resolve(JSON.parse(raw));
      } catch (_) {
        resolve(Object.fromEntries(new URLSearchParams(raw))); // form-encoded fallback
      }
    });
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const p = url.pathname.replace(/\/+$/, "") || "/";

  if (p === "/health") return send(res, 200, { ok: true });
  if (p === "/" && req.method === "GET") return send(res, 200, PANEL_HTML, "text/html; charset=utf-8");

  if (!authorized(req, url)) return send(res, 401, { error: "bad or missing API key" });

  if (p === "/state" && req.method === "GET") return send(res, 200, state);
  if (p === "/state" && req.method === "POST") {
    const body = await readBody(req);
    const result = applyUpdate(body, body.source || "watch");
    if (!result) return send(res, 400, { error: 'send {"taxMinutes": <number>} and/or {"activity": "<text>"}' });
    return send(res, 200, result);
  }

  send(res, 404, { error: "not found" });
});

server.listen(PORT, () => {
  console.log(`WatchLock server on :${PORT}${API_KEY ? " (API key required)" : ""}`);
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
<label>Set tax minutes</label><input id="val" type="number" min="0"> <button onclick="setTax(Number(val.value))">Set</button>
<label>Activity suggestion (optional, shown on the phone's blocked screen)</label><input id="act" style="width:240px"> <button onclick="setAct(act.value)">Send</button> <button onclick="setAct(null)">Clear</button>
<label>API key (only if the server has one)</label><input id="key" style="width:200px">
<script>
let cur=0;
const keyEl=document.getElementById('key');keyEl.value=localStorage.getItem('wl_key')||'';
keyEl.onchange=()=>{localStorage.setItem('wl_key',keyEl.value);refresh()};
function hdr(){return {'Content-Type':'application/json','x-api-key':keyEl.value}}
async function refresh(){
  const r=await fetch('/state',{headers:hdr()});if(!r.ok){num.textContent='–';label.textContent='Auth error: enter the API key';return}
  const s=await r.json();cur=s.taxMinutes;
  num.textContent=s.taxMinutes;num.className='big '+(s.taxMinutes>0?'due':'clear');
  label.textContent=s.taxMinutes>0?'tax minutes left, apps blocked':'tax minutes, apps open';
  meta.textContent=(s.activity?'Activity: '+s.activity+' · ':'')+'from '+s.source+' · '+new Date(s.updatedAt).toLocaleTimeString();
}
async function setTax(n){
  await fetch('/state',{method:'POST',headers:hdr(),body:JSON.stringify({taxMinutes:Math.max(0,n),source:'panel'})});refresh()
}
async function setAct(a){
  await fetch('/state',{method:'POST',headers:hdr(),body:JSON.stringify({activity:a,source:'panel'})});refresh()
}
refresh();setInterval(refresh,2000);
</script></body></html>`;
