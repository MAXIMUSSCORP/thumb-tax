# Thumb Tax

A Garmin watch app that turns phone scrolling into a screen-time bank: scroll and the watch charges you, move and it pays you back.

Built for the Tech Thursday x Garmin hackathon (Calgary, 2026-11-14). Prompt: "build something that makes your own health and wellness better."

## The problem

Doomscrolling costs sleep and focus, and it costs the most late at night, when one more swipe feels free. Nothing tells you the price while you are paying it. Thumb Tax shows the price on your wrist, live, and gives you a way to earn the time back.

## How it works: the bank

There is one balance, measured in minutes of screen time. It can go negative.

| Event | Effect on balance |
|---|---|
| Scrolling in the day (06:00 to 22:00) | Charged 1x |
| Scrolling at night (22:00 to 06:00) | Charged 2x (the sleep fee) |
| Scrolling at night in bed (wrist temperature at or above 33.0 C, estimated) | Charged 3x |
| Scrolling while the balance is negative (overdraft) | The watch buzzes, at most once every 10 s |
| Verified exercise, chores, outdoor time or calm time | Credited as a "tax return" (see the activity tables) |

Paying off debt and earning credit use the same path. A negative balance is debt that "punishments" (exercises) pay down. A positive balance is credit to scroll later. Walking is credited per kilometre and per metre climbed, and stairs per floor.

The last 20 balance changes are kept as a history. Daily totals (day scroll, night scroll, sleep fee, earned back) reset at local midnight.

## How scrolling is detected

Two signals feed one yes/no answer.

1. Phone side. A web feed reports real scrolling to a small local server. The watch polls it every 2 s:

   `GET http://127.0.0.1:8787/status` returns `{"scrolling": true}` or `{"scrolling": false}`

   A reading older than 6 s counts as offline, and offline time is never charged. The simulator reaches the server directly. A real watch sends the request through the paired phone.

2. On wrist, on real hardware. The summary page compares the magnetometer field to a baseline (START re-baselines). A jump of more than 40 units suggests a phone, with its speaker and magnets, is close to the wrist. The accelerometer adds the wrist pose of holding a phone.

The engine also accepts a manual scrolling override, used for demos.

## Earning time back

Each activity starts a detector, runs until you stop it, and credits only what the sensors verified. "Partly verified" means the watch confirms movement and effort but cannot prove the exact exercise, so the credit is an estimate. Where a sensor is missing, the session is flagged estimated, and rep exercises fall back to tapping to count.

Rates are minutes of credit per minute of verified activity, or seconds of credit per rep.

### Exercises

| Activity | Verified by | Pays | Verified |
|---|---|---|---|
| Jumping jacks | Accelerometer peaks (rep counter) | 3 s per rep | Yes |
| Squats | Accelerometer peaks | 6 s per rep | Yes |
| Lunges | Accelerometer peaks | 8 s per rep | Yes |
| High knees | Step cadence of 140 per min or more, heart rate 20 bpm above resting | 3 min per min | Yes |
| March in place | Step cadence of 80 per min or more | 1.5 min per min | Yes |
| Plank | Still wrist (low accelerometer variance) in a face-down pose | 3 min per min | Yes |
| Forearm plank | Same as plank | 3 min per min | Yes |
| Deadbug | Accelerometer peaks, 2 reps per detected cycle | 8 s per rep | Yes |
| Bird-dogs | Accelerometer peaks, 2 reps per detected cycle | 8 s per rep | Partly |
| Push-ups | Forearm tilt away from baseline by 20 degrees and back | 10 s per rep | Partly |
| Chair dips | Forearm tilt by 15 degrees and back | 10 s per rep | Partly |
| Mountain climbers | Heart rate 30 bpm above resting plus vigorous motion | 3 min per min | Partly |
| Glute bridges | Still wrist in a face-up pose | 2 min per min | Partly |

### Chores and outdoor

