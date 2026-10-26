class_name Smithy
extends Node3D
## Hollowbrook's forge: the village's own smithy, relit by Elder Wren's ore
## quest and worked by Smith Kesra. Like the tavern, the KayKit blacksmith
## house on the ring gets a door, and the workshop is built inside the
## island's rock at INTERIOR (pads both ways). Inside: a second anvil (Kesra opens the same forge panel
## and minigame as Haldor), the coal forge as light, and the village
## commission board.
##
## Commissions (the smith's job board, after Satisfy's request-driven
## smithing): each shift (Tavern.SHIFT_SECS) three villagers ask for a piece
## of gear at a minimum rank. A smith hands over a forged piece from the pack
## (the lowest-ranked one that qualifies; never a bound limited item) for Col
## and smithing EXP, more for every rank above the minimum. Only CAP smiths
## per commission per server, as realm claims "commission:<shift>:<i>"
## (kind "order"); the first gets +50% and a realm announce.
##
## Action "smithy" {op: view | deliver {i}}, Smithy.run on GameState or the
## record's RecordState; the board range is checked by the caller.

const INTERIOR := Vector3(0, -22, -22)
const ROOM := Vector3(12.0, 4.8, 10.0)
const ANVIL := Vector3(0.8, 0, -1.6)
const KESRA_SPOT := Vector3(-0.4, 0, -2.5)
const BOARD := Vector3(4.4, 0, 1.6)
const FORGE := Vector3(0, 0, -4.2)
const EXIT := Vector3(0, 0, 4.3)
const USE_RANGE := 2.4
const CAP := 3
const FIRST_BONUS := 0.5
const RANK_BONUS := 0.25

## Pool the shift's three commissions are drawn from. `rank` is the minimum.
const POOL := [
	{"recipe": "Hide Armor", "rank": 0, "col": 45, "xp": 25, "for": "Old Tam", "why": "for the cold mornings at the pond"},
	{"recipe": "Iron Sword", "rank": 0, "col": 50, "xp": 25, "for": "Herbalist Hesper", "why": "to clear brambles off the herb patches"},
	{"recipe": "Iron Sword", "rank": 1, "col": 95, "xp": 40, "for": "Trapper Vesna", "why": "the wolves have learned her traps"},
	{"recipe": "Hide Armor", "rank": 1, "col": 85, "xp": 40, "for": "Scout Fen", "why": "something keeps clawing at the waystone road"},
	{"recipe": "Iron Sword", "rank": 2, "col": 170, "xp": 70, "for": "Old Watchman Bram", "why": "his old blade finally snapped"},
	{"recipe": "Warden Plate", "rank": 1, "col": 210, "xp": 90, "for": "Captain Rhys", "why": "a new recruit at the north gate"},
	{"recipe": "Spirit Blade", "rank": 1, "col": 230, "xp": 90, "for": "Innkeeper Rook", "why": "to hang over the hearth, or so he says"},
	{"recipe": "Spirit Blade", "rank": 3, "col": 620, "xp": 220, "for": "Elder Wren", "why": "a gift for whoever clears the tower"},
]


