extends Node3D
## Hollowbrook market (Floor 1, P7): six rentable player stalls south-east of
## the village well. A stall is a realm claim (`stall:hb<i>`, cap 1, kind
## "stall") plus two realm containers: the stall stock `stall:hb<i>` (its
## meta holds the type, the owner's display name, the rent expiry and the
## price per listing) and the owner's till `till:<holder>` (Col from sales and
## anything returned when the rent runs out). Every move of Col or items is
## one RealmDB.transact() call, so a sale is atomic: buyer Col -> till, the
## ware -> buyer, 5 % market tax till -> `realm:market` (a sink nobody can
## draw from). The stall keeper is simply the market itself: wares stay
## buyable while the owner is offline.
##
## Stackable goods (fish, herbs, ore, cooked dishes) travel as "stack" items
## ({"kind": "stack", "mat", "count"}) because the escrow moves inventory
## items and Col. A stack never stays on a character: it is packed right
## before it leaves the record and unpacked into materials right after it
## arrives (and on record load, see Net._realm_check_record).
##
## A Restaurant stall lists cooked dishes only (LifeData.RECIPES; each one
## carries its timed buff) and shows seating; otherwise it is the same stall.
##
## Static functions are the server-side core (also used offline on the local
## realm through a proxy record over GameState, and by the smoke test on a
## private realm). The node part draws the stalls and signs, answers
## interact prompts and relays the stall screen's requests.
##
## Guild stalls: an Officer or the Leader can rent a stall in the guild's
## name (payload "guild": true). Its owner key is `guildstall:<gid>`, one
## stall per guild, the sign reads "[TAG] Guild Name", any Officer or the
## Leader manages it, and sales (less tax) land in the guild storage at the
## notice board instead of a till. If the guild is gone the stall closes on
## the next sweep and its wares go to that storage.

const COUNT := 6
const RENT := 120                       # Col per week, paid up front
const RENT_SECS := 7 * 86400
const MAX_WEEKS := 4                     # rent can be prepaid this far ahead
const TAX_RATE := 0.05
const MAX_LISTINGS := 12
const MAX_PRICE := 99999
const MAX_STACK := 99
const SINK := "realm:market"
const TYPES := ["shop", "restaurant"]
const USE_RANGE := 2.6
const GUILD_KEY := "guildstall:"
const GUILDS_PATH := "res://scripts/life/guilds.gd"
## Market square: south-east of the well, outside the cottage ring, rows of
## three stalls facing each other across an aisle.
const MARKET_OFFSET := 22.0
const ALONG := 6.5
const AISLE := 4.5

## Smoke tests turn this off so the offline path never writes save slot 0.
static var autosave_offline := true

var world: Node3D
var hud: Node
var stalls: Array = []        # [{"pos", "rot", "front", "sign": Label3D, "seats": Node3D, "wares": Node3D}]
var signs: Array = []         # last sign state: [{"owner", "type", "n"}]
var screen = null             # the StallScreen while open (LifeHUD owns it)
var _poll := 0.0
var _sweep_t := 0.0


# --- Ids and layout ---------------------------------------------------------------

static func claim_id(i: int) -> String:
	return "stall:hb%d" % i


static func stock_id(i: int) -> String:
	return "stall:hb%d" % i


static func till_id(holder: String) -> String:
	return "till:" + holder


## Owner key of the stall rented in guild `gid`'s name.
static func guild_key(gid: String) -> String:
	return GUILD_KEY + gid


## The guild id behind a stall owner key, or "" for a character's stall.
static func gid_of_owner(owner: String) -> String:
	return owner.trim_prefix(GUILD_KEY) if owner.begins_with(GUILD_KEY) else ""


## guilds.gd preloads this script, so it is loaded at call time here.
static func _guilds() -> Script:
	return load(GUILDS_PATH)


static func guild_officer(rdb, holder: String, gid: String) -> bool:
	var g := _guilds()
	return gid != "" and g.guild_of(rdb, holder) == gid and g.rank_value(g.rank_of(rdb, holder)) >= g.rank_value("officer")


## Who `holder` acts as at stall `i`: the guild key when the stall is their
## guild's and they are an Officer or the Leader, else themselves.
static func actor_for(rdb, holder: String, i: int) -> String:
	var owner := str(rdb.container(stock_id(i)).get("owner", ""))
	return owner if guild_officer(rdb, holder, gid_of_owner(owner)) else holder


## Where an owner's sales go: a character's till, or the guild storage.
static func till_for(owner: String) -> String:
	var gid := gid_of_owner(owner)
	return _guilds().storage_id(gid) if gid != "" else till_id(owner)


static func _ensure_till(rdb, owner: String) -> String:
	var t := till_for(owner)
	var gid := gid_of_owner(owner)
	if gid == "":
		rdb.ensure_container(t, owner, "till")
	elif rdb.container(t).is_empty():
		rdb.ensure_container(t, "", "guild", {"gid": gid})
	return t


static func market_center(hollowbrook: Vector3) -> Vector3:
	return hollowbrook + Vector3(11, 0, 17).normalized() * MARKET_OFFSET


