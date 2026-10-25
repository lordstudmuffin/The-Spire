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
	f_key.physical_keycode = KEY_F
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
	_check(get_tree().get_nodes_in_group("npcs").size() == 11, "11 NPCs spawned (incl. Old Tam, Trader Pell and the Hollowbrook chain)")
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

	print("== Done: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
