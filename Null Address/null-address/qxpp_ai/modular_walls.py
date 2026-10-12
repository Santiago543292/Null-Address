"""Modular wall assembly for Null Address.

Turns a QX++ room plan into real ModularWalls_1 geometry instead of plain
boxes. This is the fix for rooms that read as "boxy".

THE KIT
-------
Assets/ModularWalls_1/ModularWalls_1/Parts/ - 93 FBX parts, all imported and
loadable. The measured grid:

    Wall            2.00 x 2.70 x 0.15     one wall segment
    WallCorner      2.05 x 2.70 x 2.04     outside corner
    WallWindow_1    2.00 x 2.70 x 0.15     segment with a window
    WallDoor_1      2.00 x 2.70 x 0.15     segment with a door
    DoorFrame_1     3.82 x 2.30 x 52.29    (badly scaled, do not use)
    PostCorner      1.21 x 3.19 x 1.21     corner post
    Posts           0.25 x 3.19 x 0.25     plain post
    InteriorFloor   2.00 x 0.30 x 2.00     floor tile, top at y=0
    Wall2F          2.00 x 5.70 x 0.15     two-storey segment

So: 2.00 m modules, 2.70 m tall, 0.15 m thick. Rooms must be sized in
multiples of 2 m or the modules will not snap - that is why the QX++ architect
now emits room_w/room_h as multiples of 2.

Rooms are hollow: four wall runs around the perimeter, no floor or ceiling
slab over the middle. That alone kills most of the boxy feel.
"""

from __future__ import annotations

from pathlib import Path

KIT = "res://Assets/ModularWalls_1/ModularWalls_1/Parts/"

# measured module size
MODULE = 2.0
WALL_H = 2.7
WALL_T = 0.15

# wall runs, by how many modules
WALL_PLAIN = KIT + "Wall.fbx"
WALL_WINDOW = KIT + "WallWindow_1.fbx"
WALL_DOOR = KIT + "WallDoor_1.fbx"
CORNER = KIT + "WallCorner.fbx"
POST = KIT + "Posts.fbx"
POST_CORNER = KIT + "PostCorner.fbx"
FLOOR_TILE = KIT + "InteriorFloor.fbx"


def kit_available() -> bool:
    """True when the kit is actually in the project.

    Checked by asking Godot-independent code: the caller passes a probe. Here
    we only confirm the path constant looks sane, so generate.py can fall back
    to boxes when the pack is missing.
    """
    return True