## [{"pos", "rot", "front"}] for the six stalls (deterministic, so the server
## range-checks against the same spots every client draws).
static func layout(hollowbrook: Vector3) -> Array:
	var c := market_center(hollowbrook)
	var u := Vector3(11, 0, 17).normalized()
	var v := Vector3(u.z, 0, -u.x)
	var out: Array = []
	for k in COUNT:
		var side := 1.0 if k < 3 else -1.0
		var along := (float(k % 3) - 1.0) * ALONG * side
		var pos := c + u * along + v * (AISLE * side)
		var fwd := -v * side
		out.append({"pos": pos, "rot": atan2(fwd.x, fwd.z), "front": pos + fwd * 1.9})
	return out


# --- Server core (realm side) -----------------------------------------------------

static func _now(rdb) -> float:
	return float(rdb.clock.call())


static func holder_of(rec: Dictionary) -> String:
	return Net.RealmDBScript.holder_of_record(rec)


static func name_of(rec: Dictionary) -> String:
	return str(rec.get("name", rec.get("character", {}).get("name", "Someone")))


## The stall `holder` rents, or -1.
static func stall_of(rdb, holder: String) -> int:
	for i in COUNT:
		if rdb.is_holder(claim_id(i), holder):
			return i
		if str(rdb.container(stock_id(i)).get("owner", "")) == holder:
			return i
	return -1


static func meta_of(rdb, i: int) -> Dictionary:
	var c: Dictionary = rdb.container(stock_id(i))
	var m = c.get("meta", {})
	return m if m is Dictionary else {}


static func _free_meta() -> Dictionary:
	return {"type": "shop", "owner_name": "", "rent_until": 0.0, "prices": {}}


static func _set_meta(rdb, i: int, owner: String, meta: Dictionary) -> void:
	rdb.ensure_container(stock_id(i), owner, "stall", meta)


## Rent expiry and inactivity: a stall whose rent ran out or whose claim the
## realm released (30 days away) returns every ware to the owner's till and
## opens for rent again. Run before every stall action and on a timer.
## Returns the indices released.
static func sweep(rdb) -> Array:
	var out: Array = []
	if rdb == null:
		return out
	var now := _now(rdb)
	for i in COUNT:
		var c: Dictionary = rdb.container(stock_id(i))
		if c.is_empty():
			continue
		var owner := str(c.get("owner", ""))
		if owner == "":
			continue
		var held: bool = rdb.is_holder(claim_id(i), owner)
		var until := float(meta_of(rdb, i).get("rent_until", 0.0))
		var gid := gid_of_owner(owner)
		if held and now < until and (gid == "" or not _guilds().get_guild(rdb, gid).is_empty()):
			continue
		var till := _ensure_till(rdb, owner)
		var room: int = Net.RealmDBScript.MAX_CONTAINER_ITEMS - (rdb.container(till).get("items", []) as Array).size()
		var moves: Array = []
		for it in c.get("items", []):
			if moves.size() < room:
				moves.append({"item": str(it.get("id", "")), "from": stock_id(i), "to": till})
		if int(c.get("col", 0)) > 0:
			moves.append({"col": int(c["col"]), "from": stock_id(i), "to": till})
		if not moves.is_empty():
			var r: Dictionary = rdb.transact({}, moves)
			if r.get("ok", false):
				rdb.settle(int(r["seq"]))
		if held:
			rdb.release(claim_id(i), owner)
		if (rdb.container(stock_id(i)).get("items", []) as Array).is_empty():
			_set_meta(rdb, i, "", _free_meta())
			out.append(i)
			print("[market] stall %d rent ended for %s; wares returned to the till" % [i + 1, owner])
	return out


## Suggested asking price (also used when a listing lost its price).
static func suggest_price(item: Dictionary) -> int:
	if str(item.get("kind", "")) == "stack":
		var m := str(item.get("mat", ""))
		var each := 8
		if LifeData.RECIPES.has(m):
			each = 25 + int(LifeData.RECIPES[m]["xp"])
		elif LifeData.FISH.has(m):
			each = 6 + 10 * int(LifeData.FISH[m]["rarity"]) * int(LifeData.FISH[m]["rarity"]) + 4
		elif m == "spirit_shard" or m == "wisp_essence":
			each = 30
		elif m == "willow_rod":
			each = 35
		return maxi(each * int(item.get("count", 1)), 1)
	return 30 + int(item.get("atk", 0)) * 8 + int(item.get("def", 0)) * 8 + int(item.get("rank", 0)) * 40


static func item_name(item: Dictionary) -> String:
	if str(item.get("kind", "")) == "stack":
		var m := str(item.get("mat", ""))
		return "%s x%d" % [GameState.MATERIAL_NAMES.get(m, m), int(item.get("count", 1))]
	return str(item.get("name", "Item"))


## One stack item taken from the materials of `gs` (RecordState or GameState).
static func make_stack(mat: String, count: int) -> Dictionary:
	return {"id": "stk_%d_%d" % [Time.get_ticks_usec(), randi() % 100000], "kind": "stack", "mat": mat, "count": count,
		"name": "%s x%d" % [GameState.MATERIAL_NAMES.get(mat, mat), count]}


