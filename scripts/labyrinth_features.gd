extends Node3D
## Labyrinth terrace features (Floor 1): treasure chests, locked vaults that
## take a Terrace Key, and spike traps.
##
## Chests are per character: each one remembers when this character last
## opened it (record / save key "chests": {chest_id: unix seconds}) and
## refills for them after `respawn` seconds. The server rolls the loot into
## the record, so a client can neither pick its own loot nor open a chest
## twice (the timestamp is written in the same record save as the loot).
## Vaults also consume one Terrace Key (material "terrace_key", dropped by
## the terraces' kobolds) in that same write.
##
## Spike traps run on the shared wall clock (unix time), so every machine
## shows the same cycle without any network traffic; only the authority
## (offline / host / server) deals the damage, once per player per cycle.

const KEY := "terrace_key"
const CHEST_RANGE := 2.4

## lvl = LAB_LEVELS index; off = offset from the terrace centre. "mats" are
## [min, max] per material, "gear" the chance of one piece of gear whose rank
## is rolled in "rank" (Crafting.RANKS index range).
const CHESTS := [
	{"id": "t1_cache", "name": "Weathered Chest", "lvl": 0, "off": Vector3(10.5, 0, 5.0), "locked": false, "respawn": 1800.0,
		"col": [30, 70], "mats": {"iron_ore": [1, 3], "spirit_shard": [0, 1]}, "gear": 0.15, "rank": [0, 1],
		"recipes": ["Iron Sword", "Hide Armor"]},
	{"id": "t1_vault", "name": "Kobold Strongbox", "lvl": 0, "off": Vector3(6.0, 0, -10.5), "locked": true, "respawn": 3600.0,
		"col": [90, 160], "mats": {"spirit_shard": [1, 2], "iron_ore": [2, 3]}, "gear": 0.6, "rank": [1, 2],
		"recipes": ["Iron Sword", "Hide Armor", "Spirit Blade"]},
	{"id": "t2_cache", "name": "Weathered Chest", "lvl": 1, "off": Vector3(-10.5, 0, 5.0), "locked": false, "respawn": 1800.0,
		"col": [50, 100], "mats": {"iron_ore": [2, 3], "spirit_shard": [0, 2]}, "gear": 0.25, "rank": [0, 2],
		"recipes": ["Iron Sword", "Hide Armor", "Spirit Blade"]},
	{"id": "t2_vault", "name": "Sergeant's Coffer", "lvl": 1, "off": Vector3(-6.0, 0, -10.5), "locked": true, "respawn": 3600.0,
		"col": [140, 240], "mats": {"spirit_shard": [2, 3], "beast_hide": [1, 3]}, "gear": 0.85, "rank": [1, 3],
		"recipes": ["Spirit Blade", "Warden Plate"]},
]

## Spike tiles: offsets per terrace. Cycle of PERIOD seconds: resting, then
## WARN seconds of rattling, then UP seconds raised (damage).
const SPIKES := [
	[Vector3(0, 0, 4.5), Vector3(-3.5, 0, -1.0), Vector3(4.0, 0, -2.5)],
	[Vector3(0, 0, 4.5), Vector3(3.5, 0, -1.0), Vector3(-4.0, 0, -2.5)],
]
const PERIOD := 3.4
const WARN := 0.8
const UP := 0.55
const SPIKE_HALF := 1.0   # tiles are 2 x 2 m
const SPIKE_DMG := 14.0

var world: Node3D
var chests: Array = []    # {def, pos, node}
var spikes: Array = []    # {pos, lvl, phase, node, spikes}
var _hit_cycle := {}      # "peer:tile" -> cycle index already hit


static func build(w: Node3D, levels: Array) -> Node3D:
	var n := Node3D.new()
	n.set_script(load("res://scripts/labyrinth_features.gd"))
	n.name = "LabyrinthFeatures"
	w.add_child(n)
	n._build(w, levels)
	return n


func _build(w: Node3D, levels: Array) -> void:
	world = w
	for d in CHESTS:
		var lvl := int(d["lvl"])
		if lvl >= levels.size():
			continue
		var p: Vector3 = levels[lvl] + (d["off"] as Vector3)
		var face := atan2(-(d["off"] as Vector3).x, -(d["off"] as Vector3).z)
		var node := AssetLib.prop(self, "dungeon", "chest_gold" if d["locked"] else "chest", p, face, 1.4, "box", true, Color.WHITE, false)
		if node == null:
			node = _box_chest(p, face, bool(d["locked"]))
		chests.append({"def": d, "pos": p, "node": node})
	for lvl in mini(SPIKES.size(), levels.size()):
		for k in SPIKES[lvl].size():
			var p: Vector3 = levels[lvl] + (SPIKES[lvl][k] as Vector3)
			spikes.append(_build_spike(p, lvl, 0.37 * k + 1.1 * lvl))


