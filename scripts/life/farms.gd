extends Node3D
## Hollowbrook farm field (Floor 1, P8): eight rentable plots in a fenced
## field west of the village, between the cottage and the island's rim.
## A plot is a realm claim (`plot:hb<i>`, cap 1, kind "plot") plus a realm
## container of the same id whose meta holds the renter's display name, the
## rent expiry and the four soil beds:
##   {"crop": id | "", "grown": s, "at": unix, "watered": unix, "planted": unix}
## Growth is never ticked. It is computed from those timestamps whenever
## someone looks (bed_state): a bed grows only while its soil is wet, which
## lasts `dry` seconds after each watering (LifeData.CROPS), so
##   growth(now) = grown + max(0, min(now, watered + dry) - at)
## and watering folds the growth so far into `grown` and restarts the clock.
## A bed that ripens stays ripe; an unripe bed left `wither` seconds without
## water withers and must be cleared. Every change is one journaled meta
## write on the plot container, so the field persists and the server alone
## decides it. Rent is paid through the escrow (record -> `realm:farms`).
##
## Seeds come from the seed cart at the field gate (record-only purchase,
## like Trader Pell's goods). Crops land as stackable materials that the
## cooking recipes in LifeData use (Turnip Soup, Harvest Bread, Honeymelon
## Tart).
##
## Static functions are the server core (offline they run on the local realm
## through Stalls.local_rec / local_persist, the smoke test on a private
## realm). The node draws the field, answers interact prompts and relays the
## farm screen's requests, exactly like scripts/life/stalls.gd.

const Stalls := preload("res://scripts/life/stalls.gd")

const COUNT := 8
const BEDS := 4
const RENT := 60                        # Col per week, paid up front
const RENT_SECS := 7 * 86400
const MAX_WEEKS := 4
const SINK := "realm:farms"
const MAX_SEEDS := 20                    # per purchase
const PLOT_RANGE := 3.0                  # interact distance from a plot's centre
const CART_RANGE := 2.6
## Field centre relative to Hollowbrook's well: west-south-west, clear of the
## house ring (10.5 m), the old vegetable patch, the cottage and the rim.
const FIELD_OFFSET := Vector3(-21, 0, -17)
const PITCH := 4.6                       # plot spacing along a row
const ROW_Z := 3.4                       # rows sit either side of a central aisle
const HALF := 1.8                        # half the side of a plot

static var autosave_offline := true

var world: Node3D
var hud: Node
var plots: Array = []        # [{"pos", "front", "sign": Label3D, "beds": [Node3D x4], "shown": [key x4], "dirt": [Node3D x4]}]
var signs: Array = []        # last sign state per plot: {"owner", "beds": [{"crop", "stage", "dry"}]}
var cart_pos := Vector3.ZERO
var screen = null
var _poll := 0.0
var _sweep_t := 0.0
var _visuals := true


# --- Ids and layout ---------------------------------------------------------------

static func claim_id(i: int) -> String:
	return "plot:hb%d" % i


static func field_center(hollowbrook: Vector3) -> Vector3:
	return hollowbrook + FIELD_OFFSET


## [{"pos", "front", "aisle": +1 | -1}] for the eight plots: two rows of four
## facing a central aisle that runs east to the seed cart and the village.
static func layout(hollowbrook: Vector3) -> Array:
	var c := field_center(hollowbrook)
	var out: Array = []
	for i in COUNT:
		var col := i % 4
		var row := i / 4
		var s := 1.0 if row == 0 else -1.0   # direction from the plot to the aisle (z)
		var pos := c + Vector3((col - 1.5) * PITCH, 0, -s * ROW_Z)
		out.append({"pos": pos, "front": pos + Vector3(0, 0, s * (HALF + 0.5)), "aisle": s})
	return out


static func cart_spot(hollowbrook: Vector3) -> Vector3:
	return field_center(hollowbrook) + Vector3(2 * PITCH + 1.6, 0, 0)


## Local offsets of the four beds inside a plot.
static func bed_offset(b: int) -> Vector3:
	return Vector3(-0.85 if b % 2 == 0 else 0.85, 0, -0.85 if b < 2 else 0.85)


# --- Growth (pure, timestamp based) -------------------------------------------------

