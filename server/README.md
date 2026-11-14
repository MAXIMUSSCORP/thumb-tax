# WatchLock server

A small Node server that holds the numbers the watch and the phone share: the tax and credit balance (moved by the watch and the control panel), and minutes of phone use today from the iPhone (or from the control panel). It has no dependencies and needs Node 18 or newer.

Start it with `node server.js` (or `npm start`). Run the tests with `npm test`. Open the control panel at `http://127.0.0.1:48217/`.

## Environment variables

- `PORT`: default 48217.
- `API_KEY`: /state, /ledger and /usage need the header `x-api-key` or the query `?key=`. Default `group16`, the key the watch sends (`API_KEY` in the watch's Sync.mc). Set `API_KEY=` (empty) to turn the key off.
- `DATA_FILE`: where state is saved, default `state.json` next to server.js. On Railway the default is `/data/state.json` when a volume is mounted at /data.

## Contract v2

The server is the bank. It holds one signed balance in seconds (`balanceSec`, positive is credit, negative is debt). The watch, the panel and later iOS send transactions to /ledger. Nobody overwrites the balance.

| Method and path | Body | Result |
| --- | --- | --- |
| GET /health | none | 200 `{"ok":true}` |
| GET /state | none | 200 full state (fields below) |
| POST /state | activity (string, "" or null) and/or pendingChargeSec (integer >= 0), source | 200 full state, 400 if neither is given |
| POST /ledger | deltaSec, reason, source, optional session, eventId, activity, pendingChargeSec | 200 full state plus applied and lastEventId, 400 bad input |
| POST /usage | usedMinutesToday 0..1440, optional day YYYY-MM-DD, optional reset | 200 full state, 400 bad input, 409 stale day or decrease |
| OPTIONS any | none | 204 with CORS headers |

Full state has balanceSec, pendingChargeSec, taxMinutes, creditMinutes, history, activity, usedMinutesToday, usageDay, usageEpoch, usageUpdatedAt, source, updatedAt.

Derived fields are computed on every response and never stored. With effective = balanceSec - pendingChargeSec: taxMinutes = ceil(max(0, -effective) / 60) and creditMinutes = floor(max(0, effective) / 60). pendingChargeSec is what the watch reports as phone minutes already counted but not yet charged. history is the last 10 ledger entries, newest first, each `{t, deltaSec, reason, source}`. The server keeps the last 20.

POST /ledger rules:

- deltaSec is a non-zero integer, at most 86400 either way. reason is 1 to 60 characters. source is `watch`, `panel` or `ios`. Anything else is 400.
- With both session and eventId, the server keeps the last session and eventId per source. A new session, or a higher eventId in the same session, is applied. A repeat or lower eventId is not applied: the answer is 200 with `"applied": false`. Without them (the panel) every request applies.
- activity and pendingChargeSec, if sent, update the same fields as POST /state.
- lastEventId in the answer is the stored id for that source, or null.

POST /state ignores taxMinutes and creditMinutes. A body with only those is 400, so an old watch build that posts only taxMinutes is refused on purpose.

Old state files that have taxMinutes and creditMinutes but no balanceSec are migrated on load: balanceSec = (creditMinutes - taxMinutes) * 60.

Usage rolls to zero when the server's local date passes usageDay. A lower value on the same day is refused unless reset is true.

usageEpoch is a String ID generated on first start and on every accepted reset:true (not on a new day); when it changes the watch rebaselines its usage counter instead of waiting to pass its old high-water mark.

## Control panel

The panel at / shows the balance as "-85 min debt" or "+12 min credit", the derived tax and credit minutes, and buttons for +5, +15, -5, -15 and Clear debt. They post to /ledger with source `panel` and a reason such as "panel +5 min". It also has the activity text, the phone usage buttons, the API key field and a Recent list of the last 10 entries. The watch and the panel both move the same balance.

## curl.exe examples (PowerShell)

```
curl.exe -X POST http://127.0.0.1:48217/usage -H "x-api-key: KEY" -H "content-type: application/json" -d '{\"usedMinutesToday\":20}'
curl.exe http://127.0.0.1:48217/state -H "x-api-key: KEY"
curl.exe -X POST http://127.0.0.1:48217/ledger -H "x-api-key: KEY" -H "content-type: application/json" -d '{\"deltaSec\":300,\"reason\":\"panel +5 min\",\"source\":\"panel\"}'
```

Leave out the x-api-key header if you did not set API_KEY.

## Local panel

Open http://localhost:48217 on the server's own machine and use the panel with the key field empty. A request counts as local only if it comes from loopback and carries none of `cf-connecting-ip`, `cf-ray`, `x-forwarded-for`, `x-real-ip`, `forwarded`, so requests through the Cloudflare tunnel still need the key. Requests from other devices on the LAN are not loopback, so they still need the key too. Set `LOCAL_NO_KEY=0` to turn this off.

## Networking

On the first run Windows asks about the firewall. Allow Private networks, or the phone cannot reach the server. For the same Wi-Fi case, open the printed LAN URL on the iPhone.

## Exposure

The server listens on the LAN over plain HTTP. Set API_KEY for demos so nobody on the Wi-Fi can change the balance, and make sure the API_KEY constant in the watch's Sync.mc matches it.

## Deploy on Railway

The server has no dependencies, so Railway builds it straight from package.json and runs `npm start`. Railway sets PORT and terminates HTTPS at its edge; the app serves plain HTTP behind it.

1. Install the CLI: `npm i -g @railway/cli`.
2. Run `railway login`.
3. From the server/ folder, run `railway init`, then `railway up`.
4. Set the key with `railway variables --set API_KEY=group16` (the key the watch sends). Without the variable the server also defaults to `group16`; with `API_KEY` set to empty it prints "WARNING: no API_KEY set on a public server" and anyone can change your minutes.
5. Run `railway domain` to get the public address.

Clients use `https://<domain>` and send the header `x-api-key`. The health check is `/health` (configured in railway.json).

Optional: add a volume mounted at `/data`. The server then saves to `/data/state.json`. Without a volume the container filesystem is ephemeral and state resets on every redeploy or restart. That is harmless for the watch: a fresh state gets a new usageEpoch and the watch rebaselines.
