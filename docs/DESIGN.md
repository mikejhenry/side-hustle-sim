# Side Hustle Sim: Design Doc

## Pitch

A grounded, funny gig-economy life sim. You live off parody gig apps in a compressed version of
New Castle County, Delaware. Every dollar fights rent, gas, oil changes, and your own body. The
dream: trade the 1999 Rustwagon and a rented room for a Voltz EV and a house in Brandywine Hills.

## Pillars

1. **The phone is the job.** Offers, routes, shopping lists, scans, and photos all happen on an
   in-game phone. Each app plays differently.
2. **Your body and your car are both wearing out.** Hunger, bladder, sleep, gas, oil, and tires
   all compete for time and money.
3. **Peak times create decisions.** Which app is surging right now? Is it worth skipping sleep?
4. **Visible progress.** Every upgrade (car, home) changes how you play, not just a number.

## Core loop

```
Wake up -> check bills and peak times -> go online -> accept offer -> drive -> walk in ->
use phone -> deliver -> get paid -> eat / pee / gas / oil as needed -> sleep -> repeat
         \-> save up -> buy car (unlocks rideshare, better mpg/comfort) / move (better sleep)
```

## Systems (built in the vertical slice)

### Time
- 1 game minute = 2 real seconds (a day is 48 real minutes). `REAL_SECONDS_PER_GAME_MINUTE`.
- Day/night cycle drives lighting, streetlights, headlights, and app demand.

### Needs
| Need | Fills/drains | Fix | If ignored |
| --- | --- | --- | --- |
| Hunger | Drains ~17 game hours | Restaurants, WahWah, fridge | Energy drains 2.5x, slower walking |
| Bladder | Fills ~8 game hours | Any restroom | Accident: $30, 1-star ride if passenger aboard |
| Energy | Drains ~25 game hours | Sleep (bed > car), coffee | Drowsy vignette, steering drift, pass out |
| Phone battery | Drains faster when online | Charges in the car / while sleeping at home | Apps go offline |

### Money and bills
- Bills every 3 days (`BILL_CYCLE_DAYS`): rent, phone ($15), car insurance (by car).
- Auto-pay at 9 AM on the due day. Can't pay -> $25 late fee.
- Rent 2+ days overdue -> evicted (sleep in car until you sign a new lease).
- Phone bill 1+ day overdue -> service suspended, gig apps won't work.
- Bank app shows bills, lets you pay early, and lists transactions.

### Housing
| Home | Rent / 3 days | Move-in | Sleep quality |
| --- | --- | --- | --- |
| Dottie's Boarding House room | $95 | start | 80% |
| Maple Court studio | $160 | $450 + rent | 100% |
| Lakeview Towers 2BR | $260 | $1,200 + rent | 115% |
| Brandywine Hills house | $420 | $7,500 + rent | 130% |

### Cars
| Car | Price | MPG | Notes |
| --- | --- | --- | --- |
| 1999 Rustwagon | start | 20 | Too old for rideshare. Low oil, worn tires. |
| 2013 Hondo Civil | $1,400 | 31 | Unlocks Yoober and Drift |
| 2018 Toyoyo Pious Hybrid | $4,200 | 52 | Cheap to run |
| 2021 Folkswagon Passit | $9,500 | 34 | Comfy, better ride pay |
| 2025 Voltz Model Tree EV | $21,000 | 120 eq. | Fast, best comfort |

Wear per game mile: oil life, tire tread, fuel. No oil = engine damage. Bald tires = less grip.
Crashes damage the engine. Services at Lube & Tube; gas at WahWah; tow from the Garage app.
Trade-in value depends on engine health.

### Gig apps
| App | Kind | Peaks | Pay model |
| --- | --- | --- | --- |
| Yoober | ride | 7-9, 16-19, 22-2 | base + per mile, x surge, x car comfort, tips for 5 stars |
| Drift | ride | 6-9, 17-20, 23-3 | same, different numbers |
| DoorDish | food | 11-14, 17-21 | base + per mile + Peak Pay + tip (tip cut if late) |
| Instacrate | grocery | 9-12, 15-19 | base + per item + per mile + tip |
| Jungle Flex | blocks | 6-8, 17-19 | fixed block pay x surge, partial pay if unfinished |

