extends Node3D
## Guilds (Floor 1, P8). Founded for a fee at Lv 10 at the Hollowbrook notice
## board: a name (3-20 chars, unique), a tag (2-4 letters, unique) shown over
## members' heads, ranks Leader / Officer / Member, a roster, guild chat
## ("/g text") and shared guild storage.
##
## Membership is realm data: a top-level `guilds` key written only through
## the realm's "guild" journal op (RealmDB._apply), one whole guild per write:
##   guilds: { gid: {"name", "tag", "created", "members": { holder: {"name",
##             "rank": "leader"|"officer"|"member", "since"} } } }
## so it is durable, replayed after a crash and decided by the server alone.
## A character is in at most one guild (guild_of scans the members). Storage
## is the realm container `guild:<gid>` (kind "guild"): every member may
## deposit, Officers and the Leader withdraw, all through RealmDB.transact
## (escrow) so nothing duplicates; bound items never leave their owner.
## Stackable goods travel as Stalls stacks, exactly like the market.
##
## Pending invites live in memory on the server (they expire after INVITE_SECS
## and need the invitee online). The node also pushes the name -> tag map to
## every client (Net.net_guild_tags) for the name labels, and draws the
## notice board in Hollowbrook.

const Stalls := preload("res://scripts/life/stalls.gd")

const FEE := 1000
const MIN_LEVEL := 10
const MAX_MEMBERS := 40
const INVITE_SECS := 120.0
const SINK := "realm:guilds"
const RANKS := ["member", "officer", "leader"]
const RANK_NAMES := {"leader": "Leader", "officer": "Officer", "member": "Member"}
const BOARD_RANGE := 2.6
## Notice board beside the Hollowbrook well (west side, facing the well).
const BOARD_OFFSET := Vector3(-3.6, 0, 4.4)

## Server: pending invites, invitee holder -> {"gid", "from", "t"}.
static var invites := {}
static var autosave_offline := true

var world: Node3D
var hud: Node
var board_pos := Vector3.ZERO
var screen = null
var _tags_t := 0.0
var _last_tags := {}


# --- Data access ------------------------------------------------------------------

static func _now(rdb) -> float:
	return float(rdb.clock.call())


static func _err(text: String) -> Dictionary:
	return {"error": text}


static func all(rdb) -> Dictionary:
	var g = rdb.data.get("guilds", {})
	return g if g is Dictionary else {}


static func get_guild(rdb, gid: String) -> Dictionary:
	var g = all(rdb).get(gid, {})
	return g if g is Dictionary else {}


## The guild id `holder` belongs to, or "".
static func guild_of(rdb, holder: String) -> String:
	if holder == "":
		return ""
	var gs := all(rdb)
	for gid in gs:
		var m = gs[gid].get("members", {})
		if m is Dictionary and m.has(holder):
			return str(gid)
	return ""


static func rank_of(rdb, holder: String) -> String:
	var gid := guild_of(rdb, holder)
	if gid == "":
		return ""
	return str(get_guild(rdb, gid)["members"][holder].get("rank", "member"))


static func rank_value(rank: String) -> int:
	return RANKS.find(rank)


static func storage_id(gid: String) -> String:
	return "guild:" + gid


static func tag_of(rdb, holder: String) -> String:
	var gid := guild_of(rdb, holder)
	return str(get_guild(rdb, gid).get("tag", "")) if gid != "" else ""


## Holders of every member of `holder`'s guild (guild chat fan-out).
static func mates(rdb, holder: String) -> Array:
	var gid := guild_of(rdb, holder)
	if gid == "":
		return []
	return (get_guild(rdb, gid)["members"] as Dictionary).keys()


static func _write(rdb, gid: String, g: Dictionary) -> bool:
	return rdb.commit("guild", {"id": gid, "g": g}) >= 0


static func _remove(rdb, gid: String) -> bool:
	return rdb.commit("guild", {"id": gid, "remove": true}) >= 0


# --- Names ------------------------------------------------------------------------