func _box_chest(p: Vector3, face: float, locked: bool) -> Node3D:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = face
	add_child(root)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 0.8, 0.8)
	body.mesh = bm
	body.position = Vector3(0, 0.4, 0)
	body.material_override = WorldArt.mat(Color("6b4a2a") if not locked else Color("8a6a2a"), 0.0)
	root.add_child(body)
	return root


func _build_spike(p: Vector3, lvl: int, phase: float) -> Dictionary:
	var root := Node3D.new()
	root.position = p
	add_child(root)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(SPIKE_HALF * 2.0, 0.08, SPIKE_HALF * 2.0)
	plate.mesh = pm
	plate.position = Vector3(0, 0.04, 0)
	plate.material_override = WorldArt.mat(Color("4a4458"), 0.0)
	root.add_child(plate)
	# Spikes: a grid of thin cones that rise out of the plate.
	var tips := Node3D.new()
	tips.position = Vector3(0, -0.5, 0)
	root.add_child(tips)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = 0.6
	cone.radial_segments = 6
	var steel := WorldArt.mat(Color("b8bcc8"), 0.6)
	for ix in 4:
		for iz in 4:
			var m := MeshInstance3D.new()
			m.mesh = cone
			m.material_override = steel
			m.position = Vector3(-0.75 + ix * 0.5, 0.3, -0.75 + iz * 0.5)
			tips.add_child(m)
	return {"pos": p, "lvl": lvl, "phase": phase, "node": root, "tips": tips, "plate": plate}


# --- Spike traps -------------------------------------------------------------

## Where tile `s` is in its cycle at unix time `t`: "rest", "warn" or "up",
## plus the cycle index (one hit per player per cycle).
static func spike_state(s: Dictionary, t: float) -> Array:
	var x := t + float(s["phase"])
	var c := int(floor(x / PERIOD))
	var f := fmod(x, PERIOD)
	if f >= PERIOD - UP:
		return ["up", c]
	if f >= PERIOD - UP - WARN:
		return ["warn", c]
	return ["rest", c]


static func on_tile(s: Dictionary, pos: Vector3) -> bool:
	var d: Vector3 = pos - (s["pos"] as Vector3)
	return absf(d.x) <= SPIKE_HALF and absf(d.z) <= SPIKE_HALF and d.y > -0.5 and d.y < 2.2


func _now() -> float:
	return Time.get_unix_time_from_system()


func _process(_delta: float) -> void:
	var t := _now()
	var me: Node3D = world.get("player") if world else null
	for s in spikes:
		# Only animate tiles near the local player (cheap on big floors).
		if me != null and me.global_position.distance_to(s["pos"]) > 40.0:
			continue
		var st := spike_state(s, t)
		var tips: Node3D = s["tips"]
		match st[0]:
			"up":
				tips.position.y = 0.0
			"warn":
				tips.position.y = -0.45 + 0.04 * sin(t * 60.0)
			_:
				tips.position.y = -0.5
		if st[0] == "warn" and s.get("warned", -1) != st[1] and me != null and me.global_position.distance_to(s["pos"]) < 12.0:
			s["warned"] = st[1]
			Audio.play("skill_charge", s["pos"], 0.15, -10.0, 1.6)


func _physics_process(_delta: float) -> void:
	if not Net.is_authority() or world == null:
		return
	var t := _now()
	var players: Array = get_tree().get_nodes_in_group("players")
	for i in spikes.size():
		var s: Dictionary = spikes[i]
		var st := spike_state(s, t)
		if st[0] != "up":
			continue
		for p in players:
			if not p.visible or (p.has_method("is_dying") and p.is_dying()):
				continue
			var pos: Vector3 = p.srv_position() if Net.online and p.has_method("srv_position") and not p.is_local else p.global_position
			if not on_tile(s, pos):
				continue
			var key := "%d:%d" % [int(p.get("peer_id")), i]
			if int(_hit_cycle.get(key, -1)) == int(st[1]):
				continue
			_hit_cycle[key] = int(st[1])
			hit_player(p)


func hit_player(p: Node3D) -> void:
	if not Net.online or int(p.get("peer_id")) == multiplayer.get_unique_id() or multiplayer.get_peers().has(int(p.get("peer_id"))):
		p.take_damage(SPIKE_DMG)


