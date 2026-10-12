"""
Add street furniture and props to the hub scene to make it denser and more lived-in.
Reads HUBsc.tscn, adds a StreetProps group, populates it with instances of available assets.
"""
import math
import random
from pathlib import Path

random.seed(42)

HUB = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn")
BACKUP = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn.streetprops_backup")

# Asset paths (relative to res://)
BOLLARD = "res://Assets/Downtown City MegaKit[Standard]/Exports/glTF (Godot)/Prop_Bollard.gltf"
AC_UNIT = "res://Assets/Downtown City MegaKit[Standard]/Exports/glTF (Godot)/Prop_ACUnit.gltf"
BENCH = "res://Assets/KayKit_HalloweenBits_1.0_FREE/KayKit_HalloweenBits_1.0_FREE/Assets/gltf/bench.gltf"
FENCE = "res://Assets/KayKit_HalloweenBits_1.0_FREE/KayKit_HalloweenBits_1.0_FREE/Assets/gltf/fence.gltf"
FENCE_BROKEN = "res://Assets/KayKit_HalloweenBits_1.0_FREE/KayKit_HalloweenBits_1.0_FREE/Assets/gltf/fence_broken.gltf"
POST = "res://Assets/KayKit_HalloweenBits_1.0_FREE/KayKit_HalloweenBits_1.0_FREE/Assets/gltf/post.gltf"
PUMPKIN = "res://Assets/KayKit_HalloweenBits_1.0_FREE/KayKit_HalloweenBits_1.0_FREE/Assets/gltf/pumpkin_orange_jackolantern.gltf"
BARREL = "res://Assets/KayKit_Prototype_Bits_1.1_FREE/KayKit_Prototype_Bits_1.1_FREE/Assets/gltf/Barrel_A.gltf"
CRATE = "res://Assets/KayKit_Dungeon_Pack_1.1_FREE/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/crates_stacked.gltf"
TRASH = "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Props/props_trash_can.tscn"
SIGNPOST = "res://Assets/KayKit_HalloweenBits_1.0_FREE/KayKit_HalloweenBits_1.0_FREE/Assets/gltf/post_lantern.gltf"

FLOOR_Y = 0.0
PROP_SINK = 0.02

def tf(x, y, z, yaw=0.0):
    a = math.radians(yaw)
    c, s = math.cos(a), math.sin(a)
    return f"Transform3D({c:.6f}, 0, {-s:.6f}, 0, 1, 0, {s:.6f}, 0, {c:.6f}, {x}, {y}, {z})"

def prop(name, parent, scene, x, y, z, yaw=0.0):
    return f'[node name="{name}" parent="{parent}" instance=ExtResource("{scene}")]\ntransform = {tf(x, y, z, yaw)}\n'

# Read the hub scene
text = HUB.read_text(encoding="utf-8")
lines = text.split("\n")
header = lines[0]
rest = "\n".join(lines[1:])

# Backup
BACKUP.write_text(text, encoding="utf-8")

# Find the ext_resource IDs we need to add
existing_ext = set()
for line in lines:
    if line.startswith("[ext_resource"):
        # extract id
        parts = line.split('id="')
        if len(parts) > 1:
            existing_ext.add(parts[1].rstrip('"]'))

# Build new ext_resources and map asset keys to ext_ids
new_ext = []
asset_to_id = {}
eid = 100
asset_paths = {
    "bollard": BOLLARD, "ac_unit": AC_UNIT, "bench": BENCH,
    "fence": FENCE, "fence_broken": FENCE_BROKEN, "post": POST,
    "pumpkin": PUMPKIN, "barrel": BARREL, "crate": CRATE,
    "trash": TRASH, "signpost": SIGNPOST,
}
for key, path in asset_paths.items():
    if path not in existing_ext:
        ext_id = f"sp{eid}"
        new_ext.append(f'[ext_resource type="PackedScene" path="{path}" id="{ext_id}"]')
        asset_to_id[key] = ext_id
        eid += 1
    else:
        # find existing id
        for line in lines:
            if line.startswith("[ext_resource") and path in line:
                parts = line.split('id="')
                if len(parts) > 1:
                    asset_to_id[key] = parts[1].rstrip('"]')
                break

# Build the StreetProps group
props = []