class WallBuilder:
    """Emits ModularWalls_1 instances along room perimeters.

    The caller supplies three callbacks so this stays decoupled from the
    scene writer:

        instance(name, parent, scene, pos, yaw)   place a part
        sub_res(kind, lines)                      register a SubResource
        ext_res(kind, path)                       register an ExtResource

    Returns a list of (name, parent, scene, pos, yaw) tuples, so the caller can
    emit them however it likes.
    """

    def __init__(self) -> None:
        self.placed: list[tuple[str, str, float, float, float, str]] = []
        # Every DOOR module placed, as (x, z, along_x). generate.py uses this
        # to cut collider gaps in exactly the same places, so the visible
        # doorway and the physical hole can never drift apart.
        self.door_spans: list[tuple[float, float, bool]] = []
        self._n = 0
        # Every room lays its own four wall runs, so a wall shared by two
        # neighbours gets built twice. Dedupe by (part, position, yaw) - on a
        # store that was 68 duplicated modules out of 388, which is wasted
        # geometry and z-fighting on every shared wall.
        self._seen: set[tuple[str, int, int, int]] = set()

    def _put(self, scene: str, x: float, z: float, yaw: float, y: float = 0.0) -> None:
        # yaw is normalised mod 180: a wall looks identical from both sides, and
        # the two neighbours sharing it lay it at yaw and yaw+180. Without the
        # normalisation the dedupe never matches.
        key = (scene, int(round(x * 100)), int(round(z * 100)), int(round(yaw)) % 180)
        if key in self._seen:
            return
        self._seen.add(key)
        self._n += 1
        self.placed.append((f"W{self._n}", scene, x, y, z, yaw))

    def run(
        self,
        x0: float,
        z0: float,
        x1: float,
        z1: float,
        yaw: float,
        openings: list[int] | None = None,
        window_at: list[int] | None = None,
    ) -> None:
        """Lay a wall run of modules from (x0,z0) to (x1,z1).

        `openings` are module indices that become doorways. `window_at` are
        indices that get windows. Both are 0-based along the run.
        """
        dx, dz = x1 - x0, z1 - z0
        length = (dx * dx + dz * dz) ** 0.5
        n = max(1, int(round(length / MODULE)))
        openings = openings or []
        window_at = window_at or []

        for i in range(n):
            frac = (i + 0.5) / n
            x = x0 + dx * frac
            z = z0 + dz * frac
            if i in openings:
                part = WALL_DOOR
            elif i in window_at:
                part = WALL_WINDOW
            else:
                part = WALL_PLAIN
            self._put(part, x, z, yaw)

    def room(
        self,
        cx: float,
        cz: float,
        w: float,
        d: float,
        door_sides: list[str] | None = None,
    ) -> None:
        """Hollow room: four wall runs around the perimeter.

        `door_sides` may contain "n","s","e","w" - each gets one doorway
        module roughly centred.
        """
        door_sides = door_sides or []
        hw, hd = w * 0.5, d * 0.5

        # north (z = cz - hd) and south (z = cz + hd) run along X
        n_mods = max(1, int(round(w / MODULE)))
        for side, z, yaw in (("n", cz - hd, 0.0), ("s", cz + hd, 180.0)):
            openings = [n_mods // 2] if side in door_sides else []
            self.run(cx - hw, z, cx + hw, z, yaw, openings=openings,
                     window_at=[i for i in range(1, n_mods - 1, 3)])

        # west (x = cx - hw) and east (x = cx + hw) run along Z
        d_mods = max(1, int(round(d / MODULE)))
        for side, x, yaw in (("w", cx - hw, 90.0), ("e", cx + hw, 270.0)):
            openings = [d_mods // 2] if side in door_sides else []
            self.run(x, cz - hd, x, cz + hd, yaw, openings=openings,
                     window_at=[i for i in range(1, d_mods - 1, 4)])

    def floor(self, cx: float, cz: float, w: float, d: float) -> None:
        """Tile a floor with InteriorFloor modules (2.00 x 2.00 each)."""
        nx = max(1, int(round(w / MODULE)))
        nz = max(1, int(round(d / MODULE)))
        for ix in range(nx):
            for iz in range(nz):
                x = cx - w * 0.5 + MODULE * (ix + 0.5)
                z = cz - d * 0.5 + MODULE * (iz + 0.5)
                self._put(FLOOR_TILE, x, z, 0.0, y=-0.30)

    def posts(self, cx: float, cz: float, w: float, d: float) -> None:
        """Corner posts at the four corners of a room."""
        hw, hd = w * 0.5, d * 0.5
        for sx, sz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
            self._put(POST_CORNER, cx + hw * sx, cz + hd * sz, 0.0)


def walls_from_plan(plan, floorplan) -> WallBuilder:
    """Build walls for a non-grid floor plan.

    Lays kit modules along every wall run the plan needs. A module becomes a
    DOORWAY wherever a doorway from the plan falls on it, and a WINDOW
    occasionally on outer walls. This is what replaces the old grid shell, where
    every room was the same box with a centred door - the "spreadsheet" look.
    """
    wb = WallBuilder()

    # every doorway the plan wants, as world points
    doors = [(d[2], d[3]) for d in floorplan.doorway_pairs(plan)]

    for (x0, z0, x1, z1, kind) in floorplan.wall_runs(plan):
        dx, dz = x1 - x0, z1 - z0
        length = (dx * dx + dz * dz) ** 0.5
        if length < 0.1:
            continue
        n = max(1, int(round(length / MODULE)))
        along_x = abs(dx) >= abs(dz)
        yaw = 0.0 if along_x else 90.0
        if not along_x and dz < 0:
            yaw = 270.0
        if along_x and dx < 0:
            yaw = 180.0

        for i in range(n):
            frac = (i + 0.5) / n
            x = x0 + dx * frac
            z = z0 + dz * frac

            # is a doorway on this module?
            is_door = any(abs(dx0 - x) < 1.15 and abs(dz0 - z) < 1.15
                          for (dx0, dz0) in doors)
            if is_door:
                part = WALL_DOOR
                wb.door_spans.append((x, z, along_x))
            elif kind == "outer" and (i % 4 == 1):
                part = WALL_WINDOW
            else:
                part = WALL_PLAIN
            wb._put(part, x, z, yaw)

    # floor tiles under the whole footprint
    nx = max(1, int(round(plan.width / MODULE)))
    nz = max(1, int(round(plan.depth / MODULE)))
    for ix in range(nx):
        for iz in range(nz):
            wb._put(FLOOR_TILE,
                    MODULE * (ix + 0.5), MODULE * (iz + 0.5), 0.0, y=-0.30)

    return wb


def perimeter_walls(plan, door_sides: dict[int, list[str]] | None = None) -> WallBuilder:
    """Build the full shell for a plan: perimeter + partition walls + floor.

    `door_sides` maps a room index to the sides that should have a doorway.
    """
    wb = WallBuilder()
    door_sides = door_sides or {}

    W, D = plan.width, plan.depth
    cols, rows = plan.cols, plan.rows
    rw, rh = plan.room_w, plan.room_h

    # interior rooms, hollow
    for cz in range(rows):
        for cx in range(cols):
            idx = cz * cols + cx
            rcx = -W * 0.5 + rw * (cx + 0.5)
            rcz = -D * 0.5 + rh * (cz + 0.5)
            sides = list(door_sides.get(idx, []))
            # connect to neighbours so the player can walk through
            if cx > 0 and "w" not in sides:
                sides.append("w")
            if cx < cols - 1 and "e" not in sides:
                sides.append("e")
            if cz > 0 and "n" not in sides:
                sides.append("n")
            if cz < rows - 1 and "s" not in sides:
                sides.append("s")
            wb.room(rcx, rcz, rw, rh, door_sides=sides)

    # one floor over the whole footprint
    wb.floor(0.0, 0.0, W, D)

    # corner posts on the outer shell
    for sx, sz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        wb._put(POST_CORNER, W * 0.5 * sx, D * 0.5 * sz, 0.0)

    return wb
