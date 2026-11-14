# WatchLock server

A small Node server that holds the numbers the watch and the phone share: tax minutes and credit minutes from the watch, and minutes of phone use today from the iPhone (or from the control panel). It has no dependencies and needs Node 18 or newer.

Start it with `node server.js` (or `npm start`). Run the tests with `npm test`. Open the control panel at `http://127.0.0.1:48217/`.

## Environment variables

- `PORT`: default 48217.
- `API_KEY`: if set, /state and /usage need the header `x-api-key` or the query `?key=`.
- `DATA_FILE`: where state is saved, default `state.json` next to server.js. On Railway the default is `/data/state.json` when a volume is mounted at /data. On Railway the default is `/data/state.json` when a volume is mounted at /data.

## Contract v1

| Method and path | Body | Result |
| --- | --- | --- |
| GET /health | none | 200 `{"ok":true}` |
| GET /state | none | 200 taxMinutes, creditMinutes, activity, usedMinutesToday, usageDay, usageEpoch, usageUpdatedAt, source, updatedAt |
| POST /state | taxMinutes, creditMinutes, activity (at least one), source | 200 full state, 400 if none given |
| POST /usage | usedMinutesToday 0..1440, optional day YYYY-MM-DD, optional reset | 200 full state, 400 bad input, 409 stale day or decrease |
| OPTIONS any | none | 204 with CORS headers |

Usage rolls to zero when the server's local date passes usageDay. A lower value on the same day is refused unless reset is true.

usageEpoch is a String ID generated on first start and on every accepted reset:true (not on a new day); when it changes the watch rebaselines its usage counter instead of waiting to pass its old high-water mark.

## curl.exe examples (PowerShell)

```
curl.exe -X POST http://127.0.0.1:48217/usage -H "x-api-key: KEY" -H "content-type: application/json" -d '{\"usedMinutesToday\":20}'
curl.exe http://127.0.0.1:48217/state -H "x-api-key: KEY"
curl.exe -X POST http://127.0.0.1:48217/state -H "x-api-key: KEY" -H "content-type: application/json" -d '{\"taxMinutes\":10,\"source\":\"watch\"}'
```

Leave out the x-api-key header if you did not set API_KEY.

## Local panel

Open http://localhost:48217 on the server's own machine and use the panel with the key field empty. A request counts as local only if it comes from loopback and carries none of `cf-connecting-ip`, `cf-ray`, `x-forwarded-for`, `x-real-ip`, `forwarded`, so requests through the Cloudflare tunnel still need the key. Requests from other devices on the LAN are not loopback, so they still need the key too. Set `LOCAL_NO_KEY=0` to turn this off.

## Networking

On the first run Windows asks about the firewall. Allow Private networks, or the phone cannot reach the server. For the same Wi-Fi case, open the printed LAN URL on the iPhone.

## Exposure

The server listens on the LAN over plain HTTP. Set API_KEY for demos so nobody on the Wi-Fi can zero taxMinutes, and make sure the API_KEY constant in the watch's Sync.mc matches it.

## Deploy on Railway

The server has no dependencies, so Railway builds it straight from package.json and runs `npm start`. Railway sets PORT and terminates HTTPS at its edge; the app serves plain HTTP behind it.

1. Install the CLI: `npm i -g @railway/cli`.
2. Run `railway login`.
3. From the server/ folder, run `railway init`, then `railway up`.
4. Set a key with `railway variables --set API_KEY=<random>`. Without it the server prints "WARNING: no API_KEY set on a public server" and anyone can change your minutes.
5. Run `railway domain` to get the public address.

Clients use `https://<domain>` and send the header `x-api-key`. The health check is `/health` (configured in railway.json).

Optional: add a volume mounted at `/data`. The server then saves to `/data/state.json`. Without a volume the container filesystem is ephemeral and state resets on every redeploy or restart. That is harmless for the watch: a fresh state gets a new usageEpoch and the watch rebaselines.
