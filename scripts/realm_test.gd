extends Node
## Headless test of the realm world DB (scripts/realm_db.gd). Run with:
##   godot --headless --path . res://scenes/realm_test.tscn
## Prints "== Done: N failure(s)" and exits 1 on any failure.
## Works on a throwaway realm dir (user://realm_test_db) with an injected clock.

const RDB := preload("res://scripts/realm_db.gd")
const TEST_DIR := "user://realm_test_db"
const TOKEN_A := "0123456789abcdef0123456789abcdef"
const TOKEN_B := "fedcba9876543210fedcba9876543210"

var _fails := 0
var _now := 1_800_000_000.0  # injected clock, unix seconds


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		_fails += 1
		printerr("  FAIL ", what)


func _clock() -> float:
	return _now


func _wipe() -> void:
	var d := DirAccess.open(TEST_DIR)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(TEST_DIR + "/" + f)


func _open(id := "t") -> RDB:
	var db := RDB.open(id, TEST_DIR)
	db.clock = _clock
	return db


func _record(name: String, token: String, money := 100) -> Dictionary:
	var rec := Net.record_defaults()
	rec.merge({"name": name, "token": token, "level": 1, "xp": 0, "stats": {"strength": 3}, "character": {"name": name}}, true)
	rec["money"] = money
	return rec