static func commissions_for(shift: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = shift * 6151 + 29
	var idx := range(POOL.size())
	var out := []
	for i in 3:
		var k: int = idx.pop_at(rng.randi_range(0, idx.size() - 1))
		out.append(POOL[k].duplicate())
	return out


static func order_id(shift: int, i: int) -> String:
	return "commission:%d:%d" % [shift, i]


## The lowest-ranked piece in `gs`'s pack that fills commission `c`, or {}.
## Limited (bound) items never count.
static func best_fit(gs, c: Dictionary) -> Dictionary:
	var best := {}
	for it in gs.inventory:
		if not (it is Dictionary) or bool(it.get("limited", false)) or str(it.get("serial", "")) != "":
			continue
		var rank := int(it.get("rank", 0))
		if rank < int(c["rank"]) or str(it.get("name", "")) != "%s %s" % [Crafting.RANKS[rank], c["recipe"]]:
			continue
		if best.is_empty() or rank < int(best.get("rank", 0)):
			best = it
	return best


static func reward(c: Dictionary, rank: int) -> int:
	return int(round(float(c["col"]) * (1.0 + RANK_BONUS * float(rank - int(c["rank"])))))


static func run(rdb, gs, holder: String, payload: Dictionary, at_board: bool, now := -1.0) -> Dictionary:
	var t := Time.get_unix_time_from_system() if now < 0.0 else now
	var shift := Tavern.shift_index(t)
	var op := str(payload.get("op", "view"))
	var res := {}
	match op:
		"view":
			pass
		"deliver":
			if not at_board:
				return {"error": "Bring it to the commission board in Kesra's smithy."}
			if rdb == null or holder == "":
				return {"error": "The commission book is closed."}
			Tavern._forget_old_shifts(rdb, shift, "commission")
			var cs := commissions_for(shift)
			var i := int(payload.get("i", -1))
			if i < 0 or i >= cs.size():
				return {"error": "No such commission."}
			var c: Dictionary = cs[i]
			var oid := order_id(shift, i)
			if rdb.is_holder(oid, holder):
				return {"error": "You already filled that commission this shift."}
			var it := best_fit(gs, c)
			if it.is_empty():
				return {"error": "%s wants a %s of %s rank or better." % [c["for"], c["recipe"], Crafting.RANKS[int(c["rank"])]]}
			var first: bool = rdb.holders(oid).is_empty()
			var cl: Dictionary = rdb.claim(oid, CAP, holder, "order")
			if not bool(cl.get("ok", false)):
				return {"error": "Three smiths beat you to it. Try the next shift."}
			var rank := int(it.get("rank", 0))
			var item_name := str(it.get("name", ""))
			gs.remove_item(str(it.get("id", "")))
			var col := reward(c, rank)
			if first:
				col += int(round(float(col) * FIRST_BONUS))
			gs.add_money(col)
			var up: bool = gs.add_smithing_xp(int(c["xp"]) + 10 * (rank - int(c["rank"])))
			res = {"delivered": i, "item": item_name, "col": col, "first": first, "skill_up": up, "for": c["for"]}
		_:
			return {"error": "Unknown smithy request."}
	res["view"] = view(rdb, holder, gs, t)
	return res


static func view(rdb, holder: String, gs, t: float) -> Dictionary:
	var shift := Tavern.shift_index(t)
	var cs := commissions_for(shift)
	for i in cs.size():
		var hs: Array = rdb.holders(order_id(shift, i)) if rdb != null else []
		cs[i]["left"] = maxi(CAP - hs.size(), 0)
		cs[i]["mine"] = hs.has(holder)
		cs[i]["fit"] = str(best_fit(gs, cs[i]).get("name", ""))
	return {"commissions": cs, "shift_left": Tavern.shift_left(t)}


# --- World node ------------------------------------------------------------------

var world: Node3D
var hud: Node
var screen
var house_pos := Vector3.ZERO
var interior := Vector3.ZERO
var door_pos := Vector3.ZERO
var door_out := Vector3.ZERO
var exit_pos := Vector3.ZERO
var spawn_inside := Vector3.ZERO
var _inside := false
var _outdoor_ambient: Array = []


static func build(w: Node3D, pos: Vector3, face: float, footprint: Vector2) -> Smithy:
	var s := Smithy.new()
	s.name = "Smithy"
	s.world = w
	s.process_priority = 100
	w.add_child(s)
	s.house_pos = pos
	s.interior = INTERIOR
	var fwd := Vector3(sin(face), 0, cos(face))
	s.door_pos = pos + fwd * (footprint.y * 0.5 + 1.2)
	s.door_out = pos + fwd * (footprint.y * 0.5 + 2.6)
	s.exit_pos = s.interior + EXIT
	s.spawn_inside = s.interior + EXIT + Vector3(0, 1, -1.4)
	SmithyArt.build(s, s.interior, ROOM)
	var sign := Label3D.new()
	sign.text = "Hollowbrook Forge"
	sign.font_size = 64
	sign.pixel_size = 0.006
	sign.outline_size = 14
	sign.modulate = Color("ff9a4a")
	sign.outline_modulate = Color(0.12, 0.06, 0.03, 0.95)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.position = s.door_pos + Vector3(0, 3.2, 0) - fwd * 0.6
	s.add_child(sign)
	return s


func at_board(pos: Vector3, slack := 0.0) -> bool:
	return pos.distance_to(interior + BOARD) <= USE_RANGE + slack


func nearest(from: Vector3) -> Dictionary:
	if from.distance_to(interior + BOARD) < USE_RANGE:
		return {"smithy": "board", "label": "Read the village commissions"}
	return {}


func request(payload: Dictionary) -> Dictionary:
	if Net.remote_client():
		if not Net.request_action("smithy", payload):
			return {"error": "Slow down a moment."}
		return {"pending": true}
	var p = world.get("player") if world else null
	var near: bool = p != null and at_board((p as Node3D).global_position)
	return run(Net.get_realm(), GameState, Net.local_holder(), payload, near)


func srv(peer: int, rs, payload: Dictionary, pos: Vector3) -> Dictionary:
	var res := run(Net.get_realm(), rs, Net.srv_holder(peer), payload, at_board(pos, Net.RANGE_SLACK))
	if res.get("first", false):
		Net.srv_announce("%s filled the first commission for %s this shift." % [str(rs.rec.get("name", "Someone")), str(res["for"])])
	return res


func on_net(_kind: String, res: Dictionary) -> void:
	if screen != null and screen.has_method("show_result") and hud != null and hud.life.smithy_open():
		screen.show_result(res)
	elif res.has("error") and hud != null:
		hud.toast(str(res["error"]), "", "", UITheme.ROSE)


func open(h: Node) -> void:
	hud = h
	if h == null or h.get("life") == null:
		return
	screen = h.life.open_smithy(self)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var inside: bool = cam.global_position.distance_to(interior + Vector3(0, 2, 0)) < 8.5
	if inside != _inside:
		_inside = inside
		var we := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we and we.environment:
			var env := we.environment
			if inside:
				_outdoor_ambient = [env.ambient_light_source, env.ambient_light_color, env.reflected_light_source]
				env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				env.ambient_light_color = Color(0.55, 0.45, 0.4)
				env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
			elif not _outdoor_ambient.is_empty():
				env.ambient_light_source = _outdoor_ambient[0]
				env.ambient_light_color = _outdoor_ambient[1]
				env.reflected_light_source = _outdoor_ambient[2]
	if inside:
		for nm in ["Sun", "SkyFill", "Moon"]:
			var l := world.get_node_or_null(nm) as Light3D
			if l:
				l.visible = false


static func result_text(res: Dictionary) -> Array:
	if res.has("delivered"):
		var sub := "+%d Col  ·  Smithing EXP" % int(res["col"])
		if res.get("first", false):
			sub += "  ·  first of the shift"
		return ["%s delivered to %s" % [str(res["item"]), str(res["for"])], sub, "Commission"]
	return []
