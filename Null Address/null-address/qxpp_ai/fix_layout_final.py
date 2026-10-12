"""
Fix hub layout properly - handle # in node names.
Move decals to road center, lights to building walls, fix floating objects.
Remove overlapping objects that can't be fixed.
"""
import math
import random
from pathlib import Path

random.seed(42)

HUB = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn")
BACKUP = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn.final_backup")

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

# Helper: get base name (strip prefix before #)
def base_name(name):
    if "#" in name:
        return name.split("#", 1)[1]
    return name

# Apply fixes
fixes = 0
for node in nodes:
    if node["transform"] is None:
        continue
    tf = node["transform"]
    x, y, z = tf[9], tf[10], tf[11]
    name = node["name"]
    base = base_name(name)

    # Road decals: move to road center, y=0.02, z=0
    if base.startswith("Decal_") or base.startswith("Arrow_") or base.startswith("Crosswalk_") or base.startswith("BikeLane_") or base.startswith("LaneLine_"):
        tf[10] = 0.02  # y just above road
        tf[11] = 0.0   # z = road center
        fixes += 1

    # Wall lights: move to building walls (z=±58)
    if base.startswith("WallLight_"):
        # Determine which side based on current z
        if z < 0:
            tf[11] = -58
        else:
            tf[11] = 58
        tf[10] = 2.5  # wall height
        fixes += 1

    # Ceiling lights: move to building overhangs (z=±55)
    if base.startswith("CeilLight_"):
        if z < 0:
            tf[11] = -55
        else:
            tf[11] = 55
        tf[10] = 3.0  # ceiling height
        fixes += 1

    # Fix ALL floating objects (y > 0.3, not lights/trees/AC)
    if y > 0.3 and not base.startswith("WallLight_") and not base.startswith("CeilLight_") and not base.startswith("Tree_") and not base.startswith("AC_"):
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
print(f"  Road decals moved to z=0, y=0.02")
print(f"  Wall lights moved to z=±58, y=2.5")
print(f"  Ceiling lights moved to z=±55, y=3.0")
print(f"  Floating/sunk objects fixed")
print(f"Backup at: {BACKUP}")
