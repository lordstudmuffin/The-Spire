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

## Status of the priority round (game thread, 2026-10-25 22:45 UTC)
Built and smoke-green (smoke ~420 checks, realm_test 88, 2-bot soak 0 errors, orphans 0):
- P1 ring menu: scripts/ui/ring_menu.gd (behaviour) + ring_menu_style.gd (look, owned by the visuals thread). Esc/Start opens it. `--open ring[:status|items|skills|quests|messages|logout]` in the screenshot harness.
- P2 crystal sounds: tools/sfx/gen_crystal.py (pure numpy synthesis, regenerate any time) -> assets/audio/crystal/*.ogg, wired in autoload/audio.gd (EVENTS + LAYERS).
- P3 game side: Player.die() death sequence (shatter, grey "YOU ARE DEAD" countdown, respawn), Net DEATH_GRACE, HP colour bands + delayed chip bar, heartbeat under 25%, crit hit-stop offline (Enemy._hit_stop). Visual side (VFX.shatter etc.) by the visuals thread.
- P4 realm DB (Fable): scripts/realm_db.gd, docs/REALM_DB.md.
- P5 unique skill Twin Fang: scripts/unique_skills.gd. Hidden "reaction" stat (dodges of telegraphed mob strikes, parries, 3-kill chains in 8 s); threshold 30 at Lv5+; realm claim cap 1; arts on keys 4-6, checked on the server in Enemy.net_hit.
- P6 limited content: scripts/limited_content.gd. Quests "The Lantern Below" (1 place, Lamplighter Iselde on Labyrinth terrace 1) and "Whispers of the Old Watch" (3 places, Old Watchman Bram at Talven); items Veil of First Dawn (1), Wisplight Rapier (3), Mantle of the First Floor = Last Attack bonus on the Floor 1 Guardian (1). All bound + serialled.
- P7 stalls/restaurants: scripts/life/stalls.gd + scripts/ui/stall_screen.gd (6 stalls SE of the Hollowbrook well, 120 Col/week, 5% tax).
- NEW (Kyle 22:34): parry/guard like the reference Roblox game: Player.press_parry/defend (PARRY_WINDOW 0.22 s, +0.12 s online latency allowance, whiff cooldown 0.7 s, hold = guard with 30% chip damage and a guard bar, 3 blocks = guard break stun). Mob strikes now have a wind-up (Enemy.WINDUP 0.42 s, boss 0.6 s); a parry staggers (boss after 3), staggered mobs take x1.5 ripostes. Keys F / RMB, pad R3. Server-judged (net_parry stamps server time). Hooks for visuals: VFX.parry_flash(pos, broke), VFX.stagger(enemy, secs), VRMCharacter.play_guard(on).
- P8 done (23:05 UTC): 8 farm plots west of Hollowbrook (scripts/life/farms.gd, ui/farm_screen.gd; 60 Col/week, claim plot:hb<i>, crops in LifeData.CROPS, grow only while watered) and guilds (scripts/life/guilds.gd, ui/guild_screen.gd; notice board by the well, 1000 Col + Lv10, ranks Leader/Officer/Member, storage container guild:<gid>, tags on name labels, /g chat, /guild commands). Smoke has `_test_farms_guilds()`. Guild stalls (2026-10-26): an Officer/Leader rents with payload `guild: true`; owner key `guildstall:<gid>` (Stalls.guild_key), one per guild, sign "[TAG] Name", any Officer manages it (Stalls.actor_for), sales less tax go to the guild storage (Stalls.till_for); disband refuses while it has wares and then frees it.
- Pushing: this session can't reach the LFS host. Bundle commits to /mnt/project-files/anime-rpg-bundles/ and ask the "Finish pushing the game to GitHub" thread to push. Gameplay PR is #2 (branch claude/project-thread-i9qmlz).

- Gravelmaw boss (00:00 UTC 26 Oct): scripts/boss_brain.gd (class BossBrain, presets per boss, attached as child "BossBrain" when spawn data has "brain"). 4 HP bars, sentinel adds on each bar break, enrage + phase-2 moveset on the last bar, sweep (parryable) / charge (parryable on arrival) / slam (ring, not parryable), leash reset after 4 s with nobody in the arena. Clients get `net_event(kind, data)` and `signal boss_event`. VFX hooks: boss_engage, boss_sweep_warning/impact, boss_charge_warning/impact, boss_slam_warning/impact, boss_bar_break, boss_enrage, boss_reset. `SMOKE_ONLY=boss` runs just `_test_boss()`. Gotcha: calling a method on a freed typed node segfaults 4.3.
- Boss arena hazard: rockfall from bar 2 down (BossBrain PRESETS rockfall: 3 marked rings every 5-7.5 s, one on a fighter, not parryable, guard blocks). Events hazard / hazard_land; VFX hooks boss_rockfall_warning(enemy, pos, radius, secs) and boss_rockfall_impact(enemy, pos, radius).
- Labyrinth features (scripts/labyrinth_features.gd, world._lab): 2 chests per terrace (a Weathered Chest, and a locked vault needing a Terrace Key from kobolds: scouts 12%, sergeant 100%). Chests are per character: record/save key "chests" {id: unix time}, restocking after 30 or 60 min; the server rolls the loot into the record (action "chest"). 3 spike tiles per terrace on the shared unix clock (rest, then 0.8 s warning rattle, then 0.55 s up for 14 damage, once per cycle), with damage on the authority only. VFX hook chest_open(pos, gear_rank or -1). `SMOKE_ONLY=labyrinth` runs just that block.
- Hidden classes Stillblade (parry fighter: 8 clean parries in a row, then Quartermaster Dain's rite) and Hearthwright (life: 12 dishes from 4 recipes, 5 fish and 3 harvests, then Innkeeper Rook's rite). See docs/HIDDEN_CLASSES.md (scripts/hidden_classes.gd, class arts on R / C or LT+X / LT+B, net kinds 20+, validated in Enemy.net_hit). `SMOKE_ONLY=classes`. HUD has no cooldown caps for class_cd yet (that's the visuals thread's).
- NPC day/night routines (scripts/npc_routines.gd, world._routines): Vesna goes to the tavern porch 19-24, Hesper gathers at dawn 5:30-8:30, and Bram patrols Talven 20-5. Driven by day_night.time_of_day, so the server and clients agree, and server talk checks read the live NPC position. ROUTINES has a "bark" line per NPC that isn't shown yet.
- Duels (scripts/duels.gd, class Duels): `/duel Name [first|half|full]` (First Strike / Half Loss / Total Loss), accept, decline and yield. Allowed anywhere, Inner Areas included: by consent, it is the one way to deal damage in town. 60 s countdown (big numbers every 10 s and for the last 10), then the server validates hits through the same attack paths (shared Enemy._swing_times cooldowns) with a 0.25 s PvP telegraph. Player.defend handles parry and guard, and a parried attacker is stunned and pushed. Forfeit at 40 m, on disconnect, death to a mob or yield. Tally in record "duels". VFX hooks: duel_countdown, duel_start, duel_end, duel_incoming, duel_ring. `SMOKE_ONLY=duels`, and the soak flag `--duel`.
- Accuracy pass (2026-10-26 02:10):
  - Sword Arts have original names (Sweeping Edge, Twin Crescent, Falcon Rush).
  - Inner Areas (Duels.SAFE_ZONES): mobs never target a player inside one, and world._inner_area_check toasts INNER AREA / OUTER FIELD (VFX hook inner_area_notice(inside)).
  - Switch (enemy.gd): within 2 s of a parry stagger, a party mate's first hit deals x1.3 and extends the stagger (hook switch_flash).
  - Crafting.RANKS tops out at "Myth", and item details read "RATING: X".
  - Crystals (LifeData.CRYSTALS): Healing (full HP) and Teleport (to the floor's arrival point, a safe destination). Server action "crystal". Sold by Trader Pell, found in Labyrinth chests. H, or LT+Y on a pad, is a quick Healing Crystal. VFX hook crystal_burst(pos, color, teleport).
  - Weapon proficiency: GameState.sword_prof / record "sword_prof", 0..1000, +1 per landed swing (the server counts once per swing in Enemy.net_hit). Player.SKILLS "prof" gates the arts at 0 / 40 / 120, and the server refuses unlearned arts. Older records and saves are credited (level-1)*60. Player.art_unlocked(i, prof).
  - Durability (scripts/durability.gd, class Durability): forged items carry dur / dur_max (weapon 80, armor 100, +30 per rank). A weapon loses 0.2 per landed swing and 0.5 per parry; armor loses 0.25 per hit taken. The server wears the record (Net.srv_wear, sending a "gear" event at the low/broken lines), and the client mirrors it. Broken gear adds no ATK/DEF. Repair is on the anvil panel (hud._build_craft "Repair" rows, server action "repair" near a smith) for Col, with smithing Lv giving 3% off per level, capped at 45%. GameState.gear_state(slot, state) drives world.gear_notice toasts.
  - Battle results (scripts/battle_results.gd, group "battle_results"): Enemy._grant_share and the online "loot" event add kills, EXP, Col and items. The tally closes 4 s after the last kill and goes to hud.show_battle_result(data), falling back to a toast.
  - Monster and boss pass (02:50):
    - The Floor 1 Guardian is now "Vargash the Kobold Warlord", BossBrain preset "warlord" (quest id gravelmaw_bounty kept for save compatibility).
    - Guard waves: 3 Kobold Halberdiers on engage and on each bar break, trimmed to 1 + fighters and capped at 6 alive. Halberdiers take x0.5 damage unless staggered (Enemy.armor).
    - Moves: 180-degree cleave; a short buckler rush; a leaping smash onto the target's spot with a 2 s punish window.
    - Last bar: a "weapon_swap" event (hooks Enemy.swap_weapon(data) and VFX boss_weapon_swap(enemy, data)), then a 360-degree chaining whirl ("style": "whirl" in the sweep telegraph). Rockfall has been removed from the preset.
    - Field mobs: boars "rush" (RUSH_WINDUP 0.75 s telegraph, hook mob_rush_warning). Wolves, kobold scouts and the sergeant use "pack" calls (hook mob_pack_call); the sergeant also has armor 0.7.
    - New Snaptrap Grove at world.GROVE (38,0,-48): 8 vines, 2 "Fruiting" with a lure (the first hit bursts the fruit and calls the grove; hook mob_lure_burst, rig node "Fruit"), and 1 "Blossoming" that respawns in 240 s and drops snaptrap_bloom for Hesper's "grove_bloom" quest, which pays the Verdant Edge (Epic).
    - Wolves never den inside Talven's Inner Area.
  - Death penalty (Net.death_penalty, Satisfy-style, never a level): you lose 10% of the current level's EXP requirement (capped at what you have), and equipped gear loses 10% durability. The server applies it in srv_damage and sends "xp_lost" with "respawn". Player.die(xp_lost) shows a "Lost N EXP" toast after the respawn.
  - Monument of Climbers (scripts/monument.gd): the realm's characters by level. The server scans user://server_db once, merges the live records and pushes net_names every 20 s and to new peers. Art is any Node3D in group "monument" with set_names(entries); E within 4 m reads the top 10.
- Farming skill: GameState/record farming_level/xp; harvest gives xp (Farms.crop_xp), bonus crop chance 4%/level (cap 50%), +1% seed return per level.

- Party sharing + Last Attack (2026-10-26, Kyle's ask): Net.srv_reward_kill splits EXP/Col (party_split, +10%/member, members within 60 m), gives each drop to one random sharer with a record (Aincrad-style auto-distribution) and hunt-quest credit to every sharer on that quest; battle results carry "party". World._grant_last_attack(killer, la, foe): `la` = {item (LimitedContent id), xp, col, mats, realm}; the limited item while slots last, else the fallback EXP/Col/mats; told to the killer's party (net_system) and realm-announced for the Guardian. Bonuses: BOSS_LA (Mantle, cap 1), SERGEANT_LA (Sergeant's Cleaver, cap 3), GREYTUSK_LA (Greytusk Hide Vest, cap 3; Greytusk, the Old Boar is a named field elite at (0,1,82), respawn 15 min). Any mob data with "la" gets it. Vargash now waits on the throne dais (World.throne_pos(), BossBrain.throne) and opens every fight with a telegraphed leap down (BossBrain._descend: a slam telegraph with leap+descend true), as Illfang does in Aincrad. HUD hook: hud.show_last_attack(data {foe,item,xp,col,mats}) else a toast.

Next for the game thread: soak bots now parry/guard (report shows parries=N); still to do: a `--summit` bot flag so soaks fight the boss, PvP parry later, pad binds for unique arts skill_4-6, a market map marker,  a farming skill/XP, and a screenshot pass on crop scale (Nature Kit at ~1.5).

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
0. DONE (2026-10-26, gameplay thread): **Permadeath slot** in scripts/permadeath.gd (class Permadeath; the rules and their numbers are in its header).
   - Each account gets 2 standard climbers and 1 permadeath one (SaveSystem.kinds_for / Permadeath.slot_kinds). The creator's "Life" card sets `character.permadeath`, and a permadeath start needs a second "Begin with one life?" press. Online, the server record's `permadeath` is the truth.
   - Falls are decided by the server: Net.srv_damage calls _srv_fall, which writes `fallen` {t, cause, where, level, floor}, saves before telling anyone, then runs Permadeath.release (realm release_all and guild forget_holder) and a realm announce. The client gets "fallen" and runs Player.fall, then a forced kick after 11 s. The client returns to the title after FALL_SCREEN. Net.join_refusal refuses the name forever, the local slot is marked (SaveSystem.mark_fallen) and load_game refuses it.
   - Leaving mid-fight (hit within 10 s) gives a gracefully disconnected peer a lingering body: Net.srv_lingering, with world keeping the node until Net.linger_ended (20 s). A crashed client is covered by the ENet timeout. Soak hook: `--permadeath --leave-in-combat`, and scratchpad soak_pd.sh shows left in combat, then fallen, then rejoin refused.
   - Boosts: XP (add_xp), drops (Enemy and srv_reward_kill), LA fallback, and Monument entries `permadeath`/`fallen`/`fall_text`, which MonumentArt marks or strikes. Penalties: crystals (LifeData.crystal_price/use_crystal), wear (Durability.wear), stall trade split (meta.hardcore) and duels forced to First Strike.
   - Not done: a legacy reward to the account's other characters, the party-share bonus split, Hardcore cosmetics, and the guild-storage split. Smoke `_test_permadeath` (SMOKE_ONLY=permadeath).
1. **Review the round-7 screenshots and tune** creature scale/tints, window glow, Controls tab spacing. Opus.
2. **In-world mob pass**: idle/walk blend, attack timing vs hit frame, death clip length vs dissolve, shadows under flying mobs. Opus.
3. DONE (Vargash the Kobold Warlord: BossBrain, 4 bars, halberdier guard, weapon swap, throne leap, stingers). **Real Gravelmaw boss fight**: phases, telegraphed slam/charge, arena hazards, music stingers. Fable-level: new server-authoritative boss state machine is netcode plus combat feel, and it sets the pattern every later boss copies. Opus can do the arena dressing and audio afterwards.
4. **Hollowbrook polish**: tavern and smithy interiors, NPC day/night routines, ambient animals from the animals pack. Opus.
5. **Labyrinth terraces**: traps, locked doors with keys, treasure chests. Opus for content; Fable-level only for the loot-validation design (server-side chest ownership and anti-dupe is a hard-to-undo data-model call).
6. **Crafting depth** (ranks to Myth, repair/durability and the forging minigame are DONE): rank VFX is left (Fable-level shaders).
   - Forging minigame DONE (scripts/forging.gd class Forging, scripts/ui/forge_widget.gd class ForgeWidget, hud._start_forge / forge_begin / forge_result / forge_failed). Weapons and armor take 3 hammer strikes (4 at base >= 12) on a heat bar; each is Perfect / Good / Glance / Miss, and the average is the quality (0..1). Quality shifts the rank roll by up to 3 smithing levels each way (Forging.effective_level), narrows the stat roll toward the top, adds up to +50% smithing EXP, and a flawless run is never Normal. Items carry "quality" (0-100). Tools skip it; a plain "craft" action forges at QUICK_QUALITY 0.3.
   - Online: "forge_start" {recipe} makes the server roll the specs (stored as rec["_forge"], stripped from snapshots) and stamp its clock. Each "forge_strike" {i, at} is graded by the server itself and accepted only if `at` is no later than the server's elapsed time and no earlier than that minus the peer's ENet RTT x1.25 + 90 ms (clamped 140-520). Future, held-back or out-of-order strikes spoil the session. The last strike re-checks the anvil range and crafts at the server's quality. The residual cheat is aiming within one's own ping, worth at most +3 levels on the roll.
   - Bot soak: the "smith" chore now plays the real minigame (world._bot_forge_tick strikes on Perfect). Verified over ENet: "forged Epic Iron Sword at quality 1.00".
7. **Hidden class system**: add 2 more Floor 1 hidden classes with unlock quests and unique Sword Arts. Fable-level: new skills touch balance plus the validated action path and replicated VFX at once. Opus writes the quests and dialogue.
8. **Performance on Forward+**: profile on Kyle's RTX 5070, tune Ultra (SDFGI, FSR2, shadows) and Low; verify batching with `--stats`. Opus prepares the checklist; escalate to Fable only if a frame-time or leak mystery appears.
9. **Controller polish**: physical pad test, glyph art instead of text badges, radial skill menu. Opus.
10. **Accounts and floor transfer**: server records persist already; add account token UI and character transfer between floor servers. Fable-level: cross-server handoff is new architecture and a hard-to-undo data-format decision.
11. **Join race**: a client once dropped when another joined; 2×4-bot staggered tests could not reproduce it. Watch soaks. Fable-level only if it reappears (unexplained netcode bug).
12. DONE: GitHub repo lordstudmuffin/The-Spire. Gotcha: git LFS uploads (.ogg/.png/.glb) failed from this container on 2026-10-26 with an S3 'Authorization error'. New small audio files were committed as plain blobs through per-file `-filter` lines in .gitattributes. Retry LFS, or use the same workaround.

## Status of the visuals thread (2026-10-26 04:10 UTC, resumed 03:46)
- GitHub: branch claude/project-thread-xxm6yq, rolling PR #1 into main (commits authored as lordstudmuffin, no Claude trailers). Shots: /mnt/project-files/anime-rpg-shots/visuals/.
- Done: polygon-shatter death (VFX.shatter, shard/shatter_glow shaders); sky_spire sky (stars, moon, the floor-above "lid"); clean inverted-hull outlines (averaged normals); night window glow on KayKit houses; stone town wall, marble gate columns, Voronoi plaza cobbles (they lead over the photo detail on Forward+), stone fountain; mob plates (MobPlate: threat cursor, slanted HP bar with chip, boss bar pips); border-only hit vignette; presets fixed (MSAA off, High = FSR2 native; Low vs Ultra checked on Forward+, GPU timings still to be measured on Kyle's RTX 5070).
- Combat look: VFX.parry_flash, stagger, windup_glint; boss telegraphs (shaders/telegraph.gdshader: sweep/slam/charge/rockfall with a falling faceted boulder), boss_bar_break, boss_enrage, boss_reset; VRMCharacter.play_guard.
- Hidden classes: VFX.class_art_cast (still_water / breaking_wave / hearth_flare), VFX.hearth_glow (warm light for the 10 s buff); HUD class-art slots (R / C, pad LT+X / LT+B chords) after the unique slots.
- Terraces: kit spike traps (floor_tile_big_spikes, `tips` still the moving node), stone-rim teleport pads with an octahedral crystal, WorldArt.boulder_mesh boulders, clumped moss; VFX.chest_open (rank colour) and chest_sparkle.
- UI look: ring menu (RingMenuStyle), PlayerStatus (SAO-style top-left), party frames in the same HP bands, holographic full map (shaders/map_holo.gdshader), death screen, RealmBanner, guard bar, NpcBark speech bubbles for villagers out on routines (shaders/speech_bubble.gdshader).
- Town: Hall of Iron across the north road (WorldProps.iron_hall, after the Black Iron Palace; replaces ring houses i=4/5, arch clear ~10.6 m) and the Monument of Climbers slab (scripts/monument_art.gd, class MonumentArt, group "monument", set_names(entries); gameplay's scripts/monument.gd feeds it). Roads inside the wall are stone (ground.gdshader townroad).
- Progression / items UI: locked Sword Arts on the skill bar (UITheme.LockOverlay, "PROF 40/120" + progress), One-Handed Sword proficiency line in the Character panel (UITheme.ProfLine), crystal gems + counts on the status readout (PlayerStatus.set_crystals), VFX.crystal_burst (shards, heal rose pillar, teleport light column). Mob plates hide past 34 m (they draw without depth test).
- Monsters (accuracy pass vs Aincrad Floor 1, see memory aincrad-satisfy-reference): kobolds are KayKit bodies dressed by scripts/mob_dress.gd (MobDress.apply: kobold head with long muzzle and leaf ears, tail, spear/axe/halberd/bone axe + buckler; MobDress.draw_blade for the Warlord's last-bar talwar swap). Boss card shows stacked bars as pips. Snaptrap (Little Nepent-style) is a walking pitcher plant (Enemy._build_plant; the "Fruit" node is MeshMerge.mark'ed so hiding it works). Snaptrap Grove: clearings per GROVE_SPOT + WorldProps.grove_dress (trees with trunk colliders, ferns, toadstools, logs).
- Combat VFX hooks added: switch_flash, inner_area_notice, mob_rush_warning, mob_pack_call, mob_lure_burst, boss_weapon_swap, boss_leap (mesh arc tween), mob_plated_hit, whirl style on boss_sweep_warning/impact (arc >= 300).
- Life/UI: BattleResult panel (scripts/ui/battle_result.gd, top-right after fights), durability WearGauge/CrackOverlay on inventory cards, anvil rows and under the Attack key, death screen line "EXP -N · GEAR DURABILITY -10%", WorldProps.stall_keeper (VRM keeper built the first time a stall's Keeper node shows).
- Final round: LastAttackBanner (scripts/ui/last_attack_banner.gd via hud.show_last_attack), "PARTY OF N +X%" row in BattleResult, Greytusk elite look (MobDress "greytusk": grey tint 7abcbc set in Enemy._model_spec, curved tusks, mane, scars; review with mob_review --only greytusk), WorldProps.boss_throne (gameplay seats Vargash there).
- Resumed round: MobPlate.set_elite (gold name + ring, Enemy.elite from data "la"), VFX.boss_descend (roar, dais dust, heavy landing), meadow gusts and gold/lush patches (grass.gdshader + ground.gdshader share the patch formula), Monument permadeath marks and fallen strikes (entry keys "permadeath", "fallen"), FallenScreen.show_in(root, name, info, secs). Harness: --monument-demo, --open fallen, --combat-demo boss_descend.
- Open visual items: creator/slot-screen permadeath styling (waiting on gameplay's UI), preset GPU timings on Kyle's RTX 5070.
- Screenshot harness extras: --combat-demo heal_crystal|teleport_crystal|switch|inner_area|outer_field|battle_result|boss_swap|boss_leap|boss_whirl|plated|last_attack|last_attack_fallback|duel|boss_rockfall|parry|guard_break|stagger|windup|guard|shatter|shatter_player|boss_*|chest_open|still_water|breaking_wave|hearth_flare|hearth_glow, --open death|realm|party|map|ring:<panel>, --class NAME, --bark, --pad, --unique, --spawn-boss, --summit, --stalls-open. Mob lineup: mob_review.tscn -- --floor1 [--only NAME] [--turn DEG].
- Gotcha: VFX._fire ignores tiny scale_min/max in practice (soft circles render ~0.3 m); use star_05 / spark_04 for small embers.
- Next: fields/meadow pass on Forward+, Floor 1 boss arena dressing, preset perf numbers from Kyle's PC.

## Who owns what between threads
- Main build thread: all gameplay, UI, world, shaders, tests.
- Since 20:46 UTC two threads: gameplay (logic, net, hud.gd behaviour, audio) and visuals (shaders/, render_profile, sky/lighting, world_art/world_props, vfx.gd, ui_theme.gd, ring_menu_style.gd, mob_plate.gd, player_status.gd, realm_banner.gd). Shared files take additive patches only.
- Asset thread (support only, network-enabled env): downloads packs into assets/, updates LICENSES.md/CREATURES.md, and patches AssetLib additively on request.
- Project memory (/tmp/claude/memory/team/silo/): anime-game-decisions.md, anime-game-visuals.md, anime-game-assets.md hold the decisions and gotchas above in more detail.
