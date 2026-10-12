"""
Expand the hub: add more houses, trees, bushes, and street detail.
Reads HUBsc.tscn, adds instances of existing house and tree assets.
"""
import math
import random
from pathlib import Path

random.seed(1337)

HUB = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn")
BACKUP = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn.expand_backup")

# House instance pattern: reuse the existing house ext_resource
# Find the house ext_resource id from the scene
text = HUB.read_text(encoding="utf-8")
lines = text.split("\n")
header = lines[0]
rest = "\n".join(lines[1:])

# Backup
BACKUP.write_text(text, encoding="utf-8")

# Find existing ext_resource paths
existing_paths = set()
house_ext_id = None
tree_ext_ids = []
for line in lines:
    if line.startswith("[ext_resource"):
        parts = line.split('path="')
        if len(parts) > 1:
            path = parts[1].rstrip('"]')
            existing_paths.add(path)
            if "house_1" in path.lower() or "House_1" in line:
                # Extract the id= field, not uid= (which comes first)
                import re
                m = re.search(r'\bid="([^"]+)"', line)
                if m:
                    house_ext_id = m.group(1)

# Find tree ext_ids from the drive-download pack
tree_paths = [
    "res://Assets/drive-download-20261010T183029Z-1-001/glTF/BirchTree_1.gltf",
    "res://Assets/drive-download-20261010T183029Z-1-001/glTF/BirchTree_2.gltf",
    "res://Assets/drive-download-20261010T183029Z-1-001/glTF/BirchTree_3.gltf",
    "res://Assets/drive-download-20261010T183029Z-1-001/glTF/BirchTree_4.gltf",
    "res://Assets/drive-download-20261010T183029Z-1-001/glTF/BirchTree_5.gltf",
    "res://Assets/drive-download-20261010T183029Z-1-001/glTF/DeadTree_1.gltf",
    "res://Assets/drive-download-20261010T183029Z-1-001/glTF/DeadTree_10.gltf",
]
bush_paths = [
    "res://Assets/drive-download-20261010T183029Z-1-001/glTF/Bush.gltf",
    "res://Assets/drive-download-20261010T183029Z-1-001/glTF/Bush_Large.gltf",
    "res://Assets/drive-download-20261010T183029Z-1-001/glTF/Bush_Small.gltf",
    "res://Assets/drive-download-20261010T183029Z-1-001/glTF/Bush_Flowers.gltf",
]

# Build new ext_resources
new_ext = []
eid = 200
tree_to_id = {}
for path in tree_paths + bush_paths:
    if path not in existing_paths:
        ext_id = f"ex{eid}"
        new_ext.append(f'[ext_resource type="PackedScene" path="{path}" id="{ext_id}"]')
        tree_to_id[path] = ext_id
        eid += 1
    else:
        for line in lines:
            if line.startswith("[ext_resource") and path in line:
                parts = line.split('id="')
                if len(parts) > 1:
                    tree_to_id[path] = parts[1].rstrip('"]')
                break

def tf(x, y, z, yaw=0.0, scale=1.0):
    a = math.radians(yaw)
    c, s = math.cos(a), math.sin(a)
    return f"Transform3D({c*scale:.6f}, 0, {-s*scale:.6f}, 0, {scale:.6f}, 0, {s*scale:.6f}, 0, {c*scale:.6f}, {x}, {y}, {z})"

def inst(name, parent, ext_id, x, y, z, yaw=0.0, scale=1.0):
    return f'[node name="{name}" parent="{parent}" instance=ExtResource("{ext_id}")]\ntransform = {tf(x, y, z, yaw, scale)}\n'

# Add more houses (12 more, mirroring the existing 12)
new_houses = []
house_positions = [
    (-35, -20), (-25, -20), (-15, -20), (-5, -20),
    (-35, 20), (-25, 20), (-15, 20), (-5, 20),
    (-45, 0), (-30, 0), (-10, 0), (0, 0)
]
if house_ext_id:
    for i, (hx, hz) in enumerate(house_positions):
        # Offset further out
        new_houses.append(inst(f"HouseB_{i}", "Houses", house_ext_id, hx * 1.8, 0, hz * 1.5, random.uniform(0, 360)))

