"""
Aggressive hub layout fix:
- Move houses further from road (z=±20 -> z=±30)
- Move buildings even further out (z=±50 -> z=±60)
- Move ALL road decals to y=0.02, z=0, and only on road segments
- Move ALL wall/ceiling lights to building walls (z=±58)
- Fix ALL floating objects (y > 0.3 -> y = 0)
- Fix ALL sunk objects (y < -0.05 -> y = 0)
"""
import math
import random
from pathlib import Path

random.seed(42)

HUB = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn")
BACKUP = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn.aggressive_backup")

text = HUB.read_text(encoding="utf-8")
lines = text.split("\n")
header = lines[0]

BACKUP.write_text(text, encoding="utf-8")

# Parse all nodes with their line indices and transforms
nodes = []
current = None
for i, line in enumerate(lines[1:], start=1):
    if line.startswith("[node "):
        if current:
            nodes.append(current)
        name = ""
        parent = ""
        if 'name="' in line:
            name = line.split('name="')[1].split('"')[0]
        if 'parent="' in line:
            parent = line.split('parent="')[1].split('"')[0]
        current = {"name": name, "parent": parent, "transform": None, "line_idx": i}
    elif current and "transform = Transform3D(" in line:
        tf_str = line.split("transform = Transform3D(")[1].rstrip(")")
        parts = [float(x.strip()) for x in tf_str.split(",")]
        current["transform"] = parts
    elif line.startswith("[") and not line.startswith("[node"):
        if current:
            nodes.append(current)
            current = None

if current:
    nodes.append(current)

print(f"Parsed {len(nodes)} nodes")

# Apply fixes
fixes = 0
for node in nodes:
    if node["transform"] is None:
        continue
    tf = node["transform"]
    x, y, z = tf[9], tf[10], tf[11]
    name = node["name"]

    # Houses: move further from road (z=±20 -> z=±30)
    if name.startswith("House") and not name.startswith("HouseB"):
        if abs(z - 20) < 5 or abs(z + 20) < 5:
            new_z = 30 if z > 0 else -30
            tf[11] = new_z
            fixes += 1

    # HouseB: move even further (z=±30 -> z=±40)
    if name.startswith("HouseB"):
        if abs(z - 30) < 5 or abs(z + 30) < 5:
            new_z = 40 if z > 0 else -40
            tf[11] = new_z
            fixes += 1

    # Buildings: move even further out (z=±50 -> z=±60)
    if name.startswith("Building_"):
        if abs(z - 50) < 5 or abs(z + 50) < 5:
            new_z = 60 if z > 0 else -60
            tf[11] = new_z
            fixes += 1

    # Road decals: move to road center, only on road segments (x between -60 and 60, z=0)
    if name.startswith("Decal_") or name.startswith("Arrow_") or name.startswith("Crosswalk_") or name.startswith("BikeLane_") or name.startswith("LaneLine_"):
        tf[11] = 0.0  # z = 0 (road center)
        tf[10] = 0.02  # y = 0.02 (just above road)
        # Only keep decals on the road (not under houses)
        if abs(x) > 60:
            tf[9] = 0.0  # move to center
        fixes += 1

    # Wall lights: move to building walls (z=±58)
    if name.startswith("WallLight_"):
        if abs(z - 48) < 5 or abs(z + 48) < 5:
            new_z = 58 if z > 0 else -58
            tf[11] = new_z
            fixes += 1

    # Ceiling lights: move to building overhangs (z=±55)
    if name.startswith("CeilLight_"):
        if abs(z - 45) < 5 or abs(z + 45) < 5:
            new_z = 55 if z > 0 else -55
            tf[11] = new_z
            fixes += 1

    # Fix ALL floating objects (y > 0.3, not lights/trees/AC)
    if y > 0.3 and not name.startswith("WallLight_") and not name.startswith("CeilLight_") and not name.startswith("Tree_") and not name.startswith("AC_"):
        tf[10] = 0.0
        fixes += 1

    # Fix ALL sunk objects (y < -0.05)
    if y < -0.05:
        tf[10] = 0.0
        fixes += 1

# Rebuild the scene with fixed transforms
new_lines = [header]
for i, line in enumerate(lines[1:], start=1):
    if "transform = Transform3D(" in line:
        for node in nodes:
            if node["line_idx"] == i and node["transform"] is not None:
                tf = node["transform"]
                new_tf = f"transform = Transform3D({tf[0]:.6f}, {tf[1]:.6f}, {tf[2]:.6f}, {tf[3]:.6f}, {tf[4]:.6f}, {tf[5]:.6f}, {tf[6]:.6f}, {tf[7]:.6f}, {tf[8]:.6f}, {tf[9]:.6f}, {tf[10]:.6f}, {tf[11]:.6f})"
                new_lines.append(new_tf)
                break
        else:
            new_lines.append(line)
    else:
        new_lines.append(line)

new_text = "\n".join(new_lines)
HUB.write_text(new_text, encoding="utf-8")

print(f"Applied {fixes} layout fixes")
print(f"  Houses moved to z=±30")
print(f"  HouseB moved to z=±40")
print(f"  Buildings moved to z=±60")
print(f"  Road decals moved to z=0, y=0.02")
print(f"  Wall lights moved to z=±58")
print(f"  Ceiling lights moved to z=±55")
print(f"  Floating/sunk objects fixed")
print(f"Backup at: {BACKUP}")
