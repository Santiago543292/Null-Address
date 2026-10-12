"""
Aggressive layout fix - remove problematic objects entirely.
- Remove all sidewalks (overlap with trees/barrels/crates)
- Remove all wall/ceiling lights (overlap with each other)
- Move all scatter items away from road (z=±18 -> z=±35)
- Fix ALL remaining floating objects
- Remove objects inside houses
"""
import re
from pathlib import Path

HUB = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn")
BACKUP = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn.aggressive2_backup")

text = HUB.read_text(encoding="utf-8")
BACKUP.write_text(text, encoding="utf-8")

# 1. Remove all sidewalk nodes
sidewalk_pattern = r'\[node name="StreetProps#Sidewalk[^"]*"[^\]]*\]\ntransform = Transform3D\([^)]*\)\n?'
text, n_sidewalks = re.subn(sidewalk_pattern, '', text)
print(f"Removed {n_sidewalks} sidewalks")

# 2. Remove all wall light nodes
wall_light_pattern = r'\[node name="StreetProps#WallLight[^"]*"[^\]]*\]\ntransform = Transform3D\([^)]*\)\n?'
text, n_wall_lights = re.subn(wall_light_pattern, '', text)
print(f"Removed {n_wall_lights} wall lights")

# 3. Remove all ceiling light nodes
ceil_light_pattern = r'\[node name="StreetProps#CeilLight[^"]*"[^\]]*\]\ntransform = Transform3D\([^)]*\)\n?'
text, n_ceil_lights = re.subn(ceil_light_pattern, '', text)
print(f"Removed {n_ceil_lights} ceiling lights")

# 4. Move all scatter items away from road (z=±18 -> z=±35)
def fix_scatter(match):
    tf_str = match.group(0)
    tf_match = re.search(r'transform = Transform3D\(([^)]*)\)', tf_str)
    if not tf_match:
        return tf_str
    parts = [p.strip() for p in tf_match.group(1).split(",")]
    z = float(parts[11])
    if abs(z) < 25:
        # Move further out
        if z < 0:
            parts[11] = "-35.0"
        else:
            parts[11] = "35.0"
    # Fix floating
    y = float(parts[10])
    if y > 0.3 or y < -0.05:
        parts[10] = "0.0"
    return "transform = Transform3D(" + ", ".join(parts) + ")"

scatter_pattern = r'(name="Scatter#[^"]*"[^\]]*\]\n)transform = Transform3D\([^)]*\)'
text = re.sub(scatter_pattern, lambda m: m.group(1) + fix_scatter(m), text)
print("Moved scatter items away from road")

# 5. Fix ALL remaining floating/sunk objects
def fix_all_transforms(match):
    tf_str = match.group(0)
    parts = tf_str.split("(")[1].rstrip(")").split(",")
    parts = [p.strip() for p in parts]
    y = float(parts[10])
    if y > 0.3 or y < -0.05:
        parts[10] = "0.0"
    return "transform = Transform3D(" + ", ".join(parts) + ")"

text = re.sub(r'transform = Transform3D\([^)]*\)', fix_all_transforms, text)
print("Fixed all remaining floating/sunk transforms")

# 6. Remove objects inside houses (furniture, lamp parts, etc.)
# Remove nodes whose names suggest they're inside houses
inside_house_pattern = r'\[node name="House_1#[^"]*"[^\]]*\]\ntransform = Transform3D\([^)]*\)\n?'
text, n_inside = re.subn(inside_house_pattern, '', text)
print(f"Removed {n_inside} objects inside houses")

# Write
HUB.write_text(text, encoding="utf-8")
print(f"Backup at: {BACKUP}")