| Activity | Verified by | Pays | Verified |
|---|---|---|---|
| Cold shower | Skin temperature drop of 3 C, or a heart rate spike of 10 bpm when temperature is missing | 4 min per min, capped at 12 min per session | Yes |
| Stairs | Floor counter | 2 min per floor | Yes |
| Walk or hike | GPS distance plus barometric climb | 10 min per km, plus 12 s per metre climbed | Yes |
| Shovel snow or mow | GPS fix plus heart rate 15 bpm above resting | 1.5 min per min | Yes |
| Dance party | Heart rate 30 bpm above resting plus vigorous motion | 1.5 min per min | Yes |
| Morning sunlight | GPS fix outdoors, started within 2 h of your wake time | 1 min per min, capped at 10 min, once per day | Yes |
| Vacuum, mop or sweep | Heart rate 15 bpm above resting plus steady motion, session of 5 min or more | 1 min per min | Partly |
| Clean windows | Heart rate 15 bpm above resting plus steady motion | 1 min per min | Partly |
| Stretching | Heart rate 5 bpm above resting plus light motion | 0.75 min per min | Partly |

### Calm

Calm sessions count only while the wrist is still and heart rate stays under 90 bpm. Meditation adds a 5 min bonus when average heart rate over the last 30 s is at least 5 bpm below the first 30 s.

| Activity | Verified by | Pays | Verified |
|---|---|---|---|
| Meditation or breathing | Still wrist, heart rate under 90, heart rate drop bonus | 0.5 min per min, plus bonus | Yes |
| Read a book | Still wrist, heart rate under 90 | 0.5 min per min | Yes |
| Origami | Still wrist, heart rate under 90 | 0.5 min per min | Partly |
| Coloring or doodling | Still wrist, heart rate under 90 | 0.5 min per min | Partly |
| Embroidery or cross-stitch | Still wrist, heart rate under 90 | 0.5 min per min | Partly |
| Crochet or punch needle | Still wrist, heart rate under 90 | 0.5 min per min | Partly |
| Puzzle or diamond painting | Still wrist, heart rate under 90 | 0.5 min per min | Partly |

## Sensors

| Sensor | What it does |
|---|---|
| Heart rate | Effort checks against your resting rate, calm checks, the meditation bonus, cardio while scrolling, session average |
| Accelerometer | Rep counting, forearm tilt, still-hold checks, pose, motion variance, wrist pose for phone holding |
| GPS | Walk distance, and the outdoors check for mowing, shoveling and sunlight |
| Barometer / altitude | Climb during walks and hikes |
| Compass / magnetometer | Field disturbance from a phone near the wrist |
| Temperature | In-bed estimate (33.0 C or warmer), cold shower drop |
| Pulse ox | Overnight SpO2 trend page |
| Step and floor counters | Cadence for high knees and march, floors for stairs |
| User profile | Resting heart rate (60 if unset), wake time for sunlight and badge windows, sleep time for the sunset badge (07:00 and 23:00 if unset) |

## Badges

A clean day is a day with no overdraft scrolling and at least 1 h of monitored watch time. "Monitored" means the phone feed was online.

| Badge | Rule |
|---|---|
| First Clean Close | Your first clean day |
| Perfect Week | 7 clean days in a row (repeats) |
| Longest Streak | Beat your best clean streak (best must be at least 3) |
| 100 Clean Days | 100 clean days in total |
| 365 Clean Days | 365 clean days in total |
| 500 Clean Days | 500 clean days in total |
| 1,000 Clean Days | 1,000 clean days in total |
| Screen-Free Morning | No scrolling in the hour after waking, with 45 min monitored |
| Digital Sunset | No scrolling in the hour before bed, with 45 min monitored |
| Perfect Analog Week | 7 days in a row that are both clean and sunset-clean |
| Deep Work 100 | 100 awake minutes in a row without scrolling |
| Analog Fondo | 24 hours without scrolling (gaps up to 10 min are forgiven) |
| Weekend Off-Grid | A Saturday and Sunday each at 30 min of scrolling or less |
| Time Reclaimed: 10 h | Last month's scroll rate saved 10 h against the prior months |
| Time Reclaimed: 25 h | Same, 25 h |
| Time Reclaimed: 50 h | Same, 50 h |
| Local Legend | More credited activity sessions than scroll sessions in 30 days, at least 10 activities |
| Dopamine Detour | A scroll of 10 s or less, then you start an activity within 60 s |
| The Festive Unplug | Dec 24 to Jan 1, each day at 30 min or less |
| Sunday Reset | 4 phone-free Sunday mornings in a month (75% of wake to noon monitored and clean) |

Earning a badge buzzes the watch with a triple pulse. The badges above are the ones the watch can verify from its own clock and sensors. Greyscale and notification badges live on the phone side.

## The watch UI

The app opens on the thumb mascot, drawn from shapes so it fits the screen. Its mood follows the balance:

