# Realm world DB and claim registry (P4)

Server-wide persistent state for unique skills (P5), limited items and quests (P6), player stalls, farm plots and guilds (P7/P8). Built 2026-10-25. Code: `scripts/realm_db.gd` (RealmDB), server glue in `autoload/net.gd` ("Realm world DB" section), record helpers in `scripts/record_state.gd`. Tests: `scenes/realm_test.tscn` (88 checks) plus one probe line in `smoke_test.gd`.

## Where it runs

| Mode | `Net.get_realm()` | Realm id | File |
|---|---|---|---|
| Dedicated / listen server | the realm | `--realm <id>`, default `server` | `user://realm_db/server.json` + `.journal` |
| Offline single player | a local realm | `local` | `user://realm_db/local.json` |
| Remote client | `null` | - | clients only see results of actions |

Decision: offline play uses a local realm so P5-P8 code runs the same API offline (a solo player trivially holds every slot). It is shared across the three save slots; the holder key offline is `local:<name>`. Only server code and offline code touch the realm; a client never does, exactly as with records today.

Several floor servers that share one `user://` folder and the same `--realm` id share one DB and therefore one set of unique holders. (Two processes writing the same journal concurrently is NOT supported yet; a floor-transfer design (backlog 10) must put one process in charge or add a lock file.)

Until the next `godot --headless --import` the global name `RealmDB` is not in the class cache: use `Net.get_realm()` for the instance and `Net.RealmDBScript.holder_key(...)` / `.holder_of_record(rec)` for the statics. After an import `RealmDB.holder_key(...)` works too.

## Holder identity

`holder_key(token, name) = sha256(token)[:16] + ":" + name.lower()`; for records `RealmDBScript.holder_of_record(rec)`. Server code: `Net.srv_holder(peer)`; on a RecordState `rs.holder()`; offline `Net.local_holder()`. The account token itself is never stored in the realm file.

## Data model (`user://realm_db/<realm>.json`)