# --- Chests ------------------------------------------------------------------

func nearest(pos: Vector3) -> Dictionary:
	for i in chests.size():
		var c: Dictionary = chests[i]
		if pos.distance_to(c["pos"]) <= CHEST_RANGE:
			var d: Dictionary = c["def"]
			return {"chest": i, "label": ("Unlock the %s" % d["name"]) if d["locked"] else ("Open the %s" % d["name"])}
	return {}


## Seconds until chest `i` refills for the character in `gs` (0 = ready).
static func refill_left(gs, i: int, now: float) -> float:
	var d: Dictionary = CHESTS[i]
	var opened: Dictionary = gs.get("chests") if gs.get("chests") is Dictionary else {}
	var at := float(opened.get(d["id"], -1e12))
	return maxf(at + float(d["respawn"]) - now, 0.0)


## Opens chest `i` for `gs` (GameState offline / a RecordState on the server):
## checks the refill timer and the key, writes the timestamp and the loot.
static func open_chest(gs, i: int, now: float) -> Dictionary:
	if i < 0 or i >= CHESTS.size():
		return {"error": "No such chest."}
	var d: Dictionary = CHESTS[i]
	var left := refill_left(gs, i, now)
	if left > 0.0:
		return {"error": "Empty. It looks like it will be restocked in about %d min." % int(ceil(left / 60.0))}
	if d["locked"]:
		if not gs.has_materials({KEY: 1}):
			return {"error": "Locked. A Terrace Key would open it; the terraces' kobolds carry them."}
		gs.spend_materials({KEY: 1})
	var opened: Dictionary = (gs.get("chests") as Dictionary).duplicate() if gs.get("chests") is Dictionary else {}
	opened[d["id"]] = now
	gs.set("chests", opened)
	var col := randi_range(int(d["col"][0]), int(d["col"][1]))
	gs.add_money(col)
	var mats := {}
	for m in d["mats"]:
		var r: Array = d["mats"][m]
		var n := randi_range(int(r[0]), int(r[1]))
		if n > 0:
			gs.add_material(m, n)
			mats[m] = n
	var gear := {}
	if randf() < float(d["gear"]):
		var recipes: Array = d["recipes"]
		var rank := randi_range(int(d["rank"][0]), int(d["rank"][1]))
		gear = Crafting.make_item(str(recipes[randi() % recipes.size()]), rank, "")
		gs.add_item(gear)
	return {"chest": i, "col": col, "mats": mats, "gear": gear, "name": str(d["name"])}


static func loot_text(res: Dictionary) -> String:
	var parts: Array = ["%d Col" % int(res.get("col", 0))]
	var mats: Dictionary = res.get("mats", {})
	for m in mats:
		parts.append("%d %s" % [int(mats[m]), str(GameState.MATERIAL_NAMES.get(m, m))])
	var gear: Dictionary = res.get("gear", {})
	if not gear.is_empty():
		parts.append(str(gear.get("name", "gear")))
	return ", ".join(parts)


## Server: the "chest" action.
func srv(_peer: int, rs, payload: Dictionary, pos: Vector3) -> Dictionary:
	var i := int(payload.get("chest", -1))
	if i < 0 or i >= chests.size():
		return {"error": "No such chest."}
	if pos.distance_to(chests[i]["pos"]) > CHEST_RANGE + 1.0 + Net.RANGE_SLACK:
		return {"error": "Too far from the chest."}
	return open_chest(rs, i, _now())


## Interact: offline / host opens now; online asks the server.
func interact(i: int, hud: Node) -> void:
	if Net.remote_client():
		Net.request_action("chest", {"chest": i})
		return
	show_result(open_chest(GameState, i, _now()), hud)


func show_result(res: Dictionary, hud: Node) -> void:
	if hud == null:
		return
	if res.has("error"):
		hud.toast(str(res["error"]))
		Audio.play("ui_error")
		return
	var gear: Dictionary = res.get("gear", {})
	Audio.play("item_rare" if not gear.is_empty() and int(gear.get("rank", 0)) >= 2 else "pickup")
	hud.toast("%s  ·  %s" % [str(res.get("name", "Chest")), loot_text(res)])
	var i := int(res.get("chest", -1))
	if i >= 0 and i < chests.size():
		var fx := VFX.get_for(self)
		if fx and fx.has_method("chest_open"):
			fx.call("chest_open", chests[i]["pos"], int(gear.get("rank", -1)) if not gear.is_empty() else -1)
		elif fx:
			fx.flash(chests[i]["pos"] + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.4), 1.2)
