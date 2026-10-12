# PSX Horror Monsters - Free Sampler - Godot 4.3 project

bitkiln - https://bitkiln.itch.io

2 monsters of PSX Horror Monsters, set up exactly like in the full pack: a scene with collision, the
model, all of its clips and the enemy behaviour script. The full pack has 13 monsters.

Open `project.godot` with Godot 4.3 or newer and press F5: the monster showcase starts.
The hunt demo is `demo/hunt.tscn` (open it and press F6). Both run on the Compatibility renderer, so they work on
almost any GPU; everything also works with Forward+ and Mobile.

## Showcase (demo/showcase.tscn)

| key | action |
|---|---|
| 1 2 3 4 5 6 | Idle, Walk, Run, Attack, Hit, Death on every monster |
| 7 8 9 | the extra clips (Attack2, Scream, Laugh...); a monster without one stands idle |
| K | next skin |
| P | PSX shader on / off |
| R | turntable |
| Space | pause the clips |
| [ ] | slower / faster |
| Tab / Shift+Tab | the next / previous monster alone, the camera swings around it (mouse wheel: closer / farther) |
| O | every monster again, the camera looks along the stage |
| W A S D, mouse | fly (click into the window to capture the mouse) |
| Q / E, Shift | down / up, faster |
| L, H, Esc | name labels, help, free the mouse |

One-shot clips repeat after a short pause, so you can watch them as often as you like.

## Hunt (demo/hunt.tscn)

A dark maze with the monsters in it. They stroll around, notice you when you come into view, follow you around
the walls and attack. Shoot them.

| key | action |
|---|---|
| W A S D / arrows, mouse | walk, look around (click into the window first) |
| Shift, Space | sprint, jump |
| F | flashlight |
| left mouse button | shoot |
| P | PSX shader on / off |
| G | god mode (the monsters cannot hurt you) |
| N | every monster hunts you |
| R | restart |
| H, Esc | help, free the mouse |

When your health reaches 0 the scene starts again.

## Using a monster in your own project

1. Copy `monsters/`, `scripts/` and `shaders/` into your project. Copy the `[importer_defaults]` block of this
   `project.godot` into yours **before** the files are imported, so the textures stay sharp and lossless
   (GLB: Embedded Image Handling = Embed as Uncompressed; PNG: Lossless, Detect 3D off). Already imported? Select
   the files, change it in the Import dock and click Reimport.
2. Drag `monsters/<name>/<name>.tscn` into your level. That is a complete enemy: CharacterBody3D, collision
   capsule, the model, a NavigationAgent3D and `scripts/monster_brain.gd`, set up for that monster (speeds that
   match its clips, attack range and the moment the blow lands, skins, alert scream).
3. Put your player into the group `player` and give it a `take_damage(amount: float, from_position: Vector3)`
   method (and `is_dead() -> bool` if it can die). That is all the monsters need.
4. Add a NavigationRegion3D with a baked navigation mesh to your level and the monsters follow paths around walls.
   Without one they walk straight at their goal and slide along whatever is in the way.

In code:

```gdscript
var monster := preload("res://monsters/shambler/shambler.tscn").instantiate() as MonsterBrain
monster.skin = "patient"
add_child(monster)
monster.global_position = Vector3(4.0, 0.0, -6.0)
monster.died.connect(func(): print(monster.monster_name, " is down"))
# your bullets / weapons:
monster.take_damage(25.0, global_position)
```

The GLB files work on their own, too: `monsters/<name>/<name>_<skin>.glb` is a Node3D with
`Armature/Skeleton3D/<mesh>` and an AnimationPlayer with every clip. Godot imports every clip as play-once; the
brain turns on looping for Idle, Walk and Run when the monster starts. Using a GLB without the brain, set the loop
mode yourself (Advanced Import Settings > Animation > Loop Mode, or `anim.loop_mode = Animation.LOOP_LINEAR`).

Units and directions: metres, +Y up, the origin is on the floor and the models face +Z (the glTF convention). The
clips play in place: the brain (or your code) moves the body. When you turn a monster yourself, use
`look_at(target, Vector3.UP, true)` so +Z faces the target.

## MonsterBrain (scripts/monster_brain.gd)

States: IDLE (stands, sometimes plays an idle variation; a dormant monster waits frozen until it is woken),
WANDER (strolls around its start point), CHASE (runs at the target; plays the alert clip once when it spots it),
ATTACK (Attack or Attack2, chosen at random when both reach; the blow lands at `attack_hit_time` if the target is
still in reach and in front), HIT (after damage; a new hit restarts it and cancels an attack), DEAD (Death clip, no
more collision with players, monsters and bullets, the body stays on the floor).

