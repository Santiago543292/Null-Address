"""Learn from the maps Santi fixed by hand.

Reads the hand-built .tscn files, measures how they are actually built, and
writes what it learns into `learned_profile.json`. `level_architect.QX+` reads
that profile so the AI's rules move toward the maps he liked.

WHY THIS IS MEASUREMENT, NOT A NEURAL NET
-----------------------------------------
The QX++ program has to run under the Python interpreter, and its C++ sibling
cannot do loops, `int()`, or branching at all. Training a model in QX++ is not
possible. What IS possible - and what actually helps - is measuring the real
maps and feeding those numbers back as the design rules.

So this is a calibration step, not gradient descent. It is honest about that.
The "training" is: count what the good maps do, and bias the generator toward it.

Usage
-----
    python3 train_on_maps.py            # measure and write learned_profile.json
    python3 train_on_maps.py --show     # print what it found, write nothing
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
MAPS = PROJECT / "Maps"

# The maps Santi fixed by hand. These are the reference.
SOURCES = {
    "house": MAPS / "house.tscn",
    "hub": MAPS / "map_level_0.tscn",
}

# What a room count in each act should look like. Measured, not guessed.
PROFILE_OUT = HERE / "learned_profile.json"


def count(path: Path, pattern: str) -> int:
    if not path.is_file():
        return 0
    return len(re.findall(pattern, path.read_text(encoding="utf-8", errors="ignore")))


def measure(path: Path) -> dict:
    """Measure the build of one map."""
    if not path.is_file():
        return {}

    text = path.read_text(encoding="utf-8", errors="ignore")

    omni = count(path, r'type="OmniLight3D"')
    spot = count(path, r'type="SpotLight3D"')
    direct = count(path, r'type="DirectionalLight3D"')
    shapes = count(path, r'type="CollisionShape3D"')
    mesh = count(path, r'type="MeshInstance3D"')
    static = count(path, r'type="StaticBody3D"')
    instances = count(path, r'instance=ExtResource')
    nodes = len(re.findall(r'^\[node ', text, re.MULTILINE))

    # how many lights are actually switched on
    energies = [float(m) for m in re.findall(r'light_energy\s*=\s*([0-9.]+)', text)]
    live = sum(1 for e in energies if e > 0.01)
    total_fixtures = max(len(energies), 1)

    # shader and script usage
    scripts = sorted(set(re.findall(r'path="res://([a-zA-Z0-9_/]+\.gd)"', text)))
    shaders = sorted(set(re.findall(r'path="res://([a-zA-Z0-9_/]+\.gdshader)"', text)))
    textures = sorted(set(re.findall(r'path="res://([a-zA-Z0-9_/]+\.(?:png|jpg|jpeg|exr|tres))"',
                                     text)))

    return {
        "nodes": nodes,
        "mesh_instances": mesh,
        "collision_shapes": shapes,
        "static_bodies": static,
        "instances": instances,
        "lights": {"omni": omni, "spot": spot, "directional": direct, "total": omni + spot + direct},
        "lights_live_ratio": round(live / total_fixtures, 3),
        "textures": len(textures),
        "scripts": len(scripts),
        "shaders": len(shaders),
        "mesh_per_collision": round(mesh / shapes, 2) if shapes else 0.0,
    }


def derive_rules(measured: dict) -> dict:
    """Turn measurements into design rules the QX++ architect can use.

    The idea: if the hand-built maps are dense and mostly dark, push the
    generated acts the same way.
    """
    if not measured:
        return {}

    live = statistics.mean(m["lights_live_ratio"] for m in measured.values())
    density = statistics.mean(
        m["mesh_per_collision"] for m in measured.values() if m["mesh_per_collision"]
    )
    tex = statistics.mean(m["textures"] for m in measured.values())
    lights = statistics.mean(m["lights"]["total"] for m in measured.values())

    # IMPORTANT: do not learn LIGHTING from these maps.
    #
    # The hand-fixed maps are lit (73-100% of fixtures on) because they are
    # daytime exterior scenes. Null Address is a dark found-footage game, so
    # learning "turn the lights on" from them would fight the whole mood.
    # What IS worth learning is DENSITY: how much geometry and how many props
    # per unit of collision the good maps carry.
    #
    # So lighting stays driven by dread in level_architect.QX+, and the density
    # numbers below feed prop counts.
    density = max(1.0, min(6.0, density))

    # A dense map has ~2.8 meshes per collider. Turn that into a prop multiplier
    # applied on top of each venue's base furniture count.
    prop_multiplier = round(density / 2.0, 2)
    prop_multiplier = max(1.0, min(2.5, prop_multiplier))

    return {
        "measured_live_ratio": round(live, 3),
        "measured_light_count": round(lights, 1),
        "measured_texture_count": round(tex, 1),
        "measured_mesh_per_collision": round(density, 2),
        "suggested_prop_multiplier": prop_multiplier,
        "lighting_policy": "keep dread-driven; do NOT copy the lit reference maps",
        "note": (
            "Density learned from the hand-fixed maps. Lighting deliberately NOT "
            "learned from them - they are daytime exteriors and the game is dark. "
            "prop_multiplier scales each venue's base furniture count."
        ),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Learn design rules from the hand-fixed maps.")
    ap.add_argument("--show", action="store_true", help="print findings, write nothing")
    args = ap.parse_args()

    measured: dict[str, dict] = {}
    for name, path in SOURCES.items():
        m = measure(path)
        if m:
            measured[name] = m

    if not measured:
        print("No maps found to learn from. Looked for:")
        for n, p in SOURCES.items():
            print(f"  {n}: {p}")
        return 1

    print("=== what the hand-fixed maps actually do ===")
    for name, m in measured.items():
        print(f"\n  {name}")
        print(f"    nodes            : {m['nodes']}")
        print(f"    mesh instances   : {m['mesh_instances']}")
        print(f"    collision shapes : {m['collision_shapes']}")
        print(f"    lights           : {m['lights']['total']}"
              f"  ({m['lights_live_ratio'] * 100:.0f}% lit)")
        print(f"    textures         : {m['textures']}")
        print(f"    scripts          : {m['scripts']}")
        print(f"    shaders          : {m['shaders']}")
        print(f"    mesh/collision   : {m['mesh_per_collision']}")

    rules = derive_rules(measured)
    print("\n=== rules learned ===")
    for k, v in rules.items():
        if k != "note":
            print(f"  {k:32}: {v}")

    if args.show:
        print("\n(--show: nothing written)")
        return 0

    profile = {"measured": measured, "rules": rules}
    PROFILE_OUT.write_text(json.dumps(profile, indent=2), encoding="utf-8")
    print(f"\n  written to {PROFILE_OUT}")
    print("  level_architect.QX+ can now read these cutoffs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