| Mood | Screen title | When |
|---|---|---|
| Reward | TAX RETURN | Balance is positive and you earned time in the last 10 min |
| Clear | ALL CLEAR | Nothing owed, not scrolling |
| Taxed | DAY TAX | Scrolling now, or the balance is negative in the day |
| Sleep debt | SLEEP TAX | Balance is negative at night |

The amount shows under the mascot, for example "+12 min" or "-4 min owed". UP and DOWN cycle the moods as a demo preview that holds for 10 s. START opens the sensor pages.

The sensor pages scroll with UP and DOWN:

| Page | Content |
|---|---|
| Live summary | Magnetometer gauge, PHONE? or NO PHONE status, balance, heart rate and temperature tiles. START re-baselines |
| Scroll tax | Minutes scrolled and minutes taxed |
| Sleep debt | Night scrolling and the sleep fee |
| Cardio | Heart rate while scrolling against not scrolling |
| Tax returns | Minutes earned back |
| Pulse ox | Overnight SpO2 |

On the trend pages START toggles WEEK and TODAY. Trends count night as 20:00 to 08:00 for exposure, and taxed figures are the seconds the bank actually charged. All shown values are estimates.

## Architecture

`source/`

| File | Purpose |
|---|---|
| `ThumbTaxApp.mc` | App entry, starts the engine |
| `ThumbTaxDelegate.mc` | Button and swipe input |
| `AvatarView.mc` | Home screen with the mascot, mood and amount |
| `Avatar.mc` | Mascot drawing for the four moods |
| `ThumbTaxView.mc` | Live summary page and the trend pages |
| `Trends.mc` | Trend page layouts |
| `Chart.mc` | Chart primitives |
| `Icons.mc` | Sensor and page icons |
| `CardioDay.mc` | Today's heart rate split by scrolling and not scrolling |

`source/backend/`

| File | Purpose |
|---|---|
| `Catalog.mc` | The single list of 29 activity kinds, detectors, thresholds and rates |
| `Ledger.mc` | The signed balance, multipliers, overdraft, daily stats, history |
| `Engine.mc` | 1 Hz heartbeat: reads sensors, charges scrolling, buzzes, saves |
| `ScrollSource.mc` | Polls the phone feed and holds the manual override |
| `Activities.mc` | Table-driven detectors that verify and credit activities |
| `Badges.mc` | Clean days, streaks, windows, monthly savings, badge awards |
| `Records.mc` | Stored history behind the trend pages |
| `*Test.mc` | Unit tests for activities, badges, ledger and records |

Data flow:

```
phone feed --> ScrollSource --> Engine (1 Hz) --> Ledger ----> UI
                                   |                ^
                                   +--> Records ----+
                                   +--> Badges -----+
Activities (sensors) --> Ledger, Badges
```

Engine reads heart rate, temperature and pulse ox, asks ScrollSource whether you are scrolling, charges the Ledger at the right multiplier, and feeds Records and Badges. Activities credits the Ledger when a session is verified and tells Badges. The UI reads `Engine.state()` and one change callback. State saves to on-watch storage every 30 s while scrolling and when a session ends.

## Build and run

Requirements: Connect IQ SDK 9.1.0, Java 17 or newer, and your own developer key.

Target: fenix 7 Pro, API 5.2. The app is developed and demoed in the Connect IQ simulator.

```
monkeyc -d fenix7pro -f monkey.jungle -o bin/ThumbTax.prg -y <developer_key> -w
connectiq
monkeydo bin/ThumbTax.prg fenix7pro
```

Run `connectiq` in one terminal to open the simulator, then `monkeydo` in another.

Unit tests:

```
monkeyc -d fenix7pro -f monkey.jungle -o bin/ThumbTax.prg -y <developer_key> -w --unit-test
monkeydo bin/ThumbTax.prg fenix7pro /t     (Windows)
monkeydo bin/ThumbTax.prg fenix7pro -t     (macOS and Linux)
```

Phone side: start the local server on port 8787, then open the web feed and scroll it. The watch picks up `{"scrolling": true}` within 2 s and starts charging.

Sideloading: connect the watch over USB and copy `bin/ThumbTax.prg` to `GARMIN/APPS`. Magnetometer and wrist behavior are only meaningful on real hardware.

## Privacy

No data leaves the watch except the local scroll signal. The watch reads `/status` and sends nothing back. Balance, history, records and badges stay in on-watch storage. All figures are estimates from wrist sensors. Thumb Tax is not a medical device and gives no diagnosis or medical advice.
