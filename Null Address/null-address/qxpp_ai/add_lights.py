"""
Add more street lights and road decals to the hub for better visuals.
"""
import math
import random
from pathlib import Path

random.seed(999)

HUB = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn")
BACKUP = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn.lights_backup")

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
WALL_LIGHT = "res://Assets/Cenji_BackroomsLevel37_Poolrooms_FREE/GLB/PRP_06_WallLight.glb"
CEILING_LIGHT = "res://Assets/Cenji_BackroomsLevel37_Poolrooms_FREE/GLB/PRP_07_CeilingLight.glb"
DECAL_ARROW_FORWARD = "res://Assets/Downtown City MegaKit[Standard]/Exports/glTF (Godot)/Decal_ArrowStraight.gltf"
DECAL_CROSSWALK = "res://Assets/Downtown City MegaKit[Standard]/Exports/glTF (Godot)/Decal_Crosswalk.gltf"
DECAL_BIKELANE = "res://Assets/Downtown City MegaKit[Standard]/Exports/glTF (Godot)/Decal_Bikelane.gltf"
DECAL_BROKEN_LINE = "res://Assets/Downtown City MegaKit[Standard]/Exports/glTF (Godot)/Decal_BrokenLine_Straight.gltf"

new_ext = []
eid = 400
asset_to_id = {}
for path in [WALL_LIGHT, CEILING_LIGHT, DECAL_ARROW_FORWARD, DECAL_CROSSWALK, DECAL_BIKELANE, DECAL_BROKEN_LINE]:
    if path not in existing_paths:
        ext_id = f"lt{eid}"
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

# Wall lights on buildings
for i in range(20):
    bx = random.uniform(-60, 60)
    bz = random.choice([-32, 32])
    props.append(inst(f"WallLight_{i}", "StreetProps", asset_to_id[WALL_LIGHT], bx, 2.5, bz, random.uniform(0, 360)))

# Ceiling lights under building overhangs
for i in range(15):
    cx = random.uniform(-50, 50)
    cz = random.choice([-28, 28])
    props.append(inst(f"CeilLight_{i}", "StreetProps", asset_to_id[CEILING_LIGHT], cx, 3.0, cz, 0))

# Road decals - arrows
for i in range(10):
    ax = -50 + i * 10
    az = 0
    props.append(inst(f"Arrow_{i}", "StreetProps", asset_to_id[DECAL_ARROW_FORWARD], ax, 0.02, az, 0))

# Crosswalks at intersections
for i in range(8):
    cx = -40 + i * 12
    cz = 0
    props.append(inst(f"Crosswalk_{i}", "StreetProps", asset_to_id[DECAL_CROSSWALK], cx, 0.02, cz, 90))

# Bike lanes
for i in range(6):
    bx = -45 + i * 18
    bz = 8
    props.append(inst(f"BikeLane_{i}", "StreetProps", asset_to_id[DECAL_BIKELANE], bx, 0.02, bz, 0))

# Broken lane lines
for i in range(12):
    lx = -55 + i * 10
    lz = 0
    props.append(inst(f"LaneLine_{i}", "StreetProps", asset_to_id[DECAL_BROKEN_LINE], lx, 0.02, lz, 0))

# Assemble
lights_group = "\n[node name=\"ExtraLights\" type=\"Node3D\" parent=\".\"]\n"
lights_group += "".join(props)

insert_pos = rest.rfind("\n[node")
if insert_pos == -1:
    insert_pos = len(rest)

new_rest = rest[:insert_pos] + "\n" + lights_group + rest[insert_pos:]

new_text = header + "\n" + "\n".join(new_ext) + "\n" + new_rest
HUB.write_text(new_text, encoding="utf-8")

print(f"Added {len(props)} light/decal nodes to HUBsc.tscn")
print(f"  Wall lights: 20")
print(f"  Ceiling lights: 15")
print(f"  Road arrows: 10")
print(f"  Crosswalks: 8")
print(f"  Bike lanes: 6")
print(f"  Lane lines: 12")
print(f"Backup at: {BACKUP}")
