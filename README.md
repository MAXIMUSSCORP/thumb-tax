# Thumb Tax

A Garmin watch app that notices when you are scrolling your phone and bills the minutes to your sleep, with no phone app.

## The problem

I am the user. I scroll in bed, lose track of time, and sleep less than I planned. I know it and still do it, because nothing tells me what it costs while it is happening. Thumb Tax makes the cost visible at the moment of the scroll, and again the next morning.

## How it works

Planned (M1 to M4): the watch will detect "phone in hand, thumb moving" from its own sensors. While that is true it will buzz and show a running tax. In the morning it will show a statement. Today the app is only a sensor test screen: it shows the magnetometer delta against a baseline, inverts with "PHONE?" past a threshold, and reads accelerometer, heart rate and temperature. START re-baselines.

| Sensor | What it does |
|---|---|
| Magnetometer | A phone's speaker and MagSafe ring disturb the field near the wrist. A jump in field strength suggests a phone is in the hand. |
| Accelerometer | Matches the wrist pose of holding a phone, and the small repeated movement of a thumb flick. |
| Heart rate | Rise above the resting baseline while scrolling, reported as +bpm. |
| Temperature | A wrist under a blanket runs warmer, so scrolling in bed is counted as a double charge. |
| Pulse ox | The morning statement shows last night's SpO2 history. |

Habit loop, in bank language:

- Planned (M2), live: a buzz and a meter reading "Thumb Tax: -1 min of sleep" while you scroll. The framing is a loss, not a score.
- Planned (M3 and M4), morning: a statement with sessions, minutes withdrawn from sleep, +bpm, and a streak of tax-free nights.

All figures are estimates from wrist sensors. This is not a medical device and makes no diagnosis. No data leaves the watch.

## Build and run

Needs the Connect IQ SDK 9.1.0, Java 17 or newer, and your developer key.

```
monkeyc -d fenix7pro -f monkey.jungle -o bin/ThumbTax.prg -y <developer_key> -w
connectiq
monkeydo bin/ThumbTax.prg fenix7pro
```

To run on the watch, copy `bin/ThumbTax.prg` to the watch's `GARMIN/APPS` folder over USB. The simulator has no real magnetometer data, so detection has to be checked on the watch.

Target: Garmin fenix 7 Pro, API 5.2.0.

## Status

Built on the day of the Tech Thursday x Garmin hackathon in Calgary. What exists now: the M0 sensor test screen, compiled for fenix7pro. It has not been tested on the real watch yet. The detector, tax meter, vibration and morning statement are planned, not built.