## Turns every stack item in `rec`'s inventory back into materials (through
## `gs` so gather quests follow; straight into rec.materials when gs is null).
## Returns true when anything was unpacked.
static func unpack_stacks(rec: Dictionary, gs = null) -> bool:
	var inv = rec.get("inventory")
	if not (inv is Array):
		return false
	var any := false
	for k in range(inv.size() - 1, -1, -1):
		var it = inv[k]
		if it is Dictionary and str(it.get("kind", "")) == "stack":
			inv.remove_at(k)
			var m := str(it.get("mat", ""))
			var n := clampi(int(it.get("count", 0)), 0, MAX_STACK)
			if GameState.MATERIAL_NAMES.has(m) and n > 0:
				if gs != null:
					gs.add_material(m, n)
				else:
					if not (rec.get("materials") is Dictionary):
						rec["materials"] = {}
					rec["materials"][m] = int(rec["materials"].get(m, 0)) + n
			any = true
	return any


static func _find(items: Array, id: String) -> int:
	for k in items.size():
		if items[k] is Dictionary and str(items[k].get("id", "")) == id:
			return k
	return -1


## transact + unpack + persist + settle. `persist(rec) -> bool` saves the
## record side (Net.save_record on the server, GameState write-back offline).
static func _commit(rdb, gs, rec: Dictionary, moves: Array, persist: Callable) -> Dictionary:
	var r: Dictionary = rdb.transact(rec, moves)
	if not r.get("ok", false):
		return r
	unpack_stacks(rec, gs)
	if gs != null and gs != GameState and gs.has_method("_sync_weapon"):
		gs._sync_weapon()
	if persist.call(rec):
		rdb.settle(int(r["seq"]))
	return r


static func _err(text: String) -> Dictionary:
	return {"error": text}


static func _price_ok(p: int) -> bool:
	return p >= 1 and p <= MAX_PRICE


## What a viewer may see of stall `i` (no holder keys leave the server).
static func view(rdb, i: int, holder: String) -> Dictionary:
	var c: Dictionary = rdb.container(stock_id(i))
	var owner := str(c.get("owner", ""))
	var meta := meta_of(rdb, i)
	var prices: Dictionary = meta.get("prices", {}) if meta.get("prices") is Dictionary else {}
	var rows: Array = []
	for it in c.get("items", []):
		if not (it is Dictionary):
			continue
		var id := str(it.get("id", ""))
		var row := {"id": id, "name": item_name(it), "kind": str(it.get("kind", "")), "price": int(prices.get(id, suggest_price(it)))}
		for k in ["mat", "count", "rank", "atk", "def"]:
			if it.has(k):
				row[k] = it[k]
		rows.append(row)
	var till: Dictionary = rdb.container(till_id(holder)) if holder != "" else {}
	var till_items: Array = []
	for it in till.get("items", []):
		if it is Dictionary:
			till_items.append(item_name(it))
	var now := _now(rdb)
	var mine := owner != "" and owner == actor_for(rdb, holder, i)
	var my_gid: String = _guilds().guild_of(rdb, holder) if holder != "" else ""
	var officer := guild_officer(rdb, holder, my_gid)
	var out := {"stall": i, "free": owner == "", "mine": mine, "owner": str(meta.get("owner_name", "")),
		"type": str(meta.get("type", "shop")), "left": maxf(float(meta.get("rent_until", 0.0)) - now, 0.0) if mine else 0.0,
		"listings": rows, "my_stall": stall_of(rdb, holder), "hardcore": bool(meta.get("hardcore", false)), "till_col": int(till.get("col", 0)), "till_items": till_items,
		"rent": RENT, "tax": TAX_RATE, "max_listings": MAX_LISTINGS, "guild_owned": gid_of_owner(owner) != "",
		"guild_officer": officer, "guild_stall": stall_of(rdb, guild_key(my_gid)) if officer else -1}
	if officer:
		out["guild_tag"] = str(_guilds().get_guild(rdb, my_gid).get("tag", ""))
	if mine and gid_of_owner(owner) != "":
		out["guild_col"] = int(rdb.container(till_for(owner)).get("col", 0))
	return out


## Sign state for every stall: [{"owner", "type", "n"}].
static func sign_state(rdb) -> Array:
	var out: Array = []
	for i in COUNT:
		var c: Dictionary = rdb.container(stock_id(i))
		var m := meta_of(rdb, i)
		out.append({"owner": str(m.get("owner_name", "")) if str(c.get("owner", "")) != "" else "", "type": str(m.get("type", "shop")),
			"n": (c.get("items", []) as Array).size()})
	return out


