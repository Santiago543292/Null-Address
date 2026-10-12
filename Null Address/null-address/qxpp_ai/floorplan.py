"""Non-grid floor plans for Null Address.

WHY THIS EXISTS
---------------
The first generator laid every act out on a strict grid: every room the same
size, every partition on the same line, a doorway centred in each wall. Rendered
from above it looked like a spreadsheet, and walking it felt like one - which is
exactly the complaint.

Real abandoned buildings are not grids. Rooms vary, corridors run off at odd
places, some spaces are big and some are closets, and you cannot see the whole
plan from any one spot.

This module produces those plans. It keeps the 2.00 m module grid that the
ModularWalls_1 kit needs - walls still land on module boundaries - but varies
WHICH module boundaries get used:

    * a spine corridor, with rooms hanging off it at irregular intervals
    * rooms of different sizes, not a uniform cell
    * some rooms subdivided into two smaller ones
    * some left as one big space
    * doorways wherever the two spaces meet, not centred

The output is a list of Rooms plus the walls between them, which generate.py
turns into kit geometry.
"""

from __future__ import annotations

from dataclasses import dataclass, field

# the kit's module size
MODULE = 2.0


@dataclass
class Room:
    """A rectangular space, on the module grid."""
    x0: float          # min corner
    z0: float
    x1: float          # max corner
    z1: float
    kind: str = "room"      # room | corridor | closet
    light_seed: int = 0

    @property
    def w(self) -> float:
        return self.x1 - self.x0

    @property
    def d(self) -> float:
        return self.z1 - self.z0

    @property
    def cx(self) -> float:
        return (self.x0 + self.x1) * 0.5

    @property
    def cz(self) -> float:
        return (self.z0 + self.z1) * 0.5

    @property
    def area(self) -> float:
        return self.w * self.d


@dataclass
class Plan:
    """A whole floor."""
    rooms: list[Room] = field(default_factory=list)
    width: float = 0.0
    depth: float = 0.0
    venue: str = ""
    dread: float = 0.5
    act: int = 0
    act_title: str = ""

    @property
    def room_count(self) -> int:
        return len(self.rooms)

    @property
    def light_pos(self) -> list[tuple[float, float]]:
        """One fixture per ~5 m of room, biased along the long axis."""
        out: list[tuple[float, float]] = []
        for r in self.rooms:
            along_x = r.w >= r.d
            span = r.w if along_x else r.d
            n = max(1, int(round(span / 5.0)))
            for k in range(n):
                frac = (k + 0.5) / n
                if along_x:
                    out.append((r.x0 + r.w * frac, r.cz))
                else:
                    out.append((r.cx, r.z0 + r.d * frac))
        return out


def centre(plan: Plan) -> Plan:
    """Shift the plan so it is centred on the origin.

    Rooms are authored from (0,0) to (width,depth) because that is the natural
    way to lay out a floor. But the colliders, ceiling and player spawn are all
    placed around the origin. Without this shift the floor collider ends up
    half a building away and the player falls through the world.
    """
    ox = -plan.width * 0.5
    oz = -plan.depth * 0.5
    for r in plan.rooms:
        r.x0 += ox
        r.x1 += ox
        r.z0 += oz
        r.z1 += oz
    return plan


def _snap(v: float) -> float:
    """Snap to the module grid."""
    return round(v / MODULE) * MODULE


def plan_spine(venue: str, rng) -> Plan:
    """A corridor with rooms off it.

    This is the shape of most real buildings you would film: a spine you walk
    down, with rooms opening off both sides. It reads as a place rather than a
    table of cells, and you can never see the whole thing at once.
    """
    p = Plan(venue=venue)

    if venue == "tunnel":
        # a tunnel IS a corridor - but a broken one, with alcoves and a bend
        p.width, p.depth = 12.0, 48.0
        segs = [
            Room(0.0, 0.0, 12.0, 16.0, "corridor"),
            Room(0.0, 16.0, 8.0, 30.0, "corridor"),      # narrows
            Room(0.0, 30.0, 12.0, 34.0, "corridor"),     # opens to a junction
            Room(0.0, 34.0, 12.0, 48.0, "corridor"),
            Room(8.0, 16.0, 12.0, 24.0, "closet"),       # side alcove
        ]
        p.rooms = segs
        return centre(p)

    if venue == "office":
        # a corridor down the middle, offices either side, unevenly sized
        p.width, p.depth = 36.0, 24.0
        corridor_w = 4.0
        cx0 = 16.0
        p.rooms.append(Room(cx0, 0.0, cx0 + corridor_w, 24.0, "corridor"))

        # west side: two big rooms and a small one
        p.rooms.append(Room(0.0, 0.0, cx0, 10.0, "room"))
        p.rooms.append(Room(0.0, 10.0, 10.0, 18.0, "room"))
        p.rooms.append(Room(10.0, 10.0, cx0, 18.0, "closet"))
        p.rooms.append(Room(0.0, 18.0, cx0, 24.0, "room"))

        # east side: a long open floor and a subdivided pair
        ex0 = cx0 + corridor_w
        p.rooms.append(Room(ex0, 0.0, 36.0, 14.0, "room"))
        p.rooms.append(Room(ex0, 14.0, 26.0, 24.0, "room"))
        p.rooms.append(Room(26.0, 14.0, 36.0, 24.0, "room"))
        return centre(p)

    if venue == "house":
        # small rooms around a hall, the way a real house is
        p.width, p.depth = 16.0, 14.0
        p.rooms.append(Room(6.0, 0.0, 10.0, 8.0, "corridor"))
        p.rooms.append(Room(0.0, 0.0, 6.0, 8.0, "room"))       # front room
        p.rooms.append(Room(10.0, 0.0, 16.0, 8.0, "room"))     # kitchen
        p.rooms.append(Room(0.0, 8.0, 8.0, 14.0, "room"))      # back room
        p.rooms.append(Room(8.0, 8.0, 16.0, 14.0, "room"))     # bedroom
        return centre(p)

    # store: a big open sales floor with a stockroom and an office behind it
    p.width, p.depth = 32.0, 26.0
    p.rooms.append(Room(0.0, 0.0, 32.0, 16.0, "room"))         # the floor
    p.rooms.append(Room(0.0, 16.0, 12.0, 26.0, "room"))        # stockroom
    p.rooms.append(Room(12.0, 16.0, 20.0, 26.0, "corridor"))   # back hall
    p.rooms.append(Room(20.0, 16.0, 26.0, 26.0, "closet"))     # staff toilet
    p.rooms.append(Room(26.0, 16.0, 32.0, 26.0, "room"))       # office
    return centre(p)