static func empty_bed() -> Dictionary:
	return {"crop": "", "grown": 0.0, "at": 0.0, "watered": 0.0, "planted": 0.0}


static func growth(bed: Dictionary, now: float) -> float:
	var crop := str(bed.get("crop", ""))
	if not LifeData.CROPS.has(crop):
		return 0.0
	var dry := float(LifeData.CROPS[crop]["dry"])
	var at := float(bed.get("at", 0.0))
	var wet_until := float(bed.get("watered", 0.0)) + dry
	return float(bed.get("grown", 0.0)) + maxf(0.0, minf(now, wet_until) - at)


## {"stage": "empty"|"seeded"|"sprout"|"growing"|"ripe"|"withered", "progress"
## 0..1, "dry": soil dry now, "left": watered seconds until ripe, "wither_in":
## seconds until an unripe crop dies without water}.
static func bed_state(bed: Dictionary, now: float) -> Dictionary:
	var crop := str(bed.get("crop", ""))
	if not LifeData.CROPS.has(crop):
		return {"stage": "empty", "progress": 0.0, "dry": false, "left": 0.0, "wither_in": 0.0, "crop": ""}
	var d: Dictionary = LifeData.CROPS[crop]
	var g := growth(bed, now)
	var need := float(d["grow"])
	var watered := float(bed.get("watered", 0.0))
	var dry := now - watered >= float(d["dry"])
	var out := {"crop": crop, "progress": clampf(g / need, 0.0, 1.0), "dry": dry, "left": maxf(need - g, 0.0),
		"wither_in": maxf(watered + float(d["wither"]) - now, 0.0)}
	if g >= need:
		out["stage"] = "ripe"
		out["dry"] = false
	elif now - watered > float(d["wither"]):
		out["stage"] = "withered"
	elif g <= 0.0:
		out["stage"] = "seeded"
	elif g / need < 0.4:
		out["stage"] = "sprout"
	else:
		out["stage"] = "growing"
	return out


# --- Server core (realm side) -----------------------------------------------------

static func _now(rdb) -> float:
	return float(rdb.clock.call())


static func _err(text: String) -> Dictionary:
	return {"error": text}


## The plot `holder` rents, or -1.
static func plot_of(rdb, holder: String) -> int:
	if holder == "":
		return -1
	for i in COUNT:
		if rdb.is_holder(claim_id(i), holder) or str(rdb.container(claim_id(i)).get("owner", "")) == holder:
			return i
	return -1


static func meta_of(rdb, i: int) -> Dictionary:
	var m = rdb.container(claim_id(i)).get("meta", {})
	return m if m is Dictionary else {}


static func _free_meta() -> Dictionary:
	var beds: Array = []
	for b in BEDS:
		beds.append(empty_bed())
	return {"owner_name": "", "rent_until": 0.0, "beds": beds}


static func _beds_of(meta: Dictionary) -> Array:
	var beds = meta.get("beds", [])
	if not (beds is Array) or beds.size() != BEDS:
		beds = _free_meta()["beds"]
		meta["beds"] = beds
	return beds


static func _set_meta(rdb, i: int, owner: String, meta: Dictionary) -> void:
	rdb.ensure_container(claim_id(i), owner, "plot", meta)


## Rent expiry and the realm's 30-day inactivity release: the plot opens for
## rent again and its beds are turned over (crops are lost; the screen warns).
## Returns the indices released.
static func sweep(rdb) -> Array:
	var out: Array = []
	if rdb == null:
		return out
	var now := _now(rdb)
	for i in COUNT:
		var c: Dictionary = rdb.container(claim_id(i))
		var owner := str(c.get("owner", ""))
		if c.is_empty() or owner == "":
			continue
		var held: bool = rdb.is_holder(claim_id(i), owner)
		if held and now < float(meta_of(rdb, i).get("rent_until", 0.0)):
			continue
		if held:
			rdb.release(claim_id(i), owner)
		_set_meta(rdb, i, "", _free_meta())
		out.append(i)
		print("[farm] plot %d rent ended for %s" % [i + 1, owner])
	return out


