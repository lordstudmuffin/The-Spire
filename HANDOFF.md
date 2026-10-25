# The Spire: handoff for the next thread

Written 2026-10-25 20:30 UTC at Kyle's stop order. Read this before touching the project.
The README covers features; this file covers how the project is built, tested and what to do next.

## Standing rules from Kyle
- Standalone 3D multiplayer anime life RPG, Godot 4 (decided, do not reopen). Not Roblox.
- **Floor 1 only** until Kyle says it is complete. Floor 2 (Mirewood) exists but is frozen.
- Visual bar: must look like a professionally developed game. Presets Low/Medium/High/Ultra; Ultra tuned for an RTX 5070.
- Keep IP names out of code, assets and screenshots (no SAO, Aincrad, Kirito, Asuna, Overgeared, Satisfy, Grid, Pagma).
- If something only Kyle can do blocks you (GitHub repo, decisions), say so once and move on.
- Model split: Opus does most work; hand only "Fable-level" items to Fable (see backlog tags).

## Architecture in one screen
| Area | Files | Notes |
|---|---|---|
| Boot / menus | scenes/main_menu.tscn, scripts/main_menu.gd, character_creator.gd, settings_panel.gd, loading_screen.gd | 3 save slots (autoload/save_system.gd, format 3) |
| Autoloads | autoload/game_state.gd (player state, quests, inventory, apply_patch), net.gd (ENet, auth handshake, server records, parties, actions), settings.gd (user://settings.json), audio.gd, input_setup.gd (input map, remap, rumble) | |
| World | scripts/world.gd (floor build, NPC talk handlers, srv_action, pads, quests), world_art.gd (procedural terrain/sky/materials/night tint), world_props.gd (placed Kenney/KayKit props), world_floor2.gd (frozen), day_night.gd | Floor 1 constants: HOLLOWBROOK, TALVEN, TOWER_POS, LAB_LEVELS, BEACONS |
| Characters | scripts/player.gd (movement, camera, combat, anti-cheat client side, bot mode), vrm_character.gd (VRM bodies alicia/godette/seed), npc.gd (ROLES table on VRM bodies), character_model.gd (primitive fallback) | Headless/dedicated never loads VRM |
| Enemies | scripts/enemy.gd (MODELS table → rigged creature models, primitive fallback, flash/dissolve), mesh_merge.gd (merges primitive rigs on the server), vfx.gd | env MOBS_PRIMITIVE=1 forces old rigs |
| Server authority | autoload/net.gd + scripts/record_state.gd | Client calls Net.request_action(kind, payload) → _srv_action → world.srv_action → RecordState → net_apply → GameState.apply_patch. Movement validated with a token bucket; snapshots are audit only. Cheat bot: `--cheat` |
| UI | scripts/hud.gd (HUD, screens, chat, tracker), ui_theme.gd (theme, focus rings, action caps), scripts/ui/*.gd (inventory, quest log + quest_data, map + map_data, minimap, party, social, shop, cooking, storage, fishing widget, life hud) | |
| Life layer | scripts/life/{fishing,herb_field,home,life_data}.gd | Cottage at PlayerHome.HOME_POS (-47.5, 0, 19) |
| Assets | scripts/asset_lib.gd (AssetLib: prop/multi/house/pbr/texture_map/creature/play_clip, static prop batching), render_profile.gd (presets), assets/ (CC0 packs, LICENSES.md, CREATURES.md, HANDOFF.md) | asset_lib.gd in THIS folder is the source of truth; patch it additively, never copy over it |
| Shaders | shaders/toon*.gdshader (cel + outline; toon_creature for skinned meshes, no outline), foliage/grass/ground, stone, rune_floor, dissolve, hit_vignette, rug, window_sky | In light(): shadow band only for LIGHT_IS_DIRECTIONAL, point lights scaled by ATTENUATION |

## How to run things
Godot 4.3 is the primary target; 4.7.2 is also kept green. On a fresh checkout or after adding a `class_name` file run `godot --headless --path . --import` first (slow: 20-30 min with all packs; run it in the background). Headless noise that is harmless: "Parameter m is null" (dummy renderer, ~1000 lines), ALSA errors, "resources still in use" at exit.

```
# logic smoke test (~270 checks): expect "== Done: 0 failure(s)" and 0 "SCRIPT ERROR"
timeout 300 godot --headless --path . res://scenes/smoke_test.tscn

# multiplayer soak: server + bots (check 0 SCRIPT ERROR, orphans=0, mem flat, Lv rising)
godot --headless --path . -- --server [--floor 2] --port 4381 --report
godot --headless --path . -- --join 127.0.0.1 --port 4381 --name BotA --bot [--party] [--cheat] --report

# review screenshots (software GL; the real target is Forward+)
xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
  --resolution 1600x900 res://scenes/screenshot.tscn -- --shot out.png --scene world|creator|menu|vrm|loading \
  [--floor 2] [--hour H] [--cam x,y,z:tx,ty,tz] [--open inventory|quests|map|hud|boss|party|nearby|cooking|fishing|home|settings|controls] \
  [--combat-demo basic|skill0..2|hit|death|slam|dash] [--stats] [--preset Low|Medium|High|Ultra] [--hide-lights]
```
Screenshots for Kyle go in /mnt/project-files/anime-rpg-shots/ (link by path; the thread attachment cap is reached). Rebuild the zip for Kyle after a green round: `cd /mnt/project-files && zip -qr anime-rpg-prototype.zip anime-rpg -x "anime-rpg/.godot/*"`.

## Gotchas (each cost real time)
- Shared folder rules: always write /mnt/project-files/ with the trailing slash, never search the whole folder, re-read a file right before editing it, patch with python heredocs or Edit (the Write tool refuses shell-modified files). Never `pkill -f Godot`.
- A root Control scene needs anchors in the .tscn, not only in _ready, or it renders 0x0.
- Do not place a `var` between an `@rpc(...)` annotation and its `func`.
- Lantern/point lights in the custom shaders must be scaled by ATTENUATION or night looks like day.
- Moon/SkyFill DirectionalLights need SKY_MODE_LIGHT_ONLY or the procedural sky draws a dark disc.
- Dedicated server / headless must skip VRM and creature models (mem and orphans).
- Quaternius FBX scenes contain empty helper MeshInstance3Ds: guard `mi.mesh != null`. Outline pass must stay off skinned meshes.
- The asset thread once replaced asset_lib.gd from an old copy and broke the tree; the zip in /mnt/project-files/ is the last green backup.
- Concurrent agents: give each agent explicit file ownership; parse errors in another agent's half-edited file show up as "SCRIPT ERROR" floods in your smoke run.

## State at handoff (2026-10-25 20:30 UTC)
Green: smoke 4.3; round 7 code (gamepad + Controls tab, Floor 1 quest chain Hollowbrook → Gravelmaw with title "Warden of Talven", cottage window glow, Floor 1 mobs on rigged creature models with new Meadow Slime / Tunnel Rat / Cliff Bat). The final 4.7.2 smoke, Floor 1 two-bot soak and review screenshots were still running at the stop; results are in the main thread's last message.
Not yet visually verified: creature scale against the player in-world, kobold (bone) and Gravelmaw (dragon) tints, attack/death clips, window glow at night, Controls tab layout.

## Model routing (Kyle, 2026-10-25 20:25)
Opus by default. Fable for: new core architecture, netcode and server-authority changes, stubborn bugs, unexplained performance or memory-leak hunts, major visual/shader work, and hard-to-undo design calls. Escalate to Fable when Opus is stuck after two honest attempts, and hand back to Opus once the hard part is designed. Each Fable-level tag below carries its reason.

## Kyle's priority features (added 2026-10-25 20:40; rank ABOVE backlog items 3-12)
Full design: docs/FLOOR1_PRIORITY_FEATURES.md. Kyle wants the menu and sounds as close as possible to the reference anime, built only from original or CC0 material (never ripped assets); sounds stay swappable in autoload/audio.gd EVENTS, menu look in scripts/ui/ring_menu_style.gd.
P1. **Ring menu**: swipe-down vertical round-button menu with slide-out glass panels, wrapping the existing screens. Opus: UI work that reuses existing screens and patterns.
P2. **Crystal sound set**: synthesized/CC0 menu chimes, ticks, level-up, item-get, hit and shatter sounds, regenerable from tools/sfx/. Opus: content plus a remap of the existing Audio EVENTS table.
P3. **Hurt/death effects**: polygon-shatter deaths (GPU shard burst, scaled by preset), player shatter + respawn panel, delayed HP chip bars, hit-stop, restyled damage numbers, low-HP vignette. Opus: extends vfx.gd pools; escalate the shard shader to Fable only if it misses the visual bar.
P4. **Realm world DB + claim registry core**: server-wide persistent store, atomic claim/release with immediate durable writes, escrow transactions, item serials checked on load. Fable-level: new core architecture plus server authority, and a hard-to-undo data model once players own things. P5-P8 depend on it.
P5. **Unique skill "Twin Fang"**: hidden-stat grant, realm announcement, Legends board, 14-day inactivity release, cast checked against the registry. Fable-level for the first unique skill's validated cast path (same reason as item 7 below); Opus for the Sword Arts content, board and messages.
P6. **Limited items and quests (cap 1-3)**: slot reservation with timeout, bound items with serials, 3-4 items + 1-2 quests for Floor 1. Opus: content on top of the P4 registry.
P7. **Player stalls and restaurants**: 6 rentable Hollowbrook stalls, offline stall keeper, till, 5% tax, dish stalls with buffs. Opus: builds on P4 escrow and the existing shop/cooking UI.
P8. **Farm plots and guilds**: 8 rentable farm plots with real-time crops; guilds at Lv10 with ranks, chat, shared storage. Opus: routine features on the P4 core.

## Floor 1 backlog, prioritised
1. **Review the round-7 screenshots and tune** creature scale/tints, window glow, Controls tab spacing. Opus.
2. **In-world mob pass**: idle/walk blend, attack timing vs hit frame, death clip length vs dissolve, shadows under flying mobs. Opus.
3. **Real Gravelmaw boss fight**: phases, telegraphed slam/charge, arena hazards, music stingers. Fable-level: new server-authoritative boss state machine is netcode plus combat feel, and it sets the pattern every later boss copies. Opus can do the arena dressing and audio afterwards.
4. **Hollowbrook polish**: tavern and smithy interiors, NPC day/night routines, ambient animals from the animals pack. Opus.
5. **Labyrinth terraces**: traps, locked doors with keys, treasure chests. Opus for content; Fable-level only for the loot-validation design (server-side chest ownership and anti-dupe is a hard-to-undo data-model call).
6. **Crafting depth**: forging minigame (timing bar), ranks Normal→Mythical with rank VFX, repair/durability. Fable-level for the minigame's server validation (a client-timed minigame is a cheating surface) and the rank VFX shaders; Opus for the item tables and UI.
7. **Hidden class system**: add 2 more Floor 1 hidden classes with unlock quests and unique Sword Arts. Fable-level: new skills touch balance plus the validated action path and replicated VFX at once. Opus writes the quests and dialogue.
8. **Performance on Forward+**: profile on Kyle's RTX 5070, tune Ultra (SDFGI, FSR2, shadows) and Low; verify batching with `--stats`. Opus prepares the checklist; escalate to Fable only if a frame-time or leak mystery appears.
9. **Controller polish**: physical pad test, glyph art instead of text badges, radial skill menu. Opus.
10. **Accounts and floor transfer**: server records persist already; add account token UI and character transfer between floor servers. Fable-level: cross-server handoff is new architecture and a hard-to-undo data-format decision.
11. **Join race**: a client once dropped when another joined; 2×4-bot staggered tests could not reproduce it. Watch soaks. Fable-level only if it reappears (unexplained netcode bug).
12. **GitHub**: Kyle must create an empty repo; then add_repo and push the tree (exclude .godot/). Opus.

## Who owns what between threads
- Main build thread: all gameplay, UI, world, shaders, tests.
- Asset thread (support only, network-enabled env): downloads packs into assets/, updates LICENSES.md/CREATURES.md, and patches AssetLib additively on request.
- Project memory (/tmp/claude/memory/team/silo/): anime-game-decisions.md, anime-game-visuals.md, anime-game-assets.md hold the decisions and gotchas above in more detail.
