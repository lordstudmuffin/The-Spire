extends Node3D
## A floor of the Spire. GameState.floor picks the builder: Floor 1 "Town of
## First Light" (_build_floor1: island, Hollowbrook, Talven camp, the
## Labyrinth tower with two terraces and the Guardian's summit) or Floor 2
## "Mirewood" (_build_floor2: misty autumn woods, the Mere, Thornwick, the
## Sunken Barrow and a second Labyrinth; art in scripts/world_floor2.gd).
## The gameplay layer (pads, gates, boss, quests, NPCs, mobs) is shared and
## reads the per-floor layout variables below.

const ARENA_RADIUS := 18.0
const LAB_RADIUS := 14.0
## Per-floor layout; Floor 1 values by default (WorldArt holds the anchors),
## _build_floor2 overrides them.
var FLOOR_RADIUS := WorldArt.FLOOR1_RADIUS
var TOWER_POS := Vector3(WorldArt.TOWER.x, 0, WorldArt.TOWER.y)
var GATE_LEVEL := 5
var ARENA_POS := TOWER_POS + Vector3(0, 222, 0)  # Top of the Labyrinth tower.
## Labyrinth: open-air terraces climbing the tower before the summit.
var LAB_LEVELS := [TOWER_POS + Vector3(30, 70, 0), TOWER_POS + Vector3(-30, 140, 0)]
var _rune := Color("b06bff")               # summit rune colour
var _terrace_runes := [Color(0.4, 0.8, 1.0), Color("ff9f4a")]
var _gate_tint := Color("3b2a66")          # Labyrinth door slab
var _gate_glow := Color("8a3cff")

## Teleport pads: {pos, label, dest} where dest is a Vector3 or "summit".
var _pads: Array = []

var player: Player
var hud: HUD
var _rng := RandomNumberGenerator.new()
var _art_rng := RandomNumberGenerator.new()  # Decoration only; never shifts gameplay layout.
var _vein_positions: Array = []
var _players: Node3D
var _mobs: Node3D
var _player_spawner: MultiplayerSpawner
var _mob_spawner: MultiplayerSpawner
## Life layer (scripts/life/): fishing spots, herbs, camp fires, the cottage.
var _fishing: Fishing
var _herbs: HerbField
var _home: PlayerHome
## The Hollow Hearth, Rook's tavern in Hollowbrook (scripts/life/tavern.gd); null off Floor 1.
var _tavern: Tavern
## Hollowbrook Forge, Smith Kesra's workshop and commissions (scripts/life/smithy.gd).
var _smithy: Smithy
## NPCs whose anvil opens the forge panel (and passes the server's anvil check).
const SMITHS := ["Smith Haldor", "Smith Orla", "Smith Kesra"]
## Hollowbrook market stalls (P7, scripts/life/stalls.gd); null off Floor 1.
var _stalls: Node3D = null
## Hollowbrook farm field and the guild notice board (P8, scripts/life/farms.gd,
## scripts/life/guilds.gd); null off Floor 1.
var _farms: Node3D = null
## Floor 1 Labyrinth chests, vaults and spike traps (scripts/labyrinth_features.gd).
var _lab: Node3D = null
## Floor 1 villagers' day/night walks (scripts/npc_routines.gd).
var _routines: Node = null
var _monument: Node = null
var _results: Node = null
var _guilds: Node3D = null
## Player duels (scripts/duels.gd): server state + client events.
var _duels: Node = null
var _campfires: Array = []  # {"pos", "range", "label", "where"}
## Floor 1 waystones around the Talven fields (Scout Fen's visit quest):
## {"pos", "beacon": i, "lit": bool, "fx": Node3D}. Lit state mirrors
## GameState.visited ("waystone_i"); the server validates "waystone" actions.
const BEACONS := [Vector3(-90, 0, -150), Vector3(-60, 0, -204), Vector3(21, 0, -129)]
const BEACON_RANGE := 2.8
var _beacons: Array = []
var _life_keep: Array = []  # [pos, radius] kept clear of vegetation


func _ready() -> void:
	_rng.seed = 1  # Same layout every run (and identical on every peer).
	_art_rng.seed = 7
	_players = Node3D.new()
	_players.name = "Players"
	add_child(_players)
	_mobs = Node3D.new()
	_mobs.name = "Mobs"
	add_child(_mobs)
	if Net.online:
		_player_spawner = MultiplayerSpawner.new()
		_player_spawner.name = "PlayerSpawner"
		_player_spawner.spawn_path = NodePath("../Players")
		_player_spawner.spawn_function = _spawn_player_fn
		_player_spawner.spawn_limit = Net.MAX_PLAYERS + 1  # clients plus the host
		add_child(_player_spawner)
		_mob_spawner = MultiplayerSpawner.new()
		_mob_spawner.name = "MobSpawner"
		_mob_spawner.spawn_path = NodePath("../Mobs")
		_mob_spawner.spawn_function = _spawn_mob_fn
		_mob_spawner.spawn_limit = 200
		add_child(_mob_spawner)
	if GameState.floor == 2:
		await LoadingScreen.step("Raising the Mirewood", 0.15)
		await _build_floor2()
	else:
		await _build_floor1()
	LoadingScreen.done()

	if not Net.dedicated:
		hud = HUD.new()
		add_child(hud)
		hud.menus_closed.connect(func():
			if player:
				player.input_enabled = true)
		hud.chat_open_changed.connect(func(open):
			if player:
				player.input_enabled = not open)
		hud.send_chat = func(text):
			if Net.online:
				say.rpc_id(1, text)
			else:
				say(text)
		hud.toast("Floor %d  ·  %s" % [GameState.floor, GameState.floor_name()] + ("  ·  online" if Net.online else ""))

	# Test hooks: --report prints world state every 5 s, --bot makes the local player wander.
	var args := OS.get_cmdline_user_args()
	if "--report" in args:
		var t := Timer.new()
		t.wait_time = 5.0
		t.autostart = true
		t.timeout.connect(_print_report)
		add_child(t)
	_bot_mode = "--bot" in args
	_cheat_mode = "--cheat" in args
	_summit_mode = "--summit" in args
	_duel_mode = "--duel" in args
	_duels = preload("res://scripts/duels.gd").build(self)
	_duels.hud = hud
	GameState.inventory_changed.connect(_track_ore_quest)
	GameState.gear_state.connect(gear_notice)
	if Net.remote_client():
		Net.action_applied.connect(_on_net_action)

	if Net.online and not multiplayer.is_server():
		# Disconnected again in _exit_tree: a stale lambda on a freed world
		# would fire on the next session's disconnect.
		_on_server_lost = func():
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		Net.server_disconnected.connect(_on_server_lost)

	var spawn_pos: Vector3 = GameState.position if GameState.has_position else GameState.spawn_point()
	if not Net.online:
		_players.add_child(_spawn_player_fn({"peer": 1, "character": GameState.character, "pos": [spawn_pos.x, spawn_pos.y, spawn_pos.z]}))
	else:
		if multiplayer.is_server():
			multiplayer.peer_connected.connect(_on_peer_joined)
			multiplayer.peer_disconnected.connect(_on_peer_left)
			Net.linger_ended.connect(func(peer: int):
				Enemy.forget_peer(peer)
				if is_instance_valid(_players) and _players.has_node(str(peer)):
					_players.get_node(str(peer)).queue_free()
					print("Lingering body left: peer %d" % peer))
			# The Guardian wakes when the server sees a player on the summit
			# (a client's request_boss can beat its teleported position here).
			var st := Timer.new()
			st.wait_time = 1.0
			st.autostart = true
			st.timeout.connect(_srv_summit_check)
			add_child(st)
			# One server = one floor: tell every connecting peer which floor
			# this is during the auth handshake, before its world is built
			# (the main menu waits for this before loading the world).
			multiplayer.peer_authenticating.connect(func(peer: int):
				# A joining client builds its whole floor before it can answer;
				# give ENet more patience than its 5 s default so a slow first
				# load (Floor 2 streams more props) is not dropped mid-handshake.
				var ep := multiplayer.multiplayer_peer
				if ep is ENetMultiplayerPeer and ep.get_peer(peer):
					ep.get_peer(peer).set_timeout(32, 20000, 40000)
				multiplayer.send_auth(peer, var_to_bytes({"floor": GameState.floor})))
			if not Net.dedicated:
				_spawn_player_for(1, Net.sanitize_character(GameState.character))
		else:
			# Hand the server our character; it admits us (and sends the world)
			# only after this arrives, so nothing spawns before this scene exists.
			Net.send_character(GameState.character)


var _bot_mode := false
## Soak hook (--bot --summit): skip chores, take the pad to the summit and
## fight the Guardian; re-enter after each death.
var _summit_mode := false
var _summit_next := 6.0
## Soak hook (--bot --duel): meet outside the north gate and duel once.
var _duel_mode := false
var _cheat_mode := false


func _print_report() -> void:
	var who := "server" if Net.is_server() else "peer %d" % multiplayer.get_unique_id()
	var ps := []
	for p in get_tree().get_nodes_in_group("players"):
		ps.append("%s@(%.1f,%.1f,%.1f)" % [p.display_name, p.global_position.x, p.global_position.y, p.global_position.z])
	var mobs := get_tree().get_nodes_in_group("enemies").size()
	var parried := 0
	for p in get_tree().get_nodes_in_group("players"):
		parried += int(p.get("parries"))
	var alive := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.visible:
			alive += 1
	if _boss != null and is_instance_valid(_boss) and _boss.brain != null and _boss.brain.has_method("report"):
		print("[report %s] boss %s" % [who, _boss.brain.report()])
	print("[report %s] players=%s mobs=%d visible=%d me=Lv%d xp=%d col=%d hides=%d parries=%d | objs=%d nodes=%d orphans=%d mem=%dKB" % [
		who, ", ".join(ps), mobs, alive, GameState.level, GameState.xp, GameState.money, GameState.materials.get("beast_hide", 0), parried,
		Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1024)])


# --- Networking ----------------------------------------------------------

## Server: a peer finished the join handshake; its sanitized character is in Net.
func _on_peer_joined(peer: int) -> void:
	var character: Dictionary = Net.pending_characters.get(peer, Net.sanitize_character({}))
	Net.pending_characters.erase(peer)
	_spawn_player_for(peer, character)
	sync_floor_state.rpc_id(peer, _floor_cleared_on_server)
	if day_night:
		day_night.sync_time.rpc_id(peer, day_night.time_of_day)
	chat_line.rpc("Spire", "%s arrived on Floor %d." % [character["name"], GameState.floor])


func _spawn_player_for(peer: int, character: Dictionary) -> void:
	if _players.has_node(str(peer)):
		return
	var sp := GameState.spawn_point()
	_player_spawner.spawn({"peer": peer, "character": character, "pos": [sp.x, sp.y, sp.z]})
	print("Player joined: %s (peer %d), %d online" % [character["name"], peer, _players.get_child_count()])


func _on_peer_left(peer: int) -> void:
	_last_chat_ms.erase(peer)
	if _duels != null:
		_duels.on_peer_left(peer)
	if Net.is_lingering(peer):
		# Permadeath body left mid-fight: it stays, still and unguarded,
		# until Net.linger_ended (Permadeath.LINGER_SECS).
		var body := _players.get_node_or_null(str(peer))
		if body:
			body.set("blocking", false)
			body.set("lingering", true)
		return
	Enemy.forget_peer(peer)
	if _players.has_node(str(peer)):
		_players.get_node(str(peer)).queue_free()
		print("Player left: peer %d" % peer)


## Runs on every peer when a player is spawned (and locally offline).
func _spawn_player_fn(data: Dictionary) -> Node:
	var p := Player.new()
	p.peer_id = int(data["peer"])
	p.name = str(p.peer_id)
	p.appearance = data["character"].duplicate()
	p.display_name = data["character"].get("name", "")
	var pos: Array = data["pos"]
	p.position = Vector3(pos[0], pos[1], pos[2])
	p.build()
	if not Net.online or p.peer_id == multiplayer.get_unique_id():
		player = p
		p.bot = _bot_mode
		p.interact_pressed.connect(_on_interact)
		if _fishing:
			_fishing.setup(self, p, hud)
	return p


func _spawn_mob_fn(data: Dictionary) -> Node:
	var e := Enemy.from_data(data)
	if str(data.get("brain", "")) != "":
		# Boss state machine (scripts/boss_brain.gd) on every peer: the same
		# child path everywhere so its events arrive; only the authority ticks.
		var brain := BossBrain.new()
		brain.name = "BossBrain"
		brain.preset = str(data["brain"])
		brain.arena_center = ARENA_POS
		brain.arena_radius = ARENA_RADIUS
		if brain.preset == "warlord" and GameState.floor == 1:
			brain.throne = throne_pos()
		if Net.is_authority():
			brain.spawn_adds = _guardian_adds
		e.add_child(brain)
		e.brain = brain
	if data.get("la") is Dictionary and not data.get("boss", false) and Net.is_authority():
		var la: Dictionary = data["la"]
		var foe := str(data.get("name", "the foe"))
		e.died.connect(func(x): _grant_last_attack(x._last_hitter, la, foe))
	if data.get("boss", false) and Net.is_authority():
		_boss = e
		e.died.connect(_on_boss_died)
		if GameState.floor == 2:
			e.summon = _boss_summon
	return e


## Creates a mob on the server (replicated) or locally when offline. Returns
## the node on the authority (null on a client, which gets it replicated).
func _spawn_mob(data: Dictionary) -> Node:
	# Ground mobs were laid out for the flat disc at y = 1: lift them onto the
	# hills (terrace and summit mobs are far above the ground and keep theirs).
	if WorldArt.terrain_on and data.has("pos"):
		var p: Array = data["pos"]
		var gy := WorldArt.height_at(Vector2(float(p[0]), float(p[2])))
		if float(p[1]) < gy + 1.0:
			data["pos"] = [p[0], gy + 1.0, p[2]]
	if Net.online:
		if multiplayer.is_server():
			return _mob_spawner.spawn(data)
		return null
	var e := _spawn_mob_fn(data)
	_mobs.add_child(e)
	return e


var _last_chat_ms := {}


## Client asks the server to say something; the server names and relays it.
@rpc("any_peer", "call_local", "reliable")
func say(text: String) -> void:
	if not Net.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var now := Time.get_ticks_msec()
	if now - int(_last_chat_ms.get(peer, -10000)) < 500:
		return
	_last_chat_ms[peer] = now
	var who: String = GameState.character["name"] if peer == 1 else "?"
	if _players.has_node(str(peer)):
		who = _players.get_node(str(peer)).display_name
	if Net.online:
		chat_line.rpc(who, text.left(200))
	else:
		chat_line(who, text.left(200))


@rpc("authority", "call_local", "reliable")
func chat_line(sender_name: String, text: String) -> void:
	if hud:
		hud.add_chat(sender_name.left(16), text.left(200))


var _arena_lit := false


## -1 unknown, 0 outer field, 1 inside a settlement's Inner Area.
var _inner_state := -1


## Entering or leaving a settlement's Inner Area (Duels.SAFE_ZONES): no
## monster follows you inside. The HUD says so on every crossing.
func _inner_area_check() -> void:
	if GameState.floor != 1:
		return
	var inside := 1 if Duels.in_safe_zone(player.global_position) else 0
	if inside == _inner_state:
		return
	var first := _inner_state == -1
	_inner_state = inside
	if first:
		return
	if inside == 1:
		hud.toast("INNER AREA", "Monsters cannot follow you here", "", Color(0.55, 0.9, 1.0))
		Audio.play("notify")
	else:
		hud.toast("OUTER FIELD", "Monsters roam beyond the walls", "", Color(1.0, 0.7, 0.4))
		Audio.play("notify")
	var fx := VFX.get_for(player)
	if fx and fx.has_method("inner_area_notice"):
		fx.call("inner_area_notice", inside == 1)


func _process(_delta: float) -> void:
	if player == null or hud == null:
		return
	var near := _nearest_interactable()
	hud.set_prompt("[E] " + near[1] if near[0] else "")
	_inner_area_check()
	# The summit braziers only burn (as lights) while the local player is up there.
	var lit := player.global_position.distance_to(ARENA_POS) < ARENA_RADIUS + 40.0
	if lit != _arena_lit:
		_arena_lit = lit
		for l in get_tree().get_nodes_in_group("arena_lights"):
			l.visible = lit
	# Offline, walking into the opened summit gate carries you to the next floor.
	if _floor_gate_ready() and not Net.online and not _traveling and player.global_position.distance_to(_gate_pos + Vector3(0, 0, 1.2)) < 2.3:
		_travel_to_floor(GameState.floor + 1)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or hud == null:
		return
	if event.is_action_pressed("stats_menu") and not hud.is_paused():
		hud.toggle_stats()
		var open := hud.any_menu_open()
		player.input_enabled = not open
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


# --- Interaction ---------------------------------------------------------

func _nearest_interactable() -> Array:
	if _fishing and _fishing.active():
		return [null, ""]  # E belongs to the minigame until the line is in
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.in_range(player):
			return [n, "Talk to " + n.npc_name]
	var life := _life_interactable()
	if life[0] != null:
		return life
	for v in get_tree().get_nodes_in_group("ore_veins"):
		if v.visible and player.global_position.distance_to(v.global_position) < 3.0:
			return [v, "Mine Iron Ore"]
	if _monument and _monument.near(player.global_position):
		return [_monument, "Read the Monument of Climbers"]
	if player.global_position.distance_to(TOWER_POS + Vector3(0, 0, 14)) < 5:
		return [self, "Enter the Labyrinth"]
	for pad in _pads:
		if player.global_position.distance_to(pad["pos"]) < 3.0:
			return [pad, pad["label"]]
	if _exit_portal and player.global_position.distance_to(_exit_portal.global_position) < 4:
		return [_exit_portal, "Return to " + ("town" if GameState.floor == 1 else "the waygate")]
	if _gate_open and player.global_position.distance_to(_gate_pos) < 5.0:
		return [_gate, "Enter the gate to Floor %d" % (GameState.floor + 1)]
	return [null, ""]


func _on_interact() -> void:
	if _fishing and _fishing.handle_interact():
		return
	var near := _nearest_interactable()
	if near[0] is Dictionary:
		# Pads, the cottage ("kind") and camp fires ("where") are plain dicts.
		if near[0].has("stall"):
			_stalls.open(int(near[0]["stall"]), hud)
		elif near[0].has("plot"):
			_farms.open(int(near[0]["plot"]), hud)
		elif near[0].has("guild_board"):
			_guilds.open(hud)
		elif near[0].has("tavern"):
			_tavern.open(hud, str(near[0]["tavern"]))
		elif near[0].has("smithy"):
			_smithy.open(hud)
		elif near[0].has("chest"):
			_lab.interact(int(near[0]["chest"]), hud)
		elif near[0].has("beacon"):
			_light_beacon(int(near[0]["beacon"]))
		elif near[0].has("kind"):
			var line: String = _home_interact_online(near[0]) if Net.remote_client() else _home.interact(near[0], player, hud, self)
			if line != "":
				hud.show_dialogue("Cottage", line)
		elif near[0].has("where"):
			_open_cooking(near[0]["where"])
		elif near[0].has("dest"):
			_use_pad(near[0])
		return
	if near[0] == self:
		_try_enter_labyrinth()
	elif _fishing and near[0] == _fishing:
		_fishing.start(_fishing.nearest_spot(player.global_position))
	elif _herbs and near[0] == _herbs:
		_pick_herb(_herbs.nearest(player.global_position))
	elif near[0] == _exit_portal and _exit_portal:
		player.global_position = GameState.spawn_point()
		player.velocity = Vector3.ZERO
	elif near[0] == _gate and _gate:
		_use_floor_gate()
	elif _monument and near[0] == _monument:
		Audio.play("ui_open")
		hud.show_dialogue("Monument of Climbers", _monument.text())
	elif near[0] is Dictionary and near[0].has("dest"):
		_use_pad(near[0])
	elif near[0] is NPC:
		if Net.remote_client():
			# The server runs the quest talk on the record and answers with
			# the line (net_apply "talk"); shops and anvils open locally.
			_talk_local_side_effects(near[0])
			Net.request_action("talk", {"npc": near[0].npc_name})
		else:
			hud.show_dialogue(near[0].npc_name, near[0].talk())
	elif near[0] != null and near[0].is_in_group("ore_veins"):
		_mine(near[0])
	elif near[0] == null and HiddenClasses.cooks_anywhere(GameState.hidden_class) and player.is_on_floor():
		# A Hearthwright's field kitchen: interact with nothing near and the
		# pot comes out (the server accepts the cook without a fire too).
		_open_cooking("Field kitchen")


func _try_enter_labyrinth() -> void:
	if GameState.level < GATE_LEVEL:
		hud.show_dialogue("Sealed Gate", "A voice echoes: \"Only those of level %d may challenge the Floor Guardian.\"" % GATE_LEVEL)
		return
	# A cleared character can still climb the Labyrinth to farm and explore.
	if Net.remote_client():
		Net.request_action("enter_labyrinth")  # the server starts the Guardian quest on the record
	elif GameState.floors_cleared < GameState.floor and not _floor_open:
		GameState.start_quest(_boss_quest_id(), 1)
	player.global_position = LAB_LEVELS[0] + Vector3(0, 1, 9)
	player.velocity = Vector3.ZERO
	hud.toast("The Labyrinth  ·  Terrace 1" + ("  ·  cleared" if GameState.floors_cleared >= GameState.floor else ""))


## Quest id for this floor's Guardian ("floor_boss" on Floor 1 keeps old saves valid).
func _boss_quest_id() -> String:
	return "floor_boss" if GameState.floor == 1 else "floor_boss_%d" % GameState.floor