## Runs one stall operation for the character behind `rec` / `gs`.
## payload: {"op": view|rent|type|stock|price|withdraw|collect|buy, ...}.
## Returns the result plus a fresh "view" (and "signs") or {"error"}.
static func run(rdb, gs, rec: Dictionary, i: int, payload: Dictionary, persist: Callable) -> Dictionary:
	if rdb == null:
		return _err("The market ledger is closed.")
	if i < 0 or i >= COUNT:
		return _err("No such stall.")
	sweep(rdb)
	var holder := holder_of(rec)
	var op := str(payload.get("op", "view"))
	# `actor` is the owner key this character manages the stall as.
	var actor := actor_for(rdb, holder, i)
	if op == "rent" and bool(payload.get("guild", false)) and actor == holder:
		var gid: String = _guilds().guild_of(rdb, holder)
		if gid == "":
			return _err("You are not in a guild.")
		if not guild_officer(rdb, holder, gid):
			return _err("Only Officers and the Leader may rent a stall for the guild.")
		actor = guild_key(gid)
	if actor != holder:
		rdb.touch(actor)
	var res: Dictionary = {}
	match op:
		"view":
			pass
		"rent":
			res = _op_rent(rdb, gs, rec, actor, i, payload, persist)
		"type":
			res = _op_type(rdb, actor, i, str(payload.get("type", "shop")))
		"stock":
			res = _op_stock(rdb, gs, rec, actor, i, payload, persist)
		"price":
			res = _op_price(rdb, actor, i, str(payload.get("item", "")), int(payload.get("price", 0)))
		"withdraw":
			res = _op_withdraw(rdb, gs, rec, actor, i, str(payload.get("item", "")), persist)
		"collect":
			res = _op_collect(rdb, gs, rec, holder, persist)
		"buy":
			res = _op_buy(rdb, gs, rec, actor, i, payload, persist)
		_:
			return _err("Unknown stall action.")
	if res.has("error"):
		return res
	res["op"] = op
	res["view"] = view(rdb, i, holder)
	res["signs"] = sign_state(rdb)
	return res


static func _owner_ok(rdb, holder: String, i: int) -> bool:
	return holder != "" and str(rdb.container(stock_id(i)).get("owner", "")) == holder


static func _op_rent(rdb, gs, rec: Dictionary, holder: String, i: int, payload: Dictionary, persist: Callable) -> Dictionary:
	var mine := stall_of(rdb, holder)
	var gid := gid_of_owner(holder)
	if mine >= 0 and mine != i:
		return _err(("Your guild already rents stall %d. One stall per guild." if gid != "" else "You already rent stall %d. One stall per character.") % (mine + 1))
	var owner := str(rdb.container(stock_id(i)).get("owner", ""))
	if owner != "" and owner != holder:
		return _err("%s rents this stall." % str(meta_of(rdb, i).get("owner_name", "Someone")))
	if int(rec.get("money", 0)) < RENT:
		return _err("Not enough Col (%d needed for a week)." % RENT)
	var now := _now(rdb)
	var meta: Dictionary = meta_of(rdb, i).duplicate(true) if owner == holder else _free_meta()
	var until := maxf(float(meta.get("rent_until", 0.0)), now) + RENT_SECS
	if until - now > MAX_WEEKS * RENT_SECS + 1.0:
		return _err("Your rent is already paid %d weeks ahead." % MAX_WEEKS)
	var fresh := owner == ""
	var claimed_now := false
	if not rdb.is_holder(claim_id(i), holder):
		claimed_now = true
		var cl: Dictionary = rdb.claim(claim_id(i), 1, holder, "stall")
		if not cl.get("ok", false):
			return _err("Someone else just took this stall.")
	rdb.ensure_container(SINK, "", "sink")
	var r := _commit(rdb, gs, rec, [{"col": RENT, "from": "record", "to": SINK}], persist)
	if not r.get("ok", false):
		if claimed_now:
			rdb.release(claim_id(i), holder)
		return _err(str(r.get("error", "The rent could not be paid.")))
	var t := str(payload.get("type", meta.get("type", "shop")))
	meta["type"] = t if TYPES.has(t) else "shop"
	if gid != "":
		var g: Dictionary = _guilds().get_guild(rdb, gid)
		meta["owner_name"] = "[%s] %s" % [str(g.get("tag", "")), str(g.get("name", "Guild"))]
		meta["guild"] = gid
	else:
		meta["owner_name"] = name_of(rec)
	meta["rent_until"] = until
	if fresh:
		meta["hardcore"] = Permadeath.rec_on(rec)  # permadeath stalls trade only with permadeath climbers
	if not (meta.get("prices") is Dictionary):
		meta["prices"] = {}
	_set_meta(rdb, i, holder, meta)
	_ensure_till(rdb, holder)
	return {"rented": i, "renewed": not fresh, "paid": RENT, "guild": gid != ""}


static func _op_type(rdb, holder: String, i: int, t: String) -> Dictionary:
	if not _owner_ok(rdb, holder, i):
		return _err("This is not your stall.")
	if not TYPES.has(t):
		return _err("Unknown stall type.")
	if t == "restaurant":
		for it in rdb.container(stock_id(i)).get("items", []):
			if str(it.get("kind", "")) != "stack" or not LifeData.RECIPES.has(str(it.get("mat", ""))):
				return _err("A restaurant sells cooked dishes only. Withdraw the other wares first.")
	var meta: Dictionary = meta_of(rdb, i).duplicate(true)
	meta["type"] = t
	_set_meta(rdb, i, holder, meta)
	return {"type": t}