def doorway_pairs(plan: Plan) -> list[tuple[Room, Room, float, float]]:
    """Find where two rooms touch, and put a doorway in the overlap.

    Returns (a, b, x, z, axis) for each shared edge. Doorways land wherever the
    rooms happen to meet, which is what stops them being centred on a grid.
    """
    out: list[tuple[Room, Room, float, float, str]] = []
    seen: set[tuple[int, int]] = set()

    for i, a in enumerate(plan.rooms):
        for j, b in enumerate(plan.rooms):
            if i >= j:
                continue
            key = (i, j)
            if key in seen:
                continue

            # touching along a vertical edge (shared x)
            if abs(a.x1 - b.x0) < 0.01 or abs(b.x1 - a.x0) < 0.01:
                x = a.x1 if abs(a.x1 - b.x0) < 0.01 else b.x1
                lo = max(a.z0, b.z0)
                hi = min(a.z1, b.z1)
                if hi - lo >= MODULE:
                    z = (lo + hi) * 0.5
                    out.append((a, b, x, z, "x"))
                    seen.add(key)
                    continue

            # touching along a horizontal edge (shared z)
            if abs(a.z1 - b.z0) < 0.01 or abs(b.z1 - a.z0) < 0.01:
                z = a.z1 if abs(a.z1 - b.z0) < 0.01 else b.z1
                lo = max(a.x0, b.x0)
                hi = min(a.x1, b.x1)
                if hi - lo >= MODULE:
                    x = (lo + hi) * 0.5
                    out.append((a, b, x, z, "z"))
                    seen.add(key)

    return out


def wall_runs(plan: Plan) -> list[tuple[float, float, float, float, str]]:
    """Every wall the plan needs, as (x0,z0,x1,z1,kind).

    ONE run per wall LINE, not one per room edge.

    This matters more than it looks. A big room's south edge can be the same
    line as three small rooms' north edges. Emitting each room's edge separately
    produced four overlapping runs on that line, and because each run spaced its
    modules differently they landed on different offsets - so a plain wall
    module from one run sat exactly on top of a doorway module from another, and
    the room was sealed even though you could see the door.

    So: group every edge by its line, take the union span, and emit that once.
    Doorways are then cut into the single continuous run.
    """
    xs = [r.x0 for r in plan.rooms] + [r.x1 for r in plan.rooms]
    zs = [r.z0 for r in plan.rooms] + [r.z1 for r in plan.rooms]
    bx0, bx1 = min(xs), max(xs)
    bz0, bz1 = min(zs), max(zs)

    # line -> (lo, hi) span
    lines: dict[tuple[str, float], list[float]] = {}

    def add(axis: str, fixed: float, lo: float, hi: float) -> None:
        key = (axis, round(fixed, 2))
        if key not in lines:
            lines[key] = [lo, hi]
        else:
            lines[key][0] = min(lines[key][0], lo)
            lines[key][1] = max(lines[key][1], hi)

    # every room edge
    for r in plan.rooms:
        add("X", r.z0, r.x0, r.x1)   # run along X at z = r.z0
        add("X", r.z1, r.x0, r.x1)   # run along X at z = r.z1
        add("Z", r.x0, r.z0, r.z1)   # run along Z at x = r.x0
        add("Z", r.x1, r.z0, r.z1)   # run along Z at x = r.x1

    out: list[tuple[float, float, float, float, str]] = []
    for (axis, fixed), (lo, hi) in sorted(lines.items()):
        if hi - lo < 0.1:
            continue
        on_outer = (
            (axis == "X" and (abs(fixed - bz0) < 0.01 or abs(fixed - bz1) < 0.01))
            or (axis == "Z" and (abs(fixed - bx0) < 0.01 or abs(fixed - bx1) < 0.01))
        )
        kind = "outer" if on_outer else "inner"
        if axis == "X":
            out.append((lo, fixed, hi, fixed, kind))
        else:
            out.append((fixed, lo, fixed, hi, kind))

    return out
