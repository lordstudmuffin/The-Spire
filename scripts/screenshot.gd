extends Node
## Renders a scene to PNG for review without a human at the keyboard.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##       res://scenes/screenshot.tscn -- --shot /tmp/out.png [--scene world|creator|menu|loading] [--stats [--stats-verbose]] [--preset Ultra] [--no-batch] [--floor 1|2] [--hour H] [--cam x,y,z:tx,ty,tz] [--body alicia|godette|seed|classic]
##       [--open inventory|quests|map|hud|boss|party|cooking|fishing|home|settings|controls]
##   --open settings|controls works for --scene menu and world (controls = the Controls tab).

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/shot.png"
	var which := "world"
	var cam_spec := ""
	var body := ""
	for i in args.size():
		if args[i] == "--body" and i + 1 < args.size():
			body = args[i + 1]
		if args[i] == "--shot" and i + 1 < args.size():
			out = args[i + 1]
		if args[i] == "--scene" and i + 1 < args.size():
			which = args[i + 1]
		if args[i] == "--cam" and i + 1 < args.size():
			cam_spec = args[i + 1]
	# --preset Low|Medium|High|Ultra: graphics preset for this shot (not saved).
	for i in args.size():
		if args[i] == "--preset" and i + 1 < args.size() and args[i + 1] in Settings.PRESETS:
			Settings.data["preset"] = args[i + 1]
			Settings.apply_graphics()
	# --no-batch: props stay individual instances and grass stays one
	# MultiMesh (the pre-batching structure, for before/after comparisons).
	if "--no-batch" in args:
		AssetLib.batching = false
		WorldArt.foliage_chunking = false
	GameState.reset()
	GameState.character["name"] = "Preview"
	if body != "":
		GameState.character["body"] = body
	for i in args.size():
		if args[i] == "--floor" and i + 1 < args.size():
			GameState.floor = clampi(int(args[i + 1]), 1, 2)
	var path: String = {"world": "res://scenes/world.tscn", "creator": "res://scenes/character_creator.tscn", "menu": "res://scenes/main_menu.tscn", "vrm": "res://scenes/vrm_preview.tscn", "loading": "res://scenes/loading_screen.tscn"}[which]
	# The world builds in one go here (no loading screen, no per-step frames).
	LoadingScreen.enabled = which == "loading"
	# Put the scene directly under the root, as the game would, so UI anchors behave.
	await get_tree().process_frame
	var scene: Node = load(path).instantiate()
	get_tree().root.add_child(scene)
	if which == "loading":
		scene.preview(GameState.floor)
	for i in 5:
		await get_tree().process_frame
	if cam_spec != "" and which == "world":
		var parts := cam_spec.split(":")
		var eye := _vec(parts[0])
		var cam := Camera3D.new()
		cam.position = eye
		scene.add_child(cam)
		cam.look_at(_vec(parts[1]) if parts.size() > 1 else Vector3.ZERO)
		cam.current = true
	if "--hide-lights" in args:
		# DayNight re-shows the sun/moon every frame, so stop it first.
		if "day_night" in scene and scene.day_night:
			scene.day_night.queue_free()
			scene.day_night = null
			await get_tree().process_frame
		var n := 0
		for l in _all(scene, []):
			if l is Light3D:
				l.visible = false
				n += 1
		print("DBG hid lights: ", n)
	if "--light-dump" in args:
		for l in _all(scene, []):
			if l is Light3D and l.visible and l.light_energy > 0.0:
				print("DBG light %s %s energy=%.2f color=%s range=%s" % [l.name, l.get_class(), l.light_energy, l.light_color.to_html(false), str(l.get("omni_range"))])
	if "--stats" in args:
		# Structure, not FPS: MeshInstance3D / MultiMeshInstance3D nodes, the
		# surfaces they submit (one draw per surface, +1 for an outline
		# next_pass), shadow casters, and per-prop-family counts (--stats-verbose).
		var lights := 0
		var meshes := 0
		var mm := 0
		var surfaces := 0
		var mm_instances := 0
		var casters := 0
		var culled := 0
		var families := {}
		for x in _all(scene, []):
			if x is Light3D and x.visible:
				lights += 1
			elif x is MeshInstance3D and x.mesh:
				meshes += 1
				var sc: int = x.mesh.get_surface_count()
				for si in sc:
					var m: Material = x.get_active_material(si)
					surfaces += 2 if m and m.next_pass else 1
				if x.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					casters += 1
				if x.visibility_range_end > 0.0:
					culled += 1
				var fam := _family(x, scene)
				families[fam] = families.get(fam, 0) + 1
			elif x is MultiMeshInstance3D and x.multimesh and x.multimesh.mesh:
				mm += 1
				mm_instances += x.multimesh.instance_count
				var sc2: int = x.multimesh.mesh.get_surface_count()
				for si in sc2:
					var m2: Material = x.material_override if x.material_override else x.multimesh.mesh.surface_get_material(si)
					surfaces += 2 if m2 and m2.next_pass else 1
				if x.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					casters += 1
				if x.visibility_range_end > 0.0:
					culled += 1
		print("DBG lights=%d meshes=%d multimeshes=%d surfaces=%d mm_instances=%d shadow_casters=%d range_culled=%d nodes=%d batched_props=%d batch_meshes=%d" % [lights, meshes, mm, surfaces, mm_instances, casters, culled, _all(scene, []).size(), AssetLib.batched_props, AssetLib.batch_meshes])
		if "--stats-verbose" in args:
			var keys := families.keys()
			keys.sort_custom(func(a, b): return families[a] > families[b])
			for k in keys.slice(0, 40):
				print("DBG   %4d  %s" % [families[k], k])
	# --open inventory|quests|map|hud: seed the preview character with gear,
	# materials and quests, then open that screen (hud = widgets only).
	var open_ui := ""
	for i in args.size():
		if args[i] == "--open" and i + 1 < args.size():
			open_ui = args[i + 1]
	if open_ui != "" and which == "world" and "hud" in scene and scene.hud:
		_seed_ui_state(scene)
		await get_tree().process_frame
		match open_ui:
			"inventory":
				scene.hud.toggle_inventory()
			"quests":
				scene.hud.toggle_quests()
			"map":
				scene.hud.toggle_map()
			"hud":
				scene.hud.add_chat("Mira", "Welcome to the Spire!")
				scene.hud.add_chat("Preview", "Heading out to the boar fields.")
			"cooking":
				# At the Talven camp fire with a full basket; the screen opens.
				scene.player.global_position = scene.TALVEN + Vector3(0, 1, 2.6)
				GameState.add_material("boar_stew", 1)
				LifeData.eat("grilled_trout")
				await get_tree().process_frame
				scene._open_cooking("Talven camp fire")
			"home":
				# Owned, furnished cottage; the camera stands inside by the door.
				GameState.floors_cleared = 1
				GameState.home_owned = true
				for id in LifeData.DECOR:
					GameState.add_decor(id, 1)
				var order := ["rug", "bookshelf", "lantern", "plant", "trophy", ""]
				for i in order.size():
					GameState.place_furniture(i, order[i])
				GameState.store_item(GameState.inventory[4]["id"], true)
				GameState.store_item(GameState.inventory[4]["id"], true)
				LifeData.rest()
				scene.player.global_position = scene._home.spawn_inside + Vector3(-0.6, 0, -1.6)
				scene.player.velocity = Vector3.ZERO
				if cam_spec == "":
					var cam := Camera3D.new()
					cam.position = PlayerHome.INTERIOR + Vector3(3.8, 2.7, 4.0)
					cam.fov = 68
					scene.add_child(cam)
					cam.look_at(PlayerHome.INTERIOR + Vector3(-0.8, 1.0, -2.2))
					cam.current = true
			"fishing":
				# Cast at the pond; the bite (and the widget) is forced three
				# frames before the shot so it is caught mid-minigame.
				var spot: Dictionary = scene._fishing.spots[0]
				scene.player.global_position = spot["pos"] + Vector3(-0.6, 1, 0.4)
				scene.player.velocity = Vector3.ZERO
				if cam_spec == "":
					var cam := Camera3D.new()
					cam.position = spot["pos"] + Vector3(-4.0, 2.6, 4.6)
					scene.add_child(cam)
					cam.look_at(spot["water"] + Vector3(-1.0, 0.4, 0.0))
					cam.current = true
			"party":
				# Fake party of three (names, hp %, levels) plus every chat channel.
				Net.debug_seed_party(["Kyle", "Mira"], [82, 27], [7, 6])
				scene.hud.add_chat("Kyle", "Boars by the north gate, come.", "party")
				scene.hud.add_chat("Mira", "Low on hp, cover me", "party")
				scene.hud.add_chat("Ren", "trade later?", "whisper")
				scene.hud.add_chat("Preview", "Heading out to the boar fields.")
				scene.hud.add_chat("", "Ren joined the party.", "system")
				scene.player.cam_pivot.rotation.y = 0.6
			"nearby":
				Social.ignore("Mira")
				Net.debug_seed_party(["Kyle", "Mira"], [82, 27], [7, 6])
				scene.hud.toggle_nearby()  # offline this resets who_list to just us...
				Net.who_list = [{"name": "Preview", "level": 4, "floor": 1, "party": true}, {"name": "Kyle", "level": 7, "floor": 1, "party": true},
					{"name": "Mira", "level": 6, "floor": 1, "party": true}, {"name": "Ren", "level": 3, "floor": 1, "party": false},
					{"name": "Haldor", "level": 12, "floor": 1, "party": true}, {"name": "Mira", "level": 2, "floor": 1, "party": false}]
				Net.who_received.emit(Net.who_list)  # ...so re-seed and refresh the rows
				Social.unignore("Mira")
			"boss":
				var pl: Node3D = scene.player
				var fwd: Vector3 = -pl.model.global_transform.basis.z
				var bpos: Vector3 = pl.global_position + fwd * 6.0
				scene._spawn_mob({"name": "Floor Guardian: Vargash the Kobold Warlord", "level": 8, "hp": 900, "dmg": 6, "xp": 0, "money": 0,
					"boss": true, "size": [2.2, 2.6, 2.0], "respawns": false, "pos": [bpos.x, bpos.y + 0.3, bpos.z]})
				await get_tree().process_frame
				for e in get_tree().get_nodes_in_group("enemies"):
					if e.global_position.distance_to(bpos) < 2.0:
						e.aggro_range = 0.0
						e.speed = 0.0
						e.hp = 610.0
						e.look_at(Vector3(pl.global_position.x, e.global_position.y, pl.global_position.z))
	# --open ring or ring:status|items|skills|quests|messages|logout
	if open_ui.begins_with("ring") and "hud" in scene and scene.hud:
		scene.hud._toggle_pause()
		var parts := open_ui.split(":")
		if parts.size() > 1:
			for i in RingMenu.ENTRIES.size():
				if RingMenu.ENTRIES[i][0] == parts[1]:
					scene.hud._ring._select(i, false)
					scene.hud._ring.activate(i)
					if parts[1] == "logout":
						scene.hud._ring._confirm_logout()
	if "--settings" in args or open_ui in ["settings", "controls"]:
		var form: SettingsPanel = null
		if scene.has_method("_open_settings"):
			scene._open_settings()
			form = scene._settings_form if "_settings_form" in scene else null
		elif "hud" in scene and scene.hud:
			scene.hud._toggle_pause()
			scene.hud._open_settings()
			form = scene.hud._settings_form
		if open_ui == "controls" and form:
			form.show_tab("Controls")
			form.focus_first()
	# --combat-demo MODE: spawn a boar in front of the player and trigger a
	# combat moment a few frames before the shot. Time is slowed right before
	# the trigger so the effect is caught mid-flight regardless of frame rate.
	# MODE: basic | skill0 | skill1 | skill2 | hit | death | slam | dash | shatter | shatter_player
	#       | parry | guard_break | stagger | windup | guard
	var demo := ""
	var demo_boar: Node3D = null
	for i in args.size():
		if args[i] == "--combat-demo" and i + 1 < args.size():
			demo = args[i + 1]
	if demo != "" and which == "world" and "player" in scene and scene.player:
		var pl: Node3D = scene.player
		var fwd: Vector3 = -pl.model.global_transform.basis.z
		var boss := demo == "slam" or demo.begins_with("boss_")
		var bpos: Vector3 = pl.global_position + fwd * (7.0 if demo.begins_with("boss_") else 1.7)
		scene._spawn_mob({"name": "Floor Guardian: Vargash the Kobold Warlord" if boss else "Field Boar", "level": 1, "hp": 999999, "dmg": 6,
			"boss": boss, "size": [2.2, 2.6, 2.0] if boss else [0.9, 0.8, 1.3], "respawns": false,
			"pos": [bpos.x, bpos.y + 0.3, bpos.z], "brain": "warlord" if demo == "boss_plate" else ""})
		await get_tree().process_frame
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.global_position.distance_to(bpos) < 1.0:
				demo_boar = e
		if demo_boar:
			demo_boar.aggro_range = 0.0
			demo_boar.speed = 0.0
			demo_boar._wander_target = demo_boar.global_position
			demo_boar._wander_timer = 999.0
			demo_boar.look_at(Vector3(pl.global_position.x, demo_boar.global_position.y, pl.global_position.z))
		if cam_spec == "":
			var right: Vector3 = pl.model.global_transform.basis.x
			var cam := Camera3D.new()
			cam.position = pl.global_position + right * 2.6 - fwd * 1.8 + Vector3(0, 1.9, 0)
			if demo.begins_with("boss_"):
				cam.position = pl.global_position + right * 5.0 - fwd * 5.0 + Vector3(0, 7.5, 0)
			scene.add_child(cam)
			cam.look_at(pl.global_position + fwd * (5.0 if demo.begins_with("boss_") else 0.8) + Vector3(0, 1.0, 0))
			cam.current = true
		print("DBG combat-demo ", demo, " boar=", demo_boar != null)
	for i in 40:
		# Frames under xvfb take ~0.5 s, so fire 3 frames out at 0.08x: the
		# shot lands ~0.1 s (game time) into the effect.
		if demo != "" and i == 37 and "player" in scene and scene.player:
			var pl: Node3D = scene.player
			match demo:
				"basic":
					pl._attack()
				"skill0", "skill1", "skill2":
					pl._use_skill(int(demo.substr(5)))
				"hit":
					pl.take_damage(15.0)
				"death":
					if demo_boar:
						demo_boar.take_hit(9999999.0, -pl.model.global_transform.basis.z)
				"shatter":
					# Polygon-shatter burst on the boar (VFX look check).
					var sfx := VFX.get_for(pl)
					if demo_boar and sfx:
						sfx.shatter_node(demo_boar)
						demo_boar.visible = false
				"shatter_player":
					var pfx := VFX.get_for(pl)
					if pfx:
						pfx.shatter(null, pl.model, [], VFX.SHATTER_COLOR, false, 0.0)
				"parry", "guard_break":
					var qfx := VFX.get_for(pl)
					if qfx:
						var at: Vector3 = pl.global_position + Vector3(0, 1.2, 0) - pl.model.global_transform.basis.z * 0.7
						qfx.parry_flash(at, demo == "guard_break")
				"boss_sweep", "boss_slam", "boss_charge", "boss_enrage", "boss_bar", "boss_engage", "boss_plate", "boss_rockfall":
					var bfx := VFX.get_for(pl)
					if demo_boar and bfx:
						var bp: Vector3 = demo_boar.global_position
						match demo:
							"boss_sweep":
								bfx.boss_sweep_warning(demo_boar, 6.0, 150.0, 1.2)
							"boss_slam":
								bfx.boss_slam_warning(demo_boar, bp, 5.0, 1.2)
							"boss_charge":
								bfx.boss_charge_warning(demo_boar, bp, bp - demo_boar.global_transform.basis.z * 14.0, 1.2)
							"boss_enrage":
								bfx.boss_enrage(demo_boar, 1.8)
							"boss_bar":
								bfx.boss_bar_break(demo_boar, 2, 4)
							"boss_engage":
								bfx.boss_engage(demo_boar)
							"boss_rockfall":
								var pp: Vector3 = pl.global_position
								var offs := [Vector3(1.5, 0, -2.5), Vector3(-3.5, 0, -4.0), Vector3(3.0, 0, -6.0)]
								for k in offs.size():
									bfx.boss_rockfall_warning(demo_boar, pp + pl.model.global_transform.basis * offs[k], 2.2, 0.25 + 0.35 * k)
							"boss_plate":
								demo_boar.hp = demo_boar.max_hp * 0.62
								demo_boar._update_label()
				"still_water", "breaking_wave", "hearth_flare", "hearth_glow":
					var hfx := VFX.get_for(pl)
					if hfx:
						if demo == "hearth_glow":
							hfx.hearth_glow(pl)
						else:
							hfx.class_art_cast(pl, "Hearthwright" if demo == "hearth_flare" else "Stillblade", demo)
				"boss_swap", "boss_leap", "plated", "boss_whirl", "boss_descend":
					var bs: Node3D = null
					for e in scene.get_tree().get_nodes_in_group("enemies"):
						if (e.get("is_boss") and e.get("brain") != null) or (demo == "plated" and "halberdier" in str(e.get("display_name")).to_lower()):
							bs = e
							break
					var sfx := VFX.get_for(pl)
					if bs and sfx:
						bs.set("speed", 0.0)
						bs.set("aggro_range", 0.0)
						# Stand it where the --cam shots look (the arena's far side).
						if "ARENA_POS" in scene:
							bs.global_position = scene.ARENA_POS + Vector3(0, 0.2, -6)
							bs.rotation.y = 0.0
						match demo:
							"boss_swap":
								sfx.boss_weapon_swap(bs, {})
							"boss_leap":
								sfx.boss_leap(bs, bs.global_position, bs.global_position + Vector3(0, 0, 8), 1.0)
							"plated":
								sfx.mob_plated_hit(bs, Vector3(0, 0, -1))
							"boss_descend":
								sfx.boss_leap(bs, bs.global_position, bs.global_position + Vector3(0, 0, 6), 1.1)
								sfx.boss_descend(bs, bs.global_position, bs.global_position + Vector3(0, 0, 6), 1.1)
							"boss_whirl":
								sfx.boss_sweep_warning(bs, 4.2, 360.0, 0.9)
								scene.get_tree().create_timer(0.9, false).timeout.connect(func(): sfx.boss_sweep_impact(bs, 4.2, 360.0))
				"battle_result":
					var bh = scene.get("hud")
					if bh and bh.has_method("show_battle_result"):
						bh.show_battle_result({"kills": 3, "foes": {"Field Boar": 2, "Dire Wolf": 1}, "xp": 86, "col": 24,
							"items": {"beast_hide": 2, "iron_ore": 1, "heal_crystal": 1}, "level_ups": 1, "party": 3})
				"last_attack", "last_attack_fallback":
					var lh = scene.get("hud")
					if lh and lh.has_method("show_last_attack"):
						lh.show_last_attack({"foe": "Greytusk, the Old Boar", "item": "" if demo == "last_attack_fallback" else "Greytusk Hide Vest",
							"xp": 120, "col": 60, "mats": {"beast_hide": 3}})
				"switch", "inner_area", "outer_field":
					var wfx := VFX.get_for(pl)
					if wfx and demo == "switch" and demo_boar:
						wfx.switch_flash(demo_boar, 1, 2)
					elif wfx:
						wfx.inner_area_notice(demo == "inner_area")
				"heal_crystal", "teleport_crystal":
					GameState.materials["heal_crystal"] = 3
					GameState.materials["teleport_crystal"] = 1
					GameState.inventory_changed.emit()
					var xfx := VFX.get_for(pl)
					if xfx:
						xfx.crystal_burst(pl.global_position + Vector3(0, 1.0, 0), LifeData.item_color(demo), demo == "teleport_crystal")
				"duel":
					var du = scene.get("_duels")
					if du:
						du.on_net("duel", {"ev": "begin", "duel": 1, "opponent": "Mira", "opponent_peer": 99, "mode": "half", "mode_name": "Half-loss", "count": 3})
						du.on_net("duel", {"ev": "start", "a": "Preview", "b": "Mira", "a_peer": 1, "b_peer": 99, "center": pl.global_position + Vector3(0, 0, -3)})
						du.on_net("duel", {"ev": "hit", "attacker": 1, "defender": 99, "amount": 30.0, "outcome": "hit", "kind": 0, "hp": 74.0, "max": 120.0})
					var dfx := VFX.get_for(pl)
					if dfx:
						dfx.duel_start(pl, demo_boar)
						dfx.duel_ring(pl.global_position + Vector3(0, 0, -6), 9.0, true)
				"chest_open":
					var cfx := VFX.get_for(pl)
					if cfx:
						cfx.chest_open(pl.global_position - pl.model.global_transform.basis.z * 2.5, 4)
				"stagger":
					if demo_boar:
						demo_boar.net_staggered(2.0)
				"windup":
					var wfx := VFX.get_for(pl)
					if demo_boar and wfx:
						wfx.windup_glint(demo_boar, 0.42)
				"slam":
					if demo_boar:
						demo_boar._slam_fx()
						pl.take_damage(10.0)
				"dash":
					pl._dash_timer = pl.DASH_TIME
					var fx := VFX.get_for(pl)
					if fx:
						fx.dash(pl.global_position, -pl.model.global_transform.basis.z)
			Engine.time_scale = 0.3 if demo in ["death", "slam", "shatter_player", "stagger"] or (demo.begins_with("boss_") and demo != "boss_bar") else (0.12 if demo in ["shatter", "boss_bar"] else 0.08)
		# HUD states that decay in real time are set three frames before the shot.
		if open_ui == "fishing" and i == 36 and "player" in scene and scene.player:
			scene._fishing.start(0)
			scene._fishing.state = Fishing.State.WAITING
			scene._fishing._drop_bobber()
			scene._fishing._bite()
			Engine.time_scale = 0.05
		# --summit: stand on the Labyrinth summit (lights the arena braziers).
		if i == 3 and "--summit" in args and scene.has_method("_enter_summit"):
			scene._enter_summit()
		# --stalls-open: every market stall rented and stocked (keepers, wares).
		if i == 3 and "--stalls-open" in args and scene.get("_stalls") != null:
			for st in scene._stalls.stalls:
				(st["keeper"] as Node3D).visible = true
				(st["wares"] as Node3D).visible = true
		# --spawn-boss: raise the floor boss in its arena (for a model check).
		if i == 4 and "--spawn-boss" in args and scene.has_method("_spawn_boss"):
			scene._spawn_boss()
		# --pad: draw gamepad prompts. --unique: hold Twin Fang (unique slots).
		# --bark: stand the player beside the first villager out on a routine.
		if i == 24 and "--bark" in args and "_routines" in scene and scene._routines:
			for n in scene._routines._npcs:
				if scene._routines.bark(n) != "":
					var nn: Node3D = scene._routines._npcs[n]["node"]
					scene.player.global_position = nn.global_position + Vector3(2.8, 0.2, 4.6)
					if "cam_pivot" in scene.player:
						scene.player.cam_pivot.rotation.y = atan2(2.8, 4.6)
					break
		if i == 30 and "--class" in args:
			var ci := args.find("--class")
			if ci + 1 < args.size():
				GameState.unlock_hidden_class(args[ci + 1])
				if "player" in scene and scene.player and "class_cd" in scene.player:
					scene.player.class_cd[1] = 7.0
		if i == 30 and "--unique" in args:
			GameState.unique_skill = UniqueSkills.TWIN_FANG
			GameState.unique_skill_changed.emit(GameState.unique_skill)
		if i == 31 and "--pad" in args:
			InputSetup.device = "gamepad"
			InputSetup.input_device_changed.emit("gamepad")
		# --open death | realm: the death grey-out / a realm announcement banner.
		if open_ui == "death" and i == 30 and "hud" in scene and scene.hud:
			if scene.get("player"):
				scene.player.last_xp_lost = 37
			scene.hud.show_death(8.0, "the Town of First Light")
		if open_ui == "realm" and i == 28 and "hud" in scene and scene.hud:
			scene.hud.realm_announce("A player has claimed the unique skill «Starfall Edge»")
		if demo == "guard" and i == 30 and "player" in scene and scene.player:
			scene.player.press_parry()
			scene.player.guard = Player.GUARD_MAX * 0.55
		if demo == "guard" and i == 36 and "player" in scene and scene.player:
			# Input polling drops the press under the harness; hold the pose.
			scene.player._vrm.play_guard(true)
		if open_ui in ["hud", "boss"] and i == 36 and "player" in scene and scene.player:
			scene.player.skill_cd[0] = 2.6
			scene.player.skill_cd[1] = 7.1
			scene.player._dash_cd = 0.5
			if open_ui == "hud":
				GameState.add_material("iron_ore", 3)
				GameState.add_material("beast_hide", 1)
				GameState.add_item(Crafting.make_item("Iron Sword", 2, "Preview"))
			else:
				GameState.add_xp(GameState.xp_to_next() - GameState.xp)
			Engine.time_scale = 0.25
		await get_tree().process_frame
		if demo != "" and i >= 37 and "--vfx-debug" in args and VFX._inst:
			var cam3 := get_viewport().get_camera_3d()
			for sl in VFX._inst._slashes:
				var m: StandardMaterial3D = sl.material_override
				print("DBG slash f%d vis=%s pos=%s scale=%s rot=%s alpha=%.2f tex=%s screen=%s behind=%s" % [i, sl.visible, sl.global_position, sl.scale, sl.rotation, m.albedo_color.a, m.albedo_texture != null, cam3.unproject_position(sl.global_position) if cam3 else "-", cam3.is_position_behind(sl.global_position) if cam3 else "-"])
	Engine.time_scale = 1.0
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("Saved ", out, " ", img.get_size())
	get_tree().quit()