## What a viewer may see of plot `i` (-1 = the seed cart only).
static func view(rdb, gs, i: int, holder: String) -> Dictionary:
	var now := _now(rdb)
	var seeds := {}
	for c in LifeData.CROPS:
		seeds[c] = int(gs.materials.get(LifeData.CROPS[c]["seed"], 0))
	var out := {"plot": i, "my_plot": plot_of(rdb, holder), "rent": RENT, "seeds": seeds, "money": int(gs.money)}
	if i < 0:
		return out
	var c: Dictionary = rdb.container(claim_id(i))
	var owner := str(c.get("owner", ""))
	var meta := meta_of(rdb, i)
	var beds: Array = []
	if owner != "":
		for b in _beds_of(meta.duplicate(true)):
			beds.append(bed_state(b, now))
	out.merge({"free": owner == "", "mine": owner != "" and owner == holder, "owner": str(meta.get("owner_name", "")),
		"left": maxf(float(meta.get("rent_until", 0.0)) - now, 0.0) if owner == holder else 0.0, "beds": beds})
	return out


## Sign / crop-visual state for every plot.
static func sign_state(rdb) -> Array:
	var now := _now(rdb)
	var out: Array = []
	for i in COUNT:
		var c: Dictionary = rdb.container(claim_id(i))
		var owner := str(c.get("owner", ""))
		var meta := meta_of(rdb, i)
		var beds: Array = []
		if owner != "":
			for b in _beds_of(meta.duplicate(true)):
				var st := bed_state(b, now)
				beds.append({"crop": st["crop"], "stage": st["stage"], "dry": st["dry"]})
		out.append({"owner": str(meta.get("owner_name", "")) if owner != "" else "", "beds": beds})
	return out


## Runs one farm operation for the character behind `rec` / `gs`.
## payload: {"op": view|rent|seeds|plant|water|harvest|clear, ...}; `i` is the
## plot (-1 for the seed cart, which only answers view and seeds).
static func run(rdb, gs, rec: Dictionary, i: int, payload: Dictionary, persist: Callable) -> Dictionary:
	if rdb == null:
		return _err("The field ledger is closed.")
	if i < -1 or i >= COUNT:
		return _err("No such plot.")
	sweep(rdb)
	var holder := Stalls.holder_of(rec)
	var op := str(payload.get("op", "view"))
	if i < 0 and not (op in ["view", "seeds"]):
		return _err("Stand at your plot for that.")
	var res: Dictionary = {}
	match op:
		"view":
			pass
		"rent":
			res = _op_rent(rdb, gs, rec, holder, i, persist)
		"seeds":
			res = _op_seeds(gs, rec, str(payload.get("crop", "")), int(payload.get("count", 1)))
		"plant":
			res = _op_plant(rdb, gs, holder, i, int(payload.get("bed", -1)), str(payload.get("crop", "")))
		"water":
			res = _op_water(rdb, holder, i, int(payload.get("bed", -1)))
		"harvest":
			res = _op_harvest(rdb, gs, holder, i, int(payload.get("bed", -1)))
		"clear":
			res = _op_clear(rdb, holder, i, int(payload.get("bed", -1)))
		_:
			return _err("Unknown farm action.")
	if res.has("error"):
		return res
	res["op"] = op
	res["view"] = view(rdb, gs, i, holder)
	res["signs"] = sign_state(rdb)
	return res


static func _mine(rdb, holder: String, i: int) -> bool:
	return holder != "" and str(rdb.container(claim_id(i)).get("owner", "")) == holder and rdb.is_holder(claim_id(i), holder)


