// Contract v2 tests: spawn the real server and talk to it over HTTP.
const { test, before, after } = require("node:test");
const assert = require("node:assert");
const { spawn } = require("node:child_process");
const os = require("node:os");
const path = require("node:path");
const fs = require("node:fs");

const PORT = 3999;
const BASE = `http://127.0.0.1:${PORT}`;
const KEY = "t";
const DATA = path.join(os.tmpdir(), `wl-test-${Math.random().toString(36).slice(2)}.json`);
let child;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function start() {
  child = spawn(process.execPath, ["server.js"], {
    cwd: __dirname,
    env: { ...process.env, PORT: String(PORT), API_KEY: KEY, DATA_FILE: DATA },
    stdio: "ignore",
  });
  for (let i = 0; i < 50; i++) {
    try {
      if ((await fetch(BASE + "/health")).ok) return;
    } catch (_) {}
    await sleep(100);
  }
  throw new Error("server did not start");
}

async function stop() {
  if (!child) return;
  const c = child;
  child = null;
  const closed = new Promise((r) => c.once("close", r));
  c.kill();
  await closed;
}

const H = { "x-api-key": KEY, "content-type": "application/json" };
const post = (p, body) => fetch(BASE + p, { method: "POST", headers: H, body: JSON.stringify(body) });
const get = async () => (await fetch(BASE + "/state", { headers: H })).json();
const led = (b) => post("/ledger", { reason: "t", source: "panel", ...b });
async function zero() {
  const s = await get();
  if (s.balanceSec) await led({ deltaSec: -s.balanceSec });
  await post("/state", { pendingChargeSec: 0 });
}
const today = () => {
  const d = new Date();
  const z = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}`;
};
const shift = (days) => {
  const d = new Date();
  d.setDate(d.getDate() + days);
  const z = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}`;
};

before(start);
after(async () => {
  await stop();
  fs.rmSync(DATA, { force: true });
});

test("health needs no key", async () => {
  const r = await fetch(BASE + "/health");
  assert.strictEqual(r.status, 200);
  assert.deepStrictEqual(await r.json(), { ok: true });
});

test("state without key is 401", async () => {
  const R = { "cf-connecting-ip": "1.2.3.4" }; // remote path (tunnel)
  const r = await fetch(BASE + "/state", { headers: R });
  assert.strictEqual(r.status, 401);
  assert.deepStrictEqual(await r.json(), { error: "bad or missing API key" });
  assert.strictEqual((await fetch(BASE + "/usage", { method: "POST", headers: R })).status, 401);
  assert.strictEqual((await fetch(BASE + "/state?key=t", { headers: R })).status, 200);
});

test("local exemption: loopback without forwarding headers needs no key", async () => {
  assert.strictEqual((await fetch(BASE + "/state")).status, 200);
});

test("local exemption: any forwarding header forces the key", async () => {
  for (const h of ["cf-connecting-ip", "x-forwarded-for", "cf-ray", "x-real-ip", "forwarded"]) {
    assert.strictEqual((await fetch(BASE + "/state", { headers: { [h]: "1.2.3.4" } })).status, 401, h);
  }
  const ok = await fetch(BASE + "/state", { headers: { "cf-connecting-ip": "1.2.3.4", "x-api-key": KEY } });
  assert.strictEqual(ok.status, 200);
});

test("LOCAL_NO_KEY=0 requires the key even on loopback", async () => {
  const port = 3997;
  const data = path.join(os.tmpdir(), `wl-lnk-${Math.random().toString(36).slice(2)}.json`);
  const c = spawn(process.execPath, ["server.js"], {
    cwd: __dirname,
    env: { ...process.env, PORT: String(port), DATA_FILE: data, API_KEY: KEY, LOCAL_NO_KEY: "0" },
    stdio: "ignore",
  });
  const closed = new Promise((r) => c.once("close", r));
  try {
    const b = `http://127.0.0.1:${port}`;
    for (let i = 0; i < 50; i++) {
      try { if ((await fetch(b + "/health")).ok) break; } catch (_) {}
      await sleep(100);
    }
    assert.strictEqual((await fetch(b + "/state")).status, 401);
    assert.strictEqual((await fetch(b + "/state", { headers: { "x-api-key": KEY } })).status, 200);
  } finally {
    c.kill();
    await closed;
    fs.rmSync(data, { force: true });
  }
});