func _seed_ui_state(scene: Node) -> void:
	GameState.add_material("iron_ore", 14)
	GameState.add_material("beast_hide", 7)
	GameState.add_material("spirit_shard", 3)
	GameState.add_money(480)
	GameState.add_xp(600)
	GameState.smithing_level = 4
	GameState.smithing_xp = 55
	# Life layer: a basket of fish and herbs, a rod, some cooked food.
	for pair in [["minnow", 3], ["river_trout", 4], ["mire_eel", 1], ["moonscale_koi", 1], ["wild_herb", 6], ["willow_rod", 1], ["grilled_trout", 2]]:
		GameState.add_material(pair[0], pair[1])
	GameState.fishing_level = 3
	GameState.fishing_xp = 20
	GameState.cooking_level = 2
	GameState.cooking_xp = 15
	var seeds := [["Iron Sword", 0, "Preview"], ["Spirit Blade", 2, "Preview"], ["Hide Armor", 1, "Preview"], ["Warden Plate", 3, "Haldor"],
		["Iron Sword", 4, "Kyle"], ["Spirit Blade", 5, "Haldor"], ["Hide Armor", 0, "Preview"], ["Warden Plate", 2, "Preview"], ["Iron Sword", 1, "Preview"]]
	for sd in seeds:
		GameState.add_item(Crafting.make_item(sd[0], sd[1], sd[2]))
	GameState.equip(GameState.inventory[1])
	GameState.equip(GameState.inventory[3])
	GameState.start_quest("boar_trouble", 5)
	GameState.advance_quest("boar_trouble", 3)
	GameState.start_quest("wolf_hunt", 6)
	GameState.start_quest("ore_delivery", 6)
	GameState.advance_quest("ore_delivery", 6)
	GameState.start_quest("forge_trial", 5)
	GameState.complete_quest("forge_trial")
	# The Hollowbrook chain mid-way: pelts and herbs done, stew ready, one waystone lit.
	GameState.start_quest("wolf_pelts", 4)
	GameState.complete_quest("wolf_pelts")
	GameState.start_quest("field_herbs", 6)
	GameState.complete_quest("field_herbs")
	GameState.start_quest("tavern_stew", 1)
	GameState.advance_quest("tavern_stew", 1)
	GameState.start_quest("talven_waystones", 3)
	GameState.visit("waystone_0")
	if "hud" in scene and scene.hud:
		scene.hud.tracked_quest = "talven_waystones"
		scene.hud._refresh()


## Name of the prop family a mesh belongs to: its ancestor directly under the
## scene root, with trailing digits stripped (Bld_home_A_blue, Players, ...).
func _family(n: Node, root: Node) -> String:
	var cur := n
	while cur.get_parent() != null and cur.get_parent() != root:
		cur = cur.get_parent()
	return cur.name.rstrip("0123456789") if cur.get_parent() == root else n.name


func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _all(n: Node, acc: Array) -> Array:
	acc.append(n)
	for c in n.get_children():
		_all(c, acc)
	return acc
