// Contract v1 tests: spawn the real server and talk to it over HTTP.
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
  const r = await fetch(BASE + "/state");
  assert.strictEqual(r.status, 401);
  assert.deepStrictEqual(await r.json(), { error: "bad or missing API key" });
  assert.strictEqual((await fetch(BASE + "/usage", { method: "POST" })).status, 401);
  assert.strictEqual((await fetch(BASE + "/state?key=t")).status, 200);
});

test("GET /state has all 9 keys", async () => {
  const s = await get();
  assert.deepStrictEqual(Object.keys(s).sort(), [
    "activity", "creditMinutes", "source", "taxMinutes", "updatedAt", "usageDay", "usageEpoch", "usageUpdatedAt", "usedMinutesToday",
  ]);
  assert.strictEqual(s.usageDay, today());
});

test("POST /state round trip, clear activity, empty body", async () => {
  let r = await post("/state", { taxMinutes: 12.4, creditMinutes: "7", activity: "Walk", source: "watch" });
  assert.strictEqual(r.status, 200);
  let s = await r.json();
  assert.strictEqual(s.taxMinutes, 12);
  assert.strictEqual(s.creditMinutes, 7);
  assert.strictEqual(s.activity, "Walk");
  assert.strictEqual(s.source, "watch");
  r = await post("/state", { activity: "" });
  assert.strictEqual((await r.json()).activity, null);
  assert.strictEqual((await get()).creditMinutes, 7);
  assert.strictEqual((await post("/state", {})).status, 400);
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
  await post("/state", { taxMinutes: 33, creditMinutes: 4, activity: "Stairs" });
  await stop();
  await start();
  const s = await get();
  assert.strictEqual(s.taxMinutes, 33);
  assert.strictEqual(s.creditMinutes, 4);
  assert.strictEqual(s.activity, "Stairs");
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
  assert.strictEqual((await (await post("/state", { taxMinutes: 1 })).json()).usageEpoch, e1);
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
