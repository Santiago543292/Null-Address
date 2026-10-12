# QX++ Asset AI — for Null Address

## What it does

You ask for a venue. QX++ decides the whole layout — room grid, wall heights,
where doorways go, which lights are dead, how much furniture each room gets,
and a "dread score" that sets how oppressive the space should feel. Python
reads that plan and writes a `.tscn` you can open and play.

```
python3 generate.py office
python3 generate.py store
python3 generate.py tunnel
```

Each one writes `Maps/gen_<venue>.tscn` and a `plan_gen_<venue>.json` summary.

## The split, and why

```
level_architect.QX+   ← QX++ decides the design (prints a plan)
        ↓  key=value lines on stdout
generate.py           ← Python writes the Godot scene
        ↓
Maps/gen_office.tscn  ← a real, playable level
```

**QX++ is not wired into Godot at runtime.** The game has no dependency on QX++
being installed — you can open the project and play it with the language absent.
The AI runs ahead of time and produces scenes. That also means a crash in the
AI can never take the game down with it.

## Files

| File | Role |
|---|---|
| `level_architect.QX+` | The AI. Pure QX++, no Godot knowledge. |
| `qx_bridge.py` | Locates and runs QX++ **read-only**. Never writes into the QX++ tree. |
| `generate.py` | Reads a plan, writes a `.tscn`. |
| `plan_gen_*.json` | What the AI decided, per generated level. |

## Running it (start here)

Double-click **`run_ai.bat`**, or:

```
cd qxpp_ai
python3 run_ai.py
```

**Do NOT run `level_architect.QX+` directly.** The C++ interpreter (`qxpp.exe`)
crashes on it. Details below — it is not your setup, it is the interpreter.

## The C++ interpreter is broken (this is your crash)

Running the `.QX+` file directly gave:

```
libc++abi: terminating due to uncaught exception of type std::out_of_range: stoi: out of range
```

Four separate bugs, each confirmed by direct testing against `qxpp.exe`:

| # | Bug | Proof |
|---|---|---|
| 1 | A large integer multiply overflows int32 and **aborts the process** | `24 * 1103515245` → `stoi: out of range` |
| 2 | `for` loops print **nothing at all** | `for i in range(3) { print("i") }` → no output |
| 3 | `int()` does not exist | `unknown method: int` |
| 4 | Assignment inside an `if` body **never applies** | `if v == "office" { flag = 1 }` → `flag` stays 0 |

Bug 4 is the worst: it means a C++-run program **cannot branch at all**. Even
`if "office" == "office" { lit = 1 }` leaves `lit` at 0, while the same
comparison used directly in `print()` works fine.

The **Python interpreter** handles all four correctly. `run_ai.py` and
`qx_bridge.py` always use it. The C++ binary is left untouched on PATH.

The `.QX+` file is also written to avoid the bugs entirely — no loops, no
`int()`, no big numbers, and every branch lives in `main()` where string
comparison does work.

## The QX++ side

`level_architect.QX+` is deliberately plain — integers, floats, strings, loops,
functions. No tensor or ML modules, because this is spatial reasoning, not
learning. It's a rule engine with a deterministic seeded RNG, so the same venue
always produces the same layout.

**Venue profiles:**

| Act | Venue | Grid | Room | Dread | Title |
|---|---|---|---|---|
| 1 | `store` | 4 × 3 | 8 × 8 m | 0.45 | THE CLOSED STORE |
| 2 | `office` | 5 × 3 | 6 × 6 m | 0.70 | THE OFFICE FLOOR |
| 3 | `house` | 2 × 2 | 8 × 6 m | 0.80 | THE HOUSE |
| 4 | `tunnel` | 2 × 1 | 6 × 40 m | 0.95 | THE TUNNEL |

**Room sizes are multiples of 2 m and walls are 2.7 m tall on purpose** — the
ModularWalls_1 kit is a 2.00 m grid at 2.70 m, and nothing snaps otherwise.

Lights are spaced along each room's **long axis** (every 6 m), so a 40 m tunnel
gets 12 fixtures rather than one. Roughly half to three-quarters are dead,
depending on venue — tunnels are the darkest.

## Two QX++ gotchas this code works around

Both are real and will bite you again:

1. **`/` is true division, not floor division**, and `//` is a *comment*. So
   `i - (i / cols) * cols` does not give you a column index. Use
   `i - int(i / cols) * cols`. This silently produced `room_x=2.5` for every
   room until I caught it.

2. **The C++ interpreter's for-loop scoping is broken.** A loop accumulator
   stays at its initial value — `for i in range(5) { total = total + i }` leaves
   `total` at 0. The Python interpreter handles it correctly.

Because of (2), `qx_bridge.py` drives the **Python** interpreter. It falls back
to the C++ binary only for programs with no loop-carried state.

## Extending it

**A new venue:** add the four `venue_*` functions in `level_architect.QX+`
(cols, rows, room size, wall height, dread), then add `"newvenue"` to the
`choices` list in `generate.py`.

**New props:** add the category to `prop_count()` in the QX++ file and map the
name to a scene path in the `PROPS` dict in `generate.py`.

**The dread score** is exported to the plan and drives ambient light. Wire it
into `hub/presence.gd` to scale how often the house does something — high dread
means a busier, more hostile space.

## Geometry: real modular walls

The first version built rooms from plain boxes, which is exactly why they read
as "boxy". They are now assembled from the **ModularWalls_1** kit you already
have — 93 imported FBX parts on a measured 2.00 m grid:

    Wall          2.00 x 2.70 x 0.15
    WallCorner    2.05 x 2.70 x 2.04
    WallWindow_1  2.00 x 2.70 x 0.15
    WallDoor_1    2.00 x 2.70 x 0.15
    InteriorFloor 2.00 x 0.30 x 2.00
    Posts         0.25 x 3.19 x 0.25

Rooms are **hollow** — four wall runs around the perimeter, no slab over the
middle — which is most of the fix.

**Important:** those FBX parts carry **no collision**. The kit is the visible
skin; a set of invisible boxes in `WallColliders` is what actually stops the
player. Without them the walls look right and you walk straight through.

## Music

`autoload/music.gd` (autoloaded as `Music`) crossfades between beds:

    Music.play("menu")   # Park Bird & Reponix - Are You Lost (main menu)
    Music.play("hub")    # Dreamcorp - Nevermind Everything's Ok (ACT 0)

Both mp3s are set to loop in their `.import` files. Add a track by adding a row
to `TRACKS` — nothing else needs changing.

## Training on the hand-fixed maps

```
python3 train_on_maps.py
```

Measures `Maps/house.tscn` and `Maps/map_level_0.tscn` and writes
`learned_profile.json`, which the generator reads for a **density** multiplier.

**This is calibration, not a neural net, and it is worth being straight about
that.** QX++ cannot train a model — its C++ interpreter cannot even run a loop.
What it does is measure the maps you liked and bias the generator toward them.

It deliberately **does not** learn lighting from those maps. They are lit
(73–100% of fixtures on) because they are daytime exteriors; copying that would
brighten a horror game. Lighting stays driven by dread.

## Running it

```
cd qxpp_ai
python3 generate.py office
```

Requirements: Python 3.11+ and a QX++ install. The bridge finds QX++ at
`C:/Users/Santi/QIX AI/QX++` (source) or `%LOCALAPPDATA%/QX++` (installed).
Run `python3 qx_bridge.py` to print what it found.

**This code never modifies the QX++ installation.** It reads the interpreter and
stdlib, and writes its temp programs to the OS temp directory.