static func _op_rent(rdb, gs, rec: Dictionary, holder: String, i: int, persist: Callable) -> Dictionary:
	var mine := plot_of(rdb, holder)
	if mine >= 0 and mine != i:
		return _err("You already rent plot %d. One plot per character." % (mine + 1))
	var owner := str(rdb.container(claim_id(i)).get("owner", ""))
	if owner != "" and owner != holder:
		return _err("%s rents this plot." % str(meta_of(rdb, i).get("owner_name", "Someone")))
	if int(rec.get("money", 0)) < RENT:
		return _err("Not enough Col (%d needed for a week)." % RENT)
	var now := _now(rdb)
	var meta: Dictionary = meta_of(rdb, i).duplicate(true) if owner == holder else _free_meta()
	var until := maxf(float(meta.get("rent_until", 0.0)), now) + RENT_SECS
	if until - now > MAX_WEEKS * RENT_SECS + 1.0:
		return _err("Your rent is already paid %d weeks ahead." % MAX_WEEKS)
	var claimed_now := false
	if not rdb.is_holder(claim_id(i), holder):
		claimed_now = true
		if not rdb.claim(claim_id(i), 1, holder, "plot").get("ok", false):
			return _err("Someone else just took this plot.")
	rdb.ensure_container(SINK, "", "sink")
	var r := Stalls._commit(rdb, gs, rec, [{"col": RENT, "from": "record", "to": SINK}], persist)
	if not r.get("ok", false):
		if claimed_now:
			rdb.release(claim_id(i), holder)
		return _err(str(r.get("error", "The rent could not be paid.")))
	meta["owner_name"] = Stalls.name_of(rec)
	meta["rent_until"] = until
	_beds_of(meta)
	_set_meta(rdb, i, holder, meta)
	return {"rented": i, "renewed": owner == holder, "paid": RENT}


## Seed purchase: record-only (Col off the record, seeds onto it), saved with
## the record like any shop purchase. Money goes through rec so the offline
## proxy record writes it back to GameState.
static func _op_seeds(gs, rec: Dictionary, crop: String, n: int) -> Dictionary:
	if not LifeData.CROPS.has(crop):
		return _err("The cart has no such seed.")
	if n < 1 or n > MAX_SEEDS:
		return _err("Buy between 1 and %d at a time." % MAX_SEEDS)
	var d: Dictionary = LifeData.CROPS[crop]
	var cost := int(d["seed_price"]) * n
	if int(rec.get("money", 0)) < cost:
		return _err("Not enough Col (%d needed)." % cost)
	rec["money"] = int(rec["money"]) - cost
	gs.add_material(str(d["seed"]), n)
	return {"bought": str(d["seed_name"]), "count": n, "cost": cost}


static func _bed_ok(b: int) -> bool:
	return b >= 0 and b < BEDS


static func _op_plant(rdb, gs, holder: String, i: int, b: int, crop: String) -> Dictionary:
	if not _mine(rdb, holder, i):
		return _err("This is not your plot.")
	if not _bed_ok(b):
		return _err("No such bed.")
	if not LifeData.CROPS.has(crop):
		return _err("Unknown seed.")
	var seed := str(LifeData.CROPS[crop]["seed"])
	if int(gs.materials.get(seed, 0)) < 1:
		return _err("You have no %s. The seed cart by the gate sells them." % str(LifeData.CROPS[crop]["seed_name"]))
	var now := _now(rdb)
	var meta: Dictionary = meta_of(rdb, i).duplicate(true)
	var beds := _beds_of(meta)
	var st := bed_state(beds[b], now)
	if st["stage"] == "withered":
		pass  # sowing over a dead bed turns it over first
	elif st["stage"] != "empty":
		return _err("Something already grows there.")
	gs.spend_materials({seed: 1})
	# Fresh seed sits in dry soil: water it to start the growth clock.
	beds[b] = {"crop": crop, "grown": 0.0, "at": now, "watered": now - float(LifeData.CROPS[crop]["dry"]), "planted": now}
	_set_meta(rdb, i, holder, meta)
	return {"planted": crop, "bed": b}


## Waters bed `b`, or every growing bed when b is -1.
static func _op_water(rdb, holder: String, i: int, b: int) -> Dictionary:
	if not _mine(rdb, holder, i):
		return _err("This is not your plot.")
	if b != -1 and not _bed_ok(b):
		return _err("No such bed.")
	var now := _now(rdb)
	var meta: Dictionary = meta_of(rdb, i).duplicate(true)
	var beds := _beds_of(meta)
	var n := 0
	for k in BEDS:
		if b != -1 and k != b:
			continue
		var st := bed_state(beds[k], now)
		if not (st["stage"] in ["seeded", "sprout", "growing"]):
			continue
		var bed: Dictionary = beds[k]
		bed["grown"] = growth(bed, now)
		bed["at"] = now
		bed["watered"] = now
		n += 1
	if n == 0:
		return _err("Nothing there needs water." if b == -1 else "That bed needs no water.")
	_set_meta(rdb, i, holder, meta)
	return {"watered": n}


