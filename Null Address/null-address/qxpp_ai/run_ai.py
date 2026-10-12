"""Null Address AI - interactive launcher.

Run this to talk to the QX++ level architect. Double-click `run_ai.bat` on
Windows, or:

    python3 run_ai.py

WHY THIS EXISTS
---------------
Running `level_architect.QX+` directly with the C++ binary (qxpp.exe) crashes
or silently produces wrong values, because the C++ interpreter has four
confirmed bugs:

  1. `for` loops print nothing at all.
  2. `int()` does not exist.
  3. A large integer multiply overflows int32 and ABORTS with
     "std::out_of_range: stoi: out of range".
  4. Assignment inside an `if` body never applies. Verified:
         if venue == "office" { flag = 1 }   ->  flag stays 0
     so a program cannot branch at all.

The Python interpreter handles all four correctly. This launcher always uses
it, so the AI actually works. The C++ binary is untouched and still on PATH.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import generate  # noqa: E402
import qx_bridge  # noqa: E402

VENUES = ["store", "office", "tunnel", "house"]

BANNER = """
=========================================================
  NULL ADDRESS  -  LEVEL ARCHITECT
  designed by your QX++ language
=========================================================
"""

MENU = """
  Acts:
    1) store   - THE CLOSED STORE   (act 1)
    2) office  - THE OFFICE FLOOR   (act 2)
    3) house   - THE HOUSE          (act 3)
    4) tunnel  - THE TUNNEL         (act 4)

  q) quit
"""


def show_backend() -> None:
    info = qx_bridge.available()
    print("  QX++ python interpreter :", info["python_interpreter"] or "NOT FOUND")
    print("  QX++ stdlib             :", info["stdlib"] or "NOT FOUND")
    print("  QX++ cpp binary         :", info["cpp_binary"] or "not present")
    print("  (the cpp binary is not used - it cannot run this program)")


def generate_act(venue: str) -> None:
    scene_name = f"gen_{venue}"
    print(f"\n  asking QX++ to design '{venue}' ...")

    try:
        plan, path = generate.generate(venue, scene_name, write=True)
    except qx_bridge.QXPPError as exc:
        print("\n  QX++ could not produce a plan:")
        print(" ", str(exc)[:600])
        return

    dead = plan.lights.count(0)
    failing = plan.lights.count(2)
    live = plan.lights.count(1)

    print("\n  --- QX++ decided ---")
    print(f"  act         : {plan.act}  {plan.act_title}")
    print(f"  grid        : {plan.cols} x {plan.rows} = {plan.room_count} rooms")
    print(f"  size        : {plan.width:.1f} x {plan.depth:.1f} x {plan.wall_h:.1f} m")
    print(f"  dread       : {plan.dread}")
    print(f"  lights      : {len(plan.lights)} fixtures"
          f"  ({dead} dead, {failing} failing, {live} live)")
    print(f"  prop groups : {len(plan.props)}")
    print(f"  doorways    : {len(plan.doors)}")
    print(f"\n  written to  : {path}")

    manifest = HERE / f"plan_{scene_name}.json"
    if manifest.is_file():
        data = json.loads(manifest.read_text(encoding="utf-8"))
        print(f"  manifest    : {manifest.name}")
        if "act" in data:
            print(f"  act tag     : {data['act']} - {data.get('act_title', '')}")

    print("\n  Open that scene in Godot to walk it.")


def main() -> int:
    print(BANNER)
    show_backend()
    print(MENU)

    while True:
        try:
            choice = input("  choose an act (or q): ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            return 0

        if choice in ("q", "quit", "exit"):
            print("  bye.")
            return 0

        venue = None
        if choice in ("1", "store"):
            venue = "store"
        elif choice in ("2", "office"):
            venue = "office"
        elif choice in ("3", "house"):
            venue = "house"
        elif choice in ("4", "tunnel"):
            venue = "tunnel"
        elif choice in VENUES:
            venue = choice

        if venue is None:
            print("  pick 1-4, or q.")
            continue

        generate_act(venue)
        print()


if __name__ == "__main__":
    raise SystemExit(main())