# 1. Bollards along the street
for i in range(20):
    x = -40 + i * 8
    z = 12 + random.uniform(-0.5, 0.5)
    props.append(prop(f"Bollard_{i}", "StreetProps", asset_to_id["bollard"], x, FLOOR_Y, z, random.uniform(-10, 10)))

# 2. Benches near houses
house_positions = [
    (-35, -20), (-25, -20), (-15, -20), (-5, -20),
    (-35, 20), (-25, 20), (-15, 20), (-5, 20),
    (-45, 0), (-30, 0), (-10, 0), (0, 0)
]
for i, (hx, hz) in enumerate(house_positions):
    bx = hx + random.uniform(-3, 3)
    bz = hz + (5 if hz < 0 else -5)
    props.append(prop(f"Bench_{i}", "StreetProps", asset_to_id["bench"], bx, FLOOR_Y, bz, random.uniform(0, 360)))

# 3. Fences between properties
for i in range(8):
    fx = -40 + i * 10
    props.append(prop(f"Fence_{i}", "StreetProps", asset_to_id["fence"], fx, FLOOR_Y, 28, 0))

# 4. Barrels and crates in alleys
for i in range(6):
    ax = -38 + i * 14
    az = random.choice([-15, 15])
    props.append(prop(f"Barrel_{i}", "StreetProps", asset_to_id["barrel"], ax, FLOOR_Y, az, random.uniform(0, 360)))

for i in range(4):
    cx = -30 + i * 18
    cz = random.choice([-18, 18])
    props.append(prop(f"Crate_{i}", "StreetProps", asset_to_id["crate"], cx, FLOOR_Y, cz, random.uniform(0, 360)))

# 5. Trash cans near houses
for i, (hx, hz) in enumerate(house_positions[:6]):
    tx = hx + random.uniform(-4, 4)
    tz = hz + (3 if hz < 0 else -3)
    props.append(prop(f"Trash_{i}", "StreetProps", asset_to_id["trash"], tx, FLOOR_Y, tz, random.uniform(0, 360)))

# 6. Pumpkins near doors
for i, (hx, hz) in enumerate(house_positions):
    px = hx + random.uniform(-2, 2)
    pz = hz + (2 if hz < 0 else -2)
    props.append(prop(f"Pumpkin_{i}", "StreetProps", asset_to_id["pumpkin"], px, FLOOR_Y, pz, random.uniform(0, 360)))

# 7. AC units on house walls
for i, (hx, hz) in enumerate(house_positions):
    side = 1 if hz < 0 else -1
    props.append(prop(f"AC_{i}", "StreetProps", asset_to_id["ac_unit"], hx + 4, 1.5, hz + side * 2, 0))

# 8. Sign posts along the street
for i in range(5):
    sx = -35 + i * 18
    sz = 10
    props.append(prop(f"Sign_{i}", "StreetProps", asset_to_id["signpost"], sx, FLOOR_Y, sz, random.uniform(0, 360)))

# 9. Broken fences
for i in range(3):
    bx = -25 + i * 20
    props.append(prop(f"FenceBroken_{i}", "StreetProps", asset_to_id["fence_broken"], bx, FLOOR_Y, -28, 0))

# 10. Extra posts
for i in range(10):
    px = -40 + i * 9
    pz = random.choice([-25, 25])
    props.append(prop(f"Post_{i}", "StreetProps", asset_to_id["post"], px, FLOOR_Y, pz, random.uniform(0, 360)))

# Assemble
street_group = "\n[node name=\"StreetProps\" type=\"Node3D\" parent=\".\"]\n"
street_group += "".join(props)

# Insert into the scene: add ext_resources after line 0, add StreetProps before the last node
# Find the last [node] line
insert_pos = rest.rfind("\n[node")
if insert_pos == -1:
    insert_pos = len(rest)

new_rest = rest[:insert_pos] + "\n" + street_group + rest[insert_pos:]

# Write
new_text = header + "\n" + "\n".join(new_ext) + "\n" + new_rest
HUB.write_text(new_text, encoding="utf-8")

print(f"Added {len(props)} street props to HUBsc.tscn")
print(f"  Bollards: 20")
print(f"  Benches: {len(house_positions)}")
print(f"  Fences: 8 + 3 broken")
print(f"  Barrels: 6, Crates: 4")
print(f"  Trash: 6, Pumpkins: {len(house_positions)}")
print(f"  AC units: {len(house_positions)}, Signs: 5, Posts: 10")
print(f"Backup at: {BACKUP}")