test("GET /state has all 14 keys", async () => {
  const s = await get();
  assert.deepStrictEqual(Object.keys(s).sort(), [
    "activity", "badgeCommand", "balanceSec", "creditMinutes", "effectiveSec", "history", "pendingChargeSec", "source", "taxMinutes", "updatedAt", "usageDay", "usageEpoch", "usageUpdatedAt", "usedMinutesToday",
  ]);
  assert.strictEqual(s.usageDay, today());
});

test("POST /state: activity and pendingChargeSec, ignores taxMinutes, 400 otherwise", async () => {
  await zero();
  let r = await post("/state", { activity: "Walk", pendingChargeSec: 90.4, taxMinutes: 50, creditMinutes: 9, source: "watch" });
  assert.strictEqual(r.status, 200);
  let s = await r.json();
  assert.strictEqual(s.activity, "Walk");
  assert.strictEqual(s.pendingChargeSec, 90);
  assert.strictEqual(s.source, "watch");
  assert.strictEqual(s.balanceSec, 0);
  assert.strictEqual(s.taxMinutes, 2); // ceil(90/60), not 50
  assert.strictEqual(s.creditMinutes, 0);
  r = await post("/state", { activity: "" });
  assert.strictEqual((await r.json()).activity, null);
  assert.strictEqual((await get()).pendingChargeSec, 90);
  assert.strictEqual((await post("/state", {})).status, 400);
  assert.strictEqual((await post("/state", { taxMinutes: 5 })).status, 400);
  assert.strictEqual((await get()).taxMinutes, 2);
  await zero();
});

test("derived tax and credit include pendingChargeSec", async () => {
  await zero();
  let s = await (await led({ deltaSec: -100 })).json();
  assert.strictEqual(s.balanceSec, -100);
  assert.strictEqual(s.taxMinutes, 2);
  assert.strictEqual(s.creditMinutes, 0);
  s = await (await post("/state", { pendingChargeSec: 30 })).json();
  assert.strictEqual(s.taxMinutes, 3); // ceil(130/60)
  s = await (await led({ deltaSec: 500 })).json();
  assert.strictEqual(s.balanceSec, 400);
  assert.strictEqual(s.taxMinutes, 0);
  assert.strictEqual(s.creditMinutes, 6); // floor(370/60)
  s = await (await post("/state", { pendingChargeSec: 0 })).json();
  assert.strictEqual(s.creditMinutes, 6);
  await zero();
});

test("effectiveSec and clear debt: pending charges drain to zero", async () => {
  await zero();
  await led({ deltaSec: -300 });
  let s = await (await post("/state", { pendingChargeSec: 120 })).json();
  assert.strictEqual(s.effectiveSec, -420);
  assert.strictEqual(s.taxMinutes, 7);
  s = await (await led({ deltaSec: -s.effectiveSec, reason: "panel clear debt" })).json(); // +420
  assert.strictEqual(s.balanceSec, 120);
  assert.strictEqual(s.effectiveSec, 0);
  s = await (await led({ deltaSec: -120, reason: "watch charge" })).json(); // pending drains into balance
  s = await (await post("/state", { pendingChargeSec: 0 })).json();
  assert.strictEqual(s.balanceSec, 0);
  assert.strictEqual(s.effectiveSec, 0);
  await zero();
});

