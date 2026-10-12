PSX HORROR PROPS - FREE SAMPLER
by bitkiln  -  https://bitkiln.itch.io
Retro game assets, fired in the kiln.

10 low-poly PS1-style props from PSX HORROR PROPS, free for personal and commercial projects
(see LICENSE.txt), with the same formats and the same Godot 4 demo as the full pack.

THE FULL PACK: 123 props in 10 categories, 27,584 triangles:
      cemetery (15), containers (15), electronics (7), furniture (17), hospital (12), items (14),
      kitchen bath (11), lighting (8), outdoor (16), weapons (8).
Get it at https://bitkiln.itch.io and thank you for trying the sampler!

CONTENTS (counted by the build)
- 10 props in 9 categories, 1,350 triangles in total (12 to 576 per prop, 135 on average)
      cemetery (1): gravestone_round
      containers (2): crate_wood, drum_oil_rusty
      electronics (1): tv_crt
      furniture (1): chair_wooden
      hospital (1): hospital_bed
      items (1): key_old
      kitchen bath (1): fridge_retro
      lighting (1): candle
      outdoor (1): fence_chainlink
- 2 props with cut-out (alpha) parts, 1 with glowing (emissive) parts
- textures: 64 px (2), 128 px (6), 256 px (2)
- every prop as GLB (texture inside) and as OBJ + MTL + PNG (the PNG is the texture, ready to edit)
- Godot 4.3 demo project: a walkable showcase room and a PSX shader (vertex snapping, affine
  texture mapping, 15-bit colour + dithering) that you can use in your own scenes
- Catalog: props list (CSV + Markdown) and a contact sheet image of every category

FOLDERS
  Models/GLB/<category>/<name>.glb       one mesh, texture inside (nearest filtering)
  Models/OBJ/<category>/<name>/          <name>.obj + <name>.mtl + <name>.png (texture)
  Godot/                                 Godot 4.3 demo project (open Godot/project.godot)
  Catalog/props.csv, Catalog/props.md    name, category, triangles, size in metres, description
  Catalog/<category>.png                 contact sheet of each category

UNITS AND ORIENTATION
- 1 unit = 1 metre, real-world sizes (a chair seat is 0.45 m high, a shipping crate 0.6 m).
- +Y is up and the front of every prop faces +Z (the glTF convention).
- The origin is the centre of the footprint on the floor (y = 0): place a prop on a floor point and
  it stands on it.
- Nothing to apply or fix: rotation 0 and scale 1 everywhere.

FORMATS
- GLB (glTF 2.0 binary): one file per prop with the texture inside and a nearest sampler. Cut-out
  parts use alpha mask (cutoff 0.5) and are double-sided; glowing parts (flames, bulbs, screens) are
  a second material "<name>_glow" with the texture as emission. Use GLB whenever your engine reads glTF.
- OBJ + MTL + PNG: the same mesh, normals and UVs. The MTL names the texture (map_Kd), cut-outs add
  map_d, glowing parts use the second material "<name>_glow" with map_Ke.
- PNG textures: 64, 128 or 256 px, RGBA where a prop has cut-outs. Show them with nearest filtering.
- Triangles only. Hard edges have split vertices, round parts share vertices (smooth normals).

GODOT 4 (4.3 or newer)
1. Open Godot/project.godot and press F5. The showcase room shows every prop with its name.
     WASD / arrows  move              mouse    look (click to capture the mouse)
     Shift          faster            Esc      free the mouse
     F              walk / fly        E, Q     up / down while flying
     P              PSX shader on / off
     1  vertex snapping     2  affine texture mapping     3  15-bit colour + dithering
     4  virtual resolution (240 / 480 / 120 lines)        L  name labels     H  help
   The demo uses the Compatibility renderer, so it runs on almost any GPU. The shader works the
   same in Forward+ and Mobile.
2. Your own project: copy Godot/psx_horror_props/ and Godot/shaders/ into it.
   Import settings: the demo imports GLB files with "Embedded Image Handling: Embed as Uncompressed",
   so the pixel textures stay sharp and lossless. Do the same in your project: copy the
   [importer_defaults] block of Godot/project.godot into your project.godot before you add the models,
   or select the .glb files, set that option in the Import dock and click Reimport.
   Then drag a .glb into a scene, or in code:
     var crate = load("res://psx_horror_props/containers/crate_wood.glb").instantiate()