func _item(id: String) -> Dictionary:
	return {"id": id, "name": "Blade " + id, "kind": "weapon", "rank": 1, "atk": 10, "def": 0}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	_wipe()
	var ha := RDB.holder_key(TOKEN_A, "Aria")
	var hb := RDB.holder_key(TOKEN_B, "Bren")
	var hc := RDB.holder_key("", "Solo")

	print("== Holder identity")
	_check(ha.ends_with(":aria") and ha.length() == 16 + 1 + 4 and not ha.contains(TOKEN_A.left(8)), "holder key = sha256(token)[:16]:name, token never stored in clear")
	_check(hc == "local:solo", "offline holder is local:<name>")
	_check(RDB.holder_key(TOKEN_A, "ARIA ") == ha, "holder key is case/space insensitive on the name")
	_check(RDB.holder_of_record(_record("Aria", TOKEN_A)) == ha, "holder_of_record matches holder_key")

	print("== Claim caps")
	var db := _open()
	_check(db.data["seq"] == 0 and db.holders("twin_fang").is_empty(), "fresh realm is empty")
	var r1: Dictionary = db.claim("twin_fang", 1, ha, "skill")
	_check(r1["ok"] and r1["last"] and not r1["already"], "first claim of a cap-1 id is granted and takes the last slot")
	var r2: Dictionary = db.claim("twin_fang", 1, hb, "skill")
	_check(not r2["ok"] and r2["holders"] == [ha], "second holder refused on cap 1: %s" % r2.get("error", ""))
	_check(db.claim("twin_fang", 1, ha, "skill")["already"], "re-claim by the holder is idempotent")
	_check(db.is_holder("twin_fang", ha) and not db.is_holder("twin_fang", hb), "is_holder")
	var hs3 := [ha, hb, hc]
	for h in hs3:
		_check(db.claim("ember_cloak", 3, h)["ok"], "cap-3 slot for %s" % h)
	_check(not db.claim("ember_cloak", 3, RDB.holder_key(TOKEN_A, "Fourth"))["ok"] and db.slots_left("ember_cloak", 3) == 0, "fourth holder refused on cap 3")
	_check(db.release("ember_cloak", hb) and db.slots_left("ember_cloak", 3) == 1 and not db.release("ember_cloak", hb), "release frees a slot once")
	_check(not db.claim("", 1, ha)["ok"] and not db.claim("x", 1, "")["ok"], "empty id / holder refused")
	_check(db.claims_of(ha).size() == 2, "claims_of lists both claims of a holder")

	print("== Concurrent claims (interleaved burst)")
	var granted := 0
	for i in 50:
		var h := RDB.holder_key(TOKEN_B, "racer%d" % i)
		if db.claim("race_prize", 2, h)["ok"]:
			granted += 1
	_check(granted == 2 and db.holders("race_prize").size() == 2, "50 racers on a cap-2 id: exactly 2 granted (%d)" % granted)
	var th := Thread.new()
	var thread_ok: Array = [0]
	th.start(func():
		for i in 30:
			if db.claim("thread_prize", 1, RDB.holder_key(TOKEN_A, "t%d" % i))["ok"]:
				thread_ok[0] += 1)
	var main_ok := 0
	for i in 30:
		if db.claim("thread_prize", 1, RDB.holder_key(TOKEN_B, "m%d" % i))["ok"]:
			main_ok += 1
	th.wait_to_finish()
	_check(thread_ok[0] + main_ok == 1 and db.holders("thread_prize").size() == 1, "two threads racing a cap-1 id: one winner (%d+%d)" % [thread_ok[0], main_ok])

	print("== Reservations")
	var q: Dictionary = db.reserve("hidden_quest", 1, ha, 100.0, false)
	_check(q["ok"] and db.is_holder("hidden_quest", ha), "wall-time reservation holds the slot")
	_check(not db.reserve("hidden_quest", 1, hb, 100.0, false)["ok"], "second reservation refused while held")
	_now += 60.0
	_check(db.is_holder("hidden_quest", ha), "still held before the timeout")
	_now += 41.0
	_check(not db.is_holder("hidden_quest", ha) and db.holders("hidden_quest").is_empty(), "wall reservation expires after 100 s")
	_check(not db.confirm("hidden_quest", ha)["ok"], "confirm after expiry fails")
	_check(db.reserve("hidden_quest", 1, hb, 100.0, false)["ok"], "the freed slot can be reserved again")
	_now += 50.0
	_check(db.confirm("hidden_quest", hb)["ok"] and db.confirm("hidden_quest", hb)["already"], "confirm makes it permanent (idempotent)")
	_now += 1000.0
	_check(db.is_holder("hidden_quest", hb), "confirmed claim survives the old timeout")
	var oq: Dictionary = db.reserve("online_quest", 1, ha, 100.0, true)
	_check(oq["ok"], "online-time reservation")
	_now += 100_000.0
	_check(db.is_holder("online_quest", ha), "online-time reservation ignores wall time")
	db.tick_online([ha], 60.0)
	_check(db.is_holder("online_quest", ha), "60 s online: still held")
	db.tick_online([hb], 60.0)
	_check(db.is_holder("online_quest", ha), "someone else's online time does not count")
	db.tick_online([ha], 41.0)
	_check(not db.is_holder("online_quest", ha), "101 s online: reservation freed")
	_check(db.reserve("online_quest", 1, ha, 50.0, true)["ok"], "re-reserve after online timeout")
	db.tick_online([ha], 60.0)
	var swept: Array = db.sweep()
	_check(swept.size() == 1 and swept[0]["why"] == "expired" and db.holders("online_quest").is_empty(), "sweep reports the expired reservation")

	print("== Inactivity sweep")
	var announced: Array = []
	db.announce = func(t: String): announced.append(t)
	var t0 := _now
	_check(db.claim("item_relic", 1, hb, "item")["ok"], "item claim for the sweep")
	_now = t0 + 13 * 86400
	db.touch(ha)  # Aria active at day 13
	_now = t0 + 15 * 86400
	swept = db.sweep()
	_check(swept.is_empty() and db.is_holder("twin_fang", ha), "unique skill kept: holder seen 2 days ago")
	_now = t0 + 13 * 86400 + RDB.INACTIVE_RELEASE["skill"] + 1
	swept = db.sweep()
	var ids := []
	for s in swept:
		ids.append(s["id"])
	_check(ids.has("twin_fang") and not db.is_holder("twin_fang", ha), "unique skill released after 14 days away")
	_check(db.is_holder("item_relic", hb), "limited item kept at %d days" % int((_now - t0) / 86400))
	_check(announced.size() >= 1, "inactivity release is announced")
	_now = t0 + RDB.INACTIVE_RELEASE["item"] + 1
	swept = db.sweep()
	_check(not db.is_holder("item_relic", hb), "limited item released after 30 days")
	_check(db.claim("twin_fang", 1, hb, "skill")["ok"], "the freed unique skill can be claimed by someone else")

	print("== Serials")
	var ra := _record("Aria", TOKEN_A)
	_check(db.claim("ember_blade", 2, ha, "item")["ok"], "claim before minting")
	var blade := _item("ember_1")
	var serial := db.bind_serial("ember_blade", ha, blade)
	_check(serial != "" and blade["serial"] == serial and blade["bound"] and blade["limited_id"] == "ember_blade", "bind_serial stamps serial/limited_id/bound")
	_check(db.bind_serial("ember_blade", hb, _item("x")) == "", "no serial without a claim")
	var s2 := db.bind_serial("ember_blade", ha, _item("ember_2"))
	_check(s2 != serial and db.serial_info(s2)["holder"] == ha, "serials are unique and registered")
	ra["inventory"] = [blade, blade.duplicate(true), {"id": "fake", "name": "Fake", "kind": "weapon", "serial": "t-ember_blade-000999", "limited_id": "ember_blade"},
		{"id": "nos", "name": "No serial", "kind": "weapon", "limited_id": "ember_blade"}, _item("plain")]
	ra["equipped"]["weapon"] = blade
	var removed: Array = db.verify_record(ra)
	_check(removed.size() == 3 and ra["inventory"].size() == 2 and ra["inventory"][0]["serial"] == serial and ra["inventory"][1]["id"] == "plain", "verify removes the duplicate, the unregistered and the serial-less copy: %s" % str(removed))
	_check(ra["equipped"]["weapon"] != null, "the genuine equipped copy stays")
	_check(db.serial_info(s2).is_empty() and db.is_holder("ember_blade", ha), "a serial the record no longer carries is freed; the claim stays while one serial remains")
	var rb := _record("Bren", TOKEN_B)
	rb["inventory"] = [blade.duplicate(true)]
	_check(db.verify_record(rb).size() == 1 and rb["inventory"].is_empty(), "another holder carrying Aria's serial loses it")
	_check(db.serial_info(serial)["holder"] == ha, "Aria's serial untouched by Bren's check")
	ra["inventory"] = []
	ra["equipped"]["weapon"] = null
	db.verify_record(ra)
	_check(not db.is_holder("ember_blade", ha) and db.serial_info(serial).is_empty(), "losing the last serial releases the item claim")
	var rs_rec := _record("Cass", TOKEN_A)
	var rs = Net.RecordState.new(rs_rec)
	var gi: Dictionary = rs.grant_limited_item("ember_blade", 2, _item("cass_blade"))
	_check(gi["ok"] and rs_rec["inventory"].size() == 1 and rs.item_bound("cass_blade"), "RecordState.grant_limited_item claims, mints and binds (via Net's local realm)")
	Net.get_realm().release_all(rs.holder())

	print("== Escrow")
	var rec := _record("Aria", TOKEN_A, 100)
	rec["inventory"] = [_item("sword"), _item("keep")]
	db.ensure_container("stall:1", ha, "stall")
	db.ensure_container("till:1", ha, "till")
	_check(db.container("stall:1")["owner"] == ha and db.containers_of(ha) == ["stall:1", "till:1"], "containers created with an owner")
	var t: Dictionary = db.transact(rec, [{"col": 40, "from": "record", "to": "till:1"}, {"item": "sword", "from": "record", "to": "stall:1"}])
	_check(t["ok"] and rec["money"] == 60 and rec["inventory"].size() == 1 and db.container("till:1")["col"] == 40 and db.container("stall:1")["items"].size() == 1, "col + item move into containers")
	_check(rec["realm_seq"] == t["seq"] and db.pending_count() == 1, "record carries the realm_seq watermark; transaction pending until settled")
	db.settle(int(t["seq"]))
	_check(db.pending_count() == 0, "settle clears it")
	var bad: Dictionary = db.transact(rec, [{"col": 30, "from": "record", "to": "till:1"}, {"col": 50, "from": "record", "to": "till:1"}])
	_check(not bad["ok"] and rec["money"] == 60 and db.container("till:1")["col"] == 40, "insufficient Col across two moves: nothing changes (%s)" % bad.get("error", ""))
	_check(not db.transact(rec, [{"item": "ghost", "from": "record", "to": "stall:1"}])["ok"], "missing item refused")
	_check(not db.transact(rec, [{"col": 10, "from": "record", "to": "nowhere"}])["ok"], "unknown container refused")
	_check(not db.transact({}, [{"col": 10, "from": "record", "to": "till:1"}])["ok"], "record move without a record refused")
	_check(db.claim("bound_relic", 1, ha, "item")["ok"], "claim for a bound item")
	var relic := _item("relic")
	db.bind_serial("bound_relic", ha, relic)
	rec["inventory"].append(relic)
	_check(not db.transact(rec, [{"item": "relic", "from": "record", "to": "stall:1"}])["ok"], "bound item cannot leave the record")
	var t2: Dictionary = db.transact(rec, [{"item": "sword", "from": "stall:1", "to": "record"}, {"col": 40, "from": "till:1", "to": "record"}])
	_check(t2["ok"] and rec["money"] == 100 and rec["inventory"].size() == 3 and db.container("stall:1")["items"].is_empty(), "moves back out of containers")
	var t3: Dictionary = db.transact({}, [{"col": 40, "from": "till:1", "to": "stall:1"}])
	_check(not t3["ok"], "container to container needs Col there: refused when empty")
	# Crash between journal and record save: the record on disk never saw the
	# transaction. reconcile_record replays it exactly once.
	var rec_disk := rec.duplicate(true)  # what the record file still says
	var t4: Dictionary = db.transact(rec, [{"col": 25, "from": "record", "to": "till:1"}, {"item": "keep", "from": "record", "to": "stall:1"}])
	_check(t4["ok"] and db.data["pending"].has(str(t4["seq"])), "transaction journaled, not settled")
	var n := db.reconcile_record(rec_disk)
	_check(n == 1 and rec_disk["money"] == 75 and rec_disk["inventory"].size() == 2 and rec_disk["realm_seq"] == t4["seq"], "reconcile applies the pending delta to the stale record")
	_check(db.reconcile_record(rec_disk) == 0 and rec_disk["money"] == 75, "reconcile is idempotent")
	_check(db.pending_count() == 0, "reconcile settles every pending transaction of the holder (t2 and t4)")
	_check(db.container("till:1")["col"] == 25 and db.container("stall:1")["items"].size() == 1, "container side unchanged by reconcile")

	print("== Durability")
	var seq_before: int = db.data["seq"]
	var held_before: Array = db.summary()["claims"].keys()
	held_before.sort()
	# 1) Reopen without close(): everything must come back from the journal.
	var db2 := _open()
	var held_after: Array = db2.summary()["claims"].keys()
	held_after.sort()
	_check(db2.data["seq"] == seq_before and held_after == held_before and db2.container("till:1")["col"] == 25, "reopen replays the journal (seq %d, %d claims)" % [seq_before, held_after.size()])
	_check(db2.serial_info(relic["serial"])["holder"] == ha, "serials survive the reopen")
	db = null  # (never close() a realm another instance has open: close compacts)
	# 2) Torn journal tail: a half-written line must be dropped, the rest kept.
	_check(db2.claim("after_reopen", 1, hb)["ok"], "claim on the reopened realm")
	var jf := FileAccess.open(db2.journal_path(), FileAccess.READ_WRITE)
	jf.seek_end()
	jf.store_string("12345678 {\"s\": 9999, \"op\": \"claim\", \"a\": {\"id\": \"torn\", \"cap\": 1, \"hol")
	jf.close()
	db2 = null
	var db3 := _open()
	_check(db3.is_holder("after_reopen", hb) and db3.holders("torn").is_empty() and db3.data["seq"] == seq_before + 1, "torn tail dropped, valid prefix kept")
	# 3) Torn snapshot temp file is ignored, snapshot itself is still read.
	db3.flush()
	var tmp := FileAccess.open(db3.snapshot_path() + ".tmp", FileAccess.WRITE)
	tmp.store_string("{\"realm\": \"t\", \"seq\": 1, \"claims\": {")
	tmp.close()
	db3 = null
	var db4 := _open()
	_check(db4.is_holder("after_reopen", hb) and not FileAccess.file_exists(db4.snapshot_path() + ".tmp"), "torn snapshot temp ignored and removed; compacted snapshot loads")
	# 4) A corrupt line in the middle: everything after it is dropped, nothing before is lost.
	_check(db4.claim("mid_a", 1, ha)["ok"] and db4.claim("mid_b", 1, hb)["ok"], "two more claims")
	var text := FileAccess.get_file_as_string(db4.journal_path())
	var lines := text.split("\n", false)
	lines[0] = "deadbeef " + lines[0].substr(9)  # wrong checksum on the first journal line
	var jw := FileAccess.open(db4.journal_path(), FileAccess.WRITE)
	jw.store_string("\n".join(lines) + "\n")
	jw.close()
	db4 = null
	var db5 := _open()
	_check(db5.is_holder("after_reopen", hb) and not db5.is_holder("mid_a", ha), "checksum failure stops the replay at the bad line")
	# 5) Compaction every COMPACT_EVERY commits; the realm survives a reopen after many commits.
	for i in RDB.COMPACT_EVERY * 2 + 5:
		db5.claim("bulk_%d" % i, 1, ha)
	var bulk_seq: int = db5.data["seq"]
	var db6 := _open()
	_check(db6.data["seq"] == bulk_seq and db6.is_holder("bulk_%d" % (RDB.COMPACT_EVERY * 2), ha) and db6.is_holder("after_reopen", hb), "compaction + journal round-trip after %d commits" % (RDB.COMPACT_EVERY * 2 + 5))
	db5 = null
	# 6) Journal write failure: the claim must be refused, not granted in memory.
	db6._journal.close()
	var ro := FileAccess.open(TEST_DIR + "/readonly.journal", FileAccess.WRITE)
	ro.close()
	db6._journal = FileAccess.open(TEST_DIR + "/readonly.journal", FileAccess.READ)  # read-only handle: writes fail
	var rf: Dictionary = db6.claim("unwritable", 1, ha)
	_check(not rf["ok"] and not db6.is_holder("unwritable", ha), "a claim the journal cannot record is refused")
	db6._journal = null
	db6._open_journal(false)
	_check(db6.claim("unwritable", 1, ha)["ok"], "and granted once the journal is back")

	print("== Character delete")
	var before := db6.claims_of(ha).size()
	var rel: Array = db6.release_all(ha)
	_check(rel.size() == before and db6.claims_of(ha).is_empty() and db6.serial_info(relic["serial"]).is_empty() and db6.container("till:1")["owner"] == "", "release_all frees claims, serials and container ownership")
	_check(db6.is_holder("after_reopen", hb), "other holders untouched")
	db6.close()

	print("== Net integration")
	_check(Net.get_realm() != null and Net.get_realm().realm_id == "local" and Net.realm == Net.get_realm(), "offline Net opens the local realm lazily")
	_check(Net.srv_holder(1) == Net.local_holder() and Net.local_holder().begins_with("local:"), "host / offline holder")
	var got: Array = []
	Net.realm_announced.connect(func(t2: String): got.append(t2))
	Net.srv_announce("The realm stirs.")
	_check(got == ["The realm stirs."], "srv_announce reaches the realm_announced signal offline")
	var drec := Net._new_record(Net.sanitize_character({"name": "Doomed"}), TOKEN_B, {})
	Net.save_record(drec)
	_check(FileAccess.file_exists(Net.record_path("Doomed")) and not FileAccess.file_exists(Net.record_path("Doomed") + ".tmp"), "atomic record save leaves no temp file")
	Net.get_realm().claim("doom_relic", 1, Net.RealmDBScript.holder_of_record(drec))
	var del: Dictionary = Net.srv_delete_character("Doomed", "wrong")
	_check(not del["ok"], "delete with the wrong token refused")
	del = Net.srv_delete_character("Doomed", TOKEN_B)
	_check(del["ok"] and del["released"].size() == 1 and not FileAccess.file_exists(Net.record_path("Doomed")) and Net.get_realm().holders("doom_relic").is_empty(), "delete frees the claim and removes the record")
	# Record load path: a stale record with a pending trade and a dupe gets fixed in _realm_check_record.
	var lrec := Net._new_record(Net.sanitize_character({"name": "Loader"}), TOKEN_A, {})
	var lh: String = Net.RealmDBScript.holder_of_record(lrec)
	Net.get_realm().claim("load_relic", 1, lh, "item")
	var litem := _item("load_item")
	Net.get_realm().bind_serial("load_relic", lh, litem)
	lrec["inventory"] = [litem, litem.duplicate(true)]
	Net.get_realm().ensure_container("till:load", lh, "till")
	var saved_copy := lrec.duplicate(true)
	Net.get_realm().transact(lrec, [{"col": 10, "from": "record", "to": "till:load"}])  # not settled: "crash"
	Net._realm_check_record(saved_copy)
	_check(saved_copy["money"] == 40 and saved_copy["inventory"].size() == 1 and Net.get_realm().pending_count() == 0, "_realm_check_record reconciles the trade and drops the duplicate serial")
	Net.get_realm().transact(saved_copy, [{"col": 10, "from": "till:load", "to": "record"}])
	Net.get_realm().release_all(lh)
	DirAccess.remove_absolute(Net.record_path("Loader"))
	_check(Net.get_realm().remove_container("till:load") and Net.get_realm().container("till:load").is_empty(), "drained container removed (local realm left clean)")
	Net.get_realm().flush()

	_wipe()
	DirAccess.remove_absolute(TEST_DIR)
	print("== Done: %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
