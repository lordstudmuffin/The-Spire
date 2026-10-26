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
	if OS.get_environment("SMOKE_ONLY") == "classes":
		await _test_hidden_classes()
		print("== Done: %d failure(s)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	if OS.get_environment("SMOKE_ONLY") == "permadeath":
		await _test_permadeath()
		print("== Done: %d failure(s)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	if OS.get_environment("SMOKE_ONLY") == "duels":
		await _test_duels()
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
	_check(Net.weapon_atk_cap(0) < Net.weapon_atk_cap(5) and Net.weapon_atk_cap(5) == ceilf(best_base * Crafting.RANK_MULT[5] * 1.15), "weapon attack cap per rank (%d at Myth)" % int(Net.weapon_atk_cap(5)))
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
	# Crystals: a Healing Crystal restores the record's HP in full and is spent;
	# refused without one or at full HP.
	rec["hp"] = 5.0
	_check(Net._srv_action(4242, "crystal", {"id": "heal_crystal"}).has("error"), "crystal refused without one")
	rs.add_material("heal_crystal", 1)
	_check(Net._srv_action(4242, "crystal", {"id": "heal_crystal"}).has("id") and absf(float(rec["hp"]) - rs.max_hp()) < 0.01 and int(rec["materials"]["heal_crystal"]) == 0, "a Healing Crystal heals the record to full and is used up")
	rs.add_material("heal_crystal", 1)
	_check(Net._srv_action(4242, "crystal", {"id": "heal_crystal"}).has("error") and int(rec["materials"]["heal_crystal"]) == 1, "a Healing Crystal is refused at full HP")
	rs.add_material("teleport_crystal", 1)
	_check(Net._srv_action(4242, "crystal", {"id": "teleport_crystal"}).has("id") and int(rec["materials"]["teleport_crystal"]) == 0 and Net.is_safe_destination(GameState.spawn_point()), "a Teleport Crystal is spent on the record and lands on a safe destination")
	var col_c := int(rec["money"])
	rec["money"] = 1000
	_check(LifeData.buy("heal_crystal", rs) == "" and int(rec["materials"]["heal_crystal"]) == 2 and int(rec["money"]) == 1000 - int(LifeData.CRYSTALS["heal_crystal"]["price"]), "Trader Pell sells Healing Crystals")
	rec["money"] = col_c
	rec["materials"].erase("heal_crystal")
	# Server-side wear: a mob hit wears the record's armor; broken armor soaks nothing.
	var dur_plate := Crafting.make_item("Hide Armor", 0, "Tester")
	rec["inventory"].append(dur_plate)
	rs.equip(dur_plate)
	var dur_def0 := rs.armor_defense()
	Net.srv_wear(4242, "armor", Durability.max_for(dur_plate) + 1.0)
	_check(dur_def0 > 0.0 and rs.armor_defense() == 0.0 and Durability.is_broken(rec["inventory"][rec["inventory"].size() - 1]), "worn-out armor on the record breaks and soaks nothing")
	rec["money"] = 1000
	_check(Durability.repair(rs, "armor") == "" and rs.armor_defense() == dur_def0 and int(rec["money"]) < 1000, "the record's armor repairs for Col")
	rs.unequip("armor")
	rec["inventory"].pop_back()
	rec["money"] = col_c
	rec["xp"] = 40
	var lose_r: int = mini(int(rs.xp_to_next() * Net.DEATH_XP_LOSS), 40)
	Net._death_grace.erase(4242)
	_check(Net.srv_damage(4242, 1.0e5) and int(rec["xp"]) == 40 - lose_r and absf(float(rec["hp"]) - rs.max_hp()) < 0.01, "a death on the server record costs %d EXP and respawns at full HP" % lose_r)
	Net._death_grace.erase(4242)
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
	var members := ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf"]
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
	for peer in [5003, 5004, 5005, 5006]:
		_check(Net._srv_invite(5001, peer) == "", "leader invites %d" % peer)
		Net._srv_respond(peer, true)
	_check(Net.srv_parties[pid]["members"].size() == 6, "party fills to six")
	_check(Net._srv_invite(5001, 5007) != "", "seventh member refused (cap %d)" % Net.PARTY_MAX)
	Net._srv_invite(5007, 5001)
	_check(not Net.srv_invites.has(5001), "members of a party cannot be invited elsewhere")
	Net._srv_leave_party(5001)
	_check(not Net.srv_party_of.has(5001) and Net.srv_parties[pid]["leader"] == 5002, "leader leaving hands over to the oldest member")
	for peer in [5003, 5004, 5005, 5006]:
		Net._srv_leave_party(peer)
	_check(not Net.srv_parties.has(pid) and not Net.srv_party_of.has(5002), "party disbands when one member is left")
	_check(Net._srv_invite(5001, 5002) == "", "re-invite after disband")
	Net._srv_respond(5002, false)
	_check(not Net.srv_party_of.has(5002) and not Net.srv_invites.has(5002), "declining leaves no party")
	# Reward split goes through the server records: killer alone (no player
	# nodes to measure range against) keeps the full amount.
	var xp0: int = Net.srv_records[5001]["xp"]
	var shares := Net.srv_reward_kill(5001, 30, 4, Vector3.ZERO)
	_check(shares.size() == 1 and shares[5001] == [30, 4] and Net.srv_records[5001]["xp"] == xp0 + 30, "solo kill rewards the killer through the record")
	# Party in range (fake player nodes for the server's positions): EXP and
	# Col split with the bonus, each drop to one random member, hunt-quest
	# credit for every member on that quest.
	var pscript := GDScript.new()
	pscript.source_code = "extends Node3D\nvar peer_id := 0\n"
	pscript.reload()
	var fakes: Array = []
	for peer in [5001, 5002]:
		var fp := Node3D.new()
		fp.set_script(pscript)
		fp.set("peer_id", peer)
		fp.add_to_group("players")
		add_child(fp)
		fakes.append(fp)
	Net._srv_invite(5001, 5002)
	Net._srv_respond(5002, true)
	Net.srv_records[5002]["quests"]["boar_trouble"] = {"progress": 0, "goal": 99, "done": false}
	Net.srv_records[5001]["materials"]["beast_hide"] = 0
	Net.srv_records[5002]["materials"]["beast_hide"] = 0
	var xp2: int = Net.srv_records[5002]["xp"]
	for k in 24:
		shares = Net.srv_reward_kill(5001, 100, 20, Vector3.ZERO, {"beast_hide": 1.0}, "boar_trouble")
	var h1 := int(Net.srv_records[5001]["materials"].get("beast_hide", 0))
	var h2 := int(Net.srv_records[5002]["materials"].get("beast_hide", 0))
	_check(shares.size() == 2 and shares[5002] == Net.party_split(100, 20, 2) and Net.srv_records[5002]["xp"] > xp2, "party kill: the member in range gets the split share")
	_check(h1 + h2 == 24 and h1 > 0 and h2 > 0, "party kill: drops are shared out at random (%d / %d of 24)" % [h1, h2])
	_check(int(Net.srv_records[5002]["quests"]["boar_trouble"]["progress"]) == 24, "party kill: hunt-quest credit for the member on the quest")
	for fp in fakes:
		fp.queue_free()
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
	_check(rhys.talk().begins_with("Vargash waits"), "bounty in-progress line")

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
	# Weapon proficiency: the later Sword Arts unlock with use.
	var prof0 := GameState.sword_prof
	GameState.sword_prof = 0
	_check(Player.art_unlocked(0, 0) and not Player.art_unlocked(1, 0) and not Player.art_unlocked(2, 119) and Player.art_unlocked(2, 120), "Sword Arts unlock at proficiency 0 / 40 / 120")
	GameState.sword_prof = 39
	_check(GameState.add_sword_prof(1) == "Twin Crescent" and GameState.add_sword_prof(1) == "" and GameState.sword_prof == 41, "the 40th landed swing teaches Twin Crescent")
	GameState.sword_prof = GameState.PROF_CAP
	GameState.add_sword_prof(5)
	_check(GameState.sword_prof == GameState.PROF_CAP, "proficiency caps at %d" % GameState.PROF_CAP)
	var old_rec := {"name": "Old", "level": 5}
	Net.fill_record_defaults(old_rec)
	_check(int(old_rec["sword_prof"]) == GameState.prof_for_level(5) and GameState.prof_for_level(5) >= 120 and int(Net.record_defaults()["sword_prof"]) == 0, "records from before proficiency are credited by level (new ones start at 0)")
	GameState.sword_prof = prof0
	# Durability: forged gear wears with use, breaks to no stats, repairs at an anvil.
	var dur_keep_eq: Dictionary = GameState.equipped.duplicate()
	var dur_keep_inv: Array = GameState.inventory.duplicate()
	var dur_keep_col := GameState.money
	var dur_blade := Crafting.make_item("Iron Sword", 1, "Tester")
	_check(Durability.cur(dur_blade) == Durability.max_for(dur_blade) and Durability.max_for(dur_blade) == 110.0, "a forged Rare blade starts at full durability (110)")
	GameState.inventory.append(dur_blade)
	GameState.equip(dur_blade.duplicate(true))  # the save round trip leaves two copies
	var dur_atk := GameState.weapon_attack()
	GameState.wear_gear("weapon", 10.0)
	_check(is_equal_approx(Durability.cur(GameState.equipped["weapon"]), 100.0) and is_equal_approx(Durability.cur(dur_blade), 100.0), "wear lands on both the equipped and the inventory copy")
	var dur_states: Array = []
	var dur_on := func(_slot, st): dur_states.append(st)
	GameState.gear_state.connect(dur_on)
	GameState.wear_gear("weapon", 85.0)
	GameState.wear_gear("weapon", 50.0)
	GameState.gear_state.disconnect(dur_on)
	_check(dur_states == ["low", "broken"] and Durability.is_broken(GameState.equipped["weapon"]) and GameState.weapon_attack() == 0.0 and dur_atk > 0.0, "the blade warns when worn, then breaks and adds no attack")
	GameState.money = 1000
	var dur_cost := Durability.repair_cost(GameState.equipped["weapon"], GameState.smithing_level)
	_check(dur_cost > 0 and Durability.repair(GameState, "weapon") == "" and GameState.money == 1000 - dur_cost and GameState.weapon_attack() == dur_atk and Durability.repair(GameState, "weapon").contains("perfect"), "repairing for %d Col restores the blade" % dur_cost)
	_check(Durability.repair_cost(dur_blade, 16) < Durability.repair_cost({"kind": "weapon", "rank": 1, "dur": 0.0}, 1) or Durability.repair_cost(dur_blade, 16) == 0, "smithing skill lowers repair prices")
	GameState.equipped = dur_keep_eq
	GameState.inventory = dur_keep_inv
	GameState.money = dur_keep_col

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
	_test_forging(world, vrs, vrec, npc_pos["Smith Haldor"], far)
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
	for lid in ["lantern_below", "old_watch_whispers", "veil_first_dawn", "wisplight_rapier", "la_floor1", "la_sergeant", "la_greytusk"]:
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
	var la1: Dictionary = world._grant_last_attack(1)
	var shards_la := int(GameState.materials.get("spirit_shard", 0))
	var la2: Dictionary = world._grant_last_attack(1)
	_check(la1.get("item", "") == "Mantle of the First Floor" or rdb.is_holder("la_floor1", me_key), "Last Attack on the Guardian pays the Mantle")
	_check(la2.get("item", "x") == "" and int(la2.get("xp", 0)) == world.BOSS_LA["xp"] and int(GameState.materials.get("spirit_shard", 0)) == shards_la + 2,
		"a second Last Attack pays the fallback bonus (+%d EXP, +%d Col, 2 shards)" % [int(la2.get("xp", 0)), int(la2.get("col", 0))])
	var la3: Dictionary = world._grant_last_attack(1, world.SERGEANT_LA, "Kobold Sergeant")
	_check(la3.get("item", "") == "Sergeant's Cleaver" and rdb.is_holder("la_sergeant", me_key) and LimitedContent.ITEMS["la_sergeant"]["cap"] == 3, "Last Attack on the Kobold Sergeant: one of three Cleavers")
	var grey: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if world.is_ancestor_of(e) and e.display_name.begins_with("Greytusk"):
			grey = e
	_check(grey != null and grey.rush and grey.respawn_time >= 600.0, "Greytusk, the named field elite, roams the south field")
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
	for lid in ["lantern_below", "old_watch_whispers", "veil_first_dawn", "wisplight_rapier", "la_floor1", "la_sergeant", "la_greytusk"]:
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
	GameState.xp = 50
	var lose: int = mini(int(GameState.xp_to_next() * Net.DEATH_XP_LOSS), 50)
	var lv_d := GameState.level
	pl.take_damage(1.0e6)
	_check(GameState.xp == 50 - lose and GameState.level == lv_d and pl.last_xp_lost == lose, "dying costs %d EXP toward the next level, never a level" % lose)
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
	# Villagers' day/night routines (same world).
	var rt: Node = world._routines
	_check(rt != null and rt._npcs.size() == 3, "three villagers keep day/night routines")
	if rt != null:
		var dn: DayNight = world.day_night
		var t0 := dn.time_of_day
		dn.time_of_day = 21.0
		rt.settle()
		var vesna: Node3D = rt._npcs["Trapper Vesna"]["node"]
		var tavern: Vector3 = world.HOLLOWBROOK + Vector3(-4.0, 0, -4.6)
		_check(vesna.position.distance_to(tavern) < 0.2 and rt.is_out("Trapper Vesna"), "after dark Vesna stands on the tavern porch")
		_check(world._srv_npc_near(vesna.global_position, ["Trapper Vesna"]) != null, "the server finds her there for talk checks")
		var bram: Dictionary = rt._npcs["Old Watchman Bram"]
		var leg0 := int(bram["leg"])
		bram["node"].position = rt.goal_of("Old Watchman Bram")
		rt._step("Old Watchman Bram", 0.1)
		_check(int(bram["leg"]) == leg0 + 1, "Bram walks a night patrol loop")
		dn.time_of_day = 12.0
		var before: Vector3 = vesna.position
		rt._step("Trapper Vesna", 1.0)
		_check(vesna.position.distance_to(before) > 1.0 and vesna.position.distance_to(before) < 1.7, "at noon she walks home at a walking pace")
		rt.settle()
		_check(vesna.position.distance_to(rt._npcs["Trapper Vesna"]["home"]) < 0.01 and not rt.is_out("Trapper Vesna"), "and is back at her spot by day")
		dn.time_of_day = t0
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
	await _test_hidden_classes()
	await _test_duels()
	await _test_boss()
	await _test_permadeath()

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
	w._stalls.apply_signs([{"owner": "Vendra", "type": "shop", "n": 2}, {"owner": "", "n": 0}, {"owner": "Vendra", "type": "shop", "n": 0}])
	_check(w._stalls.stalls[0]["keeper"].visible and not w._stalls.stalls[1]["keeper"].visible and not w._stalls.stalls[2]["keeper"].visible, "a keeper stands at rented, stocked stalls only")
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
	# Guild stall: an Officer rents a market stall in the guild's name.
	var S = preload("res://scripts/life/stalls.gd")
	var gkey: String = S.guild_key(gid)
	dot["money"] = 500
	_check(S.run(rdb, drs, dot, 1, {"op": "rent", "guild": true}, keep).has("error") and dot["money"] == 500, "guild stall: a Member cannot rent for the guild")
	ben["money"] = 400
	r = S.run(rdb, brs, ben, 1, {"op": "rent", "type": "shop", "guild": true}, keep)
	_check(not r.has("error") and ben["money"] == 400 - S.RENT and str(rdb.container(S.stock_id(1)).get("owner", "")) == gkey and rdb.is_holder(S.claim_id(1), gkey)
		and S.sign_state(rdb)[1]["owner"] == "[LW] Lantern bWardens" and S.stall_of(rdb, bh) < 0, "guild stall: an Officer rents stall 2 for [LW]; the sign names the guild")
	_check(S.run(rdb, brs, ben, 3, {"op": "rent", "guild": true}, keep).has("error"), "guild stall: one stall per guild")
	var gaxe := {"id": "gs_axe", "name": "Guild Axe", "kind": "weapon", "rank": 1, "atk": 10, "def": 0}
	ann["inventory"].append(gaxe)
	r = S.run(rdb, ars, ann, 1, {"op": "stock", "item": "gs_axe", "price": 200}, keep)
	_check(not r.has("error") and r["view"]["mine"] and r["view"]["guild_owned"] and Stalls_find(ann["inventory"], "gs_axe") < 0, "guild stall: the Leader stocks it too")
	_check(S.run(rdb, drs, dot, 1, {"op": "withdraw", "item": "gs_axe"}, keep).has("error") and not S.view(rdb, 1, dh)["mine"], "guild stall: a Member cannot manage it")
	_check(S.close_guild_stall(rdb, gid) != "", "guild stall: disband is refused while wares are on its counter")
	var col_before := int(rdb.container(sid).get("col", 0))
	r = S.run(rdb, drs, dot, 1, {"op": "buy", "item": "gs_axe", "price": 200}, keep)
	_check(not r.has("error") and dot["money"] == 300 and Stalls_find(dot["inventory"], "gs_axe") >= 0
		and int(rdb.container(sid).get("col", 0)) == col_before + 200 - roundi(200 * S.TAX_RATE) and rdb.pending_count() == 0,
		"guild stall: a sale pays the guild storage, less %d%% tax" % int(S.TAX_RATE * 100))
	_check(S.close_guild_stall(rdb, gid) == "" and S.run(rdb, brs, ben, 1, {"op": "price", "item": "x", "price": 5}, keep).has("error"), "guild stall: an empty counter can close")
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
	G.run(rdb, brs, ben, {"op": "withdraw", "col": int(rdb.container(sid).get("col", 0))}, keep, board)
	r = G.run(rdb, brs, ben, {"op": "leave"}, keep)
	_check(not r.has("error") and G.guild_of(rdb, bh) == "" and G.get_guild(rdb, gid).is_empty() and rdb.container(sid).is_empty(), "guild: the last member's leave disbands an emptied guild")
	_check(S.sign_state(rdb)[1]["owner"] == "" and not rdb.is_holder(S.claim_id(1), gkey), "guild stall: disbanding frees the guild's stall")
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


static func player_pos_for_monument(world: Node3D) -> Vector3:
	return world.player.global_position + Vector3(1.0, 0, 0)


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
	# Monument of Climbers: sorted by level, then floors, then name; offline
	# it lists the local character; any "monument" group node gets the list.
	var Mo = load("res://scripts/monument.gd")
	var ord: Array = Mo.sorted([{"name": "b", "level": 3, "floors": 0, "online": false}, {"name": "a", "level": 3, "floors": 1, "online": true}, {"name": "c", "level": 9, "floors": 0, "online": false}])
	_check(ord.size() == 3 and ord[0]["name"] == "c" and ord[1]["name"] == "a" and ord[2]["name"] == "b", "the Monument orders climbers by level, then floors cleared")
	var face_gd := GDScript.new()
	face_gd.source_code = "extends Node3D\nvar got: Array = []\nfunc set_names(e: Array) -> void:\n\tgot = e\n"
	face_gd.reload()
	var face := Node3D.new()
	face.set_script(face_gd)
	face.add_to_group("monument")
	world.add_child(face)
	face.global_position = player_pos_for_monument(world)
	world._monument.refresh()
	_check(world._monument != null and face.get("got").size() == 1 and str(face.get("got")[0]["name"]) == str(GameState.character.get("name", "Nameless")), "the Monument lists the local character offline and fills the art node")
	_check(world._nearest_interactable()[0] == world._monument and world._monument.text().begins_with("1. "), "E next to the monument reads it")
	face.queue_free()
	# Post-battle results: kills and drops add up into one window.
	var br: Node = world._results
	br.close()
	br.note_kill("Meadow Slime", 12, 2)
	br.note_kill("Meadow Slime", 12, 2)
	br.note_item("beast_hide")
	var res_data: Dictionary = br.close()
	_check(int(res_data.get("kills", 0)) == 2 and int(res_data["xp"]) == 24 and int(res_data["col"]) == 4 and int(res_data["foes"]["Meadow Slime"]) == 2 and int(res_data["items"]["beast_hide"]) == 1 and br.close().is_empty(), "battle results sum the fight's kills, EXP, Col and items")
	_check(load("res://scripts/battle_results.gd").summary(res_data).contains("+24 EXP") and load("res://scripts/battle_results.gd").summary(res_data).contains("Beast Hide x1"), "the results summary reads +24 EXP / Beast Hide x1")
	_check(load("res://scripts/battle_results.gd").summary({"xp": 40, "col": 8, "items": {}, "party": 3}).contains("Party of 3 (+20%)"), "the results name the party share")
	# Field mobs (Aincrad's first floor): the grove, lures, packs, boar rushes.
	var vines: Array = []
	var boar: Enemy = null
	var wolf: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if not world.is_ancestor_of(e):
			continue  # mobs of another test's world still freeing
		if e.pack == "vine":
			vines.append(e)
		elif e.display_name == "Field Boar" and boar == null:
			boar = e
		elif e.display_name == "Dire Wolf" and wolf == null and not Duels.in_safe_zone(e.global_position + Vector3(0, 0, 4)):
			wolf = e
	var lures := vines.filter(func(v): return v.lure)
	var blooms := vines.filter(func(v): return v.display_name == "Blossoming Snaptrap")
	_check(vines.size() == 8 and lures.size() == 2 and blooms.size() == 1 and blooms[0].drops.get("snaptrap_bloom", 0.0) == 1.0 and blooms[0].respawn_time >= 200.0, "the Snaptrap Grove: 8 vines, 2 fruit-bearers, 1 slow-regrowing bloom")
	var pl_f: Player = world.player
	var keep_pos: Vector3 = pl_f.global_position
	pl_f.global_position = world.GROVE + Vector3(0, 1, 14)
	var fruit_vine: Enemy = lures[0]
	fruit_vine.take_hit(1.0, Vector3.FORWARD, pl_f.peer_id)
	var called := vines.filter(func(v): return v != fruit_vine and v._called_by != null and v._called_t > 0.0)
	_check(not fruit_vine.lure and called.size() >= 6, "striking the fruit bursts it and draws the grove onto you (%d answered)" % called.size())
	var wolves: Array = get_tree().get_nodes_in_group("enemies").filter(func(e): return world.is_ancestor_of(e) and e.pack == "wolf" and e != wolf and e.global_position.distance_to(wolf.global_position) <= Enemy.PACK_RANGE)
	pl_f.global_position = wolf.global_position + Vector3(0, 0, 4)
	wolf._call_pack(pl_f, Enemy.PACK_RANGE)
	_check(wolves.all(func(e): return e._called_by == pl_f), "a wolf calls its packmates in range (%d)" % wolves.size())
	_check(boar.rush and not wolf.rush, "boars charge; wolves do not")
	GameState.heal_full()
	boar.global_position = pl_f.global_position + Vector3(0, 0, -7)
	boar._rush_cd = 0.0
	boar._begin_rush(pl_f, 7.0)
	_check(is_equal_approx(boar._rush_wind, Enemy.RUSH_WINDUP), "the boar paws the ground first (telegraph)")
	boar._start_rush()
	boar.global_position = pl_f.global_position + Vector3(0, 0, -1.0)
	var hp_r := GameState.hp
	boar._rush_contact()
	_check(GameState.hp < hp_r and boar._rush_t == 0.0 and boar._rush_cd > 0.0, "a boar's charge lands on the player in its path")
	GameState.heal_full()
	pl_f.global_position = keep_pos
	# Hesper's grove errand pays the Verdant Edge.
	var q_keep: Dictionary = GameState.quests.duplicate(true)
	GameState.quests["field_herbs"] = {"progress": 6, "goal": 6, "done": true}
	GameState.quests["tavern_stew"] = {"progress": 1, "goal": 1, "done": true}
	GameState.quests.erase("grove_bloom")
	GameState.materials["snaptrap_bloom"] = 0
	_check(world._hesper_talk().contains("snaptraps") and GameState.quests.has("grove_bloom"), "Hesper sends you to the Snaptrap Grove after the stew")
	GameState.add_material("snaptrap_bloom", 1)
	var inv_n := GameState.inventory.size()
	world._hesper_talk()
	_check(GameState.quest_done("grove_bloom") and GameState.inventory.size() == inv_n + 1 and GameState.inventory[inv_n]["name"] == "Verdant Edge" and int(GameState.inventory[inv_n]["rank"]) == 2, "the bloom buys the Verdant Edge")
	GameState.inventory.pop_back()
	GameState.quests = q_keep
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
	# Switch: a party mate cutting in on a parry-staggered mob.
	var mob: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and e.visible and not e.is_boss and e.brain == null and world.is_ancestor_of(e):
			mob = e
			break
	if mob != null:
		mob._posture = 0
		mob._stagger = 0.0
		mob._parried(world.player)
		_check(mob._stagger > 0.0 and mob._switch_from == world.player.peer_id and mob._switch_until > Time.get_ticks_msec(), "a staggering parry opens a Switch window")
		Net.online = true
		Net.srv_party_of = {5: 9, 6: 9, 7: 0}
		mob._switch_from = 5
		mob._switched = false
		mob.max_hp = 5000.0
		mob.hp = 5000.0
		var st0: float = mob._stagger
		mob.take_hit(10.0, Vector3.FORWARD, 6, 0)
		var sw_dmg: float = 5000.0 - mob.hp
		_check(is_equal_approx(sw_dmg, 10.0 * Enemy.RIPOSTE_MULT * Enemy.SWITCH_MULT) and mob._switched and mob._stagger > st0, "a party mate's Switch lands boosted and keeps the mob reeling")
		var h1: float = mob.hp
		mob.take_hit(10.0, Vector3.FORWARD, 6, 0)
		_check(is_equal_approx(h1 - mob.hp, 10.0 * Enemy.RIPOSTE_MULT), "only the first cut-in counts as the Switch")
		mob._switched = false
		var h2: float = mob.hp
		mob.take_hit(10.0, Vector3.FORWARD, 7, 0)
		_check(is_equal_approx(h2 - mob.hp, 10.0 * Enemy.RIPOSTE_MULT) and not mob._switched, "no Switch for a player outside the party")
		Net.online = false
		Net.srv_party_of = {}
		mob._stagger = 0.0
		mob.hp = mob.max_hp
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


## Hidden classes Stillblade and Hearthwright (scripts/hidden_classes.gd):
## hidden deeds, the NPC rites, the arts' cast rules, the perks, and the
## server-side record path. SMOKE_ONLY=classes runs just this block.
func _test_hidden_classes() -> void:
	print("== Hidden classes: Stillblade and Hearthwright")
	var keep_class := GameState.hidden_class
	var keep_hidden: Dictionary = GameState.hidden_stats.duplicate(true)
	var keep_quests: Dictionary = GameState.quests.duplicate(true)
	var keep_stats: Dictionary = GameState.stats.duplicate()
	var keep_mats: Dictionary = GameState.materials.duplicate()
	var keep_buffs: Dictionary = GameState.buffs.duplicate(true)
	GameState.hidden_class = ""
	GameState.hidden_stats = {}
	GameState.buffs = {}
	GameState.floor = 1
	GameState.has_position = false
	GameState.heal_full()
	var H = HiddenClasses
	_check(GameState.HIDDEN_CLASSES.has(H.STILLBLADE) and GameState.HIDDEN_CLASSES.has(H.HEARTHWRIGHT) and GameState.HIDDEN_CLASSES.size() == 3, "three hidden classes on Floor 1")
	_check(H.arts_of(H.STILLBLADE).size() == 2 and H.arts_of(H.HEARTHWRIGHT).size() == 1 and H.arts_of("Forgeborn").is_empty(), "Stillblade has two arts, Hearthwright one, Forgeborn none")
	_check(H.is_art_kind(H.KIND_BASE) and not H.is_art_kind(H.KIND_BASE + H.ARTS.size()) and not UniqueSkills.is_unique_kind(H.KIND_BASE) and H.KIND_BASE >= UniqueSkills.KIND_BASE + 10, "class art kinds sit in their own range above the unique kinds")
	_check(H.kind_of(H.STILLBLADE, 1) == H.KIND_BASE + 1 and H.kind_of(H.HEARTHWRIGHT, 0) == H.KIND_BASE + 2 and H.kind_of(H.HEARTHWRIGHT, 1) == -1, "kind_of maps a class slot to its net kind")
	for a in H.ARTS:
		_check(not str(a["name"]).to_lower().contains("sword art online") and not str(a["name"]).to_lower().contains("overgeared"), "art '%s' uses an original name" % a["name"])
	# Hidden deeds: eight clean parries, a hit resets the streak.
	for i in 5:
		GameState.note_hidden("parry")
	GameState.note_hidden("hurt")
	_check(int(GameState.hidden_stats.get("clean_parries", 0)) == 0 and int(GameState.hidden_stats.get("best_streak", 0)) == 5 and not H.still_ready(GameState), "a hit ends the clean parry streak (best 5, not ready)")
	for i in H.STILL_STREAK:
		GameState.note_hidden("parry")
	_check(H.still_ready(GameState) and int(GameState.hidden_stats.get("best_streak", 0)) == H.STILL_STREAK, "%d clean parries in a row set the Stillblade deed" % H.STILL_STREAK)
	_check(GameState.to_dict()["hidden"].has("still_ready") and not GameState.to_dict().has("still_ready"), "the deed lives in the save's hidden block")
	# The rite: Dain opens it only once the deed is done, never before.
	var world: Node3D = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var world_npcs := 0
	var npc_names := {}
	for c in world.get_children():
		if c is NPC:
			world_npcs += 1
			npc_names[c.npc_name] = true
	_check(world_npcs == 13 and npc_names.has("Quartermaster Dain") and npc_names.has("Innkeeper Rook"), "no new NPCs: Dain and Rook carry the rites (%d NPCs in the world)" % world_npcs)
	GameState.hidden_stats = {}
	GameState.quests.erase(H.STILL_QUEST)
	var line: String = world._dain_talk()
	_check(not GameState.quests.has(H.STILL_QUEST) and (line.begins_with("Sit by the fire") or line.begins_with("You did it")), "Dain says nothing of the rite before the deed")
	_check(bool(QuestData.info(H.STILL_QUEST).get("hidden", false)) and bool(QuestData.info(H.HEARTH_QUEST).get("hidden", false)) and not QuestData.active_ids().has(H.STILL_QUEST), "the rites are flagged hidden and absent from the log until opened")
	for i in H.STILL_STREAK:
		GameState.note_hidden("parry")
	line = world._dain_talk()
	_check(GameState.quests.has(H.STILL_QUEST) and int(GameState.quests[H.STILL_QUEST]["goal"]) == H.STILL_QUEST_GOAL and line.contains("Eight blows"), "the deed done, Dain opens The Unmoving Edge")
	_check(QuestData.active_ids().has(H.STILL_QUEST) and QuestData.title(H.STILL_QUEST) == "The Unmoving Edge", "the opened rite now shows in the quest log")
	for i in H.STILL_QUEST_GOAL - 1:
		GameState.note_hidden("parry")
	line = world._dain_talk()
	_check(GameState.hidden_class == "" and line.begins_with("9 of 10"), "parries move the rite; one short, no class yet")
	GameState.note_hidden("parry")
	var str0: int = GameState.stats["agility"]
	line = world._dain_talk()
	_check(GameState.hidden_class == H.STILLBLADE and GameState.quest_done(H.STILL_QUEST) and GameState.stats["agility"] == str0 + 2 and GameState.class_title() == "Stillblade", "ten parries later Dain names you Stillblade (+2 AGI)")
	_check(world._dain_talk().begins_with("Stillblade."), "Dain greets a Stillblade")
	# Perks and arts on the player.
	var pl: Player = world.player
	pl.global_position = Vector3(0, 1, 40)  # clear of the spawn's mobs: the casts below hit nothing
	pl.velocity = Vector3.ZERO
	_check(is_equal_approx(pl._guard_regen(), Player.GUARD_REGEN * H.GUARD_REGEN_MULT), "Stillblade guard recovers %.1fx faster" % H.GUARD_REGEN_MULT)
	pl.last_parry_ms = -100000
	pl.class_cd = [0.0, 0.0]
	_check(not pl.use_class_art(0) and pl.class_cd[0] == 0.0, "Still Water refuses without a recent parry")
	pl.last_parry_ms = Time.get_ticks_msec()
	_check(pl.use_class_art(0) and pl.class_cd[0] > 0.0, "Still Water casts right after a parry and starts its cooldown")
	_check(not pl.use_class_art(0), "Still Water honours its cooldown")
	_check(pl.use_class_art(1) and pl.class_cd[1] > 0.0 and not pl.use_class_art(2), "Breaking Wave casts; there is no third class art")
	await get_tree().create_timer(0.25, false).timeout  # let the two hit cones resolve (on nothing)
	# Breaking Wave builds posture on the mob it lands on (offline: take_hit).
	var mob: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and not e.is_boss and e.visible and not e.is_staggered():
			mob = e
			break
	if mob != null:
		mob._posture = 0
		var hp0: float = mob.hp
		mob.take_hit(1.0, Vector3.FORWARD, 1, H.KIND_BASE + 1)
		_check(mob.is_staggered() and mob.hp < hp0, "Breaking Wave staggers a normal mob outright")
		mob._stagger = 0.0
		mob._posture = 0
	else:
		_check(false, "a living mob to test Breaking Wave on")
	# Server side: the class and the buff come from the record, never the client.
	var rec: Dictionary = Net.record_defaults()
	rec.merge({"name": "RecTester", "level": 3, "stats": {"strength": 3, "agility": 2, "endurance": 2, "spirit": 1},
		"character": {"name": "RecTester", "origin": "Swordsman"}}, true)
	Net.srv_records[7101] = rec
	var bogus: Dictionary = Net.record_defaults()
	bogus["hidden_class"] = "Bladewraith"
	Net.srv_records[7102] = bogus
	_check(Net.srv_hidden_class(7101) == "" and Net.srv_hidden_class(7102) == "" and Net.srv_hidden_class(1) == H.STILLBLADE, "srv_hidden_class reads the record (unknown classes read as none; offline peer 1 is GameState)")
	var rs = Net.RecordState.new(rec)
	H.note(rs, "parry")
	H.note(rs, "parry")
	Net.srv_damage(7101, 1.0)  # a hit resets the streak on the record
	_check(int(rec["hidden"]["clean_parries"]) == 0 and int(rec["hidden"]["best_streak"]) == 2, "srv_damage ends a record's parry streak")
	for i in H.STILL_STREAK:
		H.note(rs, "parry")
	_check(H.still_ready(rs) and int(rec["hidden"]["clean_parries"]) == H.STILL_STREAK, "the record path tracks the streak (srv_damage resets, parries build)")
	line = world._dain_talk(rs)
	_check(rec["quests"].has(H.STILL_QUEST) and str(rec.get("hidden_class", "")) == "", "Dain opens the rite on a record")
	for i in H.STILL_QUEST_GOAL:
		H.note(rs, "parry")
	line = world._dain_talk(rs)
	_check(str(rec["hidden_class"]) == H.STILLBLADE and rs.events.size() > 0 and rs.events[-1].has("class") and Net.srv_hidden_class(7101) == H.STILLBLADE, "the rite completes on the record and the server now sees the class")
	_check(not Net.snapshot_for_client(rec).has("hidden") and Net.snapshot_for_client(rec).get("hidden_class", "") == H.STILLBLADE, "the client snapshot carries the class but never the hidden deeds")
	Net.srv_class_buff(7101, "hearth_glow", H.HEARTH_GLOW)
	_check(rec["buffs"].has("hearth_glow") and float(rec["buffs"]["hearth_glow"]["regen"]) == 3.0, "srv_class_buff puts an art's buff on the record")
	Net.srv_records.erase(7101)
	Net.srv_records.erase(7102)
	# Hearthwright: the life deeds, Rook's rite, and the food perk.
	GameState.hidden_class = ""
	GameState.stats = keep_stats.duplicate()
	GameState.hidden_stats = {}
	GameState.quests.erase(H.HEARTH_QUEST)
	GameState.quests["tavern_stew"] = {"progress": 1, "goal": 1, "done": true}
	for i in 3:
		GameState.note_hidden("cook:grilled_trout")
		GameState.note_hidden("cook:turnip_soup")
		GameState.note_hidden("cook:harvest_bread")
	for i in 3:
		GameState.note_hidden("cook:boar_stew")
	for i in H.HEARTH_FISH:
		GameState.note_hidden("fish")
	_check(int(GameState.hidden_stats.get("dishes", 0)) == 12 and GameState.hidden_stats["recipes"].size() == 4 and not H.hearth_ready(GameState), "twelve dishes over four recipes and five fish: not yet, the plots are missing")
	line = world._rook_talk()
	_check(not GameState.quests.has(H.HEARTH_QUEST), "Rook keeps quiet before the deed")
	for i in H.HEARTH_HARVESTS:
		GameState.note_hidden("harvest")
	_check(H.hearth_ready(GameState), "three harvests complete the Hearthwright deed")
	GameState.materials["grilled_trout"] = 0
	GameState.materials["turnip_soup"] = 0
	GameState.materials["harvest_bread"] = 0
	line = world._rook_talk()
	_check(GameState.quests.has(H.HEARTH_QUEST) and line.contains("trail supper"), "Rook opens The Wandering Pot")
	GameState.materials["grilled_trout"] = 1
	line = world._rook_talk()
	_check(GameState.hidden_class == "" and line.begins_with("1 of 3"), "progress mirrors the supper dishes carried")
	GameState.materials["turnip_soup"] = 1
	GameState.materials["harvest_bread"] = 1
	line = world._rook_talk()
	_check(GameState.hidden_class == H.HEARTHWRIGHT and GameState.quest_done(H.HEARTH_QUEST) and int(GameState.materials["grilled_trout"]) == 0 and int(GameState.materials["harvest_bread"]) == 0, "the supper served, Rook names you Hearthwright and takes the dishes")
	_check(world._rook_talk().begins_with("Hearthwright!"), "Rook greets a Hearthwright")
	_check(world._dain_talk().begins_with("Sit by the fire") or world._dain_talk().begins_with("You did it"), "Dain offers no second class to a Hearthwright")
	# Food perk: longer and stronger buffs, server and offline alike.
	GameState.materials["grilled_trout"] = 1
	GameState.buffs = {}
	_check(LifeData.eat("grilled_trout") and is_equal_approx(float(GameState.buffs["grilled_trout"]["left"]), 90.0 * H.FOOD_DURATION_MULT) and is_equal_approx(float(GameState.buffs["grilled_trout"]["regen"]), 2.0 * H.FOOD_POWER_MULT), "a Hearthwright's trout lasts %.0f%% longer and heals %.0f%% harder" % [(H.FOOD_DURATION_MULT - 1.0) * 100.0, (H.FOOD_POWER_MULT - 1.0) * 100.0])
	_check(world._srv_near_fire(Vector3(1e6, 0, 1e6), GameState), "the server lets a Hearthwright cook far from any fire")
	GameState.hidden_class = ""
	_check(not world._srv_near_fire(Vector3(1e6, 0, 1e6), GameState), "...and nobody else")
	GameState.hidden_class = H.HEARTHWRIGHT
	# Hearth Flare: wide arc, and landing it leaves the caster glowing.
	pl.class_cd = [0.0, 0.0]
	GameState.buffs = {}
	if mob != null:
		pl.global_position = Vector3(0, 1, 40)
		pl.velocity = Vector3.ZERO
		pl.model.rotation.y = 0.0
		var fwd: Vector3 = -pl.model.global_transform.basis.z
		mob.global_position = pl.global_position + fwd * 1.6
		var mhp0: float = mob.hp
		_check(pl.use_class_art(0), "Hearth Flare casts")
		await get_tree().create_timer(0.35, false).timeout
		_check(mob.hp < mhp0 and GameState.has_buff("hearth_glow"), "Hearth Flare lands and grants Hearth Glow")
		pl.global_position = GameState.spawn_point()
	_check(not pl.use_class_art(1), "a Hearthwright has no second art")
	# Bindings: the arts have keys, and the pad reaches them through the LT chord.
	_check(InputMap.has_action("class_1") and InputMap.has_action("class_2") and not InputSetup.events("class_1", "kb").is_empty() and not InputSetup.events("class_2", "kb").is_empty(), "class arts have keyboard bindings (R / C)")
	_check(not InputSetup.events("target", "pad").is_empty() and not InputSetup.events("attack", "pad").is_empty() and not InputSetup.events("dash", "pad").is_empty(), "the pad chord (LT + X / B) has all three buttons bound")
	# Restore.
	GameState.hidden_class = keep_class
	GameState.hidden_stats = keep_hidden
	GameState.quests = keep_quests
	GameState.stats = keep_stats
	GameState.materials = keep_mats
	GameState.buffs = keep_buffs
	GameState.heal_full()
	world.queue_free()
	await get_tree().process_frame


func _test_boss() -> void:
	print("== Floor Guardian: the Kobold Warlord (BossBrain)")
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
	_check(boss != null and boss.brain is BossBrain and boss.get_node_or_null("BossBrain") == boss.brain, "the Warlord spawns with a BossBrain child")
	var b: BossBrain = boss.brain
	_check(b.bar_count() == 4 and b.current_bar() == 4 and is_equal_approx(b.bar_fraction(), 1.0) and b.phase == 1 and b.state_name() == "idle", "four full HP bars, phase 1, idle")
	var P0: Dictionary = BossBrain.PRESETS["warlord"]["phases"][0]
	var P1: Dictionary = BossBrain.PRESETS["warlord"]["phases"][1]
	var events: Array = []
	b.boss_event.connect(func(k, _d): events.append(k))
	# Engage: a player stands on the summit.
	pl.global_position = boss.global_position + Vector3(0, 0, 10)
	pl.velocity = Vector3.ZERO
	var ctl: Dictionary = b.tick(0.05, pl)
	_check(boss.global_position.distance_to(w.throne_pos()) < 1.5 and b.throne != Vector3.ZERO, "the Guardian waits on his throne")
	var stings_ok := true
	for ev in ["boss_sting", "boss_phase_sting", "floor_victory", "last_attack"]:
		stings_ok = stings_ok and Audio.EVENTS.has(ev) and ResourceLoader.exists("res://assets/audio/" + str(Audio.EVENTS[ev][0]))
	_check(stings_ok and Audio.has_method("stinger"), "the boss stingers, victory fanfare and Last Attack chime are wired to synthesized sounds")
	_check(b.state == BossBrain.State.WINDUP and b.move == "slam" and events.has("engage") and ctl.has("target") and ctl.has("spd"), "a player on the summit wakes the Guardian: he crouches to leap down (engage, then a telegraphed descent)")
	var seat: Vector3 = boss.global_position
	b._timer = 0.0
	b.tick(0.05, pl)
	_check(boss.global_position.distance_to(seat) > 4.0 and boss.global_position.z > seat.z and b.state == BossBrain.State.RECOVER, "the descent lands him on the arena floor, open to punish")
	_check(b.living_adds() == 2, "his guard steps out on engage: two halberdiers for a lone climber (%d)" % b.living_adds())
	# Bar breaks fire on the hit that crosses the threshold.
	var bar_hp: float = b.bar_hp()
	var adds0: int = b.living_adds()
	boss.take_hit(bar_hp * 0.5, Vector3.FORWARD, 1)
	_check(b.current_bar() == 4 and b.living_adds() == adds0 and not events.has("bar_break"), "chipping inside a bar breaks nothing")
	boss.take_hit(bar_hp * 0.6, Vector3.FORWARD, 1)
	_check(b.current_bar() == 3 and events.has("bar_break") and b.state == BossBrain.State.BREAK and b.stagger_immune(), "crossing the threshold breaks the bar: event and a break beat")
	var n_adds: int = b.living_adds()
	_check(n_adds == adds0 + 2, "a wave of guards answers the bar break (%d alive)" % n_adds)
	var add_names := {}
	for a in b.adds:
		add_names[a.display_name] = true
	_check(add_names.size() == 1 and add_names.has("Kobold Halberdier") and is_equal_approx((b.adds[0] as Enemy).armor, 0.5), "the guard is armored Kobold Halberdiers (%s)" % ", ".join(add_names.keys()))
	var hal: Enemy = b.adds[0]
	var hal_hp: float = hal.hp
	hal.take_hit(10.0, Vector3.FORWARD, 1)
	var plated: float = hal_hp - hal.hp
	hal._stagger = 1.0
	hal_hp = hal.hp
	hal.take_hit(10.0, Vector3.FORWARD, 1)
	_check(is_equal_approx(plated, 5.0) and hal_hp - hal.hp > 10.0, "halberdier plate halves blows until a parry opens it (%.0f vs %.0f)" % [plated, hal_hp - hal.hp])
	hal._stagger = 0.0
	b._spawn_adds(b._add_count(3))
	b._spawn_adds(b._add_count(3))
	_check(b.living_adds() <= 6, "the guard never grows past six (%d)" % b.living_adds())
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
	_check(b._choose(8.0) == "charge" and b._choose(3.0) == "sweep", "move choice: buckler rush at range, cleave up close")
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
	_check(events.has("weapon_swap") and b.swapped, "at the last bar he casts down axe and buckler for the long blade (weapon_swap)")
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
	_check(float(b._ph()["sweep_arc"]) >= 359.0 and str(b._ph()["style"]) == "whirl" and float(b._ph()["chain"]) > 0.0, "the long blade spins a full circle and chains")
	# Leaping smash: from range he lands on the spot the target held.
	b._cooldown = 99.0
	GameState.heal_full()
	pl.global_position = boss.global_position + Vector3(0, 0, 10)
	pl.velocity = Vector3.ZERO
	b._slam_cd = 0.0
	var mark: Vector3 = pl.global_position
	b._begin("slam", pl)
	_check(Vector2(b._slam_at.x - mark.x, b._slam_at.z - mark.z).length() < 0.5 and b._threatened.has(pl), "the leap is marked on the target's spot")
	pl.global_position = mark + Vector3(7, 0, 0)  # step off the mark
	hp0 = GameState.hp
	b._resolve()
	_check(Vector2(boss.global_position.x - mark.x, boss.global_position.z - mark.z).length() < 1.0 and GameState.hp == hp0 and is_equal_approx(b._timer, float(P1["leap"]["recover"])), "he lands where you stood; stepping off dodges, and the landing leaves him open")
	_check(b.pending_hazards() == 0 and not BossBrain.PRESETS["warlord"].has("rockfall"), "no arena hazards: the fight is him and his guard")
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


## Player duels (scripts/duels.gd): the server logic driven directly with two
## fake peers (records + Player nodes), as there is nobody to duel offline.
## SMOKE_ONLY=duels runs just this block.
func _test_duels() -> void:
	print("== Duels (PvP)")
	GameState.floor = 1
	GameState.has_position = false
	GameState.heal_full()
	var keep_duels: Dictionary = GameState.duels.duplicate()
	var world: Node3D = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var D = world._duels
	_check(D != null and D.is_in_group("duels") and D.name == "Duels", "the world carries a Duels node (group 'duels')")
	if D == null:
		world.queue_free()
		return
	D.paused = true
	var Dc = load("res://scripts/duels.gd")
	for m in Dc.MODES:
		_check(not str(Dc.MODES[m]).to_lower().contains("sword art") and not str(Dc.MODES[m]).to_lower().contains("overgeared"), "mode '%s' uses an original name" % m)
	_check(Dc.in_safe_zone(Vector3(0, 0, 10)) and Dc.in_safe_zone(Vector3(-48, 0, 38)) and not Dc.in_safe_zone(Vector3(10, 0, -45)), "town, Hollowbrook and Talven are Inner Areas; the fields are not")
	# Events the server delivers, per peer.
	var events := []
	D.server_event.connect(func(peer, data): events.append([peer, data]))
	var last_ev := func(peer: int, ev: String) -> Dictionary:
		for i in range(events.size() - 1, -1, -1):
			if int(events[i][0]) == peer and str(events[i][1].get("ev", "")) == ev:
				return events[i][1]
		return {}
	# Two fake peers: a record each (the server's HP) and a Player node each
	# (the server's position / parry state), frozen so nothing moves.
	const A := 7201
	const B := 7202
	const C := 7203
	var field := Vector3(10, 1, -45)
	# The duel field sits in wolf country: freeze this world's mobs so a pack
	# never joins the duel (a mob kill ends it and made the suite flaky).
	for e in get_tree().get_nodes_in_group("enemies"):
		if world.is_ancestor_of(e):
			e.process_mode = Node.PROCESS_MODE_DISABLED
	var make := func(peer: int, pname: String, pos: Vector3) -> Player:
		var rec: Dictionary = Net._new_record(Net.sanitize_character({"name": pname}), "0123456789abcdef0123456789abcdef", {})
		Net.srv_records[peer] = rec
		var p := Player.new()
		p.peer_id = peer
		p.appearance = Net.sanitize_character({"name": pname})
		p.position = pos
		p.input_enabled = false
		world._players.add_child(p)
		p.display_name = pname
		p.set_physics_process(false)
		p.srv_attack = 17.0
		return p
	var pa: Player = make.call(A, "Ashe", field)
	var pb: Player = make.call(B, "Bram", field + Vector3(2, 0, 0))
	var pc: Player = make.call(C, "Cass", field + Vector3(0, 0, 2))
	var ra: Dictionary = Net.srv_records[A]
	var rb: Dictionary = Net.srv_records[B]
	var rc: Dictionary = Net.srv_records[C]
	var max_b: float = Net.RecordState.new(rb).max_hp()
	var hp_b := func() -> float: return float(rb["hp"])
	# --- Invites -----------------------------------------------------------------
	_check(D.srv_invite(A, "Ashe").has("error") and D.srv_invite(A, "Nobody").has("error") and D.srv_invite(A, "Bram", "sudden").has("error"), "no duel with yourself, a stranger, or an unknown mode")
	pa.global_position = field + Vector3(40, 0, 0)
	_check(str(D.srv_invite(A, "Bram").get("error", "")).contains("too far"), "the other player must be within %d m" % int(Dc.INVITE_RANGE))
	pa.global_position = field
	var res: Dictionary = D.srv_invite(A, "bram")
	_check(not res.has("error") and res.get("invited") == "Bram" and res.get("mode") == "first" and D.invites.has(B), "a challenge by name (any case) defaults to First Strike")
	_check(last_ev.call(B, "invited").get("from") == "Ashe" and last_ev.call(B, "invited").get("mode") == "first", "the challenged player gets the invite event")
	_check(str(D.srv_invite(C, "Bram").get("error", "")).contains("pending"), "a second challenger waits while one is pending")
	res = D.srv_respond(B, false)
	_check(res.get("op") == "decline" and not D.invites.has(B) and last_ev.call(A, "declined").get("by") == "Bram", "declining clears the invite and tells the challenger")
	_check(D.srv_respond(B, true).has("error"), "nothing to accept after a decline")
	D.srv_invite(A, "Bram")
	D.tick(Dc.INVITE_TTL + 1.0)
	_check(not D.invites.has(B) and not last_ev.call(B, "expired").is_empty() and D.srv_respond(B, true).has("error"), "an unanswered challenge expires after %d s" % int(Dc.INVITE_TTL))
	# --- Accept and countdown --------------------------------------------------------
	D.srv_invite(A, "Bram")
	res = D.srv_respond(B, true)
	var id := int(res.get("duel", 0))
	_check(id > 0 and D.duel_of.get(A) == id and D.duel_of.get(B) == id and D.duels[id]["phase"] == "count", "accepting starts the duel in its countdown")
	_check(last_ev.call(A, "begin").get("opponent") == "Bram" and last_ev.call(B, "begin").get("opponent") == "Ashe" and int(last_ev.call(B, "begin").get("count", 0)) == Dc.COUNTDOWN, "both duelists get the begin event with the opponent and the count")
	_check(D.srv_hit(A, B, -1, Vector3.RIGHT, 1) == "not started", "no blows land during the countdown")
	D.tick(1.05)
	_check(int(last_ev.call(A, "count").get("n", 0)) == Dc.COUNTDOWN - 1 and D.duels[id]["phase"] == "count", "the count ticks down second by second")
	D.tick(float(Dc.COUNTDOWN))
	_check(D.duels[id]["phase"] == "fight" and not last_ev.call(A, "start").is_empty() and not last_ev.call(B, "start").is_empty(), "after %d s: DUEL! (start event to both)" % Dc.COUNTDOWN)
	_check(not last_ev.call(C, "start").is_empty() and bool(last_ev.call(C, "start").get("spectator", false)), "a nearby player sees the duel start as a spectator")
	_check(D.srv_invite(C, "Ashe").has("error") and str(D.srv_invite(A, "Cass").get("error", "")).contains("already"), "duelists can neither be challenged nor challenge")
	# --- Nobody outside the duel gets hurt ---------------------------------------------
	var hp_c0 := float(rc["hp"])
	_check(D.srv_hit(A, C, -1, Vector3.FORWARD, 2) == "not your opponent" and D.srv_hit(C, A, -1, Vector3.FORWARD, 1) == "not duelling", "hits on anyone but the opponent are refused")
	D.tick(Dc.WINDUP + 0.05)
	_check(float(rc["hp"]) == hp_c0 and float(ra["hp"]) == Net.RecordState.new(ra).max_hp(), "a bystander and a non-duelist take no damage")
	_check(D.srv_hit(A, B, 99, Vector3.RIGHT, 3) == "bad kind" and D.srv_hit(A, B, HiddenClasses.KIND_BASE, Vector3.RIGHT, 3) == "bad kind", "unknown kinds and class arts without the class are refused")
	pa.global_position = field + Vector3(-6, 0, 0)
	_check(D.srv_hit(A, B, -1, Vector3.RIGHT, 3) == "out of range", "a swing from too far away is refused")
	pa.global_position = field
	# --- First Strike: a weak hit is not enough, a 5% hit wins ------------------------------
	pa.srv_attack = 3.0
	var hp0: float = hp_b.call()
	_check(D.srv_hit(A, B, -1, Vector3.RIGHT, 4) == "" and D.srv_hit(A, B, -1, Vector3.RIGHT, 4) == "duplicate swing" and hp_b.call() == hp0, "an accepted swing is telegraphed first (no damage yet), and lands once")
	_check(not last_ev.call(B, "incoming").is_empty() and is_equal_approx(float(last_ev.call(B, "incoming")["windup"]), Dc.WINDUP), "the defender is warned of the incoming blow (%.2f s telegraph)" % Dc.WINDUP)
	_check(D.srv_hit(A, B, -1, Vector3.RIGHT, 5) == "cooldown", "the basic attack honours its cooldown between swings (shared table with mob hits)")
	D.tick(Dc.WINDUP + 0.01)
	_check(is_equal_approx(hp_b.call(), hp0 - 3.0) and D.duels.has(id), "a 3-damage hit lands but is too weak for First Strike")
	Enemy._swing_times.erase("%d:-1" % A)
	pa.srv_attack = 20.0
	_check(D.srv_hit(A, B, -1, Vector3.RIGHT, 6) == "", "the next swing is accepted once the cooldown has passed")
	D.tick(Dc.WINDUP + 0.01)
	_check(not D.duels.has(id) and not D.duel_of.has(A) and not D.duel_of.has(B), "a clean hit worth 5% of max HP ends a First Strike duel")
	_check(last_ev.call(A, "end").get("won") == true and last_ev.call(B, "end").get("won") == false and last_ev.call(A, "end").get("reason") == "win", "the winner and loser are told")
	_check(bool(last_ev.call(C, "end").get("spectator", false)) and str(last_ev.call(C, "end").get("text", "")).contains("won the duel"), "nearby players hear the result")
	_check(int(ra["duels"]["won"]) == 1 and int(rb["duels"]["lost"]) == 1 and int(ra["duels"]["lost"]) == 0, "the records tally the win and the loss")
	_check(last_ev.call(B, "end").get("patch") is Dictionary and int(last_ev.call(B, "end")["patch"]["duels"]["lost"]) == 1, "the end event carries the record patch (client tally)")
	var begin := func(mode: String) -> int:
		Enemy._swing_times.clear()
		pa._stun = 0.0
		pb._stun = 0.0
		pb.blocking = false
		pa.global_position = field
		pb.global_position = field + Vector3(2, 0, 0)
		D.srv_invite(A, "Bram", mode)
		var r: Dictionary = D.srv_respond(B, true)
		D.tick(float(Dc.COUNTDOWN) + 0.5)
		return int(r.get("duel", 0))
	var strike := func(attack: float, swing: int) -> String:
		Enemy._swing_times.clear()
		pa.srv_attack = attack
		var why: String = D.srv_hit(A, B, -1, Vector3.RIGHT, swing)
		D.tick(Dc.WINDUP + 0.01)
		return why
	# --- Half ---------------------------------------------------------------------
	Net.RecordState.new(rb).heal_full()
	id = begin.call("half")
	_check(id > 0 and D.duels[id]["mode"] == "half" and D.duels[id]["phase"] == "fight", "a Half duel starts")
	strike.call(max_b * 0.3, 10)
	_check(D.duels.has(id) and hp_b.call() < max_b and hp_b.call() > max_b * 0.5, "30% of max HP in one blow does not end a Half duel")
	strike.call(max_b * 0.3, 11)
	_check(not D.duels.has(id) and hp_b.call() < max_b * 0.5 and int(ra["duels"]["won"]) == 2, "under half HP: the Half duel ends")
	# --- Full ---------------------------------------------------------------------
	Net.RecordState.new(rb).heal_full()
	id = begin.call("full")
	strike.call(max_b * 0.6, 20)
	_check(D.duels.has(id) and hp_b.call() < max_b * 0.5, "a Full duel goes on below half HP")
	strike.call(max_b * 0.6, 21)
	_check(not D.duels.has(id) and is_equal_approx(hp_b.call(), 1.0) and int(rb["duels"]["lost"]) == 3, "a Full duel ends at 1 HP: the loser never dies")
	# --- Parry and guard in PvP ---------------------------------------------------------
	Net.RecordState.new(rb).heal_full()
	id = begin.call("first")
	hp0 = hp_b.call()
	pb.press_parry()
	Enemy._swing_times.clear()
	pa.srv_attack = 20.0
	_check(D.srv_hit(A, B, -1, Vector3.RIGHT, 30) == "", "a swing is accepted while the defender's parry window is open")
	D.tick(Dc.WINDUP + 0.01)
	_check(hp_b.call() == hp0 and D.duels.has(id) and pb.parries >= 1, "a parry inside the window deflects the blow (no damage, duel goes on)")
	_check(pa.is_stunned() and is_equal_approx(float(last_ev.call(A, "parried").get("stun", 0.0)), Dc.PARRY_STUN) and last_ev.call(A, "parried").get("push") is Vector3, "the parried attacker is staggered and shoved back")
	_check(D.srv_hit(A, B, -1, Vector3.RIGHT, 31) == "stunned", "a staggered attacker cannot swing")
	pa._stun = 0.0
	pb.release_parry()
	pb.press_parry()
	# The window closes on the wall clock (headless frames outrun it); holding on is a guard.
	var wait_from := Time.get_ticks_msec()
	while Time.get_ticks_msec() - wait_from < int((Player.PARRY_WINDOW + 0.1) * 1000.0):
		await get_tree().process_frame
	var guard0: float = pb.guard
	_check(strike.call(20.0, 32) == "" and is_equal_approx(hp_b.call(), hp0 - maxf(20.0 * (1.0 - Player.BLOCK_REDUCTION), 1.0)) and pb.guard < guard0, "holding guard after the window blocks: %d%% damage and guard wears down" % int((1.0 - Player.BLOCK_REDUCTION) * 100.0))
	_check(D.duels.has(id), "a blocked hit is not a clean First Strike")
	pb.release_parry()
	pa.global_position = field + Vector3(2, 0, 2)  # square behind: the defender cannot see the attacker
	pb.model.rotation.y = 0.0  # facing -Z; the attacker now stands at +Z
	pb.press_parry()
	var hp1: float = hp_b.call()
	strike.call(3.0, 33)
	_check(hp_b.call() < hp1 and D.duels.has(id), "no parrying blows from behind")
	pb.release_parry()
	D.srv_yield(B)
	_check(not D.duels.has(id) and last_ev.call(A, "end").get("reason") == "yield" and int(ra["duels"]["won"]) == 4, "/duel yield hands the win over")
	# --- Forfeit by range, disconnect, death ----------------------------------------------
	Net.RecordState.new(rb).heal_full()
	id = begin.call("first")
	pb.global_position = field + Vector3(Dc.FORFEIT_RANGE + 2.0, 0, 0)
	D.tick(0.1)
	_check(not D.duels.has(id) and last_ev.call(B, "end").get("reason") == "range" and last_ev.call(B, "end").get("won") == false, "walking %d m away forfeits the duel" % int(Dc.FORFEIT_RANGE))
	id = begin.call("first")
	D.on_peer_left(B)
	_check(not D.duels.has(id) and last_ev.call(A, "end").get("reason") == "left" and last_ev.call(A, "end").get("won") == true, "a disconnect forfeits the duel")
	id = begin.call("first")
	Net._death_grace[B] = Time.get_ticks_msec() + 5000
	D.tick(0.1)
	Net._death_grace.erase(B)
	_check(not D.duels.has(id) and last_ev.call(A, "end").get("reason") == "death", "dying to a monster mid-duel ends it")
	_check(int(ra["duels"]["won"]) == 7 and int(rb["duels"]["lost"]) == 7 and int(rb["duels"]["won"]) == 0, "the tally after every duel: Ashe 7-0, Bram 0-7")
	_check(Net.snapshot_for_client(ra).get("duels", {}).get("won") == 7 and Net.record_defaults().has("duels"), "the tally is a record field that reaches the client")
	# --- Save / patch on the client side -----------------------------------------------
	GameState.duels = {"won": 2, "lost": 1}
	var dd: Dictionary = GameState.to_dict()
	GameState.apply_patch({"duels": {"won": 4, "lost": 1}})
	_check(int(dd["duels"]["won"]) == 2 and int(GameState.duels["won"]) == 4, "the save carries the tally and a server patch updates it")
	GameState.apply_patch({"duels": "junk"})
	_check(int(GameState.duels["won"]) == 4 and GameState._parse_duels({"won": -3}) == {"won": 0, "lost": 0}, "bad tallies are ignored or clamped")
	# --- Chat command offline ---------------------------------------------------------------
	var lines := []
	var sys := func(msg): lines.append(str(msg))
	_check(not Dc.chat_command("/w Bram hi", world.hud, sys) and Dc.chat_command("/duel", world.hud, sys) and lines.size() == 1 and str(lines[0]).begins_with("Duel:"), "/duel alone prints the usage; other commands pass through")
	_check(Dc.chat_command("/duel Bram half", world.hud, sys) and str(lines[-1]).contains("offline"), "offline there is nobody to duel")
	_check(Dc.chat_command("/duel accept", world.hud, sys) and lines.size() == 3, "/duel accept is a duel command too")
	# --- Clean up -----------------------------------------------------------------------
	for peer in [A, B, C]:
		DirAccess.remove_absolute(Net.record_path(str(Net.srv_records[peer]["name"])))  # _end saved them to the server DB
		Net.srv_records.erase(peer)
	Enemy._swing_times.clear()
	pa.queue_free()
	pb.queue_free()
	pc.queue_free()
	GameState.duels = keep_duels
	GameState.heal_full()
	world.queue_free()
	await get_tree().process_frame


## Permadeath climbers (scripts/permadeath.gd): slot rules, boosts and
## penalties, the server-side fall (record, realm, refusal), the monument,
## the stall split and the offline fall in a live world.
func _test_permadeath() -> void:
	print("== Permadeath")
	var keep_char: Dictionary = GameState.character.duplicate()
	GameState.character["name"] = "Tester"
	GameState.character["permadeath"] = false
	GameState.fallen = {}
	# Slots: two standard climbers and one permadeath per account.
	var n := {"exists": true, "permadeath": false}
	var pd := {"exists": true, "permadeath": true}
	var e := {"exists": false}
	var k1: Dictionary = Permadeath.slot_kinds([n, n, e], 2)
	var k2: Dictionary = Permadeath.slot_kinds([pd, e, n], 1)
	var k3: Dictionary = Permadeath.slot_kinds([pd, n, n], 0)
	_check(not k1["normal"] and k1["permadeath"] and k2["normal"] and not k2["permadeath"] and k3["permadeath"] and not k3["normal"],
		"slots: at most %d standard and %d permadeath climber(s); overwriting a slot frees its kind" % [Permadeath.MAX_NORMAL, Permadeath.MAX_PERMADEATH])
	# Boosts and penalties only for the permadeath character.
	_check(Permadeath.xp_gain(GameState, 100) == 100 and is_equal_approx(Permadeath.drop_chance(GameState, 0.5), 0.5), "a standard climber gets no permadeath boost")
	GameState.character["permadeath"] = true
	var xp0 := GameState.xp
	var lv0 := GameState.level
	GameState.add_xp(100)
	_check(Permadeath.xp_gain(GameState, 100) == 115 and (GameState.xp - xp0 == 115 or GameState.level > lv0), "permadeath: +15% EXP")
	_check(is_equal_approx(Permadeath.drop_chance(GameState, 0.5), 0.55) and Permadeath.drop_chance(GameState, 1.0) == 1.0, "permadeath: +10% drop chance (capped at 100%)")
	_check(LifeData.crystal_price("heal_crystal") == 300 and LifeData.crystal_price("teleport_crystal") == 90, "permadeath: Healing Crystals cost double")
	var dsword := {"id": "pd_sword", "name": "Test Blade", "kind": "weapon", "rank": 0, "atk": 5, "def": 0}
	Durability.stamp(dsword)
	GameState.inventory.append(dsword)
	GameState.equipped["weapon"] = dsword
	var d0 := Durability.cur(dsword)
	Durability.wear(GameState, "weapon", 1.0)
	_check(is_equal_approx(d0 - Durability.cur(dsword), Permadeath.WEAR_MULT), "permadeath: gear wears %.1fx faster" % Permadeath.WEAR_MULT)
	GameState.equipped["weapon"] = null
	GameState.inventory.erase(dsword)
	GameState.materials["heal_crystal"] = 2
	GameState.materials["teleport_crystal"] = 1
	Permadeath._last_heal.clear()
	Permadeath._last_hurt.clear()
	GameState.hp = 5.0
	_check(LifeData.use_crystal("heal_crystal") == "", "permadeath: a Healing Crystal works")
	GameState.hp = 5.0
	var cd_msg := LifeData.use_crystal("heal_crystal")
	_check("next Healing Crystal" in cd_msg and int(GameState.materials["heal_crystal"]) == 1, "permadeath: then a %d s cooldown (%s)" % [int(Permadeath.HEAL_CRYSTAL_CD), cd_msg])
	GameState.take_damage(1.0)
	_check("in combat" in LifeData.use_crystal("teleport_crystal") and int(GameState.materials["teleport_crystal"]) == 1, "permadeath: no Teleport Crystal in combat")
	Permadeath._last_hurt.clear()
	Permadeath._last_heal.clear()
	GameState.materials["heal_crystal"] = 0
	GameState.materials["teleport_crystal"] = 0
	GameState.heal_full()
	# Server: the fall is decided and written on the record.
	var rdb = Net.get_realm()
	var prec: Dictionary = Net._new_record(Net.sanitize_character({"name": "Pd Tester"}), "p".repeat(32), {})
	prec["permadeath"] = true
	prec["level"] = 4
	var ph: String = Net.RealmDBScript.holder_of_record(prec)
	rdb.claim("pd_test_item", 1, ph, "item")
	Net.srv_records[7001] = prec
	var fell: bool = Net.srv_damage(7001, 99999.0)
	_check(fell and not (prec["fallen"] as Dictionary).is_empty() and float(prec["hp"]) == 0.0 and int(prec["fallen"]["level"]) == 4, "server: a permadeath record's HP at 0 is a fall (%s)" % Permadeath.fall_text(prec.get("fallen", {})))
	_check(not rdb.is_holder("pd_test_item", ph), "server: the fall frees the climber's realm claims")
	_check(not Net.srv_damage(7001, 10.0) and float(prec["hp"]) == 0.0, "server: a fallen body takes no more hits and never respawns")
	var disk := Net.load_record("Pd Tester")
	_check(not (disk.get("fallen", {}) as Dictionary).is_empty() and "has fallen" in Net.join_refusal(disk), "server: the fall is on disk first, and the name may never join again")
	var nrec: Dictionary = Net._new_record(Net.sanitize_character({"name": "Std Tester"}), "q".repeat(32), {})
	Net.srv_records[7002] = nrec
	Net.srv_damage(7002, 99999.0)
	_check((nrec.get("fallen", {}) as Dictionary).is_empty() and float(nrec["hp"]) > 0.0 and Net.join_refusal(nrec) == "", "server: a standard climber still respawns")
	Net.srv_records.erase(7001)
	Net.srv_records.erase(7002)
	Net._death_grace.erase(7001)
	Net._death_grace.erase(7002)
	DirAccess.remove_absolute(Net.record_path("Pd Tester"))
	DirAccess.remove_absolute(Net.record_path("Std Tester"))
	# Monument: the fallen name is marked; permadeath climbers carry Undying.
	var M = load("res://scripts/monument.gd")
	var mon = M.new()
	mon.entries = [M._entry("Ayla", 9, 0, true, true, {}), M._entry("Brann", 4, 0, false, true, prec["fallen"])]
	var mt: String = mon.text()
	_check("Ayla  ·  Lv 9  ·  Undying" in mt and "† Brann" in mt, "monument: Undying climbers and struck names (%s)" % mt.replace("\n", " | "))
	mon.free()
	# Stalls: permadeath and standard climbers do not trade.
	var S = preload("res://scripts/life/stalls.gd")
	const PDIR := "user://realm_test_pd"
	var srdb = Net.RealmDBScript.open("pd", PDIR)
	var keep := func(_r) -> bool: return true
	var seller: Dictionary = Net._new_record(Net.sanitize_character({"name": "Seller"}), "s".repeat(32), {})
	seller["permadeath"] = true
	seller["money"] = 500
	var sword := {"id": "pd_ware", "name": "Ware", "kind": "weapon", "rank": 0, "atk": 4, "def": 0}
	seller["inventory"].append(sword)
	var srs = Net.RecordState.new(seller)
	S.run(srdb, srs, seller, 0, {"op": "rent"}, keep)
	S.run(srdb, srs, seller, 0, {"op": "stock", "item": "pd_ware", "price": 20}, keep)
	var buyer: Dictionary = Net._new_record(Net.sanitize_character({"name": "Buyer"}), "b".repeat(32), {})
	buyer["money"] = 500
	var bres: Dictionary = S.run(srdb, Net.RecordState.new(buyer), buyer, 0, {"op": "buy", "item": "pd_ware", "price": 20}, keep)
	_check(bres.has("error") and int(buyer["money"]) == 500, "stalls: a permadeath stall does not sell to standard climbers")
	buyer["permadeath"] = true
	bres = S.run(srdb, Net.RecordState.new(buyer), buyer, 0, {"op": "buy", "item": "pd_ware", "price": 20}, keep)
	_check(not bres.has("error") and int(buyer["money"]) == 480, "stalls: but it sells to permadeath climbers")
	srdb.close()
	var dd := DirAccess.open(PDIR)
	if dd != null:
		for f in dd.get_files():
			DirAccess.remove_absolute(PDIR + "/" + f)
	# Offline fall in a live world: the slot becomes a memorial.
	GameState.floor = 1
	GameState.has_position = false
	GameState.heal_full()
	SaveSystem.current_slot = 2
	var w: Node3D = load("res://scenes/world.tscn").instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	Player.menu_after_fall = false
	var pl: Player = w.player
	pl.last_attacker = "Dire Wolf"
	pl.take_damage(99999.0)
	await get_tree().process_frame
	_check(not GameState.fallen.is_empty() and str(GameState.fallen.get("cause", "")) == "Dire Wolf" and pl.is_dying() and not pl.input_enabled, "offline: the permadeath climber falls to the Dire Wolf")
	var ended := false
	for h in get_tree().get_nodes_in_group("hud"):  # earlier test worlds may still hold a HUD
		if h.is_dead_screen() and h._death_label.text == "YOUR JOURNEY HAS ENDED":
			ended = true
	_check(ended, "offline: the journey-ended screen, not the respawn countdown")
	var info := SaveSystem.slot_info(2)
	_check(info["permadeath"] and not (info["fallen"] as Dictionary).is_empty() and not SaveSystem.load_game(2), "offline: the slot is a memorial and refuses to load")
	await get_tree().create_timer(Player.DEATH_SHATTER + Player.DEATH_TIME + 0.5).timeout
	_check(pl.is_dying() and pl.global_position.distance_to(GameState.spawn_point()) > 0.5 or not pl.model.visible, "offline: no respawn after a fall")
	w.queue_free()
	await get_tree().process_frame
	Player.menu_after_fall = true
	SaveSystem.delete_slot(2)
	SaveSystem.current_slot = 0
	GameState.fallen = {}
	GameState.character = keep_char
	GameState.character["permadeath"] = false
	GameState.heal_full()


## Client ms (after its strike opened) where `spec`'s spark is dead centre,
## at least `min_ms` in.
func _perfect_ms(spec: Dictionary, min_ms: int) -> int:
	var period := float(spec["period"])
	var ms := fposmod(float(spec["center"]) * 0.5 - float(spec["phase"]), 1.0) * period
	while ms < float(min_ms):
		ms += period
	return int(round(ms))


## Forging minigame: the server rolls the strikes, grades each one itself and
## only takes strike times that fit their arrival.
func _test_forging(world: Node, vrs, vrec: Dictionary, anvil: Vector3, far: Vector3) -> void:
	print("== Forging minigame (server-graded strikes)")
	var spec := {"center": 0.5, "width": 0.2, "period": 1000, "phase": 0.0}
	_check(Forging.grade(spec, 250.0) == "perfect" and Forging.grade(spec, 750.0) == "perfect" and Forging.grade(spec, 0.0) == "miss" and Forging.grade(spec, 6000.0) == "miss", "heat bar: dead centre is Perfect, the far end and a timed-out strike miss")
	_check(Forging.quality(["perfect", "perfect", "perfect"]) == 1.0 and is_equal_approx(Forging.quality(["good", "miss"]), 0.325), "quality is the strikes' average score")
	_check(Forging.strike_count("Iron Sword") == 3 and Forging.strike_count("Spirit Blade") == 4 and not Forging.uses_minigame("Willow Rod"), "3 strikes, 4 for advanced recipes; tools skip the anvil game")
	var lo := 0
	var hi := 0
	for k in 400:
		lo += Crafting.roll_rank(3, false, 0.0)
		hi += Crafting.roll_rank(3, false, 1.0)
	_check(hi > lo + 60, "better forging rolls higher ranks (%d vs %d over 400)" % [hi, lo])
	_check(Crafting.roll_rank(1, false, 1.0) >= 1, "a flawless forging is never Normal")
	_check(world.srv_action(4343, vrs, "forge_start", {"recipe": "Iron Sword"}, far).has("error"), "forging away from an anvil is refused")
	_check(world.srv_action(4343, vrs, "forge_start", {"recipe": "Willow Rod"}, anvil).has("error"), "tools are not hammered")
	vrs.add_material("iron_ore", 6)
	var open: Dictionary = world.srv_action(4343, vrs, "forge_start", {"recipe": "Iron Sword"}, anvil)
	_check(open.get("specs", []).size() == 3 and vrec.has("_forge") and not Net.snapshot_for_client(vrec).has("_forge"), "forge_start rolls 3 strikes on the record (never sent in snapshots)")
	# A strike claiming a moment that has not happened yet spoils the piece.
	vrec["_forge"]["t0"] = Time.get_ticks_msec() - 300
	_check(world.srv_action(4343, vrs, "forge_strike", {"i": 0, "at": 2000}, anvil).has("error") and not vrec.has("_forge"), "a strike from the future is refused and spoils the session")
	open = world.srv_action(4343, vrs, "forge_start", {"recipe": "Iron Sword"}, anvil)
	vrec["_forge"]["t0"] = Time.get_ticks_msec() - 3000
	_check(world.srv_action(4343, vrs, "forge_strike", {"i": 0, "at": 1500}, anvil).has("error"), "a held-back strike (far older than its arrival) is refused")
	open = world.srv_action(4343, vrs, "forge_start", {"recipe": "Iron Sword"}, anvil)
	_check(world.srv_action(4343, vrs, "forge_strike", {"i": 1, "at": 0}, anvil).has("error"), "out-of-order strikes are refused")
	open = world.srv_action(4343, vrs, "forge_start", {"recipe": "Iron Sword"}, anvil)
	var specs: Array = open["specs"]
	var inv0: int = vrec["inventory"].size()
	var ore0: int = int(vrec["materials"]["iron_ore"])
	var last := 0
	var res: Dictionary = {}
	for i in specs.size():
		var at := last + _perfect_ms(specs[i], Forging.MIN_GAP_MS + 10)
		vrec["_forge"]["t0"] = Time.get_ticks_msec() - at - 60  # arrives 60 ms after the client's strike
		res = world.srv_action(4343, vrs, "forge_strike", {"i": i, "at": at}, anvil)
		if i < specs.size() - 1:
			_check(str(res.get("grade", "")) == "perfect", "strike %d graded Perfect by the server" % (i + 1))
		last = at
	_check(res.has("name") and is_equal_approx(float(res.get("forge_q", 0)), 1.0) and int(res.get("rank", 0)) >= 1 and int(res.get("quality", 0)) == 100, "three Perfect strikes forge a flawless piece (%s)" % str(res.get("name", res)))
	_check(vrec["inventory"].size() == inv0 + 1 and int(vrec["materials"]["iron_ore"]) == ore0 - 3 and not vrec.has("_forge"), "the piece lands on the record, materials spent once, session closed")
	# Missing every strike still forges, at Crude quality.
	open = world.srv_action(4343, vrs, "forge_start", {"recipe": "Iron Sword"}, anvil)
	last = 0
	for i in 3:
		var at := last + int(Forging.STRIKE_WINDOW * 1000.0) + 50
		vrec["_forge"]["t0"] = Time.get_ticks_msec() - at - 60
		res = world.srv_action(4343, vrs, "forge_strike", {"i": i, "at": at}, anvil)
		last = at
	_check(res.has("name") and float(res.get("forge_q", 1)) == 0.0 and res.get("grades", []) == ["miss", "miss", "miss"], "timed-out strikes all miss; the piece still forges, Crude")
	_check(world.srv_action(4343, vrs, "forge_strike", {"i": 0, "at": 400}, anvil).has("error"), "a strike with no session is refused")
	# Local widget: a perfect run reports quality 1.0.
	var fw := ForgeWidget.make()
	add_child(fw)
	var got := [-1.0]
	fw.finished.connect(func(_r, q, _g): got[0] = q)
	fw.begin("Iron Sword", Forging.roll_specs("Iron Sword", 1, false, 7), false)
	_check(Forging.roll_specs("Iron Sword", 1, false, 7) == Forging.roll_specs("Iron Sword", 1, false, 7), "seeded strike specs are deterministic")
	last = 0
	for i in fw.specs.size():
		var at := last + _perfect_ms(fw.specs[i], Forging.MIN_GAP_MS + 30)
		fw._land(at)
		last = at
	_check(is_equal_approx(got[0], 1.0) and fw.is_active(), "anvil widget grades a perfect run 1.0 and holds until the piece is forged")
	fw.queue_free()