static func _op_harvest(rdb, gs, holder: String, i: int, b: int) -> Dictionary:
	if not _mine(rdb, holder, i):
		return _err("This is not your plot.")
	var now := _now(rdb)
	var meta: Dictionary = meta_of(rdb, i).duplicate(true)
	var beds := _beds_of(meta)
	var got := {}
	var seeds_back := 0
	for k in BEDS:
		if b != -1 and k != b:
			continue
		var st := bed_state(beds[k], now)
		if st["stage"] != "ripe":
			continue
		var crop := str(st["crop"])
		var y: Array = LifeData.CROPS[crop]["yield"]
		var n := randi_range(int(y[0]), int(y[1]))
		gs.add_material(crop, n)
		got[crop] = int(got.get(crop, 0)) + n
		# A ripe plant sometimes drops a seed of its own.
		if randf() < 0.3:
			gs.add_material(str(LifeData.CROPS[crop]["seed"]), 1)
			seeds_back += 1
		beds[k] = empty_bed()
	if got.is_empty():
		return _err("Nothing is ripe yet." if b == -1 else "That bed is not ripe yet.")
	_set_meta(rdb, i, holder, meta)
	var parts: Array = []
	for c in got:
		parts.append("%d %s" % [got[c], str(LifeData.CROPS[c]["name"])])
	return {"harvested": got, "text": ", ".join(parts), "seeds_back": seeds_back}


static func _op_clear(rdb, holder: String, i: int, b: int) -> Dictionary:
	if not _mine(rdb, holder, i):
		return _err("This is not your plot.")
	if not _bed_ok(b):
		return _err("No such bed.")
	var meta: Dictionary = meta_of(rdb, i).duplicate(true)
	var beds := _beds_of(meta)
	if str(beds[b].get("crop", "")) == "":
		return _err("That bed is already bare.")
	var st := bed_state(beds[b], _now(rdb))
	beds[b] = empty_bed()
	_set_meta(rdb, i, holder, meta)
	return {"cleared": b, "was": st["stage"]}


# --- Offline / listen host ----------------------------------------------------------

static func run_local(i: int, payload: Dictionary) -> Dictionary:
	var rec := Stalls.local_rec()
	var persist := func(r: Dictionary) -> bool:
		return _local_persist(r)
	var res := run(Net.get_realm(), GameState, rec, i, payload, persist)
	if not res.has("error") and str(payload.get("op", "view")) != "view":
		_local_persist(rec)
		# The view was taken before the write-back: money is the proxy's.
		if res.get("view") is Dictionary:
			res["view"]["money"] = GameState.money
	return res


static func _local_persist(rec: Dictionary) -> bool:
	var keep: bool = Stalls.autosave_offline
	Stalls.autosave_offline = autosave_offline and keep
	var ok: bool = Stalls.local_persist(rec)
	Stalls.autosave_offline = keep
	return ok


# --- World node --------------------------------------------------------------------

static func build(w: Node3D, hollowbrook: Vector3) -> Node3D:
	var f = load("res://scripts/life/farms.gd").new()
	f.name = "FarmField"
	f.world = w
	w.add_child(f)
	f._build(hollowbrook)
	return f