test("ledger: panel delta applies and shows in history", async () => {
  await zero();
  const r = await led({ deltaSec: 300, reason: "  panel +5 min " });
  assert.strictEqual(r.status, 200);
  const s = await r.json();
  assert.strictEqual(s.applied, true);
  assert.strictEqual(s.lastEventId, null);
  assert.strictEqual(s.balanceSec, 300);
  assert.strictEqual(s.creditMinutes, 5);
  const h = s.history[0];
  assert.strictEqual(h.deltaSec, 300);
  assert.strictEqual(h.reason, "panel +5 min");
  assert.strictEqual(h.source, "panel");
  assert.ok(!Number.isNaN(Date.parse(h.t)));
  const r2 = await (await led({ deltaSec: 300 })).json(); // no session: always applies
  assert.strictEqual(r2.balanceSec, 600);
  const r3 = await (await led({ deltaSec: -60, activity: "Run", pendingChargeSec: 20 })).json();
  assert.strictEqual(r3.activity, "Run");
  assert.strictEqual(r3.pendingChargeSec, 20);
  await zero();
});

test("ledger: watch idempotency by session and eventId", async () => {
  await zero();
  const w = (eventId, session = "s1") => led({ deltaSec: 60, source: "watch", session, eventId });
  let s = await (await w(1)).json();
  assert.strictEqual(s.applied, true);
  assert.strictEqual(s.lastEventId, 1);
  const base = s.balanceSec;
  s = await (await w(1)).json();
  assert.strictEqual(s.applied, false);
  assert.strictEqual(s.balanceSec, base);
  assert.strictEqual(s.lastEventId, 1);
  s = await (await w(2)).json();
  assert.strictEqual(s.applied, true);
  assert.strictEqual(s.balanceSec, base + 60);
  s = await (await w(1)).json(); // older than 2
  assert.strictEqual(s.applied, false);
  assert.strictEqual(s.lastEventId, 2);
  s = await (await w(1, "s2")).json(); // new session resets
  assert.strictEqual(s.applied, true);
  assert.strictEqual(s.lastEventId, 1);
  assert.strictEqual(s.balanceSec, base + 120);
  s = await (await led({ deltaSec: 60, source: "ios", session: "s1", eventId: 1 })).json(); // per source
  assert.strictEqual(s.applied, true);
  await zero();
});

test("ledger: validation 400s", async () => {
  const bad = [
    { deltaSec: 0 }, { deltaSec: 86401 }, { deltaSec: -86401 }, { deltaSec: 1.5 }, { deltaSec: "60" }, { deltaSec: null }, {},
    { deltaSec: 60, reason: "" }, { deltaSec: 60, reason: "   " }, { deltaSec: 60, reason: "x".repeat(61) }, { deltaSec: 60, reason: 5 },
    { deltaSec: 60, source: "tv" }, { deltaSec: 60, source: undefined },
  ];
  for (const b of bad) {
    const before = (await get()).balanceSec;
    const r = await post("/ledger", { reason: "t", source: "panel", ...b });
    assert.strictEqual(r.status, 400, JSON.stringify(b));
    assert.strictEqual((await get()).balanceSec, before);
  }
  assert.strictEqual((await led({ deltaSec: 86400 })).status, 200);
  assert.strictEqual((await led({ deltaSec: -86400 })).status, 200);
  assert.strictEqual((await led({ reason: "x".repeat(60), deltaSec: 1 })).status, 200);
  await zero();
});

test("ledger: history stored 20, returned 10, newest first", async () => {
  await zero();
  for (let i = 1; i <= 25; i++) await led({ deltaSec: i, reason: "n" + i });
  const s = await get();
  assert.strictEqual(s.history.length, 10);
  assert.strictEqual(s.history[0].reason, "n25");
  assert.strictEqual(s.history[9].reason, "n16");
  const saved = JSON.parse(fs.readFileSync(DATA, "utf8"));
  assert.strictEqual(saved.history.length, 20);
  assert.strictEqual(saved.taxMinutes, undefined);
  await zero();
});