static func _op_stock(rdb, gs, rec: Dictionary, holder: String, i: int, payload: Dictionary, persist: Callable) -> Dictionary:
	if not _owner_ok(rdb, holder, i):
		return _err("This is not your stall.")
	if not rdb.is_holder(claim_id(i), holder):
		return _err("Your rent has run out.")
	var cont: Dictionary = rdb.container(stock_id(i))
	if (cont.get("items", []) as Array).size() >= MAX_LISTINGS:
		return _err("The stall is full (%d wares)." % MAX_LISTINGS)
	var price := int(payload.get("price", 0))
	if not _price_ok(price):
		return _err("Set a price between 1 and %d Col." % MAX_PRICE)
	var meta: Dictionary = meta_of(rdb, i).duplicate(true)
	var restaurant := str(meta.get("type", "shop")) == "restaurant"
	var list_id := ""
	var nm := ""
	if payload.has("mat"):
		var m := str(payload["mat"])
		var n := int(payload.get("count", 1))
		if not GameState.MATERIAL_NAMES.has(m):
			return _err("You cannot sell that.")
		if restaurant and not LifeData.RECIPES.has(m):
			return _err("A restaurant sells cooked dishes only.")
		if n < 1 or n > MAX_STACK or int(gs.materials.get(m, 0)) < n:
			return _err("You do not carry that many.")
		# Pack, persist the packed record (a crash now unpacks it on load),
		# then move the stack out in one transaction.
		var stack := make_stack(m, n)
		gs.spend_materials({m: n})
		rec["inventory"].append(stack)
		var durable: bool = gs != GameState
		if durable:
			persist.call(rec)
		var r := _commit(rdb, gs, rec, [{"item": stack["id"], "from": "record", "to": stock_id(i)}], persist)
		if not r.get("ok", false):
			unpack_stacks(rec, gs)
			if durable:
				persist.call(rec)
			return _err(str(r.get("error", "Refused.")))
		list_id = stack["id"]
		nm = item_name(stack)
	else:
		var id := str(payload.get("item", ""))
		var k := _find(rec.get("inventory", []), id)
		if k < 0:
			return _err("You do not carry that item.")
		var it: Dictionary = rec["inventory"][k]
		if restaurant:
			return _err("A restaurant sells cooked dishes only.")
		if bool(it.get("bound", false)) or rdb.is_bound(it):
			return _err("That item is bound to you and cannot be sold.")
		if not (str(it.get("kind", "")) in ["weapon", "armor"]):
			return _err("You cannot sell that.")
		nm = str(it.get("name", "Item"))
		var r := _commit(rdb, gs, rec, [{"item": id, "from": "record", "to": stock_id(i)}], persist)
		if not r.get("ok", false):
			return _err(str(r.get("error", "Refused.")))
		list_id = id
	if not (meta.get("prices") is Dictionary):
		meta["prices"] = {}
	meta["prices"][list_id] = price
	_set_meta(rdb, i, holder, meta)
	return {"stocked": nm, "price": price, "item": list_id}


static func _op_price(rdb, holder: String, i: int, id: String, price: int) -> Dictionary:
	if not _owner_ok(rdb, holder, i):
		return _err("This is not your stall.")
	if _find(rdb.container(stock_id(i)).get("items", []), id) < 0:
		return _err("No such ware.")
	if not _price_ok(price):
		return _err("Set a price between 1 and %d Col." % MAX_PRICE)
	var meta: Dictionary = meta_of(rdb, i).duplicate(true)
	if not (meta.get("prices") is Dictionary):
		meta["prices"] = {}
	meta["prices"][id] = price
	_set_meta(rdb, i, holder, meta)
	return {"item": id, "price": price}


static func _drop_price(rdb, i: int, owner: String, id: String) -> void:
	var meta: Dictionary = meta_of(rdb, i).duplicate(true)
	if meta.get("prices") is Dictionary and meta["prices"].has(id):
		meta["prices"].erase(id)
		_set_meta(rdb, i, owner, meta)


static func _op_withdraw(rdb, gs, rec: Dictionary, holder: String, i: int, id: String, persist: Callable) -> Dictionary:
	if not _owner_ok(rdb, holder, i):
		return _err("This is not your stall.")
	var items: Array = rdb.container(stock_id(i)).get("items", [])
	var k := _find(items, id)
	if k < 0:
		return _err("No such ware.")
	var nm := item_name(items[k])
	var r := _commit(rdb, gs, rec, [{"item": id, "from": stock_id(i), "to": "record"}], persist)
	if not r.get("ok", false):
		return _err(str(r.get("error", "Refused.")))
	_drop_price(rdb, i, holder, id)
	return {"withdrawn": nm}


static func _op_collect(rdb, gs, rec: Dictionary, holder: String, persist: Callable) -> Dictionary:
	var till: Dictionary = rdb.container(till_id(holder))
	var col := int(till.get("col", 0))
	var moves: Array = []
	if col > 0:
		moves.append({"col": col, "from": till_id(holder), "to": "record"})
	var room: int = Net.MAX_INVENTORY - (rec.get("inventory", []) as Array).size()
	var n := 0
	for it in till.get("items", []):
		if n < room:
			moves.append({"item": str(it.get("id", "")), "from": till_id(holder), "to": "record"})
			n += 1
	if moves.is_empty():
		return _err("Your till is empty." if (till.get("items", []) as Array).is_empty() else "Your inventory is full.")
	var r := _commit(rdb, gs, rec, moves, persist)
	if not r.get("ok", false):
		return _err(str(r.get("error", "Refused.")))
	return {"collected": col, "items": n}


