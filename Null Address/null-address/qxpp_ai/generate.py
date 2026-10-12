"""Null Address asset generator.

Reads a level plan produced by the QX++ Level Architect and writes a Godot 4
scene (.tscn) plus a manifest.

This is the half that touches Godot. It is deliberately decoupled from the QX++
half: the QX++ program only prints a plan, this only consumes it. Neither
imports the other, so the game runs fine with no QX++ installed.

Usage
-----
    python3 generate.py office            # write Maps/gen_office.tscn
    python3 generate.py store --name shop # custom scene name
    python3 generate.py tunnel --no-write # plan only, print the summary
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path

import floorplan
import modular_walls
import qx_bridge

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
MAPS = PROJECT / "Maps"

# Godot material paths already present in the project (from the asset packs).
MAT = {
    "wall": "res://Assets/LoafbrrAssets/HouseAndPropsPack/Material/Wall_Lime.material",
    "wall_ext": "res://Assets/LoafbrrAssets/HouseAndPropsPack/Material/Wall_Bricks.material",
    "floor": "res://Assets/LoafbrrAssets/HouseAndPropsPack/Material/Floor_Wood_1.material",
    "floor2": "res://Assets/LoafbrrAssets/HouseAndPropsPack/Material/Floor_Wood_2.material",
    "roof": "res://Assets/LoafbrrAssets/HouseAndPropsPack/Material/Roof_Tiles.material",
    "trim": "res://Assets/LoafbrrAssets/HouseAndPropsPack/Material/Trim_Wood.material",
    "door": "res://Assets/LoafbrrAssets/HouseAndPropsPack/Material/Doors.material",
}

# --- Vertical placement ------------------------------------------------------
#
# The visible floor is the kit's `InteriorFloor` tiles, whose TOP surface sits at
# y = 0 (see modular_walls.py). The thin collider slab under them is centred at
# y = -0.35 with height 0.3, so ITS top is at y = -0.20 - i.e. 0.2 m BELOW the
# floor the player sees.
#
# Props were placed at y = 0.0, which is the visible floor exactly, so anything
# whose model origin is at its base sat correctly while anything modelled from
# its centre floated. Every prop now goes through `prop_y()`.
FLOOR_Y = 0.0

# Sink props a hair so they rest on the floor instead of on a hairline.
PROP_SINK = 0.02


def prop_y() -> float:
    """Y for an object that should rest on the visible floor."""
    return FLOOR_Y - PROP_SINK


# Furniture that belongs INSIDE a room, by venue. These are the pieces that stop
# a room reading as an empty box - the reported "rooms are not fully made".
# Chosen from the packs already in Assets/; all are floor-standing.
FURNITURE = {
    "house": [
        "res://Assets/KayKit_Furniture_Bits_1.0_FREE/KayKit_Furniture_Bits_1.0_FREE/Assets/gltf/bed_single_A.gltf",
        "res://Assets/KayKit_Furniture_Bits_1.0_FREE/KayKit_Furniture_Bits_1.0_FREE/Assets/gltf/cabinet_medium.gltf",
        "res://Assets/KayKit_Furniture_Bits_1.0_FREE/KayKit_Furniture_Bits_1.0_FREE/Assets/gltf/chair_A.gltf",
        "res://Assets/KayKit_Furniture_Bits_1.0_FREE/KayKit_Furniture_Bits_1.0_FREE/Assets/gltf/armchair.gltf",
    ],
    "office": [
        "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/table_rect_a.tscn",
        "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/chair_a.tscn",
        "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/cabinet_a_static.tscn",
        "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/shelf_a.tscn",
    ],
    "store": [
        "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/shelf_a.tscn",
        "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/crate_static.tscn",
        "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/container_a.tscn",
    ],
    "tunnel": [
        "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Props/props_locker.tscn",
        "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Props/props_chest.tscn",
    ],
}

# Prop scenes already in the project, by the category QX++ emits.
PROPS = {
    "desk": "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/table_rect_a.tscn",
    "chair": "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/chair_a.tscn",
    "cabinet": "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/cabinet_a_static.tscn",
    "shelf": "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/shelf_a.tscn",
    "crate": "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/crate_static.tscn",
    "cart": "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/container_a.tscn",
    "pipe": "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/barrel_a.tscn",
    "debris": "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Debris/debri_floor_debris_1.tscn",
    # detail dressing - what stops a room reading as an empty box
    "trash": "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Props/props_trash_can.tscn",
    "bucket": "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Props/props_bucket.tscn",
    "locker": "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Props/props_locker.tscn",
    "stool": "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Props/props_stool.tscn",
    "table": "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Props/props_table_1.tscn",
    "chest": "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Props/props_chest.tscn",
    "plugs": "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Props/props_plugs_a.tscn",
    "switch": "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Props/props_switch.tscn",
}

# Wall damage decals - applied to interior walls so the rooms look neglected.
WALL_DECALS = [
    "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Debris/debri_wall_debris_1.tscn",
    "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Debris/debri_wall_debris_2.tscn",
    "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Debris/debri_wall_debris_3.tscn",
    "res://Assets/BackroomsLikeAssetPack/Walls/Scenes/Debris/debri_wall_debris_4.tscn",
]

# Ceiling fixtures, so the lights read as installed hardware not floating orbs.
CEILING_FIXTURE = "res://Assets/LoafbrrAssets/WoodStuff/Scenes/WoodObjects/barrel_a.tscn"

# The ModularWalls_1 FBX parts ship with a normal map but NO albedo, so every
# wall renders as flat grey - that was the "bland" problem. This material wires
# up the kit's own Atlasv2Color.png plus its roughness/metal/AO maps.
WALL_ATLAS = "res://Assets/ModularWalls_1/wall_atlas.tres"

# The running order of acts, and what each gate leads to. The last act's gate
# loops back to the hub.
ACT_NEXT = {
    "store":  {"next": "office", "label": "ACT 2", "one_way": False},
    "office": {"next": "house",  "label": "ACT 3", "one_way": False},
    "house":  {"next": "tunnel", "label": "ACT 4", "one_way": False},
    "tunnel": {"next": "",       "label": "THE END", "one_way": True},
}

PLAYER = "res://Player.tscn"
PAUSE = "res://ui/pause_menu.gd"
HUD = "res://hub/hub_hud.gd"
FLICKER = "res://hub/flicker_light.gd"
WATCHER = "res://hub/watcher.gd"
HIDING = "res://hub/hiding_spots.gd"
HIDING_PROP = "res://Assets/KayKit_Furniture_Bits_1.0_FREE/KayKit_Furniture_Bits_1.0_FREE/Assets/gltf/cabinet_medium.gltf"


@dataclass
class Plan:
    venue: str = "office"
    cols: int = 1
    rows: int = 1
    room_w: float = 5.0
    room_h: float = 4.5
    wall_h: float = 2.8
    dread: float = 0.5
    room_count: int = 0
    rooms: list[tuple[float, float]] = field(default_factory=list)
    lights: list[int] = field(default_factory=list)
    light_pos: list[tuple[float, float]] = field(default_factory=list)
    props: list[tuple[str, int]] = field(default_factory=list)
    doors: list[str] = field(default_factory=list)
    # ACT identity - acts are the game's chapters, not "levels"
    act: int = 0
    act_title: str = ""
    # rule sheet (QX++ emits intent; Python applies it per room)
    light_spacing: float = 6.0
    dead_cut: int = 70
    fail_cut: int = 88
    energy_fail: float = 1.1
    energy_live: float = 2.0
    prop_base: dict = field(default_factory=dict)

    @property
    def width(self) -> float:
        return self.cols * self.room_w

    @property
    def depth(self) -> float:
        return self.rows * self.room_h


def learned_prop_multiplier() -> float:
    """Density learned from the hand-fixed maps (see train_on_maps.py).

    Returns 1.0 when there is no profile, so the generator works standalone.
    """
    f = HERE / "learned_profile.json"
    if not f.is_file():
        return 1.0
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
        return float(data.get("rules", {}).get("suggested_prop_multiplier", 1.0))
    except (ValueError, OSError):
        return 1.0


_PROP_MULT = learned_prop_multiplier()


def expand_rules(p: Plan) -> Plan:
    """Turn the QX++ rule sheet into per-room values.

    The C++ interpreter cannot run loops or apply assignments inside `if`
    bodies, so the .QX+ file states rules only. Python does the per-room
    arithmetic - which is the right split anyway.
    """
    if not p.room_count:
        p.room_count = p.cols * p.rows
    if p.rooms and p.lights:
        return p  # already expanded

    p.rooms = []
    for cz in range(p.rows):
        for cx in range(p.cols):
            p.rooms.append((cx * p.room_w + p.room_w * 0.5,
                            cz * p.room_h + p.room_h * 0.5))

    # lights: spaced along each room's long axis
    p.lights = []
    p.light_pos = []
    for idx, (rx, rz) in enumerate(p.rooms):
        along_long_x = p.room_w > p.room_h
        span = p.room_w if along_long_x else p.room_h
        n = max(1, int(span / max(p.light_spacing, 1.0)))
        for k in range(n):
            frac = (k + 0.5) / n
            lx = (rx - p.room_w * 0.5) + p.room_w * frac if along_long_x else rx
            lz = rz if along_long_x else (rz - p.room_h * 0.5) + p.room_h * frac
            roll = (idx * 37 + k * 11) % 100
            state = 0 if roll < p.dead_cut else (2 if roll < p.fail_cut else 1)
            p.lights.append(state)
            p.light_pos.append((round(lx, 2), round(lz, 2)))

    # furniture: base count + per-room variation
    p.props = []
    for idx in range(p.room_count):
        for cat, base in p.prop_base.items():
            if base <= 0:
                continue
            var = (idx * 31 + len(cat) * 7) % 3
            n = int(round((base + var) * _PROP_MULT))
            p.props.append((cat, max(1, n)))
    return p


def parse_plan(text: str) -> Plan:
    p = Plan()
    xs: list[float] = []
    zs: list[float] = []
    for raw in text.splitlines():
        line = raw.strip()
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        k, v = k.strip(), v.strip()
        if k == "venue":
            p.venue = v
        elif k == "cols":
            p.cols = int(float(v))
        elif k == "rows":
            p.rows = int(float(v))
        elif k == "room_w":
            p.room_w = float(v)
        elif k == "room_h":
            p.room_h = float(v)
        elif k == "wall_h":
            p.wall_h = float(v)
        elif k == "dread":
            p.dread = float(v)
        elif k == "rooms":
            p.room_count = int(float(v))
        elif k == "room_x":
            xs.append(float(v))
        elif k == "room_z":
            zs.append(float(v))
        elif k == "light":
            p.lights.append(int(float(v)))
        elif k == "light_x":
            _pending_x = float(v)
            p.light_pos.append([_pending_x, 0.0])
        elif k == "light_z":
            if p.light_pos:
                p.light_pos[-1][1] = float(v)
        elif k == "prop":
            p.props.append([v, 0])          # count filled on the next line
        elif k == "prop_count":
            if p.props:
                p.props[-1][1] = int(float(v))
        elif k == "door":
            p.doors.append(v)
        elif k == "act":
            p.act = int(float(v))
        elif k == "act_title":
            p.act_title = v
        elif k == "light_spacing":
            p.light_spacing = float(v)
        elif k == "dead_cut":
            p.dead_cut = int(float(v))
        elif k == "fail_cut":
            p.fail_cut = int(float(v))
        elif k == "energy_fail":
            p.energy_fail = float(v)
        elif k == "energy_live":
            p.energy_live = float(v)
        elif k.startswith("prop_base_"):
            p.prop_base[k[len("prop_base_"):]] = int(float(v))

    p.rooms = list(zip(xs, zs))
    p.light_pos = [tuple(v) for v in p.light_pos]
    p.props = [(a, b) for a, b in p.props]
    return expand_rules(p)


# ---------------------------------------------------------------- scene writer
class SceneBuilder:
    def __init__(self) -> None:
        self.ext: list[tuple[str, str, str]] = []
        self.sub: list[tuple[str, str, list[str]]] = []
        self.nodes: list[str] = []
        self._eid = 0
        self._sid = 0

    def ext_res(self, kind: str, path: str) -> str:
        for k, p, i in self.ext:
            if p == path:
                return i
        self._eid += 1
        i = f"e{self._eid}"
        self.ext.append((kind, path, i))
        return i

    def sub_res(self, kind: str, lines: list[str]) -> str:
        self._sid += 1
        i = f"s{self._sid}"
        self.sub.append((kind, i, lines))
        return i

    def box(self, name: str, parent: str, pos, size, mat: str, collide: bool = True) -> None:
        mesh_id = self.sub_res("BoxMesh", [
            f"size = Vector3({size[0]}, {size[1]}, {size[2]})",
            f"material = ExtResource(\"{mat}\")",
        ])
        tf = f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]}, {pos[1]}, {pos[2]})"
        self.nodes.append(
            chr(10).join([
                f'[node name="{name}" type="MeshInstance3D" parent="{parent}"]',
                f"transform = {tf}",
                f'mesh = SubResource("{mesh_id}")',
                "",
            ])
        )
        if collide:
            shp = self.sub_res("BoxShape3D", [f"size = Vector3({size[0]}, {size[1]}, {size[2]})"])
            self.nodes.append(
                chr(10).join([
                    f'[node name="{name}_col" type="CollisionShape3D" parent="{parent}"]',
                    f"transform = {tf}",
                    f'shape = SubResource("{shp}")',
                    "",
                ])
            )

    def collider(self, name: str, parent: str, pos, size) -> None:
        """An invisible collision box. Used to make imported kit geometry solid.

        The ModularWalls_1 FBX parts carry no collision of their own, so the
        walls look right but the player walks through them. These boxes are the
        physical walls; the kit is the visible skin.
        """
        shp = self.sub_res("BoxShape3D",
                           [f"size = Vector3({size[0]}, {size[1]}, {size[2]})"])
        tf = f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]}, {pos[1]}, {pos[2]})"
        self.nodes.append(
            chr(10).join([
                f'[node name="{name}" type="CollisionShape3D" parent="{parent}"]',
                f"transform = {tf}",
                f'shape = SubResource("{shp}")',
                "",
            ])
        )

    def _near_door(self, x: float, z: float, clearance: float = 1.9) -> bool:
        """Is this point close enough to a doorway to block it?

        A method rather than a nested function: the nested version could not see
        the enclosing scope and raised UnboundLocalError.
        """
        for (dx, dz) in getattr(self, "door_pts", []):
            if abs(dx - x) < clearance and abs(dz - z) < clearance:
                return True
        return False

    def instance(self, name: str, parent: str, scene: str, pos, yaw: float = 0.0) -> None:
        import math
        a = math.radians(yaw)
        c, s = math.cos(a), math.sin(a)
        tf = (f"Transform3D({c:.6f}, 0, {-s:.6f}, 0, 1, 0, {s:.6f}, 0, {c:.6f}, "
              f"{pos[0]}, {pos[1]}, {pos[2]})")
        i = self.ext_res("PackedScene", scene)
        self.nodes.append(
            f'[node name="{name}" parent="{parent}" instance=ExtResource("{i}")]\n'
            f"transform = {tf}\n"
        )

    def light(self, name: str, parent: str, pos, state: int, energy: float, phase: float) -> None:
        if state == 0:
            return  # dead fixture: no light node at all
        i = self.ext_res("Script", FLICKER)
        flick = ("flicker_enabled = true\nflicker_depth = 0.5\ndropout_rate = 0.5"
                 if state == 2 else "flicker_enabled = false")
        self.nodes.append(
            f'[node name="{name}" type="OmniLight3D" parent="{parent}"]\n'
            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]}, {pos[1]}, {pos[2]})\n"
            f"light_color = Color(0.80, 0.86, 0.82, 1)\n"
            f"light_energy = {energy}\nomni_range = 7.5\nshadow_enabled = true\n"
            f'script = ExtResource("{i}")\nbase_energy = {energy}\nphase_offset = {phase}\n'
            f"{flick}\n"
        )

    def build(self, plan: Plan, scene_name: str) -> str:
        import random
        rng = random.Random(hash(plan.venue) & 0xFFFF)

        m_wall = self.ext_res("Material", MAT["wall"])
        m_wallext = self.ext_res("Material", MAT["wall_ext"])
        m_floor = self.ext_res("Material", MAT["floor"])
        m_floor2 = self.ext_res("Material", MAT["floor2"])
        m_trim = self.ext_res("Material", MAT["trim"])

        W, D, H = plan.width, plan.depth, plan.wall_h

        self.nodes.append(
            f'\n[node name="{scene_name}" type="Node3D"]\n'
            f'\n[node name="WorldEnvironment" type="WorldEnvironment" parent="." groups=["world_environment"]]\n'
            f'environment = SubResource("ENV")\n'
        )
        env = self.sub_res("Environment", [
            "background_mode = 1",
            "background_color = Color(0.012, 0.014, 0.018, 1)",
            "ambient_light_source = 1",
            f"ambient_light_energy = {0.55 - 0.35 * plan.dread}",
            "ambient_light_color = Color(0.13, 0.15, 0.20, 1)",
            "tonemap_mode = 3",
            "tonemap_exposure = 1.25",
            "glow_enabled = true",
            "glow_intensity = 0.3",
            "fog_enabled = true",
            "fog_light_color = Color(0.10, 0.11, 0.14, 1)",
            "fog_density = 0.010",
            "ssao_enabled = true",
            "ssao_intensity = 0.8",
        ])
        # patch the placeholder id
        self.nodes = [n.replace("SubResource(\"ENV\")", f"SubResource(\"{env}\")") for n in self.nodes]

        # --- shell: real ModularWalls_1 geometry ---------------------------
        # NOTE: W and D are taken from the floor plan below, not from the old
        # uniform grid.
        # Plain boxes were what made every room read as a box. The kit is a
        # 2.00m grid of wall modules, so the shell is built from them instead.
        self.nodes.append('\n[node name="Shell" type="StaticBody3D" parent="."]')

        # thin collider floor + ceiling: the player cannot fall through or jump
        # out, while the VISIBLE floor is the kit's own tiles
        t = 0.3
        self.box("FloorCollider", "Shell", (0, -0.35, 0), (W, 0.3, D), m_floor, collide=True)
        self.box("Ceiling", "Shell", (0, H + 0.15, 0), (W, 0.3, D), m_floor2, collide=True)

        fp_plan = floorplan.plan_spine(plan.venue, rng)
        # W/D come from the floor plan now, not the old grid. Plan.width is a
        # computed property, so keep these as locals.
        W, D = fp_plan.width, fp_plan.depth
        wb = modular_walls.walls_from_plan(fp_plan, floorplan)
        self.nodes.append('\n[node name="WallKit" type="Node3D" parent="."]')
        atlas = self.ext_res("Material", WALL_ATLAS)
        for nm, scene, x, y, z, yaw in wb.placed:
            self.instance(nm, "WallKit", scene, (round(x, 3), round(y, 3), round(z, 3)), yaw)
            # The kit's own material ships with a normal map but NO albedo, so
            # every wall renders flat grey. Override surface 0 with the atlas
            # material - this is what actually makes the walls textured.
            child = scene.rsplit("/", 1)[-1].replace(".fbx", "")
            self.nodes.append(
                chr(10).join([
                    f'[node name="{child}" parent="WallKit/{nm}" index="0"]',
                    f'surface_material_override/0 = ExtResource("{atlas}")',
                    "",
                ])
            )
        wall_count = len(wb.placed)

        # The kit's FBX parts carry NO collision, so the walls above are only a
        # skin. These invisible boxes are the real, physical walls - emitted per
        # wall run, with a gap wherever the plan puts a doorway.
        self.nodes.append(chr(10) + '[node name="WallColliders" type="StaticBody3D" parent="."]')
        ct = 0.25
        # Cut the collider gap at the SAME module positions the walls used.
        # Deriving the two independently let them drift apart, which sealed the
        # rooms: the player could see a doorway and not walk through it.
        door_modules = set()
        for (dx, dz, dalong) in wb.door_spans:
            door_modules.add((round(dx, 2), round(dz, 2)))

        ci = 0
        for (wx0, wz0, wx1, wz1, wkind) in floorplan.wall_runs(fp_plan):
            wdx, wdz = wx1 - wx0, wz1 - wz0
            wlen = (wdx * wdx + wdz * wdz) ** 0.5
            if wlen < 0.1:
                continue
            along_x = abs(wdx) >= abs(wdz)
            n_mod = max(1, int(round(wlen / modular_walls.MODULE)))
            seg = wlen / n_mod
            for i in range(n_mod):
                frac = (i + 0.5) / n_mod
                mx = wx0 + wdx * frac
                mz = wz0 + wdz * frac
                # skip the modules that are doorways
                if (round(mx, 2), round(mz, 2)) in door_modules:
                    continue
                if along_x:
                    self.collider(f"Col{ci}", "WallColliders",
                                  (round(mx, 3), H / 2, round(mz, 3)), (round(seg, 3), H, ct))
                else:
                    self.collider(f"Col{ci}", "WallColliders",
                                  (round(mx, 3), H / 2, round(mz, 3)), (ct, H, round(seg, 3)))
                ci += 1

        # Partitions are part of the modular kit now - each room is hollow with
        # its own four wall runs, so there is nothing to add here.

        # --- beams, to break the ceiling ---
        self.nodes.append('\n[node name="Beams" type="MeshInstance3D" parent="."]')
        beam_gap = 2.2
        n_beams = max(1, int(D / beam_gap))
        for b in range(n_beams):
            z = -D / 2 + beam_gap * (b + 0.5)
            self.box(f"Beam{b}", "Beams", (0, H - 0.16, z), (W - 0.3, 0.32, 0.3), m_trim, collide=False)

        # --- lights from the QX++ plan ---
        self.nodes.append('\n[node name="Lights" type="Node3D" parent="."]')
        lit = 0
        positions = fp_plan.light_pos
        # the state pattern still comes from QX++'s dead/fail policy
        states = []
        for idx in range(len(positions)):
            roll = (idx * 37 + 11) % 100
            states.append(0 if roll < plan.dead_cut else (2 if roll < plan.fail_cut else 1))
        plan.lights = states
        plan.light_pos = positions
        for idx, (pos, state) in enumerate(zip(positions, states)):
            energy = 0.0 if state == 0 else (1.1 if state == 2 else 2.0)
            phase = round(0.37 * idx, 3)
            if state != 0:
                lit += 1
            self.light(f"Lamp{idx}", "Lights", (pos[0], H - 0.5, pos[1]), state, energy, phase)

        # --- props from the QX++ plan ---
        self.nodes.append('\n[node name="Props" type="Node3D" parent="."]')
        pi = 0
        for idx, (cat, count) in enumerate(plan.props):
            scene = PROPS.get(cat)
            if not scene:
                continue
            fr = fp_plan.rooms[idx % len(fp_plan.rooms)]
            room = (fr.cx, fr.cz)
            for n in range(count):
                # push toward the room's walls, not the middle
                side = rng.randrange(4)
                off_x = plan.room_w * 0.32
                off_z = plan.room_h * 0.32
                dx = rng.uniform(-off_x, off_x)
                dz = rng.uniform(-off_z, off_z)
                if side == 0:
                    dz = -off_z
                elif side == 1:
                    dz = off_z
                elif side == 2:
                    dx = -off_x
                else:
                    dx = off_x
                x = room[0] + dx
                z = room[1] + dz
                # nudge out of any doorway before placing
                for _try in range(12):
                    if not self._near_door(x, z):
                        break
                    x = room[0] + rng.uniform(-off_x, off_x)
                    z = room[1] + rng.uniform(-off_z, off_z)
                if self._near_door(x, z):
                    continue
                yaw = round(rng.uniform(-8, 8), 1)   # break the grid
                self.instance(f"{cat}_{pi}", "Props", scene,
                              (round(x, 2), prop_y(), round(z, 2)), yaw)
                pi += 1

        # --- signage -------------------------------------------------------
        # RichText3D renders BBCode in 3D. Used for the act sign at the entry
        # and for a few wayfinding placards deeper in.
        self.nodes.append(chr(10) + '[node name="Signage" type="Node3D" parent="."]')
        rt = self.ext_res("Script", "res://addons/rich_text_3d_0_1_3/addons/rich_text_3d/rich_text_3d.gd")
        signs = [
            ("ActSign", (0.0, 2.2, D / 2 - 0.6), 180.0,
             f"[center][font_size=64][b]ACT {plan.act}[/b][/font_size]"
             f"[font_size=34]{plan.act_title}[/font_size][/center]"),
            ("ExitSign", (-W / 2 + 1.0, 2.4, 0.0), 90.0,
             "[center][font_size=40][color=#7fd4a0]EXIT[/color][/font_size][/center]"),
            ("WarningSign", (W / 2 - 1.0, 2.4, D / 4), 270.0,
             "[center][font_size=30][color=#d46a6a]KEEP OUT[/color][/font_size]"
             "[font_size=22]STRUCTURE UNSAFE[/font_size][/center]"),
        ]
        for nm, pos, yaw, txt in signs:
            a = math.radians(yaw)
            c, sn = math.cos(a), math.sin(a)
            self.nodes.append(
                chr(10).join([
                    f'[node name="{nm}" type="MeshInstance3D" parent="Signage"]',
                    f"transform = Transform3D({c:.6f}, 0, {-sn:.6f}, 0, 1, 0, {sn:.6f}, 0, {c:.6f}, {pos[0]}, {pos[1]}, {pos[2]})",
                    f'script = ExtResource("{rt}")',
                    "size = Vector2(2.2, 1.1)",
                    f'text = "{txt}"',
                    "font_size = 64",
                    "outline_size = 8",
                    "billboard_mode = 0",
                    "",
                ])
            )

        # --- ACT gate: the way to the next act -------------------------------
        # One Area3D on the far wall from the spawn point. Walking into it fades
        # the screen, loads the next act, and fades back in.
        nxt = ACT_NEXT.get(plan.venue, {"next": "", "label": "", "one_way": False})
        gz = self.ext_res("Script", "res://hub/act_gate.gd")
        gshape = self.sub_res("BoxShape3D", ["size = Vector3(2.4, 2.6, 1.0)"])
        gz_pos = -D / 2 + 0.9
        self.nodes.append(chr(10) + '[node name="ActGate" type="Area3D" parent="."]')
        self.nodes.append(
            chr(10).join([
                "",
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, {gz_pos})",
                f'script = ExtResource("{gz}")',
                f'next_act = "{nxt["next"]}"',
                f'gate_label = "{nxt["label"]}"',
                f"one_way = {str(nxt['one_way']).lower()}",
                "",
                f'[node name="GateShape" type="CollisionShape3D" parent="ActGate"]',
                "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.3, 0)",
                f'shape = SubResource("{gshape}")',
                "",
                f'[node name="GateSign" type="MeshInstance3D" parent="ActGate"]',
                "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.9, 0.2)",
                f'script = ExtResource("{rt}")',
                "size = Vector2(1.8, 0.7)",
                f'text = "[center][font_size=44][color=#e8e2d0]{nxt["label"]}[/color][/font_size][/center]"',
                "font_size = 44",
                "outline_size = 6",
                "",
            ])
        )

        # Furniture must stay out of doorways. Without this, cabinets and desks
        # get placed straight across a door and seal a room - which is exactly
        # what happened in the office: 3 doorways blocked by cabinets.
        door_pts = [(d[2], d[3]) for d in floorplan.doorway_pairs(fp_plan)]
        self.door_pts = door_pts

        # --- dressing -------------------------------------------------------
        # Wall damage: the rooms read as neglected rather than newly built.
        self.nodes.append(chr(10) + '[node name="Damage" type="Node3D" parent="."]')
        di = 0
        for c in range(1, plan.cols):
            x = -W / 2 + c * plan.room_w
            for cz in range(plan.rows):
                zc = -D / 2 + plan.room_h * (cz + 0.5)
                for half in (-1, 1):
                    if rng.random() > 0.55:
                        continue
                    z = zc + half * (plan.room_h * 0.28)
                    decal = WALL_DECALS[rng.randrange(len(WALL_DECALS))]
                    self.instance(f"Decal{di}", "Damage", decal,
                                  (round(x, 2), round(rng.uniform(0.0, 0.5), 2), round(z, 2)),
                                  round(rng.uniform(0, 360), 1))
                    di += 1
        for r in range(1, plan.rows):
            z = -D / 2 + r * plan.room_h
            for cx in range(plan.cols):
                xc = -W / 2 + plan.room_w * (cx + 0.5)
                if rng.random() > 0.55:
                    continue
                x = xc + rng.uniform(-plan.room_w * 0.3, plan.room_w * 0.3)
                decal = WALL_DECALS[rng.randrange(len(WALL_DECALS))]
                self.instance(f"Decal{di}", "Damage", decal,
                              (round(x, 2), round(rng.uniform(0.0, 0.5), 2), round(z, 2)),
                              round(rng.uniform(0, 360), 1))
                di += 1

        # Clutter: small props pushed against the walls of each room.
        self.nodes.append(chr(10) + '[node name="Clutter" type="Node3D" parent="."]')
        clutter_cats = ["trash", "bucket", "stool", "plugs", "switch", "chest"]
        ci = 0
        for idx, fr in enumerate(fp_plan.rooms):
            rx, rz = fr.cx, fr.cz
            n_here = 2 + (idx * 7) % 4
            for k in range(n_here):
                cat = clutter_cats[(idx + k * 3) % len(clutter_cats)]
                scene = PROPS.get(cat)
                if not scene:
                    continue
                side = (idx + k) % 4
                ox = fr.w * 0.40
                oz = fr.d * 0.40
                dx = rng.uniform(-ox, ox)
                dz = rng.uniform(-oz, oz)
                if side == 0:
                    dz = -oz
                elif side == 1:
                    dz = oz
                elif side == 2:
                    dx = -ox
                else:
                    dx = ox
                cx2, cz2 = rx + dx, rz + dz
                for _try in range(12):
                    if not self._near_door(cx2, cz2, 1.7):
                        break
                    cx2 = rx + rng.uniform(-ox, ox)
                    cz2 = rz + rng.uniform(-oz, oz)
                if self._near_door(cx2, cz2, 1.7):
                    continue
                self.instance(f"Cl{ci}", "Clutter", scene,
                              (round(cx2, 2), prop_y(), round(cz2, 2)),
                              round(rng.uniform(0, 360), 1))
                ci += 1

        # --- interiors ------------------------------------------------------
        # Furniture inside every room, so no room reads as an empty box. This is
        # the "rooms are not fully made" fix: props alone (a bin in a corner)
        # do not make a room furnished.
        #
        # Each room gets 1-3 pieces, snapped against a wall, kept clear of the
        # doorway, and placed on the floor. A single anchor piece (a bed in a
        # bedroom, a desk in an office) is placed first so the room reads as
        # having a purpose, then dressing goes around it.
        self.nodes.append(chr(10) + '[node name="Furniture" type="Node3D" parent="."]')
        fset = FURNITURE.get(plan.venue, FURNITURE["office"])
        fi2 = 0
        for idx, fr in enumerate(fp_plan.rooms):
            rx, rz = fr.cx, fr.cz
            # 1-3 pieces, deterministic per room so a re-run is stable
            n_here = 1 + (idx * 5) % 3
            for k in range(n_here):
                scene = fset[(idx * 3 + k) % len(fset)]
                # sit against a wall: pick a side, then inset by half the piece
                side = (idx + k) % 4
                inset_x = fr.w * 0.5 - 0.55
                inset_z = fr.d * 0.5 - 0.55
                if inset_x < 0.2 or inset_z < 0.2:
                    continue          # room too small to furnish
                dx = rng.uniform(-inset_x, inset_x)
                dz = rng.uniform(-inset_z, inset_z)
                if side == 0:
                    dz = -inset_z
                elif side == 1:
                    dz = inset_z
                elif side == 2:
                    dx = -inset_x
                else:
                    dx = inset_x
                fx, fz = rx + dx, rz + dz
                # keep it out of the doorway, with clearance for its footprint
                for _try in range(12):
                    if not self._near_door(fx, fz, 1.8):
                        break
                    fx = rx + rng.uniform(-inset_x, inset_x)
                    fz = rz + rng.uniform(-inset_z, inset_z)
                if self._near_door(fx, fz, 1.8):
                    continue
                # face into the room
                if side == 0:
                    yaw = 0.0
                elif side == 1:
                    yaw = 180.0
                elif side == 2:
                    yaw = 90.0
                else:
                    yaw = 270.0
                yaw += rng.uniform(-6, 6)     # break the grid
                self.instance(f"Furn{fi2}", "Furniture", scene,
                              (round(fx, 2), prop_y(), round(fz, 2)),
                              round(yaw, 1))
                fi2 += 1

        # Ceiling fixtures above each live light, so lamps read as hardware.
        self.nodes.append(chr(10) + '[node name="Fixtures" type="Node3D" parent="."]')
        fi = 0
        positions = plan.light_pos if len(plan.light_pos) == len(plan.lights) else plan.rooms
        for (lx, lz), state in zip(positions, plan.lights):
            if state == 0:
                continue
            self.instance(f"Fix{fi}", "Fixtures", CEILING_FIXTURE,
                          (round(lx, 2), round(H - 0.45, 2), round(lz, 2)), 0.0)
            fi += 1

        # --- player + ui ---
        # Spawn in the LAST room of the plan, not at a fixed grid point - the
        # old default sat outside the floor plan entirely, which dropped the
        # player through the world.
        spawn_room = fp_plan.rooms[-1]
        self.instance("Player", ".", PLAYER,
                      (round(spawn_room.cx, 2), 0.6, round(spawn_room.cz, 2)), 180.0)
        pz = self.ext_res("Script", PAUSE)
        hz = self.ext_res("Script", HUD)
        self.nodes.append(
            f'\n[node name="PauseMenu" type="CanvasLayer" parent="."]\nscript = ExtResource("{pz}")\n'
            f'\n[node name="HubHUD" type="CanvasLayer" parent="."]\nscript = ExtResource("{hz}")\n'
            f'level_name = "ACT {plan.act}"\n'
            f'level_subtitle = "{plan.act_title}"\n'
            f'objective = "GET OUT"\n'
        )

        # --- the monster and the hiding it must respect -----------------------
        #
        # Emitted for EVERY generated act, not just the hub. Without these an act
        # has no presence in it and nothing to hide from - the player walks an
        # empty building, which is exactly the "no way to progress / not scary"
        # report. The two must be added together: the watcher only goes quiet for
        # a hidden player, so a Watcher without a HidingSpots registry is a
        # monster that finds you in a wardrobe.
        ws = self.ext_res("Script", WATCHER)
        hd = self.ext_res("Script", HIDING)
        # spawn the hiding registry BEFORE the watcher: the watcher looks it up
        # by capability in its own _ready(), so the registry must already exist.
        self.nodes.append(
            f'\n[node name="HidingSpots" type="Node" parent="."]\nscript = ExtResource("{hd}")\n'
            f'default_dwell = 1.2\n'
            f'max_hide_speed = 1.2\n'
            f'\n[node name="Watcher" type="Node3D" parent="."]\nscript = ExtResource("{ws}")\n'
            f'grace_seconds = 14.0\n'
            f'near_distance = 3.0\n'
            f'far_distance = 9.0\n'
            f'touch_lamps_after = 2\n'
            f'door_name = "ActGate"\n'
        )

        # A hiding spot in every room, so "hide" is available wherever the player
        # is rather than only at one scripted location. Each spot is a cabinet
        # prop (visual) plus an Area3D (collision volume the registry tracks).
        self.nodes.append(chr(10) + '[node name="HidingSpotsGeo" type="Node3D" parent="."]')
        for i, fr in enumerate(fp_plan.rooms):
            hx, hz2 = self._hiding_spot_for(fr, i)
            hx, hz2 = round(hx, 2), round(hz2, 2)
            hyaw = round((i * 90) % 360, 1)
            # visual cabinet
            self.instance(f"Hide{i}", "HidingSpotsGeo", HIDING_PROP,
                          (hx, prop_y(), hz2), hyaw)
            # collision volume (Area3D + CollisionShape3D)
            self.nodes.append(
                f'\n[node name="HideArea{i}" type="Area3D" parent="HidingSpotsGeo"]\n'
                f'collision_layer = 0\n'
                f'collision_mask = 1\n'
                f'monitoring = true\n'
                f'transform = Transform3D(1,0,0, 0,1,0, 0,0,1, {hx}, 1.0, {hz2})\n'
            )
            self.nodes.append(
                f'[node name="HideShape{i}" type="CollisionShape3D" parent="HideArea{i}"]\n'
                f'shape = SubResource("HideBox{i}")\n'
            )
            self.sub.append(
                ("BoxShape3D", f"HideBox{i}",
                 f'size = Vector3(1.8, 2.0, 1.8)\n')
            )

        return self._assemble()

    ## A clear floor position against a wall of this room for a hiding spot.
    ## Kept out of the doorway so the player can actually get into it.
    def _hiding_spot_for(self, fr, idx: int) -> tuple[float, float]:
        inset_x = max(fr.w * 0.5 - 0.6, 0.0)
        inset_z = max(fr.d * 0.5 - 0.6, 0.0)
        side = idx % 4
        if side == 0:
            x, z = fr.cx, fr.cz - inset_z
        elif side == 1:
            x, z = fr.cx, fr.cz + inset_z
        elif side == 2:
            x, z = fr.cx - inset_x, fr.cz
        else:
            x, z = fr.cx + inset_x, fr.cz
        # nudge out of any doorway
        for _try in range(10):
            if not self._near_door(x, z, 1.6):
                break
            x += 0.5 if x < fr.cx else -0.5
        return x, z

    def _assemble(self) -> str:
        out = [f"[gd_scene load_steps={len(self.ext) + len(self.sub) + 1} format=3]", ""]
        for kind, path, i in self.ext:
            out.append(f'[ext_resource type="{kind}" path="{path}" id="{i}"]')
        out.append("")
        for kind, i, lines in self.sub:
            out.append(f'[sub_resource type="{kind}" id="{i}"]')
            if isinstance(lines, list):
                out.extend(lines)
            else:
                out.append(lines)
            out.append("")
        # Join with a newline, NOT "". A block that does not end in a newline
        # (e.g. the WallKit header) would otherwise run straight into the next
        # node header, producing two headers on one line:
        #     [node name="WallKit" ...][node name="W1" parent="WallKit" ...]
        # Godot cannot parse that, so the wall modules silently never load and
        # the level is left with nothing but the invisible colliders.
        out.append("\n".join(self.nodes))
        return "\n".join(out)


def generate(venue: str, scene_name: str, write: bool = True) -> tuple[Plan, Path | None]:
    src = (HERE / "level_architect.QX+").read_text(encoding="utf-8")
    # swap the venue line so one QX++ program serves every venue
    src = src.replace('let venue = "office"', f'let venue = "{venue}"')

    result = qx_bridge.run_source(src, f"architect_{venue}")
    if not result.ok:
        raise qx_bridge.QXPPError(
            f"QX++ architect failed.\nstdout: {result.stdout[:500]}\nstderr: {result.stderr[:900]}"
        )

    plan = parse_plan(result.stdout)
    if plan.room_count == 0:
        raise qx_bridge.QXPPError(
            "QX++ produced no rooms. stdout was:\n" + result.stdout[:800]
        )

    text = SceneBuilder().build(plan, scene_name)
    path = None
    if write:
        MAPS.mkdir(parents=True, exist_ok=True)
        path = MAPS / f"{scene_name}.tscn"
        path.write_text(text, encoding="utf-8")

        manifest = {
            "act": plan.act,
            "act_title": plan.act_title,
            "venue": plan.venue,
            "cols": plan.cols,
            "rows": plan.rows,
            "rooms": plan.room_count,
            "dread": plan.dread,
            "size": [plan.width, plan.depth, plan.wall_h],
            "lights": {"total": len(plan.lights),
                       "dead": plan.lights.count(0),
                       "failing": plan.lights.count(2),
                       "working": plan.lights.count(1)},
            "props": len(plan.props),
            "doors": len(plan.doors),
        }
        (HERE / f"plan_{scene_name}.json").write_text(
            json.dumps(manifest, indent=2), encoding="utf-8"
        )
    return plan, path


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate a Null Address level with QX++.")
    # `house` is supported by the QX++ architect AND by floorplan.plan_spine, but
    # was missing from this list - so `python generate.py house` was rejected and
    # gen_house.tscn could never be regenerated (it had no furniture, and no way
    # to get any). Keep this in sync with the venue branches in floorplan.py.
    ap.add_argument("venue", choices=["office", "store", "tunnel", "house"])
    ap.add_argument("--name", default=None, help="scene name (default gen_<venue>)")
    ap.add_argument("--no-write", action="store_true", help="plan only, do not write a scene")
    args = ap.parse_args()

    scene_name = args.name or f"gen_{args.venue}"
    try:
        plan, path = generate(args.venue, scene_name, write=not args.no_write)
    except qx_bridge.QXPPError as exc:
        print("QX++ error:", exc, file=sys.stderr)
        return 2

    print(f"venue      : {plan.venue}")
    print(f"grid       : {plan.cols} x {plan.rows} = {plan.room_count} rooms")
    print(f"size       : {plan.width:.1f} x {plan.depth:.1f} x {plan.wall_h:.1f} m")
    print(f"dread      : {plan.dread}")
    dead = plan.lights.count(0)
    print(f"lights     : {len(plan.lights)} fixtures, {dead} dead")
    print(f"prop groups: {len(plan.props)}")
    print(f"doorways   : {len(plan.doors)}")
    print(f"scene      : {path if path else '(not written)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