func _build(hollowbrook: Vector3) -> void:
	_visuals = not Net.dedicated
	var c := field_center(hollowbrook)
	cart_pos = cart_spot(hollowbrook)
	if world.get("_life_keep") is Array:
		world._life_keep.append([c, 11.5])
		world._life_keep.append([cart_pos, 3.0])
	var ex := 2 * PITCH + 0.2
	var ez := ROW_Z + HALF + 0.8
	var gap := 1.7
	WorldProps.fences(world, [[c + Vector3(-ex, 0, -ez), c + Vector3(ex, 0, -ez)], [c + Vector3(-ex, 0, ez), c + Vector3(ex, 0, ez)],
		[c + Vector3(-ex, 0, -ez), c + Vector3(-ex, 0, -gap)], [c + Vector3(-ex, 0, gap), c + Vector3(-ex, 0, ez)],
		[c + Vector3(ex, 0, -ez), c + Vector3(ex, 0, -gap)], [c + Vector3(ex, 0, gap), c + Vector3(ex, 0, ez)]])
	# Seed cart and a water barrel at the gate toward Hollowbrook.
	var cart_at := cart_pos + Vector3(0.6, 0, 2.6)
	if WorldProps.prop(world, "town", "cart", cart_at, PI * 0.5, WorldProps.TOWN, "box") == null:
		WorldArt.crate(world, cart_at, 0.9, 0.3)
	WorldProps.barrel(world, cart_pos + Vector3(0.4, 0, -2.4), 0.6)
	if WorldProps.prop(world, "survival", "bucket", cart_pos + Vector3(-0.4, 0, -2.0), 0.3, WorldProps.SURVIVAL, "none") == null:
		WorldArt.cyl(world, 0.2, 0.16, 0.3, cart_pos + Vector3(-0.4, 0.15, -2.0), WorldArt.WOOD, 8)
	var cart_sign := _label(cart_pos + Vector3(0.6, 2.6, 2.6), "Seed Cart\nTurnip · Sunwheat · Honeymelon", Color("d8f0a0"), 34)
	world.add_child(cart_sign)
	WorldProps.lantern(world, cart_pos + Vector3(-0.2, 0, 3.6), -PI * 0.5)
	for d in layout(hollowbrook):
		var pos: Vector3 = d["pos"]
		var s: float = d["aisle"]
		var entry := {"pos": pos, "front": d["front"], "beds": [], "dirt": [], "shown": ["", "", "", ""], "wet": [null, null, null, null]}
		# Low timber edging around the plot.
		WorldArt.box(world, Vector3(HALF * 2.0, 0.12, 0.12), pos + Vector3(0, 0.06, -HALF), WorldArt.WOOD, Vector3.ZERO, 0.0)
		WorldArt.box(world, Vector3(HALF * 2.0, 0.12, 0.12), pos + Vector3(0, 0.06, HALF), WorldArt.WOOD, Vector3.ZERO, 0.0)
		WorldArt.box(world, Vector3(0.12, 0.12, HALF * 2.0), pos + Vector3(-HALF, 0.06, 0), WorldArt.WOOD, Vector3.ZERO, 0.0)
		WorldArt.box(world, Vector3(0.12, 0.12, HALF * 2.0), pos + Vector3(HALF, 0.06, 0), WorldArt.WOOD, Vector3.ZERO, 0.0)
		for b in BEDS:
			var dirt := Node3D.new()
			dirt.position = pos + bed_offset(b)
			world.add_child(dirt)
			entry["dirt"].append(dirt)
			var crop := Node3D.new()
			crop.position = pos + bed_offset(b)
			world.add_child(crop)
			entry["beds"].append(crop)
		var post := pos + Vector3(-HALF + 0.2, 0, s * (HALF + 0.35))
		if not WorldProps.signpost(world, post, 0.0 if s > 0 else PI):
			WorldArt.cyl(world, 0.05, 0.07, 1.3, post + Vector3(0, 0.65, 0), WorldArt.WOOD, 6)
			WorldArt.box(world, Vector3(0.8, 0.36, 0.05), post + Vector3(0, 1.15, 0), WorldArt.WOOD_LIGHT)
		var sign := _label(pos + Vector3(0, 2.4, s * (HALF + 0.3)), "Plot %d\nFOR RENT  ·  %d Col / week" % [plots.size() + 1, RENT], Color(1, 0.93, 0.6), 36)
		world.add_child(sign)
		entry["sign"] = sign
		plots.append(entry)
		_show_dirt(plots.size() - 1, false, false)
	if Net.is_authority() or not Net.online:
		_refresh_local_signs()