| group | options |
|---|---|
| (top) | `monster_name`, `active` (off: the monster stands still and ignores everything) |
| Target | `target_group` ("player"), `detect_range`, `lose_range`, `need_line_of_sight`, `sight_mask`, `eye_height`, `forget_time` |
| Movement | `walk_speed`, `run_speed`, `use_run`, `acceleration`, `turn_speed`, `gravity`, `walk_animation_speed` / `run_animation_speed` (the clips speed up or slow down to match a changed speed, so the feet do not slide) |
| Wander | `wander`, `wander_radius`, `idle_time` |
| Attack | `attack_range`, `attack_hit_time`, `attack2_range`, `attack2_hit_time`, `attack2_chance`, `attack_cooldown`, `damage`, `hit_reach`, `hit_angle` |
| Health | `max_health`, `flinch`, `flinch_cooldown`, `remove_after` |
| Animations | `animation_player`, the clip names (`anim_idle` ... `anim_death`, `anim_attack2`, `anim_alert`), `start_dormant` + `anim_wake` (wait frozen in the first frame of the wake clip, e.g. the Scarecrow's Awaken, until a target comes close), `idle_variations`, `loop_animations`, `blend_time` |
| Skin | `skin_textures`, `skin` |
| Hover | `hover_height`, `hover_bob`, `hover_period`, `model` (floating monsters) |
| Navigation | `use_navigation` |

Signals: `state_changed`, `target_spotted`, `target_lost`, `attack_started`, `attack_landed`, `damaged`, `died`.
Methods: `take_damage(amount, from_position, source)`, `kill()`, `revive()`, `hunt(node)`, `is_dead()`, `is_dormant()`,
`play_animation(name, restart, blend)`, `next_skin()`, `skin_names()`, `state_name()`.

Physics layers of the demo: 1 level, 2 player, 3 monsters (a monster collides with 1, 2 and 3). Change them in
the monster scene if your project uses other layers; `sight_mask` is the layer that blocks the monsters' view.

Your own models work too: put the script on a CharacterBody3D with your model as a child and type in the names of
your clips in the Animations group.

## Skins

Every monster has two skins. Pick one in the Inspector (MonsterBrain > Skin) or in code with
`monster.skin = "<name>"` or `monster.next_skin()`. The brain puts the skin texture (`monsters/<name>/*.png`) on
the model, shared by every monster with the same skin, and it keeps working while the PSX shader is on.
Each skin is also a GLB of its own, with that texture inside.

## The PSX shader

`shaders/psx_lit.gdshader`: vertex snapping to a low virtual resolution, affine texture mapping, nearest
sampling without mipmaps, 15-bit colour with dithering, diffuse light without highlights. Turn the materials of
any node tree into PSX materials and back:

```gdscript
const PSX := preload("res://shaders/apply_psx.gd")
PSX.apply(self)                               # every material under this node -> PSX shader
PSX.restore(self)                             # back to the original materials
PSX.set_setting("snap_resolution", 480.0)    # change a setting on every PSX material
```

Call `PSX.apply()` on monsters you spawn later, too. Depth fog (Environment > Fog > Mode: Depth) and a dark ambient
light complete the look, as in the hunt demo.

## The monsters

| monster | scene | skins | clips | walk / run m/s | attack range |
|---|---|---|---|---|---|
| Shambler | `monsters/shambler/shambler.tscn` | worker, patient | Idle, Walk, Run, Attack, Attack2, Hit, Death, Scream | 0.35 / 1.45 | 1.2 m |
| Hound | `monsters/hound/hound.tscn` | flayed, black | Idle, Walk, Run, Attack, Attack2, Hit, Death, Howl | 0.67 / 3.53 | 1.8 m |

Collision capsules are sized from each monster's Idle pose. Damage and health in the scenes are starting values;
tune them for your game.

## Folders

| folder | content |
|---|---|
| `monsters/<name>/` | `<name>.tscn` (ready enemy), `<name>_<skin>.glb` (one per skin), `<name>_<skin>.png` (skin textures) |
| `scripts/` | `monster_brain.gd` (enemy behaviour), `player.gd` (first-person player of the hunt demo) |
| `shaders/` | the PSX shader (`psx_lit.gdshader`, double-sided version) and `apply_psx.gd` |
| `demo/` | `showcase.tscn`, `hunt.tscn`, the player scene, the maze builder, camera and light scripts, textures |

## Credits

The floor, wall, ceiling and door textures of the demo scenes are from the free sample of the PSX Horror Texture
Pack by bitkiln (https://bitkiln.itch.io), free for personal and commercial projects.

## Contact

Questions, problems or monster requests: comment on the itch.io page (https://bitkiln.itch.io) or write to
@bitkiln_assets on X. Thank you for supporting a small creator!