## Letters, digits, spaces, apostrophes and hyphens; runs of spaces collapse.
static func clean_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		var ok := (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in [" ", "'", "-"]
		if ok and not (ch == " " and out.ends_with(" ")):
			out += ch
	return out.strip_edges()


static func clean_tag(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges().to_upper():
		if ch >= "A" and ch <= "Z":
			out += ch
	return out


static func name_error(n: String) -> String:
	if n.length() < 3 or n.length() > 20:
		return "A guild name needs 3 to 20 letters or digits."
	if not (n[0] >= "A" and n[0] <= "Z") and not (n[0] >= "a" and n[0] <= "z"):
		return "A guild name starts with a letter."
	return ""


static func taken(rdb, name: String, tag: String) -> String:
	var gs := all(rdb)
	for gid in gs:
		if str(gs[gid].get("name", "")).to_lower() == name.to_lower():
			return "The guild \"%s\" already exists." % str(gs[gid]["name"])
		if str(gs[gid].get("tag", "")) == tag:
			return "The tag [%s] is already worn by %s." % [tag, str(gs[gid]["name"])]
	return ""


# --- View -------------------------------------------------------------------------

static func item_row(it: Dictionary) -> Dictionary:
	var row := {"id": str(it.get("id", "")), "name": Stalls.item_name(it), "kind": str(it.get("kind", ""))}
	for k in ["mat", "count", "rank", "atk", "def"]:
		if it.has(k):
			row[k] = it[k]
	return row


## What the guild screen shows. `ctx`: {"online": Callable(holder) -> bool,
## "at_board": bool}. No holder keys leave the server.
static func view(rdb, rec: Dictionary, holder: String, ctx: Dictionary) -> Dictionary:
	var out := {"fee": FEE, "min_level": MIN_LEVEL, "level": int(rec.get("level", 1)), "money": int(rec.get("money", 0)),
		"at_board": bool(ctx.get("at_board", false)), "in_guild": false, "invite": {}}
	var inv: Dictionary = invites.get(holder, {})
	if not inv.is_empty() and _now(rdb) - float(inv.get("t", 0.0)) <= INVITE_SECS:
		var ig := get_guild(rdb, str(inv.get("gid", "")))
		if not ig.is_empty():
			out["invite"] = {"guild": str(ig["name"]), "tag": str(ig["tag"]), "from": str(inv.get("from", ""))}
	var gid := guild_of(rdb, holder)
	if gid == "":
		return out
	var g := get_guild(rdb, gid)
	var online: Callable = ctx.get("online", Callable())
	var rows: Array = []
	for h in g["members"]:
		var m: Dictionary = g["members"][h]
		rows.append({"name": str(m.get("name", "")), "rank": str(m.get("rank", "member")), "since": float(m.get("since", 0.0)),
			"me": h == holder, "online": h == holder or (online.is_valid() and bool(online.call(h)))})
	rows.sort_custom(func(a, b):
		if rank_value(a["rank"]) != rank_value(b["rank"]):
			return rank_value(a["rank"]) > rank_value(b["rank"])
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	var st: Dictionary = rdb.container(storage_id(gid))
	var items: Array = []
	for it in st.get("items", []):
		if it is Dictionary:
			items.append(item_row(it))
	out.merge({"in_guild": true, "guild": {"name": str(g["name"]), "tag": str(g["tag"]), "created": float(g.get("created", 0.0)), "members": rows},
		"my_rank": str(g["members"][holder].get("rank", "member")), "storage": {"col": int(st.get("col", 0)), "items": items}}, true)
	return out


# --- Operations -------------------------------------------------------------------

## Runs one guild operation for the character behind `rec` / `gs`.
## payload: {"op": view|found|invite|accept|decline|leave|kick|promote|demote|
## transfer|disband|deposit|withdraw, ...}. `ctx`: {"at_board": bool,
## "online": Callable(holder) -> bool, "target": {"holder", "name"} for invite
## (the server resolves an online name)}. Returns the result plus a fresh
## "view", or {"error"}; "notify": [{"holders": [...], "text"}] lists the
## system lines the server sends to other members.
static func run(rdb, gs, rec: Dictionary, payload: Dictionary, persist: Callable, ctx: Dictionary = {}) -> Dictionary:
	if rdb == null:
		return _err("The guild ledger is closed.")
	var holder := Stalls.holder_of(rec)
	var op := str(payload.get("op", "view"))
	var res: Dictionary = {}
	match op:
		"view":
			pass
		"found":
			res = _op_found(rdb, gs, rec, holder, payload, persist, ctx)
		"invite":
			res = _op_invite(rdb, rec, holder, ctx)
		"accept":
			res = _op_accept(rdb, rec, holder)
		"decline":
			invites.erase(holder)
			res = {"declined": true}
		"leave":
			res = _op_leave(rdb, holder)
		"kick", "promote", "demote", "transfer":
			res = _op_rank(rdb, holder, op, str(payload.get("name", "")))
		"disband":
			res = _op_disband(rdb, holder)
		"deposit":
			res = _op_deposit(rdb, gs, rec, holder, payload, persist, ctx)
		"withdraw":
			res = _op_withdraw(rdb, gs, rec, holder, payload, persist, ctx)
		_:
			return _err("Unknown guild action.")
	if res.has("error"):
		return res
	res["op"] = op
	res["view"] = view(rdb, rec, holder, ctx)
	return res


static func _op_found(rdb, gs, rec: Dictionary, holder: String, payload: Dictionary, persist: Callable, ctx: Dictionary) -> Dictionary:
	if not bool(ctx.get("at_board", false)):
		return _err("Guilds are founded at the Hollowbrook notice board.")
	if guild_of(rdb, holder) != "":
		return _err("You already belong to a guild. Leave it first.")
	if int(rec.get("level", 1)) < MIN_LEVEL:
		return _err("Only adventurers of level %d may found a guild." % MIN_LEVEL)
	var nm := clean_name(str(payload.get("name", "")))
	var e := name_error(nm)
	if e != "":
		return _err(e)
	var tag := clean_tag(str(payload.get("tag", "")))
	if tag.length() < 2 or tag.length() > 4:
		return _err("A guild tag is 2 to 4 letters.")
	var t := taken(rdb, nm, tag)
	if t != "":
		return _err(t)
	if int(rec.get("money", 0)) < FEE:
		return _err("The charter costs %d Col." % FEE)
	var gid := "g%d" % (int(rdb.data.get("seq", 0)) + 1)
	while all(rdb).has(gid):
		gid += "x"
	var now := _now(rdb)
	var g := {"name": nm, "tag": tag, "created": now, "members": {holder: {"name": Stalls.name_of(rec), "rank": "leader", "since": now}}}
	# The guild first, then the fee: a refused fee removes it again, a crash
	# in between leaves a free guild (never a paid fee without one).
	if not _write(rdb, gid, g):
		return _err("The guild ledger could not be written.")
	rdb.ensure_container(SINK, "", "sink")
	var r := Stalls._commit(rdb, gs, rec, [{"col": FEE, "from": "record", "to": SINK}], persist)
	if not r.get("ok", false):
		_remove(rdb, gid)
		return _err(str(r.get("error", "The charter fee could not be paid.")))
	rdb.ensure_container(storage_id(gid), "", "guild", {"gid": gid})
	invites.erase(holder)
	print("[guild] %s founded %s [%s]" % [Stalls.name_of(rec), nm, tag])
	return {"founded": nm, "tag": tag, "paid": FEE, "announce": "%s founded the guild %s [%s]." % [Stalls.name_of(rec), nm, tag]}


static func _op_invite(rdb, rec: Dictionary, holder: String, ctx: Dictionary) -> Dictionary:
	var gid := guild_of(rdb, holder)
	if gid == "":
		return _err("You are not in a guild.")
	if rank_value(rank_of(rdb, holder)) < rank_value("officer"):
		return _err("Only Officers and the Leader may invite.")
	var target: Dictionary = ctx.get("target", {})
	var th := str(target.get("holder", ""))
	var tn := str(target.get("name", ""))
	if th == "":
		return _err("%s is not online." % (tn if tn != "" else "Nobody by that name"))
	if th == holder:
		return _err("You are already in your guild.")
	if guild_of(rdb, th) != "":
		return _err("%s already belongs to a guild." % tn)
	var g := get_guild(rdb, gid)
	if (g["members"] as Dictionary).size() >= MAX_MEMBERS:
		return _err("The guild is full (%d members)." % MAX_MEMBERS)
	invites[th] = {"gid": gid, "from": Stalls.name_of(rec), "t": _now(rdb)}
	return {"invited": tn, "invitee": th, "guild": str(g["name"]), "tag": str(g["tag"])}


static func _op_accept(rdb, rec: Dictionary, holder: String) -> Dictionary:
	var inv: Dictionary = invites.get(holder, {})
	if inv.is_empty() or _now(rdb) - float(inv.get("t", 0.0)) > INVITE_SECS:
		invites.erase(holder)
		return _err("You have no guild invitation (they last %d s)." % int(INVITE_SECS))
	if guild_of(rdb, holder) != "":
		invites.erase(holder)
		return _err("You already belong to a guild.")
	var gid := str(inv["gid"])
	var g := get_guild(rdb, gid).duplicate(true)
	if g.is_empty():
		invites.erase(holder)
		return _err("That guild has disbanded.")
	if (g["members"] as Dictionary).size() >= MAX_MEMBERS:
		return _err("The guild is full.")
	g["members"][holder] = {"name": Stalls.name_of(rec), "rank": "member", "since": _now(rdb)}
	if not _write(rdb, gid, g):
		return _err("The guild ledger could not be written.")
	invites.erase(holder)
	return {"joined": str(g["name"]), "tag": str(g["tag"]),
		"notify": [{"holders": (g["members"] as Dictionary).keys(), "text": "%s joined the guild." % Stalls.name_of(rec)}]}


## Leaving: the last member's leave disbands (storage must be empty); a
## leader's leave hands the guild to the senior Officer (else Member).
static func _op_leave(rdb, holder: String) -> Dictionary:
	var gid := guild_of(rdb, holder)
	if gid == "":
		return _err("You are not in a guild.")
	var g := get_guild(rdb, gid).duplicate(true)
	var members: Dictionary = g["members"]
	if members.size() == 1:
		var r := _op_disband(rdb, holder)
		if r.has("error"):
			return _err("You are the last member: " + str(r["error"]).to_lower())
		r["left"] = str(g["name"])
		return r
	var me: Dictionary = members[holder]
	members.erase(holder)
	var heir := ""
	if str(me.get("rank", "")) == "leader":
		var best := -1
		var best_since := INF
		for h in members:
			var rv := rank_value(str(members[h].get("rank", "member")))
			var since := float(members[h].get("since", 0.0))
			if rv > best or (rv == best and since < best_since):
				best = rv
				best_since = since
				heir = h
		members[heir]["rank"] = "leader"
	if not _write(rdb, gid, g):
		return _err("The guild ledger could not be written.")
	var text := "%s left the guild." % str(me.get("name", ""))
	if heir != "":
		text += " %s now leads it." % str(members[heir].get("name", ""))
	return {"left": str(g["name"]), "notify": [{"holders": members.keys(), "text": text}]}


## A character was deleted: take it off its guild's roster (handing on the
## lead like a leave). If it was the last member the guild goes too, with
## whatever is left in its storage, since no one remains to claim it.
static func forget_holder(rdb, holder: String) -> void:
	invites.erase(holder)
	var gid := guild_of(rdb, holder)
	if gid == "":
		return
	if (get_guild(rdb, gid)["members"] as Dictionary).size() > 1:
		_op_leave(rdb, holder)
		return
	_remove(rdb, gid)
	if not rdb.container(storage_id(gid)).is_empty():
		rdb.remove_container(storage_id(gid))
	for h in invites.keys():
		if str(invites[h].get("gid", "")) == gid:
			invites.erase(h)


static func _find_member(g: Dictionary, name: String) -> String:
	for h in g.get("members", {}):
		if str(g["members"][h].get("name", "")).to_lower() == name.strip_edges().to_lower():
			return h
	return ""


## kick (Officer+ on lower ranks), promote / demote (Leader: Member <->
## Officer), transfer (Leader hands the guild to another member).
static func _op_rank(rdb, holder: String, op: String, name: String) -> Dictionary:
	var gid := guild_of(rdb, holder)
	if gid == "":
		return _err("You are not in a guild.")
	var g := get_guild(rdb, gid).duplicate(true)
	var members: Dictionary = g["members"]
	var th := _find_member(g, name)
	if th == "":
		return _err("%s is not in your guild." % name)
	if th == holder:
		return _err("Not on yourself.")
	var mine := rank_value(str(members[holder]["rank"]))
	var theirs := rank_value(str(members[th]["rank"]))
	var tname := str(members[th]["name"])
	var text := ""
	match op:
		"kick":
			if mine < rank_value("officer"):
				return _err("Only Officers and the Leader may remove members.")
			if theirs >= mine:
				return _err("You cannot remove someone of your own rank or above.")
			members.erase(th)
			text = "%s was removed from the guild by %s." % [tname, str(members[holder]["name"])]
		"promote":
			if mine < rank_value("leader"):
				return _err("Only the Leader may promote.")
			if theirs != rank_value("member"):
				return _err("%s is already an Officer. Use Make Leader to hand over the guild." % tname)
			members[th]["rank"] = "officer"
			text = "%s is now an Officer." % tname
		"demote":
			if mine < rank_value("leader"):
				return _err("Only the Leader may demote.")
			if theirs != rank_value("officer"):
				return _err("%s holds no rank to lose." % tname)
			members[th]["rank"] = "member"
			text = "%s is a Member again." % tname
		"transfer":
			if mine < rank_value("leader"):
				return _err("Only the Leader may hand over the guild.")
			members[th]["rank"] = "leader"
			members[holder]["rank"] = "officer"
			text = "%s now leads the guild." % tname
	if not _write(rdb, gid, g):
		return _err("The guild ledger could not be written.")
	var to: Array = members.keys()
	if op == "kick":
		to.append(th)
	return {op: tname, "notify": [{"holders": to, "text": text}]}


static func _op_disband(rdb, holder: String) -> Dictionary:
	var gid := guild_of(rdb, holder)
	if gid == "":
		return _err("You are not in a guild.")
	if rank_of(rdb, holder) != "leader":
		return _err("Only the Leader may disband the guild.")
	var se: String = Stalls.close_guild_stall(rdb, gid)
	if se != "":
		return _err(se)
	var st: Dictionary = rdb.container(storage_id(gid))
	if int(st.get("col", 0)) > 0 or not (st.get("items", []) as Array).is_empty():
		return _err("Empty the guild storage first.")
	Stalls.release_guild_stall(rdb, gid)
	var g := get_guild(rdb, gid)
	var to: Array = (g["members"] as Dictionary).keys()
	if not _remove(rdb, gid):
		return _err("The guild ledger could not be written.")
	if not st.is_empty():
		rdb.remove_container(storage_id(gid))
	for h in invites.keys():
		if str(invites[h].get("gid", "")) == gid:
			invites.erase(h)
	print("[guild] %s [%s] disbanded" % [str(g["name"]), str(g["tag"])])
	return {"disbanded": str(g["name"]), "notify": [{"holders": to, "text": "The guild %s has been disbanded." % str(g["name"])}]}


static func _storage_ok(rdb, holder: String, ctx: Dictionary) -> String:
	if guild_of(rdb, holder) == "":
		return "You are not in a guild."
	if not bool(ctx.get("at_board", false)):
		return "The guild storage is kept at the Hollowbrook notice board."
	return ""


static func _op_deposit(rdb, gs, rec: Dictionary, holder: String, payload: Dictionary, persist: Callable, ctx: Dictionary) -> Dictionary:
	var e := _storage_ok(rdb, holder, ctx)
	if e != "":
		return _err(e)
	var gid := guild_of(rdb, holder)
	var sid := storage_id(gid)
	rdb.ensure_container(sid, "", "guild", {"gid": gid})
	if payload.has("col"):
		var n := int(payload["col"])
		if n < 1 or n > int(rec.get("money", 0)):
			return _err("You do not carry that much Col.")
		var r := Stalls._commit(rdb, gs, rec, [{"col": n, "from": "record", "to": sid}], persist)
		if not r.get("ok", false):
			return _err(str(r.get("error", "Refused.")))
		return {"deposited": "%d Col" % n, "col": n}
	if payload.has("mat"):
		var m := str(payload["mat"])
		var n := int(payload.get("count", 1))
		if not GameState.MATERIAL_NAMES.has(m):
			return _err("You cannot store that.")
		if n < 1 or n > Stalls.MAX_STACK or int(gs.materials.get(m, 0)) < n:
			return _err("You do not carry that many.")
		var stack := Stalls.make_stack(m, n)
		gs.spend_materials({m: n})
		rec["inventory"].append(stack)
		var durable: bool = gs != GameState
		if durable:
			persist.call(rec)
		var r := Stalls._commit(rdb, gs, rec, [{"item": stack["id"], "from": "record", "to": sid}], persist)
		if not r.get("ok", false):
			Stalls.unpack_stacks(rec, gs)
			if durable:
				persist.call(rec)
			return _err(str(r.get("error", "Refused.")))
		return {"deposited": Stalls.item_name(stack)}
	var id := str(payload.get("item", ""))
	var k := Stalls._find(rec.get("inventory", []), id)
	if k < 0:
		return _err("You do not carry that item.")
	var it: Dictionary = rec["inventory"][k]
	if bool(it.get("bound", false)) or rdb.is_bound(it):
		return _err("That item is bound to you and cannot be stored for the guild.")
	for slot in ["weapon", "armor"]:
		var eq = rec.get("equipped", {}).get(slot)
		if eq is Dictionary and str(eq.get("id", "")) == id:
			return _err("Unequip it first.")
	var nm := str(it.get("name", "Item"))
	var r := Stalls._commit(rdb, gs, rec, [{"item": id, "from": "record", "to": sid}], persist)
	if not r.get("ok", false):
		return _err(str(r.get("error", "Refused.")))
	return {"deposited": nm}


static func _op_withdraw(rdb, gs, rec: Dictionary, holder: String, payload: Dictionary, persist: Callable, ctx: Dictionary) -> Dictionary:
	var e := _storage_ok(rdb, holder, ctx)
	if e != "":
		return _err(e)
	if rank_value(rank_of(rdb, holder)) < rank_value("officer"):
		return _err("Only Officers and the Leader may take from the guild storage.")
	var sid := storage_id(guild_of(rdb, holder))
	var st: Dictionary = rdb.container(sid)
	if payload.has("col"):
		var n := int(payload["col"])
		if n < 1 or n > int(st.get("col", 0)):
			return _err("The guild storage holds less Col than that.")
		var r := Stalls._commit(rdb, gs, rec, [{"col": n, "from": sid, "to": "record"}], persist)
		if not r.get("ok", false):
			return _err(str(r.get("error", "Refused.")))
		return {"withdrawn": "%d Col" % n, "col": n}
	var id := str(payload.get("item", ""))
	var items: Array = st.get("items", [])
	var k := Stalls._find(items, id)
	if k < 0:
		return _err("That is no longer in the guild storage.")
	var nm := Stalls.item_name(items[k])
	var r := Stalls._commit(rdb, gs, rec, [{"item": id, "from": sid, "to": "record"}], persist)
	if not r.get("ok", false):
		return _err(str(r.get("error", "Refused.")))
	return {"withdrawn": nm}


# --- Offline / listen host ----------------------------------------------------------

static func run_local(payload: Dictionary, at_board: bool) -> Dictionary:
	var rec := Stalls.local_rec()
	rec["level"] = GameState.level
	var persist := func(r: Dictionary) -> bool:
		return _local_persist(r)
	var ctx := {"at_board": at_board, "online": func(_h): return false}
	if str(payload.get("op", "")) == "invite":
		ctx["target"] = {"holder": "", "name": str(payload.get("name", ""))}
	var res := run(Net.get_realm(), GameState, rec, payload, persist, ctx)
	if not res.has("error") and str(payload.get("op", "view")) != "view":
		_local_persist(rec)
		if res.get("view") is Dictionary:
			res["view"]["money"] = GameState.money
	return res


static func _local_persist(rec: Dictionary) -> bool:
	var keep: bool = Stalls.autosave_offline
	Stalls.autosave_offline = autosave_offline and keep
	var ok: bool = Stalls.local_persist(rec)
	Stalls.autosave_offline = keep
	return ok


# --- World node: notice board, tags, server glue ---------------------------------

static func build(w: Node3D, hollowbrook: Vector3) -> Node3D:
	var g = load("res://scripts/life/guilds.gd").new()
	g.name = "Guilds"
	g.world = w
	g.add_to_group("guild_office")
	w.add_child(g)
	g._build(hollowbrook)
	return g


func _build(hollowbrook: Vector3) -> void:
	board_pos = hollowbrook + BOARD_OFFSET
	if world.get("_life_keep") is Array:
		world._life_keep.append([board_pos, 2.0])
	# Two posts, a plank board with a little roof and pinned notices; the
	# board faces the well.
	var n := Node3D.new()
	n.name = "NoticeBoard"
	n.position = board_pos
	n.rotation.y = atan2(-BOARD_OFFSET.x, -BOARD_OFFSET.z)
	world.add_child(n)
	for sx in [-0.8, 0.8]:
		WorldArt.cyl(n, 0.07, 0.08, 2.3, Vector3(sx, 1.15, 0), WorldArt.WOOD, 6)
	WorldArt.box(n, Vector3(1.8, 1.1, 0.08), Vector3(0, 1.45, 0), WorldArt.WOOD_LIGHT)
	var roof := PrismMesh.new()
	roof.size = Vector3(2.1, 0.32, 0.5)
	WorldArt.mesh_node(n, roof, Vector3(0, 2.32, 0), WorldArt.mat(WorldArt.WOOD, 0.02))
	var papers := [[Vector3(-0.5, 1.6, 0.05), Color("efe6cf"), 0.05], [Vector3(0.05, 1.5, 0.05), Color("f5edd8"), -0.08],
		[Vector3(0.55, 1.62, 0.05), Color("e6dcc0"), 0.1], [Vector3(-0.2, 1.18, 0.05), Color("f0e4c8"), -0.03], [Vector3(0.45, 1.2, 0.05), Color("d9e8f0"), 0.06]]
	for p in papers:
		WorldArt.box(n, Vector3(0.36, 0.42, 0.01), p[0], p[1], Vector3(0, 0, p[2]), 0.0)
	WorldArt.box_collider(n, Vector3(1.8, 2.3, 0.3), Vector3(0, 1.15, 0))
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, 2.85, 0)
	l.font_size = 34
	l.outline_size = 12
	l.modulate = Color("f3e2b0")
	l.outline_modulate = Color(0.12, 0.08, 0.2, 0.9)
	l.pixel_size = 0.005
	l.text = "Notice Board\nGuild charters · %d Col" % FEE
	n.add_child(l)


func board_front() -> Vector3:
	var dir := -BOARD_OFFSET.normalized()
	return board_pos + Vector3(dir.x, 0, dir.z) * 1.2


func nearest(from: Vector3) -> Dictionary:
	if from.distance_to(board_front()) < BOARD_RANGE or from.distance_to(board_pos) < BOARD_RANGE:
		return {"guild_board": true, "label": "Read the notice board (guilds)"}
	return {}


func at_board(pos: Vector3, slack := 0.0) -> bool:
	return pos.distance_to(board_pos) <= BOARD_RANGE + 1.0 + slack


func _process(delta: float) -> void:
	# Server / host / offline: keep everyone's name -> tag map current.
	if Net.remote_client():
		return
	_tags_t -= delta
	if _tags_t > 0.0:
		return
	_tags_t = 3.0
	var rdb = Net.get_realm()
	if rdb == null:
		return
	var tags := {}
	if Net.online:
		for peer in Net.srv_records:
			var rec: Dictionary = Net.srv_records[peer]
			var t := tag_of(rdb, Net.RealmDBScript.holder_of_record(rec))
			if t != "":
				tags[str(rec.get("name", "")).to_lower()] = t
		if Net.is_server() and not Net.dedicated:
			var mine := tag_of(rdb, Net.local_holder())
			if mine != "":
				tags[str(GameState.character.get("name", "")).to_lower()] = mine
	else:
		var mine := tag_of(rdb, Net.local_holder())
		if mine != "":
			tags[str(GameState.character.get("name", "")).to_lower()] = mine
	var peers := Net.srv_records.keys()
	peers.sort()
	var sig := {"tags": tags, "peers": peers}
	if sig == _last_tags:
		return
	_last_tags = sig
	Net.guild_tags = tags
	if Net.online and Net.is_server():
		Net.broadcast_guild_tags(tags)


## Holder of an online character by name (server), or "".
static func _online_holder(name: String) -> Dictionary:
	var peer := Net.srv_peer_by_name(name)
	if peer != 0 and Net.srv_records.has(peer):
		var rec: Dictionary = Net.srv_records[peer]
		return {"holder": Net.RealmDBScript.holder_of_record(rec), "name": str(rec.get("name", name)), "peer": peer}
	return {"holder": "", "name": Net.sanitize_name(name)}


static func _peer_of_holder(holder: String) -> int:
	for peer in Net.srv_records:
		if Net.RealmDBScript.holder_of_record(Net.srv_records[peer]) == holder:
			return int(peer)
	return 0


## Server: the guild screen's operations for a connected peer.
func srv(peer: int, rs, _kind: String, payload: Dictionary, pos: Vector3) -> Dictionary:
	var rdb = Net.get_realm()
	if rdb == null:
		return _err("The guild ledger is closed.")
	var ctx := {"at_board": at_board(pos, Net.RANGE_SLACK), "online": func(h): return _peer_of_holder(h) != 0}
	var target := {}
	if str(payload.get("op", "")) == "invite":
		target = _online_holder(str(payload.get("name", "")))
		ctx["target"] = target
	var res := run(rdb, rs, rs.rec, payload, func(r): return Net.save_record(r), ctx)
	if res.has("error"):
		return res
	for note in res.get("notify", []):
		for h in note.get("holders", []):
			var p := _peer_of_holder(str(h))
			if p != 0 and p != peer:
				Net._send(p, Net.net_system, [str(note.get("text", ""))])
	if res.has("invited") and int(target.get("peer", 0)) != 0:
		Net._send(int(target["peer"]), Net.net_apply, ["guild_invite", {"guild": res["guild"], "tag": res["tag"], "from": Stalls.name_of(rs.rec)}])
	if res.has("announce"):
		Net.srv_announce(str(res["announce"]))
	_tags_t = 0.0
	res.erase("notify")
	res.erase("invitee")
	return res


## The guild screen's request: offline / host now, online through the server.
func request(payload: Dictionary) -> Dictionary:
	if Net.remote_client():
		if not Net.request_action("guild", payload):
			return {"error": "Slow down a moment."}
		return {"pending": true}
	var p = world.get("player") if world else null
	var near: bool = p != null and at_board((p as Node3D).global_position)
	var res := run_local(payload, near)
	if Net.online and Net.is_server() and not res.has("error"):
		# Listen host: tell the other members too.
		for note in res.get("notify", []):
			for h in note.get("holders", []):
				var peer := _peer_of_holder(str(h))
				if peer != 0:
					Net._send(peer, Net.net_system, [str(note.get("text", ""))])
	if res.has("announce") and not res.has("error"):
		Net.srv_announce(str(res["announce"]))
	_tags_t = 0.0
	return res


func on_net(kind: String, res: Dictionary) -> void:
	if kind == "guild_invite":
		var txt := "%s invites you to the guild %s [%s]. Type /guild accept, or open /guild." % [str(res.get("from", "Someone")), str(res.get("guild", "")), str(res.get("tag", ""))]
		Net.chat_received.emit("", txt, "system")
		if hud != null and hud.has_method("toast"):
			hud.toast("Guild invitation", "%s [%s]" % [str(res.get("guild", "")), str(res.get("tag", ""))], "Guild", UITheme.GOLD)
		if screen != null and screen.has_method("refresh_view") and hud != null and hud.life.guild_open():
			screen.refresh_view()
		return
	if kind != "guild":
		return
	if screen != null and screen.has_method("show_result") and hud != null and hud.life.guild_open():
		screen.show_result(res)
	else:
		# A chat command (/guild accept ...) answered by the server.
		var line := str(res["error"]) if res.has("error") else result_text(res)
		if line != "":
			Net.chat_received.emit("", line, "system")


func open(h: Node) -> void:
	hud = h
	if h == null or h.get("life") == null or not h.life.has_method("open_guild"):
		return
	screen = h.life.open_guild(self)


## Chat commands: "/g text" (guild chat) and "/guild [accept|decline|leave|
## invite Name]" (no argument opens the guild panel). Returns true when the
## line was a guild command. `system` prints a system line.
static func chat_command(text: String, hud_node: Node, system: Callable) -> bool:
	var t := text.strip_edges()
	var low := t.to_lower()
	if low == "/g" or low.begins_with("/g "):
		var body := t.substr(2).strip_edges()
		if body == "":
			system.call("Usage: /g message")
		else:
			Net.request_guild_chat(body)
		return true
	if not (low == "/guild" or low.begins_with("/guild ")):
		return false
	var node = hud_node.get_tree().get_first_node_in_group("guild_office") if hud_node and hud_node.is_inside_tree() else null
	if node == null:
		system.call("There is no guild office on this floor.")
		return true
	node.hud = hud_node
	var args := t.substr(6).strip_edges().split(" ", false, 1)
	var sub := args[0].to_lower() if args.size() > 0 else ""
	if sub == "":
		node.open(hud_node)
		return true
	var payload := {}
	match sub:
		"accept", "decline", "leave":
			payload = {"op": sub}
		"invite":
			if args.size() < 2:
				system.call("Usage: /guild invite Name")
				return true
			payload = {"op": "invite", "name": args[1].strip_edges()}
		_:
			system.call("Guild: /g message, /guild, /guild invite Name, /guild accept, /guild decline, /guild leave")
			return true
	var res: Dictionary = node.request(payload)
	if res.has("error"):
		system.call(str(res["error"]))
	elif not res.get("pending", false):
		system.call(result_text(res))
	return true


## One line describing a finished guild operation (chat and toasts).
static func result_text(res: Dictionary) -> String:
	match str(res.get("op", "")):
		"found":
			return "You founded %s [%s] for %d Col." % [str(res.get("founded", "")), str(res.get("tag", "")), int(res.get("paid", 0))]
		"invite":
			return "Invitation sent to %s." % str(res.get("invited", ""))
		"accept":
			return "Welcome to %s [%s]." % [str(res.get("joined", "")), str(res.get("tag", ""))]
		"decline":
			return "Invitation declined."
		"leave":
			return "You left %s." % str(res.get("left", "the guild"))
		"kick":
			return "%s was removed." % str(res.get("kick", ""))
		"promote":
			return "%s is now an Officer." % str(res.get("promote", ""))
		"demote":
			return "%s is a Member again." % str(res.get("demote", ""))
		"transfer":
			return "%s now leads the guild." % str(res.get("transfer", ""))
		"disband":
			return "%s has been disbanded." % str(res.get("disbanded", "The guild"))
		"deposit":
			return "Deposited %s." % str(res.get("deposited", ""))
		"withdraw":
			return "Took %s from the guild storage." % str(res.get("withdrawn", ""))
	return ""