static func _label(pos: Vector3, text: String, c: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	l.font_size = size
	l.outline_size = 12
	l.modulate = c
	l.outline_modulate = Color(0.12, 0.08, 0.2, 0.9)
	l.pixel_size = 0.005
	l.text = text
	return l


## The soil of a bed: tilled and dark when wet, pale when dry or unrented.
func _show_dirt(k: int, tilled: bool, wet: bool) -> void:
	var e: Dictionary = plots[k]
	for b in BEDS:
		var key = [tilled, wet]
		if e["wet"][b] == key:
			continue
		e["wet"][b] = key
		var n: Node3D = e["dirt"][b]
		for ch in n.get_children():
			ch.queue_free()
		if not _visuals:
			continue
		var tint := Color(0.62, 0.55, 0.5) if wet else (Color.WHITE if tilled else Color(0.85, 0.9, 0.7))
		if WorldProps.live_prop(n, "nature", "crops_dirtSingle", Vector3.ZERO, 0.0, 1.5, "none", tint) == null:
			var col := Color("4a3424") if wet else (Color("7a5a3a") if tilled else Color("8a7a52"))
			WorldArt.box(n, Vector3(1.45, 0.14, 1.45), Vector3(0, 0.07, 0), col, Vector3.ZERO, 0.0)


func _process(delta: float) -> void:
	if not Net.online or Net.is_authority():
		_sweep_t -= delta
		if _sweep_t <= 0.0:
			_sweep_t = 20.0  # also advances the crop visuals (growth is time based)
			var rdb = Net.get_realm()
			if rdb != null:
				sweep(rdb)
				_refresh_local_signs()
		return
	var p = world.get("player")
	if p == null or plots.is_empty():
		return
	_poll -= delta
	if _poll <= 0.0 and (p as Node3D).global_position.distance_to(field_center(world.HOLLOWBROOK)) < 60.0:
		_poll = 12.0
		Net.request_action("farm_signs", {})


func _refresh_local_signs() -> void:
	var rdb = Net.get_realm()
	if rdb != null:
		apply_signs(sign_state(rdb))


func apply_signs(list: Array) -> void:
	signs = list
	for k in mini(list.size(), plots.size()):
		var s: Dictionary = list[k]
		var e: Dictionary = plots[k]
		var owner := str(s.get("owner", ""))
		var lbl: Label3D = e["sign"]
		var beds: Array = s.get("beds", []) if s.get("beds") is Array else []
		if owner == "":
			lbl.text = "Plot %d\nFOR RENT  ·  %d Col / week" % [k + 1, RENT]
			lbl.modulate = Color(1, 0.93, 0.6)
		else:
			var ripe := 0
			var dry := 0
			for b in beds:
				if b is Dictionary:
					ripe += 1 if str(b.get("stage", "")) == "ripe" else 0
					dry += 1 if bool(b.get("dry", false)) and str(b.get("stage", "")) in ["seeded", "sprout", "growing"] else 0
			var line := "%d ripe" % ripe if ripe > 0 else ("%d bed%s thirsty" % [dry, "" if dry == 1 else "s"] if dry > 0 else "tended")
			lbl.text = "%s's Plot\n%s" % [owner, line]
			lbl.modulate = Color("c8f0a0")
		for b in BEDS:
			var st: Dictionary = beds[b] if b < beds.size() and beds[b] is Dictionary else {}
			_show_crop(k, b, str(st.get("crop", "")), str(st.get("stage", "empty")))
		_show_dirt_beds(k, owner != "", beds)


func _show_dirt_beds(k: int, tilled: bool, beds: Array) -> void:
	# One look per plot keeps the node churn low: wet when any bed is wet.
	var wet := false
	for st in beds:
		if st is Dictionary and str(st.get("stage", "")) in ["seeded", "sprout", "growing"] and not bool(st.get("dry", true)):
			wet = true
	_show_dirt(k, tilled, wet)


## Crop model per stage (Kenney Nature Kit crops, primitives as fallback).
func _show_crop(k: int, b: int, crop: String, stage: String) -> void:
	var e: Dictionary = plots[k]
	var key := crop + ":" + stage
	if e["shown"][b] == key:
		return
	e["shown"][b] = key
	var n: Node3D = e["beds"][b]
	for ch in n.get_children():
		ch.queue_free()
	if not _visuals or crop == "" or stage in ["empty", "seeded"]:
		if _visuals and stage == "seeded":
			WorldArt.sphere(n, 0.12, Vector3(0, 0.12, 0), Color("5a4030"))
		return
	var names := {"sprout": "crops_leafsStageA", "growing": "crops_leafsStageB", "withered": "crops_leafsStageA"}
	var ripe_names := {"turnip": "crop_turnip", "sunwheat": "crops_wheatStageB", "honeymelon": "crop_melon"}
	if crop == "sunwheat" and stage == "growing":
		names["growing"] = "crops_wheatStageA"
	var nm: String = ripe_names.get(crop, "crop_turnip") if stage == "ripe" else str(names.get(stage, "crops_leafsStageA"))
	var tint := Color(0.55, 0.4, 0.25) if stage == "withered" else Color.WHITE
	var scl := 1.6 if stage == "ripe" else (1.0 if stage == "sprout" else 1.4)
	if WorldProps.live_prop(n, "nature", nm, Vector3(0, 0.1, 0), float(b) * 1.3, scl, "none", tint) != null:
		return
	var c := Color(LifeData.CROPS[crop]["color"]) if LifeData.CROPS.has(crop) else Color("6fbf5a")
	match stage:
		"sprout":
			WorldArt.sphere(n, 0.16, Vector3(0, 0.22, 0), Color("6fbf5a"))
		"growing":
			WorldArt.cyl(n, 0.04, 0.05, 0.4, Vector3(0, 0.3, 0), Color("4f9a45"), 6)
			WorldArt.sphere(n, 0.28, Vector3(0, 0.5, 0), Color("6fbf5a"))
		"ripe":
			WorldArt.sphere(n, 0.3, Vector3(0, 0.45, 0), Color("5fae4f"))
			WorldArt.sphere(n, 0.26, Vector3(0.18, 0.28, 0.1), c)
		"withered":
			WorldArt.sphere(n, 0.22, Vector3(0, 0.16, 0), Color("7a5e3a"))


## Interact prompt: {"plot": i, "label"} on a plot, {"plot": -1} at the cart.
func nearest(from: Vector3) -> Dictionary:
	if from.distance_to(cart_pos) < CART_RANGE:
		return {"plot": -1, "label": "Buy seeds at the seed cart"}
	var best := {}
	var best_d := PLOT_RANGE
	for k in plots.size():
		var d: float = Vector2(from.x, from.z).distance_to(Vector2(plots[k]["pos"].x, plots[k]["pos"].z))
		if d < best_d:
			best_d = d
			var s: Dictionary = signs[k] if k < signs.size() else {}
			var owner := str(s.get("owner", ""))
			var label := "Rent farm plot %d (%d Col / week)" % [k + 1, RENT]
			if owner != "":
				label = "Tend your plot" if owner == str(GameState.character.get("name", "")) else "Look at %s's plot" % owner
			best = {"plot": k, "label": label}
	return best


## Server: range check, then the core on the record. Kinds "farm" (the
## screen's operations) and "farm_signs" (sign poll, no range check).
func srv(_peer: int, rs, kind: String, payload: Dictionary, pos: Vector3) -> Dictionary:
	var rdb = Net.get_realm()
	if rdb == null:
		return _err("The field ledger is closed.")
	if kind == "farm_signs":
		sweep(rdb)
		return {"signs": sign_state(rdb)}
	var i := int(payload.get("plot", -2))
	if i < -1 or i >= plots.size():
		return _err("No such plot.")
	var ok := false
	if i == -1:
		ok = pos.distance_to(cart_pos) <= CART_RANGE + 1.0 + Net.RANGE_SLACK
	else:
		ok = pos.distance_to(plots[i]["pos"]) <= PLOT_RANGE + 1.0 + Net.RANGE_SLACK
	if not ok:
		return _err("You are not at that plot." if i >= 0 else "You are not at the seed cart.")
	var res := run(rdb, rs, rs.rec, i, payload, func(r): return Net.save_record(r))
	if not res.has("error") and res.has("signs"):
		apply_signs(res["signs"])
	return res


## The farm screen's request: offline / host now, online through the server.
func request(i: int, payload: Dictionary) -> Dictionary:
	var p := payload.duplicate()
	p["plot"] = i
	if Net.remote_client():
		if not Net.request_action("farm", p):
			return {"error": "Slow down a moment."}
		return {"pending": true}
	var res := run_local(i, p)
	if res.has("signs"):
		apply_signs(res["signs"])
	return res


func on_net(kind: String, res: Dictionary) -> void:
	if res.has("signs") and res["signs"] is Array:
		apply_signs(res["signs"])
	if kind == "farm" and screen != null and screen.has_method("show_result"):
		screen.show_result(res)


func open(i: int, h: Node) -> void:
	hud = h
	if h == null or h.get("life") == null or not h.life.has_method("open_farm"):
		return
	screen = h.life.open_farm(self, i)