test("ledger: needs the key through the tunnel", async () => {
  const R = { "cf-connecting-ip": "1.2.3.4", "content-type": "application/json" };
  const body = JSON.stringify({ deltaSec: 60, reason: "t", source: "panel" });
  const before = (await get()).balanceSec;
  assert.strictEqual((await fetch(BASE + "/ledger", { method: "POST", headers: R, body })).status, 401);
  assert.strictEqual((await get()).balanceSec, before);
  assert.strictEqual((await fetch(BASE + "/ledger", { method: "POST", headers: { ...R, "x-api-key": KEY }, body })).status, 200);
  await zero();
});

const BADGE_IDS = ["fc", "pw", "ls", "d1", "d3", "d5", "dk", "sm", "ds", "pa", "dw", "af", "wo", "r1", "r2", "r5", "ll", "dd", "fu", "sr"];

test("badge: unknown id is 400 and changes nothing", async () => {
  const before = (await get()).badgeCommand;
  for (const body of [{ id: "perfectWeek" }, { id: "" }, { id: 5 }, {}]) {
    const r = await post("/badge", body);
    assert.strictEqual(r.status, 400);
    assert.deepStrictEqual(await r.json(), { error: "unknown badge" });
  }
  assert.deepStrictEqual((await get()).badgeCommand, before);
});

test("badge: valid id is 200, seq increments, ledger untouched", async () => {
  const h = (await get()).history.length;
  const a = await (await post("/badge", { id: "pw" })).json();
  assert.strictEqual(a.badgeCommand.id, "pw");
  assert.ok(!Number.isNaN(Date.parse(a.badgeCommand.at)));
  const b = await post("/badge", { id: "sr" });
  assert.strictEqual(b.status, 200);
  const bj = await b.json();
  assert.strictEqual(bj.badgeCommand.seq, a.badgeCommand.seq + 1);
  assert.strictEqual(bj.badgeCommand.id, "sr");
  assert.strictEqual(bj.history.length, h);
  assert.deepStrictEqual((await get()).badgeCommand, bj.badgeCommand);
});

test("badge: badgeCommand persists across restart", async () => {
  const c = (await (await post("/badge", { id: "dk" })).json()).badgeCommand;
  await stop();
  await start();
  assert.deepStrictEqual((await get()).badgeCommand, c);
  const n = await (await post("/badge", { id: "fc" })).json();
  assert.strictEqual(n.badgeCommand.seq, c.seq + 1);
});

test("badge: needs the key through the tunnel", async () => {
  const R = { "cf-connecting-ip": "1.2.3.4", "content-type": "application/json" };
  const before = (await get()).badgeCommand;
  assert.strictEqual((await fetch(BASE + "/badge", { method: "POST", headers: R, body: JSON.stringify({ id: "pw" }) })).status, 401);
  assert.deepStrictEqual((await get()).badgeCommand, before);
});

test("badge: panel HTML lists every badge id", async () => {
  const html = await (await fetch(BASE + "/")).text();
  for (const id of BADGE_IDS) assert.ok(html.includes(`"${id}"`), id);
  assert.ok(html.includes("Unlock on watch"));
});

test("usage: increase, decrease, reset", async () => {
  await post("/usage", { usedMinutesToday: 0, reset: true });
  const before = await get();
  let r = await post("/usage", { usedMinutesToday: 10 });
  assert.strictEqual(r.status, 200);
  const s = await r.json();
  assert.strictEqual(s.usedMinutesToday, 10);
  assert.ok(s.usageUpdatedAt);
  assert.strictEqual(s.source, before.source);
  assert.strictEqual(s.updatedAt, before.updatedAt);
  r = await post("/usage", { usedMinutesToday: 5 });
  assert.strictEqual(r.status, 409);
  assert.strictEqual((await r.json()).error, "decrease");
  r = await post("/usage", { usedMinutesToday: 5, reset: true });
  assert.strictEqual(r.status, 200);
  assert.strictEqual((await get()).usedMinutesToday, 5);
});