- Ratings (per app) go up with good jobs and down with crashes, lateness, and cancellations.
  Low ratings mean fewer offers.
- One active job at a time in the slice (multi-apping is on the roadmap).

### Map: New Castlewood County
A 5x5 grid of 90 m blocks inside the I-95 Beltway. Parody nods to the real county:

| Real | In game |
| --- | --- |
| Wilmington, Rodney Square | Wilmingtown downtown, Rodknee Square (park + public restroom) |
| Newark / University of Delaware | Newerk Rd, University of Delawhere, Blue Chicken housing |
| Wawa | WahWah (gas + hoagies) |
| Acme / ShopRite | Ackme Market / ShopWrite |
| Grotto Pizza / Capriotti's | Grotty Pizza / Capritoni's |
| Concord Pike, Kirkwood Hwy, Route 40, Route 202, Market St, King St | street names |
| Port of Wilmington / Amazon DE stations | Jungle Flex DNC9 station on the east side |

Enterable interiors: all 9 restaurants, both grocery stores, WahWah market, Lube & Tube (drive-in
bay), Honest Al's office, the Jungle Flex warehouse (drive-in), the laundromat, the park restroom,
and all 4 homes (bed, toilet, fridge, leasing desk). Houses and apartment complexes are delivery
addresses (101 in total) with doorstep drop-off points.

## Architecture

- **Code-built world.** `town.gd` builds roads, lots, buildings and interiors from primitives at
  startup. No binary assets, tiny repo, and every building type is a function you can tweak. It can
  later be swapped for hand-made scenes (`.tscn`) or imported models per building type without
  touching game logic, because jobs only depend on the `addresses / restaurants / stores / station`
  data the town exposes.
- **Autoloads.** `Game` owns state (time, needs, money, bills, car, home, save/load). `Gigs` owns the
  gig economy and the job state machine. UI and world objects call into them; they emit signals.
- **Interactables.** Any world object can expose `prompt()` and `action()` callables. `main.gd`
  picks the nearest one with a non-empty prompt and shows `[E] ...`.
- **Data-driven balance.** All numbers in `game_data.gd`.
- **Tests.** `tests/smoke_test.tscn` runs headless and plays through every job type.

## Roadmap

**Done**
- AI traffic, police with line-of-sight speeding detection, chases and tickets.
- Pedestrians on sidewalks.
- Sound: engine, horn, siren, crash, phone pings, ambience (synthesized).
- Quaternius character, trees and cop car; Poly Haven textures and props.
- Mirrors, turn-by-turn GPS, pause menu with settings, gamepad support, tutorial.

**Next (polish the slice)**
- Pedestrians crossing at crosswalks, with cars yielding.
- Turn signals, parking spot detection, parking tickets.
- More Quaternius cars/characters/trees once their download hosts are reachable.
- Real motion-capture walk clips (Mixamo) retargeted onto the character.

**Then (depth)**
- Multi-apping: accept offers from two apps at once and juggle them.
- Stacked orders, scheduled grocery deliveries, airport rides (an "ILG" parody airport).
- Customer personalities and chat messages; ride conversations.
- Credit score, car loans, credit card debt, emergency expenses (flat tire, parking tickets).
- Weather: rain lowers grip and raises demand.
- Car customization: phone mount, dashcam (fewer bad ratings), cooler bag (better tips).

**Bigger map**
- Grow from a 5x5 town to districts: Wilmingtown, Newerk, Bear/Glasgow sprawl along Route 40,
  Middletown subdivisions, Christiana Mall area, an I-95 run with on/off ramps, and the port.
- Stream districts in and out to keep performance good.
- File size stays small while the map is code/primitive-based; real 3D assets are what grows it
  (expect tens to a few hundred MB with a full art pass).
