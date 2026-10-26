class_name Tavern
extends Node3D
## The Hollow Hearth: Innkeeper Rook's tavern in Hollowbrook (Floor 1). The
## KayKit tavern house on the village ring gets a door; like the cottage, its
## interior is built inside the island's rock (INTERIOR, near the axis where
## the rock is thick: right under a ring house the underside cone cuts into
## the room), and the door and the exit mat are pads the server knows. Rook
## works the bar inside; his minimap dot stays at the house (meta map_pos).
##
## What it is for (Kyle's life-sim list: places players use and keep alive):
## - The counter: hot meals and drinks for Col. A meal is the "tavern_meal"
##   buff (one at a time, it replaces the last). Also a rented room upstairs:
##   full heal and Well Rested, for climbers without a cottage.
## - Kitchen orders: each shift (SHIFT_SECS of real time) Rook posts three
##   orders for dishes players cook (LifeData.RECIPES). Each order takes only
##   ORDER_CAP cooks per server, claimed in the realm DB ("kitchen:<shift>:<i>",
##   kind "order", journaled before anyone is paid), and the first cook gets
##   Rook's thanks on top. Pays Col and cooking EXP.
## - Rumours: one tip per shift, true hints about Floor 1.
## - The hearth: a cooking fire (world._campfires), open to everyone.
##
## Server-authoritative online: action "tavern" {op: view | meal | room |
## order, id / i}. `run` is the one code path, on GameState offline and on
## the record's RecordState on the server; the counter range is checked
## by the caller. Orders and their slots are a pure function of the shift
## index, so the client draws them from the server's view.

## Hall centre (floor level), clear of the cottage at PlayerHome.INTERIOR.
const INTERIOR := Vector3(0, -22, 24)
const ROOM := Vector3(14.0, 4.8, 11.0)
const COUNTER := Vector3(0, 0, -2.6)   # where you stand to order
const ROOK_SPOT := Vector3(0, 0, -4.35)
const BOARD := Vector3(4.6, 0, -2.9)   # kitchen orders board by the bar end
const STAIRS := Vector3(5.6, 0, 2.6)   # "rooms upstairs"
const HEARTH := Vector3(-6.4, 0, -0.4)
const EXIT := Vector3(0, 0, 4.8)
const USE_RANGE := 2.6

const MEALS := {
	"hearth_stew": {"name": "Hearth Stew", "col": 30, "color": "c98a3a", "glyph": "food",
		"buff": {"regen": 1.0, "atk": 0.08, "speed": 0.0, "dur": 240.0},
		"desc": "Rook's own pot, always on the fire. Thick enough to stand a spoon in."},
	"honey_mead": {"name": "Honey Mead", "col": 18, "color": "e8b860", "glyph": "food",
		"buff": {"regen": 0.5, "atk": 0.0, "speed": 0.06, "dur": 180.0},
		"desc": "Golden, sweet and stronger than it tastes. Light on the feet."},
	"rooks_plate": {"name": "Rook's Plate", "col": 65, "color": "ffd27a", "glyph": "food",
		"buff": {"regen": 2.0, "atk": 0.06, "speed": 0.06, "dur": 300.0},
		"desc": "Bread, roast, pickles and a slab of cheese. A climber's supper."},
}
const ROOM_PRICE := 25

## Kitchen orders draw from the dishes a Floor 1 cook can make.
const ORDER_DISHES := ["grilled_trout", "boar_stew", "turnip_soup", "harvest_bread", "melon_tart"]
const ORDERS_PER_SHIFT := 3
const ORDER_CAP := 3
const SHIFT_SECS := 21600
const FIRST_BONUS := 0.5