test("usage: future day accepted, past day 409", async () => {
  await post("/usage", { usedMinutesToday: 50 });
  const f = shift(1);
  let r = await post("/usage", { usedMinutesToday: 3, day: f });
  assert.strictEqual(r.status, 200);
  assert.strictEqual((await r.json()).usageDay, f);
  r = await post("/usage", { usedMinutesToday: 3, day: today() });
  assert.strictEqual(r.status, 409);
  assert.strictEqual((await r.json()).error, "stale day");
  await post("/usage", { usedMinutesToday: 0, day: shift(1), reset: true });
});

test("usage: invalid values are 400", async () => {
  assert.strictEqual((await post("/usage", { usedMinutesToday: 1441 })).status, 400);
  assert.strictEqual((await post("/usage", { usedMinutesToday: "x" })).status, 400);
  assert.strictEqual((await post("/usage", { usedMinutesToday: 5, day: "2026-1-1" })).status, 400);
});

test("OPTIONS is 204 with CORS, before auth", async () => {
  const r = await fetch(BASE + "/state", { method: "OPTIONS" });
  assert.strictEqual(r.status, 204);
  assert.strictEqual(r.headers.get("access-control-allow-origin"), "*");
  assert.strictEqual(r.headers.get("access-control-allow-headers"), "content-type,x-api-key");
  assert.strictEqual(r.headers.get("access-control-allow-methods"), "GET,POST,OPTIONS");
  assert.strictEqual(r.headers.get("cache-control"), "no-store");
});

test("state survives restart", async () => {
  await zero();
  await led({ deltaSec: 600, source: "watch", session: "r1", eventId: 5 });
  await post("/state", { activity: "Stairs", pendingChargeSec: 60 });
  await stop();
  await start();
  const s = await get();
  assert.strictEqual(s.balanceSec, 600);
  assert.strictEqual(s.pendingChargeSec, 60);
  assert.strictEqual(s.creditMinutes, 9);
  assert.strictEqual(s.activity, "Stairs");
  assert.strictEqual(s.history[0].deltaSec, 600);
  const r = await (await led({ deltaSec: 600, source: "watch", session: "r1", eventId: 5 })).json();
  assert.strictEqual(r.applied, false);
  await zero();
});

test("malformed Host header does not crash the server", async () => {
  const status = await new Promise((resolve, reject) => {
    const r = require("node:http").request({ host: "127.0.0.1", port: PORT, path: "/health", headers: { host: "[" } }, (res) => {
      res.resume();
      resolve(res.statusCode);
    });
    r.on("error", () => resolve(0));
    r.end();
  });
  assert.ok(status === 200 || status === 0 || status === 400);
  assert.strictEqual((await fetch(BASE + "/health")).status, 200);
});

test("oversize body is 413", async () => {
  const r = await fetch(BASE + "/state", { method: "POST", headers: H, body: JSON.stringify({ activity: "x".repeat(200000) }) });
  assert.strictEqual(r.status, 413);
  assert.deepStrictEqual(await r.json(), { error: "body too large" });
  assert.strictEqual((await fetch(BASE + "/health")).status, 200);
});

test("usage: day must be a real date within one day of today", async () => {
  for (const day of ["9999-12-31", "2026-13-45", "2026-02-30", shift(2), shift(-2)]) {
    const r = await post("/usage", { usedMinutesToday: 5, day });
    assert.strictEqual(r.status, 400, day);
    assert.deepStrictEqual(await r.json(), { error: "bad day" });
  }
  const r = await post("/usage", { usedMinutesToday: 5, day: shift(-1) });
  assert.ok(r.status === 200 || r.status === 409);
  if (r.status === 409) assert.strictEqual((await r.json()).error, "stale day");
});

test("usageEpoch: String, stable on increase, changed by reset, kept on new day", async () => {
  const e0 = (await get()).usageEpoch;
  assert.strictEqual(typeof e0, "string");
  assert.ok(e0.length >= 6 && e0.length <= 12, e0);
  await post("/usage", { usedMinutesToday: 0, day: shift(1), reset: true });
  const e1 = (await get()).usageEpoch;
  assert.notStrictEqual(e1, e0);
  const r = await post("/usage", { usedMinutesToday: 9, day: shift(1) });
  assert.strictEqual((await r.json()).usageEpoch, e1);
  assert.strictEqual((await (await led({ deltaSec: 1 })).json()).usageEpoch, e1);
  assert.strictEqual((await get()).usageEpoch, e1);
});

