PSX HORROR MONSTERS - FREE SAMPLER
by bitkiln  -  https://bitkiln.itch.io
Retro game assets, fired in the kiln.

2 animated low-poly PS1-style horror enemies from PSX HORROR MONSTERS, free for personal and
commercial projects (see LICENSE.txt), with the same formats and the same Godot 4 demo as the full
pack.

THE FULL PACK: 13 monsters (Shambler, Crawler, Asylum Patient, Porcelain Doll, Butcher, Plague
Doctor, Scarecrow, Mannequin, Wraith, Antler Stalker, Hound, Giant Spider, Giant Rat), 98 animations,
26 skins, GLB + FBX, Godot 4 demo with an enemy behaviour script. Get it at https://bitkiln.itch.io
and thank you for trying the sampler!

CONTENTS (counted by the build)
- 2 monsters, 16 animations, 4 skins, 2,931 triangles in total
  Shambler (shambler): 1085 tris, 18 bones, 1.87 m, skins worker / patient
      Slow, limping zombie in torn clothes. Reaches out with one arm, lunges and bites.
      clips: Idle 3.2s (loop), Walk 1.7s (loop), Run 0.9s (loop), Attack 1.3s, Attack2 1.1s, Hit 0.6s, Death 2.2s, Scream 1.8s
      walk 0.35 m/s, run 1.45 m/s, attack range 1.2 m, the attack lands at 0.55 s
  Hound (hound): 1846 tris, 23 bones, 1.00 m, skins flayed / black
      Skinless, rotting hound with exposed ribs and bare teeth: prowls, gallops, leaps at its prey, bites and shakes, and sits back to howl.
      clips: Idle 4.0s (loop), Walk 1.0s (loop), Run 0.5s (loop), Attack 1.5s, Attack2 1.4s, Hit 0.5s, Death 2.2s, Howl 3.0s
      walk 0.67 m/s, run 3.53 m/s, attack range 1.8 m, the attack lands at 0.62 s
- every monster: one skinned mesh, one armature, one 256x256 texture per skin
- every animation plays in place at 30 fps; Idle, Walk and Run loop seamlessly, the others play once and
  Death ends with the body lying still on the floor

FOLDERS
  Models/GLB/<monster>/<monster>_<skin>.glb   mesh + armature + every animation, that skin's texture inside
  Models/FBX/<monster>/<monster>.fbx          mesh + armature + every animation (first skin embedded)
  Textures/<monster>/<monster>_<skin>.png     the skin textures (swap them on the material for the other skin)
  Godot/                                 Godot 4.3 project: showcase + hunt demo, ready enemy scenes
  Catalog/monsters.csv, Catalog/monsters.md   name, triangles, bones, height, skins, clips and lengths
  Catalog/<monster>.png                       picture card of every monster

UNITS, ORIENTATION, RIG
- 1 unit = 1 metre, real-world sizes (the Shambler is 1.87 m tall, the Porcelain Doll 0.93 m).
- +Y is up and every monster faces +Z (the glTF convention); the origin is on the floor under the body.
- Rigid skinning like the original console: every vertex follows exactly one bone, joints are hidden with
  overlapping parts. Nothing to apply or fix: rotation 0 and scale 1.
- Two-legged monsters use the common humanoid bone names (Hips, Spine, Chest, Neck, Head, LeftUpperArm,
  LeftLowerArm, LeftHand, LeftUpperLeg, LeftLowerLeg, LeftFoot and the Right ones) plus extras such as Jaw,
  apron or coat panels: Shambler.
  Custom skeletons: Hound.
- Clip names: Idle, Walk, Run, Attack, Hit, Death and the extras (Attack2, Scream, Laugh, Taunt, Ritual,
  Awaken, Pose, Howl, Rear). The same names on every monster, so one controller can drive all of them.
- Speeds: the walk/run speeds above match the clips, so the feet do not slide when you move the body at
  that speed.

FORMATS
- GLB (glTF 2.0 binary): one file per skin, texture inside with a nearest sampler. Cut-out parts (hair,
  straw, rags, tatters) use alpha mask (cutoff 0.5) and are double-sided; glowing parts (eyes, lenses,
  lantern) are a second material "<monster>_glow" with the texture as emission.
- FBX (binary, 7.4): the same mesh, armature and clips, the first skin embedded, scale 1 (metres). Clips are
  named "Armature|Idle", "Armature|Walk" ... in most importers.
- PNG textures: 256x256, RGBA where a monster has cut-out parts. Show them with nearest filtering.

GODOT 4 (4.3 or newer)
- Open the Godot project (Godot/) and press F5: the
  showcase. demo/hunt.tscn is a playable dark maze where the monsters hunt you. README_GODOT.md explains the
  ready enemy scenes, the behaviour script (wander, spot, chase, attack, flinch, die), skins and the PSX shader.
- GLB only: drag a .glb into a scene; an AnimationPlayer holds every clip. Set Idle, Walk and Run to loop
  (Advanced Import Settings > Animation > Loop Mode, or in code: anim.loop_mode = Animation.LOOP_LINEAR).

UNITY
- Import the FBX files (Models/FBX). Model tab: Scale Factor 1. Rig tab: Generic (the clips play as made).
  Two-legged monsters can also be set to Humanoid for retargeting; if the avatar setup asks for a T-pose,
  use Pose > Enforce T-Pose.
- Animation tab: tick Loop Time on Idle, Walk and Run.
- Textures: Filter Mode Point (no filter), Compression None. Materials: for the other skin, put the second
  PNG from Textures/ on the material. Cut-outs: Alpha Clipping 0.5 and Render Face Both. Glow material:
  Emission with the same texture.
- glTF importers such as glTFast load the GLB files as well.

UNREAL ENGINE
- Import the FBX as a Skeletal Mesh with "Import Animations" on (or the GLB with the glTF / Interchange
  importer). Set the textures to Texture Group "2D Pixels (unfiltered)" and turn off mipmaps.

BLENDER
- File > Import > glTF 2.0 (.glb): mesh, armature, texture (Closest interpolation) and one action per clip.
- File > Import > FBX works too.

TIPS
- Keep nearest filtering and lossless textures: 256 px textures smear with linear filtering or VRAM compression.
- PS1 games played animations at low frame rates: try 12-15 fps (or STEP interpolation) for an even more
  jerky, retro feel. The Mannequin is made stop-motion on purpose.
- Pair them with the PSX Horror Texture Pack, PSX Horror Props and PSX Horror Modular Kit
  (https://bitkiln.itch.io): same scale, same look.

LICENSE
See LICENSE.txt. Short version: use the monsters in any personal or commercial project, but do not resell
or redistribute the models, animations or textures themselves. Credit is appreciated but not required:
"Art by bitkiln".

CONTACT
Questions, problems or monster requests: comment on the itch.io page (https://bitkiln.itch.io)
or write to @bitkiln_assets on X. Thank you for supporting a small creator!