static func _op_buy(rdb, gs, rec: Dictionary, holder: String, i: int, payload: Dictionary, persist: Callable) -> Dictionary:
	var c: Dictionary = rdb.container(stock_id(i))
	var owner := str(c.get("owner", ""))
	if owner == "":
		return _err("This stall is empty.")
	if owner == holder:
		return _err("That is your guild's stall: withdraw it instead." if gid_of_owner(owner) != "" else "That is your own stall: withdraw it instead.")
	var id := str(payload.get("item", ""))
	var items: Array = c.get("items", [])
	var k := _find(items, id)
	if k < 0:
		return _err("Someone bought that already.")
	var item: Dictionary = items[k]
	if Permadeath.rec_on(rec) != bool(meta_of(rdb, i).get("hardcore", false)):
		return _err("Permadeath climbers trade only with each other." if Permadeath.rec_on(rec) else "A permadeath stall sells only to permadeath climbers.")
	var prices = meta_of(rdb, i).get("prices", {})
	var price := int(prices.get(id, suggest_price(item))) if prices is Dictionary else suggest_price(item)
	if payload.has("price") and int(payload["price"]) != price:
		return _err("The price changed to %d Col. Take another look." % price)
	if int(rec.get("money", 0)) < price:
		return _err("Not enough Col (%d needed)." % price)
	var tax := roundi(price * TAX_RATE)
	var till := _ensure_till(rdb, owner)
	rdb.ensure_container(SINK, "", "sink")
	var moves: Array = [{"col": price, "from": "record", "to": till}, {"item": id, "from": stock_id(i), "to": "record"}]
	if tax > 0:
		moves.append({"col": tax, "from": till, "to": SINK})
	var nm := item_name(item)
	var r := _commit(rdb, gs, rec, moves, persist)
	if not r.get("ok", false):
		return _err(str(r.get("error", "Refused.")))
	_drop_price(rdb, i, owner, id)
	print("[market] %s bought %s at stall %d for %d Col (tax %d)" % [name_of(rec), nm, i + 1, price, tax])
	return {"bought": nm, "price": price, "tax": tax, "mat": str(item.get("mat", "")), "dish": LifeData.RECIPES.has(str(item.get("mat", "")))}


# --- Offline / listen host: the same core on GameState ------------------------------

## A record-shaped view of GameState for RealmDB.transact: inventory and
## equipped are the live GameState containers, money is written back after.
static func local_rec() -> Dictionary:
	return {"name": str(GameState.character.get("name", "Nameless")), "token": "", "money": GameState.money,
		"inventory": GameState.inventory, "equipped": GameState.equipped, "realm_seq": 0, "permadeath": Permadeath.is_on(GameState)}


static func local_persist(rec: Dictionary) -> bool:
	if GameState.money != int(rec["money"]):
		GameState.money = int(rec["money"])
		GameState.money_changed.emit(GameState.money)
	GameState.inventory_changed.emit()
	GameState.stats_changed.emit()
	if autosave_offline and not Net.online:
		SaveSystem.save_game(0)
	return true


static func run_local(i: int, payload: Dictionary) -> Dictionary:
	var rec := local_rec()
	var res := run(Net.get_realm(), GameState, rec, i, payload, local_persist)
	if not res.has("error") and str(payload.get("op", "view")) != "view":
		local_persist(rec)
	return res


# --- World node --------------------------------------------------------------------

static func build(w: Node3D, hollowbrook: Vector3) -> Node3D:
	var s = load("res://scripts/life/stalls.gd").new()
	s.name = "MarketStalls"
	s.world = w
	w.add_child(s)
	s._build(hollowbrook)
	return s