const RUMOURS := [
	"A grey boar older than the village sleeps in the far south fields. Greytusk, the trappers call him. Whoever lands the last blow walks off in his hide.",
	"The Kobold Warlord sits his throne until someone steps into the ring. They say he comes down off it like a falling bell.",
	"There's a smith, so the story goes, who hammered at the anvil until the metal started talking back. Keep forging and see what you hear.",
	"The old waystones on the way to Talven hum after dark. Wake them all and the watchman will want a word.",
	"Only three of the Warlord's sergeants ever carried that cleaver. Once it's gone, it's gone, until someone stops climbing.",
	"Climbers who swore the one-life oath have their own column on the Monument. A struck name stays struck.",
	"Cook for the room and the room remembers. My orders board fills fast after a shift turns.",
	"The Labyrinth's terraces open to anyone past level five. Bring crystals; the stairs do not care how brave you are.",
]


# --- Shifts and orders (pure) ------------------------------------------------

static func shift_index(t: float) -> int:
	return int(floor(t / float(SHIFT_SECS)))


static func shift_left(t: float) -> int:
	return SHIFT_SECS - int(fposmod(t, float(SHIFT_SECS)))


## Col a portion of `dish` fetches on an order.
static func dish_price(dish: String) -> int:
	return 12 + int(round(float(LifeData.RECIPES[dish]["xp"]) * 1.5))


