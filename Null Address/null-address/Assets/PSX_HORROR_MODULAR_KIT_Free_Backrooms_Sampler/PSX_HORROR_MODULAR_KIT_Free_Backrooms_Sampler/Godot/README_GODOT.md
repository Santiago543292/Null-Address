# PSX Horror Modular Kit - Free Sampler - Godot 4.3 project

bitkiln - https://bitkiln.itch.io

10 backrooms pieces of the PSX Horror Modular Kit, ready to paint with Godot's GridMap, with the same
PSX materials, player and settings as the full kit and a small backrooms maze to walk through.

Open `project.godot` with Godot 4.3 or newer and press F5.

## Controls (demo)

| key | action |
|---|---|
| W A S D / arrows | walk |
| mouse | look around (click into the window first) |
| Shift | run |
| Space | jump |
| F | flashlight |
| Esc | free the mouse |
| P | PSX effects on / off (vertex snapping, affine textures, 15-bit colour) |
| H | hide the help |

## What is in the project

| folder | content |
|---|---|
| `kit/<Theme>/*.glb` | the pieces as GLB files (also for your own scenes, see "Using the GLBs directly") |
| `meshlibs/<Theme>.meshlib` | one MeshLibrary per theme: meshes, PSX materials, collision, palette previews |
| `materials/<theme>_<slot>.tres` | 8 shared ShaderMaterials, one per surface type |
| `textures/*.png` | the 8 textures the materials use (128 px per metre) |
| `shaders/` | the PSX shader (`psx_lit.gdshader`, double-sided version) and `apply_psx.gd` |
| `demo/` | the demo level (`demo_level.tscn`, built from `layout.json`), first-person player, scripts |

| MeshLibrary | items | ids |
|---|---|---|
| res://meshlibs/Backrooms.meshlib | 10 | 0, 1, 2, 3, 4, 5, 6, 12, 13, 14 |

Item ids follow the catalog order of each theme and never change.
The sampler uses the same ids as the full kit, so a level you paint with the sampler keeps working when
you switch to the full kit's MeshLibrary.

## Grid and cell settings

Every piece is built on the same grid:

- cell 2 x 2 m (X, Z), storey height 3 m (Y), metres, +Y up
- the origin of a piece is the centre of its cell floor
- edge pieces (walls, openings, railings, doors, windows) sit on the cell's **north** edge (-Z); their front looks
  into the cell (+Z)
- floors are quads at y = 0 facing up, ceilings quads at y = 3 facing down, so storeys stack without z-fighting
- 1 texture repeat = 1 m on every tiling surface, so neighbouring pieces continue the pattern

GridMap settings (the demo GridMaps use exactly these):

| property | value |
|---|---|
| Cell > Size | (2, 3, 2) |
| Cell > Center X | on |
| Cell > Center Y | **off** |
| Cell > Center Z | on |
| Cell > Octant Size | 4 (smaller octants work better with many lights in the Compatibility renderer) |

## Painting a level with GridMap

1. Add a **GridMap** node, set **Mesh Library** to `res://meshlibs/House.meshlib` (or another theme) and the cell
   settings above.
2. Select the GridMap: the palette with the piece previews opens. Pick a piece and click into the viewport to paint;
   right click erases.
3. **Rotate** the cursor around Y with **S** (Shift+S turns the other way). A and D turn around X and Z: you never
   need them for this kit, every piece stands upright. Rotations: 0 = north edge, 90 = west, 180 = south, 270 = east.
4. Change the storey with the **Floor** field of the GridMap toolbar. One storey = one cell in Y.
5. **Keep floors and ceilings unrotated**: their texture coordinates follow the cell, a turned floor breaks the
   pattern at the seams. Walls may take any of the four rotations.

**One piece per cell.** A GridMap stores a single item in each cell, but a room cell often needs a floor, a ceiling,
one or two walls, a window and a corner post. Use several GridMaps with the same MeshLibrary as layers, like the demo:

| GridMap | holds |
|---|---|
| `<Theme>_Floors` | floors, floor holes, porch deck, drains |
| `<Theme>_Ceilings` | ceilings, ceiling lights, ceiling holes, joists |
| `<Theme>_Walls` (+ `_Walls2`, ...) | walls and wall openings, one per cell edge; a second GridMap for the second wall of a corner cell |
| `<Theme>_Details` (+ `_Details2`) | doors and windows in their openings, corner posts, pillars, railings, pipes |
| `<Theme>_Stairs` (+ `_Stairs2`) | stairs and their hand rails |
| `House_Roof` (+ `_Roof2`, ...) | roof slopes, ridge, gables, rake trims, chimney, porch roof |
| `Sewer_Tunnels` | the tunnel pieces (one piece = floor, channel, walls and vault) |