func _build(hollowbrook: Vector3) -> void:
	var lay := layout(hollowbrook)
	var center := market_center(hollowbrook)
	var u := Vector3(11, 0, 17).normalized()
	if world.get("_life_keep") is Array:
		world._life_keep.append([center, ALONG * 1.6 + 2.0])
	# Stepping stones down the aisle and a lantern at each end.
	for k in 9:
		var sp := center + u * (-8.0 + k * 2.0) + Vector3(u.z, 0, -u.x) * (0.35 * ((k % 2) * 2 - 1))
		if not WorldProps.prop(world, "survival", "rock-flat", sp, k * 1.1, WorldProps.SURVIVAL * 0.1, "none"):
			WorldArt.cyl(world, 0.45, 0.5, 0.06, sp + Vector3(0, 0.03, 0), WorldArt.STONE, 8)
	for e in [-1.0, 1.0]:
		WorldProps.lantern(world, center + u * (e * (ALONG * 1.5 + 1.5)) + Vector3(u.z, 0, -u.x) * 1.6, atan2(u.x, u.z))
	for k in COUNT:
		var d: Dictionary = lay[k]
		var pos: Vector3 = d["pos"]
		var rot: float = d["rot"]
		var fwd := Vector3(sin(rot), 0, cos(rot))
		var side := Vector3(cos(rot), 0, -sin(rot))
		WorldProps.stall(world, pos, rot, k % 2)  # red / green awnings (the plain "stall" has none)
		var post := pos + fwd * 0.9 - side * 2.0
		if not WorldProps.signpost(world, post, rot):
			WorldArt.cyl(world, 0.06, 0.08, 1.6, post + Vector3(0, 0.8, 0), WorldArt.WOOD, 6)
			WorldArt.box(world, Vector3(1.0, 0.45, 0.06), post + Vector3(0, 1.4, 0), WorldArt.WOOD_LIGHT, Vector3(0, rot, 0))
		var sign := Label3D.new()
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.position = pos + Vector3(0, 3.5, 0) + fwd * 0.3
		sign.font_size = 40
		sign.outline_size = 12
		sign.modulate = Color(1, 0.93, 0.6)
		sign.outline_modulate = Color(0.12, 0.08, 0.2, 0.9)
		sign.pixel_size = 0.005
		sign.text = "Stall %d\nFOR RENT  ·  %d Col / week" % [k + 1, RENT]
		world.add_child(sign)
		# Restaurant seating and shop goods: live props, shown by type.
		var seats := Node3D.new()
		seats.name = "Seats%d" % k
		seats.visible = false
		world.add_child(seats)
		var tpos := pos + fwd * 2.9 - side * 2.6
		if WorldProps.live_prop(seats, "dungeon", "table_small_decorated_A", tpos, rot, WorldProps.DUNGEON, "box") == null:
			WorldArt.cyl(seats, 0.5, 0.5, 0.08, tpos + Vector3(0, 0.75, 0), WorldArt.WOOD_LIGHT, 10)
			WorldArt.cyl(seats, 0.08, 0.1, 0.75, tpos + Vector3(0, 0.37, 0), WorldArt.WOOD, 6)
		for sx in [-1.0, 1.0]:
			var st: Vector3 = tpos + side * (sx * 0.95)
			if WorldProps.live_prop(seats, "dungeon", "stool", st, rot, WorldProps.DUNGEON, "none") == null:
				WorldArt.cyl(seats, 0.22, 0.22, 0.45, st + Vector3(0, 0.22, 0), WorldArt.WOOD, 8)
		WorldProps.live_prop(seats, "dungeon", "plate_food_A", pos + fwd * 0.35 + Vector3(0, 1.0, 0) - side * 0.6, rot, WorldProps.DUNGEON, "none")
		WorldProps.live_prop(seats, "dungeon", "plate_food_B", pos + fwd * 0.35 + Vector3(0, 1.0, 0) + side * 0.5, rot + 0.6, WorldProps.DUNGEON, "none")
		var wares := Node3D.new()
		wares.name = "Wares%d" % k
		wares.visible = false
		world.add_child(wares)
		if WorldProps.live_prop(wares, "dungeon", "crates_stacked", pos - fwd * 1.3 - side * 1.0, rot + 0.3, WorldProps.DUNGEON * 0.8, "none") == null:
			WorldArt.crate(wares, pos - fwd * 1.3 - side * 1.0, 0.8, rot)
		# The stall keeper: stands behind the counter while the stall is rented
		# and stocked (the owner can be offline; the keeper sells for them).
		# Art hook: WorldProps.stall_keeper(parent, pos, rot, index) builds the
		# figure; a plain primitive stands in until it exists.
		var keeper := Node3D.new()
		keeper.name = "Keeper%d" % k
		keeper.visible = false
		world.add_child(keeper)
		var kpos := pos - fwd * 0.55
		var wp: Script = load("res://scripts/world_props.gd")
		if not (wp.has_method("stall_keeper") and wp.call("stall_keeper", keeper, kpos, rot + PI, k)):
			var apron := Color("b8865a") if k % 2 == 0 else Color("6f8f5a")
			WorldArt.cyl(keeper, 0.2, 0.26, 1.05, kpos + Vector3(0, 0.55, 0), apron, 8)
			WorldArt.cyl(keeper, 0.24, 0.24, 0.32, kpos + Vector3(0, 1.22, 0), Color("e8d2b8"), 8)
			WorldArt.cyl(keeper, 0.27, 0.2, 0.12, kpos + Vector3(0, 1.43, 0), Color("4a3a2e"), 8)
		stalls.append({"pos": pos, "rot": rot, "front": d["front"], "sign": sign, "seats": seats, "wares": wares, "keeper": keeper})
	if Net.is_authority() or not Net.online:
		_refresh_local_signs()


func _process(delta: float) -> void:
	if not Net.online or Net.is_authority():
		_sweep_t -= delta
		if _sweep_t <= 0.0:
			_sweep_t = 30.0
			var rdb = Net.get_realm()
			if rdb != null and not sweep(rdb).is_empty() or signs.is_empty():
				_refresh_local_signs()
		return
	# Online client: ask for the signs while the market is in sight.
	var p = world.get("player")
	if p == null or stalls.is_empty():
		return
	_poll -= delta
	if _poll <= 0.0 and (p as Node3D).global_position.distance_to(stalls[1]["pos"]) < 55.0:
		_poll = 10.0
		Net.request_action("stall_signs", {})