```
version, realm, seq                 # seq = last applied transaction number
claims:    { limited_id: { cap, kind, holders: { holder: { since, state: "held"|"reserved",
                                                           expires (wall), online_left (s) } } } }
serials:   { serial: { limited_id, holder, item_id, minted, bound } }
containers:{ id: { owner, kind, col, items: [item dicts], meta, created } }
last_seen: { holder: unix }
pending:   { seq: { holder, delta: { col, remove: [item ids], add: [items] } } }   # escrow not yet settled
serial_counter
```
`kind` of a claim sets its inactivity rule: `INACTIVE_RELEASE = {skill: 14 d, item: 30 d, quest: 30 d, stall: 30 d, plot: 30 d}` (consts in realm_db.gd; Kyle's defaults).

## Durability (what you can rely on)

- Every mutation is one transaction: appended to `<realm>.journal` as a checksummed JSON line and flushed BEFORE it is applied in memory. If the journal cannot be written, the call fails (`ok: false`) and nothing is granted.
- A snapshot is rewritten atomically (temp + rename) every 64 transactions, on `flush()` (Net calls it every 60 s) and on `close()`. Load = snapshot + replay of journal lines newer than it; a torn tail line or a bad checksum ends the replay; a leftover `.json.tmp` is ignored and removed.
- `Net.save_record` is now atomic too (temp + rename).
- Escrow: `transact()` journals the moves, applies the container side, applies the record side in place and stamps `rec.realm_seq`. The caller saves the record and calls `settle(seq)` (`Net.srv_transact` does all of that). On every record load `reconcile_record(rec)` replays pending transactions with `seq > rec.realm_seq` exactly once, so a crash between the journal write and the record save neither duplicates nor loses Col or items.
- Consequences for callers: a claim that is `ok` is on disk. A record grant (item added to `rs`) is persisted by Net after the action like every other action; if the server dies in between, the next load finds a serial with no item, frees it and releases the item claim (heals toward "not held", never toward a duplicate).

## API (RealmDB instance = `Net.get_realm()`)

Claims
- `claim(limited_id, cap, holder, kind := "item") -> {ok, last, already, holders, error, seq}`: atomic grant of one of `cap` slots. `last` = this took the final slot (announce it). Idempotent for the same holder.
- `reserve(limited_id, cap, holder, timeout := 7200.0, online := true, kind := "quest")`: a slot that frees itself after `timeout` seconds of online time (Net ticks online holders once a second) or wall time (`online = false`). `confirm(limited_id, holder)` makes it permanent; fails once expired.
- `release(limited_id, holder) -> bool` (also frees that holder's serials of the id), `holders(id) -> Array`, `is_holder(id, holder)`, `slots_left(id, cap)`, `cap_of(id)`, `claims_of(holder)`.
- `touch(holder)`, `last_seen(holder)`, `tick_online(holders, dt)`, `sweep() -> [{id, holder, why: "expired"|"inactive"}]` (Net runs sweep every 60 s; inactivity releases call `announce`).
- `release_all(holder) -> Array`: character delete. `Net.srv_delete_character(name, token)` does this plus the record file.

Serials and bound items
- `bind_serial(limited_id, holder, item, bound := true) -> serial` stamps `item.serial`, `item.limited_id`, `item.bound`; refused unless the holder holds a claim on the id. Serial format `<realm>-<limited_id>-<000001>`.
- `verify_record(rec) -> removed[]`: run on every record load by Net. Removes items whose serial is unregistered, minted for another holder, duplicated inside the record, or missing while `limited_id` is set; frees serials the record no longer carries.
- `is_bound(item)`; `RecordState.item_bound(id)`. Bound items are refused by `transact()` (cannot leave the record); P7 must also refuse them in any drop / mail / trade UI it adds. Storing a bound item in the owner's own home storage is allowed.
- Convenience: `rs.grant_limited_item(limited_id, cap, item, bound := true)` = claim + bind_serial + add_item, returns the claim result. Limited item dicts must still be weapon/armor shaped (`kind`, `name`, `atk`/`def`) or `GameState._parse_items` on the client drops them; extend `_parse_items` when a new kind (cloak, trinket) arrives.

Containers and escrow
- `ensure_container(id, owner := "", kind := "generic", meta := {})`, `container(id)`, `containers_of(owner)`, `remove_container(id)` (only when empty). Suggested ids: `stall:<n>`, `till:<n>`, `plot:<n>`, `guild:<id>:storage`.
- `transact(rec, moves) -> {ok, seq, delta, error}` with moves `{"col": n, "from", "to"}` and `{"item": item_id, "from", "to"}`, each side `"record"` or a container id. All moves are validated first (enough Col, item present, bound items stay, inventory cap 60, container cap 200); then all or nothing. `rec` may be `{}` for container-to-container moves (a stall keeper selling to an NPC buyer, tax to a realm till).
- Server wrapper: `Net.srv_transact(peer, moves, reply_kind := "trade")` validates, saves the record, settles and answers the client with the usual patch (or `{error}`); handlers in `world.srv_action` can call it and return its result.

Announcements
- `Net.srv_announce(text)`: server / offline only. Clients receive `net_realm_announce`, everyone gets `Net.realm_announced(text)`, a system chat line, and nodes in group `"hud"` with `realm_announce(text)` are called (HUD side is open work).

Introspection: `summary()` (for a Legends board), `log` (last 200 realm log lines), `pending_count()`.

## Net hooks already in place
- `host()` opens the realm; `_go_offline()` closes it. `get_realm()` opens the local realm lazily offline.
- `_on_auth` (record load): `reconcile_record`, `verify_record`, `touch`, record re-saved when anything changed.
- `_on_peer_disconnected`: `touch`. `_on_persist_tick` (60 s): `touch` everyone online, `sweep`, `flush`. `_on_life_tick` (1 s): `tick_online` for limited-quest reservations.

## Recipes for P5-P8
- Unique skill (P5): on the hidden-stat threshold, server side: `var r = realm.claim("twin_fang", 1, rs.holder(), "skill")`; if `r.ok and not r.already`: write the skill onto the record, `Net.srv_announce(...)`. Cast validation: `realm.is_holder("twin_fang", Net.srv_holder(peer))` inside the action handler. The 14-day release is automatic; the 10-day warning mail is not built (compute from `last_seen`).
- Limited quest (P6): on accept `realm.reserve(quest_id, cap, holder, 7200.0, true)`; refuse with "someone has already taken this" when `ok` is false; on completion `realm.confirm(...)`; on abandon `realm.release(...)`.
- Limited item (P6): `rs.grant_limited_item("ember_cloak", 3, item)`; announce when `last`.
- Stall (P7): `ensure_container("stall:3", holder, "stall")` and `("till:3", holder, "till")`; stocking = `srv_transact(peer, [{"item": id, "from": "record", "to": "stall:3"}])`; a sale by the keeper = `transact(buyer_rec, [{"col": price, "from": "record", "to": "till:3"}, {"item": id, "from": "stall:3", "to": "record"}])` plus a 5 % tax move `{"col": tax, "from": "till:3", "to": "realm:tax"}` in the same call; rent = a `claim("stall:3", 1, holder, "stall")` renewed by `touch`.
- Guild storage (P8): one container per guild; membership is ordinary realm data you can add as a new top-level key with its own journal ops (`_apply` match) if the claim model does not fit.
  Built 2026-10-25 (scripts/life/guilds.gd): top-level key `guilds: {gid: {name, tag, created, members: {holder: {name, rank, since}}}}`, created lazily by the journal op `"guild"` (`{"id", "g": whole guild}` or `{"id", "remove": true}`), written only through `rdb.commit("guild", ...)`. Storage container `guild:<gid>` (kind "guild"); fee and rent sinks `realm:guilds`, `realm:farms`.
- Farm plots (P8, scripts/life/farms.gd): claim `plot:hb<i>` (cap 1, kind "plot") plus a container of the same id whose `meta` holds `owner_name`, `rent_until` and four beds `{crop, grown, at, watered, planted}`; growth is computed from those timestamps (LifeData.CROPS), never ticked.

## Known limits / left for Opus
- No HUD display of announcements (`realm_announce(text)` on a "hud" group node, or connect `Net.realm_announced`).
- No client-facing delete-character request (server function exists).
- No multi-process sharing of one realm file; no 10-day warning mail; no admin command to list/force-release claims (use `summary()`).
- `touch` is journaled at most hourly per holder (in-memory value exact), so after a crash `last_seen` can be up to an hour stale: harmless against 14/30-day limits.