test("usageEpoch: survives restart, differs for a fresh DATA_FILE", async () => {
  const e = (await get()).usageEpoch;
  await stop();
  await start();
  assert.strictEqual((await get()).usageEpoch, e);
  await stop();
  fs.rmSync(DATA, { force: true });
  await start();
  const f = (await get()).usageEpoch;
  assert.strictEqual(typeof f, "string");
  assert.notStrictEqual(f, e);
});

test("usageEpoch: added when saved state lacks it", async () => {
  await stop();
  const s = JSON.parse(fs.readFileSync(DATA, "utf8"));
  delete s.usageEpoch;
  fs.writeFileSync(DATA, JSON.stringify(s));
  await start();
  const e = (await get()).usageEpoch;
  assert.strictEqual(typeof e, "string");
  await stop();
  await start();
  assert.strictEqual((await get()).usageEpoch, e);
});

test("migration: old state without balanceSec", async () => {
  await stop();
  const s = JSON.parse(fs.readFileSync(DATA, "utf8"));
  delete s.balanceSec;
  delete s.pendingChargeSec;
  delete s.history;
  delete s.ledgerSessions;
  s.taxMinutes = 10;
  s.creditMinutes = 3;
  fs.writeFileSync(DATA, JSON.stringify(s));
  await start();
  const g = await get();
  assert.strictEqual(g.balanceSec, -420);
  assert.strictEqual(g.taxMinutes, 7);
  assert.strictEqual(g.creditMinutes, 0);
  assert.strictEqual(g.pendingChargeSec, 0);
  assert.deepStrictEqual(g.history, []);
  await stop();
  await start();
  assert.strictEqual((await get()).balanceSec, -420); // migrated once, not again
  await zero();
});

// Railway startup output: separate child on its own port and temp DATA_FILE.
async function bootOutput(extra) {
  const port = 3998;
  const data = path.join(os.tmpdir(), `wl-rw-${Math.random().toString(36).slice(2)}.json`);
  const env = { ...process.env, PORT: String(port), DATA_FILE: data, API_KEY: "", RAILWAY_ENVIRONMENT: "", RAILWAY_PUBLIC_DOMAIN: "", ...extra };
  const c = spawn(process.execPath, ["server.js"], { cwd: __dirname, env, stdio: ["ignore", "pipe", "pipe"] });
  let out = "";
  c.stdout.on("data", (d) => (out += d));
  c.stderr.on("data", (d) => (out += d));
  for (let i = 0; i < 50 && !/API key|No API key/.test(out); i++) await sleep(100);
  const closed = new Promise((r) => c.once("close", r));
  c.kill();
  await closed;
  fs.rmSync(data, { force: true });
  return out;
}

test("railway: prints public URL, no LAN lines, warns without API_KEY", async () => {
  const out = await bootOutput({ RAILWAY_ENVIRONMENT: "production", RAILWAY_PUBLIC_DOMAIN: "x.up.railway.app" });
  assert.match(out, /Railway: https:\/\/x\.up\.railway\.app/);
  assert.doesNotMatch(out, /same Wi-Fi/);
  assert.match(out, /WARNING: no API_KEY set on a public server/);
});

test("railway: no domain yet, no warning when API_KEY set", async () => {
  const out = await bootOutput({ RAILWAY_ENVIRONMENT: "production", API_KEY: "k" });
  assert.match(out, /Railway: no public domain yet/);
  assert.doesNotMatch(out, /WARNING/);
});

test("local run: no Railway line, no warning", async () => {
  const out = await bootOutput({});
  assert.doesNotMatch(out, /Railway|WARNING/);
});
