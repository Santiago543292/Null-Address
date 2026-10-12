"""
Fix hub layout with direct text replacement.
- Remove overlapping road decals
- Move wall/ceiling lights to building walls
- Fix all floating/sunk objects
"""
import re
from pathlib import Path

HUB = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn")
BACKUP = Path("C:/Users/Santi/Null Address/null-address/Maps/HUBsc.tscn.final2_backup")

text = HUB.read_text(encoding="utf-8")
BACKUP.write_text(text, encoding="utf-8")

# 1. Remove all road decal nodes (they overlap with houses)
# Pattern: [node name="StreetProps#Decal_..." parent="." ...]\ntransform = ...
decal_pattern = r'\[node name="StreetProps#Decal_[^"]*" parent="\."[^\]]*\]\ntransform = Transform3D\([^)]*\)\n?'
text, n_decals = re.subn(decal_pattern, '', text)
print(f"Removed {n_decals} road decals")

# Remove arrow decals too
arrow_pattern = r'\[node name="StreetProps#Arrow_[^"]*" parent="\."[^\]]*\]\ntransform = Transform3D\([^)]*\)\n?'
text, n_arrows = re.subn(arrow_pattern, '', text)
print(f"Removed {n_arrows} arrow decals")

# Remove crosswalk decals
crosswalk_pattern = r'\[node name="StreetProps#Crosswalk_[^"]*" parent="\."[^\]]*\]\ntransform = Transform3D\([^)]*\)\n?'
text, n_crosswalks = re.subn(crosswalk_pattern, '', text)
print(f"Removed {n_crosswalks} crosswalk decals")

# Remove bike lane decals
bike_pattern = r'\[node name="StreetProps#BikeLane_[^"]*" parent="\."[^\]]*\]\ntransform = Transform3D\([^)]*\)\n?'
text, n_bikes = re.subn(bike_pattern, '', text)
print(f"Removed {n_bikes} bike lane decals")

# Remove lane line decals
lane_pattern = r'\[node name="StreetProps#LaneLine_[^"]*" parent="\."[^\]]*\]\ntransform = Transform3D\([^)]*\)\n?'
text, n_lanes = re.subn(lane_pattern, '', text)
print(f"Removed {n_lanes} lane line decals")

# 2. Fix all transforms: y > 0.3 -> y = 0, y < -0.05 -> y = 0
def fix_transform(match):
    tf_str = match.group(0)
    parts = tf_str.split("(")[1].rstrip(")").split(",")
    parts = [p.strip() for p in parts]
    y = float(parts[10])
    if y > 0.3 or y < -0.05:
        parts[10] = "0.0"
    return "transform = Transform3D(" + ", ".join(parts) + ")"

text = re.sub(r'transform = Transform3D\([^)]*\)', fix_transform, text)
print("Fixed all floating/sunk transforms")

# 3. Move wall lights to building walls (z=±58, y=2.5)
def fix_wall_light(m):
    header = m.group(1)
    tf_str = m.group(0)
    # Extract just the transform part
    tf_match = re.search(r'transform = Transform3D\(([^)]*)\)', tf_str)
    if not tf_match:
        return tf_str
    parts = [p.strip() for p in tf_match.group(1).split(",")]
    z = float(parts[11])
    if z < 0:
        parts[11] = "-58.0"
    else:
        parts[11] = "58.0"
    parts[10] = "2.5"
    new_tf = "transform = Transform3D(" + ", ".join(parts) + ")"
    return header + new_tf

wall_light_pattern = r'(name="StreetProps#WallLight_[^"]*"[^\]]*\]\n)transform = Transform3D\([^)]*\)'
text = re.sub(wall_light_pattern, fix_wall_light, text)
print("Moved wall lights to building walls")

# 4. Move ceiling lights to building overhangs (z=±55, y=3.0)
def fix_ceil_light(m):
    header = m.group(1)
    tf_str = m.group(0)
    tf_match = re.search(r'transform = Transform3D\(([^)]*)\)', tf_str)
    if not tf_match:
        return tf_str
    parts = [p.strip() for p in tf_match.group(1).split(",")]
    z = float(parts[11])
    if z < 0:
        parts[11] = "-55.0"
    else:
        parts[11] = "55.0"
    parts[10] = "3.0"
    new_tf = "transform = Transform3D(" + ", ".join(parts) + ")"
    return header + new_tf

ceil_light_pattern = r'(name="StreetProps#CeilLight_[^"]*"[^\]]*\]\n)transform = Transform3D\([^)]*\)'
text = re.sub(ceil_light_pattern, fix_ceil_light, text)
print("Moved ceiling lights to building overhangs")

# Write
HUB.write_text(text, encoding="utf-8")
print(f"Backup at: {BACKUP}")