## The village bounty on this floor's Guardian (Captain Rhys on Floor 1), or "".
func _bounty_quest_id() -> String:
	return "gravelmaw_bounty" if GameState.floor == 1 else ""


func _use_pad(pad: Dictionary) -> void:
	if pad["dest"] is String and pad["dest"] == "summit":
		_enter_summit()
		return
	player.global_position = pad["dest"]
	player.velocity = Vector3.ZERO
	hud.toast(pad.get("toast", pad["label"]))


func _enter_summit() -> void:
	player.global_position = ARENA_POS + Vector3(0, 1, 12)
	player.velocity = Vector3.ZERO
	if GameState.floors_cleared >= GameState.floor or _floor_open:
		hud.toast("Guardian's Summit  ·  cleared")
		return
	if Net.online and not multiplayer.is_server():
		request_boss.rpc_id(1)
	elif _boss == null:
		_spawn_boss()
	hud.toast("Guardian's Summit  ·  Floor Guardian")


var _on_server_lost: Callable


func _exit_tree() -> void:
	if _on_server_lost.is_valid() and Net.server_disconnected.is_connected(_on_server_lost):
		Net.server_disconnected.disconnect(_on_server_lost)
	if Net.action_applied.is_connected(_on_net_action):
		Net.action_applied.disconnect(_on_net_action)


@rpc("any_peer", "call_remote", "reliable")
func request_boss() -> void:
	if not multiplayer.is_server() or _boss != null or _floor_cleared_on_server:
		return
	# Only a player standing on the summit can wake the Guardian.
	var sender := multiplayer.get_remote_sender_id()
	if not _players.has_node(str(sender)):
		return
	# Use the server-accepted position, not the client-synced one.
	var sp: Node = _players.get_node(str(sender))
	var where: Vector3 = sp.srv_position() if sp.has_method("srv_position") else sp.global_position
	if where.distance_to(ARENA_POS) > ARENA_RADIUS + 6.0:
		return
	_spawn_boss()


## Server, every second: spawn the Guardian once an accepted player position
## is on the summit and the floor is not cleared yet.
func _srv_summit_check() -> void:
	if _boss != null or _floor_cleared_on_server or GameState.floor != 1:
		return
	for sp in _players.get_children():
		var where: Vector3 = sp.srv_position() if sp.has_method("srv_position") else sp.global_position
		if where.distance_to(ARENA_POS) <= ARENA_RADIUS + 6.0:
			_spawn_boss()
			return


func _mine(vein: Node3D) -> void:
	vein.visible = false
	get_tree().create_timer(30.0, false).timeout.connect(func():
		if is_instance_valid(vein):
			vein.visible = true)
	if Net.remote_client():
		# The server rolls the ore against its own vein list and cooldown.
		Net.request_action("mine", {"vein": get_tree().get_nodes_in_group("ore_veins").find(vein)})
		return
	var n := randi_range(2, 4)
	GameState.add_material("iron_ore", n)
	hud.toast("+%d Iron Ore" % n)
	_track_ore_quest()


## Keeps the gather quests' trackers in step with what you carry (Elder
## Wren's ore on Floor 1, Keeper Ilsa's wisp essence on Floor 2).
func _track_ore_quest() -> void:
	for pair in Net.RecordState.GATHER_QUESTS:
		if GameState.quests.has(pair[0]) and not GameState.quest_done(pair[0]):
			var q: Dictionary = GameState.quests[pair[0]]
			var have: int = min(GameState.materials.get(pair[1], 0), q["goal"])
			if q["progress"] != have:
				q["progress"] = have
				GameState.quest_changed.emit()


# --- Life layer: fishing, herbs, camp fires, the cottage -----------------

## The life-layer prompt, checked after NPCs and before ore veins.
func _life_interactable() -> Array:
	var p := player.global_position
	if _lab:
		var ch: Dictionary = _lab.nearest(p)
		if not ch.is_empty():
			return [ch, ch["label"]]
	if _stalls:
		var st: Dictionary = _stalls.nearest(p)
		if not st.is_empty():
			return [st, st["label"]]
	if _guilds:
		var gb: Dictionary = _guilds.nearest(p)
		if not gb.is_empty():
			return [gb, gb["label"]]
	if _farms:
		var fp: Dictionary = _farms.nearest(p)
		if not fp.is_empty():
			return [fp, fp["label"]]
	if _smithy:
		var sm: Dictionary = _smithy.nearest(p)
		if not sm.is_empty():
			return [sm, sm["label"]]
	if _tavern:
		var tv: Dictionary = _tavern.nearest(p)
		if not tv.is_empty():
			return [tv, tv["label"]]
	if _home:
		var hit := _home.nearest(p)
		if not hit.is_empty():
			return [hit, hit["label"]]
	if _fishing:
		var sp := _fishing.nearest_spot(p)
		if sp >= 0:
			return [_fishing, "Fish at %s" % LifeData.SPOT_NAMES.get(_fishing.spot_kind(sp), "the water")]
	for cf in _campfires:
		if p.distance_to(cf["pos"]) < cf["range"]:
			return [cf, cf["label"]]
	for b in _beacons:
		if not b["lit"] and p.distance_to(b["pos"]) < BEACON_RANGE:
			return [b, "Touch the waystone"]
	if _herbs:
		if _herbs.nearest(p) >= 0:
			return [_herbs, "Pick Wild Herb"]
	return [null, ""]


# --- Waystones (Floor 1, "Stones of the Old Watch") -----------------------

func _build_beacons() -> void:
	for i in BEACONS.size():
		var p: Vector3 = BEACONS[i]
		var n := Node3D.new()
		n.name = "Waystone%d" % i
		n.position = p
		add_child(n)
		# A leaning standing stone on a flagstone footing, rune face toward the camp.
		var yaw := atan2(TALVEN.x - p.x, TALVEN.z - p.z)
		n.rotation.y = yaw
		WorldArt.cyl(n, 1.1, 1.3, 0.3, Vector3(0, 0.15, 0), WorldArt.STONE_DARK, 10)
		var stone := BoxMesh.new()
		stone.size = Vector3(0.9, 2.6, 0.55)
		WorldArt.mesh_node(n, stone, Vector3(0, 1.55, 0), WorldArt.mat(WorldArt.STONE, 0.03), Vector3(0.06, 0, -0.05))
		var cap := BoxMesh.new()
		cap.size = Vector3(0.7, 0.5, 0.45)
		WorldArt.mesh_node(n, cap, Vector3(0.05, 3.0, -0.02), WorldArt.mat(WorldArt.STONE_DARK, 0.03), Vector3(0.1, 0.2, -0.08))
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.0, 3.2, 0.7)
		cs.shape = shape
		cs.position.y = 1.6
		body.add_child(cs)
		n.add_child(body)
		# The waking rune (crystal, floor ring, light) sits under one node so
		# a touched stone is a single visibility flip.
		var fx := Node3D.new()
		fx.name = "Fx"
		n.add_child(fx)
		var rune_c := Color("b06bff")
		var crystal := SphereMesh.new()
		crystal.radius = 0.16
		crystal.height = 0.5
		crystal.radial_segments = 8
		crystal.rings = 4
		var gem := WorldArt.mesh_node(fx, crystal, Vector3(0, 1.9, 0.33), WorldArt.mat(Color("d9b8ff"), 0.0, rune_c, 3.0))
		gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ring := WorldArt.rune_floor(fx, Vector3(0, 0.31, 0), 1.0, rune_c, 2.4)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not WorldArt.headless():
			var l := OmniLight3D.new()
			l.light_color = rune_c
			l.light_energy = 1.2
			l.omni_range = 7.0
			l.shadow_enabled = false
			l.position = Vector3(0, 1.9, 0.6)
			fx.add_child(l)
		fx.visible = false
		_beacons.append({"pos": p, "beacon": i, "lit": false, "fx": fx})
		_life_keep.append([p, 3.0])
	_refresh_beacons()
	GameState.quest_changed.connect(_refresh_beacons)


## Woken waystones follow GameState.visited (offline, or the server's patch).
func _refresh_beacons() -> void:
	for b in _beacons:
		var lit: bool = GameState.visited.has("waystone_%d" % int(b["beacon"]))
		if lit != bool(b["lit"]):
			b["lit"] = lit
			b["fx"].visible = lit


func _light_beacon(i: int) -> void:
	if i < 0 or i >= _beacons.size() or _beacons[i]["lit"]:
		return
	Audio.play("teleport", player.global_position)
	if Net.remote_client():
		Net.request_action("waystone", {"i": i})
		return
	GameState.visit("waystone_%d" % i)
	_refresh_beacons()
	var lit := GameState.visited_count(GameState.visited, "waystone_")
	if hud:
		hud.toast("Waystone woken", "%d of %d stones lit around Talven" % [lit, BEACONS.size()], "Old Watch", UITheme.GOLD)


## Herbs work like veins: the clump hides locally at once; offline the herb
## lands in GameState here, online the server rolls it (srv_action "herb").
func _pick_herb(i: int) -> void:
	if _herbs == null or not _herbs.is_up(i):
		return
	var n := _herbs.pick(i)
	Audio.play("pickup", player.global_position)
	var fx := VFX.get_for(self)
	if fx:
		fx.puff(_herbs.positions[i] + Vector3(0, 0.4, 0), 0.6, Color(0.6, 0.9, 0.5, 0.6))
	if Net.remote_client():
		Net.request_action("herb", {"i": i})
		return
	GameState.add_material("wild_herb", n)
	hud.toast("+%d Wild Herb" % n, "", "", UITheme.GREEN)


