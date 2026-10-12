"""
Add buildings, sidewalks, and containers to the hub to make it bigger.
"""
import math
import random
from pathlib import Path

random.seed(777)

HUB = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn")
BACKUP = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn.buildings_backup")

text = HUB.read_text(encoding="utf-8")
lines = text.split("\n")
header = lines[0]
rest = "\n".join(lines[1:])

BACKUP.write_text(text, encoding="utf-8")

existing_paths = set()
for line in lines:
    if line.startswith("[ext_resource"):
        parts = line.split('path="')
        if len(parts) > 1:
            existing_paths.add(parts[1].rstrip('"]'))

# Assets to add
BUILDING_LARGE = "res://Assets/Downtown City MegaKit[Standard]/Exports/glTF (Godot)/Building_Large_2.gltf"
BUILDING_MEDIUM = "res://Assets/Downtown City MegaKit[Standard]/Exports/glTF (Godot)/Building_Medium_2_001.gltf"
BUILDING_SMALL = "res://Assets/Downtown City MegaKit[Standard]/Exports/glTF (Godot)/Building_Small_1.gltf"
SIDEWALK_STRAIGHT = "res://Assets/Downtown City MegaKit[Standard]/Exports/glTF (Godot)/Sidewalk_Straight_3m.gltf"
SIDEWALK_CORNER = "res://Assets/Downtown City MegaKit[Standard]/Exports/glTF (Godot)/Sidewalk_Corner_Flat_3m.gltf"
CONTAINER_1 = "res://Assets/FlowerArrangementPack/Scenes/container/containers_1.tscn"
CONTAINER_2 = "res://Assets/FlowerArrangementPack/Scenes/container/containers_2.tscn"
CONTAINER_3 = "res://Assets/FlowerArrangementPack/Scenes/container/containers_3.tscn"
CONTAINER_4 = "res://Assets/FlowerArrangementPack/Scenes/container/containers_4.tscn"
CONTAINER_5 = "res://Assets/FlowerArrangementPack/Scenes/container/containers_5.tscn"
CONTAINER_6 = "res://Assets/FlowerArrangementPack/Scenes/container/containers_6.tscn"
CONTAINER_7 = "res://Assets/FlowerArrangementPack/Scenes/container/containers_7.tscn"

new_ext = []
eid = 300
asset_to_id = {}
for path in [BUILDING_LARGE, BUILDING_MEDIUM, BUILDING_SMALL, SIDEWALK_STRAIGHT, SIDEWALK_CORNER,
             CONTAINER_1, CONTAINER_2, CONTAINER_3, CONTAINER_4, CONTAINER_5, CONTAINER_6, CONTAINER_7]:
    if path not in existing_paths:
        ext_id = f"bd{eid}"
        new_ext.append(f'[ext_resource type="PackedScene" path="{path}" id="{ext_id}"]')
        asset_to_id[path] = ext_id
        eid += 1
    else:
        for line in lines:
            if line.startswith("[ext_resource") and path in line:
                parts = line.split('id="')
                if len(parts) > 1:
                    asset_to_id[path] = parts[1].rstrip('"]')
                break

def tf(x, y, z, yaw=0.0, scale=1.0):
    a = math.radians(yaw)
    c, s = math.cos(a), math.sin(a)
    return f"Transform3D({c*scale:.6f}, 0, {-s*scale:.6f}, 0, {scale:.6f}, 0, {s*scale:.6f}, 0, {c*scale:.6f}, {x}, {y}, {z})"

def inst(name, parent, ext_id, x, y, z, yaw=0.0, scale=1.0):
    return f'[node name="{name}" parent="{parent}" instance=ExtResource("{ext_id}")]\ntransform = {tf(x, y, z, yaw, scale)}\n'

props = []

# Buildings along the street (large buildings on both sides)
building_positions = [
    (-60, -35), (-40, -35), (-20, -35), (0, -35), (20, -35), (40, -35), (60, -35),
    (-60, 35), (-40, 35), (-20, 35), (0, 35), (20, 35), (40, 35), (60, 35),
]
for i, (bx, bz) in enumerate(building_positions):
    path = random.choice([BUILDING_LARGE, BUILDING_MEDIUM, BUILDING_SMALL])
    ext_id = asset_to_id.get(path, "")
    if ext_id:
        scale = random.uniform(0.8, 1.3)
        props.append(inst(f"Building_{i}", "Buildings", ext_id, bx, 0, bz, random.uniform(0, 360), scale))

# Sidewalks along the main road
for i in range(20):
    sx = -60 + i * 6
    sz = 18
    props.append(inst(f"Sidewalk_{i}", "StreetProps", asset_to_id[SIDEWALK_STRAIGHT], sx, 0.01, sz, 0))

for i in range(20):
    sx = -60 + i * 6
    sz = -18
    props.append(inst(f"SidewalkB_{i}", "StreetProps", asset_to_id[SIDEWALK_STRAIGHT], sx, 0.01, sz, 180))

# Containers in alleys and behind buildings
for i in range(10):
    cx = random.uniform(-50, 50)
    cz = random.choice([-25, 25])
    path = random.choice([CONTAINER_1, CONTAINER_2, CONTAINER_3, CONTAINER_4, CONTAINER_5, CONTAINER_6, CONTAINER_7])
    ext_id = asset_to_id.get(path, "")
    if ext_id:
        props.append(inst(f"Container_{i}", "StreetProps", ext_id, cx, 0, cz, random.uniform(0, 360)))

# Assemble
buildings_group = "\n[node name=\"Buildings\" type=\"Node3D\" parent=\".\"]\n"
buildings_group += "".join(props)

insert_pos = rest.rfind("\n[node")
if insert_pos == -1:
    insert_pos = len(rest)

new_rest = rest[:insert_pos] + "\n" + buildings_group + rest[insert_pos:]

new_text = header + "\n" + "\n".join(new_ext) + "\n" + new_rest
HUB.write_text(new_text, encoding="utf-8")

print(f"Added {len(props)} building/sidewalk/container nodes to HUBsc.tscn")
print(f"  Buildings: {len(building_positions)}")
print(f"  Sidewalks: 40")
print(f"  Containers: 10")
print(f"Backup at: {BACKUP}")