Use separate GridMaps for each theme as well (each GridMap has one MeshLibrary). The sampler maze has 5 GridMaps with 234 cells; `demo/layout.json` lists them.

Tips:

- A wall between two rooms can also go into the neighbour cell turned by 180 degrees: both faces look the same, so
  you need fewer wall layers.
- Corner posts (`*_corner`) close the small gap on the outside of an L-shaped wall corner. Put them in any cell that
  touches the corner; rotation 0 = north-east corner of the cell, 90 = north-west, 180 = south-west, 270 = south-east.
- Ceiling lights only glow: add an OmniLight3D under the fixture for real light (the demo does that).

## Collision

The MeshLibrary items carry their collision, so a GridMap is solid as soon as you paint (the GridMap's collision
layer and mask apply):

- floors, walls, openings, doors, windows, railings, pillars, pipes, roofs and tunnels: a trimesh
  (`ConcavePolygonShape3D`) of their surfaces; glowing parts (bulbs, light panels) have none
- ceilings have no collision: nobody walks on them, the floor of the storey above is solid, and stair openings
  stay free for the player's head
- the demo player also climbs single steps up to 0.32 m (porch steps, sewer walkways, rubble)

## Materials: restyle a whole theme

All pieces of a theme share one material per surface type: `res://materials/<theme>_<slot>.tres`, for example
`house_wall.tres` (wallpaper), `house_wainscot.tres`, `hosp_floor.tres`, `back_wall.tres`. Change one material and every
piece that uses it changes, in the editor and in the game.

Each material is a ShaderMaterial with `shaders/psx_lit.gdshader` (cut-outs such as cell bars and grates use
`psx_lit_double_sided.gdshader`). Useful parameters:

| parameter | what it does |
|---|---|
| `albedo_texture` | the texture (drag another PNG onto it) |
| `albedo_color` | tint |
| `uv_scale` | texture scale (1 = one repeat per metre; keep 1 so pieces stay seamless) |
| `vertex_snap`, `snap_resolution` | PS1 vertex wobble and its virtual resolution (240 lines) |
| `affine_strength` | 1 = PS1 affine texture warp, 0 = perspective-correct |
| `color_15bit`, `dithering` | 15-bit colour with ordered dither |
| `unshaded` | ignore lights (the glowing light panels and bulbs use it) |
| `alpha_scissor` | cut-out transparency |

The textures are sampled with nearest filtering and repeat by the shader itself, whatever their import settings.
To change the look of every material at once, edit the defaults at the top of `psx_lit.gdshader`, or set a
parameter on all materials from a script (see `set_psx()` in `demo/level.gd`).

## Textures from the PSX Horror Texture Pack

The kit uses the same scale as the **PSX Horror Texture Pack** (128 px per metre, tiling, nearest filtering), so any
of its textures drops into any slot:

1. Copy the PNG into `res://textures/` (or anywhere in your project).
2. In the Import dock keep it lossless: Compress Mode **Lossless**, Detect 3D **Disabled** (the `[importer_defaults]`
   in `project.godot` already do this), then Reimport.
3. Open the material, for example `materials/back_wall.tres`, and drag the new texture onto `albedo_texture`.

Tiling textures fit walls, floors, ceilings and the sewer; non-tiling ones (doors, windows, light panels) map 0..1
over their face. The 64 px versions of the kit textures (in the kit's `Textures_64` folder) give an even chunkier
look: assign them the same way.

## Using the GLBs directly

The GLB files in `kit/<Theme>/` import as normal scenes with standard materials (nearest filtering, repeat). For the
PSX look on such an instance call:

```gdscript
const PSX := preload("res://shaders/apply_psx.gd")
PSX.apply(self)    # PSX materials for everything under this node; PSX.restore(self) undoes it
```

To build your own MeshLibrary from the GLBs: put the pieces into a scene, then Scene > Export As... > MeshLibrary.
The ready-made MeshLibraries already contain the shared materials, collision and previews.

## Player

`demo/player.tscn` is a CharacterBody3D first-person player (walk, run, jump, mouse look, flashlight, use). It adds its
input actions (`move_forward`, `move_back`, `move_left`, `move_right`, `run`, `jump`, `interact`, `flashlight`)
when your project does not define them, so you can copy it into any project.

## Rendering notes

- The project uses the Compatibility renderer (runs everywhere, also on the web). The PSX shader works in Forward+
  and Mobile too.
- Fog: the demo uses depth fog (Environment > Fog > Mode: Depth) as on the console; mood zones change it per area.
- Compatibility draws at most 8 lights per object by default: keep the GridMap octant size small when you use many
  OmniLights, or raise `rendering/limits/opengl/max_lights_per_object`.
