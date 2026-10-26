extends Node
## Headless logic test. Run with:
##   godot --headless res://scenes/smoke_test.tscn
## Exits with code 1 and prints FAIL lines if any check breaks.

var _fails := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		_fails += 1
		printerr("  FAIL ", what)


func _ready() -> void:
	if OS.get_environment("SMOKE_ONLY") == "boss":
		# Fast loop while working on the Guardian: SMOKE_ONLY=boss godot ... smoke_test.tscn
		await _test_boss()
		print("== Done: %d failure(s)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	if OS.get_environment("SMOKE_ONLY") == "labyrinth":
		await _test_labyrinth()
		print("== Done: %d failure(s)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	print("== GameState")
	GameState.reset()
	GameState.character["name"] = "Tester"
	GameState.apply_origin("Guardian")
	_check(GameState.stats["endurance"] == 4, "origin applies stats")
	var hp0 := GameState.max_hp()
	GameState.add_xp(1000)
	_check(GameState.level > 1, "xp levels up (now Lv %d)" % GameState.level)
	_check(GameState.stat_points == (GameState.level - 1) * 3, "stat points per level")
	_check(GameState.max_hp() > hp0, "max hp grows with level")
	_check(GameState.spend_point("strength"), "spend a stat point")

	print("== Input map / remapping")
	# Every gameplay action has a keyboard/mouse binding and a gamepad binding.
	var need_both := ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "dash", "attack",
		"skill_1", "skill_2", "skill_3", "target", "interact", "inventory", "quest_log", "map", "nearby", "stats_menu",
		"chat", "pause", "map_zoom_in", "map_zoom_out"]
	var missing: Array = []
	for a in need_both:
		if not InputMap.has_action(a):
			missing.append(a + "(absent)")
		elif InputSetup.events(a, "kb").is_empty():
			missing.append(a + "(no key)")
		elif InputSetup.events(a, "pad").is_empty():
			missing.append(a + "(no pad)")
	_check(missing.is_empty(), "every gameplay action has a key and a gamepad binding %s" % ("" if missing.is_empty() else str(missing)))
	var cam_ok := true
	for a in ["camera_up", "camera_down", "camera_left", "camera_right"]:
		cam_ok = cam_ok and InputMap.has_action(a) and not InputSetup.events(a, "pad").is_empty()
	_check(cam_ok, "right-stick camera actions registered")
	_check(absf(InputMap.action_get_deadzone("move_left") - float(Settings.data["stick_deadzone"])) < 0.001, "stick deadzone comes from settings (%.2f)" % InputMap.action_get_deadzone("move_left"))
	_check(InputSetup.event_text(InputSetup.events("jump", "pad")[0]) == "A" and InputSetup.event_text(InputSetup.events("pause", "kb")[0]) == "Esc", "binding glyph text (A, Esc)")
	_check(InputSetup.hint("inventory") == "I", "hints show key names on the keyboard")
	InputSetup.device = "gamepad"
	_check(InputSetup.hint("inventory") == "D-Up" and InputSetup.hint("back") == "B", "hints show pad glyphs on a gamepad")
	InputSetup.device = "keyboard"
	# Remap: save / load round trip through user://settings.json.
	var saved_bindings: Dictionary = Settings.data["bindings"].duplicate(true)
	var f_key := InputEventKey.new()
	f_key.physical_keycode = KEY_K
	var displaced := InputSetup.rebind("jump", f_key)
	_check(displaced == "" and InputMap.event_is_action(f_key, "jump") and InputSetup.events("jump", "kb").size() == 1, "rebind jump to F replaces the key binding")
	_check(not InputSetup.events("jump", "pad").is_empty(), "the gamepad column survives a keyboard rebind")
	var y_btn := InputEventJoypadButton.new()
	y_btn.button_index = JOY_BUTTON_Y
	_check(InputSetup.rebind("dash", y_btn) == "interact" and InputSetup.events("interact", "pad").is_empty(), "binding Y to dash takes it off interact")
	_check(Settings.data["bindings"].has("jump") and Settings.data["bindings"].has("dash") and not Settings.data["bindings"].has("attack"), "only remapped actions are stored")
	Settings.save_settings()
	Settings.data["bindings"] = {}
	InputSetup.apply_bindings({})
	_check(not InputMap.event_is_action(f_key, "jump"), "defaults restored in memory")
	Settings.load_settings()
	Settings.apply_input()
	_check(InputMap.event_is_action(f_key, "jump") and InputMap.event_is_action(y_btn, "dash") and InputSetup.events("interact", "pad").is_empty(), "remaps round-trip through settings.json")
	InputSetup.reset_bindings()
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	_check(InputMap.event_is_action(space, "jump") and not InputMap.event_is_action(f_key, "jump") and Settings.data["bindings"].is_empty(), "reset to defaults")
	Settings.set_value("bindings", saved_bindings)
	Settings.save_settings()

	print("== Crafting")
	var r := Crafting.craft("Iron Sword")
	_check(r.has("error"), "craft refused without materials")
	GameState.add_material("iron_ore", 30)
	GameState.add_material("beast_hide", 30)
	GameState.add_material("spirit_shard", 10)
	GameState.add_money(1000)
	var atk0 := GameState.attack_damage()
	var item := Crafting.craft("Iron Sword")
	_check(not item.has("error"), "craft succeeds with materials")
	_check(GameState.inventory.size() == 1, "item lands in inventory")
	_check(GameState.materials["iron_ore"] == 27, "materials spent")
	GameState.equip(item)
	_check(GameState.attack_damage() > atk0, "equipped weapon raises attack")
	var armor := Crafting.craft("Hide Armor")
	GameState.equip(armor)
	_check(GameState.armor_defense() > 0, "armor gives defense")
	var hp_before := GameState.hp
	GameState.take_damage(10)
	_check(GameState.hp > hp_before - 10, "armor soaks damage")
	var ranks := {}
	for i in 300:
		var rk := Crafting.roll_rank(10, true)
		ranks[rk] = ranks.get(rk, 0) + 1
	_check(ranks.size() >= 4, "rank roll spreads across ranks at skill 10: %s" % str(ranks))
	for i in 3:
		Crafting.craft("Hide Armor")
	_check(GameState.items_crafted == 5, "items_crafted counts (5)")

	print("== Save / load round trip")
	GameState.position = Vector3(1, 2, 3)
	_check(SaveSystem.save_game(2), "save slot 2")
	var d := GameState.to_dict()
	GameState.reset()
	_check(SaveSystem.load_game(2), "load slot 2")
	_check(GameState.character["name"] == "Tester", "name restored")
	_check(GameState.inventory.size() == d["inventory"].size(), "inventory restored")
	_check(GameState.equipped["weapon"] != null, "equipped weapon restored")
	_check(GameState.has_position and GameState.position == Vector3(1, 2, 3), "position restored")
	DirAccess.remove_absolute(SaveSystem.slot_path(2))

	print("== Save slots")
	# Migration: a format-2 file (one slot, token, no meta) gains meta and keeps its token.
	var legacy := GameState.to_dict()  # also the snapshot restored after this section
	legacy["net_token"] = "feedfacefeedfacefeedfacefeedface"
	var lf := FileAccess.open(SaveSystem.slot_path(1), FileAccess.WRITE)
	lf.store_string(JSON.stringify(legacy))
	lf = null
	_check(SaveSystem.migrate() == 1, "migrate() upgrades the one legacy file")
	var mig = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.slot_path(1)))
	_check(mig is Dictionary and mig.get("meta", {}).get("format", 0) == SaveSystem.FORMAT and mig.get("net_token", "") == "feedfacefeedfacefeedfacefeedface", "migrated file has meta and the old net_token")
	_check(SaveSystem.migrate() == 0, "migrate() is idempotent")
	var info1 := SaveSystem.slot_info(1)
	_check(info1["exists"] and info1["name"] == "Tester" and info1["playtime"] == 0.0 and info1["last_played"] > 0, "slot_info reads a migrated slot (%s, played %s)" % [info1["name"], SaveSystem.format_playtime(info1["playtime"])])
	var expect_free := 0 if not SaveSystem.has_save(0) else 2
	_check(SaveSystem.slot_info(2)["exists"] == false and SaveSystem.first_free_slot() == expect_free, "empty slot reported, first free slot is %d" % expect_free)
	# Playtime: the session clock folds into the file on save and carries across load.
	var prev_token := Net.client_token
	SaveSystem.new_game(1)
	_check(SaveSystem.current_slot == 1 and GameState.level == 1 and Net.client_token == "", "new_game(1) resets state, token and makes slot 1 current")
	GameState.character["name"] = "Slotter"
	SaveSystem._session_mark -= 90000  # pretend 90 s went by
	_check(SaveSystem.playtime() >= 90.0, "playtime() counts the running session")
	_check(SaveSystem.save_game(0), "save_game(0) saves to the current slot (1)")
	var info1b := SaveSystem.slot_info(1)
	_check(info1b["name"] == "Slotter" and info1b["playtime"] >= 90.0 and not SaveSystem.has_save(0) or info1b["name"] == "Slotter" and SaveSystem.slot_info(0)["name"] != "Slotter", "slot 1 holds Slotter with 90 s; slot 0 untouched")
	GameState.reset()
	_check(SaveSystem.load_game(1) and GameState.character["name"] == "Slotter" and SaveSystem.playtime() >= 90.0 and SaveSystem.playtime() < 120.0, "load_game(1) restores the character and carries playtime")
	SaveSystem._session_mark -= 30000
	SaveSystem.save_game()
	_check(SaveSystem.slot_info(1)["playtime"] >= 120.0, "second save accumulates (%.0f s)" % SaveSystem.slot_info(1)["playtime"])
	_check(SaveSystem.last_played_slot() == 1, "last_played_slot() is 1")
	_check(SaveSystem.delete_slot(1) and not SaveSystem.has_save(1) and not SaveSystem.delete_slot(1), "delete_slot removes the file once")
	_check(SaveSystem.format_playtime(5820.0) == "1h 37m" and SaveSystem.format_playtime(30.0) == "under a minute", "playtime formatting")
	SaveSystem.current_slot = 0
	Net.client_token = prev_token
	GameState.from_dict(legacy)  # back to the crafted/equipped Tester the later sections expect

	print("== Life layer: fishing tables")
	var frng := RandomNumberGenerator.new()
	frng.seed = 5
	var pond := {}
	for i in 3000:
		var f := LifeData.roll_fish("pond", 1, frng)
		pond[f] = pond.get(f, 0) + 1
	_check(pond.size() == 4, "pond roll covers all four fish: %s" % str(pond))
	_check(pond.get("minnow", 0) > pond.get("moonscale_koi", 0) * 5, "koi are rare at the pond")
	var koi_bw := 0
	var koi_pond := 0
	for i in 3000:
		if LifeData.roll_fish("boardwalk", 1, frng) == "moonscale_koi":
			koi_bw += 1
		if LifeData.roll_fish("pond", 1, frng) == "moonscale_koi":
			koi_pond += 1
	_check(koi_bw > koi_pond * 2, "boardwalk rolls more koi than the pond (%d vs %d)" % [koi_bw, koi_pond])
	_check(LifeData.fish_weights("pond", 10)["moonscale_koi"] > LifeData.fish_weights("pond", 1)["moonscale_koi"] and LifeData.fish_weights("pond", 10)["minnow"] < LifeData.fish_weights("pond", 1)["minnow"], "fishing skill shifts the table toward koi")
	var d0 := LifeData.difficulty("minnow")
	var d3 := LifeData.difficulty("moonscale_koi")
	_check(d3["zone"] < d0["zone"] and d3["speed"] > d0["speed"], "rarer fish: smaller zone, faster marker")
	GameState.start_quest("pond_catch", 5)
	GameState.start_quest("mere_catch", 3)
	var fl := GameState.fishing_level
	for i in 6:
		LifeData.land_fish("mire_eel")
	_check(GameState.materials["mire_eel"] == 6 and GameState.fishing_level > fl, "catches stack and level fishing (Lv %d)" % GameState.fishing_level)
	_check(GameState.quest_ready("pond_catch") and GameState.quest_ready("mere_catch"), "catches advance both fisher quests")
	_check(not LifeData.has_rod(), "no rod by default")
	GameState.add_material("iron_ore", 2)
	GameState.add_material("beast_hide", 2)
	var inv_before := GameState.inventory.size()
	var rod := Crafting.craft("Willow Rod")
	_check(not rod.has("error") and LifeData.has_rod() and GameState.inventory.size() == inv_before, "Willow Rod forges into the pack as a tool, not gear")

	print("== Life layer: cooking and buffs")
	GameState.materials["river_trout"] = 0
	GameState.materials["wild_herb"] = 0
	_check(LifeData.cook("grilled_trout").has("error"), "cooking refused without ingredients")
	GameState.add_material("river_trout", 2)
	GameState.add_material("wild_herb", 5)
	var cooked := LifeData.cook("grilled_trout")
	_check(not cooked.has("error") and GameState.materials["grilled_trout"] == 1 and GameState.materials["river_trout"] == 1, "Grilled Trout cooks and consumes ingredients")
	_check(LifeData.cook("koi_sashimi").has("error"), "Koi Sashimi needs Cooking Lv 3")
	var atk_pre_buff := GameState.attack_damage()
	GameState.add_material("boar_stew", 1)
	_check(LifeData.eat("boar_stew") and GameState.has_buff("boar_stew") and GameState.materials["boar_stew"] == 0, "eating Boar Stew consumes it and starts its buff")
	_check(GameState.attack_damage() > atk_pre_buff * 1.09, "+10% attack buff applies")
	GameState.hp = 10.0
	_check(LifeData.eat("grilled_trout"), "eat Grilled Trout")
	GameState.tick_buffs(5.0)
	_check(GameState.hp > 10.0 and GameState.hp <= 20.01, "regen buff heals over time (hp %.1f)" % GameState.hp)
	GameState.tick_buffs(1000.0)
	_check(GameState.buffs.is_empty() and absf(GameState.attack_damage() - atk_pre_buff) < 0.01, "buffs expire and attack returns to normal")
	var cl := GameState.cooking_level
	for i in 8:
		GameState.add_life_xp("cooking", 30)
	_check(GameState.cooking_level > cl, "cooking levels with xp (Lv %d)" % GameState.cooking_level)
	var spd := GameState.move_speed()
	LifeData.rest()
	_check(GameState.move_speed() > spd and GameState.has_buff("rested"), "rest buff raises speed")

	print("== Life layer: home")
	GameState.money = 100
	_check(not GameState.buy_home(LifeData.HOME_PRICE) and not GameState.home_owned, "cottage refused without Col")
	GameState.money = 400
	_check(GameState.buy_home(LifeData.HOME_PRICE) and GameState.home_owned and GameState.money == 100, "cottage bought for 300 Col")
	_check(LifeData.buy("trophy") != "", "trophy locked before Floor 1 is cleared")
	GameState.money = 1000
	_check(LifeData.buy("rug") == "" and GameState.decor_owned["rug"] == 1, "rug bought from the trader")
	_check(GameState.place_furniture(0, "rug") and not GameState.place_furniture(1, "rug"), "one rug fills one slot only")
	if GameState.inventory.is_empty():
		GameState.add_material("iron_ore", 3)
		Crafting.craft("Iron Sword")
	var sword_id: String = GameState.inventory[0]["id"]
	GameState.equip(GameState.inventory[0])
	_check(GameState.store_item(sword_id, true) and GameState.home_storage.size() == 1 and GameState.equipped["weapon"] == null, "storing equipped gear unequips it")
	_check(GameState.store_item(sword_id, false) and GameState.home_storage.is_empty(), "taking it back out")
	GameState.store_item(sword_id, true)
	GameState.add_buff("boar_stew", 50.0, LifeData.RECIPES["boar_stew"]["buff"])
	_check(SaveSystem.save_game(2), "save with home state")
	var fl2 := GameState.fishing_level
	GameState.reset()
	_check(not GameState.home_owned and GameState.fishing_level == 1, "reset clears the life layer")
	_check(SaveSystem.load_game(2), "load it back")
	_check(GameState.home_owned and GameState.home_furniture[0] == "rug" and GameState.decor_owned.get("rug", 0) == 1 and GameState.home_storage.size() == 1 and GameState.home_storage[0]["id"] == sword_id and GameState.fishing_level == fl2 and GameState.has_buff("boar_stew"), "home, furniture, storage, skills and buffs round-trip through the save")
	DirAccess.remove_absolute(SaveSystem.slot_path(2))

	print("== Server records / anti-cheat helpers")
	_check(Net.is_safe_destination(Vector3(0.3, 0.2, 6.1)), "town plaza is a safe destination")
	_check(not Net.is_safe_destination(Vector3(40, 0, 40)), "open field is not a safe destination")
	_check(Net.in_world_bounds(Vector3(60, 0, -40)) and not Net.in_world_bounds(Vector3(120, 0, 0)), "island bounds")
	_check(Net.in_world_bounds(Vector3(-30, 141, -61)) and not Net.in_world_bounds(Vector3(60, 100, 60)), "tower/terrace bounds")
	var best_base := 0.0
	for rcp in Crafting.RECIPES.values():
		if rcp["kind"] == "weapon":
			best_base = maxf(best_base, float(rcp["base"]))
	_check(Net.weapon_atk_cap(0) < Net.weapon_atk_cap(5) and Net.weapon_atk_cap(5) == ceilf(best_base * Crafting.RANK_MULT[5] * 1.15), "weapon attack cap per rank (%d at Mythical)" % int(Net.weapon_atk_cap(5)))
	_check(Net.xp_to_next(3) == GameState.xp_to_next() or GameState.level != 3, "server xp curve matches GameState")
	var snap_char := Net.sanitize_character({"name": "  Rec<script>Tester  ", "origin": "Nope"})
	_check(snap_char["name"].length() <= 16 and snap_char["origin"] == "Swordsman", "character sanitized")
	var rec := Net._new_record(snap_char, "0123456789abcdef0123456789abcdef", {"strength": 99})
	_check(rec["stats"]["strength"] == 3, "first-join stat claim over budget is ignored")
	Net.srv_records[4242] = rec
	Net.srv_grant_reward(4242, 150, 10)
	_check(rec["level"] == 2 and rec["xp"] == 50 and rec["money"] == 60, "server-side reward levels the record")
	Net.srv_set_reported(4242, 99, 999.0, 9)
	_check(rec["stats"]["strength"] == 3 and float(rec["weapon_atk"]) == 0.0 and absf(Net.srv_attack_for(4242) - (8.0 + 9.0 + 2.0)) < 0.01, "reported strength/weapon ignored; attack comes from the record")
	Net.srv_apply_snapshot(4242, {"level": 99, "xp": 9999, "money": 99999, "materials": {"moonscale_koi": 50},
		"inventory": [{"name": "Hack", "kind": "weapon", "rank": 7, "atk": 5000, "id": "h"}], "equipped": {"weapon": {"id": "h"}},
		"home_owned": true, "fishing_level": 99, "hidden_class": "Forgeborn"})
	_check(rec["level"] == 2 and rec["money"] == 60 and rec["inventory"].is_empty() and rec["materials"]["moonscale_koi"] == 0 and not rec["home_owned"] and rec["fishing_level"] == 1 and rec["hidden_class"] == "", "a 99,999 Col / 50 koi / hacked-blade snapshot is ignored; the record is untouched")
	# Pure server-side actions on the record (no world needed).
	var rs = Net.RecordState.new(rec)
	_check(Crafting.craft("Iron Sword", rs).has("error"), "record craft refused without materials")
	rs.add_material("iron_ore", 10)
	rs.money = 100
	var ri: Dictionary = Crafting.craft("Iron Sword", rs)
	_check(not ri.has("error") and rec["inventory"].size() == 1 and rec["materials"]["iron_ore"] == 7 and rec["money"] == 80 and rec["items_crafted"] == 1, "record craft spends materials and Col and adds the item")
	_check(Net._srv_action(4242, "equip", {"id": ri["id"]}).has("id") and rec["equipped"]["weapon"] != null and int(rec["weapon_atk"]) == int(ri["atk"]) and Net.srv_attack_for(4242) > 19.0, "server equips from the record and derives weapon_atk")
	_check(Net._srv_action(4242, "equip", {"id": "hack"}).has("error") and Net._srv_action(4242, "unequip", {"kind": "armor"}).has("error"), "equipping an unknown item / unequipping an empty slot refused")
	rec["stat_points"] = 1
	_check(Net._srv_action(4242, "spend_point", {"stat": "strength"}).has("stat") and rec["stats"]["strength"] == 4 and Net._srv_action(4242, "spend_point", {"stat": "strength"}).has("error"), "stat points are spent on the record and refused at 0")
	_check(LifeData.cook("grilled_trout", rs).has("error"), "record cook refused without ingredients")
	rs.add_material("river_trout", 1)
	rs.add_material("wild_herb", 1)
	_check(not LifeData.cook("grilled_trout", rs).has("error") and rec["materials"]["grilled_trout"] == 1 and rec["materials"]["river_trout"] == 0, "record cook consumes ingredients")
	var atk_plain := Net.srv_attack_for(4242)
	_check(Net._srv_action(4242, "eat", {"id": "koi_sashimi"}).has("error"), "eat refused without the food")
	rs.add_material("boar_stew", 1)
	_check(Net._srv_action(4242, "eat", {"id": "boar_stew"}).has("id") and rec["buffs"].has("boar_stew") and rec["materials"]["boar_stew"] == 0 and Net.srv_attack_for(4242) > atk_plain * 1.09, "eating on the record buffs the server's attack by 10%")
	rec["hp"] = 10.0
	_check(LifeData.eat("grilled_trout", rs) and rs.regen_tick(1.0) and rec["hp"] > 10.0 and rec["hp"] <= 12.01, "server regen tick heals from the food buff (hp %.1f)" % rec["hp"])
	rec["buffs"]["boar_stew"]["until"] = 0.0
	_check(rs.prune_buffs() and not rec["buffs"].has("boar_stew") and absf(Net.srv_attack_for(4242) - atk_plain) < 0.01, "an expired buff drops off the server's attack")
	rs.heal_full()
	var full: float = rec["hp"]
	_check(not rs.take_damage(10.0) and rec["hp"] < full and rs.take_damage(100000.0) and rec["hp"] == 0.0, "record takes damage and reports a lethal hit")
	rs.heal_full()
	var patch := Net.patch_for_client(rec)
	_check(not patch.has("token") and not patch.has("character") and patch["buffs"].has("grilled_trout") and float(patch["buffs"]["grilled_trout"]["left"]) > 0.0, "patch strips token and looks, buffs carry seconds left")
	var keep := GameState.to_dict()
	GameState.apply_patch(patch)
	_check(GameState.money == rec["money"] and GameState.inventory.size() == 1 and GameState.equipped["weapon"] != null and GameState.has_buff("grilled_trout") and GameState.materials["grilled_trout"] == 0 and GameState.materials["iron_ore"] == 7 and absf(GameState.hp - float(rec["hp"])) < 0.01, "client adopts the patch through GameState.apply_patch")
	GameState.from_dict(keep)
	_check(Net.save_record(rec) and Net.load_record(snap_char["name"])["level"] == 2 and Net.load_record(snap_char["name"]).has("buffs"), "record round trip on disk (with defaults filled)")
	_check(not Net.snapshot_for_client(rec).has("token"), "snapshot to client strips the token")
	DirAccess.remove_absolute(Net.record_path(snap_char["name"]))
	Net.srv_records.erase(4242)

	print("== Party / social helpers")
	_check(Net.party_split(100, 20, 1) == [100, 20], "solo keeps the whole reward")
	_check(Net.party_split(100, 20, 2) == [55, 11], "duo: +10%% pool split in two (%s)" % str(Net.party_split(100, 20, 2)))
	_check(Net.party_split(100, 20, 3) == [40, 8] and Net.party_split(100, 20, 4) == [32, 6], "trio 40 / full party 32 xp each")
	_check(Net.party_split(1, 0, 4) == [1, 0], "a positive base never rounds to nothing")
	_check(Net.sanitize_name("  Ky[le]\u0007Zed  ") == "KyleZed" and Net.sanitize_name("x".repeat(40)).length() == 16, "names lose brackets, control chars and length")
	var pc := Social.parse_command("/w Kyle  hello there ")
	_check(pc["cmd"] == "w" and pc["target"] == "Kyle" and pc["text"] == "hello there", "/w parses target and text")
	_check(Social.parse_command("/P let's go")["cmd"] == "p" and Social.parse_command("/invite Mira")["target"] == "Mira", "/p and /invite parse")
	_check(Social.parse_command("/roll 20")["text"] == "20" and Social.parse_command("/frobnicate")["cmd"] == "?", "/roll keeps its argument, unknown commands flagged")
	_check(Social.parse_command("plain words")["cmd"] == "say", "plain text is a say")
	Social.ignore("Troll")
	_check(Social.is_ignored("troll") and not Social.is_ignored("Tester"), "ignore list is case-insensitive")
	Social.unignore("Troll")
	_check(not Social.is_ignored("Troll") and Settings.data["ignored"].is_empty(), "unignore clears it from settings")
	# Server-side party state machine on fake records (no peers to rpc to).
	var members := ["Alpha", "Bravo", "Charlie", "Delta", "Echo"]
	for i in members.size():
		Net.srv_records[5001 + i] = Net._new_record(Net.sanitize_character({"name": members[i]}), "0123456789abcdef0123456789abcdef", {})
	_check(Net.srv_peer_by_name("bravo") == 5002 and Net.srv_peer_by_name("Nobody") == 0, "names resolve to peers, case-insensitive")
	_check(Net._srv_invite(5001, 5001) != "" and Net._srv_invite(5001, 0) != "", "cannot invite yourself or a ghost")
	_check(Net._srv_invite(5001, 5002) == "" and Net.srv_invites.has(5002), "invite is recorded")
	_check(Net._srv_invite(5003, 5002) != "", "a second inviter must wait for the pending invite")
	Net._srv_respond(5002, true)
	_check(Net.srv_party_of.get(5001, 0) == Net.srv_party_of.get(5002, 0) and Net.srv_party_of.has(5001), "accepting forms a party of two")
	var pid: int = Net.srv_party_of[5001]
	_check(Net.srv_parties[pid]["leader"] == 5001, "inviter leads")
	_check(Net._srv_invite(5002, 5003) != "", "only the leader invites")
	for peer in [5003, 5004]:
		_check(Net._srv_invite(5001, peer) == "", "leader invites %d" % peer)
		Net._srv_respond(peer, true)
	_check(Net.srv_parties[pid]["members"].size() == 4, "party fills to four")
	_check(Net._srv_invite(5001, 5005) != "", "fifth member refused (cap %d)" % Net.PARTY_MAX)
	Net._srv_invite(5005, 5001)
	_check(not Net.srv_invites.has(5001), "members of a party cannot be invited elsewhere")
	Net._srv_leave_party(5001)
	_check(not Net.srv_party_of.has(5001) and Net.srv_parties[pid]["leader"] == 5002, "leader leaving hands over to the oldest member")
	Net._srv_leave_party(5003)
	Net._srv_leave_party(5004)
	_check(not Net.srv_parties.has(pid) and not Net.srv_party_of.has(5002), "party disbands when one member is left")
	_check(Net._srv_invite(5001, 5002) == "", "re-invite after disband")
	Net._srv_respond(5002, false)
	_check(not Net.srv_party_of.has(5002) and not Net.srv_invites.has(5002), "declining leaves no party")
	# Reward split goes through the server records: killer alone (no player
	# nodes to measure range against) keeps the full amount.
	var xp0: int = Net.srv_records[5001]["xp"]
	var shares := Net.srv_reward_kill(5001, 30, 4, Vector3.ZERO)
	_check(shares.size() == 1 and shares[5001] == [30, 4] and Net.srv_records[5001]["xp"] == xp0 + 30, "solo kill rewards the killer through the record")
	for i in members.size():
		Net.srv_records.erase(5001 + i)
	Net.srv_parties.clear()
	Net.srv_party_of.clear()
	Net.srv_invites.clear()
	Net._rate.clear()

	print("== World flows")
	var world: Node3D = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(world.player != null and world.hud != null, "world spawns player and hud")
	_check(get_tree().get_nodes_in_group("enemies").size() >= 22, "mobs spawned (%d)" % get_tree().get_nodes_in_group("enemies").size())
	_check(get_tree().get_nodes_in_group("npcs").size() == 13, "13 NPCs spawned (incl. Old Tam, Trader Pell, the Hollowbrook chain and the limited-quest givers)")
	_check(get_tree().get_nodes_in_group("ore_veins").size() == 10, "10 ore veins")

	# Smith: with 5 crafts done and no trial yet, first talk should offer the trial.
	GameState.items_crafted = 5
	GameState.quests.erase("forge_trial")
	var line: String = world._smith_talk()
	_check(GameState.quests.has("forge_trial"), "smith offers Trial of the Forge: " + line.left(40))
	GameState.quests["forge_trial"]["progress"] = 5
	line = world._smith_talk()
	_check(GameState.hidden_class == "Forgeborn", "trial completion unlocks Forgeborn")
	_check(GameState.class_title() == "Forgeborn", "class title shows hidden class")
	line = world._smith_talk()
	_check(world.hud.any_menu_open(), "smith opens the anvil UI")
	world.hud.toggle_craft()

	# Elder: gather quest.
	GameState.materials["iron_ore"] = 0
	line = world._elder_talk()
	_check(GameState.quests.has("ore_delivery"), "elder starts ore quest")
	GameState.materials["iron_ore"] = 6
	line = world._elder_talk()
	_check(GameState.quest_done("ore_delivery") and GameState.materials["iron_ore"] == 0, "elder completes ore quest and takes the ore")

	print("== Hollowbrook quest chain (offline)")
	for id in ["wolf_pelts", "field_herbs", "tavern_stew", "talven_waystones", "gravelmaw_bounty"]:
		_check(QuestData.QUESTS.has(id) and QuestData.info(id)["giver"] != "Unknown", "quest log data covers %s" % id)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.display_name == "Dire Wolf":
			_check(e.drops.has("wolf_pelt"), "dire wolves drop Wolf Pelts")
			break
	var rhys: NPC = null
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.npc_name == "Captain Rhys":
			rhys = n
	_check(rhys != null and world._beacons.size() == 3 and not world._beacons[0]["fx"].visible, "Captain Rhys and three dark waystones around Talven")
	for id in ["wolf_pelts", "field_herbs", "tavern_stew", "talven_waystones", "gravelmaw_bounty", "wolf_hunt"]:
		GameState.quests.erase(id)
	GameState.materials["wolf_pelt"] = 0
	GameState.visited = []
	world._refresh_beacons()
	var col0: int = GameState.money
	var hides0: int = GameState.materials.get("beast_hide", 0)
	world._vesna_talk()
	_check(GameState.quests.has("wolf_pelts") and GameState.quests["wolf_pelts"]["goal"] == 4, "Vesna starts the wolf pelt quest")
	_check(world._hesper_talk().begins_with("Vesna's wolves first"), "Hesper is locked behind Vesna")
	_check(not GameState.quests.has("field_herbs"), "locked NPC starts nothing")
	GameState.add_material("wolf_pelt", 2)
	_check(GameState.quests["wolf_pelts"]["progress"] == 2, "pelts carried track the gather quest (gather hook)")
	_check("2 of 4" in world._vesna_talk(), "Vesna reports 2 of 4")
	GameState.add_material("wolf_pelt", 2)
	world._vesna_talk()
	_check(GameState.quest_done("wolf_pelts") and GameState.materials["wolf_pelt"] == 0 and GameState.money == col0 + 160 and GameState.materials["beast_hide"] == hides0 + 2, "Vesna takes the pelts and pays Col and hides")
	_check(QuestData.progress_text("wolf_pelts", GameState.quests["wolf_pelts"]) == "Completed", "quest log shows the pelt quest completed")
	GameState.materials["wild_herb"] = 0
	world._hesper_talk()
	_check(GameState.quests.has("field_herbs"), "Hesper starts the herb quest once the wolves are done")
	GameState.add_material("wild_herb", 6)
	var trout0: int = GameState.materials.get("grilled_trout", 0)
	world._hesper_talk()
	_check(GameState.quest_done("field_herbs") and GameState.materials["wild_herb"] == 0 and GameState.materials["grilled_trout"] == trout0 + 2, "Hesper takes six herbs and hands over trout")
	_check(world._rook_talk().begins_with("My cook walked out"), "Rook offers the stew quest")
	_check(GameState.quests.has("tavern_stew") and GameState.quests["tavern_stew"]["progress"] == 0, "stew quest starts at 0 / 1")
	GameState.materials["boar_stew"] = 0
	GameState.add_material("beast_hide", 1)
	GameState.add_material("wild_herb", 2)
	var stew := LifeData.cook("boar_stew")
	_check(not stew.has("error") and GameState.quests["tavern_stew"]["progress"] == 1 and GameState.quest_ready("tavern_stew"), "cooking a Boar Stew readies Rook's quest (cooking hook)")
	_check(world._fen_talk().begins_with("Rook feeds the watch"), "Fen is locked until the stew is delivered")
	var koi0: int = GameState.materials.get("koi_sashimi", 0)
	world._rook_talk()
	_check(GameState.quest_done("tavern_stew") and GameState.materials["boar_stew"] == 0 and GameState.materials["koi_sashimi"] == koi0 + 1, "Rook takes the stew and pays with sashimi")
	world._fen_talk()
	_check(GameState.quests.has("talven_waystones") and GameState.quests["talven_waystones"]["goal"] == 3, "Fen starts the waystone quest")
	world.player.global_position = world.BEACONS[0] + Vector3(1.2, 0, 0)
	_check(world._nearest_interactable()[1] == "Touch the waystone", "waystone prompt")
	world._on_interact()
	_check(GameState.visited.has("waystone_0") and GameState.quests["talven_waystones"]["progress"] == 1 and world._beacons[0]["fx"].visible, "E wakes the stone, records the visit and advances the quest (visit hook)")
	_check(world._nearest_interactable()[1] != "Touch the waystone", "a woken stone offers no prompt")
	world._light_beacon(0)
	_check(GameState.quests["talven_waystones"]["progress"] == 1 and GameState.visited.size() == 1, "touching it again counts nothing")
	_check("1 of 3" in world._fen_talk(), "Fen counts one of three")
	world._light_beacon(1)
	world._light_beacon(2)
	_check(GameState.quest_ready("talven_waystones") and QuestData.progress_text("talven_waystones", GameState.quests["talven_waystones"]) == "Return to Scout Fen", "all three awake: quest ready, tracker says return")
	var shards0: int = GameState.materials.get("spirit_shard", 0)
	world._fen_talk()
	_check(GameState.quest_done("talven_waystones") and GameState.materials["spirit_shard"] == shards0 + 2, "Fen pays the waystone quest")
	rhys.talk()
	_check(GameState.quests.has("wolf_hunt") and not GameState.quests.has("gravelmaw_bounty"), "Rhys offers the wolf hunt first (no bounty yet)")
	GameState.advance_quest("wolf_hunt", 6)
	rhys.talk()
	_check(GameState.quest_done("wolf_hunt"), "wolf hunt turned in through Rhys's handler")
	rhys.talk()
	_check(GameState.quests.has("gravelmaw_bounty") and not GameState.quest_ready("gravelmaw_bounty"), "Rhys posts the town's bounty once the chain is done")
	_check(rhys.talk().begins_with("Gravelmaw waits"), "bounty in-progress line")

	print("== Hollowbrook quest chain (server records)")
	var rec2 := Net._new_record(Net.sanitize_character({"name": "Hollow"}), "0123456789abcdef0123456789abcdef", {})
	Net.srv_records[4545] = rec2
	var rs2 = Net.RecordState.new(rec2)
	var far2 := Vector3(80, 0, -80)
	var npc_pos2 := {}
	for n in get_tree().get_nodes_in_group("npcs"):
		npc_pos2[n.npc_name] = n.global_position
	_check(world.srv_action(4545, rs2, "talk", {"npc": "Trapper Vesna"}, far2).has("error") and not rec2["quests"].has("wolf_pelts"), "Vesna refuses a talk from across the island")
	world.srv_action(4545, rs2, "talk", {"npc": "Trapper Vesna"}, npc_pos2["Trapper Vesna"])
	_check(rec2["quests"].has("wolf_pelts") and rec2["quests"]["wolf_pelts"]["progress"] == 0, "pelt quest starts on the record")
	rs2.add_material("wolf_pelt", 4)
	_check(rec2["quests"]["wolf_pelts"]["progress"] == 4, "record gather hook mirrors the pelts")
	world.srv_action(4545, rs2, "talk", {"npc": "Trapper Vesna"}, npc_pos2["Trapper Vesna"])
	_check(rec2["quests"]["wolf_pelts"]["done"] and rec2["materials"]["wolf_pelt"] == 0 and rec2["money"] == 210 and rec2["materials"]["beast_hide"] == 2, "record turn-in takes the pelts and pays")
	world.srv_action(4545, rs2, "talk", {"npc": "Herbalist Hesper"}, npc_pos2["Herbalist Hesper"])
	rs2.add_material("wild_herb", 6)
	world.srv_action(4545, rs2, "talk", {"npc": "Herbalist Hesper"}, npc_pos2["Herbalist Hesper"])
	_check(rec2["quests"]["field_herbs"]["done"] and rec2["materials"]["grilled_trout"] == 2, "Hesper's quest runs on the record")
	world.srv_action(4545, rs2, "talk", {"npc": "Innkeeper Rook"}, npc_pos2["Innkeeper Rook"])
	_check(rec2["quests"].has("tavern_stew"), "Rook's quest starts on the record")
	rs2.add_material("beast_hide", 1)
	rs2.add_material("wild_herb", 2)
	_check(world.srv_action(4545, rs2, "cook", {"id": "boar_stew"}, world.TALVEN).has("name") and rec2["quests"]["tavern_stew"]["progress"] == 1, "server-side cooking at the Talven fire readies the stew quest")
	var t3: Dictionary = world.srv_action(4545, rs2, "talk", {"npc": "Innkeeper Rook"}, npc_pos2["Innkeeper Rook"])
	_check(rec2["quests"]["tavern_stew"]["done"] and rec2["materials"]["boar_stew"] == 0 and "Koi Sashimi" in str(t3.get("line", "")), "Rook's turn-in on the record")
	_check(world.srv_action(4545, rs2, "waystone", {"i": 0}, far2).has("error") and rec2["visited"].is_empty(), "waystone refused from afar")
	_check(world.srv_action(4545, rs2, "waystone", {"i": 7}, far2).has("error"), "bogus waystone refused")
	world.srv_action(4545, rs2, "talk", {"npc": "Scout Fen"}, npc_pos2["Scout Fen"])
	_check(rec2["quests"].has("talven_waystones"), "Fen's quest starts on the record")
	var lit1: Dictionary = world.srv_action(4545, rs2, "waystone", {"i": 0}, world.BEACONS[0] + Vector3(1, 0, 0))
	_check(int(lit1.get("lit", 0)) == 1 and rec2["visited"] == ["waystone_0"] and rec2["quests"]["talven_waystones"]["progress"] == 1, "waking a stone books the visit and the quest on the record")
	_check(world.srv_action(4545, rs2, "waystone", {"i": 0}, world.BEACONS[0]).has("error"), "a woken stone cannot be woken twice")
	world.srv_action(4545, rs2, "waystone", {"i": 1}, world.BEACONS[1])
	world.srv_action(4545, rs2, "waystone", {"i": 2}, world.BEACONS[2])
	var col2: int = rec2["money"]
	world.srv_action(4545, rs2, "talk", {"npc": "Scout Fen"}, npc_pos2["Scout Fen"])
	_check(rec2["quests"]["talven_waystones"]["done"] and rec2["money"] == col2 + 200 and rec2["materials"]["spirit_shard"] == 2, "Fen pays on the record")
	var t4: Dictionary = world.srv_action(4545, rs2, "talk", {"npc": "Captain Rhys"}, npc_pos2["Captain Rhys"])
	_check(rec2["quests"].has("wolf_hunt") and not rec2["quests"].has("gravelmaw_bounty"), "Rhys's default wolf flow on the record: " + str(t4.get("line", "")).left(30))
	rs2.advance_quest("wolf_hunt", 6)
	world.srv_action(4545, rs2, "talk", {"npc": "Captain Rhys"}, npc_pos2["Captain Rhys"])
	world.srv_action(4545, rs2, "talk", {"npc": "Captain Rhys"}, npc_pos2["Captain Rhys"])
	_check(rec2["quests"]["wolf_hunt"]["done"] and rec2["quests"].has("gravelmaw_bounty") and not rec2["quests"]["gravelmaw_bounty"]["done"], "bounty posted on the record after the chain")
	var inv2: int = rec2["inventory"].size()
	world.srv_action(4545, rs2, "talk", {"npc": "Captain Rhys"}, npc_pos2["Captain Rhys"])
	_check(rec2["inventory"].size() == inv2 and rec2["title"] == "", "no bounty payout before the kill")
	rs2.advance_quest("gravelmaw_bounty")
	var col3: int = rec2["money"]
	world.srv_action(4545, rs2, "talk", {"npc": "Captain Rhys"}, npc_pos2["Captain Rhys"])
	_check(rec2["quests"]["gravelmaw_bounty"]["done"] and rec2["title"] == "Warden of Talven" and rec2["money"] == col3 + 400 and rec2["inventory"].size() == inv2 + 1 and rec2["inventory"][inv2]["rank"] == 1 and rec2["inventory"][inv2]["name"] == "Rare Spirit Blade", "bounty pays a Rare Spirit Blade and the title on the record")
	var patch2 := Net.patch_for_client(rec2)
	_check(patch2.get("title", "") == "Warden of Talven" and patch2.get("visited", []).size() == 3, "patch carries the title and visited stones to the client")
	Net.srv_records.erase(4545)
	Net._srv_cd.erase(4545)

	# Gate and boss.
	GameState.level = 1
	world._try_enter_labyrinth()
	_check(world._boss == null, "gate sealed below level 5")
	GameState.level = 6
	world._try_enter_labyrinth()
	_check(world.player.global_position.distance_to(world.LAB_LEVELS[0]) < 20, "gate opens onto Terrace 1")
	_check(world._pads.size() == 7, "5 teleport pads placed (+ cottage door and exit)")
	world._use_pad(world._pads[1])
	_check(world.player.global_position.distance_to(world.LAB_LEVELS[1]) < 20, "pad climbs to Terrace 2")
	world._use_pad(world._pads[3])
	_check(world._boss != null, "summit pad spawns the boss")
	_check(world.player.global_position.distance_to(world.ARENA_POS) < 20, "player teleported to arena")
	var enemies_before := get_tree().get_nodes_in_group("enemies").size()
	_check(not world._gate_open and not world._floor_gate_ready(), "summit gate sealed before the Guardian falls")
	world._boss.take_hit(100000, Vector3.FORWARD)
	await get_tree().process_frame
	_check(GameState.floors_cleared == 1, "boss death clears floor 1")
	_check(world._exit_portal != null, "exit portal appears")
	_check(GameState.quest_done("floor_boss"), "floor_boss quest completed")
	_check(GameState.quest_ready("gravelmaw_bounty"), "the kill readies the town's bounty (kill hook)")
	var inv_b: int = GameState.inventory.size()
	var col_b: int = GameState.money
	var bline: String = rhys.talk()
	_check(GameState.quest_done("gravelmaw_bounty") and GameState.title == "Warden of Talven" and GameState.money == col_b + 400 and GameState.inventory.size() == inv_b + 1 and GameState.inventory[inv_b]["name"] == "Rare Spirit Blade", "Rhys pays the bounty: Rare blade and the Warden title")
	_check(rhys.talk().begins_with("Warden of Talven"), "Rhys's done line: " + bline.left(30))
	_check("WARDEN OF TALVEN" in world.hud._class_label.text, "HUD shows the earned title")
	_check(get_tree().get_nodes_in_group("enemies").size() == enemies_before - 1, "boss removed from enemies")
	_check(world._gate_open and world._floor_gate_ready(), "summit gate opens to Floor 2 after the kill")
	_check(world._gate.get_node("Door") != null, "sealed gate door is the animated part")

	# Player sword arts.
	var p: Player = world.player
	p._use_skill(2)
	_check(p.skill_cd[2] > 0.0, "sword art goes on cooldown")

	# Server-side validators against this world, on a fake record (what an
	# online client's requests run through: world.srv_action).
	var vrec := Net._new_record(Net.sanitize_character({"name": "Validator"}), "0123456789abcdef0123456789abcdef", {})
	Net.srv_records[4343] = vrec
	var vrs = Net.RecordState.new(vrec)
	var far := Vector3(80, 0, 80)
	var npc_pos := {}
	for n in get_tree().get_nodes_in_group("npcs"):
		npc_pos[n.npc_name] = n.global_position
	_check(world.srv_action(4343, vrs, "mine", {"vein": 0}, far).has("error") and vrec["materials"]["iron_ore"] == 0, "mining refused from across the island")
	var vein_pos: Vector3 = world._vein_positions[0]
	var mined: Dictionary = world.srv_action(4343, vrs, "mine", {"vein": 0}, vein_pos + Vector3(1, 0, 0))
	_check(mined.has("n") and vrec["materials"]["iron_ore"] == mined["n"], "mining next to the vein books ore on the record")
	_check(world.srv_action(4343, vrs, "mine", {"vein": 0}, vein_pos).has("error") and world.srv_action(4343, vrs, "mine", {"vein": 99}, vein_pos).has("error"), "the same vein is spent; a bogus vein refused")
	var spot_pos: Vector3 = world._fishing.spots[0]["pos"]
	_check(world.srv_action(4343, vrs, "land", {"spot": 0}, spot_pos).has("error") and vrec["fish_caught"] == 0, "landing a koi without a cast is refused")
	_check(world.srv_action(4343, vrs, "cast", {"spot": 0}, spot_pos).has("error"), "casting without a rod is refused")
	vrs.add_material("willow_rod", 1)
	_check(world.srv_action(4343, vrs, "cast", {"spot": 0}, far).has("error"), "casting away from the stake is refused")
	var cast: Dictionary = world.srv_action(4343, vrs, "cast", {"spot": 0}, spot_pos)
	_check(LifeData.FISH.has(str(cast.get("fish", ""))), "the server rolls the fish on cast (%s)" % str(cast.get("fish")))
	_check(world.srv_action(4343, vrs, "land", {"spot": 0}, spot_pos).has("error"), "landing right after the cast is too early")
	vrec["_fish"] = {"fish": cast["fish"], "spot": 0, "ms": Time.get_ticks_msec() - 5000}
	var landed: Dictionary = world.srv_action(4343, vrs, "land", {"spot": 0}, spot_pos)
	_check(str(landed.get("fish", "")) == cast["fish"] and vrec["materials"][cast["fish"]] == 1 and vrec["fish_caught"] == 1 and not vrec.has("_fish"), "landing after the wait books the server's fish, once")
	_check(world.srv_action(4343, vrs, "buy_home", {}, world._home.door_pos).has("error") and not vrec["home_owned"], "cottage refused with 50 Col")
	vrs.money = 1000
	_check(world.srv_action(4343, vrs, "buy_home", {}, far).has("error") and not vrec["home_owned"], "cottage refused away from the door")
	_check(not world.srv_action(4343, vrs, "buy_home", {}, world._home.door_pos).has("error") and vrec["home_owned"] and vrec["money"] == 700, "cottage bought on the record at the door")
	_check(world.srv_action(4343, vrs, "buy_home", {}, world._home.door_pos).has("error"), "cannot buy it twice")
	_check(world.srv_action(4343, vrs, "talk", {"npc": "Elder Wren"}, far).has("error") and not vrec["quests"].has("ore_delivery"), "quest talk refused out of range")
	world.srv_action(4343, vrs, "talk", {"npc": "Elder Wren"}, npc_pos["Elder Wren"])
	_check(vrec["quests"].has("ore_delivery") and not vrec["quests"]["ore_delivery"]["done"], "quest starts on the record")
	vrec["materials"]["iron_ore"] = 0
	var t2: Dictionary = world.srv_action(4343, vrs, "talk", {"npc": "Elder Wren"}, npc_pos["Elder Wren"])
	_check(not vrec["quests"]["ore_delivery"]["done"] and vrec["money"] == 700 and "0 of the 6" in str(t2.get("line", "")), "turn-in without progress gives nothing")
	vrec["materials"]["iron_ore"] = 6
	world.srv_action(4343, vrs, "talk", {"npc": "Elder Wren"}, npc_pos["Elder Wren"])
	_check(vrec["quests"]["ore_delivery"]["done"] and vrec["money"] == 780 and vrec["materials"]["iron_ore"] == 0 and vrec["materials"]["spirit_shard"] == 2 and vrec["level"] == 2 and vrec["xp"] == 20, "turn-in with the ore pays XP (levels the record), Col and shards")
	world.srv_action(4343, vrs, "talk", {"npc": "Guide Mira"}, npc_pos["Guide Mira"])
	_check(vrec["quests"].has("boar_trouble") and vrec["quests"]["boar_trouble"]["goal"] == 5, "plain quest NPC starts its quest on the record")
	world.srv_action(4343, vrs, "talk", {"npc": "Guide Mira"}, npc_pos["Guide Mira"])
	_check(not vrec["quests"]["boar_trouble"]["done"] and vrec["money"] == 780, "plain quest NPC: no reward without kills")
	vrs.advance_quest("boar_trouble", 5)
	world.srv_action(4343, vrs, "talk", {"npc": "Guide Mira"}, npc_pos["Guide Mira"])
	_check(vrec["quests"]["boar_trouble"]["done"] and vrec["money"] == 880, "plain quest NPC pays on the record once the kills are in")
	_check(world.srv_action(4343, vrs, "craft", {"recipe": "Iron Sword"}, far).has("error"), "crafting away from an anvil is refused")
	vrs.add_material("iron_ore", 3)
	_check(world.srv_action(4343, vrs, "craft", {"recipe": "Iron Sword"}, npc_pos["Smith Haldor"]).has("name") and vrec["inventory"].size() == 1, "crafting at Haldor's anvil lands on the record")
	_check(world.srv_action(4343, vrs, "craft", {"recipe": "Spirit Blade"}, npc_pos["Smith Haldor"]).has("error"), "crafting without the shards is refused")
	_check(world.srv_action(4343, vrs, "cook", {"id": "grilled_trout"}, far).has("error") and world.srv_action(4343, vrs, "buy", {"id": "rug"}, far).has("error"), "cooking needs a fire, buying needs the trader")
	vrs.add_material("river_trout", 1)
	vrs.add_material("wild_herb", 1)
	_check(world.srv_action(4343, vrs, "cook", {"id": "grilled_trout"}, world.TALVEN).has("name") and vrec["materials"]["grilled_trout"] == 1, "cooking at the Talven fire")
	_check(world.srv_action(4343, vrs, "buy", {"id": "rug"}, npc_pos["Trader Pell"]).has("id") and vrec["decor_owned"]["rug"] == 1 and world.srv_action(4343, vrs, "buy", {"id": "trophy"}, npc_pos["Trader Pell"]).has("error"), "trader sells the rug, not the locked trophy")
	_check(world.srv_action(4343, vrs, "place", {"slot": 0, "id": "rug"}, PlayerHome.INTERIOR + PlayerHome.SLOTS[0]).has("slot") and vrec["home_furniture"][0] == "rug" and world.srv_action(4343, vrs, "place", {"slot": 1, "id": "rug"}, PlayerHome.INTERIOR + PlayerHome.SLOTS[1]).has("error"), "one rug fills one slot on the record")
	_check(world.srv_action(4343, vrs, "herb", {"i": 0}, far).has("error") and world.srv_action(4343, vrs, "herb", {"i": 1}, world._herbs.positions[1]).has("n") and vrec["materials"]["wild_herb"] >= 1, "herbs: refused from afar, picked next to the clump")
	_check(world.srv_action(4343, vrs, "enter_labyrinth", {}, world.TOWER_POS + Vector3(0, 0, 14)).has("error"), "Labyrinth gate refuses a level 1 record")
	_check(world.srv_action(4343, vrs, "bogus", {}, far).has("error"), "unknown action refused")
	Net.srv_records.erase(4343)
	Net._srv_cd.erase(4343)

	# Life layer in the world: herbs, fishing, the camp fire, the cottage.
	_check(world._fishing != null and world._fishing.spots.size() == 2, "two fishing spots on floor 1")
	_check(world._herbs != null and world._herbs.positions.size() >= 12, "herb clumps planted (%d)" % world._herbs.positions.size())
	world.player.global_position = world._herbs.positions[0] + Vector3(0.5, 0, 0)
	var herbs0: int = GameState.materials.get("wild_herb", 0)
	_check(world._nearest_interactable()[1] == "Pick Wild Herb", "herb prompt")
	world._on_interact()
	_check(GameState.materials.get("wild_herb", 0) > herbs0 and not world._herbs.is_up(0), "picking a herb gives Wild Herb and hides the clump")
	GameState.materials["willow_rod"] = 0
	world.player.global_position = world._fishing.spots[0]["pos"] + Vector3(0.3, 0, 0.3)
	_check(str(world._nearest_interactable()[1]).begins_with("Fish at"), "fishing prompt at the pond stake")
	world._on_interact()
	_check(not world._fishing.active(), "no rod, no cast")
	GameState.add_material("willow_rod", 1)
	world._on_interact()
	_check(world._fishing.active() and world._nearest_interactable()[1] == "", "cast starts and takes over the E prompt")
	world._fishing.state = Fishing.State.WAITING
	world._fishing._bite()
	_check(world._fishing.state == Fishing.State.BITE and world._fishing.current_fish != "" and world.hud.life.fishing.is_active(), "bite rolls a fish and shows the widget")
	var fish_id: String = world._fishing.current_fish
	var had: int = GameState.materials.get(fish_id, 0)
	world._fishing._land()
	_check(GameState.materials.get(fish_id, 0) == had + 1 and not world._fishing.active(), "landing books the fish: %s" % fish_id)
	GameState.quests.erase("pond_catch")
	GameState.materials["willow_rod"] = 0
	var tam: NPC = null
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.npc_name == "Old Tam":
			tam = n
	_check(tam != null, "Old Tam by the pond")
	tam.talk()
	_check(GameState.quests.has("pond_catch") and LifeData.has_rod(), "Tam starts the pond quest and lends a rod")
	world.player.global_position = world.TALVEN + Vector3(1.5, 0, -1.5)
	_check(world._nearest_interactable()[1] == "Cook at the camp fire", "camp fire prompt")
	world._on_interact()
	_check(world.hud.life.cooking_open() and world.hud.any_menu_open(), "camp fire opens the cooking screen")
	world.hud.close_screens()
	_check(not world.hud.any_menu_open(), "cooking screen closes with the others")
	GameState.home_owned = false
	GameState.money = 500
	world.player.global_position = world._home.door_pos
	_check(str(world._nearest_interactable()[1]).begins_with("For Sale"), "cottage for sale prompt")
	world._on_interact()
	_check(not GameState.home_owned, "first E only asks")
	world._on_interact()
	_check(GameState.home_owned and GameState.money == 200, "second E buys the cottage for 300 Col")
	world._on_interact()
	_check(world.player.global_position.distance_to(PlayerHome.INTERIOR) < 6.0, "door leads inside")
	world.player.global_position = PlayerHome.INTERIOR + PlayerHome.HEARTH + Vector3(0, 0, 1.0)
	_check(world._nearest_interactable()[1] == "Cook at the hearth", "hearth prompt")
	world._on_interact()
	_check(world.hud.life.cooking_open(), "hearth opens cooking")
	world.hud.close_screens()
	world.player.global_position = PlayerHome.INTERIOR + PlayerHome.BED + Vector3(0.5, 0, 0)
	world.day_night.time_of_day = 22.0
	world._on_interact()
	_check(absf(world.day_night.time_of_day - 7.0) < 0.01 and GameState.has_buff("rested"), "sleeping skips to morning with the rest buff")
	world.player.global_position = PlayerHome.INTERIOR + PlayerHome.CHEST + Vector3(-0.6, 0, 0)
	world._on_interact()
	_check(world.hud.any_menu_open(), "chest opens the storage screen")
	world.hud.close_screens()
	GameState.add_decor("plant", 1)
	world.player.global_position = PlayerHome.INTERIOR + PlayerHome.SLOTS[2]
	world._on_interact()
	_check(GameState.home_furniture[2] == "plant" and world._home._furniture.get_child_count() >= 1, "E at a slot places the owned decoration")
	world._on_interact()
	_check(GameState.home_furniture[2] == "", "E again cycles back to empty")
	world.player.global_position = world._home.exit_pos
	world._on_interact()
	_check(world.player.global_position.distance_to(world._home.door_out) < 2.0, "exit mat leads back outside")
	for q in ["pond_catch", "mere_catch"]:
		GameState.complete_quest(q)
	world.hud.tracked_quest = ""
	world.hud._refresh()

	print("== UI screens")
	_check(QuestData.QUESTS.has("pond_catch") and QuestData.QUESTS.has("mere_catch"), "quest data covers the fisher quests")
	var hud: HUD = world.hud
	_check(MapData.landmarks().size() >= 7, "map data lists %d landmarks" % MapData.landmarks().size())
	_check(MapData.place_name(Vector2(0, 15)) == "Town of First Light", "place name resolves the town")
	var life_marks := {}
	for l in MapData.landmarks():
		life_marks[l["label"]] = l["pos"]
	var mk3: Vector3 = load("res://scripts/life/stalls.gd").market_center(world.HOLLOWBROOK)
	_check(life_marks.has("Market") and life_marks.has("Farm Plots") and life_marks.has("Guild Board") and (life_marks["Market"] as Vector2).distance_to(Vector2(mk3.x, mk3.z)) < 0.1, "map marks the Market, Farm Plots and Guild Board")
	_check(MapData.place_name(life_marks["Market"]) == "Market" and MapData.place_name(life_marks["Farm Plots"]) == "Farm Plots", "standing at the market / farm names the place")
	for id in hud.QUEST_NAMES:
		_check(QuestData.QUESTS.has(id), "quest data covers %s" % id)
	for a in ["inventory", "quest_log", "map", "map_zoom_in", "map_zoom_out"]:
		_check(InputMap.has_action(a), "input action %s registered" % a)
	GameState.start_quest("boar_trouble", 5)
	GameState.advance_quest("boar_trouble", 2)
	_check(hud.tracked_quest == "boar_trouble", "HUD tracks the new quest")
	_check(hud.toggle_inventory() and hud.any_menu_open(), "inventory opens")
	_check(not hud.toggle_inventory() and not hud.any_menu_open(), "inventory closes")
	_check(hud.toggle_quests() and hud.any_menu_open(), "quest log opens")
	hud.close_screens()
	_check(hud.toggle_map() and hud.any_menu_open(), "map opens")
	hud.toggle_map()
	_check(not hud.any_menu_open(), "map closes")
	_check(hud.toggle_stats() and hud.any_menu_open(), "Tab (toggle_stats) opens the inventory screen")
	hud.close_screens()
	_check(InputMap.has_action("nearby") and hud.toggle_nearby() and hud.any_menu_open(), "Nearby panel (O) opens")
	hud.close_screens()
	# Ring menu: opens on pause, panels slide out, logout asks first, closes.
	hud._toggle_pause()
	_check(hud.is_paused() and hud._ring.is_open and hud._ring.visible, "ring menu opens on pause")
	var ring_nodes := hud._ring.get_child_count()
	for i in RingMenu.ENTRIES.size():
		if hud._ring._panel_kind(RingMenu.ENTRIES[i][0]):
			hud._ring.activate(i)
			_check(hud._ring.current_panel == RingMenu.ENTRIES[i][0] and hud._ring._panel_body.get_child_count() > 0, "ring panel %s fills" % RingMenu.ENTRIES[i][0])
	hud._ring._confirm_logout()
	_check(hud._ring._sub.visible, "log out asks for confirmation in a second panel")
	_check(hud._ring.back() and not hud._ring._sub.visible, "back closes the confirmation first")
	_check(hud._ring.get_child_count() == ring_nodes, "ring panels reuse their nodes")
	hud._toggle_pause()
	_check(not hud.is_paused() and not hud._ring.is_open, "ring menu closes on pause again")
	hud._toggle_pause()
	hud._ring.activate(4)  # Map: leaves the menu and opens the full screen.
	_check(not hud.is_paused() and hud._map_panel.visible, "ring Map entry opens the map screen")
	hud.close_screens()
	# Unique skill: hidden reaction stat -> realm claim (one holder) -> casts.
	var rdb = Net.get_realm()
	var me_key: String = Net.local_holder()
	rdb.release(UniqueSkills.TWIN_FANG, me_key)
	GameState.unique_skill = ""
	GameState.hidden_stats = {"reaction": UniqueSkills.SKILLS[UniqueSkills.TWIN_FANG]["threshold"] - 1}
	var lvl0 := GameState.level
	GameState.level = maxi(GameState.level, 5)
	GameState.note_hidden("kill")
	GameState.note_hidden("kill")
	_check(GameState.unique_skill == "", "unique skill not granted below the threshold")
	GameState.note_hidden("dodge")
	_check(GameState.unique_skill == UniqueSkills.TWIN_FANG and rdb.is_holder(UniqueSkills.TWIN_FANG, me_key), "dodge crosses the threshold: Twin Fang granted and registered")
	_check("hidden" in GameState.to_dict() and not Net.snapshot_for_client({"hidden": {"reaction": 3}, "name": "x"}).has("hidden"), "hidden stats saved but never sent to clients")
	var rival: String = Net.RealmDBScript.holder_key("tok", "Rival")
	_check(UniqueSkills.try_grant(rdb, rival, 50, {"reaction": 999}, "") == "", "a second character cannot take a held unique skill")
	var pl_u: Player = world.player
	_check(pl_u.use_unique(0) and pl_u.unique_cd[0] > 0.0, "holder casts a unique Sword Art")
	_check(not pl_u.use_unique(0), "unique art respects its cooldown")
	await get_tree().create_timer(1.2, true, false, true).timeout
	# Gamepad chord: target (LT) held + the third Sword Art button = third unique art.
	pl_u.unique_cd[2] = 0.0
	pl_u.skill_cd[2] = 0.0
	Input.action_press("target")
	Input.action_press("skill_3")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("skill_3")
	Input.action_release("target")
	_check(pl_u.unique_cd[2] > 0.0 and pl_u.skill_cd[2] == 0.0, "target + Sword Art button casts the unique art instead (gamepad chord)")
	await get_tree().create_timer(1.4, true, false, true).timeout
	pl_u.unique_cd[1] = 0.0
	rdb.release(UniqueSkills.TWIN_FANG, me_key)
	_check(not pl_u.use_unique(1) and GameState.unique_skill == "", "losing the registry slot revokes the skill")
	GameState.level = lvl0
	GameState.hidden_stats = {}
	# Limited quests and items: realm slots, bound serial items, one copy each.
	for lid in ["lantern_below", "old_watch_whispers", "veil_first_dawn", "wisplight_rapier", "la_floor1"]:
		rdb.release(lid, me_key)
	GameState.quests.erase("lantern_below")
	var shards_keep := int(GameState.materials.get("spirit_shard", 0))
	GameState.materials["spirit_shard"] = 0
	# The Guardian test earlier may already have paid the Last Attack mantle.
	GameState.inventory = GameState.inventory.filter(func(it): return not LimitedContent.is_bound(it))
	var line_l: String = world._iselde_talk(GameState)
	_check(GameState.quests.has("lantern_below") and rdb.is_holder("lantern_below", me_key) and "Limited quest" in line_l, "accepting a limited quest reserves its realm slot")
	_check(not rdb.reserve("lantern_below", 1, rival).get("ok", true), "a full limited quest refuses a second taker")
	_check("%d of %d" % [0, 6] in world._iselde_talk(GameState), "limited quest shows progress")
	GameState.materials["spirit_shard"] = 6
	var inv_n := GameState.inventory.size()
	world._iselde_talk(GameState)
	var veil = GameState.inventory[-1] if GameState.inventory.size() > inv_n else {}
	_check(GameState.quest_done("lantern_below") and veil is Dictionary and veil.get("name", "") == "Veil of First Dawn" and LimitedContent.is_bound(veil) and str(veil.get("serial", "")) != "", "turn-in pays the bound, serialled limited item")
	_check(rdb.is_holder("veil_first_dawn", me_key) and LimitedContent.slots_left("veil_first_dawn") == 0, "the item claim is on the realm")
	_check(LimitedContent.grant_item(GameState, "veil_first_dawn").get("already", false) and GameState.inventory.size() == inv_n + 1, "a holder never gets a second copy")
	world._grant_last_attack(1)
	world._grant_last_attack(1)
	var mantles := 0
	for it in GameState.inventory:
		if it is Dictionary and it.get("name", "") == "Mantle of the First Floor":
			mantles += 1
	_check(mantles == 1 and rdb.is_holder("la_floor1", me_key), "Last Attack bonus is granted once")
	var dup: Dictionary = veil.duplicate(true)
	dup["id"] = "dupe_copy"
	var fake := {"name": "Tester", "token": "", "inventory": [veil.duplicate(true), dup], "home_storage": [], "equipped": {"weapon": null, "armor": null}}
	rdb.verify_record(fake)
	_check(fake["inventory"].size() == 1, "a duplicated limited item is removed on load")
	# Clean up so local play keeps every slot free.
	for lid in ["lantern_below", "old_watch_whispers", "veil_first_dawn", "wisplight_rapier", "la_floor1"]:
		rdb.release(lid, me_key)
	GameState.inventory = GameState.inventory.filter(func(it): return not LimitedContent.is_bound(it))
	GameState.quests.erase("lantern_below")
	GameState.materials["spirit_shard"] = shards_keep
	hud._chat_lines.clear()  # realm announcements went to chat; later chat checks count lines
	# Mob strikes are telegraphed: stepping out during the wind-up dodges.
	var mob: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.visible and not e.is_boss:
			mob = e
			break
	if mob:
		GameState.hidden_stats = {}
		var hp_wind := GameState.hp
		mob._windup_target = pl_u
		pl_u.global_position = mob.global_position + Vector3(20, 0, 0)
		mob._resolve_strike(1.3 + mob.size.z * 0.5)
		_check(GameState.hp == hp_wind and int(GameState.hidden_stats.get("reaction", 0)) == 0, "far-away target is neither hit nor credited")
		mob._windup_target = pl_u
		pl_u.global_position = mob.global_position + Vector3(2.4, 0, 0)
		mob._resolve_strike(1.3 + mob.size.z * 0.5)
		_check(GameState.hp == hp_wind and int(GameState.hidden_stats.get("dodges", 0)) == 1, "stepping out of reach during the wind-up is a dodge")
		mob._windup_target = pl_u
		pl_u.global_position = mob.global_position + Vector3(0.5, 0, 0)
		mob._resolve_strike(1.3 + mob.size.z * 0.5)
		_check(GameState.hp < hp_wind, "staying in reach takes the blow")
		GameState.heal_full()
		# Parry: tap as the strike lands -> no damage, mob staggers, riposte.
		mob._posture = 0
		mob._stagger = 0.0
		pl_u.global_position = mob.global_position + Vector3(0.5, 0, 0)
		pl_u.model.look_at(Vector3(mob.global_position.x, pl_u.model.global_position.y, mob.global_position.z))
		pl_u._parry_ready_ms = 0
		pl_u.press_parry()
		var hp_p := GameState.hp
		mob._windup_target = pl_u
		mob._resolve_strike(1.3 + mob.size.z * 0.5)
		_check(GameState.hp == hp_p and mob.is_staggered() and pl_u.parries >= 1, "a timed parry deflects the strike and staggers the mob")
		var mob_hp: float = mob.hp
		mob.take_hit(10.0, Vector3.FORWARD, 1)
		_check(is_equal_approx(mob_hp - mob.hp, 10.0 * Enemy.RIPOSTE_MULT), "hits on a staggered mob are ripostes")
		mob._stagger = 0.0
		# Holding after the window guards: chip damage and the guard bar wears.
		pl_u._parry_open_ms = -100000
		var g0: float = pl_u.guard
		mob._windup_target = pl_u
		mob._resolve_strike(1.3 + mob.size.z * 0.5)
		_check(GameState.hp < hp_p and hp_p - GameState.hp <= mob.damage * 0.31 + 0.5 and pl_u.guard < g0, "guarding takes chip damage and wears the guard bar")
		for k in 3:
			mob._windup_target = pl_u
			mob._resolve_strike(1.3 + mob.size.z * 0.5)
		_check(pl_u.is_stunned() and not pl_u.blocking, "an empty guard bar is a guard break (stunned)")
		# Mashing: a whiffed parry goes on cooldown, a second press inside it guards only.
		pl_u._stun = 0.0
		pl_u.guard = Player.GUARD_MAX
		pl_u.release_parry()
		pl_u._parry_ready_ms = 0
		pl_u.press_parry()
		pl_u._parry_open_ms -= 1000  # the window passed with no strike: a whiff
		pl_u.release_parry()
		pl_u.press_parry()
		_check(Time.get_ticks_msec() - pl_u._parry_open_ms > int(Player.PARRY_WINDOW * 1000.0), "a whiffed parry can't be re-opened by mashing")
		pl_u.release_parry()
		mob._posture = 0
		mob._stagger = 0.0
		GameState.heal_full()
		GameState.hidden_stats = {}
	# Death: shatter, grey screen with countdown, respawn at the arrival point.
	var pl: Player = world.pl if "pl" in world else world.player
	pl.take_damage(1.0e6)
	_check(pl.is_dying() and hud.is_dead_screen() and not pl.input_enabled, "lethal hit starts the death sequence")
	pl.take_damage(50.0)
	_check(pl.is_dying(), "no damage while dying")
	await get_tree().create_timer(Player.DEATH_SHATTER + Player.DEATH_TIME + 0.3, true, false, true).timeout
	_check(not pl.is_dying() and pl.input_enabled and pl.model.visible, "player respawns after the countdown")
	_check(pl.global_position.distance_to(GameState.spawn_point()) < 3.0 and GameState.hp >= GameState.max_hp(), "respawn at the arrival point with full HP")
	await get_tree().create_timer(0.5, true, false, true).timeout
	_check(not hud.is_dead_screen(), "death screen fades out")
	Net.debug_seed_party(["Kyle", "Mira"], [82, 24], [7, 5])
	_check(Net.in_party() and Net.party_size() == 3 and Net.party_ids.size() == 2, "seeded party of three")
	var n0: int = hud._chat_lines.size()
	hud.add_chat("Kyle", "on my way", "party")
	hud.add_chat("Mira", "psst", "whisper")
	hud.add_chat("", "Invited Kyle to your party.", "system")
	hud.add_chat("Mira", "Welcome [b]to[/b] the Spire!")
	_check(hud._chat_lines.size() == n0 + 4 and "[lb]b]to[lb]/b]" in hud._chat_lines[n0 + 3], "chat lines carry channel colours and escape bbcode")
	Social.ignore("Mira")
	hud.add_chat("Mira", "ignored line")
	_check(hud._chat_lines.size() == n0 + 4, "ignored players are muted")
	Social.unignore("Mira")
	hud._on_chat_submitted("/roll 6")
	_check(hud._chat_lines.size() == n0 + 5 and "rolls" in hud._chat_lines[n0 + 4], "/roll offline rolls locally")
	Net._party_reset()
	_check(not Net.in_party(), "party state resets")
	# Equip / unequip through the screen helpers.
	var first: Dictionary = GameState.inventory[0]
	GameState.equip(first)
	_check(InventoryScreen.is_equipped(first), "screen sees the equipped item")
	InventoryScreen.unequip(first["kind"])
	_check(GameState.equipped[first["kind"]] == null, "unequip clears the slot")
	# Opening and closing repeatedly must not grow the tree (pooled cards).
	hud.toggle_inventory()
	hud.close_screens()
	var nodes_before := get_tree().get_node_count()
	for i in 25:
		hud.toggle_inventory()
		hud.close_screens()
		hud.toggle_quests()
		hud.close_screens()
		hud.toggle_map()
		hud.close_screens()
	await get_tree().process_frame
	var nodes_after := get_tree().get_node_count()
	_check(nodes_after <= nodes_before + 2, "screens reuse their nodes (%d -> %d)" % [nodes_before, nodes_after])
	hud.feed("+3  Iron Ore", "ore")
	hud.toast("Test", "sub", "kicker")
	hud._on_level_up(GameState.level)
	_check(true, "feed, toast and level banner run headless")

	print("== Floor 2: Mirewood")
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.floor = 2
	GameState.has_position = false
	world = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(world.player != null and world.hud != null, "floor 2 world spawns player and hud")
	_check(world.player.global_position.distance_to(GameState.spawn_point()) < 3.0, "player arrives at the Mirewood waygate")
	_check(world.TOWER_POS == Floor2Art.TOWER and world.LAB_LEVELS.size() == 1, "floor 2 layout: one terrace, tower moved")
	var mobs2 := get_tree().get_nodes_in_group("enemies").size()
	_check(mobs2 >= 29, "floor 2 mobs spawned (%d)" % mobs2)
	var kinds := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		kinds[e.display_name] = true
	_check(kinds.has("Mire Toad") and kinds.has("Thornback Stag") and kinds.has("Marsh Wisp"), "toads, stags and wisps present: %s" % str(kinds.keys()))
	_check(get_tree().get_nodes_in_group("npcs").size() == 5, "5 NPCs on floor 2 (incl. Fisher Maud)")
	_check(world._fishing.spots.size() == 2 and world._fishing.spot_kind(1) == "boardwalk", "Mere shore and boardwalk fishing spots")
	_check(world._campfires.size() == 1 and world._home == null, "Thornwick fire pit cooks; no cottage on floor 2")
	GameState.quests.erase("mere_catch")
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.npc_name == "Fisher Maud":
			n.talk()
	_check(GameState.quests.has("mere_catch"), "Fisher Maud starts the eel quest")
	_check(get_tree().get_nodes_in_group("ore_veins").size() == 6, "6 ore veins on floor 2")
	_check(world._pads.size() == 3, "3 teleport pads on floor 2")
	_check(world.get_node_or_null("Lake") != null and world.get_node_or_null("Boardwalk") != null, "lake and boardwalk built")

	# Huntmaster: stag quest through the default NPC flow.
	var sable: NPC = null
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.quest_id == "stag_hunt":
			sable = n
	_check(sable != null, "Huntmaster Sable offers the stag hunt")
	sable.talk()
	_check(GameState.quests.has("stag_hunt"), "stag hunt started")
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.display_name == "Thornback Stag":
			_check(e.quest_id == "stag_hunt", "stags advance the stag hunt")
			break
	GameState.advance_quest("stag_hunt", 6)
	var xp_before := GameState.xp + GameState.level * 100000
	sable.talk()
	_check(GameState.quest_done("stag_hunt") and GameState.xp + GameState.level * 100000 > xp_before, "stag hunt turned in with reward")

	# Shrine keeper: wisp essence gather quest unlocks the Drowned Plate recipe.
	GameState.materials["wisp_essence"] = 0
	world._keeper_talk()
	_check(GameState.quests.has("shrine_rite"), "keeper starts the shrine rite")
	var plate := Crafting.craft("Drowned Plate")
	_check(plate.has("error"), "Drowned Plate refused before the rite")
	GameState.materials["wisp_essence"] = 5
	world._keeper_talk()
	_check(GameState.quest_done("shrine_rite") and GameState.recipe_unlocked("shrine_rite") and GameState.materials["wisp_essence"] == 0, "rite completes, takes the essence, teaches the recipe")
	GameState.add_material("wisp_essence", 4)
	GameState.add_material("stag_horn", 4)
	GameState.add_material("iron_ore", 20)
	GameState.add_material("beast_hide", 10)
	GameState.add_money(2000)
	plate = Crafting.craft("Drowned Plate")
	_check(not plate.has("error") and plate["def"] >= 11, "Drowned Plate crafts after the rite (def %s)" % str(plate.get("def")))
	var blade := Crafting.craft("Mirewood Blade")
	_check(not blade.has("error") and blade["atk"] >= 15, "Mirewood Blade crafts (atk %s)" % str(blade.get("atk")))

	# Wisp bolt: ranged damage through the normal damage path.
	var wisp: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.display_name == "Marsh Wisp":
			wisp = e
	_check(wisp != null and wisp.ranged > 0.0, "wisps are ranged")
	GameState.heal_full()
	var hp_full := GameState.hp
	world.player.global_position = wisp.global_position + Vector3(4, 0, 0)
	wisp._bolt(world.player)
	await get_tree().create_timer(0.7).timeout
	_check(GameState.hp < hp_full, "wisp bolt damages the player")

	# Gate, terrace and the Drowned Knight.
	GameState.level = 5
	world._try_enter_labyrinth()
	_check(world.player.global_position.distance_to(world.LAB_LEVELS[0]) > 20, "floor 2 gate sealed below level 10")
	GameState.level = 12
	world._try_enter_labyrinth()
	_check(world.player.global_position.distance_to(world.LAB_LEVELS[0]) < 20, "gate opens onto the Mirewood terrace")
	_check(GameState.quests.has("floor_boss_2"), "floor 2 boss quest started")
	world._use_pad(world._pads[1])
	_check(world._boss != null and "Mirelord" in world._boss.display_name, "summit pad spawns Mirelord")
	_check(world.player.global_position.distance_to(world.ARENA_POS) < 20, "player teleported to the floor 2 arena")
	var adds := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.display_name == "Drowned Wisp":
			adds += 1
	_check(adds == 2, "Mirelord raises two Drowned Wisps (%d)" % adds)
	_check(world._boss.summon.is_valid(), "boss summon hook wired")
	world._boss_summon(world._boss)
	adds = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.display_name == "Drowned Wisp":
			adds += 1
	_check(adds == 4, "summon caps at four wisps (%d)" % adds)
	_check(not world._gate_open, "floor 2 summit gate sealed before the kill")
	world._boss.take_hit(1000000, Vector3.FORWARD)
	await get_tree().process_frame
	_check(GameState.floors_cleared == 2, "Mirelord's death clears floor 2")
	_check(GameState.quest_done("floor_boss_2"), "floor_boss_2 quest completed")
	_check(world._gate_open and not world._floor_gate_ready(), "floor 2 gate opens but leads nowhere yet (no Floor 3)")

	# The floor travels with the save.
	_check(SaveSystem.save_game(2), "save on floor 2")
	GameState.reset()
	_check(GameState.floor == 1, "reset returns to floor 1")
	_check(SaveSystem.load_game(2), "load floor 2 save")
	_check(GameState.floor == 2 and GameState.floors_cleared == 2 and GameState.recipe_unlocked("shrine_rite"), "floor, clears and recipes restored")
	_check(GameState.title == "Warden of Talven" and GameState.visited.size() == 3 and GameState.quest_done("gravelmaw_bounty"), "title, visited waystones and the chain survive the save")
	DirAccess.remove_absolute(SaveSystem.slot_path(2))
	GameState.floor = 1
	_check(Net.get_realm() != null and Net.get_realm().claim("smoke_probe", 1, "local:tester", "item")["ok"] and Net.get_realm().release("smoke_probe", "local:tester"), "realm DB (P4) opens offline, grants and releases a claim; full suite: scenes/realm_test.tscn")

	await _test_market()
	await _test_farms_guilds()
	_test_farming_skill()
	await _test_labyrinth()
	await _test_boss()

	print("== Done: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


## P7 Hollowbrook market stalls (scripts/life/stalls.gd) on a throwaway realm
## with an injected clock, plus the offline path on GameState and the local realm.
func _test_market() -> void:
	print("== Market stalls (P7)")
	var S = preload("res://scripts/life/stalls.gd")
	const MDIR := "user://realm_test_market"
	var wipe := func():
		var d := DirAccess.open(MDIR)
		if d != null:
			for f in d.get_files():
				DirAccess.remove_absolute(MDIR + "/" + f)
	wipe.call()
	var rdb = Net.RealmDBScript.open("market", MDIR)
	var now := [1_800_000_000.0]
	rdb.clock = func() -> float: return now[0]
	var keep := func(_r) -> bool: return true
	var seller := Net._new_record(Net.sanitize_character({"name": "Mara"}), "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", {})
	var buyer := Net._new_record(Net.sanitize_character({"name": "Bram"}), "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", {})
	var poor := Net._new_record(Net.sanitize_character({"name": "Cato"}), "cccccccccccccccccccccccccccccccc", {})
	var srs = Net.RecordState.new(seller)
	var brs = Net.RecordState.new(buyer)
	var prs = Net.RecordState.new(poor)
	seller["money"] = 500
	buyer["money"] = 300
	poor["money"] = 50
	var r: Dictionary = S.run(rdb, prs, poor, 0, {"op": "rent"}, keep)
	_check(r.has("error") and poor["money"] == 50 and rdb.holders(S.claim_id(0)).is_empty(), "renting refused without the week's Col")
	r = S.run(rdb, srs, seller, 0, {"op": "rent", "type": "shop"}, keep)
	_check(not r.has("error") and seller["money"] == 500 - S.RENT and rdb.is_holder(S.claim_id(0), S.holder_of(seller)) and r["view"]["mine"], "rent a stall: %d Col paid up front, realm claim held" % S.RENT)
	_check(int(rdb.container(S.SINK).get("col", 0)) == S.RENT and float(S.meta_of(rdb, 0)["rent_until"]) == now[0] + S.RENT_SECS, "rent goes to the market sink; rent runs one week")
	_check(S.run(rdb, srs, seller, 1, {"op": "rent"}, keep).has("error") and not rdb.is_holder(S.claim_id(1), S.holder_of(seller)), "a second stall for the same character is refused")
	_check(S.run(rdb, brs, buyer, 0, {"op": "rent"}, keep).has("error") and buyer["money"] == 300, "someone else's stall cannot be rented")
	var sword := {"id": "mk_sword", "name": "Iron Sword", "kind": "weapon", "rank": 1, "atk": 10, "def": 0}
	var bound := {"id": "mk_bound", "name": "Ember Fang", "kind": "weapon", "rank": 3, "atk": 30, "def": 0, "bound": true}
	seller["inventory"].append(sword)
	seller["inventory"].append(bound)
	srs.add_material("grilled_trout", 3)
	r = S.run(rdb, srs, seller, 0, {"op": "stock", "item": "mk_sword", "price": 200}, keep)
	_check(not r.has("error") and S._find(seller["inventory"], "mk_sword") < 0 and r["view"]["listings"].size() == 1 and int(r["view"]["listings"][0]["price"]) == 200, "stock gear: record -> stall at 200 Col")
	r = S.run(rdb, srs, seller, 0, {"op": "stock", "item": "mk_bound", "price": 50}, keep)
	_check(r.has("error") and S._find(seller["inventory"], "mk_bound") >= 0, "a bound item is refused and stays on the record")
	r = S.run(rdb, srs, seller, 0, {"op": "stock", "mat": "grilled_trout", "count": 5, "price": 60}, keep)
	_check(r.has("error") and seller["materials"]["grilled_trout"] == 3, "stocking more dishes than carried is refused")
	r = S.run(rdb, srs, seller, 0, {"op": "stock", "mat": "grilled_trout", "count": 2, "price": 60}, keep)
	var stack_id := str(r.get("item", ""))
	_check(not r.has("error") and seller["materials"]["grilled_trout"] == 1 and stack_id.begins_with("stk_") and S._find(seller["inventory"], stack_id) < 0, "stock a stack of 2 dishes (materials -> stall stack)")
	r = S.run(rdb, prs, poor, 0, {"op": "buy", "item": "mk_sword", "price": 200}, keep)
	_check(r.has("error") and poor["money"] == 50 and S._find(rdb.container(S.stock_id(0))["items"], "mk_sword") >= 0, "buying without enough Col is refused; the ware stays")
	_check(S.run(rdb, brs, buyer, 0, {"op": "buy", "item": "mk_sword", "price": 150}, keep).has("error") and buyer["money"] == 300, "a stale price is refused")
	_check(S.run(rdb, srs, seller, 0, {"op": "buy", "item": "mk_sword"}, keep).has("error"), "the owner cannot buy from their own stall")
	var till := S.till_id(S.holder_of(seller))
	r = S.run(rdb, brs, buyer, 0, {"op": "buy", "item": "mk_sword", "price": 200}, keep)
	_check(not r.has("error") and buyer["money"] == 100 and S._find(buyer["inventory"], "mk_sword") >= 0 and int(r["tax"]) == 10, "buy: buyer pays 200, gets the sword")
	_check(int(rdb.container(till)["col"]) == 190 and int(rdb.container(S.SINK)["col"]) == S.RENT + 10, "till gets 190, 5% tax (10 Col) leaves through the market sink")
	r = S.run(rdb, brs, buyer, 0, {"op": "buy", "item": stack_id, "price": 60}, keep)
	_check(not r.has("error") and buyer["money"] == 40 and int(buyer["materials"].get("grilled_trout", 0)) == 2 and S._find(buyer["inventory"], stack_id) < 0 and r.get("dish", false), "buy a dish stack: it unpacks into the buyer's provisions")
	_check(int(rdb.container(till)["col"]) == 190 + 57 and rdb.pending_count() == 0, "dish sale pays the till minus tax; every escrow settled")
	var helm := {"id": "mk_helm", "name": "Hide Vest", "kind": "armor", "rank": 0, "atk": 0, "def": 4}
	seller["inventory"].append(helm)
	S.run(rdb, srs, seller, 0, {"op": "stock", "item": "mk_helm", "price": 80}, keep)
	r = S.run(rdb, srs, seller, 0, {"op": "price", "item": "mk_helm", "price": 95}, keep)
	_check(not r.has("error") and int(r["view"]["listings"][0]["price"]) == 95, "owner changes a price")
	_check(S.run(rdb, brs, buyer, 0, {"op": "price", "item": "mk_helm", "price": 1}, keep).has("error"), "a stranger cannot change prices")
	_check(S.run(rdb, srs, seller, 0, {"op": "type", "type": "restaurant"}, keep).has("error"), "restaurant refused while gear is listed")
	r = S.run(rdb, srs, seller, 0, {"op": "withdraw", "item": "mk_helm"}, keep)
	_check(not r.has("error") and S._find(seller["inventory"], "mk_helm") >= 0 and r["view"]["listings"].is_empty(), "withdraw an unsold item back to the pack")
	r = S.run(rdb, srs, seller, 0, {"op": "type", "type": "restaurant"}, keep)
	_check(not r.has("error") and r["view"]["type"] == "restaurant" and S.sign_state(rdb)[0]["owner"] == "Mara", "the stall becomes a restaurant; the sign names the owner")
	_check(S.run(rdb, srs, seller, 0, {"op": "stock", "item": "mk_helm", "price": 80}, keep).has("error"), "a restaurant refuses gear")
	_check(S.run(rdb, srs, seller, 0, {"op": "stock", "mat": "iron_ore", "count": 1, "price": 5}, keep).has("error"), "a restaurant refuses raw goods")
	srs.add_material("boar_stew", 2)
	r = S.run(rdb, srs, seller, 0, {"op": "stock", "mat": "boar_stew", "count": 2, "price": 90}, keep)
	_check(not r.has("error") and r["view"]["listings"].size() == 1 and seller["materials"]["boar_stew"] == 0, "a restaurant lists cooked dishes")
	var m0: int = seller["money"]
	r = S.run(rdb, srs, seller, 0, {"op": "collect"}, keep)
	_check(not r.has("error") and seller["money"] == m0 + 247 and int(rdb.container(till)["col"]) == 0, "collect the till (247 Col -> record)")
	_check(S.run(rdb, srs, seller, 0, {"op": "collect"}, keep).has("error"), "an empty till is refused")
	now[0] += S.RENT_SECS + 3600.0
	var freed: Array = S.sweep(rdb)
	_check(freed == [0] and not rdb.is_holder(S.claim_id(0), S.holder_of(seller)) and S.sign_state(rdb)[0]["owner"] == "" and rdb.container(S.stock_id(0))["items"].is_empty(), "rent expiry frees the stall")
	_check(rdb.container(till)["items"].size() == 1, "unsold dishes return to the owner's till, not lost")
	r = S.run(rdb, srs, seller, 3, {"op": "collect"}, keep)
	_check(not r.has("error") and seller["materials"]["boar_stew"] == 2 and rdb.container(till)["items"].is_empty(), "collecting the till returns the dishes as provisions")
	_check(not S.run(rdb, srs, seller, 1, {"op": "rent"}, keep).has("error"), "after expiry the owner may rent another stall")
	var crash := {"inventory": [S.make_stack("wild_herb", 3)], "materials": {}}
	_check(S.unpack_stacks(crash) and crash["inventory"].is_empty() and crash["materials"]["wild_herb"] == 3, "a stack left on a record by a crash unpacks on load")
	rdb.close()
	wipe.call()
	# Offline: the same core through GameState on the local realm.
	S.autosave_offline = false
	var lr = Net.get_realm()
	var real_clock: Callable = lr.clock
	var lnow := [Time.get_unix_time_from_system()]
	lr.clock = func() -> float: return lnow[0]
	S.sweep(lr)
	GameState.money = 1000
	var lsword := {"id": "mk_local", "name": "Local Blade", "kind": "weapon", "rank": 0, "atk": 6, "def": 0}
	GameState.inventory.append(lsword)
	var local_stall := -1
	for i in S.COUNT:
		if S.stall_of(lr, Net.local_holder()) < 0 and str(lr.container(S.stock_id(i)).get("owner", "")) == "":
			local_stall = i
			break
	r = S.run_local(local_stall, {"op": "rent"})
	_check(not r.has("error") and GameState.money == 1000 - S.RENT, "offline: rent on the local realm through GameState")
	r = S.run_local(local_stall, {"op": "stock", "item": "mk_local", "price": 40})
	_check(not r.has("error") and S._find(GameState.inventory, "mk_local") < 0, "offline: stock from GameState's pack")
	lnow[0] += S.RENT_SECS + 60.0
	S.sweep(lr)
	r = S.run_local(local_stall, {"op": "collect"})
	_check(not r.has("error") and S._find(GameState.inventory, "mk_local") >= 0 and S.stall_of(lr, Net.local_holder()) < 0, "offline: rent expiry returns the blade via the till")
	lr.clock = real_clock
	S.autosave_offline = true
	_check(Net._srv_action(4242, "stall", {"op": "view", "stall": 0}).has("error"), "a stall request on a floor without a market is refused")
	# Floor 1 world: the market's server path (range checks) and the screen.
	for c in get_children():
		if c.has_method("srv_action"):
			c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.floor = 1
	GameState.has_position = false
	var w: Node3D = load("res://scenes/world.tscn").instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(w._stalls != null and w._stalls.stalls.size() == S.COUNT, "six stalls stand in the Hollowbrook market")
	var lay: Array = S.layout(w.HOLLOWBROOK)
	var min_gap := 99.0
	for d in lay:
		min_gap = minf(min_gap, (d["pos"] as Vector3).distance_to(w.HOLLOWBROOK))
		min_gap = minf(min_gap, (d["pos"] as Vector3).distance_to(PlayerHome.HOME_POS))
	_check(min_gap > 14.0, "stalls keep clear of the well and the cottage (%.1f m)" % min_gap)
	var mrec := Net._new_record(Net.sanitize_character({"name": "Vendra"}), "dddddddddddddddddddddddddddddddd", {})
	mrec["money"] = 400
	var mrs = Net.RecordState.new(mrec)
	var free_i := -1
	for i in S.COUNT:
		if str(lr.container(S.stock_id(i)).get("owner", "")) == "":
			free_i = i
			break
	_check(w.srv_action(4747, mrs, "stall", {"op": "rent", "stall": free_i}, Vector3(80, 0, -80)).has("error") and mrec["money"] == 400, "server refuses a stall action from across the island")
	r = w.srv_action(4747, mrs, "stall", {"op": "rent", "stall": free_i}, lay[free_i]["front"])
	_check(not r.has("error") and mrec["money"] == 400 - S.RENT and str(w._stalls.signs[free_i]["owner"]) == "Vendra", "server rents at the stall front; the sign shows the renter")
	_check(w.srv_action(4747, mrs, "stall_signs", {}, Vector3(80, 0, -80)).get("signs", []).size() == S.COUNT, "sign poll answers from anywhere")
	w.player.global_position = lay[free_i]["front"]
	var near: Array = w._nearest_interactable()
	_check(near[0] is Dictionary and int(near[0].get("stall", -1)) == free_i and "Vendra" in str(near[1]), "interact prompt at a rented stall (%s)" % str(near[1]))
	w._stalls.open(free_i, w.hud)
	_check(w.hud.life.stall_open() and w.hud.any_menu_open() and not w._stalls.screen.view.is_empty() and w._stalls.screen.view["owner"] == "Vendra", "stall screen opens on interact with the stall's view")
	w._stalls.screen._set_tab("manage")
	w.hud.close_screens()
	_check(not w.hud.life.stall_open(), "close_screens hides the stall screen")
	lnow[0] = Time.get_unix_time_from_system() + S.RENT_SECS * 5
	lr.clock = func() -> float: return lnow[0]
	S.sweep(lr)
	lr.clock = real_clock
	_check(str(lr.container(S.stock_id(free_i)).get("owner", "")) == "", "test stall released again")


## P8 farm plots (scripts/life/farms.gd) and guilds (scripts/life/guilds.gd)
## on a throwaway realm with an injected clock, then the offline path and the
## Floor 1 world (range checks, layout, prompts, screens, chat command).
func _test_farms_guilds() -> void:
	print("== Farm plots and guilds (P8)")
	var F = preload("res://scripts/life/farms.gd")
	var G = preload("res://scripts/life/guilds.gd")
	const FDIR := "user://realm_test_farms"
	var wipe := func():
		var d := DirAccess.open(FDIR)
		if d != null:
			for f in d.get_files():
				DirAccess.remove_absolute(FDIR + "/" + f)
	wipe.call()
	var rdb = Net.RealmDBScript.open("farms", FDIR)
	var now := [1_800_000_000.0]
	rdb.clock = func() -> float: return now[0]
	var keep := func(_r) -> bool: return true
	var mk := func(n: String, ch: String) -> Dictionary:
		return Net._new_record(Net.sanitize_character({"name": n}), ch.repeat(32), {})
	var ann = mk.call("Anna", "a")
	var ben = mk.call("Benno", "b")
	var cid = mk.call("Cid", "c")
	var dot = mk.call("Dora", "d")
	var ars = Net.RecordState.new(ann)
	var brs = Net.RecordState.new(ben)
	var crs = Net.RecordState.new(cid)
	var drs = Net.RecordState.new(dot)
	ann["money"] = 300
	ben["money"] = 30
	# --- Farms -----------------------------------------------------------------
	var r: Dictionary = F.run(rdb, brs, ben, 0, {"op": "rent"}, keep)
	_check(r.has("error") and ben["money"] == 30 and rdb.holders(F.claim_id(0)).is_empty(), "farm: renting refused without the week's Col")
	r = F.run(rdb, ars, ann, 2, {"op": "rent"}, keep)
	var ah: String = Net.RealmDBScript.holder_of_record(ann)
	_check(not r.has("error") and ann["money"] == 300 - F.RENT and rdb.is_holder(F.claim_id(2), ah) and r["view"]["mine"] and r["view"]["beds"].size() == F.BEDS,
		"farm: rent plot 3 for %d Col: realm claim, four beds" % F.RENT)
	_check(int(rdb.container(F.SINK).get("col", 0)) == F.RENT and rdb.pending_count() == 0, "farm: rent goes to the field sink through the escrow")
	_check(F.run(rdb, ars, ann, 5, {"op": "rent"}, keep).has("error") and not rdb.is_holder(F.claim_id(5), ah), "farm: one plot per character")
	ben["money"] = 300
	_check(F.run(rdb, brs, ben, 2, {"op": "rent"}, keep).has("error") and ben["money"] == 300, "farm: someone else's plot cannot be rented")
	_check(F.run(rdb, brs, ben, 2, {"op": "plant", "bed": 0, "crop": "turnip"}, keep).has("error"), "farm: a stranger cannot plant on your plot")
	_check(F.run(rdb, ars, ann, 2, {"op": "plant", "bed": 0, "crop": "turnip"}, keep).has("error"), "farm: planting without seeds is refused")
	var m0: int = ann["money"]
	r = F.run(rdb, ars, ann, -1, {"op": "seeds", "crop": "turnip", "count": 3}, keep)
	var tprice: int = LifeData.CROPS["turnip"]["seed_price"]
	_check(not r.has("error") and ann["money"] == m0 - 3 * tprice and int(ann["materials"].get("turnip_seeds", 0)) == 3, "farm: buy 3 turnip seeds at the cart (%d Col)" % (3 * tprice))
	_check(F.run(rdb, ars, ann, -1, {"op": "seeds", "crop": "turnip", "count": 999}, keep).has("error"), "farm: absurd seed orders refused")
	_check(F.run(rdb, ars, ann, -1, {"op": "plant", "bed": 0, "crop": "turnip"}, keep).has("error"), "farm: the cart cannot plant")
	r = F.run(rdb, ars, ann, 2, {"op": "plant", "bed": 0, "crop": "turnip"}, keep)
	_check(not r.has("error") and int(ann["materials"]["turnip_seeds"]) == 2 and r["view"]["beds"][0]["stage"] == "seeded" and r["view"]["beds"][0]["dry"], "farm: sow a turnip (seed spent, dry soil)")
	_check(F.run(rdb, ars, ann, 2, {"op": "plant", "bed": 0, "crop": "turnip"}, keep).has("error"), "farm: a sown bed refuses a second seed")
	var td: Dictionary = LifeData.CROPS["turnip"]
	now[0] += 300.0
	_check(F.bed_state(F.meta_of(rdb, 2)["beds"][0], now[0])["progress"] == 0.0, "farm: dry seed does not grow")
	r = F.run(rdb, ars, ann, 2, {"op": "water", "bed": 0}, keep)
	_check(not r.has("error") and int(r["watered"]) == 1 and not r["view"]["beds"][0]["dry"], "farm: watering wets the bed")
	now[0] += float(td["dry"]) * 0.5
	var st: Dictionary = F.bed_state(F.meta_of(rdb, 2)["beds"][0], now[0])
	_check(absf(float(st["progress"]) - float(td["dry"]) * 0.5 / float(td["grow"])) < 0.001 and st["stage"] in ["sprout", "growing"], "farm: growth follows the injected clock (%.2f)" % float(st["progress"]))
	now[0] += float(td["dry"]) * 2.0
	var st2: Dictionary = F.bed_state(F.meta_of(rdb, 2)["beds"][0], now[0])
	_check(st2["dry"] and absf(float(st2["progress"]) - float(td["dry"]) / float(td["grow"])) < 0.001, "farm: growth pauses once the soil dries")
	_check(F.run(rdb, ars, ann, 2, {"op": "harvest", "bed": 0}, keep).has("error"), "farm: an unripe bed cannot be harvested")
	# Keep it watered until ripe.
	var guard := 0
	while F.bed_state(F.meta_of(rdb, 2)["beds"][0], now[0])["stage"] != "ripe" and guard < 20:
		guard += 1
		F.run(rdb, ars, ann, 2, {"op": "water", "bed": 0}, keep)
		now[0] += float(td["dry"]) - 1.0
	_check(F.bed_state(F.meta_of(rdb, 2)["beds"][0], now[0])["stage"] == "ripe", "farm: a watered turnip ripens (%d waterings)" % guard)
	now[0] += float(td["wither"]) * 3.0
	_check(F.bed_state(F.meta_of(rdb, 2)["beds"][0], now[0])["stage"] == "ripe", "farm: a ripe crop waits for its farmer")
	r = F.run(rdb, ars, ann, 2, {"op": "harvest", "bed": 0}, keep)
	var got := int(ann["materials"].get("turnip", 0))
	_check(not r.has("error") and got >= int(td["yield"][0]) and got <= int(td["yield"][1]) and r["view"]["beds"][0]["stage"] == "empty", "farm: harvest %d turnips into provisions" % got)
	ars.add_material("wild_herb", 1)
	ars.add_material("turnip", 2)
	_check(LifeData.can_cook("turnip_soup", ars) and not LifeData.cook("turnip_soup", ars).has("error") and int(ann["materials"].get("turnip_soup", 0)) == 1, "farm: turnips cook into Turnip Soup")
	# Wither: sow, water once, walk away.
	F.run(rdb, ars, ann, 2, {"op": "plant", "bed": 1, "crop": "turnip"}, keep)
	F.run(rdb, ars, ann, 2, {"op": "water", "bed": 1}, keep)
	now[0] += float(td["wither"]) + 10.0
	_check(F.bed_state(F.meta_of(rdb, 2)["beds"][1], now[0])["stage"] == "withered", "farm: an unwatered crop withers")
	_check(F.run(rdb, ars, ann, 2, {"op": "water", "bed": 1}, keep).has("error") and F.run(rdb, ars, ann, 2, {"op": "harvest", "bed": 1}, keep).has("error"), "farm: a withered bed cannot be watered or harvested")
	r = F.run(rdb, ars, ann, 2, {"op": "clear", "bed": 1}, keep)
	_check(not r.has("error") and r["was"] == "withered" and r["view"]["beds"][1]["stage"] == "empty", "farm: clear a withered bed")
	_check(F.sign_state(rdb)[2]["owner"] == "Anna" and F.sign_state(rdb)[0]["owner"] == "", "farm: plot signs name the renter")
	# Persistence: reopen the realm from disk.
	F.run(rdb, ars, ann, 2, {"op": "plant", "bed": 3, "crop": "turnip"}, keep)
	rdb.close()
	rdb = Net.RealmDBScript.open("farms", FDIR)
	rdb.clock = func() -> float: return now[0]
	_check(str(F.meta_of(rdb, 2)["beds"][3]["crop"]) == "turnip" and rdb.is_holder(F.claim_id(2), ah), "farm: plot and beds survive a realm reload")
	now[0] += F.RENT_SECS * 5.0
	_check(F.sweep(rdb) == [2] and F.plot_of(rdb, ah) < 0 and str(F.meta_of(rdb, 2)["beds"][3]["crop"]) == "", "farm: rent expiry frees the plot and turns the beds over")
	_check(not F.run(rdb, ars, ann, 6, {"op": "rent"}, keep).has("error") and F.plot_of(rdb, ah) == 6, "farm: after expiry another plot can be rented")
	# --- Guilds ----------------------------------------------------------------
	var board := {"at_board": true, "online": func(_h): return true}
	ann["money"] = 5000
	ann["level"] = 9
	r = G.run(rdb, ars, ann, {"op": "found", "name": "Lantern Wardens", "tag": "LW"}, keep, board)
	_check(r.has("error") and ann["money"] == 5000 and G.guild_of(rdb, ah) == "", "guild: founding refused below Lv %d" % G.MIN_LEVEL)
	ann["level"] = 12
	_check(G.run(rdb, ars, ann, {"op": "found", "name": "Lantern Wardens", "tag": "LW"}, keep, {"at_board": false}).has("error"), "guild: founding needs the notice board")
	_check(G.run(rdb, ars, ann, {"op": "found", "name": "Lo", "tag": "LW"}, keep, board).has("error"), "guild: a 2-letter name is refused")
	_check(G.run(rdb, ars, ann, {"op": "found", "name": "Lantern Wardens", "tag": "L"}, keep, board).has("error"), "guild: a 1-letter tag is refused")
	r = G.run(rdb, ars, ann, {"op": "found", "name": "  Lantern [b]Wardens ", "tag": "lw1"}, keep, board)
	var gid: String = G.guild_of(rdb, ah)
	_check(not r.has("error") and gid != "" and ann["money"] == 5000 - G.FEE and G.get_guild(rdb, gid)["name"] == "Lantern bWardens" and G.get_guild(rdb, gid)["tag"] == "LW",
		"guild: founded for %d Col; name and tag sanitized (%s [%s])" % [G.FEE, str(G.get_guild(rdb, gid).get("name", "")), str(G.get_guild(rdb, gid).get("tag", ""))])
	_check(G.rank_of(rdb, ah) == "leader" and r["view"]["in_guild"] and r["view"]["my_rank"] == "leader", "guild: the founder leads")
	_check(G.run(rdb, ars, ann, {"op": "found", "name": "Second Guild", "tag": "SG"}, keep, board).has("error"), "guild: one guild per character (founder)")
	ben["money"] = 2000
	ben["level"] = 15
	_check(G.run(rdb, brs, ben, {"op": "found", "name": "lantern bwardens", "tag": "ZZ"}, keep, board).has("error"), "guild: names are unique (case-insensitive)")
	_check(G.run(rdb, brs, ben, {"op": "found", "name": "Night Owls", "tag": "LW"}, keep, board).has("error") and ben["money"] == 2000, "guild: tags are unique")
	var bh: String = Net.RealmDBScript.holder_of_record(ben)
	var ch: String = Net.RealmDBScript.holder_of_record(cid)
	var dh: String = Net.RealmDBScript.holder_of_record(dot)
	_check(G.run(rdb, ars, ann, {"op": "invite"}, keep, {"target": {"holder": "", "name": "Ghost"}}).has("error"), "guild: inviting someone offline is refused")
	r = G.run(rdb, ars, ann, {"op": "invite"}, keep, {"target": {"holder": bh, "name": "Benno"}})
	_check(not r.has("error") and G.invites.has(bh), "guild: the leader invites Benno")
	_check(G.run(rdb, crs, cid, {"op": "accept"}, keep).has("error") and G.guild_of(rdb, ch) == "", "guild: accepting without an invitation is refused")
	r = G.run(rdb, brs, ben, {"op": "view"}, keep)
	_check(r["view"]["invite"].get("guild", "") == "Lantern bWardens", "guild: the invitee sees the invitation")
	r = G.run(rdb, brs, ben, {"op": "accept"}, keep)
	_check(not r.has("error") and G.guild_of(rdb, bh) == gid and G.rank_of(rdb, bh) == "member" and r["notify"][0]["holders"].has(ah), "guild: Benno accepts and joins as Member")
	_check(G.run(rdb, brs, ben, {"op": "found", "name": "Night Owls", "tag": "NO"}, keep, board).has("error"), "guild: one guild per character (member)")
	_check(G.run(rdb, brs, ben, {"op": "invite"}, keep, {"target": {"holder": ch, "name": "Cid"}}).has("error"), "guild: a Member cannot invite")
	_check(G.run(rdb, brs, ben, {"op": "promote", "name": "Anna"}, keep).has("error"), "guild: a Member cannot promote")
	G.run(rdb, ars, ann, {"op": "invite"}, keep, {"target": {"holder": ch, "name": "Cid"}})
	G.run(rdb, crs, cid, {"op": "accept"}, keep)
	_check(G.run(rdb, brs, ben, {"op": "kick", "name": "Cid"}, keep).has("error") and G.guild_of(rdb, ch) == gid, "guild: a Member cannot remove anyone")
	r = G.run(rdb, ars, ann, {"op": "promote", "name": "benno"}, keep)
	_check(not r.has("error") and G.rank_of(rdb, bh) == "officer", "guild: the Leader promotes Benno to Officer")
	_check(G.run(rdb, brs, ben, {"op": "kick", "name": "Anna"}, keep).has("error") and G.rank_of(rdb, ah) == "leader", "guild: an Officer cannot remove the Leader")
	_check(G.run(rdb, brs, ben, {"op": "demote", "name": "Cid"}, keep).has("error"), "guild: only the Leader demotes")
	r = G.run(rdb, brs, ben, {"op": "invite"}, keep, {"target": {"holder": dh, "name": "Dora"}})
	_check(not r.has("error"), "guild: an Officer may invite")
	now[0] += G.INVITE_SECS + 5.0
	_check(G.run(rdb, drs, dot, {"op": "accept"}, keep).has("error") and G.guild_of(rdb, dh) == "", "guild: invitations expire")
	r = G.run(rdb, brs, ben, {"op": "kick", "name": "Cid"}, keep)
	_check(not r.has("error") and G.guild_of(rdb, ch) == "" and r["notify"][0]["holders"].has(ch), "guild: an Officer removes a Member (who is told)")
	# Storage.
	var sid: String = G.storage_id(gid)
	var gsword := {"id": "gd_sword", "name": "Guild Blade", "kind": "weapon", "rank": 1, "atk": 9, "def": 0}
	var gbound := {"id": "gd_bound", "name": "Oathbound", "kind": "weapon", "rank": 3, "atk": 30, "def": 0, "bound": true}
	ann["inventory"].append(gsword)
	ann["inventory"].append(gbound)
	ars.add_material("sunwheat", 6)
	_check(G.run(rdb, ars, ann, {"op": "deposit", "item": "gd_sword"}, keep, {"at_board": false}).has("error"), "guild: storage only at the notice board")
	r = G.run(rdb, ars, ann, {"op": "deposit", "item": "gd_sword"}, keep, board)
	_check(not r.has("error") and Stalls_find(ann["inventory"], "gd_sword") < 0 and r["view"]["storage"]["items"].size() == 1, "guild: deposit a sword (record -> guild storage)")
	r = G.run(rdb, ars, ann, {"op": "deposit", "item": "gd_bound"}, keep, board)
	_check(r.has("error") and Stalls_find(ann["inventory"], "gd_bound") >= 0, "guild: a bound item is refused and stays")
	r = G.run(rdb, ars, ann, {"op": "deposit", "mat": "sunwheat", "count": 4}, keep, board)
	_check(not r.has("error") and int(ann["materials"]["sunwheat"]) == 2 and rdb.container(sid)["items"].size() == 2, "guild: deposit 4 sunwheat as a stack")
	var bm: int = ben["money"]
	r = G.run(rdb, brs, ben, {"op": "deposit", "col": 150}, keep, board)
	_check(not r.has("error") and ben["money"] == bm - 150 and int(rdb.container(sid)["col"]) == 150, "guild: an Officer deposits 150 Col")
	_check(G.run(rdb, brs, ben, {"op": "deposit", "col": 999999}, keep, board).has("error"), "guild: depositing more Col than carried is refused")
	G.run(rdb, ars, ann, {"op": "invite"}, keep, {"target": {"holder": dh, "name": "Dora"}})
	G.run(rdb, drs, dot, {"op": "accept"}, keep)
	dot["money"] = 40
	r = G.run(rdb, drs, dot, {"op": "deposit", "col": 40}, keep, board)
	_check(not r.has("error") and dot["money"] == 0 and int(rdb.container(sid)["col"]) == 190, "guild: a Member deposits too")
	_check(G.run(rdb, drs, dot, {"op": "withdraw", "item": "gd_sword"}, keep, board).has("error") and G.run(rdb, drs, dot, {"op": "withdraw", "col": 10}, keep, board).has("error") and dot["money"] == 0,
		"guild: a Member cannot take from storage")
	var stack_id := ""
	for it in rdb.container(sid)["items"]:
		if str(it.get("kind", "")) == "stack":
			stack_id = str(it["id"])
	r = G.run(rdb, brs, ben, {"op": "withdraw", "item": stack_id}, keep, board)
	_check(not r.has("error") and int(ben["materials"].get("sunwheat", 0)) == 4 and Stalls_find(ben["inventory"], stack_id) < 0, "guild: an Officer takes the sunwheat (unpacked into materials)")
	bm = ben["money"]
	r = G.run(rdb, brs, ben, {"op": "withdraw", "col": 90}, keep, board)
	_check(not r.has("error") and ben["money"] == bm + 90 and int(rdb.container(sid)["col"]) == 100 and rdb.pending_count() == 0, "guild: an Officer takes 90 Col; escrow settled")
	_check(G.run(rdb, ars, ann, {"op": "disband"}, keep).has("error") and G.guild_of(rdb, ah) == gid, "guild: disband refused while the storage holds goods")
	_check(G.run(rdb, brs, ben, {"op": "disband"}, keep).has("error"), "guild: only the Leader disbands")
	# Leaving and leadership.
	r = G.run(rdb, drs, dot, {"op": "leave"}, keep)
	_check(not r.has("error") and G.guild_of(rdb, dh) == "", "guild: a Member leaves")
	r = G.run(rdb, ars, ann, {"op": "leave"}, keep)
	_check(not r.has("error") and G.guild_of(rdb, ah) == "" and G.rank_of(rdb, bh) == "leader", "guild: the Leader leaves; the Officer inherits the guild")
	# Reload: membership is durable realm data.
	rdb.close()
	rdb = Net.RealmDBScript.open("farms", FDIR)
	rdb.clock = func() -> float: return now[0]
	_check(G.guild_of(rdb, bh) == gid and G.rank_of(rdb, bh) == "leader" and G.get_guild(rdb, gid)["members"].size() == 1, "guild: membership survives a realm reload (journal op)")
	G.run(rdb, brs, ben, {"op": "withdraw", "item": "gd_sword"}, keep, board)
	G.run(rdb, brs, ben, {"op": "withdraw", "col": 100}, keep, board)
	r = G.run(rdb, brs, ben, {"op": "leave"}, keep)
	_check(not r.has("error") and G.guild_of(rdb, bh) == "" and G.get_guild(rdb, gid).is_empty() and rdb.container(sid).is_empty(), "guild: the last member's leave disbands an emptied guild")
	r = G.run(rdb, crs, cid, {"op": "found", "name": "Lantern bWardens", "tag": "LW"}, keep, board)
	_check(r.has("error"), "guild: Cid (Lv 1) still cannot found")
	cid["level"] = 10
	cid["money"] = 1000
	r = G.run(rdb, crs, cid, {"op": "found", "name": "Lantern bWardens", "tag": "LW"}, keep, board)
	_check(not r.has("error") and cid["money"] == 0, "guild: a disbanded name and tag are free again")
	var gid2: String = G.guild_of(rdb, ch)
	r = G.run(rdb, crs, cid, {"op": "disband"}, keep)
	_check(not r.has("error") and G.get_guild(rdb, gid2).is_empty(), "guild: the Leader disbands an empty guild")
	_check(G.clean_tag("a-b c") == "ABC" and G.name_error(G.clean_name("  ")) != "" and G.name_error("Twenty One Characters") != "", "guild: tag/name sanitizers")
	rdb.close()
	wipe.call()
	G.invites.clear()
	# --- Offline: the same cores on GameState and the local realm ---------------
	F.autosave_offline = false
	G.autosave_offline = false
	var lr = Net.get_realm()
	var real_clock: Callable = lr.clock
	var lnow := [Time.get_unix_time_from_system()]
	lr.clock = func() -> float: return lnow[0]
	var lh := Net.local_holder()
	var free_plot := -1
	for i in F.COUNT:
		if F.plot_of(lr, lh) < 0 and str(lr.container(F.claim_id(i)).get("owner", "")) == "":
			free_plot = i
			break
	GameState.money = 2000
	r = F.run_local(free_plot, {"op": "rent"})
	_check(not r.has("error") and GameState.money == 2000 - F.RENT and F.plot_of(lr, lh) == free_plot, "offline: rent a plot on the local realm")
	r = F.run_local(-1, {"op": "seeds", "crop": "sunwheat", "count": 2})
	_check(not r.has("error") and GameState.money == 2000 - F.RENT - 2 * int(LifeData.CROPS["sunwheat"]["seed_price"]) and int(GameState.materials.get("sunwheat_seeds", 0)) >= 2, "offline: buy seeds; Col comes off GameState")
	r = F.run_local(free_plot, {"op": "plant", "bed": 2, "crop": "sunwheat"})
	F.run_local(free_plot, {"op": "water", "bed": -1})
	lnow[0] += float(LifeData.CROPS["sunwheat"]["grow"]) * 0.5
	F.run_local(free_plot, {"op": "water", "bed": -1})
	lnow[0] += float(LifeData.CROPS["sunwheat"]["dry"])
	var sw0 := int(GameState.materials.get("sunwheat", 0))
	r = F.run_local(free_plot, {"op": "harvest", "bed": -1})
	_check(not r.has("error") and int(GameState.materials.get("sunwheat", 0)) > sw0, "offline: grow and harvest sunwheat into GameState")
	var lvl0 := GameState.level
	GameState.level = 10
	GameState.money = 1500
	var gname := "Smoke Guild %d" % (randi() % 9000 + 1000)
	r = G.run_local({"op": "found", "name": gname, "tag": "SMK"}, true)
	if r.has("error") and "tag" in str(r["error"]):
		r = G.run_local({"op": "found", "name": gname, "tag": "SMQ"}, true)
	_check(not r.has("error") and GameState.money == 500 and G.guild_of(lr, lh) != "", "offline: found a guild at the board (%s)" % str(r.get("error", "ok")))
	_check(G.run_local({"op": "invite", "name": "Nobody"}, true).has("error"), "offline: nobody to invite")
	await get_tree().process_frame
	# --- Floor 1 world ---------------------------------------------------------
	var w: Node3D = null
	for c in get_children():
		if c.has_method("srv_action") and c.get("_farms") != null:
			w = c
	_check(w != null and w._farms.plots.size() == F.COUNT and w._guilds != null, "world: eight farm plots and the guild notice board on Floor 1")
	if w != null:
		var lay: Array = F.layout(w.HOLLOWBROOK)
		var clear := 99.0
		var grass := true
		var hb: Vector3 = w.HOLLOWBROOK
		var houses: Array = []
		for k in 5:
			var a := TAU * k / 5.0 + 0.35
			houses.append(hb + Vector3(cos(a), 0, sin(a)) * 10.5)
		var market: Vector3 = preload("res://scripts/life/stalls.gd").market_center(hb)
		var herbs: Array = w._herbs.positions if w._herbs else []
		for d in lay:
			var p: Vector3 = d["pos"]
			for q in houses + [PlayerHome.HOME_POS, market, Vector3(WorldArt.POND.x, 0, WorldArt.POND.y), hb]:
				clear = minf(clear, p.distance_to(q))
			for q in herbs:
				clear = minf(clear, p.distance_to(q) + 3.0)
			var gk := WorldArt.ground_kind(Vector2(p.x, p.z))
			grass = grass and (gk == WorldArt.Ground.GRASS or gk == WorldArt.Ground.DIRT)
		_check(clear > 6.0 and grass, "world: plots keep clear of houses, cottage, market, pond, herbs and roads (%.1f m)" % clear)
		var fp: Dictionary = lay[free_plot]
		w.player.global_position = fp["front"]
		var near: Array = w._nearest_interactable()
		_check(near[0] is Dictionary and int(near[0].get("plot", -9)) == free_plot, "world: interact prompt on your plot (%s)" % str(near[1]))
		w._farms.open(free_plot, w.hud)
		_check(w.hud.life.farm_open() and w.hud.any_menu_open() and bool(w._farms.screen.view.get("mine", false)), "world: farm screen opens on your plot")
		w.hud.close_screens()
		_check(not w.hud.life.farm_open(), "world: close_screens hides the farm screen")
		w.player.global_position = w._farms.cart_pos
		near = w._nearest_interactable()
		_check(near[0] is Dictionary and int(near[0].get("plot", -9)) == -1, "world: seed cart prompt")
		var frec := Net._new_record(Net.sanitize_character({"name": "Fenna"}), "e".repeat(32), {})
		frec["money"] = 200
		var frs = Net.RecordState.new(frec)
		var other: int = (free_plot + 1) % F.COUNT
		_check(w.srv_action(4848, frs, "farm", {"op": "rent", "plot": other}, Vector3(80, 0, -80)).has("error") and frec["money"] == 200, "world: server refuses a plot action from across the island")
		r = w.srv_action(4848, frs, "farm", {"op": "rent", "plot": other}, lay[other]["front"])
		_check(not r.has("error") and str(w._farms.signs[other]["owner"]) == "Fenna", "world: server rents at the plot; the sign names the renter")
		_check(w.srv_action(4848, frs, "farm_signs", {}, Vector3(80, 0, -80)).get("signs", []).size() == F.COUNT, "world: farm sign poll answers from anywhere")
		var grec := Net._new_record(Net.sanitize_character({"name": "Galen"}), "f".repeat(32), {})
		grec["money"] = 3000
		grec["level"] = 20
		var grs = Net.RecordState.new(grec)
		_check(w.srv_action(4949, grs, "guild", {"op": "found", "name": "Far Away Guild", "tag": "FAR"}, Vector3(80, 0, -80)).has("error") and grec["money"] == 3000, "world: founding away from the board is refused")
		r = w.srv_action(4949, grs, "guild", {"op": "found", "name": "Board Side Guild", "tag": "BSG"}, w._guilds.board_pos)
		_check(not r.has("error") and grec["money"] == 3000 - G.FEE, "world: founding at the notice board")
		w.player.global_position = w._guilds.board_front()
		near = w._nearest_interactable()
		_check(near[0] is Dictionary and near[0].has("guild_board"), "world: notice board prompt (%s)" % str(near[1]))
		w._guilds.open(w.hud)
		_check(w.hud.life.guild_open() and bool(w._guilds.screen.view.get("in_guild", false)) and w._guilds.screen.view["guild"]["tag"] in ["SMK", "SMQ"], "world: guild panel shows your guild")
		w._guilds.screen._set_tab("storage")
		w._guilds.screen._set_tab("roster")
		w.hud.close_screens()
		_check(not w.hud.life.guild_open(), "world: close_screens hides the guild panel")
		w._guilds._tags_t = 0.0
		w._guilds._process(0.1)
		_check(Net.guild_label(str(GameState.character.get("name", ""))).ends_with("]"), "world: your guild tag joins your name label (%s)" % Net.guild_label(str(GameState.character.get("name", ""))))
		var sys: Array = []
		_check(G.chat_command("/g hello guild", w.hud, func(m): sys.append(m)) and sys.is_empty(), "chat: /g sends guild chat")
		_check(not G.chat_command("/p hi", w.hud, func(m): sys.append(m)), "chat: other commands pass through")
		w.hud.add_chat("Tester", "for the guild", "guild")
		_check("[Guild]" in w.hud._chat_log.text, "chat: guild channel line in the log")
		_check(G.chat_command("/guild", w.hud, func(m): sys.append(m)) and w.hud.life.guild_open(), "chat: /guild opens the panel")
		w.hud.close_screens()
		# Clean the world test's realm rows.
		G.run(Net.get_realm(), grs, grec, {"op": "disband"}, func(_r): return true)
		lnow[0] += F.RENT_SECS * 6.0
		F.sweep(lr)
	G.run_local({"op": "disband"}, true)
	_check(G.guild_of(lr, lh) == "" and F.plot_of(lr, lh) < 0, "offline: test guild disbanded and plot released")
	GameState.level = lvl0
	lr.clock = real_clock
	F.autosave_offline = true
	G.autosave_offline = true


func Stalls_find(items: Array, id: String) -> int:
	return preload("res://scripts/life/stalls.gd")._find(items, id)


## Floor 1 Guardian (scripts/boss_brain.gd): drives Gravelmaw's state machine
## offline on a fresh Floor 1 world: stacked HP bars and bar breaks, adds that
## come and go, the final-bar enrage, slam (never parried) versus charge and
## sweep (parried), the leash reset, and the Last Attack bonus on the kill.
func _test_farming_skill() -> void:
	print("== Farming skill")
	var F = load("res://scripts/life/farms.gd")
	_check(F.crop_xp("turnip") < F.crop_xp("sunwheat") and F.crop_xp("sunwheat") < F.crop_xp("honeymelon"), "longer crops teach more farming xp")
	_check(F.farm_bonus_chance(1) == 0.0 and F.farm_bonus_chance(11) > 0.3 and F.farm_bonus_chance(99) == 0.5, "bonus crop chance grows with level and caps at 50%")
	var lv0 := GameState.farming_level
	var xp0 := GameState.farming_xp
	GameState.farming_level = 1
	GameState.farming_xp = 0
	var up := GameState.add_life_xp("farming", GameState.life_xp_to_next(1))
	_check(up and GameState.farming_level == 2 and GameState.farming_xp == 0, "farming levels with xp")
	var d := GameState.to_dict()
	_check(int(d.get("farming_level", 0)) == 2, "farming level is saved")
	var rs = Net.RecordState.new(Net.record_defaults())
	_check(rs.add_life_xp("farming", 30) and int(rs.rec["farming_level"]) == 2, "server records level farming too")
	GameState.farming_level = lv0
	GameState.farming_xp = xp0


func _test_labyrinth() -> void:
	print("== Labyrinth chests and traps")
	GameState.floor = 1
	GameState.has_position = false
	GameState.heal_full()
	var world: Node3D = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var lab: Node3D = world._lab
	_check(lab != null and lab.chests.size() == 4 and lab.spikes.size() == 6, "terraces hold 4 chests and 6 spike tiles")
	if lab == null:
		world.queue_free()
		return
	var L = load("res://scripts/labyrinth_features.gd")
	var now := Time.get_unix_time_from_system()
	var keep_chests: Dictionary = GameState.chests.duplicate()
	var keys0 := int(GameState.materials.get(L.KEY, 0))
	GameState.chests = {}
	GameState.materials.erase(L.KEY)
	var col0 := GameState.money
	var r: Dictionary = L.open_chest(GameState, 0, now)
	_check(not r.has("error") and GameState.money > col0 and GameState.chests.has("t1_cache"), "a chest pays out and remembers the opening")
	_check(L.open_chest(GameState, 0, now + 5.0).has("error") and L.refill_left(GameState, 0, now + 5.0) > 0.0, "an opened chest is empty until it restocks")
	_check(L.refill_left(GameState, 0, now + float(L.CHESTS[0]["respawn"]) + 1.0) == 0.0, "the chest restocks after its timer")
	r = L.open_chest(GameState, 1, now)
	_check(r.has("error") and not GameState.chests.has("t1_vault"), "a vault stays shut without a Terrace Key")
	GameState.add_material(L.KEY, 1)
	r = L.open_chest(GameState, 1, now)
	_check(not r.has("error") and int(GameState.materials.get(L.KEY, 0)) == 0 and GameState.chests.has("t1_vault"), "a Terrace Key opens the vault and is used up")
	_check(GameState.to_dict().get("chests", {}).has("t1_vault"), "chest timers are saved")
	var rs = Net.RecordState.new(Net.record_defaults())
	r = L.open_chest(rs, 2, now)
	_check(not r.has("error") and (rs.rec["chests"] as Dictionary).has("t2_cache") and int(rs.rec["money"]) > 0, "the server rolls chest loot into the record")
	_check(lab.srv(1, rs, {"chest": 3}, Vector3(0, 0, 0)).has("error"), "the server refuses a chest opened from afar")
	_check(L.loot_text({"col": 5, "mats": {"iron_ore": 2}, "gear": {}}) == "5 Col, 2 Iron Ore", "loot line reads well")
	# Spike cycle: rest -> warn -> up.
	var tile: Dictionary = lab.spikes[0]
	var base_t: float = 1000.0 * float(L.PERIOD) - float(tile["phase"])
	_check(L.spike_state(tile, base_t + 0.1)[0] == "rest" and L.spike_state(tile, base_t + L.PERIOD - L.UP - 0.2)[0] == "warn" and L.spike_state(tile, base_t + L.PERIOD - 0.1)[0] == "up", "spike tiles cycle rest, warn, up")
	# Stand on a raised tile: hurt once per cycle.
	var pl: Player = world.player
	GameState.heal_full()
	pl.global_position = (tile["pos"] as Vector3) + Vector3(0, 0.5, 0)
	pl.velocity = Vector3.ZERO
	var phase0 := float(tile["phase"])
	tile["phase"] = L.PERIOD - L.UP * 0.5 - fmod(Time.get_unix_time_from_system(), L.PERIOD) + 0.05
	var hp0 := GameState.hp
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hp1 := GameState.hp
	await get_tree().physics_frame
	_check(hp1 < hp0 and GameState.hp >= hp1 - 0.01, "raised spikes hurt the player on the tile once per cycle")
	tile["phase"] = phase0
	pl.global_position = GameState.spawn_point()
	GameState.heal_full()
	GameState.chests = keep_chests
	if keys0 > 0:
		GameState.materials[L.KEY] = keys0
	world.queue_free()
	await get_tree().process_frame


func _test_boss() -> void:
	print("== Floor Guardian: Gravelmaw (BossBrain)")
	GameState.floor = 1
	GameState.has_position = false
	GameState.heal_full()
	var w: Node3D = load("res://scenes/world.tscn").instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	var pl: Player = w.player
	w._spawn_boss()
	var boss: Enemy = w._boss
	_check(boss != null and boss.brain is BossBrain and boss.get_node_or_null("BossBrain") == boss.brain, "Gravelmaw spawns with a BossBrain child")
	var b: BossBrain = boss.brain
	_check(b.bar_count() == 4 and b.current_bar() == 4 and is_equal_approx(b.bar_fraction(), 1.0) and b.phase == 1 and b.state_name() == "idle", "four full HP bars, phase 1, idle")
	var P0: Dictionary = BossBrain.PRESETS["gravelmaw"]["phases"][0]
	var P1: Dictionary = BossBrain.PRESETS["gravelmaw"]["phases"][1]
	var events: Array = []
	b.boss_event.connect(func(k, _d): events.append(k))
	# Engage: a player stands on the summit.
	pl.global_position = boss.global_position + Vector3(0, 0, 10)
	pl.velocity = Vector3.ZERO
	var ctl: Dictionary = b.tick(0.05, pl)
	_check(b.state == BossBrain.State.ENGAGE and events.has("engage") and ctl.has("target") and ctl.has("spd"), "a player on the summit wakes the Guardian (engage event, brain drives movement)")
	# Bar breaks fire on the hit that crosses the threshold.
	var bar_hp: float = b.bar_hp()
	var adds0: int = b.living_adds()
	boss.take_hit(bar_hp * 0.5, Vector3.FORWARD, 1)
	_check(b.current_bar() == 4 and b.living_adds() == adds0 and not events.has("bar_break"), "chipping inside a bar breaks nothing")
	boss.take_hit(bar_hp * 0.6, Vector3.FORWARD, 1)
	_check(b.current_bar() == 3 and events.has("bar_break") and b.state == BossBrain.State.BREAK and b.stagger_immune(), "crossing the threshold breaks the bar: event and a break beat")
	var n_adds: int = b.living_adds()
	_check(n_adds >= 2 and n_adds <= 3, "2-3 adds answer the bar break (%d)" % n_adds)
	var add_names := {}
	for a in b.adds:
		add_names[a.display_name] = true
	_check(add_names.has("Ruin Sentinel") and add_names.has("Kobold Scout"), "adds reuse the Floor 1 guard types (%s)" % ", ".join(add_names.keys()))
	b._timer = 0.0
	b.tick(0.05, pl)
	_check(b.state == BossBrain.State.ENGAGE and not b.stagger_immune(), "the break beat ends and the fight resumes")
	# Sweep: wide arc, parryable; parries build posture, three stagger.
	boss.rotation.y = PI  # faces +Z
	pl.global_position = boss.global_position + Vector3(0, 0, 3.0)
	pl.model.look_at(Vector3(boss.global_position.x, pl.model.global_position.y, boss.global_position.z))
	boss._posture = 0
	boss._stagger = 0.0
	b._slam_cd = 999.0
	pl._parry_ready_ms = 0
	pl.press_parry()
	b._begin("sweep", pl)
	_check(b.state == BossBrain.State.WINDUP and b.move == "sweep" and events[-1] == "telegraph" and is_equal_approx(b._timer, P0["windup"]["sweep"]), "sweep is telegraphed for the phase's wind-up")
	var hp0: float = GameState.hp
	var par0: int = pl.parries
	b._resolve()
	_check(GameState.hp == hp0 and boss._posture == 1 and pl.parries == par0 + 1 and b.state == BossBrain.State.RECOVER and events[-1] == "impact", "a timed parry deflects the sweep and builds posture")
	pl.release_parry()
	pl._parry_open_ms = -100000
	b._begin("sweep", pl)
	hp0 = GameState.hp
	b._resolve()
	_check(GameState.hp < hp0, "an unparried sweep lands")
	pl.global_position = boss.global_position + Vector3(0, 0, -3.0)  # behind the Guardian
	hp0 = GameState.hp
	b._begin("sweep", pl)
	b._resolve()
	_check(GameState.hp == hp0, "the sweep is an arc: standing behind it is safe")
	pl.global_position = boss.global_position + Vector3(0, 0, 3.0)
	boss._posture = 2
	pl._parry_ready_ms = 0
	pl.press_parry()
	b._begin("sweep", pl)
	b._resolve()
	_check(boss.is_staggered() and boss._posture == 0, "the third parry staggers the Guardian")
	pl.release_parry()
	boss._stagger = 1.0
	b._begin("sweep", pl)
	b.tick(0.05, pl)
	_check(b.state != BossBrain.State.WINDUP and b.move == "", "a stagger cancels the wind-up")
	boss._stagger = 0.0
	GameState.heal_full()
	# Slam: a ring; never parried (a guard only chips), stepping out dodges.
	pl._parry_ready_ms = 0
	pl.press_parry()
	hp0 = GameState.hp
	par0 = pl.parries
	b._begin("slam", pl)
	_check(b.move == "slam" and b._threatened.has(pl) and events[-1] == "telegraph", "slam telegraph marks the players inside the ring")
	b._resolve()
	_check(GameState.hp < hp0 and pl.parries == par0 and events[-1] == "impact" and b._slam_cd > 0.0, "the slam cannot be parried: inside the ring you take it")
	pl.release_parry()
	pl._parry_open_ms = -100000
	GameState.hidden_stats = {}
	b._begin("slam", pl)
	pl.global_position = boss.global_position + Vector3(0, 0, P0["slam_radius"] + 1.5)
	hp0 = GameState.hp
	b._resolve()
	_check(GameState.hp == hp0 and int(GameState.hidden_stats.get("dodges", 0)) == 1, "stepping out of the ring during the wind-up dodges the slam (reaction point)")
	# Charge: a line toward the target, parried as the body arrives.
	pl.global_position = boss.global_position + Vector3(0, 0, 10.0)
	b._cooldown = 0.0
	b._slam_cd = 999.0
	_check(b._choose(10.0) == "charge" and b._choose(3.0) == "sweep", "move choice: charge at range, sweep up close")
	b._begin("charge", pl)
	_check(b.move == "charge" and b._charge_end.distance_to(pl.global_position) < 4.0 and events[-1] == "telegraph", "charge aims a line at the target")
	b._resolve()
	_check(b.state == BossBrain.State.CHARGE and events[-1] == "charge", "wind-up over: the Guardian runs the line")
	ctl = b.tick(0.016, pl)
	_check(float(ctl["spd"]) == float(P0["charge_speed"]) and (ctl["target"] as Vector3).distance_to(b._charge_end) < 0.01, "the run moves at charge speed toward the line's end")
	boss.global_position = pl.global_position - Vector3(0, 0, 2.0)
	boss.rotation.y = PI
	pl.model.look_at(Vector3(boss.global_position.x, pl.model.global_position.y, boss.global_position.z))
	pl._parry_ready_ms = 0
	pl.press_parry()
	hp0 = GameState.hp
	par0 = pl.parries
	b._charge_tick()
	_check(GameState.hp == hp0 and pl.parries == par0 + 1, "the charge is parried the moment it arrives")
	b._charge_tick()
	_check(pl.parries == par0 + 1, "one charge strikes a player once")
	pl.release_parry()
	b._end_charge()
	_check(b.state == BossBrain.State.RECOVER and events[-1] == "impact", "the charge ends with an impact event")
	GameState.heal_full()
	# Final bar: the enrage roar (stagger-immune), then the second moveset.
	boss.hp = bar_hp * 1.05
	boss.take_hit(bar_hp * 0.1, Vector3.FORWARD, 1)
	_check(b.current_bar() == 1 and b.state == BossBrain.State.ENRAGE and events.has("enrage") and b.stagger_immune() and b.phase == 1, "breaking into the last bar starts the enrage roar (stagger-immune warning beat)")
	boss._posture = 0
	pl._parry_ready_ms = 0
	pl.press_parry()
	hp0 = GameState.hp
	var out: String = b._strike(pl, 10.0, true)
	_check(out == "parry" and GameState.hp == hp0 and boss._posture == 0 and not boss.is_staggered(), "a parry during the roar still deflects but builds no posture")
	pl.release_parry()
	b._timer = 0.0
	b.tick(0.05, pl)
	_check(b.phase == 2 and b.is_enraged() and events.has("phase") and b.state == BossBrain.State.ENGAGE, "the roar ends: phase 2")
	_check(float(b._ph()["windup"]["sweep"]) < float(P0["windup"]["sweep"]) and float(b._ph()["slam_radius"]) > float(P0["slam_radius"]) and float(b._ph()["charge_speed"]) > float(P0["charge_speed"]) and b._ph() == P1, "phase 2 moveset: faster wind-ups, wider slam, faster charge")
	# Arena hazard: from bar 2 down, stones fall on marked rings.
	b._hazards.clear()
	b._hazard_cd = 0.0
	b._cooldown = 99.0
	GameState.heal_full()
	pl.global_position = boss.global_position + Vector3(0, 0, 8)
	pl.velocity = Vector3.ZERO
	b.tick(0.01, pl)
	var on_me := false
	for h in b._hazards:
		if ((h["pos"] as Vector3) - pl.global_position).length() < 1.5:
			on_me = true
	_check(b.pending_hazards() == 3 and events.has("hazard") and on_me, "rockfall marks three stones, one on a fighter")
	hp0 = GameState.hp
	b.tick(1.5, pl)
	_check(GameState.hp < hp0 and b.pending_hazards() == 0 and events.has("hazard_land"), "a landing stone hurts the fighter under it")
	b._hazard_cd = 0.0
	b.tick(0.01, pl)
	_check(b.pending_hazards() == 3, "the next volley is marked")
	GameState.heal_full()
	# Leash: nobody alive on the summit -> full reset, adds gone.
	_check(b.living_adds() >= 2, "adds alive before the reset (%d)" % b.living_adds())
	pl.global_position = Vector3(0, 1, 0)
	b.tick(5.0, pl)
	_check(b.state == BossBrain.State.IDLE and boss.hp == boss.max_hp and b.current_bar() == 4 and b.phase == 1 and events[-1] == "reset", "nobody on the summit for the grace period: the Guardian resets to full, phase 1")
	_check(b.living_adds() == 0 and boss.global_position.distance_to(boss.home) < 0.5, "the reset removes the adds and walks the Guardian home")
	_check(b.pending_hazards() == 0, "the reset clears falling stones")
	await get_tree().process_frame
	_check(b.adds.is_empty() and boss.visible and boss.is_inside_tree(), "vanished adds are freed; the Guardian stays")
	# Death: adds vanish; the Last Attack bonus still pays.
	pl.global_position = boss.global_position + Vector3(0, 0, 8)
	b.tick(0.05, pl)
	boss.take_hit(bar_hp * 2.5, Vector3.FORWARD, 1)
	_check(b.current_bar() == 2 and b.living_adds() >= 2, "a hit across two thresholds breaks straight into bar 2 and calls adds")
	var rdb = Net.get_realm()
	var me_key: String = Net.local_holder()
	for hk in rdb.holders("la_floor1"):
		rdb.release("la_floor1", hk)  # a crashed earlier run may still hold the slot
	GameState.inventory = GameState.inventory.filter(func(it): return not LimitedContent.is_bound(it))
	var fc0: int = GameState.floors_cleared
	boss.take_hit(1.0e6, Vector3.FORWARD, 1)
	# The Guardian does not respawn: the node (and its brain) frees this frame.
	var adds_left: int = b.living_adds()
	var died_event: bool = events.has("death")
	await get_tree().process_frame
	var mantles := 0
	for it in GameState.inventory:
		if it is Dictionary and it.get("name", "") == "Mantle of the First Floor":
			mantles += 1
	_check(died_event and adds_left == 0 and w._boss == null and not is_instance_valid(boss), "the Guardian's death removes the adds and frees the boss")
	_check(mantles == 1 and rdb.is_holder("la_floor1", me_key) and GameState.floors_cleared >= 1, "Last Attack bonus and the floor clear still pay on the brain-driven kill")
	GameState.floors_cleared = fc0
	rdb.release("la_floor1", me_key)
	GameState.inventory = GameState.inventory.filter(func(it): return not LimitedContent.is_bound(it))
	GameState.hidden_stats = {}
	GameState.heal_full()
	w.queue_free()
	await get_tree().process_frame