# Add trees (30 trees scattered around)
new_trees = []
for i in range(30):
    tx = random.uniform(-80, 80)
    tz = random.uniform(-50, 50)
    # Avoid placing trees inside houses
    too_close = False
    for hx, hz in house_positions:
        if abs(tx - hx) < 8 and abs(tz - hz) < 8:
            too_close = True
            break
    if too_close:
        continue
    path = random.choice(tree_paths)
    ext_id = tree_to_id.get(path, "")
    if ext_id:
        scale = random.uniform(0.8, 1.5)
        new_trees.append(inst(f"Tree_{i}", "Scatter", ext_id, tx, 0, tz, random.uniform(0, 360), scale))

# Add bushes (40 bushes)
new_bushes = []
for i in range(40):
    bx = random.uniform(-80, 80)
    bz = random.uniform(-50, 50)
    path = random.choice(bush_paths)
    ext_id = tree_to_id.get(path, "")
    if ext_id:
        scale = random.uniform(0.6, 1.4)
        new_bushes.append(inst(f"Bush_{i}", "Scatter", ext_id, bx, 0, bz, random.uniform(0, 360), scale))

# Add more street props (crates, barrels, etc.)
new_props = []
CRATE_PATH = "res://Assets/KayKit_Dungeon_Pack_1.1_FREE/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/crates_stacked.gltf"
BARREL_PATH = "res://Assets/KayKit_Prototype_Bits_1.1_FREE/KayKit_Prototype_Bits_1.1_FREE/Assets/gltf/Barrel_A.gltf"
BENCH_PATH = "res://Assets/KayKit_HalloweenBits_1.0_FREE/KayKit_HalloweenBits_1.0_FREE/Assets/gltf/bench.gltf"
BOLLARD_PATH = "res://Assets/Downtown City MegaKit[Standard]/Exports/glTF (Godot)/Prop_Bollard.gltf"

for path in [CRATE_PATH, BARREL_PATH, BENCH_PATH, BOLLARD_PATH]:
    if path not in existing_paths:
        ext_id = f"ex{eid}"
        new_ext.append(f'[ext_resource type="PackedScene" path="{path}" id="{ext_id}"]')
        tree_to_id[path] = ext_id
        eid += 1
    else:
        for line in lines:
            if line.startswith("[ext_resource") and path in line:
                parts = line.split('id="')
                if len(parts) > 1:
                    tree_to_id[path] = parts[1].rstrip('"]')
                break

for i in range(15):
    cx = random.uniform(-70, 70)
    cz = random.choice([-20, 20])
    new_props.append(inst(f"CrateB_{i}", "StreetProps", tree_to_id[CRATE_PATH], cx, 0, cz, random.uniform(0, 360)))

for i in range(10):
    bx = random.uniform(-60, 60)
    bz = random.choice([-18, 18])
    new_props.append(inst(f"BarrelB_{i}", "StreetProps", tree_to_id[BARREL_PATH], bx, 0, bz, random.uniform(0, 360)))

for i in range(8):
    bx = random.uniform(-50, 50)
    bz = random.choice([-15, 15])
    new_props.append(inst(f"BenchB_{i}", "StreetProps", tree_to_id[BENCH_PATH], bx, 0, bz, random.uniform(0, 360)))

for i in range(20):
    bx = -60 + i * 6
    bz = 14
    new_props.append(inst(f"BollardB_{i}", "StreetProps", tree_to_id[BOLLARD_PATH], bx, 0, bz, random.uniform(-10, 10)))

# Assemble
expand_group = "\n[node name=\"ExpandProps\" type=\"Node3D\" parent=\".\"]\n"
expand_group += "".join(new_houses + new_trees + new_bushes + new_props)

# Insert into the scene
insert_pos = rest.rfind("\n[node")
if insert_pos == -1:
    insert_pos = len(rest)

new_rest = rest[:insert_pos] + "\n" + expand_group + rest[insert_pos:]

# Write
new_text = header + "\n" + "\n".join(new_ext) + "\n" + new_rest
HUB.write_text(new_text, encoding="utf-8")

total = len(new_houses) + len(new_trees) + len(new_bushes) + len(new_props)
print(f"Added {total} new nodes to HUBsc.tscn")
print(f"  Houses: {len(new_houses)}")
print(f"  Trees: {len(new_trees)}")
print(f"  Bushes: {len(new_bushes)}")
print(f"  Street props: {len(new_props)}")
print(f"Backup at: {BACKUP}")