func _refresh_local_signs() -> void:
	var rdb = Net.get_realm()
	if rdb != null:
		apply_signs(sign_state(rdb))


func apply_signs(list: Array) -> void:
	signs = list
	for k in mini(list.size(), stalls.size()):
		var s: Dictionary = list[k]
		var st: Dictionary = stalls[k]
		var owner := str(s.get("owner", ""))
		var resto := str(s.get("type", "shop")) == "restaurant"
		var lbl: Label3D = st["sign"]
		if owner == "":
			lbl.text = "Stall %d\nFOR RENT  ·  %d Col / week" % [k + 1, RENT]
			lbl.modulate = Color(1, 0.93, 0.6)
		else:
			var n := int(s.get("n", 0))
			lbl.text = "%s's %s\n%s" % [owner, "Kitchen" if resto else "Stall",
				("%d %s  ·  keeper on duty" % [n, "dishes" if resto else ("wares" if n != 1 else "ware")]) if n > 0 else "sold out"]
			lbl.modulate = Color("ffcf8a") if resto else Color("bfe8ff")
		(st["seats"] as Node3D).visible = owner != "" and resto
		(st["wares"] as Node3D).visible = owner != "" and not resto and int(s.get("n", 0)) > 0
		(st["keeper"] as Node3D).visible = owner != "" and int(s.get("n", 0)) > 0


## Closes the stall guild `gid` rents (the guild is disbanding). Refuses
## ("" ok, else the reason) while wares are still on its counter.
static func close_guild_stall(rdb, gid: String) -> String:
	var key := guild_key(gid)
	var i := stall_of(rdb, key)
	if i < 0:
		return ""
	var c: Dictionary = rdb.container(stock_id(i))
	if not (c.get("items", []) as Array).is_empty() or int(c.get("col", 0)) > 0:
		return "Withdraw the wares from the guild stall (stall %d) first." % (i + 1)
	return ""


static func release_guild_stall(rdb, gid: String) -> void:
	var key := guild_key(gid)
	var i := stall_of(rdb, key)
	if i < 0:
		return
	if rdb.is_holder(claim_id(i), key):
		rdb.release(claim_id(i), key)
	_set_meta(rdb, i, "", _free_meta())


## Interact prompt: {"stall": i, "label"} when the player stands at a stall front.
func nearest(from: Vector3) -> Dictionary:
	var best := {}
	var best_d := USE_RANGE
	for k in stalls.size():
		var d: float = from.distance_to(stalls[k]["front"])
		if d < best_d:
			best_d = d
			var s: Dictionary = signs[k] if k < signs.size() else {}
			var owner := str(s.get("owner", ""))
			var label := "Rent stall %d (%d Col / week)" % [k + 1, RENT]
			if owner != "":
				label = "Browse %s's %s" % [owner, "kitchen" if str(s.get("type", "")) == "restaurant" else "stall"]
			best = {"stall": k, "label": label}
	return best


## Server: range check, then the core on the record. Kinds "stall" (the
## screen's operations) and "stall_signs" (sign poll, no range check).
func srv(_peer: int, rs, kind: String, payload: Dictionary, pos: Vector3) -> Dictionary:
	var rdb = Net.get_realm()
	if rdb == null:
		return _err("The market ledger is closed.")
	if kind == "stall_signs":
		sweep(rdb)
		return {"signs": sign_state(rdb)}
	var i := int(payload.get("stall", -1))
	if i < 0 or i >= stalls.size():
		return _err("No such stall.")
	if pos.distance_to(stalls[i]["front"]) > USE_RANGE + 1.0 + Net.RANGE_SLACK:
		return _err("You are not at that stall.")
	var res := run(rdb, rs, rs.rec, i, payload, func(r): return Net.save_record(r))
	if not res.has("error") and res.has("signs"):
		apply_signs(res["signs"])
	return res


## The stall screen's request: offline / host run it now, an online client
## asks the server (the answer comes back through on_net). Returns the result
## or {"pending": true}.
func request(i: int, payload: Dictionary) -> Dictionary:
	var p := payload.duplicate()
	p["stall"] = i
	if Net.remote_client():
		if not Net.request_action("stall", p):
			return {"error": "Slow down a moment."}
		return {"pending": true}
	var res := run_local(i, p)
	if res.has("signs"):
		apply_signs(res["signs"])
	return res


## Online client: a "stall" / "stall_signs" answer from the server.
func on_net(kind: String, res: Dictionary) -> void:
	if res.has("signs") and res["signs"] is Array:
		apply_signs(res["signs"])
	if kind == "stall" and screen != null and screen.has_method("show_result"):
		screen.show_result(res)


## Opens the stall screen on stall `i` through the HUD's LifeHUD.
func open(i: int, h: Node) -> void:
	hud = h
	if h == null or h.get("life") == null or not h.life.has_method("open_stall"):
		return
	screen = h.life.open_stall(self, i)
