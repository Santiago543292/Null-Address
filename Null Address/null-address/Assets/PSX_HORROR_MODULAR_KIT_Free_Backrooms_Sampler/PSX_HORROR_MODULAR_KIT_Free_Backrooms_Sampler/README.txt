PSX HORROR MODULAR KIT - FREE BACKROOMS SAMPLER
by bitkiln  -  https://bitkiln.itch.io
Retro game assets, fired in the kiln.

10 free PS1-style modular pieces to build an endless yellow maze: walls, a damp wall, a doorway,
a half wall, a corner post, a pillar, carpet floors, a stained ceiling and a buzzing ceiling light.
Every piece as GLB and OBJ + MTL, with a Godot 4.3 project (GridMap MeshLibrary + a small walkable maze).
Free for personal and commercial projects.

CONTENTS
  back_floor, back_floor_wet, back_ceiling, back_ceiling_light, back_wall, back_wall_damp, back_wall_half,
  back_wall_doorway, back_corner, back_pillar
- 460 triangles in total, 8 textures (128 px per metre, 64 px set too)
- Godot/: open project.godot and press F5 (WASD, mouse, Shift run, F flashlight)

FOLDERS
  GLB/Backrooms/<name>.glb   one mesh, textures inside (nearest, repeat)
  OBJ/Backrooms/<name>.obj   the same mesh, MTL points to ../../Textures/<texture>.png
  Textures/, Textures_64/    128 px and 64 px textures (1 repeat = 1 metre)
  Godot/                     Godot 4.3 project: res://meshlibs/Backrooms.meshlib, demo maze

THE GRID (everything snaps to it)
- 1 unit = 1 metre, +Y up. Cell = 2 x 2 m (X, Z), storey height = 3 m (Y).
- The origin of every piece is the centre of its cell floor (x 0, y 0, z 0): snap to 2 m in X and Z and
  to 3 m in Y. Nothing to fix: rotation 0 and scale 1 everywhere.
- Walls, openings, doors, windows and railings sit on the cell's NORTH edge: centre line z = -1, 0.2 m thick,
  centred on the edge, front face looking into the cell (+Z). Rotate in 90 degree steps for the other edges.
- <theme>_corner posts close the small gap where two walls meet at an outer corner.
- Floors are single quads at y = 0 facing up, ceilings single quads at y = 3 facing down, so storeys stack
  without z-fighting. Wall tops stop 5 mm under y = 3.
- Openings: door 1.0 x 2.2 m, double door 1.6 x 2.2 m, window 1.0 x 1.2 m (sill at 0.9 m), doorway
  1.6 x 2.4 m. The door, double door and window pieces fit them exactly. <theme>_door_leaf has its origin at
  the hinge, for doors you open in code; <theme>_door_open is a static half-open door.
- Stairs climb 3 m over two cells: from the south edge of their own cell to the north edge of the next cell.
- Keep floors and ceilings unrotated so the texture direction stays the same in every cell.

THE FULL KIT ($2.99, fixed price)
PSX Horror Modular Kit: 142 pieces in 5 themes (house with exterior, roof and porch, hospital,
basement, backrooms, sewer tunnels), 46 textures, 4 skies, doors, windows, stairs, railings and a Godot
demo level: https://bitkiln.itch.io/psx-horror-modular-kit
Same scale as the PSX Horror Texture Pack and PSX Horror Props by bitkiln.

UNITY
- Import the GLB files with a glTF importer (glTFast or UnityGLTF), or the OBJ folders (keep OBJ/ and
  Textures/ side by side so the MTL paths ../../Textures/ resolve). 1 unit = 1 metre, the same as Unity.
- Texture import: Filter Mode Point (no filter), Wrap Mode Repeat, Compression None, mipmaps off for the
  full PS1 look.
- Grid snapping: set the move snap to 2 (X, Z) and 3 (Y), rotate in 90 degree steps.
- Emissive materials: Emission on with the same texture. Cut-outs: Alpha Clipping 0.5, Render Face Both.

UNREAL ENGINE
- Import the GLB files (Interchange). If your project works in centimetres and the importer does not
  convert, import with scale 100. Grid snap 200 / 300 units.
- Textures: Filter Nearest, Compression UserInterface2D (RGBA) or VectorDisplacementmap, no mipmaps.

BLENDER
- File > Import > glTF 2.0 (.glb): meshes, materials and textures come in with Closest interpolation.
- File > Import > Wavefront (.obj) works too, with the default axes (forward -Z, up Y).
- GLB/Kits/<Theme>_kit.glb holds a whole theme in one file, every piece as its own object.

OTHER ENGINES
- Any engine or tool that reads glTF 2.0 or OBJ: three.js, Bevy, Defold, Stride, Babylon.js and more.
- Use point / nearest filtering, repeat wrapping, no texture compression and alpha test (not blending)
  for cut-outs.

LICENSE
See LICENSE.txt. Use the sampler in any personal or commercial project; do not resell or redistribute the
assets themselves. Credit is appreciated but not required: "Art by bitkiln".