func _open_cooking(where := "Camp fire") -> void:
	if hud == null or hud.life == null:
		return
	if not hud.life.cooking_open():
		hud.life.toggle_cooking(where)
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _open_shop() -> void:
	if hud == null or hud.life == null:
		return
	hud.life.open_shop()
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Quest talks take `gs`: GameState offline (and for the listen-server
## host), the talker's server record (Net.RecordState) when the server runs
## a client's "talk" request. _set_talk registers both forms for an NPC.
var _talk_handlers := {}  # npc name -> Callable(gs) -> String


func _set_talk(npc: NPC, handler: Callable) -> void:
	_talk_handlers[npc.npc_name] = handler
	npc.talk_override = func(): return handler.call(GameState)


## The plain quest NPC flow (NPC.talk) against `gs`.
func _default_talk(npc: NPC, gs) -> String:
	if npc.quest_id == "":
		return npc.lines["offer"]
	if not gs.quests.has(npc.quest_id):
		gs.start_quest(npc.quest_id, npc.quest_goal)
		return npc.lines["offer"]
	if gs.quest_ready(npc.quest_id):
		gs.complete_quest(npc.quest_id)
		gs.add_xp(npc.quest_xp)
		gs.add_money(npc.quest_money)
		return "%s\n(+%d XP, +%d Col)" % [npc.lines["turn_in"], npc.quest_xp, npc.quest_money]
	if gs.quests[npc.quest_id]["done"]:
		return npc.lines["done"]
	return npc.lines["in_progress"]


## Online client: what a talk does on this machine besides the line the
## server will send (open the anvil or the stall).
func _talk_local_side_effects(npc: NPC) -> void:
	if npc.npc_name in SMITHS:
		_open_craft("%s's anvil" % npc.npc_name.trim_prefix("Smith "))
	elif npc.npc_name == "Trader Pell":
		_open_shop()


## Fisher NPCs: a catch quest, and a spare rod for anyone without one.
func _fisher_talk(id: String, goal: int, xp: int, money: int, lines: Dictionary, gs = GameState) -> String:
	if gs.quest_done(id):
		return lines["done"]
	if not gs.quests.has(id):
		gs.start_quest(id, goal)
		var extra := ""
		if not LifeData.has_rod(gs):
			gs.add_material("willow_rod", 1)
			extra = "\n(Received: Willow Rod)"
		return lines["offer"] + extra
	if gs.quest_ready(id):
		gs.complete_quest(id)
		gs.add_xp(xp)
		gs.add_money(money)
		return "%s\n(+%d XP, +%d Col)" % [lines["turn_in"], xp, money]
	return lines["in_progress"]


func _new_fishing() -> void:
	_fishing = Fishing.new()
	_fishing.name = "Fishing"
	add_child(_fishing)
	_fishing.setup(self, player, hud)


## Floor 1 life layer: the pond and stream stakes with Old Tam, the Talven
## camp fire, Trader Pell's stall in the plaza, the cottage and the herb clumps.
func _build_life_floor1() -> void:
	_new_fishing()
	var pond := Vector3(WorldArt.POND.x, 0, WorldArt.POND.y)
	var pond_spot := pond + Vector3(-9.8, 0, -4.5)
	_fishing.add_spot(pond_spot, "pond", pond + Vector3(-4.5, 0, -2.0))
	var stream_spot := pond + Vector3(17.8, 0, -0.4)
	_fishing.add_spot(stream_spot, "stream", pond + Vector3(17.8, 0, -3.2))
	_life_keep.append([pond_spot, 3.0])
	_life_keep.append([stream_spot, 3.0])
	var tam := NPC.new()
	tam.npc_name = "Old Tam"
	tam.appearance = {"hair_color": "e8e4de", "outfit_color": "3a6b8a", "hair_style": 1, "eye_color": "5b3a29", "height": 0.93}
	tam.position = pond + Vector3(-11.8, 0, -7.0)
	tam.rotation.y = -PI * 0.35
	_set_talk(tam, func(gs): return _fisher_talk("pond_catch", 5, 150, 80, {
		"offer": "The pond's thick with fish and my back's done for. Catch 5 of anything that bites and I'll pay. Press E at the stake to cast; when the marker swims through the green, E again.",
		"in_progress": "Patience, that's the whole art. The stream east of the pond runs trout; koi show up when the moon's out.",
		"turn_in": "Ha! A natural. Here's your due. Grill the trout with a wild herb and you'll feel it in your arms.",
		"done": "Mire eels on Floor 2, they say. Fisher Maud at the Mere would pay for those."}, gs))
	add_child(tam)
	_campfires.append({"pos": TALVEN, "range": 2.6, "label": "Cook at the camp fire", "where": "Talven camp fire"})
	# Trader Pell at the west plaza stall: rod and cottage decorations.
	var pell := NPC.new()
	pell.npc_name = "Trader Pell"
	pell.appearance = {"hair_color": "7a4a21", "outfit_color": "9b59b6", "hair_style": 4, "eye_color": "a0522d", "height": 1.02}
	pell.position = Vector3(-12.6, 0, 10.9)
	pell.rotation.y = PI * 0.9
	_set_talk(pell, func(gs):
		if gs == GameState:
			_open_shop()
		if gs.home_owned:
			return "The cottage owner! Rugs, shelves, a fern for the window: make it yours."
		return "Willow rods for the pond, and fine furnishings for whoever buys the Hollowbrook cottage. Honest prices.")
	add_child(pell)
	_home = PlayerHome.build(self)
	_life_keep.append([PlayerHome.HOME_POS, 9.0])
	# The door and the exit mat are pads too, so the server knows the jump.
	_pads.append({"pos": _home.door_pos, "label": "Enter the cottage", "dest": _home.spawn_inside, "toast": "Your cottage"})
	_pads.append({"pos": _home.exit_pos, "label": "Leave the cottage", "dest": _home.door_out + Vector3(0, 1, 0), "toast": "Hollowbrook"})
	# Wild herbs: clumps on the open grass, clear of every place.
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var spots := []
	var guard := 0
	var mill := Vector3(WorldArt.WINDMILL.x, 0, WorldArt.WINDMILL.y)
	while spots.size() < 40 and guard < 1200:
		guard += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(42, FLOOR_RADIUS - 14)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var on_road := WorldArt.ground_kind(Vector2(p.x, p.z)) != WorldArt.Ground.GRASS
		var in_stream := p.x > pond.x + 2.0 and absf(p.z - (pond.z - 3.5)) < 6.0
		var ok := not on_road and not in_stream and p.distance_to(Vector3(0, 0, 15)) > 40 and p.distance_to(pond) > 13 \
			and p.distance_to(HOLLOWBROOK) > 18 and p.distance_to(TALVEN) > 14 and p.distance_to(TOWER_POS) > 24 \
			and p.distance_to(mill) > 9 and p.distance_to(PlayerHome.HOME_POS) > 9
		p.y = WorldArt.height_at(Vector2(p.x, p.z))
		for sp in spots:
			if p.distance_to(sp) < 10.0:
				ok = false
		if ok:
			spots.append(p)
	_herbs = HerbField.build(self, spots)
	for sp in spots:
		_life_keep.append([sp, 2.0])


## Hollowbrook market: six rentable player stalls (scripts/life/stalls.gd).
func _build_market_floor1() -> void:
	_stalls = preload("res://scripts/life/stalls.gd").build(self, HOLLOWBROOK)
	_farms = preload("res://scripts/life/farms.gd").build(self, HOLLOWBROOK)
	_guilds = preload("res://scripts/life/guilds.gd").build(self, HOLLOWBROOK)


func _build_life_floor2(village: Dictionary) -> void:
	_new_fishing()
	var lake: Vector3 = Floor2Art.LAKE
	var shore := lake + Vector3(0, 0, -(Floor2Art.LAKE_RADIUS + 2.4))
	_fishing.add_spot(shore, "mere", lake + Vector3(0, 0, -(Floor2Art.LAKE_RADIUS - 3.5)))
	var ends := Floor2Art.boardwalk_ends()
	var dir: Vector3 = (ends[1] - ends[0]).normalized()
	var side := dir.cross(Vector3.UP)
	var mid: Vector3 = ends[0].lerp(ends[1], 0.45)
	_fishing.add_spot(mid + side * 0.6, "boardwalk", mid + side * 4.2)
	_life_keep.append([shore, 3.0])
	var maud := NPC.new()
	maud.npc_name = "Fisher Maud"
	maud.appearance = {"hair_color": "c4262e", "outfit_color": "2f4858", "hair_style": 3, "eye_color": "3cb371", "height": 0.98}
	maud.position = shore + Vector3(-3.4, 0, -0.8)
	maud.rotation.y = PI * 0.5
	_set_talk(maud, func(gs): return _fisher_talk("mere_catch", 3, 600, 300, {
		"offer": "The Mere eels fetch a price in Thornwick, pie or smoked. Bring me 3 Mire Eels. They fight; keep your eye on the green.",
		"in_progress": "Eels bite deep water. Try the end of the boardwalk if the shore is quiet; the koi like it there too.",
		"turn_in": "Three fat eels. Thornwick eats pie tonight. Here, you earned it.",
		"done": "Eel pie puts a spring in your step. Ask at the fire pit."}, gs))
	add_child(maud)
	_campfires.append({"pos": village.get("fire", Floor2Art.VILLAGE), "range": 2.8, "label": "Cook at the fire pit", "where": "Thornwick fire pit"})
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var spots := []
	var guard := 0
	while spots.size() < 16 and guard < 500:
		guard += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(30, 78)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var ok := Floor2Art.ground_kind(Vector2(p.x, p.z)) == WorldArt.Ground.GRASS and p.distance_to(lake) > Floor2Art.LAKE_RADIUS + 6 \
			and p.distance_to(Floor2Art.BARROW) > Floor2Art.BARROW_RADIUS + 4 and p.distance_to(Floor2Art.VILLAGE) > 18 \
			and p.distance_to(Vector3(Floor2Art.PLAZA.x, 0, Floor2Art.PLAZA.y)) > 14 and p.distance_to(TOWER_POS) > 24
		for sp in spots:
			if p.distance_to(sp) < 6.0:
				ok = false
		if ok:
			spots.append(p)
	_herbs = HerbField.build(self, spots, Color("8fb36a"))
	for sp in spots:
		_life_keep.append([sp, 2.0])



# --- Server-side life actions ---------------------------------------------
## Net._srv_action hands every world-dependent request here with the
## requester's RecordState and the position the server last accepted for it.
## Range checks use the world's own object positions (veins, herbs, fishing
## stakes, camp fires, NPCs, the cottage) plus Net.RANGE_SLACK; sufficiency
## (materials, Col, levels, recipes, rod, quest state) is checked by the same
## Crafting / LifeData / quest-talk code offline uses, run on the record.
## Returns {"error": why} or the result the client shows.
func srv_action(peer: int, rs, kind: String, payload: Dictionary, pos: Vector3) -> Dictionary:
	match kind:
		"duel":
			if _duels == null:
				return {"error": "There are no duels on this floor."}
			return _duels.srv(peer, rs, payload, pos)
		"mine":
			var i := int(payload.get("vein", -1))
			if i < 0 or i >= _vein_positions.size():
				return {"error": "No such vein."}
			if not _srv_near(pos, _vein_positions[i], 3.0):
				return {"error": "Too far from the vein."}
			if not Net.srv_cooldown(peer, "vein:%d" % i, 30000):
				return {"error": "That vein is spent for now."}
			var n := randi_range(2, 4)
			rs.add_material("iron_ore", n)
			return {"n": n, "vein": i}
		"herb":
			var i := int(payload.get("i", -1))
			if _herbs == null or i < 0 or i >= _herbs.positions.size():
				return {"error": "No such herb."}
			if not _srv_near(pos, _herbs.positions[i], HerbField.PICK_RANGE):
				return {"error": "Too far from the herb."}
			if not Net.srv_cooldown(peer, "herb:%d" % i, int(HerbField.REGROW * 1000.0)):
				return {"error": "That clump is picked bare."}
			var n := 1 if randf() < 0.65 else 2
			rs.add_material("wild_herb", n)
			return {"n": n, "i": i}
		"cast":
			var i := int(payload.get("spot", -1))
			if _fishing == null or i < 0 or i >= _fishing.spots.size():
				return {"error": "No such fishing spot."}
			if not _srv_near(pos, _fishing.spots[i]["pos"], Fishing.CAST_RANGE):
				return {"error": "Too far from the water."}
			if not LifeData.has_rod(rs):
				return {"error": "You need a rod."}
			var fish: String = LifeData.roll_fish(_fishing.spot_kind(i), int(rs.fishing_level))
			rs.rec["_fish"] = {"fish": fish, "spot": i, "ms": Time.get_ticks_msec()}
			return {"fish": fish, "spot": i}
		"land":
			var pending = rs.rec.get("_fish")
			var i := int(payload.get("spot", -1))
			if not (pending is Dictionary) or int(pending.get("spot", -2)) != i:
				return {"error": "Nothing on the line (no cast)."}
			var waited := Time.get_ticks_msec() - int(pending["ms"])
			if waited < 2400 or waited > 90000:
				rs.rec.erase("_fish")
				return {"error": "The line was not in the water long enough."}
			if _fishing == null or i < 0 or i >= _fishing.spots.size() or not _srv_near(pos, _fishing.spots[i]["pos"], Fishing.CAST_RANGE):
				rs.rec.erase("_fish")
				return {"error": "You walked off and lost the line."}
			rs.rec.erase("_fish")
			return LifeData.land_fish(str(pending["fish"]), rs)
		"cook":
			if not _srv_near_fire(pos, rs):
				return {"error": "You need a fire to cook."}
			return LifeData.cook(str(payload.get("id", "")), rs)
		"craft":
			if _srv_npc_near(pos, SMITHS) == null:
				return {"error": "You need an anvil (talk to a smith)."}
			return Crafting.craft(str(payload.get("recipe", "")), rs)
		"forge_start":
			if _srv_npc_near(pos, SMITHS) == null:
				return {"error": "You need an anvil (talk to a smith)."}
			var fr := str(payload.get("recipe", ""))
			if not Forging.uses_minigame(fr):
				return {"error": "Nothing to hammer: forge that one directly."}
			var ferr := Crafting.check(fr, rs)
			return {"error": ferr} if ferr != "" else Forging.srv_open(rs, fr)
		"forge_strike":
			var st := Forging.srv_strike(rs, int(payload.get("i", -1)), int(payload.get("at", -1)), Net.srv_rtt(peer))
			if not st.get("done", false):
				return st
			# The last strike lands the piece: re-check at the anvil, then
			# forge at the quality the server graded.
			if _srv_npc_near(pos, SMITHS) == null:
				return {"error": "You walked away from the anvil; the piece is spoiled."}
			var made := Crafting.craft(str(st["recipe"]), rs, float(st["quality"]))
			if not made.has("error"):
				made["forge_q"] = float(st["quality"])
				made["grades"] = st["grades"]
			return made
		"repair":
			if _srv_npc_near(pos, SMITHS) == null:
				return {"error": "You need an anvil (talk to a smith)."}
			var slot := str(payload.get("slot", ""))
			var rerr := Durability.repair(rs, slot)
			if rerr == "":
				rs._sync_weapon()
			return {"slot": slot} if rerr == "" else {"error": rerr}
		"buy":
			if _srv_npc_near(pos, ["Trader Pell"]) == null:
				return {"error": "Trader Pell is not here."}
			var id := str(payload.get("id", ""))
			var err: String = LifeData.buy(id, rs)
			return {"id": id} if err == "" else {"error": err}
		"buy_home":
			if _home == null or not _srv_near(pos, _home.door_pos, 2.6):
				return {"error": "You are not at the cottage door."}
			if rs.home_owned:
				return {"error": "You already own the cottage."}
			if not rs.buy_home(LifeData.HOME_PRICE):
				return {"error": "Not enough Col (%d needed)." % LifeData.HOME_PRICE}
			return {}
		"store":
			if _home == null or not rs.home_owned or not _srv_near(pos, PlayerHome.INTERIOR + PlayerHome.CHEST, 1.8):
				return {"error": "You are not at your storage chest."}
			var to_storage := bool(payload.get("to_storage", true))
			if to_storage and rs.home_storage.size() >= StorageScreen.ROWS:
				return {"error": "The chest is full."}
			if not rs.store_item(str(payload.get("id", "")), to_storage):
				return {"error": "No such item."}
			return {"to_storage": to_storage}
		"place":
			var slot := int(payload.get("slot", -1))
			var id := str(payload.get("id", ""))
			if _home == null or not rs.home_owned or slot < 0 or slot >= PlayerHome.SLOTS.size() or not _srv_near(pos, PlayerHome.INTERIOR + PlayerHome.SLOTS[slot], 1.4):
				return {"error": "You are not at that furniture slot."}
			if id != "" and not LifeData.DECOR.has(id):
				return {"error": "No such decoration."}
			if not rs.place_furniture(slot, id):
				return {"error": "You own no spare %s." % LifeData.DECOR[id]["name"]}
			return {"slot": slot, "id": id}
		"rest":
			if _home == null or not rs.home_owned or not _srv_near(pos, PlayerHome.INTERIOR + PlayerHome.BED, 1.9):
				return {"error": "You are not at your bed."}
			LifeData.rest(rs)
			return {}
		"talk":
			var name := str(payload.get("npc", ""))
			var npc := _srv_npc_near(pos, [name])
			if npc == null:
				return {"error": "%s is not within reach." % name}
			var line: String
			if _talk_handlers.has(name):
				line = str(_talk_handlers[name].call(rs))
			else:
				line = _default_talk(npc, rs)
			return {"npc": name, "line": line}
		"waystone":
			var i := int(payload.get("i", -1))
			if i < 0 or i >= _beacons.size():
				return {"error": "No such waystone."}
			if not _srv_near(pos, _beacons[i]["pos"], BEACON_RANGE):
				return {"error": "Too far from the waystone."}
			if not rs.visit("waystone_%d" % i):
				return {"error": "That stone is already awake."}
			return {"i": i, "lit": GameState.visited_count(rs.visited, "waystone_")}
		"smithy":
			if _smithy == null:
				return {"error": "There is no village forge on this floor."}
			return _smithy.srv(peer, rs, payload, pos)
		"tavern":
			if _tavern == null:
				return {"error": "There is no tavern on this floor."}
			return _tavern.srv(peer, rs, payload, pos)
		"stall", "stall_signs":
			if _stalls == null:
				return {"error": "There is no market on this floor."}
			return _stalls.srv(peer, rs, kind, payload, pos)
		"farm", "farm_signs":
			if _farms == null:
				return {"error": "There are no farm plots on this floor."}
			return _farms.srv(peer, rs, kind, payload, pos)
		"chest":
			if _lab == null:
				return {"error": "There are no chests on this floor."}
			return _lab.srv(peer, rs, payload, pos)
		"guild":
			if _guilds == null:
				return {"error": "There is no guild office on this floor."}
			return _guilds.srv(peer, rs, kind, payload, pos)
		"enter_labyrinth":
			if not _srv_near(pos, TOWER_POS + Vector3(0, 0, 14), 5.0):
				return {"error": "You are not at the Labyrinth gate."}
			if int(rs.level) < GATE_LEVEL:
				return {"error": "Only those of level %d may challenge the Floor Guardian." % GATE_LEVEL}
			if int(rs.floors_cleared) < GameState.floor and not _floor_cleared_on_server:
				rs.start_quest(_boss_quest_id(), 1)
			return {}
	return {"error": "Unknown action '%s'." % kind}


func _srv_near(pos: Vector3, target: Vector3, range_: float) -> bool:
	return pos.distance_to(target) <= range_ + Net.RANGE_SLACK


func _srv_near_fire(pos: Vector3, rs) -> bool:
	if HiddenClasses.cooks_anywhere(str(rs.hidden_class)):
		return true  # a Hearthwright carries the fire
	for cf in _campfires:
		if _srv_near(pos, cf["pos"], float(cf["range"])):
			return true
	return _home != null and rs.home_owned and _srv_near(pos, PlayerHome.INTERIOR + PlayerHome.HEARTH + Vector3(0, 0, 0.6), 2.1)


func _srv_npc_near(pos: Vector3, names: Array) -> NPC:
	for n in get_tree().get_nodes_in_group("npcs"):
		if n is NPC and names.has(n.npc_name) and _srv_near(pos, n.global_position, NPC.TALK_RANGE):
			return n
	return null


# --- Online client: cottage interactions and server answers -----------------

## Online, the cottage's own interact() runs only for the moves that change
## nothing on the record (walking through the door, the chest UI, cooking
## UI); purchase, resting and furniture go to the server.
func _home_interact_online(hit: Dictionary) -> String:
	match hit.get("kind", ""):
		"door":
			if GameState.home_owned:
				return _home.interact(hit, player, hud, self)
			if _home._confirm_t > 0.0:
				_home._confirm_t = 0.0
				Net.request_action("buy_home")
				return ""
			_home._confirm_t = 6.0
			Audio.play("ui_tick")
			return "A snug cottage, hearth and all, for %d Col. Elder Wren says the roof is sound.\nPress E again to buy it." % LifeData.HOME_PRICE
		"bed":
			Net.request_action("rest")
			return ""
		"slot":
			var i := int(hit.get("index", 0))
			var cur: String = GameState.home_furniture[i]
			var options := [""]
			for id in LifeData.DECOR:
				if id == cur or GameState.decor_free(id) > 0:
					options.append(id)
			if options.size() == 1:
				Audio.play("ui_error")
				return "You own no decorations to place. Trader Pell in the town plaza sells rugs, shelves, plants and lanterns."
			Net.request_action("place", {"slot": i, "id": options[(options.find(cur) + 1) % options.size()]})
			return ""
	return _home.interact(hit, player, hud, self)


## Online client: the server answered an action (Net.action_applied). The
## patch is already in GameState; this is the feedback the local code path
## would have given (toasts, sounds, the dialogue line, the fishing widget).
func _on_net_action(kind: String, res: Dictionary) -> void:
	if hud == null:
		return
	if kind in ["stall", "stall_signs"]:
		if _stalls:
			_stalls.on_net(kind, res)
		return
	if kind == "tavern":
		if _tavern:
			_tavern.on_net(kind, res)
		return
	if kind == "smithy":
		if _smithy:
			_smithy.on_net(kind, res)
		return
	if kind in ["farm", "farm_signs"]:
		if _farms:
			_farms.on_net(kind, res)
		return
	if kind == "chest":
		if _lab:
			_lab.show_result(res, hud)
		return
	if kind in ["guild", "guild_invite"]:
		if _guilds:
			_guilds.hud = hud
			_guilds.on_net(kind, res)
		return
	if kind == "duel":
		if _duels:
			_duels.hud = hud
			_duels.on_net(kind, res)
		return
	if kind in ["cast", "land"]:
		if _fishing:
			_fishing.on_net(kind, res)
		return
	if kind == "forge_start" or kind == "forge_strike":
		if res.has("error"):
			hud.forge_failed(str(res["error"]))
		elif kind == "forge_start":
			hud.forge_begin(res)
		elif res.has("name"):
			hud.forge_result(res)
			if _bot_mode:
				print("[bot] forged %s at quality %.2f %s" % [res["name"], float(res.get("forge_q", -1)), str(res.get("grades", []))])
		if res.has("error") and _bot_mode:
			print("[bot] forge refused: %s" % res["error"])
		return
	if res.has("error"):
		Audio.play("craft_fail")
		hud.toast(str(res["error"]), "", "", UITheme.ROSE)
		return
	match kind:
		"craft":
			if res.has("name"):
				hud._forge_sfx(int(res.get("rank", 0)))
				var sub := "Smithing Lv %d" % GameState.smithing_level if res.get("skill_up", false) else ""
				hud.toast(str(res["name"]), sub, "Forged" if int(res.get("rank", 0)) < 3 else "Masterwork forged!", Crafting.rank_color(int(res.get("rank", 0))))
		"cook":
			Audio.play("cook")
			if hud.life:
				hud.life._on_cooked(res)
		"crystal":
			crystal_effect(str(res.get("id", "")))
		"loot":
			if _results:
				var got: Dictionary = res.get("drops", {}) if res.get("drops") is Dictionary else {}
				for id in got:
					_results.note_item(str(id), int(got[id]))
		"gear":
			gear_notice(str(res.get("slot", "")), str(res.get("state", "")))
		"repair":
			repaired(str(res.get("slot", "")))
		"buy":
			Audio.play("coins")
			var id := str(res.get("id", ""))
			var nm: String = LifeData.TOOLS[id]["name"] if LifeData.TOOLS.has(id) else (LifeData.CRYSTALS[id]["name"] if LifeData.CRYSTALS.has(id) else LifeData.DECOR.get(id, {}).get("name", id))
			hud.toast(nm, "Bought from Trader Pell", "Purchase", UITheme.GOLD)
		"buy_home":
			Audio.play("coins")
			Audio.play("quest_complete")
			hud.toast("Cottage purchased!", "Hollowbrook has a new neighbour. Step inside.", "Home", UITheme.GOLD)
		"rest":
			Audio.play("sleep")
			hud.toast("You rest a while", "Well Rested: %s" % LifeData.buff_text(LifeData.REST_BUFF), "Home", UITheme.CYAN)
		"store":
			Audio.play("drop" if res.get("to_storage", true) else "pickup")
		"place":
			var id := str(res.get("id", ""))
			Audio.play("drop" if id != "" else "pickup")
			if id == "":
				hud.toast("Slot %d cleared" % (int(res.get("slot", 0)) + 1), "", "Decorate", UITheme.MUTED)
			else:
				hud.toast(LifeData.DECOR[id]["name"], "Slot %d  ·  E again to cycle" % (int(res.get("slot", 0)) + 1), "Decorate", UITheme.GOLD)
		"mine":
			hud.toast("+%d Iron Ore" % int(res.get("n", 0)))
		"herb":
			hud.toast("+%d Wild Herb" % int(res.get("n", 0)), "", "", UITheme.GREEN)
		"waystone":
			_refresh_beacons()
			hud.toast("Waystone woken", "%d of %d stones lit around Talven" % [int(res.get("lit", 0)), BEACONS.size()], "Old Watch", UITheme.GOLD)
		"talk":
			hud.show_dialogue(str(res.get("npc", "")), str(res.get("line", "")))
		"floor_cleared":
			hud.toast("FLOOR %d CLEARED!" % GameState.floor)
		"last_attack":
			_show_last_attack(res)
		"unique_skill":
			pass  # GameState.unique_skill_changed already toasts
		"respawn":
			if player:
				player.die(int(res.get("xp_lost", 0)))
		"fallen":
			if player and res.get("fallen") is Dictionary:
				player.fall(res["fallen"])
		"hp":
			if player and float(res.get("hp", 0.0)) < float(res.get("prev", 0.0)):
				var lost: float = float(res["prev"]) - float(res["hp"])
				Audio.play("player_hit", null, 0.1)
				player.shake(clampf(0.15 + lost / 60.0, 0.15, 0.4))
				var fx := VFX.get_for(self)
				if fx:
					fx.hit(player.global_position + Vector3(0, 1.1, 0), -player.model.global_transform.basis.z, Color(1.0, 0.35, 0.3))


## Equipped gear crossed a durability line ("low" / "broken"): offline via
## GameState.gear_state, online via the server's "gear" event.
func gear_notice(slot: String, state: String) -> void:
	var it = GameState.equipped.get(slot)
	if hud == null or not (it is Dictionary):
		return
	if state == "broken":
		Audio.play("craft_fail")
		hud.toast("%s broke!" % str(it.get("name", "Gear")), "It adds nothing until a smith repairs it", "Durability", UITheme.ROSE)
	else:
		Audio.play("ui_error")
		hud.toast("%s is wearing out" % str(it.get("name", "Gear")), "%s  ·  repair at an anvil" % Durability.text(it), "Durability", UITheme.GOLD)


## A repair went through (offline right away, online on the server's answer).
func repaired(slot: String) -> void:
	var it = GameState.equipped.get(slot)
	Audio.play("anvil")
	Audio.play("craft_pot")
	if hud and it is Dictionary:
		hud.toast("%s repaired" % str(it.get("name", "Gear")), Durability.text(it), "Anvil", UITheme.CYAN)
		if hud.has_method("refresh_craft"):
			hud.refresh_craft()


## A crystal was crushed (offline right away, online once the server agreed):
## the flash, the sound, the toast, and for a Teleport Crystal the move to
## the floor's arrival point. VFX hook: crystal_burst(pos, color, teleport).
func crystal_effect(id: String) -> void:
	if not LifeData.CRYSTALS.has(id) or player == null:
		return
	var c := LifeData.item_color(id)
	var fx := VFX.get_for(self)
	var tele := id == "teleport_crystal"
	if fx:
		if fx.has_method("crystal_burst"):
			fx.call("crystal_burst", player.global_position + Vector3(0, 1.0, 0), c, tele)
		else:
			fx.flash(player.global_position + Vector3(0, 1.0, 0), c, 1.4)
			fx.sparkle(player.global_position + Vector3(0, 1.0, 0), c)
	Audio.play("respawn" if tele else "quest_complete")
	if tele:
		player.global_position = GameState.spawn_point()
		player.velocity = Vector3.ZERO
		if fx:
			fx.sparkle(player.global_position + Vector3(0, 1.0, 0), c)
		if hud:
			hud.toast("Teleport: Hollowbrook", "The crystal shatters and the plaza forms around you", "Crystal", c)
	elif hud:
		hud.toast("HP fully restored", "Healing Crystal", "Crystal", c)


# --- Test bots: honest chores and cheat probes -------------------------------
## --bot (no --cheat): before hunting, the bot walks a short errand that
## exercises every server-side action once: mine two veins, forge an Iron
## Sword at Haldor's anvil, pick a herb, take Old Tam's rod, cast and land
## a fish, then report the ore to Elder Wren. --cheat: 1.5 s after spawning
## it fires forged requests at the server (craft without materials, a
## 99,999 Col snapshot, a koi landed without a cast, the cottage with no
## Col, quest turn-ins and mining from across the island), each of which the
## server must refuse with a "[life] refused" / "[anticheat]" line.
const CHORES := ["vein", "herb", "vein", "tam", "fish", "smith", "elder", "elder"]
const CHORE_BUDGET := 70.0  # seconds per chore before the bot gives up on it (the floor is ~540 m across)
## The bot leaves and re-enters town by the north road (spawn -> gate is a
## straight run); its errands are picked near that gate.
const CHORE_GATE := Vector3(0, 0, -21)
const CHORE_GATE_IN := Vector3(0, 0, -13)
const CHORE_GATE_OUT := Vector3(0, 0, -29)
var _chore_mined := {}
var _chore_i := -1
var _chore_t := 0.0
var _chore_wait := 0.0
var _chore_started := 0.0
var _chore_last := Vector3.ZERO
var _chore_best_d := INF
var _chore_stuck := 0
var _chore_strafe := Vector3.ZERO
var _chore_strafe_t := 0.0
var _chore_target: Node3D
var _probes_sent := false


func _physics_process(delta: float) -> void:
	if not _bot_mode or player == null or not Net.remote_client():
		return
	_chore_t += delta
	if _bot_forge_tick():
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		return
	if _duel_mode and _duels != null and _duels.bot_tick(self, player, delta):
		return
	if _summit_mode:
		if _chore_t >= _summit_next:
			_summit_next = _chore_t + 10.0
			var far := player.global_position.distance_to(ARENA_POS) > ARENA_RADIUS + 4.0
			if far and not player.is_dying():
				player.bot = true
				print("[bot] heading to the summit")
				_enter_summit()
		return
	if _cheat_mode:
		if not _probes_sent and _chore_t > 1.5:
			_probes_sent = true
			_send_cheat_probes()
		return
	if _chore_i == -1:
		if _chore_t < 4.0:
			return
		_chore_i = 0
		player.bot = false
		print("[bot] starting chores")
	if _chore_i >= CHORES.size():
		return
	_chore_wait -= delta
	if _chore_wait > 0.0:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		return
	if _chore_t - _chore_started > CHORE_BUDGET:
		_chore_next("out of time")
		return
	var goal: Variant = _chore_goal(CHORES[_chore_i])
	if goal == null:
		_chore_next("no target")
		return
	var reach: float = 2.0 if CHORES[_chore_i] in ["vein", "herb", "fish"] else 1.8
	var flat: Vector3 = (goal - player.global_position) * Vector3(1, 0, 1)
	if flat.length() <= reach:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		_chore_act(CHORES[_chore_i])
		return
	_chore_walk(goal, delta)


var _bot_forging := false


## Bot: strike the anvil bar whenever the spark sits dead centre; close the
## panel once the piece is forged (or refused).
func _bot_forge_tick() -> bool:
	if not _bot_forging or hud == null:
		return false
	var fw: ForgeWidget = hud._forge
	if fw != null and fw._active:
		var spec: Dictionary = fw.specs[fw.grades.size()]
		if Forging.grade(spec, float(fw._elapsed() - fw._last)) == "perfect":
			fw.strike()
	elif fw == null:
		if hud._craft_panel.visible:
			hud.toggle_craft()
		_bot_forging = false
	return _bot_forging


func _chore_next(note := "") -> void:
	print("[bot] chore '%s' done%s (t=%.0f s, col=%d, ore=%d, herbs=%d, fish=%d)" % [CHORES[_chore_i], (": " + note) if note != "" else "", _chore_t,
		GameState.money, GameState.materials.get("iron_ore", 0), GameState.materials.get("wild_herb", 0), GameState.fish_caught])
	_chore_i += 1
	_chore_wait = 1.0
	_chore_started = _chore_t + 1.0
	_chore_stuck = 0
	_chore_best_d = INF
	_chore_target = null
	if _chore_i >= CHORES.size():
		print("[bot] chores finished, hunting")
		player.bot = true


func _chore_goal(kind: String) -> Variant:
	match kind:
		"vein":
			if _chore_target == null:
				var best := INF
				for v in get_tree().get_nodes_in_group("ore_veins"):
					var d: float = v.global_position.distance_to(CHORE_GATE_OUT)
					if v.visible and d < best and not _chore_mined.has(v.get_instance_id()):
						best = d
						_chore_target = v
			return _chore_target.global_position if _chore_target else null
		"herb":
			if _herbs == null:
				return null
			var best := INF
			var pick := -1
			for i in _herbs.positions.size():
				var d: float = _herbs.positions[i].distance_to(player.global_position)
				if _herbs.is_up(i) and d < best:
					best = d
					pick = i
			return _herbs.positions[pick] if pick >= 0 else null
		"fish":
			return _fishing.spots[0]["pos"] if _fishing and not _fishing.spots.is_empty() else null
		"smith", "tam", "elder":
			var want: String = {"smith": "Smith Haldor", "tam": "Old Tam", "elder": "Elder Wren"}[kind]
			for n in get_tree().get_nodes_in_group("npcs"):
				if n.npc_name == want:
					return n.global_position
	return null


func _chore_act(kind: String) -> void:
	match kind:
		"vein":
			_chore_mined[_chore_target.get_instance_id()] = true
			_mine(_chore_target)
			_chore_next()
		"herb":
			_pick_herb(_herbs.nearest(player.global_position, 3.0))
			_chore_next()
		"smith":
			# Through the real anvil minigame: open the panel, hammer each
			# strike dead centre (_bot_forge_tick), let the server grade it.
			Net.request_action("talk", {"npc": "Smith Haldor"})
			if not hud._craft_panel.visible:
				hud.toggle_craft()
			var ferr := Crafting.check("Iron Sword", GameState)
			hud._start_forge("Iron Sword")
			_bot_forging = ferr == "" and hud._craft_panel.visible
			_chore_next("forging at the anvil" if ferr == "" else ferr)
		"tam":
			Net.request_action("talk", {"npc": "Old Tam"})
			_chore_next()
		"elder":
			Net.request_action("talk", {"npc": "Elder Wren"})
			_chore_wait = 2.0
			_chore_next()
		"fish":
			if _fishing.active():
				if _fishing.state == Fishing.State.BITE:
					var w = hud.life.fishing if hud and hud.life else null
					if w and w.in_zone():
						_fishing.handle_interact()
				if _chore_t > 110.0:
					_fishing.cancel()
					_chore_next("gave up")
				return
			if _fishing.catches > 0 or _fishing.casts >= 3:
				_chore_next("%d catch(es) in %d casts" % [_fishing.catches, _fishing.casts])
				return
			if not LifeData.has_rod():
				if _chore_t > 100.0:
					_chore_next("no rod")
				return
			_fishing.start(0)


## Walks the bot toward `goal`, leaving or entering town by the north gate
## (inner and outer waypoints line it up with the road), hopping and
## sidestepping when stuck.
func _chore_walk(goal: Vector3, delta: float) -> void:
	var c: Vector3 = Player.BOT_WALL_CENTER
	var me_in := Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length() < Player.BOT_WALL_RADIUS - 1.0
	var goal_in := Vector2(goal.x - c.x, goal.z - c.z).length() < Player.BOT_WALL_RADIUS - 1.0
	if me_in != goal_in:
		var near_pt := CHORE_GATE_IN if me_in else CHORE_GATE_OUT
		var far_pt := CHORE_GATE_OUT if me_in else CHORE_GATE_IN
		var flat_me := player.global_position * Vector3(1, 0, 1)
		goal = near_pt if (flat_me.distance_to(near_pt) > 1.5 and flat_me.distance_to(CHORE_GATE) > 7.0) else far_pt
	var to := (goal - player.global_position) * Vector3(1, 0, 1)
	if fmod(_chore_t, 1.0) < delta:
		if player.global_position.distance_to(_chore_last) < 0.8:
			_chore_stuck += 1
			if player.is_on_floor():
				player.velocity.y = Player.JUMP_VELOCITY
			_chore_strafe = to.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
			_chore_strafe_t = 1.2
			if _chore_stuck >= 8:
				_chore_next("stuck")
				return
		else:
			_chore_stuck = 0
		_chore_best_d = minf(_chore_best_d, to.length())
		_chore_last = player.global_position
	var dir := to.normalized()
	if _chore_strafe_t > 0.0:
		_chore_strafe_t -= delta
		dir = _chore_strafe
	# Sprint pace (a legitimate player's Shift), plus the controller's idle drag.
	var speed: float = GameState.move_speed() * 1.7 + 0.8
	player.velocity.x = dir.x * speed
	player.velocity.z = dir.z * speed
	if player.model:
		player.model.rotation.y = atan2(-dir.x, -dir.z)


func _send_cheat_probes() -> void:
	print("[bot] cheat: sending forged requests")
	var blades := []
	for i in 50:
		blades.append({"id": "hack_%d" % i, "name": "Myth Spirit Blade", "kind": "weapon", "rank": 5, "atk": 55})
	Net.net_client_snapshot.rpc_id(1, {"money": 99999, "level": 99, "materials": {"moonscale_koi": 50, "iron_ore": 9999}, "inventory": blades})
	for probe in [["craft", {"recipe": "Spirit Blade"}], ["land", {"spot": 0}], ["buy_home", {}], ["talk", {"npc": "Elder Wren"}],
			["talk", {"npc": "Guide Mira"}], ["mine", {"vein": 0}], ["eat", {"id": "koi_sashimi"}], ["spend_point", {"stat": "strength"}],
			["equip", {"id": "hack_1"}], ["buy", {"id": "trophy"}], ["cook", {"id": "koi_sashimi"}], ["herb", {"i": 0}]]:
		Net.net_request_action.rpc_id(1, probe[0], probe[1])

# --- Hollowbrook quest chain ------------------------------------------------
## Five Floor 1 quests, each NPC pointing to the next: Vesna's wolf pelts
## (gather, from the Dire Wolves by the tower), Hesper's herbs (the field
## clumps), Rook's stew (cooking), Fen's three waystones around Talven
## (visit) and Captain Rhys's bounty on the Kobold Warlord (kill), which pays a Rare
## Spirit Blade and the "Warden of Talven" title. Every handler takes `gs`
## so the server runs it on the record (srv_action "talk").

const CHAIN_ORDER := ["wolf_pelts", "field_herbs", "tavern_stew", "talven_waystones"]


func _spawn_hollowbrook_chain() -> void:
	var c := HOLLOWBROOK
	var vesna := NPC.new()
	vesna.npc_name = "Trapper Vesna"
	vesna.appearance = {"hair_color": "2a1e14", "outfit_color": "5a4a32", "hair_style": 1, "eye_color": "7a9a4a", "height": 1.02}
	vesna.position = c + Vector3(-8.0, 0, -2.5)
	vesna.rotation.y = PI * 0.5
	vesna.quest_id = "wolf_pelts"  # marker only; the talk below runs the quest
	_set_talk(vesna, _vesna_talk)
	add_child(vesna)
	var hesper := NPC.new()
	hesper.npc_name = "Herbalist Hesper"
	hesper.appearance = {"hair_color": "b5651d", "outfit_color": "4f6a3a", "hair_style": 3, "eye_color": "4a8a6a", "height": 0.96}
	hesper.position = c + Vector3(-11.5, 0, 8.0)
	hesper.rotation.y = PI * 0.75
	hesper.quest_id = "field_herbs"
	_set_talk(hesper, _hesper_talk)
	add_child(hesper)
	var rook := NPC.new()
	rook.npc_name = "Innkeeper Rook"
	rook.appearance = {"hair_color": "4a3a2a", "outfit_color": "6a3a2a", "hair_style": 0, "eye_color": "5a4a3a", "height": 1.08}
	rook.position = c + Vector3(-2.2, 0, -6.4)
	rook.rotation.y = PI * 0.15
	if _tavern:
		rook.position = _tavern.interior + Tavern.ROOK_SPOT  # behind his bar
		rook.rotation.y = PI
		rook.set_meta("map_pos", _tavern.door_pos)
	if _smithy:
		var kesra := NPC.new()
		kesra.npc_name = "Smith Kesra"
		kesra.appearance = {"hair_color": "c4262e", "outfit_color": "4a3a32", "hair_style": 3, "eye_color": "d9a441", "height": 1.0}
		kesra.position = _smithy.interior + Smithy.KESRA_SPOT
		kesra.rotation.y = PI * 0.8
		kesra.set_meta("map_pos", _smithy.door_pos)
		_set_talk(kesra, _kesra_talk)
		add_child(kesra)
	rook.quest_id = "tavern_stew"
	_set_talk(rook, _rook_talk)
	add_child(rook)
	var fen := NPC.new()
	fen.npc_name = "Scout Fen"
	fen.appearance = {"hair_color": "8a7a5a", "outfit_color": "3a4a3a", "hair_style": 2, "eye_color": "d9a441"}
	fen.position = TALVEN + Vector3(4.2, 0, 0.0)
	fen.rotation.y = PI * 0.5
	fen.quest_id = "talven_waystones"
	_set_talk(fen, _fen_talk)
	add_child(fen)
	_spawn_limited_npcs()


# --- Limited quests (LimitedContent: 1-3 holders in the whole realm) --------

func _spawn_limited_npcs() -> void:
	var bram := NPC.new()
	bram.npc_name = "Old Watchman Bram"
	bram.appearance = {"hair_color": "d8d4cc", "outfit_color": "3a3f4a", "hair_style": 0, "eye_color": "6a7a8a", "height": 1.0}
	bram.position = TALVEN + Vector3(-3.6, 0, 3.2)
	bram.rotation.y = PI * 0.8
	bram.quest_id = "old_watch_whispers"
	_set_talk(bram, _bram_talk)
	add_child(bram)
	# A lamplighter nobody in town remembers, at the far edge of the first
	# Labyrinth terrace.
	var iselde := NPC.new()
	iselde.npc_name = "Lamplighter Iselde"
	iselde.appearance = {"hair_color": "f1d9a0", "outfit_color": "e8e4de", "hair_style": 3, "eye_color": "f0c060", "height": 0.94}
	iselde.position = LAB_LEVELS[0] + Vector3(-7.0, 0, 5.0)
	iselde.rotation.y = PI * 0.25
	iselde.quest_id = "lantern_below"
	_set_talk(iselde, _iselde_talk)
	add_child(iselde)


## Shared flow: accept reserves a realm slot (refused when full), the slot
## frees itself if the quest sits unfinished too long, the turn-in confirms
## it and pays the limited item.
func _limited_talk(gs, qid: String, req: String, lines: Dictionary) -> String:
	var q: Dictionary = LimitedContent.QUESTS[qid]
	var mat: String = q["mat"]
	var need := int(q["need"])
	if gs.quest_done(qid):
		return lines["done"]
	if req != "" and not gs.quest_done(req):
		return lines["locked"]
	if not gs.quests.has(qid):
		var res := LimitedContent.reserve_quest(gs, qid)
		if not res.get("ok", false):
			return lines["full"]
		gs.start_quest(qid, need)
		var left := LimitedContent.slots_left(qid)
		return "%s\n(Limited quest: %d of %d places left in the realm. Finish within two hours of play or the place passes on.)" % [lines["offer"], left, int(q["cap"])]
	if not LimitedContent.holds_quest(gs, qid):
		gs.quests.erase(qid)
		if gs == GameState:
			GameState.quest_changed.emit()
		return lines["expired"]
	var have := int(gs.materials.get(mat, 0))
	gs.quests[qid]["progress"] = mini(have, need)
	if gs == GameState:
		GameState.quest_changed.emit()
	if have < need:
		return lines["in_progress"] % [have, need]
	var conf := LimitedContent.confirm_quest(gs, qid)
	if not conf.get("ok", false):
		gs.quests.erase(qid)
		return lines["expired"]
	gs.spend_materials({mat: need})
	gs.complete_quest(qid)
	gs.add_xp(int(q["xp"]))
	gs.add_money(int(q["col"]))
	var item_id: String = q["reward"]
	var got := LimitedContent.grant_item(gs, item_id)
	var reward: String = LimitedContent.ITEMS[item_id]["name"] if got.get("ok", false) else "no item (the realm refused it)"
	return "%s\n(+%d XP, +%d Col, %s)" % [lines["turn_in"], int(q["xp"]), int(q["col"]), reward]


func _bram_talk(gs = GameState) -> String:
	return _limited_talk(gs, "old_watch_whispers", "talven_waystones", {
		"locked": "The stones are dark and so am I. Wake the old line with Fen first, then we will talk about what the watch left behind.",
		"offer": "You lit the line. Then you have earned the rest of the story: the last watch-captains forged three blades at those stones, and the wolves dragged the scabbards off. Bring me 5 wolf pelts from the north slope and I will kindle one more blade. Only three were ever made.",
		"in_progress": "%d of %d pelts. The pack runs the scrub below the tower. Do not dawdle: the fire in these stones does not wait forever.",
		"turn_in": "Five. The stones remember you. Take it: a Wisplight blade, one of three. It will not leave your hand for anyone else's.",
		"done": "Carry it well. Three blades, three wardens. The watch is not dead while one of you walks.",
		"full": "Three blades were promised and three wardens carry them now. I am sorry. The stones have nothing left to give.",
		"expired": "You took too long, and the stones gave your place to another. That is the way of the old watch. Come back if a place opens again.",
	})


func _iselde_talk(gs = GameState) -> String:
	return _limited_talk(gs, "lantern_below", "", {
		"locked": "",
		"offer": "Oh. You can see me. Nobody climbs this far and looks at the corners. My lantern went out when the Guardian woke, and only the shards of this tower can relight it. Bring me 6 Spirit Shards. I only have the one veil to give, and I will give it once.",
		"in_progress": "%d of %d shards. The terraces' guardians carry them. Please hurry: if you wander off too long, the lantern will choose someone else.",
		"turn_in": "Light. Real light. Here: the Veil of First Dawn. There is only one, and now it is yours. When you climb higher, take a little of this floor's morning with you.",
		"done": "The lantern burns. Thank you, Lamplighter's friend.",
		"full": "Someone already carries my lantern's promise. I am sorry, traveller. There was only ever one veil.",
		"expired": "The lantern waited, and you did not come. Someone else carries the promise now, or will soon.",
	})


## Last Attack bonus, as in Aincrad: whoever lands the killing blow gets
## something nobody else in the fight does. `la` = {"item": LimitedContent id
## (a realm-capped, bound piece) or "", "xp", "col", "mats": {id: n},
## "realm": announce to the whole realm}. The first holders get the limited
## item; once its slots are gone (or the killer already holds one) the bonus
## is the EXP / Col / materials instead, so a Last Attack always pays. The
## killer's party hears about it. Defaults to the Floor Guardian's bonus.
const BOSS_LA := {"item": "la_floor1", "xp": 150, "col": 200, "mats": {"spirit_shard": 2}, "realm": true}
const SERGEANT_LA := {"item": "la_sergeant", "xp": 60, "col": 40, "mats": {"terrace_key": 1}}
const GREYTUSK_LA := {"item": "la_greytusk", "xp": 50, "col": 35, "mats": {"beast_hide": 3}}


func _grant_last_attack(killer: int, la: Dictionary = {}, foe := "") -> Dictionary:
	if la.is_empty():
		if GameState.floor != 1:
			return {}
		la = BOSS_LA
	if foe == "":
		foe = "the Floor Guardian"
	var local := not Net.online or (killer == multiplayer.get_unique_id() and not Net.srv_records.has(killer))
	var gs
	if local:
		gs = GameState
	elif Net.srv_records.has(killer):
		gs = Net.RecordState.new(Net.srv_records[killer])
	else:
		return {}
	var who := str(GameState.character.get("name", "Someone")) if local else str(Net.srv_records[killer].get("name", "Someone"))
	var data := {"foe": foe, "item": "", "xp": 0, "col": 0, "mats": {}}
	var lid := str(la.get("item", ""))
	if lid != "" and LimitedContent.ITEMS.has(lid):
		var res := LimitedContent.grant_item(gs, lid)
		if res.get("ok", false) and not res.get("already", false):
			data["item"] = str(LimitedContent.ITEMS[lid]["name"])
	if data["item"] == "":
		var mult := 1.0 + (Permadeath.LA_BONUS if Permadeath.is_on(gs) else 0.0)
		data["xp"] = int(round(int(la.get("xp", 0)) * mult))
		data["col"] = int(round(int(la.get("col", 0)) * mult))
		gs.add_xp(data["xp"])
		data["xp"] = Permadeath.xp_gain(gs, data["xp"])  # what add_xp really paid
		gs.add_money(data["col"])
		var mats: Dictionary = la.get("mats", {})
		for m in mats:
			if GameState.MATERIAL_NAMES.has(m):
				gs.add_material(m, int(mats[m]))
				data["mats"][m] = int(mats[m])
	var text := "%s took the Last Attack on %s%s." % [who, foe, (" and won the %s" % data["item"]) if data["item"] != "" else ""]
	if bool(la.get("realm", false)):
		Net.srv_announce(text)
	if Net.online and multiplayer.is_server():
		for m in Net._srv_party_members(killer):
			if m != killer:
				Net._send(m, Net.net_system, [text])
	if local:
		_show_last_attack(data)
	else:
		Net.save_record(Net.srv_records[killer])
		Net._srv_reply(killer, "last_attack", data)
	return data


## The "LAST ATTACK BONUS" pop-up (hud.show_last_attack when the HUD has it).
func _show_last_attack(data: Dictionary) -> void:
	if hud == null:
		return
	if hud.has_method("show_last_attack"):
		hud.show_last_attack(data)  # the banner plays its own sounds
		return
	Audio.stinger("last_attack", 2.0)
	var what := str(data.get("item", ""))
	if what == "":
		var parts: Array = ["+%d EXP" % int(data.get("xp", 0)), "+%d Col" % int(data.get("col", 0))]
		var mats: Dictionary = data.get("mats", {})
		for m in mats:
			parts.append("%s x%d" % [GameState.MATERIAL_NAMES.get(m, m), int(mats[m])])
		what = "  ·  ".join(parts)
	hud.toast("LAST ATTACK BONUS", what, str(data.get("foe", "")), UITheme.GOLD)


## Shared flow for the chain's gather quests: progress mirrors the material
## carried (RecordState.GATHER_QUESTS / _track_ore_quest), the turn-in takes
## it. `req` is the quest that must be done first ("" for none).
func _gather_talk(gs, id: String, mat: String, need: int, xp: int, money: int, req: String, lines: Dictionary, bonus: Callable) -> String:
	if req != "" and not gs.quest_done(req):
		return lines["locked"]
	if gs.quest_done(id):
		return lines["done"]
	var fresh := false
	if not gs.quests.has(id):
		gs.start_quest(id, need)
		fresh = true
	var have: int = int(gs.materials.get(mat, 0))
	gs.quests[id]["progress"] = min(have, need)
	if gs == GameState:
		GameState.quest_changed.emit()
	if have >= need:
		gs.spend_materials({mat: need})
		gs.complete_quest(id)
		gs.add_xp(xp)
		gs.add_money(money)
		var extra: String = bonus.call(gs)
		return "%s\n(+%d XP, +%d Col%s)" % [lines["turn_in"], xp, money, extra]
	if fresh:
		return lines["offer"]
	return lines["in_progress"] % [have, need]


func _vesna_talk(gs = GameState) -> String:
	return _gather_talk(gs, "wolf_pelts", "wolf_pelt", 4, 260, 160, "", {
		"offer": "The dire wolves have come down off the tower slope and nobody sets a snare north of the gate any more. Bring me 4 wolf pelts. Proof the pack is thinning, and boots for the village before the frost.",
		"in_progress": "%d of %d pelts. The pack runs the scrub below the Labyrinth tower, north past the town gate. They hunt in threes; put a wall at your back.",
		"turn_in": "Four pelts, clean cuts. These will be boots by the first frost. Hesper by the vegetable patch patches up what the wolves bite; she has been asking for someone who can walk the open grass.",
		"done": "The north slope is quieter. Hesper by the vegetable patch has work for you, if you have not seen her.",
		"locked": "",
	}, func(g):
		g.add_material("beast_hide", 2)
		return ", +2 Beast Hide")


func _hesper_talk(gs = GameState) -> String:
	if gs.quest_done("field_herbs") and (gs.quests.has("grove_bloom") or gs.quest_done("tavern_stew")):
		return _bloom_talk(gs)
	return _gather_talk(gs, "field_herbs", "wild_herb", 6, 220, 140, "wolf_pelts", {
		"locked": "Vesna's wolves first, if you would. I patch up what they bite, and my shelves are bare. Come back when the snares are safe to set.",
		"offer": "Feverleaf and fog-root, the pale clumps on the open grass between here and the town. I need 6 before the next field hand limps in. Pick them clean and they grow back within the hour.",
		"in_progress": "%d of %d herbs. They grow in the clearings between the trees, never on the road and never by the water.",
		"turn_in": "Fresh, and still damp. That is a week of poultices. Take these; a grilled trout keeps a body on its feet. And tell Rook at the tavern I sent you: his cook walked out and the field hands are getting ugly about it.",
		"done": "My shelves are full again. Rook at the tavern could use a hand in his kitchen.",
	}, func(g):
		g.add_material("grilled_trout", 2)
		return ", +2 Grilled Trout")


## Hesper's second errand (after Rook's stew): a bloom from the one Snaptrap
## in flower in the north-east grove. Pays the Verdant Edge, a blade forged
## by Haldor and tempered in the bloom's sap: a strong first-floor sword.
func _bloom_talk(gs = GameState) -> String:
	return _gather_talk(gs, "grove_bloom", "snaptrap_bloom", 1, 320, 120, "field_herbs", {
		"locked": "",
		"offer": "Past the pond, in the woods north-east of town, the snaptraps have taken root: pitcher-mouthed vines that spit. One of them is in flower. Its bloom's sap, pressed and boiled, tempers steel like nothing else on this floor. Bring me the bloom and Haldor will forge you a blade with it. Do not strike the ones with a swollen fruit; the burst draws every vine in the grove.",
		"in_progress": "%d of %d blooms. The flowering one is pink-crowned and wary; if someone beat you to it, it blooms again in a few minutes. Mind the fruit-bearers.",
		"turn_in": "Still fragrant. Haldor has had the steel ready for a week; he'll fold the sap in tonight. Here. It is light, and it will not dull on kobold plate.",
		"done": "Keep the Verdant Edge oiled. The sap remembers being alive.",
	}, func(g):
		var blade := Crafting.make_item("Iron Sword", 2, "Smith Haldor")
		blade["name"] = "Verdant Edge"
		blade["atk"] = int(ceil(Crafting.RECIPES["Iron Sword"]["base"] * Crafting.RANK_MULT[2] * 1.1))
		g.add_item(blade)
		return ", Verdant Edge (Epic sword)")


func _rook_talk(gs = GameState) -> String:
	var hearth := _hearth_talk(gs)
	if hearth != "":
		return hearth
	return _gather_talk(gs, "tavern_stew", "boar_stew", 1, 300, 180, "field_herbs", {
		"locked": "Hesper sends me every stray with a strong back. Help her first; I will still be short a cook when you are done.",
		"offer": "My cook walked out and the field hands want boar stew. Trimmings from one boar hide, two of Hesper's herbs, and a fire: the Talven camp fire will do, or your own hearth. Bring me one pot that would not shame this house and the job is yours, in spirit at least.",
		"in_progress": "%d of %d pots. Boars roam the south fields past the houses; the hide is the trimmings. Two herbs, one hide, over a fire. The camp at Talven keeps one burning.",
		"turn_in": "Thick, hot, and the room has gone quiet. That is the sound of a full tavern. Here: a plate of moonscale koi, sliced thin, for when you need every blessing at once. Scout Fen is out at the Talven camp; the scout has a job nobody else wants.",
		"done": "The stew holds. Fen at the Talven camp has been asking after a pair of steady legs.",
	}, func(g):
		g.add_material("koi_sashimi", 1)
		return ", +1 Koi Sashimi")


## Innkeeper Rook's hidden rite (HiddenClasses): once his stew is served and
## the fishers and field hands have talked about your fires (twelve dishes
## over four recipes, five fish, three harvests), he asks for a trail supper.
## Returns "" when the plain stew talk should run instead.
func _hearth_talk(gs) -> String:
	var qid := HiddenClasses.HEARTH_QUEST
	if str(gs.hidden_class) == HiddenClasses.HEARTHWRIGHT:
		return "Hearthwright! Pull up a stool; no, the other way round, you feed me for once. The road is lucky to have you."
	if not gs.quest_done("tavern_stew") or gs.quest_done(qid):
		return ""
	if gs.quests.has(qid):
		var have := HiddenClasses.supper_count(gs)
		gs.quests[qid]["progress"] = mini(have, 3)
		if gs == GameState:
			GameState.quest_changed.emit()
		if HiddenClasses.has_supper(gs):
			gs.spend_materials(HiddenClasses.HEARTH_SUPPER)
			gs.complete_quest(qid)
			gs.unlock_hidden_class(HiddenClasses.HEARTHWRIGHT)
			return "Trout off the coals, soup still steaming, bread that has not had time to cool. That is a supper for a road. The cooks who walked the Spire with a pot on their back were called Hearthwrights, and you are one now: your food will hold longer and do more, you will not need a fire to cook on, and when the coals fly, keep them. Hearth Flare, they called that."
		return "%d of 3 dishes. Grilled Trout from the pond, Turnip Soup from the plots, Harvest Bread from the sunwheat. Cooked by you, mind, at any fire you like." % have
	if str(gs.hidden_class) != "":
		return ""  # one hidden class per character
	if HiddenClasses.hearth_ready(gs):
		gs.start_quest(qid, 3)
		return "Tam says you fish like you mean it, the plots west of here know your boots, and the field hands come in smelling of your cooking instead of mine. There was a name for cooks like that once. Bring me a trail supper, Grilled Trout, Turnip Soup and Harvest Bread, all three at once, and I will tell you what it was."
	return ""


func _fen_talk(gs = GameState) -> String:
	var need := 3
	if not gs.quest_done("tavern_stew"):
		return "Rook feeds the watch, and the watch is me. Sort his kitchen out and I will have a job for you that keeps the whole valley sleeping."
	if gs.quest_done("talven_waystones"):
		return "Three stones awake around Talven. The old watch line holds again. Captain Rhys has been waiting on you; the Captain does not wait for many."
	if not gs.quests.has("talven_waystones"):
		gs.start_quest("talven_waystones", need)
		gs.sync_visit_quests()
		return "The old watch set waystones around these fields, long before the town. They went dark when the Guardian woke. Three of them: west of the camp, south toward the tower, and one by the road outside the north gate. Lay a hand on each and the line wakes."
	gs.sync_visit_quests()
	if gs.quest_ready("talven_waystones"):
		gs.complete_quest("talven_waystones")
		gs.add_xp(340)
		gs.add_money(200)
		gs.add_material("spirit_shard", 2)
		return "I saw the third one catch from the camp. The whole line lit. Talven will not forget who did that. Now go to Captain Rhys: the town has a bounty, and it is yours to take.\n(+340 XP, +200 Col, +2 Spirit Shards)"
	var have: int = GameState.visited_count(gs.visited, "waystone_")
	return "%d of %d stones awake. West of the camp, south toward the tower, and by the road outside the north gate. Press E at the stone." % [have, need]


## Captain Rhys: the wolf hunt through the plain flow, then the bounty once
## Hollowbrook and the Talven camp have vouched for you.
func _rhys_talk(npc: NPC, gs) -> String:
	if not gs.quest_done("wolf_hunt"):
		return _default_talk(npc, gs)
	if gs.quest_done("gravelmaw_bounty"):
		return "Warden of Talven. The town keeps that name for the ones who kept it. Drinks are on Rook, tonight and always."
	if not gs.quests.has("gravelmaw_bounty"):
		for q in CHAIN_ORDER:
			if not gs.quest_done(q):
				return "Vesna, Hesper and Rook in Hollowbrook, and Fen at the Talven camp: all of them have work for a blade with your reach. Do right by them, then come back. There is a bounty I only post for one of our own."
		gs.start_quest("gravelmaw_bounty", 1)
		if int(gs.floors_cleared) >= 1:
			gs.advance_quest("gravelmaw_bounty")  # the Guardian already fell to you
			return "You have already done it? Then I owe you the bounty before the words are out. Say so again and it is yours."
		return "Then hear it: the town has posted a bounty on the Floor Guardian. Vargash, the kobold warlord, at the summit of the Labyrinth, past the gate that only opens at level %d. Bring it down and come back to me. The town names its own." % GATE_LEVEL
	if gs.quest_ready("gravelmaw_bounty"):
		gs.title = "Warden of Talven"
		gs.complete_quest("gravelmaw_bounty")
		gs.add_xp(600)
		gs.add_money(400)
		gs.add_item(Crafting.make_item("Spirit Blade", 1, "Captain Rhys"))
		return "The Guardian is down and the fields are ours again. Haldor forged this for whoever did it; it is yours. And the name: Warden of Talven. Wear it where the next floor can see it.\n(+600 XP, +400 Col, Rare Spirit Blade, title: Warden of Talven)"
	return "Vargash waits at the summit of the Labyrinth with his halberdiers. When he crouches, he is about to leap: move. We will be here when it is done."


# --- Blacksmith ----------------------------------------------------------

func _smith_talk(gs = GameState) -> String:
	if not gs.quest_done("forge_trial") and gs.items_crafted >= 2 and not gs.quests.has("forge_trial"):
		gs.start_quest("forge_trial", 5)
		return "You have the hands for it. Legends say the first Spire smith forged a class into existence. Craft 5 pieces and we'll see what wakes in you."
	if gs.quest_ready("forge_trial"):
		gs.complete_quest("forge_trial")
		gs.unlock_hidden_class("Forgeborn")
		return "The anvil sings for you. You are Forgeborn now: stronger, tougher, and your work will reach higher ranks."
	if gs == GameState:
		_open_craft()
	if gs.hidden_class == "Forgeborn":
		return "Welcome back, Forgeborn. The anvil is yours."
	return "Bring ore and hides, pay the forge fee, and I'll let you work the anvil."


func _open_craft(anvil := "Haldor's anvil") -> void:
	hud.anvil_name = anvil
	if not hud.toggle_craft():
		hud.toggle_craft()
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- World building ------------------------------------------------------

## Floor 1, "Town of First Light": the original island, unchanged.
func _build_floor1() -> void:
	# Each LoadingScreen.step yields one frame when a loading screen is up
	# (so the bar moves and the window keeps painting); headless and in the
	# tests it returns at once and the build stays synchronous.
	await LoadingScreen.step("Lighting the sky", 0.05)
	_build_environment()
	_build_ground()
	await LoadingScreen.step("Raising the Town of First Light", 0.2)
	_build_town()
	_build_field()
	await LoadingScreen.step("Carving the Labyrinth", 0.4)
	_build_tower()
	_build_arena()
	_build_labyrinth()
	_lab = preload("res://scripts/labyrinth_features.gd").build(self, LAB_LEVELS)
	await LoadingScreen.step("Settling Hollowbrook and Talven", 0.55)
	_build_hollowbrook()
	_build_talven()
	_spawn_ore_veins()
	_spawn_npcs()
	_build_life_floor1()
	_build_market_floor1()
	_build_beacons()
	_routines = preload("res://scripts/npc_routines.gd").build(self)
	_monument = preload("res://scripts/monument.gd").build(self)
	_results = preload("res://scripts/battle_results.gd").build(self)
	_results.hud = hud
	NpcBark.attach(self, _routines)
	# Cosmetic villagers on the plaza: never on a server or headless run.
	if not Net.dedicated and DisplayServer.get_name() != "headless":
		preload("res://scripts/town_crowd.gd").build(self)
	await LoadingScreen.step("Planting the meadow", 0.7)
	_dress_world()
	await LoadingScreen.step("Waking the wilds", 0.92)
	if Net.is_authority():
		_spawn_mobs()


func _mat(c: Color, rough := 0.9) -> Material:
	# Cel-shaded material shared by every prop (cached per colour).
	return WorldArt.mat(c, 0.025)


func _static_box(size: Vector3, pos: Vector3, color: Color, rot_y := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(color)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


var day_night: DayNight


func _build_environment() -> void:
	# Sky, sun, fog and post-processing live in WorldArt so the Forward+ and
	# Compatibility paths stay in one place.
	WorldArt.build_environment(self)
	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup(self)
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--hour" and i + 1 < args.size():
			day_night.time_of_day = float(args[i + 1])


func _build_ground() -> void:
	# Walkable floor: flat at y = 0 in every town, camp and road, rolling hills
	# between them (WorldArt.height_at); a heightmap collider matches the mesh.
	# The looks (painterly ground shader, cliff rocks, rocky underside) are art.
	WorldArt.terrain_on = true
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.add_child(WorldArt.height_shape())
	add_child(body)
	WorldArt.build_terrain(self, _art_rng, FLOOR_RADIUS)
	WorldArt.build_sky(self, _art_rng, FLOOR_RADIUS)


func _build_town() -> void:
	# Cobbled plaza (drawn by the ground shader) with a curb, the teleport
	# gate, a fountain, lantern posts, market stalls and a ring of houses
	# inside a crenellated wall.
	var curb := TorusMesh.new()
	curb.inner_radius = 21.6
	curb.outer_radius = 22.4
	curb.rings = 64
	WorldArt.mesh_node(self, curb, Vector3(0, 0.0, 15), WorldArt.mat(WorldArt.STONE_DARK, 0.0), Vector3.ZERO, Vector3(1, 0.35, 1))

	# Teleport gate: two carved pillars (WorldProps keeps their collision
	# boxes), a glowing ring and a rune circle.
	WorldProps.portal_pillars(self, Vector3(0, 0, 15), 3.0, 6.5)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.4
	tm.outer_radius = 2.8
	tm.rings = 48
	tm.material = WorldArt.rune_mat(Color("4fc3ff"), 2.4)
	ring.mesh = tm
	ring.rotation.x = PI / 2
	ring.position = Vector3(0, 4, 15)
	add_child(ring)
	var tw := ring.create_tween().set_loops()
	tw.tween_property(ring, "rotation:z", TAU, 14.0).from(0.0)
	WorldArt.rune_ring(self, Vector3(0, 0.07, 15), 4.2, Color("4fc3ff"), 0.22)
	WorldProps.fountain(self, Vector3(0, 0, 27))
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8
		WorldProps.lantern(self, Vector3(cos(a) * 17, 0, 15 + sin(a) * 17), -a)
	WorldProps.stall(self, Vector3(-12, 0, 8), 0.7, 0)
	WorldProps.stall(self, Vector3(15, 0, 6), -0.9, 1)
	WorldProps.stall(self, Vector3(-14, 0, 24), 1.9, 2)
	WorldProps.crate(self, Vector3(-10.5, 0, 5.5), 0.9, 0.3)
	WorldProps.crate(self, Vector3(-9.6, 0, 6.6), 0.7, 0.9)
	WorldProps.barrel(self, Vector3(17, 0, 8.5))
	WorldProps.barrel(self, Vector3(18, 0, 7.6), 0.8)
	WorldProps.prop(self, "town", "cart", Vector3(-16.5, 0, 20.5), 2.6, WorldProps.TOWN, "box")
	WorldProps.prop(self, "town", "cart-high", Vector3(19.5, 0, 2.0), -1.7, WorldProps.TOWN, "box")

	# Ring of KayKit buildings facing the plaza; i=8 is the smithy next to
	# Smith Haldor, i=1 / i=7 are nudged off the west and east roads.
	var kinds := ["home_A", "home_B", "tavern", "home_A", "home_B", "church", "home_A", "market", "blacksmith", "home_B"]
	var colors := ["blue", "red", "green", "yellow", "blue", "red", "green", "yellow", "red", "blue"]
	var hedge_lines := []
	for i in 10:
		var a := PI * 0.15 + (PI * 1.7) * i / 9.0 + PI / 2
		if i == 1:
			a -= 0.12
		elif i == 7:
			a += 0.12
		var pos := Vector3(cos(a) * 28, 0, sin(a) * 28 + 15)
		var face := atan2(-pos.x, -(pos.z - 15))
		var scl := WorldProps.HOUSE * (0.92 if kinds[i] == "tavern" else 1.0)
		if i == 4 or i == 5:
			# The Hall of Iron stands here instead (below).
			_rng.randf()
			_rng.randf()
			continue
		WorldProps.house(self, pos, kinds[i], colors[i], face, scl)
		_rng.randf()  # Keeps the gameplay RNG stream where the old houses left it.
		_rng.randf()
		if i % 3 == 0:
			WorldProps.lantern(self, pos + Vector3(cos(a + 0.3), 0, sin(a + 0.3)) * -5.5, face)
		elif i % 3 == 1 and kinds[i].begins_with("home"):
			# Low hedge along the front of a cottage, split by its door.
			var fp := WorldProps.footprint(kinds[i], colors[i], scl)
			var fwd := Vector3(sin(face), 0, cos(face))
			var side := Vector3(cos(face), 0, -sin(face))
			var front := pos + fwd * (fp.y * 0.5 + 1.4)
			hedge_lines.append([front - side * fp.x * 0.5, front - side * 1.3])
			hedge_lines.append([front + side * 1.3, front + side * fp.x * 0.5])
	WorldProps.hedges(self, hedge_lines)
	# Hall of Iron across the north road (after the Black Iron Palace on
	# the north side of the Town of Beginnings' plaza), with the Monument of
	# Climbers in front of its east wing, facing the plaza.
	WorldProps.iron_hall(self, Vector3(0, 0, -12.5))
	MonumentArt.make(self, Vector3(7.5, 0, -7.2), 0.0)
	# Town wall with gates north (to the tower), south, and west (Hollowbrook).
	var hb_dir := Vector2(HOLLOWBROOK.x, HOLLOWBROOK.z) - WorldArt.PLAZA
	WorldArt.town_wall(self, Vector3(0, 0, 15), 36.0, [
		[-PI / 2, 0.22], [PI / 2, 0.16], [atan2(hb_dir.y, hb_dir.x), 0.14], [atan2(-2.0, 22.0), 0.12]])


## Vegetation and ambience go last so they can keep clear of everything
## gameplay placed (NPCs, ore veins, the gate, villages, the spawn point).
func _dress_world() -> void:
	var keep := [[Vector3(0, 0, 6), 4.0], [TOWER_POS + Vector3(0, 0, 14), 8.0], [HOLLOWBROOK, 17.0], [TALVEN, 13.0],
		[Vector3(WorldArt.WINDMILL.x, 0, WorldArt.WINDMILL.y), 7.0], [Vector3(0, 0, -12.5), 11.0], [Vector3(0, 0, 27), 5.0], [Vector3(17.5, 0, 20), 4.0]]
	for n in get_tree().get_nodes_in_group("npcs"):
		keep.append([n.position, 3.0])
	for v in _vein_positions:
		keep.append([v, 3.0])
	for lvl in LAB_LEVELS:
		keep.append([lvl, LAB_RADIUS + 2])
	keep.append_array(_life_keep)
	# Snaptrap Grove: each vine stands in its own small clearing in the woods.
	for sp in GROVE_SPOTS:
		keep.append([GROVE + sp, 2.8])
	WorldArt.build_vegetation(self, _art_rng, FLOOR_RADIUS, keep)
	WorldProps.grove_dress(self, GROVE, GROVE_SPOTS)
	WorldArt.build_ambience(self)
	WorldProps.flush(self)


func _build_field() -> void:
	# Fields: pond and stream, a windmill, fences along the roads.
	WorldArt.build_water(self, FLOOR_RADIUS)
	var mill := Vector3(WorldArt.WINDMILL.x, 0, WorldArt.WINDMILL.y)
	if WorldProps.ready():
		WorldProps.house(self, mill, "windmill", "green", 1.2, WorldProps.HOUSE * 1.3)
	else:
		WorldArt.windmill(self, mill, 1.2)
	# Fences follow the roads out of the north and south gates, round the
	# windmill's paddock and the Hollowbrook pasture.
	var hb := HOLLOWBROOK
	WorldProps.fences(self, [
		[Vector3(-3.7, 0, -17), Vector3(-1.9, 0, -40)], [Vector3(5.7, 0, -22), Vector3(7.9, 0, -50)],
		[Vector3(-4.4, 0, 40), Vector3(-3.5, 0, 58)], [Vector3(4.8, 0, 44), Vector3(5.6, 0, 60)],
		[mill + Vector3(-8, 0, 6), mill + Vector3(6, 0, 12)], [mill + Vector3(6, 0, 12), mill + Vector3(12, 0, 0)],
		[hb + Vector3(-8, 0, -12), hb + Vector3(-16, 0, -2)], [hb + Vector3(-16, 0, -2), hb + Vector3(-12, 0, 10)]])
	# Hay bales by the windmill and a signpost at the crossroads.
	var bales := []
	for k in 4:
		bales.append(mill + Vector3(-4 + k * 1.9, 0, -7 + (k % 2) * 1.2))
	if not WorldProps.hay(self, bales):
		for b in bales:
			WorldArt.cyl(self, 0.8, 0.8, 1.4, b + Vector3(0, 0.8, 0), Color("e6c76a"), 12, Vector3(0, 0, PI / 2))
	if not WorldProps.signpost(self, Vector3(3.2, 0, -8), 0.4):
		WorldArt.cyl(self, 0.08, 0.1, 2.6, Vector3(3.2, 1.3, -8), WorldArt.WOOD, 6)
		WorldArt.box(self, Vector3(1.4, 0.3, 0.08), Vector3(3.4, 2.2, -8), WorldArt.WOOD_LIGHT, Vector3(0, 0.4, 0))
		WorldArt.box(self, Vector3(1.4, 0.3, 0.08), Vector3(3.0, 1.8, -8), WorldArt.WOOD_LIGHT, Vector3(0, -1.2, 0))
	# Pond-side rest spot: a log stack and a crooked tree.
	WorldProps.prop(self, "nature", "log_stack", Vector3(WorldArt.POND.x - 11.5, 0, WorldArt.POND.y + 3.0), 0.6, WorldProps.NATURE, "box")


func _build_tower() -> void:
	# The labyrinth tower rises past the clouds toward the next floor. The
	# collision cylinder is unchanged; WorldArt.tower adds the tiers, ledges,
	# buttresses, spiralling windows and the gate arch.
	var body := StaticBody3D.new()
	body.position = TOWER_POS
	var shape := CylinderShape3D.new()
	shape.radius = 12
	shape.height = 220
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 110
	body.add_child(cs)
	add_child(body)
	WorldArt.tower(self, TOWER_POS)
	WorldProps.labyrinth_grounds(self, TOWER_POS, _art_rng)
	# Sealed door.
	var door := _static_box(Vector3(5, 7, 1), TOWER_POS + Vector3(0, 3.5, 12), Color("2a1f45"))
	var dmi: MeshInstance3D = door.get_child(0)
	dmi.mesh.material = WorldArt.mat(_gate_tint, 0.03, _gate_glow, 1.4)
	var seal := TorusMesh.new()
	seal.inner_radius = 1.2
	seal.outer_radius = 1.5
	seal.material = WorldArt.rune_mat(_gate_glow.lightened(0.4), 2.5)
	WorldArt.mesh_node(door, seal, Vector3(0, 0.4, 0.6), null, Vector3(PI / 2, 0, 0))
	WorldProps.tower_gate_dress(self, TOWER_POS)


var _boss: Enemy
var _exit_portal: Node3D
var _floor_cleared_on_server := false
var _floor_open := false  # This instance's Guardian is down (shown to everyone).
var _gate: Node3D         # The sealed gate behind the Guardian (WorldArt.sealed_gate).
var _gate_pos := Vector3.ZERO
var _gate_open := false
var _traveling := false


## Server tells a late joiner whether this instance already beat the Guardian.
## They get the open gate and the exit portal, not the reward.
@rpc("authority", "call_remote", "reliable")
func sync_floor_state(cleared: bool) -> void:
	if cleared:
		_show_floor_cleared()


func _build_arena() -> void:
	# Round platform on top of the tower, ringed by a low wall.
	var body := StaticBody3D.new()
	body.position = ARENA_POS
	var disc := CylinderMesh.new()
	disc.top_radius = ARENA_RADIUS
	disc.bottom_radius = ARENA_RADIUS
	disc.height = 1.0
	disc.radial_segments = 48
	disc.material = WorldArt.platform_floor_mat(Vector2(ARENA_POS.x, ARENA_POS.z), _rune, ARENA_POS.y - 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.position.y = -0.5
	body.add_child(mi)
	var shape := CylinderShape3D.new()
	shape.radius = ARENA_RADIUS
	shape.height = 1.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)
	# Summoning circle over the flags, carved underside, floating rubble.
	var rune := _rune
	var dais := WorldArt.cyl(self, ARENA_RADIUS - 2.5, ARENA_RADIUS - 2.3, 0.12, ARENA_POS, Color("6f6887"), 48)
	dais.material_override = WorldArt.ruin_mat("ledge")
	WorldArt.rune_floor(self, ARENA_POS + Vector3(0, 0.06, 0), ARENA_RADIUS - 2.9, rune)
	WorldArt.platform_dress(self, ARENA_POS, ARENA_RADIUS, rune)
	WorldArt.floating_debris(self, ARENA_POS, ARENA_RADIUS, rune)
	# Parapet ring: the boxes keep the collision, the dungeon balustrade
	# (when the pack is there) replaces their look. The gate side stays open
	# for the sealed door.
	var gate_dir := Vector3(0, 0, -1)
	var entry_dir := Vector3(0, 0, 1)
	var angles := []
	for i in 24:
		var a := TAU * i / 24.0
		angles.append(a)
		var seg := _static_box(Vector3(4.6, 1.5, 0.8), ARENA_POS + Vector3(cos(a), 0, sin(a)) * (ARENA_RADIUS - 0.4) + Vector3(0, 0.75, 0), Color("6f6887"), -a - PI / 2)
		if WorldProps.has("dungeon", "barrier"):
			seg.get_child(0).visible = false
	WorldProps.parapet(self, ARENA_POS, ARENA_RADIUS - 0.4, angles, 4.6, 1.5, 0.88, gate_dir)
	# Four tall columns (same 1.2 x 9 x 1.2 colliders), two of them snapped.
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4
		var p := ARENA_POS + Vector3(cos(a), 0, sin(a)) * ARENA_RADIUS * 0.75
		var pillar := _static_box(Vector3(1.2, 9, 1.2), p + Vector3(0, 4.5, 0), Color("5a4a7a"))
		pillar.get_child(0).visible = false
		WorldArt.broken_column(self, p, 9.0, rune, i % 2 == 1, 1.0)
	# Sealed gate behind the Guardian, braziers, ruined colonnade.
	_gate_pos = ARENA_POS + Vector3(0, 0, -(ARENA_RADIUS - 1.6))
	_gate = WorldArt.sealed_gate(self, _gate_pos, entry_dir, rune)
	WorldArt.box_collider(self, Vector3(9.0, 9.0, 2.6), ARENA_POS + Vector3(0, 4.5, -(ARENA_RADIUS - 0.6)))
	for p in [Vector3(-4.6, 0, -12.6), Vector3(4.6, 0, -12.6), Vector3(-14.2, 0, 1.5), Vector3(14.2, 0, 1.5)]:
		WorldArt.brazier(self, ARENA_POS + p)
		WorldArt.box_collider(self, Vector3(1.4, 2.2, 1.4), ARENA_POS + p + Vector3(0, 1.1, 0))
	WorldProps.summit_props(self, ARENA_POS, ARENA_RADIUS, rune, gate_dir, entry_dir)
	# The Guardian's throne before the sealed gate (it waits there, then leaps down).
	WorldProps.boss_throne(self, ARENA_POS + Vector3(0, 0, -10.5), rune)


func _build_platform(pos: Vector3, radius: float, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 1.0
	disc.radial_segments = 40
	disc.material = WorldArt.platform_floor_mat(Vector2(pos.x, pos.z), color, pos.y - 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.position.y = -0.5
	body.add_child(mi)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 1.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)


func _add_pad(pos: Vector3, label: String, dest, color: Color, toast := "") -> void:
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4
	cm.bottom_radius = 1.5
	cm.height = 0.15
	cm.radial_segments = 24
	cm.material = WorldArt.ruin_mat("trim")
	pad.mesh = cm
	pad.position = pos + Vector3(0, 0.08, 0)
	add_child(pad)
	# Glowing inlay inside a stone rim, instead of a solid lit slab.
	var inlay := CylinderMesh.new()
	inlay.top_radius = 1.15
	inlay.bottom_radius = 1.15
	inlay.height = 0.02
	inlay.radial_segments = 24
	WorldArt.mesh_node(self, inlay, pos + Vector3(0, 0.165, 0), WorldArt.mat(color.darkened(0.35), 0.0, color, 0.35))
	WorldArt.rune_ring(self, pos + Vector3(0, 0.18, 0), 1.25, color, 0.18)
	# Floating octahedral crystal (both points), a classic waypoint marker.
	var crystal := SphereMesh.new()
	crystal.radius = 0.32
	crystal.height = 1.2
	crystal.radial_segments = 4
	crystal.rings = 1
	var c := WorldArt.mesh_node(self, crystal, pos + Vector3(0, 1.6, 0), WorldArt.mat(color.lightened(0.3), 0.0, color, 3.0))
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "position:y", pos.y + 2.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(c, "position:y", pos.y + 1.4, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var spin := c.create_tween().set_loops()
	spin.tween_property(c, "rotation:y", TAU, 4.0).from(0.0)
	_pads.append({"pos": pos, "label": label, "dest": dest, "toast": toast if toast != "" else label})


func _build_labyrinth() -> void:
	var up_color: Color = _terrace_runes[0]
	var down_color := Color(1.0, 0.75, 0.3)
	var home_label := "Descend to town" if GameState.floor == 1 else "Descend to the waygate"
	for i in LAB_LEVELS.size():
		var base: Vector3 = LAB_LEVELS[i]
		_build_platform(base, LAB_RADIUS, Color("5b5570"))
		var toward := (TOWER_POS - base) * Vector3(1, 0, 1)
		var rune: Color = _terrace_runes[mini(i, _terrace_runes.size() - 1)]
		WorldArt.platform_dress(self, base, LAB_RADIUS, rune, toward.normalized(), 0.85)
		# Stone bridge back to the tower wall so the terrace reads as attached:
		# carved deck, balustrades (dungeon kit) and a rune keystone.
		var span := toward.length() - 10.0
		var dir := toward.normalized()
		var side := dir.cross(Vector3.UP)
		var mid := base + dir * (span / 2 + LAB_RADIUS - 1.5)
		var rot_y := -atan2(toward.z, toward.x)
		var deck := WorldArt.box(self, Vector3(span, 1.2, 4.0), mid + Vector3(0, -0.6, 0), WorldArt.STONE_DARK, Vector3(0, rot_y, 0), 0.0)
		deck.material_override = WorldArt.ruin_mat("wall")
		var keel := WorldArt.box(self, Vector3(span, 1.4, 2.2), mid + Vector3(0, -1.8, 0), WorldArt.STONE_DARK, Vector3(0, rot_y, 0), 0.0)
		keel.material_override = WorldArt.ruin_mat("trim")
		var a_end := mid - dir * (span / 2 - 0.3)
		var b_end := mid + dir * (span / 2 - 1.5)
		for sx in [-1, 1]:
			if not WorldProps.balustrade_line(self, a_end + side * sx * 1.85, b_end + side * sx * 1.85, 1.0):
				var rail := WorldArt.box(self, Vector3(span, 0.8, 0.3), mid + Vector3(0, 0.4, 0) + side * sx * 1.9, WorldArt.STONE, Vector3(0, rot_y, 0), 0.0)
				rail.material_override = WorldArt.ruin_mat("ledge")
		WorldArt.rune_ring(self, mid + Vector3(0, 0.06, 0), 1.3, rune, 0.16)
		WorldProps.entrance(self, base, LAB_RADIUS, dir, "banner_patternB_blue" if i == 0 else "banner_patternA_red")
		# Low wall with a gap toward the tower (boxes keep the collision; the
		# dungeon balustrade replaces their look when the pack is there).
		var angles := []
		for k in 20:
			var a := TAU * k / 20.0
			var toward_tower := Vector3(cos(a), 0, sin(a)).dot((TOWER_POS - base).normalized() * Vector3(1, 0, 1))
			if toward_tower > 0.85:
				continue
			angles.append(a)
			var seg := _static_box(Vector3(4.2, 1.2, 0.8), base + Vector3(cos(a), 0, sin(a)) * (LAB_RADIUS - 0.4) + Vector3(0, 0.6, 0), Color("6f6887"), -a - PI / 2)
			if WorldProps.has("dungeon", "barrier"):
				seg.get_child(0).visible = false
		WorldProps.parapet(self, base, LAB_RADIUS - 0.4, angles, 4.2, 1.25)
		# Pillars and rubble for cover (dungeon kit when present).
		if not WorldProps.terrace_dress(self, base, i):
			for k in 4:
				var a := TAU * k / 4.0 + 0.4
				var pillar := _static_box(Vector3(1.4, 3.0, 1.4), base + Vector3(cos(a) * 7, 1.5, sin(a) * 7), Color("7a7390"))
				WorldArt.box(pillar, Vector3(1.9, 0.4, 1.9), Vector3(0, 1.7, 0), WorldArt.STONE_DARK)
				WorldArt.box(pillar, Vector3(1.9, 0.4, 1.9), Vector3(0, -1.3, 0), WorldArt.STONE_DARK)
		for k in 5:
			var a := TAU * k / 5.0 + 1.1 + i
			var s := 0.6 + 0.3 * k
			WorldArt.mesh_node(self, WorldArt.boulder_mesh(k + 3 * i), base + Vector3(cos(a) * 10, s * 0.35, sin(a) * 10), WorldArt.ruin_mat("trim"), Vector3(0, a, 0), Vector3(2.0, 1.1, 2.0) * s)
		_add_pad(base + Vector3(0, 0, 9), home_label, GameState.spawn_point(), down_color, GameState.floor_name())
		if i + 1 < LAB_LEVELS.size():
			var next: Vector3 = LAB_LEVELS[i + 1]
			_add_pad(base + Vector3(0, 0, -9), "Ascend to Terrace %d" % (i + 2), next + Vector3(0, 1, 9), up_color, "The Labyrinth  ·  Terrace %d" % (i + 2))
		else:
			_add_pad(base + Vector3(0, 0, -9), "Ascend to the Guardian's Summit", "summit", _rune.lerp(Color(0.7, 0.3, 1.0), 0.3))
	var last := LAB_LEVELS.size()
	_add_pad(ARENA_POS + Vector3(0, 0, 14), "Descend to Terrace %d" % last, LAB_LEVELS[last - 1] + Vector3(0, 1, 9), down_color, "The Labyrinth  ·  Terrace %d" % last)


func _spawn_boss() -> void:
	var bp := ARENA_POS + Vector3(0, 1, -6)
	if GameState.floor == 2:
		_spawn_mob({"name": "Floor Guardian: Mirelord, the Drowned Knight", "level": 13, "hp": 1500, "dmg": 24, "xp": 1400, "money": 900,
			"color": "3e5a60", "size": [2.4, 3.0, 2.4], "speed": 2.8, "aggro": 40, "boss": true, "respawns": false,
			"drops": {"spirit_shard": 1.0, "wisp_essence": 1.0, "stag_horn": 1.0}, "pos": [bp.x, bp.y, bp.z]})
		_boss_summon(null)
		return
	# The Kobold Warlord: four stacked HP bars, a guard of halberdiers on
	# engage and on every bar break, the weapon swap and second moveset on
	# the last bar (BossBrain.PRESETS["warlord"]). Twice a man's height.
	# He waits on his throne at the back of the room and leaps down when the
	# raid comes in (BossBrain.throne).
	var tp := throne_pos()
	_spawn_mob({"name": BOSS_NAME, "level": 7, "hp": 650, "dmg": 18, "xp": 600, "money": 400,
		"color": "8a6a4a", "size": [2.2, 3.4, 2.2], "speed": 3.0, "aggro": 40, "boss": true, "respawns": false,
		"brain": "warlord", "drops": {"spirit_shard": 1.0, "iron_ore": 1.0}, "pos": [tp.x, tp.y, tp.z]})


const BOSS_NAME := "Floor Guardian: Vargash the Kobold Warlord"


## Top of the throne dais (WorldProps.boss_throne at ARENA_POS + (0, 0, -10.5)).
func throne_pos() -> Vector3:
	return ARENA_POS + Vector3(0, 1.0, -10.3)


## The Warlord's guard: plated kobolds with halberds. Their plate halves any
## blow until a parry staggers them (then the gaps are open), so a party
## parries and Switches through them.
func _halberdier_data(sp: Vector3) -> Dictionary:
	return {"name": "Kobold Halberdier", "level": 6, "hp": 130, "dmg": 11, "xp": 90, "money": 30,
		"color": "667380", "size": [1.0, 1.7, 1.0], "speed": 3.6, "aggro": 40, "respawns": false, "armor": 0.5,
		"drops": {"iron_ore": 0.8}, "pos": [sp.x, sp.y, sp.z]}


## The Warlord's call (BossBrain.spawn_adds, authority only): `count`
## halberdiers step out in a ring around him, on engage and when one of his
## HP bars breaks. They vanish with the boss or on reset.
func _guardian_adds(brain: Node, count: int) -> Array:
	var out: Array = []
	var boss: Node3D = brain.get_parent() as Node3D
	var at := boss.global_position if boss else ARENA_POS + Vector3(0, 1, -6)
	for i in count:
		var a := TAU * float(i) / float(maxi(count, 1)) + _rng.randf_range(0.0, 0.8)
		var sp := at + Vector3(cos(a) * 5.5, 0, sin(a) * 5.5)
		if sp.distance_to(ARENA_POS) > ARENA_RADIUS - 1.0:
			sp = ARENA_POS + (sp - ARENA_POS).normalized() * (ARENA_RADIUS - 1.0)
		sp.y = ARENA_POS.y + 1.0
		var e := _spawn_mob(_halberdier_data(sp))
		if e != null:
			out.append(e)
	return out


## Mirelord's call: two Drowned Wisps rise beside him (at the start of the
## fight and every Enemy.SUMMON_PERIOD s) while fewer than four are up.
## Authority only; wisps use the normal mob path and do not respawn.
func _boss_summon(boss: Enemy) -> void:
	var alive := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.visible and e.display_name == "Drowned Wisp":
			alive += 1
	if alive >= 4:
		return
	var at := boss.global_position if boss else ARENA_POS + Vector3(0, 1, -6)
	for side in [-1, 1]:
		var sp := at + Vector3(4.5 * side, 1, 3)
		_spawn_mob({"name": "Drowned Wisp", "level": 12, "hp": 150, "dmg": 13, "xp": 160, "money": 40,
			"color": "7fe8d0", "size": [0.7, 0.9, 0.7], "speed": 3.2, "aggro": 40, "ranged": 11.0, "respawns": false,
			"drops": {"wisp_essence": 0.7}, "pos": [sp.x, sp.y, sp.z]})


## Server-side (or offline): the Guardian fell. Everyone on the floor clears it.
func _on_boss_died(_e: Enemy) -> void:
	_boss = null
	_floor_cleared_on_server = true
	if is_instance_valid(_e):
		_grant_last_attack(_e._last_hitter)
	if Net.online:
		# Server: the clear reward goes onto the record of everyone on the
		# summit (server-accepted positions) and reaches them as a patch.
		for peer in Net.srv_records.keys():
			var pp = Net._srv_player_pos(peer)
			if pp is Vector3 and pp.distance_to(ARENA_POS) < ARENA_RADIUS + 10:
				var rs = Net.RecordState.new(Net.srv_records[peer])
				var bounty: bool = _bounty_quest_id() != "" and rs.quests.has(_bounty_quest_id()) and not rs.quest_done(_bounty_quest_id())
				if bounty:
					rs.advance_quest(_bounty_quest_id())  # Captain Rhys's bounty: the kill counts for everyone on the summit
				if int(rs.floors_cleared) < GameState.floor:
					rs.floors_cleared = GameState.floor
					rs.start_quest(_boss_quest_id(), 1)
					rs.advance_quest(_boss_quest_id())
					rs.complete_quest(_boss_quest_id())
					rs.add_material("spirit_shard", 3)
					Net.save_record(Net.srv_records[peer])
					Net._srv_reply(peer, "floor_cleared", {})
				elif bounty:
					Net.save_record(Net.srv_records[peer])
					Net._srv_reply(peer, "bounty", {})
		net_floor_cleared.rpc()
	else:
		net_floor_cleared()


@rpc("authority", "call_local", "reliable")
func net_floor_cleared() -> void:
	# Reward once per character, and only if you were on the summit for the kill.
	# An online client gets its reward from the server (net_apply "floor_cleared").
	if Net.remote_client():
		_show_floor_cleared()
		return
	if _bounty_quest_id() != "" and player and player.global_position.distance_to(ARENA_POS) < ARENA_RADIUS + 10:
		GameState.advance_quest(_bounty_quest_id())  # no-op unless the bounty is open
	if GameState.floors_cleared < GameState.floor and player and player.global_position.distance_to(ARENA_POS) < ARENA_RADIUS + 10:
		GameState.floors_cleared = GameState.floor
		GameState.advance_quest(_boss_quest_id())
		GameState.complete_quest(_boss_quest_id())
		GameState.add_material("spirit_shard", 3)
		if hud:
			hud.toast("FLOOR %d CLEARED!" % GameState.floor)
	_show_floor_cleared()


## The sealed gate behind the Guardian wakes: the slab sinks into the floor
## and the seals turn from the floor's rune colour to living green.
func _open_gate() -> void:
	if _gate_open or _gate == null:
		return
	_gate_open = true
	var open_c := Color("6fe0a0")
	var door := _gate.get_node_or_null("Door") as MeshInstance3D
	if door:
		var tw := door.create_tween()
		tw.tween_property(door, "position:y", -3.6, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func(): door.visible = false)
	for nm in ["Seal", "Seal2"]:
		var mi := _gate.get_node_or_null(nm) as MeshInstance3D
		if mi:
			mi.mesh = mi.mesh.duplicate()
			mi.mesh.surface_set_material(0, WorldArt.rune_mat(open_c if nm == "Seal" else open_c.lightened(0.3), 3.2))
	for nm in ["Bar1", "Bar5", "Keystone"]:
		var mi := _gate.get_node_or_null(nm) as MeshInstance3D
		if mi:
			mi.mesh = mi.mesh.duplicate()
			mi.mesh.surface_set_material(0, WorldArt.mat(open_c.lightened(0.4), 0.0, open_c, 3.0))
	# Light spills through the open arch.
	var glow := CylinderMesh.new()
	glow.top_radius = 2.1
	glow.bottom_radius = 2.1
	glow.height = 0.05
	glow.radial_segments = 32
	var gm := WorldArt.mesh_node(_gate, glow, Vector3(0, 3.5, -0.2), WorldArt.water_mat(Vector2(0, 1), 0.5, open_c.lightened(0.3), open_c.darkened(0.4)), Vector3(PI / 2, 0, 0))
	gm.name = "Veil"
	if not WorldArt.headless():
		var l := OmniLight3D.new()
		l.light_color = open_c
		l.light_energy = 1.6
		l.omni_range = 10.0
		l.position = Vector3(0, 3.5, 1.5)
		_gate.add_child(l)
	if hud and GameState.floor == 1:
		hud.toast("The gate to Floor 2 stirs open.")


## True when the summit gate is open and leads somewhere (Floor 2 exists).
func _floor_gate_ready() -> bool:
	return _gate_open and GameState.floor == 1


func _use_floor_gate() -> void:
	if Net.online:
		hud.show_dialogue("Waygate", "Floors are separate servers. To continue on Floor %d, join a Floor %d server from the main menu (dedicated: --server --floor %d)." % [GameState.floor + 1, GameState.floor + 1, GameState.floor + 1])
	elif GameState.floor >= 2:
		hud.show_dialogue("Sealed Gate", "Beyond the arch the stair climbs into cloud. Floor 3 is not yet carved.")
	else:
		_travel_to_floor(GameState.floor + 1)


## Offline floor change: the character keeps everything, arrives at the new
## floor's waygate, and the save follows so Continue returns there.
func _travel_to_floor(f: int) -> void:
	if _traveling:
		return
	_traveling = true
	GameState.floor = clampi(f, 1, 2)
	GameState.has_position = false
	GameState.heal_full()
	SaveSystem.save_game(0)
	if hud:
		hud.toast("Ascending to Floor %d  ·  %s" % [GameState.floor, GameState.floor_name()])
	Audio.play("teleport")
	get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")


func _show_floor_cleared() -> void:
	_floor_open = true
	_open_gate()
	if _exit_portal:
		return
	# Exit portal appears where the boss stood.
	_exit_portal = Node3D.new()
	_exit_portal.position = ARENA_POS + Vector3(0, 2, -6)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.6
	tm.outer_radius = 2.0
	tm.rings = 48
	tm.material = WorldArt.rune_mat(Color(0.4, 0.8, 1.0), 2.5)
	ring.mesh = tm
	ring.rotation.x = PI / 2
	_exit_portal.add_child(ring)
	var core := CylinderMesh.new()
	core.top_radius = 1.6
	core.bottom_radius = 1.6
	core.height = 0.05
	core.radial_segments = 32
	WorldArt.mesh_node(_exit_portal, core, Vector3.ZERO, WorldArt.water_mat(Vector2(1, 1), 0.8), Vector3(PI / 2, 0, 0))
	var tw := ring.create_tween().set_loops()
	tw.tween_property(ring, "rotation:z", TAU, 10.0).from(0.0)
	add_child(_exit_portal)


const HOLLOWBROOK := Vector3(-144, 0, 84)  # WorldArt.HOLLOWBROOK
const TALVEN := Vector3(-42, 0, -162)      # WorldArt.TALVEN


## First village outside town: a handful of cottages and the elder's gather quest.
func _build_hollowbrook() -> void:
	# Five cottages (and the cold forge from the elder's quest) ring the well,
	# doors toward it. The ring radius grows a little so the bigger KayKit
	# footprints stay clear of each other and of the road ending at the east.
	var kinds := ["home_A", "home_B", "blacksmith", "tavern", "home_B"]  # the tavern is Innkeeper Rook's
	var colors := ["yellow", "green", "red", "blue", "red"]
	var ring := 10.5 if WorldProps.ready() else 9.0
	for i in 5:
		var a := TAU * i / 5.0 + 0.35
		var pos := HOLLOWBROOK + Vector3(cos(a) * ring, 0, sin(a) * ring)
		var face := atan2(-cos(a), -sin(a))
		if WorldProps.ready():
			WorldProps.house(self, pos, kinds[i], colors[i], face, WorldProps.HOUSE * 0.9)
		else:
			WorldArt.house(self, pos, 5.0, 4.5, 3.4, face, [1, 3, 0, 1, 2][i])
		if kinds[i] == "tavern":
			_build_tavern(pos, face, WorldProps.footprint("tavern", colors[i], WorldProps.HOUSE * 0.9))
		elif kinds[i] == "blacksmith":
			_build_smithy(pos, face, WorldProps.footprint("blacksmith", colors[i], WorldProps.HOUSE * 0.9))
	# Well in the middle.
	if WorldProps.ready():
		WorldProps.house(self, HOLLOWBROOK, "well", "red", 0.6, 4.2)
	else:
		var well := _static_box(Vector3(1.6, 1.0, 1.6), HOLLOWBROOK + Vector3(0, 0.5, 0), Color("8f8c96"))
		var wm := CylinderMesh.new()
		wm.top_radius = 0.6
		wm.bottom_radius = 0.6
		wm.height = 0.1
		WorldArt.mesh_node(well, wm, Vector3(0, 0.52, 0), WorldArt.water_mat(Vector2(1, 1), 0.2))
		for sx in [-1, 1]:
			WorldArt.box(well, Vector3(0.14, 2.0, 0.14), Vector3(sx * 0.7, 1.4, 0), WorldArt.WOOD)
		var roof := PrismMesh.new()
		roof.size = Vector3(2.2, 0.8, 2.0)
		WorldArt.mesh_node(well, roof, Vector3(0, 2.75, 0), WorldArt.mat(WorldArt.TERRACOTTA, 0.03))
		WorldArt.cyl(well, 0.05, 0.05, 1.5, Vector3(0, 2.1, 0), WorldArt.WOOD, 6, Vector3(0, 0, PI / 2))
		WorldArt.cyl(well, 0.18, 0.18, 0.25, Vector3(0, 1.3, 0), WorldArt.WOOD, 8)
	# Village dressing: lanterns, crates, a cart, a vegetable patch.
	WorldProps.lantern(self, HOLLOWBROOK + Vector3(4, 0, 4), 0.8)
	WorldProps.lantern(self, HOLLOWBROOK + Vector3(-4, 0, -4), -2.3)
	WorldProps.crate(self, HOLLOWBROOK + Vector3(5, 0, -1), 0.9, 0.4)
	WorldProps.barrel(self, HOLLOWBROOK + Vector3(-5.5, 0, 1.5))
	WorldProps.prop(self, "town", "cart", HOLLOWBROOK + Vector3(6.5, 0, 6.0), 1.1, WorldProps.TOWN, "box")
	WorldProps.prop(self, "nature", "log_stack", HOLLOWBROOK + Vector3(-7.5, 0, -5.5), 0.3, WorldProps.NATURE, "box")
	if not WorldProps.crops(self, HOLLOWBROOK + Vector3(-19, 0, -1), 4, 0.0):
		for k in 6:
			WorldArt.box(self, Vector3(1.0, 0.25, 3.5), HOLLOWBROOK + Vector3(-16 + k * 1.3, 0.12, 2), Color("7a5a3a"), Vector3.ZERO, 0.0)
			for j in 4:
				WorldArt.sphere(self, 0.3, HOLLOWBROOK + Vector3(-16 + k * 1.3, 0.4, 0.8 + j * 0.8), Color("6fbf5a"))
	WorldProps.fences(self, [[HOLLOWBROOK + Vector3(-21, 0, -3.5), HOLLOWBROOK + Vector3(-9, 0, -3.5)],
		[HOLLOWBROOK + Vector3(-21, 0, 5.5), HOLLOWBROOK + Vector3(-9, 0, 5.5)]])
	var elder := NPC.new()
	elder.npc_name = "Elder Wren"
	elder.appearance = {"hair_color": "dddddd", "outfit_color": "6d597a", "hair_style": 2, "eye_color": "355070", "height": 0.95}
	elder.position = HOLLOWBROOK + Vector3(0, 0, -3)
	elder.rotation.y = PI
	_set_talk(elder, _elder_talk)
	add_child(elder)


## Rook's tavern: its door and exit mat are pads (the server knows the jump)
## and its hearth is a cooking fire.
func _build_tavern(pos: Vector3, face: float, footprint: Vector2) -> void:
	_tavern = Tavern.build(self, pos, face, footprint)
	_pads.append({"pos": _tavern.door_pos, "label": "Enter the Hollow Hearth", "dest": _tavern.spawn_inside, "toast": "The Hollow Hearth"})
	_pads.append({"pos": _tavern.exit_pos, "label": "Leave the tavern", "dest": _tavern.door_out + Vector3(0, 1, 0), "toast": "Hollowbrook"})
	_campfires.append({"pos": _tavern.interior + Tavern.HEARTH + Vector3(1.4, 0, 0), "range": 2.2, "label": "Cook at the tavern hearth", "where": "The Hollow Hearth"})


func _build_smithy(pos: Vector3, face: float, footprint: Vector2) -> void:
	_smithy = Smithy.build(self, pos, face, footprint)
	_pads.append({"pos": _smithy.door_pos, "label": "Enter Hollowbrook Forge", "dest": _smithy.spawn_inside, "toast": "Hollowbrook Forge"})
	_pads.append({"pos": _smithy.exit_pos, "label": "Leave the forge", "dest": _smithy.door_out + Vector3(0, 1, 0), "toast": "Hollowbrook"})


func _kesra_talk(gs = GameState) -> String:
	if gs == GameState:
		_open_craft("Kesra's anvil")
	if gs.quest_done("ore_delivery"):
		return "Wren's ore lit this forge, and you carried it. The anvil is yours whenever you need it. The village pins its commissions on the board by the door."
	return "Cold iron and no ore wagons. I can still lend you the anvil; the village pins its commissions on the board by the door. Wren could use your help with ore."


func _elder_talk(gs = GameState) -> String:
	var need := 6
	if gs.quest_done("ore_delivery"):
		return "Hollowbrook's forge burns again thanks to you. Rest a while."
	if not gs.quests.has("ore_delivery"):
		gs.start_quest("ore_delivery", need)
		return "Our forge went cold when the ore wagons stopped. Bring me %d Iron Ore from the veins in the fields and Hollowbrook will remember you." % need
	var have: int = gs.materials.get("iron_ore", 0)
	gs.quests["ore_delivery"]["progress"] = min(have, need)
	if gs == GameState:
		GameState.quest_changed.emit()
	if have >= need:
		gs.spend_materials({"iron_ore": need})
		gs.complete_quest("ore_delivery")
		gs.add_xp(120)
		gs.add_money(80)
		gs.add_material("spirit_shard", 2)
		return "Bless you. Take these shards; the smith in town knows what to do with them.\n(+120 XP, +80 Col, +2 Spirit Shards)"
	return "You carry %d of the %d ore we need. The veins glint gold in the fields south of town." % [have, need]


## Last camp before the Labyrinth: tents, a fire, and a quartermaster who patches you up.
func _build_talven() -> void:
	for i in 3:
		var a := TAU * i / 3.0 + 0.5
		var pos := TALVEN + Vector3(cos(a) * 6, 0, sin(a) * 6)
		if WorldProps.tent(self, pos, atan2(-cos(a), -sin(a))):
			continue
		var tent := StaticBody3D.new()
		tent.position = pos
		tent.rotation.y = -a
		var pm := PrismMesh.new()
		pm.size = Vector3(4, 2.6, 4)
		pm.material = WorldArt.mat([Color("c9a06a"), Color("9a6a4a"), Color("b8865a")][i], 0.03)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.position.y = 1.3
		tent.add_child(mi)
		WorldArt.box(tent, Vector3(4.2, 0.18, 0.18), Vector3(0, 2.6, 0), WorldArt.WOOD)
		WorldArt.box(tent, Vector3(0.12, 2.6, 0.12), Vector3(0, 1.3, 1.95), WorldArt.WOOD)
		WorldArt.box(tent, Vector3(0.12, 2.6, 0.12), Vector3(0, 1.3, -1.95), WorldArt.WOOD)
		WorldArt.box(tent, Vector3(0.06, 1.0, 0.7), Vector3(0, 3.4, 0.35), Color("c93d5a"), Vector3.ZERO, 0.0)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(4, 2.6, 4)
		cs.shape = bs
		cs.position.y = 1.3
		tent.add_child(cs)
		add_child(tent)
	# Campfire: stone ring, logs, flame and a flickering light.
	if not WorldProps.campfire(self, TALVEN):
		for k in 8:
			var a := TAU * k / 8.0
			WorldArt.sphere(self, 0.3, TALVEN + Vector3(cos(a) * 1.0, 0.15, sin(a) * 1.0), WorldArt.STONE_DARK, Vector3(1, 0.7, 1))
		for k in 3:
			WorldArt.cyl(self, 0.12, 0.12, 1.3, TALVEN + Vector3(0, 0.25, 0), WorldArt.WOOD, 6, Vector3(0, TAU * k / 3.0, PI / 2.3))
	var fire := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.0
	fm.bottom_radius = 0.55
	fm.height = 1.2
	fm.radial_segments = 8
	fm.material = WorldArt.mat(Color("ffb347"), 0.0, Color("ff6a1a"), 3.5)
	fire.mesh = fm
	fire.position = TALVEN + Vector3(0, 0.75, 0)
	add_child(fire)
	var ftw := fire.create_tween().set_loops()
	ftw.tween_property(fire, "scale", Vector3(0.85, 1.2, 0.85), 0.35).set_trans(Tween.TRANS_SINE)
	ftw.tween_property(fire, "scale", Vector3(1.1, 0.9, 1.1), 0.4).set_trans(Tween.TRANS_SINE)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.omni_range = 6
	light.light_energy = 0.8
	light.position = TALVEN + Vector3(0, 1.5, 0)
	add_child(light)
	if not WorldArt.headless():
		var smoke := WorldArt._particles(TALVEN + Vector3(0, 1.4, 0), 24, 3.0, Vector3(0.2, 0.1, 0.2), Color(0.5, 0.5, 0.55, 0.45), 0.5, 0.0)
		smoke.process_material.initial_velocity_min = 1.0
		smoke.process_material.initial_velocity_max = 1.6
		smoke.process_material.spread = 12.0
		smoke.process_material.scale_max = 2.5
		add_child(smoke)
	WorldProps.crate(self, TALVEN + Vector3(4.5, 0, -3), 1.0, 0.5)
	WorldProps.barrel(self, TALVEN + Vector3(-4.2, 0, -3.5))
	WorldProps.barrel(self, TALVEN + Vector3(-3.2, 0, -4.2), 1.1)
	if not WorldProps.camp_gear(self, TALVEN):
		WorldArt.crate(self, TALVEN + Vector3(4.5, 1.0, -3), 0.7, 0.2)
		# Weapon rack and a camp banner.
		WorldArt.box(self, Vector3(2.0, 0.12, 0.12), TALVEN + Vector3(-5, 1.4, 2), WorldArt.WOOD)
		for k in 3:
			WorldArt.box(self, Vector3(0.08, 1.5, 0.08), TALVEN + Vector3(-5.6 + k * 0.6, 0.75, 2), WorldArt.WOOD)
			WorldArt.box(self, Vector3(0.1, 1.1, 0.04), TALVEN + Vector3(-5.6 + k * 0.6, 1.2, 2.1), Color("c9ced8"), Vector3(0.2, 0, 0))
		WorldArt.cyl(self, 0.06, 0.08, 4.0, TALVEN + Vector3(6, 2.0, 3), WorldArt.WOOD, 6)
		WorldArt.box(self, Vector3(1.2, 1.6, 0.05), TALVEN + Vector3(6.6, 3.2, 3), Color("2f4858"), Vector3.ZERO, 0.0)
	var qm := NPC.new()
	qm.npc_name = "Quartermaster Dain"
	qm.appearance = {"hair_color": "2b2b2b", "outfit_color": "2f4858", "hair_style": 1, "eye_color": "f6ae2d"}
	qm.position = TALVEN + Vector3(0, 0, 3)
	qm.rotation.y = PI
	_set_talk(qm, _dain_talk)
	add_child(qm)


## Quartermaster Dain patches you up; and if he has seen you turn eight
## blows in a row without a scratch (hidden stat, HiddenClasses), he opens
## the Stillblade rite nobody is told about.
func _dain_talk(gs = GameState) -> String:
	gs.heal_full()
	var still := _still_talk(gs)
	if still != "":
		return still
	if gs.floors_cleared >= 1:
		return "You did it. The whole camp is talking about the Guardian's fall."
	return "Sit by the fire, you're patched up. The Guardian hits like a landslide; bring armor and don't stand in the slam."


func _still_talk(gs) -> String:
	var qid := HiddenClasses.STILL_QUEST
	if str(gs.hidden_class) == HiddenClasses.STILLBLADE:
		return "Stillblade. Keep the edge where it is and let them come to it. The fire is yours whenever you want it."
	if gs.quest_done(qid):
		return ""
	if gs.quests.has(qid):
		if gs.quest_ready(qid):
			gs.complete_quest(qid)
			gs.unlock_hidden_class(HiddenClasses.STILLBLADE)
			return "Ten, and not one of them moved you. The old drill has a name for that: Stillblade. Your guard will come back faster now, and you will feel two cuts the rest of us never learn. Still Water, in the breath after a parry; Breaking Wave, when something needs putting on its knees."
		var q: Dictionary = gs.quests[qid]
		return "%d of %d. Turn the blow, do not chase it. The mob tells you when it swings; you only have to be there." % [int(q["progress"]), int(q["goal"])]
	if str(gs.hidden_class) != "":
		return ""  # one hidden class per character
	if HiddenClasses.still_ready(gs):
		gs.start_quest(qid, HiddenClasses.STILL_QUEST_GOAL)
		return "I watched you from the fire. Eight blows turned, not a scratch taken. The camp had a drill for that once, before the Guardian woke, and a name at the end of it. Ten more parries, anywhere on this floor, and come back to me. Tell nobody; the ones who go looking for it never find it."
	return ""


func _spawn_ore_veins(count := 26) -> void:
	var rock := WorldArt.rock_mesh()
	for i in count:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(45, FLOOR_RADIUS - 8)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		if GameState.floor != 2:
			# Off the roads and out of the pond.
			var guard1 := 0
			while WorldArt.ground_kind(Vector2(pos.x, pos.z)) != WorldArt.Ground.GRASS and guard1 < 40:
				guard1 += 1
				a = _rng.randf() * TAU
				r = _rng.randf_range(45, FLOOR_RADIUS - 8)
				pos = Vector3(cos(a) * r, 0, sin(a) * r)
			pos.y = WorldArt.height_at(Vector2(pos.x, pos.z))
		if GameState.floor == 2:
			# Mirewood: keep veins out of the lake, the barrow and the tracks.
			var guard := 0
			while Floor2Art.ground_kind(Vector2(pos.x, pos.z)) != WorldArt.Ground.GRASS and guard < 40:
				guard += 1
				a = _rng.randf() * TAU
				r = _rng.randf_range(40, FLOOR_RADIUS - 8)
				pos = Vector3(cos(a) * r, 0, sin(a) * r)
		var vein := _static_box(Vector3(1.6, 1.2, 1.6), pos + Vector3(0, 0.6, 0), Color("6e6a70"), _rng.randf() * TAU)
		(vein.get_child(0) as MeshInstance3D).visible = false
		WorldArt.mesh_node(vein, rock, Vector3(0, -0.35, 0), WorldArt.mat(Color("6e6a70"), 0.03), Vector3.ZERO, Vector3(1.3, 1.1, 1.2))
		WorldArt.mesh_node(vein, rock, Vector3(0.6, -0.5, 0.4), WorldArt.mat(Color("5c585f"), 0.03), Vector3(0, 1.2, 0), Vector3(0.7, 0.6, 0.7))
		var ore := MeshInstance3D.new()
		var om := SphereMesh.new()
		om.radius = 0.35
		om.height = 0.7
		om.radial_segments = 6
		om.rings = 3
		om.material = WorldArt.mat(Color("e0a040"), 0.02, Color("ffb84a"), 0.6)
		ore.mesh = om
		ore.position.y = 0.55
		vein.add_child(ore)
		for k in 3:
			var ang := TAU * k / 3.0 + 0.7
			WorldArt.mesh_node(vein, om, Vector3(cos(ang) * 0.6, 0.15 + 0.1 * k, sin(ang) * 0.6), null, Vector3(0.3, ang, 0.2), Vector3(0.5, 0.5, 0.5))
		vein.add_to_group("ore_veins")
		_vein_positions.append(pos)


func _spawn_npcs() -> void:
	var smith := NPC.new()
	smith.npc_name = "Smith Haldor"
	smith.appearance = {"hair_color": "6b3e26", "outfit_color": "4a4a4a", "hair_style": 0, "eye_color": "8d6e63", "height": 1.1}
	smith.position = Vector3(16, 0, 22)
	smith.rotation.y = PI * 0.75
	_set_talk(smith, _smith_talk)
	add_child(smith)
	# Anvil, forge and tool rack next to him.
	if not WorldProps.smithy(self, Vector3(17.5, 0, 20.5), Vector3(19.5, 0, 18.5)):
		var anvil := _static_box(Vector3(1.2, 0.5, 0.5), Vector3(17.5, 0.75, 20.5), Color("3b3b44"))
		WorldArt.box(anvil, Vector3(0.6, 0.5, 0.6), Vector3(0, -0.5, 0), WorldArt.WOOD)
		WorldArt.cyl(anvil, 0.1, 0.22, 0.5, Vector3(0.75, 0.0, 0), Color("3b3b44"), 8, Vector3(0, 0, PI / 2))
		var forge := _static_box(Vector3(2.2, 1.2, 1.6), Vector3(19.5, 0.6, 18.5), Color("7a6a66"))
		WorldArt.box(forge, Vector3(1.0, 1.4, 1.0), Vector3(-0.4, 1.3, -0.2), WorldArt.STONE_DARK)
		WorldArt.mesh_node(forge, SphereMesh.new(), Vector3(0.4, 0.65, 0.3), WorldArt.mat(Color("ff9a3c"), 0.0, Color("ff5a1a"), 3.0), Vector3.ZERO, Vector3(0.35, 0.25, 0.35))
	else:
		# Forge embers under the grindstone keep the smithy's warm glow.
		WorldArt.mesh_node(self, SphereMesh.new(), Vector3(19.9, 0.5, 18.8), WorldArt.mat(Color("ff9a3c"), 0.0, Color("ff5a1a"), 3.0), Vector3.ZERO, Vector3(0.3, 0.2, 0.3))
	var fl := OmniLight3D.new()
	fl.light_color = Color("ff8a3c")
	fl.light_energy = 0.6
	fl.omni_range = 3.5
	fl.position = Vector3(19.9, 1.5, 18.8)
	add_child(fl)
	_add_npc("Guide Mira", Vector3(5, 0, 10), {
		"hair_color": "f4a261", "outfit_color": "2a9d8f", "hair_style": 3, "eye_color": "264653"},
		"boar_trouble", 5, 150, 100, {
			"offer": "Welcome to the Spire, newcomer! Boars have been tearing up the fields outside town. Take down 5 of them?",
			"in_progress": "The boars roam the southern fields, just past the houses.",
			"turn_in": "You're a natural! Here's your reward.",
			"done": "Smith Haldor by the plaza can turn those hides into armor. Captain Rhys up north has work too.",
		})
	var rhys := _add_npc("Captain Rhys", Vector3(-4, 0, -12), {
		"hair_color": "c0c0c0", "outfit_color": "3a3a5a", "hair_style": 1, "eye_color": "e63946"},
		"wolf_hunt", 6, 400, 250, {
			"offer": "Dire wolves gather near the Labyrinth tower to the north. Thin their pack: 6 should do.",
			"in_progress": "Watch yourself, they hunt in groups.",
			"turn_in": "Impressive. Reach level %d and the tower gate will open for you." % GATE_LEVEL,
			"done": "The Floor Guardian waits atop the Labyrinth.",
		})
	_set_talk(rhys, func(gs): return _rhys_talk(rhys, gs))
	_spawn_hollowbrook_chain()


func _add_npc(n: String, pos: Vector3, look: Dictionary, quest: String, goal: int, xp: int, money: int, lines: Dictionary) -> NPC:
	var npc := NPC.new()
	npc.npc_name = n
	npc.appearance = look
	npc.quest_id = quest
	npc.quest_goal = goal
	npc.quest_xp = xp
	npc.quest_money = money
	npc.lines = lines
	npc.position = pos
	add_child(npc)
	npc.rotation.y = atan2(-pos.x, -pos.z) + PI
	return npc


func _spawn_mobs() -> void:
	# Meadow Slimes on the edge of the south field: the first thing to hit.
	for i in 9:
		var a := _rng.randf_range(0.3, PI - 0.3)
		var r := _rng.randf_range(46, 80)
		_spawn_mob({"name": "Meadow Slime", "level": 1, "hp": 22, "dmg": 3, "xp": 12, "money": 2, "color": "7fd36a",
			"size": [0.9, 0.7, 0.9], "speed": 2.2, "aggro": 6, "drops": {"spirit_shard": 0.1},
			"model": {"pack": "creatures", "name": "Slime"}, "pos": [cos(a) * r, 1, sin(a) * r]})
	# Boars in the south field (easy), wolves near the tower (harder).
	for i in 18:
		var a := _rng.randf_range(0.2, PI - 0.2)
		var r := _rng.randf_range(80, 205)
		if Vector3(cos(a) * r, 0, sin(a) * r).distance_to(HOLLOWBROOK) < 50.0:
			r = 75.0  # not in the village's back gardens
		# Boars paw the ground and charge (telegraphed, parryable, sidestep it).
		_spawn_mob({"name": "Field Boar", "level": 1, "hp": 40, "dmg": 6, "xp": 25, "money": 5, "color": "8c5940",
			"pos": [cos(a) * r, 1, sin(a) * r], "quest": "boar_trouble", "drops": {"beast_hide": 0.7}, "rush": true})
	# Greytusk: a named field elite (Satisfy-style): an old scarred boar that
	# roams the far end of the south field, comes back slowly, and pays a Last
	# Attack bonus (three Greytusk Hide Vests in the realm, then EXP and hide).
	_spawn_mob({"name": "Greytusk, the Old Boar", "level": 6, "hp": 380, "dmg": 15, "xp": 260, "money": 90, "color": "6b5a4a",
		"size": [1.5, 1.4, 2.2], "speed": 3.6, "aggro": 14, "rush": true, "armor": 0.8, "respawn": 900.0,
		"pos": [WorldArt.GREYTUSK.x, 1, WorldArt.GREYTUSK.y], "quest": "boar_trouble", "drops": {"beast_hide": 1.0, "spirit_shard": 0.4}, "la": GREYTUSK_LA})
	# Wolves hunt as a pack: strike one and the others come running.
	# Two dens in the northern woods on either side of the tower road.
	for i in 12:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := TOWER_POS + Vector3(side * _rng.randf_range(18, 64), 1, _rng.randf_range(26, 80))
		if Duels.in_safe_zone(p) or p.distance_to(TALVEN) < 18.0:
			p.x = absf(p.x - TOWER_POS.x) + TOWER_POS.x + 6.0  # never den inside the Talven camp's Inner Area
		_spawn_mob({"name": "Dire Wolf", "level": 4, "hp": 90, "dmg": 14, "xp": 70, "money": 15, "color": "59596b",
			"pos": [p.x, p.y, p.z], "quest": "wolf_hunt", "drops": {"beast_hide": 0.8, "wolf_pelt": 0.7, "spirit_shard": 0.35}, "pack": "wolf"})
	_spawn_grove()
	# Cliff Bats flit along the tower's foot, between the wolves and the gate.
	for i in 4:
		var p := TOWER_POS + Vector3(-30 + 20 * i, 1, _rng.randf_range(10, 14))
		_spawn_mob({"name": "Cliff Bat", "level": 3, "hp": 55, "dmg": 9, "xp": 50, "money": 10, "color": "4a3a52",
			"size": [0.8, 0.6, 0.8], "speed": 4.6, "aggro": 10, "drops": {"beast_hide": 0.3, "spirit_shard": 0.15},
			"model": {"pack": "creatures", "name": "Bat", "lift": 1.3, "fit": 1.4}, "pos": [p.x, p.y, p.z]})
	# Labyrinth terraces: kobold scouts, and a sergeant guarding the way to the summit.
	for lvl in LAB_LEVELS.size():
		var base: Vector3 = LAB_LEVELS[lvl]
		for i in 3:
			var a := TAU * i / 3.0 + lvl
			# Kobold Scouts patrol in threes and answer each other.
			var kp := base + Vector3(cos(a) * 5, 1, sin(a) * 5)
			_spawn_mob({"name": "Kobold Scout", "level": 5 + lvl, "hp": 110 + 30 * lvl, "dmg": 12 + 3 * lvl, "xp": 80 + 20 * lvl, "money": 20,
				"color": "6b7a3a", "size": [0.9, 1.5, 0.9], "pos": [kp.x, kp.y, kp.z], "pack": "kobold",
				"drops": {"iron_ore": 0.6, "spirit_shard": 0.2, "terrace_key": 0.12}})
		# Tunnel Rats scurry round the terrace rim (quick, weak).
		for i in 2:
			var a := TAU * i / 2.0 + lvl + 1.0
			_spawn_mob({"name": "Tunnel Rat", "level": 4 + lvl, "hp": 60 + 15 * lvl, "dmg": 8 + 2 * lvl, "xp": 45 + 10 * lvl, "money": 8,
				"color": "6e6258", "size": [0.6, 0.5, 1.0], "speed": 4.2, "aggro": 7, "drops": {"beast_hide": 0.3},
				"model": {"pack": "creatures", "name": "Rat", "fit": 1.3}, "pos": [base.x + cos(a) * 8, base.y + 1, base.z + sin(a) * 8]})
	_spawn_mob({"name": "Kobold Sergeant", "level": 7, "hp": 260, "dmg": 16, "xp": 220, "money": 80, "color": "8a5a2b",
		"size": [1.3, 1.4, 1.5], "speed": 3.4, "aggro": 12, "pack": "kobold", "armor": 0.7, "drops": {"iron_ore": 1.0, "spirit_shard": 0.6, "terrace_key": 1.0}, "la": SERGEANT_LA,
		"pos": [LAB_LEVELS[1].x, LAB_LEVELS[1].y + 1, LAB_LEVELS[1].z - 4]})


## The Snaptrap Grove, in the woods north-east of town: carnivorous vines
## rooted among the trees (slow, a whip up close and an acid spit at range).
## Most are plain; two bear a swollen fruit that bursts when struck and
## draws every vine in the grove onto the striker; one is in bloom and drops
## the Snaptrap Bloom (Herbalist Hesper's errand).
const GROVE := Vector3(114, 0, -174)  # WorldArt.GROVE
const GROVE_SPOTS := [Vector3(0, 0, 0), Vector3(6, 0, 3), Vector3(-5, 0, 4), Vector3(4, 0, -6), Vector3(-6, 0, -4),
	Vector3(9, 0, -2), Vector3(-2, 0, 8), Vector3(1, 0, -10)]


func _spawn_grove() -> void:
	for i in GROVE_SPOTS.size():
		var p: Vector3 = GROVE + GROVE_SPOTS[i] + Vector3(0, 1, 0)
		var d := {"name": "Snaptrap Vine", "level": 2, "hp": 48, "dmg": 7, "xp": 34, "money": 6, "color": "5f8a3a",
			"size": [1.0, 1.5, 1.0], "speed": 1.1, "aggro": 8, "ranged": 6.0, "pack": "vine",
			"drops": {"wild_herb": 0.5, "spirit_shard": 0.1}, "pos": [p.x, p.y, p.z]}
		if i == 2 or i == 5:
			d["name"] = "Fruiting Snaptrap"
			d["lure"] = true
			d["color"] = "7a8a3a"
		elif i == 7:
			d["name"] = "Blossoming Snaptrap"
			d["color"] = "c26a8a"
			d["hp"] = 60
			d["xp"] = 60
			d["drops"] = {"snaptrap_bloom": 1.0, "wild_herb": 1.0}
			d["respawn"] = 240.0  # rarely in flower: four minutes to bloom again
		_spawn_mob(d)


func _add_mob(n: String, lvl: int, hp: float, dmg: float, xp: int, money: int, c: String, pos: Vector3, quest: String, drops: Dictionary, size: Array = []) -> void:
	var d := {"name": n, "level": lvl, "hp": hp, "dmg": dmg, "xp": xp, "money": money, "color": c,
		"pos": [pos.x, pos.y, pos.z], "quest": quest, "drops": drops}
	if size.size() == 3:
		d["size"] = size
	_spawn_mob(d)


# =========================================================== Floor 2 =====
# "Mirewood": the Spire's second floor. Layout lives in Floor2Art; this
# section wires gameplay onto it (NPCs, quests, mobs, the second Labyrinth).

func _build_floor2() -> void:
	FLOOR_RADIUS = 90.0  # Mirewood is frozen at the prototype size (and flat).
	WorldArt.terrain_on = false
	TOWER_POS = Floor2Art.TOWER
	ARENA_POS = TOWER_POS + Vector3(0, 222, 0)
	LAB_LEVELS = [TOWER_POS + Vector3(-30, 90, 0)]
	GATE_LEVEL = 10
	_rune = Floor2Art.RUNE
	_terrace_runes = [Color("7fd9c0")]
	_gate_tint = Color("1e3838")
	_gate_glow = Color("3fc9a0")
	_build_environment()
	Floor2Art.tune_environment(self)
	# Walkable floor: same flat disc collider as Floor 1 under the Mirewood terrain.
	var body := StaticBody3D.new()
	body.name = "Floor"
	var shape := CylinderShape3D.new()
	shape.radius = FLOOR_RADIUS
	shape.height = 2.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = -1
	body.add_child(cs)
	add_child(body)
	Floor2Art.build_terrain(self, _art_rng, FLOOR_RADIUS)
	Floor2Art.build_waygate(self)
	await LoadingScreen.step("Settling Thornwick", 0.3)
	var village := Floor2Art.build_village(self)
	await LoadingScreen.step("Filling the Mere", 0.45)
	Floor2Art.build_lake(self, _art_rng)
	Floor2Art.build_barrow(self, _art_rng)
	await LoadingScreen.step("Carving the Labyrinth", 0.6)
	_build_tower()
	_build_arena()
	_build_labyrinth()
	_spawn_ore_veins(6)
	_spawn_npcs_floor2(village)
	_build_life_floor2(village)
	await _dress_floor2()
	if Net.is_authority():
		_spawn_mobs_floor2()


func _dress_floor2() -> void:
	var keep := [[Vector3(Floor2Art.PLAZA.x, 0, Floor2Art.PLAZA.y), 11.0], [Floor2Art.VILLAGE, 17.0], [Floor2Art.LAKE, Floor2Art.LAKE_RADIUS + 4.0],
		[Floor2Art.BARROW, Floor2Art.BARROW_RADIUS + 2.0], [TOWER_POS + Vector3(0, 0, 14), 8.0], [GameState.spawn_point(), 4.0]]
	for n in get_tree().get_nodes_in_group("npcs"):
		keep.append([n.position, 3.0])
	for v in _vein_positions:
		keep.append([v, 3.0])
	for lvl in LAB_LEVELS:
		keep.append([lvl, LAB_RADIUS + 2])
	keep.append_array(_life_keep)
	await LoadingScreen.step("Waking the Mirewood", 0.85)
	Floor2Art.build_vegetation(self, _art_rng, FLOOR_RADIUS, keep)
	Floor2Art.build_ambience(self)
	WorldProps.flush(self)


func _spawn_npcs_floor2(village: Dictionary) -> void:
	var c: Vector3 = Floor2Art.VILLAGE
	_add_npc("Huntmaster Sable", c + Vector3(3.2, 0, 3.6), {
		"hair_color": "3b2a1e", "outfit_color": "4a5a2e", "hair_style": 4, "eye_color": "8fb34a", "height": 1.05},
		"stag_hunt", 6, 900, 500, {
			"offer": "Thornwick lives off the woods, and the woods have turned. Thornback stags gore anyone on the east tracks. Bring down 6 and the village eats this winter.",
			"in_progress": "The stags run the eastern woods, past the Mere. They charge: step aside, then strike.",
			"turn_in": "Six thornbacks. You hunt like one of us. Take this, and take their horns to Orla.",
			"done": "Reach level %d and the Labyrinth gate will answer you. The Drowned Knight waits at the top." % GATE_LEVEL,
		})
	var anvil: Vector3 = village.get("smith", c)
	var orla := NPC.new()
	orla.npc_name = "Smith Orla"
	orla.appearance = {"hair_color": "c84a2a", "outfit_color": "3a3a3a", "hair_style": 2, "eye_color": "5a7a9a", "height": 1.0}
	orla.position = anvil + Vector3(-1.6, 0, 1.4)
	orla.rotation.y = PI * 0.6
	_set_talk(orla, _orla_talk)
	add_child(orla)
	var keeper := NPC.new()
	keeper.npc_name = "Keeper Ilsa"
	keeper.appearance = {"hair_color": "e8e8f0", "outfit_color": "2e6a62", "hair_style": 3, "eye_color": "5ee0b0", "height": 0.97}
	keeper.position = Floor2Art.ISLE + Vector3(1.2, 0, 3.4)
	keeper.rotation.y = PI * 0.85
	_set_talk(keeper, _keeper_talk)
	add_child(keeper)
	var bran := NPC.new()
	bran.npc_name = "Waykeeper Bran"
	bran.appearance = {"hair_color": "6b5a4a", "outfit_color": "5a4a7a", "hair_style": 1, "eye_color": "d9a441"}
	bran.position = Vector3(Floor2Art.PLAZA.x - 3.5, 0, Floor2Art.PLAZA.y + 2.5)
	bran.rotation.y = -PI * 0.3
	_set_talk(bran, func(gs):
		gs.heal_full()
		if gs.floors_cleared >= 2:
			return "Mirelord is down? Then the Spire has a third floor to show us, once someone carves the way."
		return "Welcome to Mirewood, climber. Thornwick is west along the track; the Mere and its shrine lie east. Keep out of the Barrow after dark unless you want wisps for company.\n(You feel rested.)")
	add_child(bran)


func _orla_talk(gs = GameState) -> String:
	if gs == GameState:
		_open_craft("Orla's anvil")
	if gs.recipe_unlocked("shrine_rite"):
		return "Ilsa taught you the rite? Then I can temper plate in the Mere's water. Bring hides, ore and essence."
	return "Stag horn takes an edge like nothing else; bring me some with ore and I'll forge a Mirewood Blade. Plate work I only do for those the shrine has blessed."


## Shrine quest: gather 5 Wisp Essence from the Barrow; the keeper teaches the
## Drowned Plate recipe (Crafting "unlock": "shrine_rite").
func _keeper_talk(gs = GameState) -> String:
	var need := 5
	if gs.quest_done("shrine_rite"):
		return "The water remembers you. Orla can forge the Drowned Plate for you now."
	if not gs.quests.has("shrine_rite"):
		gs.start_quest("shrine_rite", need)
		return "The wisps in the Sunken Barrow are what is left of the drowned. Bring me %d of their essence and I will teach you the rite the old smiths used to temper plate in still water." % need
	var have: int = gs.materials.get("wisp_essence", 0)
	gs.quests["shrine_rite"]["progress"] = min(have, need)
	if gs == GameState:
		GameState.quest_changed.emit()
	if have >= need:
		gs.spend_materials({"wisp_essence": need})
		gs.complete_quest("shrine_rite")
		gs.unlock_recipe("shrine_rite")
		gs.add_xp(700)
		gs.add_money(300)
		return "Rest, drowned ones. Listen: steel quenched in the Mere forgets its weight. Tell Orla you know the rite.\n(+700 XP, +300 Col, recipe learned: Drowned Plate)"
	return "You carry %d of the %d essence. The wisps gather at the Barrow, north-west past Thornwick; they strike from range, so close in fast." % [have, need]


func _spawn_mobs_floor2() -> void:
	# Mire Toads round the lake shore (slow, tanky), clear of the boardwalk.
	var ends := Floor2Art.boardwalk_ends()
	var placed := 0
	var guard := 0
	while placed < 9 and guard < 200:
		guard += 1
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(Floor2Art.LAKE_RADIUS + 3.0, Floor2Art.LAKE_RADIUS + 9.0)
		var p := Floor2Art.LAKE + Vector3(cos(a) * r, 1, sin(a) * r)
		if p.distance_to(ends[0]) < 7.0 or p.length() > FLOOR_RADIUS - 6:
			continue
		_spawn_mob({"name": "Mire Toad", "level": 8, "hp": 230, "dmg": 14, "xp": 120, "money": 25, "color": "5f7a3a",
			"size": [1.3, 0.9, 1.4], "speed": 2.4, "aggro": 8, "drops": {"beast_hide": 0.7, "spirit_shard": 0.15},
			"pos": [p.x, p.y, p.z]})
		placed += 1
	# Thornback Stags in the eastern and southern woods (fast chargers).
	placed = 0
	guard = 0
	while placed < 8 and guard < 300:
		guard += 1
		var a := _rng.randf_range(-0.9, 1.6)
		var r := _rng.randf_range(46, 80)
		var p := Vector3(cos(a) * r, 1, sin(a) * r)
		if Floor2Art.ground_kind(Vector2(p.x, p.z)) != WorldArt.Ground.GRASS or p.distance_to(Floor2Art.LAKE) < Floor2Art.LAKE_RADIUS + 8.0:
			continue
		_add_mob("Thornback Stag", 10, 190, 20, 170, 35, "7a4a2a", p, "stag_hunt", {"stag_horn": 0.8, "beast_hide": 0.5})
		placed += 1
	# Marsh Wisps haunt the Sunken Barrow (ranged bolts).
	for i in 7:
		var a := TAU * i / 7.0 + 0.4
		var r := 4.0 + 3.0 * (i % 3)
		var p := Floor2Art.BARROW + Vector3(cos(a) * r, 1, sin(a) * r)
		_spawn_mob({"name": "Marsh Wisp", "level": 11, "hp": 130, "dmg": 13, "xp": 200, "money": 40, "color": "7fe8d0",
			"size": [0.7, 0.9, 0.7], "speed": 3.2, "aggro": 16, "ranged": 11.0,
			"drops": {"wisp_essence": 0.8, "spirit_shard": 0.3}, "pos": [p.x, p.y, p.z]})
	# The terrace: toads and barrow wisps, and the Thornback Alpha at the far pad.
	var base: Vector3 = LAB_LEVELS[0]
	for i in 2:
		var a := TAU * i / 2.0 + 0.7
		var p := base + Vector3(cos(a) * 6, 1, sin(a) * 6)
		_spawn_mob({"name": "Mire Toad", "level": 11, "hp": 320, "dmg": 18, "xp": 190, "money": 40, "color": "4f6a3a",
			"size": [1.4, 1.0, 1.5], "speed": 2.6, "aggro": 12, "drops": {"beast_hide": 0.8, "spirit_shard": 0.3}, "pos": [p.x, p.y, p.z]})
		var q := base + Vector3(cos(a + 1.5) * 7, 1, sin(a + 1.5) * 7)
		_spawn_mob({"name": "Barrow Wisp", "level": 12, "hp": 160, "dmg": 15, "xp": 240, "money": 50, "color": "9fe0ff",
			"size": [0.7, 0.9, 0.7], "speed": 3.4, "aggro": 14, "ranged": 11.0, "drops": {"wisp_essence": 0.9, "spirit_shard": 0.4}, "pos": [q.x, q.y, q.z]})
	_spawn_mob({"name": "Thornback Alpha", "level": 12, "hp": 480, "dmg": 24, "xp": 420, "money": 120, "color": "5a2e1e",
		"size": [1.2, 1.9, 2.3], "speed": 5.6, "aggro": 12, "quest": "stag_hunt", "drops": {"stag_horn": 1.0, "spirit_shard": 0.6},
		"pos": [base.x, base.y + 1, base.z - 4]})
