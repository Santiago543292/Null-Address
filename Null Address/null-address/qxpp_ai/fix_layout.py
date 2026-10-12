"""
Fix hub layout: move buildings away from houses, decals to road center, lights to building walls.
"""
import math
import random
from pathlib import Path

random.seed(42)

HUB = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn")
BACKUP = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn.layout_backup")

text = HUB.read_text(encoding="utf-8")
lines = text.split("\n")
header = lines[0]
rest = "\n".join(lines[1:])

BACKUP.write_text(text, encoding="utf-8")

# Parse all nodes and their transforms
nodes = []
current = None
for i, line in enumerate(lines[1:], start=1):
    if line.startswith("[node "):
        if current:
            nodes.append(current)
        # Parse node header
        name = ""
        parent = ""
        if 'name="' in line:
            name = line.split('name="')[1].split('"')[0]
        if 'parent="' in line:
            parent = line.split('parent="')[1].split('"')[0]
        current = {"name": name, "parent": parent, "transform": None, "line_idx": i}
    elif current and "transform = Transform3D(" in line:
        # Extract transform values
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

# Fix 1: Move buildings further out (z=±35 -> z=±50)
# Fix 2: Move road decals to road center (z=0, y=0.02)
# Fix 3: Move wall lights to building walls (z=±48, y=2.5)
# Fix 4: Move ceiling lights to building overhangs (z=±45, y=3.0)
# Fix 5: Fix floating objects (y > 0.3 -> y = 0)

fixes = 0
for node in nodes:
    if node["transform"] is None:
        continue
    tf = node["transform"]
    x, y, z = tf[9], tf[10], tf[11]
    name = node["name"]

    # Buildings: move further out
    if name.startswith("Building_"):
        if abs(z - 35) < 5 or abs(z + 35) < 5:
            new_z = 50 if z > 0 else -50
            tf[11] = new_z
            fixes += 1

    # Road decals: move to road center
    if name.startswith("Decal_") or name.startswith("Arrow_") or name.startswith("Crosswalk_") or name.startswith("BikeLane_") or name.startswith("LaneLine_"):
        tf[11] = 0.0  # z = 0 (road center)
        tf[10] = 0.02  # y = 0.02 (just above road)
        fixes += 1

    # Wall lights: move to building walls
    if name.startswith("WallLight_"):
        if abs(z - 32) < 5 or abs(z + 32) < 5:
            new_z = 48 if z > 0 else -48
            tf[11] = new_z
            fixes += 1

    # Ceiling lights: move to building overhangs
    if name.startswith("CeilLight_"):
        if abs(z - 28) < 5 or abs(z + 28) < 5:
            new_z = 45 if z > 0 else -45
            tf[11] = new_z
            fixes += 1

    # Fix floating objects (y > 0.3 and not a light or tree)
    if y > 0.3 and not name.startswith("WallLight_") and not name.startswith("CeilLight_") and not name.startswith("Tree_") and not name.startswith("AC_"):
        tf[10] = 0.0
        fixes += 1

    # Fix sunk objects (y < -0.05)
    if y < -0.05:
        tf[10] = 0.0
        fixes += 1

# Rebuild the scene
new_lines = [header]
for i, line in enumerate(lines[1:], start=1):
    if "transform = Transform3D(" in line:
        # Find the node this transform belongs to
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
print(f"  Buildings moved to z=±50")
print(f"  Road decals moved to z=0")
print(f"  Wall lights moved to z=±48")
print(f"  Ceiling lights moved to z=±45")
print(f"  Floating/sunk objects fixed")
print(f"Backup at: {BACKUP}")
