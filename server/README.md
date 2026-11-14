# WatchLock server

A small Node server that holds the numbers the watch and the phone share: tax minutes and credit minutes from the watch, and minutes of phone use today from the iPhone (or from the control panel). It has no dependencies and needs Node 18 or newer.

Start it with `node server.js` (or `npm start`). Run the tests with `npm test`. Open the control panel at `http://127.0.0.1:48217/`.

## Environment variables

- `PORT`: default 48217.
- `API_KEY`: if set, /state and /usage need the header `x-api-key` or the query `?key=`.
- `DATA_FILE`: where state is saved, default `state.json` next to server.js.

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

## Networking

On the first run Windows asks about the firewall. Allow Private networks, or the phone cannot reach the server. For the same Wi-Fi case, open the printed LAN URL on the iPhone.

## Exposure

The server listens on the LAN over plain HTTP. Set API_KEY for demos so nobody on the Wi-Fi can zero taxMinutes, and make sure the API_KEY constant in the watch's Sync.mc matches it.
