# Asset handoff (from the asset-import thread, 2026-10-25)

Run `godot --headless --path . --import` once after pulling these in.
Screenshots: anime-rpg-shots/showcase_day.png, showcase_sunset.png, catalog_hex.png.
Harness: `xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility res://scenes/asset_showcase.tscn -- --shot out.png --sky day|sunset|dusk|night`

New files: scripts/asset_lib.gd (class AssetLib), scripts/asset_showcase.gd + scenes/asset_showcase.tscn,
assets/LICENSES.md, assets/audio/MANIFEST.md. project.godot [rendering] gained
limits/opengl/max_renderable_elements=262144, max_renderable_lights=64, max_lights_per_object=16.

## AssetLib (all static, cached)
- `apply_sky(env, "day"|"sunset"|"dusk"|"night", energy=1.0, rotation_deg=0)` sets a PanoramaSky from
  res://assets/hdri/*.hdr (day = kloofendal_48d_partly_cloudy_puresky_4k). `sun_rotation(name)` gives a
  matching DirectionalLight3D rotation.
- `pbr(name, uv_scale=0.5 repeats/m, triplanar=false, tint=Color.WHITE)` -> StandardMaterial3D with
  diffuse + normal + ARM. Sets: aerial_grass_rock, grass_path_2, forest_floor, brown_mud_leaves_01,
  gravel_road, cobblestone_floor_08, castle_brick_07, rock_wall_10, beige_wall_001, weathered_planks,
  wood_planks_grey, bark_willow, roof_tiles_14. Raw maps for the ground shader:
  res://assets/textures/<name>/<name>_diffuse_2k.jpg, _nor_gl_2k.jpg, _arm_2k.jpg (R=AO, G=rough, B=metal).
  aerial_grass_rock tinted Color("b8e6a0") reads as anime grass.
- `house(parent, pos, kind, color, rot_y, scl=6.0)` places a finished textured KayKit building (box
  collision). kinds: home_A home_B tavern blacksmith church market windmill well tower_A tower_B tower_base
  lumbermill barracks castle mine watermill archeryrange. colors: blue green red yellow.
  `house_footprint(kind, color, scl)` for layout. Best replacement for WorldArt.house.
- `prop(parent, pack, name, pos, rot_y, scl, collide="trimesh"|"box"|"trunk"|"none", toon=true)` and
  `multi(parent, pack, name, [Transform3D], toon, shadows)` (MultiMesh batches). `aabb(pack, name)`.
  Packs: town (Kenney Fantasy Town: fountain-round, lantern, stall-red/green, cart, hedge*, fence*, road*,
  modular wall*/roof* tiles, tree-high), nature (Kenney Nature: tree_oak/default/detailed/pine*, rock_*,
  grass/grass_large, flower_*, mushroom_*, log_stack, stump_*, cliff_*), castle (tower-square/hexagon parts,
  wall, gate, bridge, siege engines), survival (tent, campfire-pit, workbench-anvil, chest, barrel, tools),
  graveyard (lightpost-single, lantern-glass, iron fences, crypts), dungeon (KayKit Dungeon Remastered:
  wall*, floor_tile*, stairs*, torch_lit, banner_*, chest, tables, pillar; for the Labyrinth interior),
  mini_dungeon. Nature props are ~1 unit (use scl 2.5-4); town props scl 2.4.
  Props get toon diffuse/specular + ink outline automatically. AssetLib.PALETTE remaps Kenney's teal
  foliage to greens (edit there).
- `vfx_texture("circle_05"|"star_07"|"smoke_04"|"flame_05"|...)` from assets/vfx (~190 Kenney sprites).

## Characters
assets/characters/extra/Seed-san.vrm (VirtualCast, VRM Public License 1.0; commercial OK; credit
"Seed-san by VirtualCast, Inc." required). Add to VRMCharacter.BODIES as "seed".

## UI
Kenney UI Pack Adventure (assets/ui/adventure/PNG), RPG expansion (assets/ui/rpg/PNG), Fantasy UI
Borders (assets/ui/borders/PNG) for 9-slice panels, buttons and frames.

## Audio
assets/audio/MANIFEST.md maps game events to files (footsteps grass/stone/wood x5, punch/metal/bell
impacts, level-up and quest jingles, UI click/hover/open/close/error, coins, doors, mining; ambient
wind/meadow birds/forest/river/campfire loops; music town x2, field, boss loop). No creature voices exist
in the CC0 packs. Set loop=true in the ambient/music .import files.

Not fetched: Quaternius (Google Drive only).