3. The PSX look in your own scenes:
     const PSX := preload("res://shaders/apply_psx.gd")
     PSX.apply(self)                               # every material under this node -> PSX shader
     PSX.restore(self)                             # back to the original materials
     PSX.set_setting("snap_resolution", 480.0)    # change a setting on every PSX material
   Or make a ShaderMaterial with shaders/psx_lit.gdshader (psx_lit_double_sided.gdshader for
   double-sided surfaces) and set its albedo_texture.

THE PSX SHADER (Godot/shaders/psx_lit.gdshader)
- Vertex snapping: every vertex snaps to the pixel grid of a low virtual resolution (snap_resolution,
  240 lines by default, the width follows the window). The console had no sub-pixel precision, so
  polygons jittered as the camera moved.
- Affine texture mapping: textures are interpolated in screen space without perspective correction,
  so they swim and bend on large or close polygons. affine_strength goes from 0 (correct) to 1.
- Nearest texture sampling without mipmaps: every texel stays a sharp square.
- 15-bit colour and dithering: the surface colour is reduced to 5 bits per channel with a 4 x 4
  ordered dither the size of the virtual pixels (color_15bit, dithering, dither_strength).
- Emission for flames, bulbs and screens, alpha scissor for cut-outs, back-face or no culling.
- Lights and fog come from Godot: diffuse only, no specular highlights, like the console.
  Depth fog (Environment > Fog > Mode: Depth) hides the draw distance the classic way.
apply_psx.gd keeps the albedo colour and texture, UV scale, vertex colours, emission (colour, texture,
energy), alpha scissor, unshaded mode and cull mode of every material. Alpha-blended materials stay
as they are. All instances of a model share one PSX material.

UNITY
- Import the OBJ folders (each OBJ has its MTL and PNG next to it), or the GLB files with a glTF
  importer such as glTFast. 1 unit = 1 metre, the same as Unity.
- Texture settings: Filter Mode Point (no filter), Compression None. Mipmaps off for the full look.
- Cut-out props: Alpha Clipping on (threshold 0.5) and Render Face Both.
- Glowing parts (material "<name>_glow"): turn on Emission with the same texture as emission map.

BLENDER
- File > Import > glTF 2.0 (.glb): mesh, texture and materials come in, with Closest (nearest)
  interpolation on the texture.
- File > Import > Wavefront (.obj) works too, with the default axes (forward -Z, up Y).

OTHER ENGINES
- Any engine or tool that reads glTF 2.0 or OBJ: Unreal Engine, three.js, Bevy, Defold, Stride and
  more. If your engine works in centimetres and its importer does not convert, import with scale 100.
- Use point / nearest filtering, no texture compression and alpha test (not blending) for cut-outs.

TIPS
- Keep nearest filtering: linear filtering blurs the small textures and the look is gone.
- Keep the textures lossless: VRAM compression (DXT/BC, ETC, ASTC) smears 64-256 px textures.
  In Godot that means "Embed as Uncompressed" for GLB files, or "Lossless" with "Detect 3D: Disabled"
  for PNG files.
- Vertex snapping looks best at 240 to 480 lines. Fewer lines wobble more (try 120 in the demo).
- Big floors and walls warp a lot with affine mapping: split them into smaller polygons, as PS1
  games did, or lower affine_strength for those materials.
- Cut-out props (fences, flames, grates) are double-sided: use alpha test / alpha scissor, not
  alpha blending, so they sort correctly.
- Small textures + low resolution + fog = the PS1 look.

DEMO ROOM
The floor, wall and ceiling textures of the demo room are from the free sample of the
PSX Horror Texture Pack by bitkiln (https://bitkiln.itch.io).

LICENSE
See LICENSE.txt. Short version: use the props in any personal or commercial project, but do not
resell or redistribute the models or textures themselves. Credit is appreciated but not required:
"Art by bitkiln".

CONTACT
Questions, problems or prop requests: comment on the itch.io page (https://bitkiln.itch.io)
or write to @bitkiln_assets on X. Thank you for supporting a small creator!