## The shift's orders: [{dish, qty, col, xp}], the same on every machine.
static func orders_for(shift: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = shift * 7919 + 13
	var pool: Array = ORDER_DISHES.duplicate()
	var out := []
	for i in ORDERS_PER_SHIFT:
		var dish: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var qty := rng.randi_range(1, 2) if int(LifeData.RECIPES[dish].get("level", 1)) >= 2 else rng.randi_range(2, 3)
		out.append({"dish": dish, "qty": qty, "col": dish_price(dish) * qty, "xp": int(LifeData.RECIPES[dish]["xp"]) * 2 * qty})
	return out


static func order_id(shift: int, i: int) -> String:
	return "kitchen:%d:%d" % [shift, i]


static func rumour(shift: int) -> String:
	return RUMOURS[posmod(shift, RUMOURS.size())]


# --- The one code path -------------------------------------------------------

## Runs `payload` for `gs` (GameState offline, a RecordState on the server).
## `holder` is its realm holder key, `at_counter` whether it stands at the
## bar (view works anywhere). Returns the result with a fresh "view".
static func run(rdb, gs, holder: String, payload: Dictionary, at_counter: bool, now := -1.0) -> Dictionary:
	var t := Time.get_unix_time_from_system() if now < 0.0 else now
	var shift := shift_index(t)
	var op := str(payload.get("op", "view"))
	var res := {}
	if op != "view" and not at_counter:
		return {"error": "Step up to Rook's bar first."}
	match op:
		"view":
			pass
		"meal":
			var id := str(payload.get("id", ""))
			if not MEALS.has(id):
				return {"error": "Rook has never heard of that dish."}
			var m: Dictionary = MEALS[id]
			if int(gs.money) < int(m["col"]):
				return {"error": "Not enough Col (%d)." % int(m["col"])}
			gs.add_money(-int(m["col"]))
			var b: Dictionary = m["buff"].duplicate()
			b["name"] = m["name"]
			b["color"] = m["color"]
			gs.add_buff("tavern_meal", float(b["dur"]), b)
			res = {"meal": id, "name": m["name"]}
		"room":
			if int(gs.money) < ROOM_PRICE:
				return {"error": "A room is %d Col a night." % ROOM_PRICE}
			gs.add_money(-ROOM_PRICE)
			gs.heal_full()
			var rb: Dictionary = LifeData.REST_BUFF.duplicate()
			gs.add_buff("rested", float(rb["dur"]), rb)
			res = {"room": true}
		"order":
			if rdb == null or holder == "":
				return {"error": "Rook's order book is closed."}
			_forget_old_shifts(rdb, shift)
			var i := int(payload.get("i", -1))
			var orders := orders_for(shift)
			if i < 0 or i >= orders.size():
				return {"error": "No such order."}
			var o: Dictionary = orders[i]
			var oid := order_id(shift, i)
			if rdb.is_holder(oid, holder):
				return {"error": "You already filled that order this shift."}
			if int(gs.materials.get(o["dish"], 0)) < int(o["qty"]):
				return {"error": "Rook wants %d %s." % [int(o["qty"]), LifeData.RECIPES[o["dish"]]["name"]]}
			var first: bool = rdb.holders(oid).is_empty()
			var cl: Dictionary = rdb.claim(oid, ORDER_CAP, holder, "order")
			if not bool(cl.get("ok", false)):
				return {"error": "Three cooks beat you to that order. Try the next shift."}
			gs.spend_materials({o["dish"]: int(o["qty"])})
			var col := int(o["col"]) + (int(round(float(o["col"]) * FIRST_BONUS)) if first else 0)
			gs.add_money(col)
			var up: bool = gs.add_life_xp("cooking", int(o["xp"]))
			res = {"order": i, "col": col, "first": first, "skill_up": up, "dish": o["dish"], "qty": int(o["qty"])}
		_:
			return {"error": "Unknown tavern request."}
	res["view"] = view(rdb, holder, t)
	return res


## What the screen draws: the menu prices, this shift's orders with slots
## left and whether `holder` filled them, the rumour and the shift clock.
static func view(rdb, holder: String, t: float) -> Dictionary:
	var shift := shift_index(t)
	var orders := orders_for(shift)
	for i in orders.size():
		var oid := order_id(shift, i)
		var hs: Array = rdb.holders(oid) if rdb != null else []
		orders[i]["left"] = maxi(ORDER_CAP - hs.size(), 0)
		orders[i]["mine"] = hs.has(holder)
	return {"orders": orders, "shift_left": shift_left(t), "rumour": rumour(shift), "room": ROOM_PRICE}


## Order claims of earlier shifts are history: let them go so the realm
## file stays small.
static func _forget_old_shifts(rdb, shift: int, prefix := "kitchen") -> void:
	var cur := "%s:%d:" % [prefix, shift]
	for id in rdb.data["claims"].keys():
		var sid := str(id)
		if sid.begins_with(prefix + ":") and not sid.begins_with(cur):
			for h in rdb.holders(sid):
				rdb.release(sid, str(h))
			rdb.data["claims"].erase(sid)


# --- World node -------------------------------------------------------------------

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
const INSIDE_AMBIENT := Color(0.6, 0.5, 0.44)


## `pos` / `face` / `footprint` are the tavern house's (world._build_hollowbrook).
static func build(w: Node3D, pos: Vector3, face: float, footprint: Vector2) -> Tavern:
	var t := Tavern.new()
	t.name = "Tavern"
	t.world = w
	t.process_priority = 100  # after DayNight, like the cottage
	w.add_child(t)
	t.house_pos = pos
	t.interior = INTERIOR
	var fwd := Vector3(sin(face), 0, cos(face))
	t.door_pos = pos + fwd * (footprint.y * 0.5 + 1.2)
	t.door_out = pos + fwd * (footprint.y * 0.5 + 2.6)
	t.exit_pos = t.interior + EXIT
	t.spawn_inside = t.interior + EXIT + Vector3(0, 1, -1.4)
	TavernArt.build(t, t.interior, ROOM)
	t._build_sign(face, fwd)
	return t


func _build_sign(face: float, fwd: Vector3) -> void:
	var s := Label3D.new()
	s.text = "The Hollow Hearth"
	s.font_size = 64
	s.pixel_size = 0.006
	s.outline_size = 14
	s.modulate = Color("f0c060")
	s.outline_modulate = Color(0.12, 0.07, 0.04, 0.95)
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.position = door_pos + Vector3(0, 3.2, 0) - fwd * 0.6
	s.rotation.y = face
	add_child(s)


func counter_pos() -> Vector3:
	return interior + COUNTER


func at_counter(pos: Vector3, slack := 0.0) -> bool:
	for p in [interior + COUNTER, interior + BOARD, interior + STAIRS]:
		if pos.distance_to(p) <= USE_RANGE + slack:
			return true
	return false


## The bar (and its board and the stairs) open the tavern screen.
func nearest(from: Vector3) -> Dictionary:
	if from.distance_to(interior) > 12.0:
		return {}
	var best := {}
	var best_d := 99.0
	for cand in [["counter", COUNTER, "Order at the bar"], ["orders", BOARD, "Read Rook's kitchen orders"], ["rooms", STAIRS, "Rent a room upstairs"]]:
		var d: float = from.distance_to(interior + cand[1])
		if d < USE_RANGE and d < best_d:
			best_d = d
			best = {"tavern": cand[0], "label": cand[2]}
	return best


## Client: run `payload` here (offline / host) or ask the server.
func request(payload: Dictionary) -> Dictionary:
	if Net.remote_client():
		if not Net.request_action("tavern", payload):
			return {"error": "Slow down a moment."}
		return {"pending": true}
	var p = world.get("player") if world else null
	var near: bool = p != null and at_counter((p as Node3D).global_position)
	return run(Net.get_realm(), GameState, Net.local_holder(), payload, near)


## Server: one "tavern" action for `peer`.
func srv(peer: int, rs, payload: Dictionary, pos: Vector3) -> Dictionary:
	var res := run(Net.get_realm(), rs, Net.srv_holder(peer), payload, at_counter(pos, Net.RANGE_SLACK))
	if res.get("first", false):
		Net.srv_announce("%s filled Rook's first %s order of the shift." % [str(rs.rec.get("name", "Someone")), LifeData.RECIPES[res["dish"]]["name"]])
	return res


## Online client: the server's answer.
func on_net(_kind: String, res: Dictionary) -> void:
	if screen != null and screen.has_method("show_result") and hud != null and hud.life.tavern_open():
		screen.show_result(res)
	elif res.has("error") and hud != null:
		hud.toast(str(res["error"]), "", "", UITheme.ROSE)


func open(h: Node, tab: String) -> void:
	hud = h
	if h == null or h.get("life") == null:
		return
	screen = h.life.open_tavern(self, tab)


func _process(_delta: float) -> void:
	_update_interior_light()


## Same rule as the cottage: while this client's camera is in the room the
## sun, sky fill and moon go dark and the ambient turns warm; the fire,
## candles and lamps light the room.
func _update_interior_light() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var inside: bool = cam.global_position.distance_to(interior + Vector3(0, 2, 0)) < 9.5
	if inside != _inside:
		_inside = inside
		var we := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we and we.environment:
			var env := we.environment
			if inside:
				_outdoor_ambient = [env.ambient_light_source, env.ambient_light_color, env.reflected_light_source]
				env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				env.ambient_light_color = INSIDE_AMBIENT
				env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
			elif not _outdoor_ambient.is_empty():
				env.ambient_light_source = _outdoor_ambient[0]
				env.ambient_light_color = _outdoor_ambient[1]
				env.reflected_light_source = _outdoor_ambient[2]
	if not inside:
		return
	for nm in ["Sun", "SkyFill", "Moon"]:
		var l := world.get_node_or_null(nm) as Light3D
		if l:
			l.visible = false


## A line for the result toast.
static func result_text(res: Dictionary) -> Array:
	if res.has("meal"):
		var m: Dictionary = MEALS[res["meal"]]
		return [str(m["name"]), LifeData.buff_text(m["buff"]), "The Hollow Hearth"]
	if res.has("room"):
		return ["A room for the night", "Well Rested: %s" % LifeData.buff_text(LifeData.REST_BUFF), "The Hollow Hearth"]
	if res.has("order"):
		var sub := "+%d Col  ·  Cooking EXP" % int(res["col"])
		if res.get("first", false):
			sub += "  ·  Rook's thanks (first of the shift)"
		return ["Order filled: %d %s" % [int(res.get("qty", 1)), LifeData.RECIPES[res["dish"]]["name"]], sub, "Kitchen order"]
	return []
