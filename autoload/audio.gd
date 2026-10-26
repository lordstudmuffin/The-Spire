extends Node
## Game audio: pooled SFX (2D for UI, 3D for the world), crossfaded music,
## layered ambient loops, and the Master/Music/SFX/Ambient bus volumes from
## Settings. Events are names from assets/audio/MANIFEST.md; each maps to one
## or more CC0 Kenney files and a random variant is picked per play.
##
## Streams load lazily on first use and stay cached. Headless / dedicated
## server runs do nothing at all so tests stay silent and fast.
##
## Music and ambience are driven from here by polling the live world (player
## position, boss, time of day) so world.gd needs no audio code.

const DIR := "res://assets/audio/"

const EVENTS := {
	# Combat
	"swing": ["rpg_audio/knifeSlice.ogg", "rpg_audio/knifeSlice2.ogg", "rpg_audio/drawKnife1.ogg"],
	"skill": ["impact_sounds/impactMetal_light_000.ogg", "impact_sounds/impactMetal_light_001.ogg", "impact_sounds/impactMetal_light_002.ogg"],
	"hit_flesh": ["impact_sounds/impactPunch_medium_000.ogg", "impact_sounds/impactPunch_medium_001.ogg", "impact_sounds/impactPunch_heavy_000.ogg"],
	"hit_metal": ["impact_sounds/impactMetal_medium_000.ogg", "impact_sounds/impactMetal_heavy_000.ogg"],
	"hit_heavy": ["impact_sounds/impactBell_heavy_000.ogg", "impact_sounds/impactPlate_heavy_000.ogg"],
	"crit": ["impact_sounds/impactMetal_heavy_002.ogg", "impact_sounds/impactGlass_heavy_000.ogg"],
	"slam": ["impact_sounds/impactPlate_heavy_001.ogg", "impact_sounds/impactPlate_heavy_002.ogg"],
	"grunt": ["impact_sounds/impactSoft_heavy_000.ogg", "impact_sounds/impactSoft_heavy_001.ogg", "impact_sounds/impactSoft_heavy_002.ogg"],
	"death": ["crystal/shatter.ogg"],
	"boss_death": ["crystal/shatter_boss.ogg"],
	"player_hit": ["impact_sounds/impactSoft_medium_001.ogg", "impact_sounds/impactSoft_medium_002.ogg"],
	# Movement
	"step_grass": ["impact_sounds/footstep_grass_000.ogg", "impact_sounds/footstep_grass_001.ogg", "impact_sounds/footstep_grass_002.ogg", "impact_sounds/footstep_grass_003.ogg", "impact_sounds/footstep_grass_004.ogg"],
	"step_stone": ["impact_sounds/footstep_concrete_000.ogg", "impact_sounds/footstep_concrete_001.ogg", "impact_sounds/footstep_concrete_002.ogg", "impact_sounds/footstep_concrete_003.ogg", "impact_sounds/footstep_concrete_004.ogg"],
	"step_wood": ["impact_sounds/footstep_wood_000.ogg", "impact_sounds/footstep_wood_001.ogg", "impact_sounds/footstep_wood_002.ogg", "impact_sounds/footstep_wood_003.ogg", "impact_sounds/footstep_wood_004.ogg"],
	"jump": ["rpg_audio/cloth1.ogg"],
	"land": ["impact_sounds/impactSoft_medium_000.ogg"],
	"dash": ["rpg_audio/cloth3.ogg"],
	# Progression / crafting / loot
	"level_up": ["crystal/level_up.ogg"],
	"quest_complete": ["crystal/quest_complete.ogg"],
	"quest_accept": ["crystal/quest_accept.ogg"],
	"class_unlock": ["music_jingles/jingles_PIZZI00.ogg"],
	"craft_success": ["music_jingles/jingles_PIZZI10.ogg"],
	"craft_pot": ["rpg_audio/metalPot2.ogg"],
	"anvil": ["rpg_audio/metalClick.ogg"],
	"craft_fail": ["interface_sounds/error_004.ogg"],
	"coins": ["rpg_audio/handleCoins.ogg", "rpg_audio/handleCoins2.ogg"],
	"pickup": ["crystal/item_get.ogg"],
	"equip": ["rpg_audio/clothBelt.ogg"],
	"drop": ["rpg_audio/dropLeather.ogg"],
	"mine": ["rpg_audio/chop.ogg", "impact_sounds/impactMining_000.ogg", "impact_sounds/impactMining_001.ogg"],
	# Life layer: the packs have no water sound, so a splash is a soft leather
	# drop pitched down; casting is a cloth whip, eating a leather rustle.
	"splash": ["rpg_audio/dropLeather.ogg", "impact_sounds/impactSoft_heavy_000.ogg"],
	"cast": ["rpg_audio/cloth4.ogg"],
	"eat": ["rpg_audio/handleSmallLeather.ogg", "rpg_audio/handleSmallLeather2.ogg"],
	"cook": ["rpg_audio/metalPot1.ogg", "rpg_audio/metalPot3.ogg"],
	"sleep": ["rpg_audio/cloth2.ogg"],
	"book": ["rpg_audio/bookFlip1.ogg", "rpg_audio/bookFlip2.ogg", "rpg_audio/bookFlip3.ogg"],
	"book_open": ["rpg_audio/bookOpen.ogg"],
	"book_close": ["rpg_audio/bookClose.ogg"],
	"door_open": ["rpg_audio/doorOpen_1.ogg"],
	"door_close": ["rpg_audio/doorClose_1.ogg"],
	"teleport": ["interface_sounds/maximize_004.ogg"],
	# UI
	"ui_click": ["crystal/menu_select.ogg"],
	"ui_hover": ["crystal/menu_select.ogg"],
	"ui_open": ["crystal/menu_confirm.ogg"],
	"ui_close": ["crystal/menu_back.ogg"],
	"ui_back": ["crystal/menu_back.ogg"],
	"ui_confirm": ["crystal/menu_confirm.ogg"],
	"ui_error": ["crystal/menu_error.ogg"],
	"ui_toggle": ["ui_audio/switch1.ogg"],
	"ui_tick": ["crystal/menu_select.ogg"],
	"chat": ["crystal/notify.ogg"],
	# Crystal interface set (synthesized by tools/sfx/gen_crystal.py; regenerate
	# or tweak there). Ring menu, notifications, loot, death and realm events.
	"menu_open": ["crystal/menu_open.ogg"],
	"menu_close": ["crystal/menu_close.ogg"],
	"menu_select": ["crystal/menu_select.ogg"],
	"panel_slide": ["crystal/panel_slide.ogg"],
	"notify": ["crystal/notify.ogg"],
	"party_invite": ["crystal/party_invite.ogg"],
	"item_rare": ["crystal/item_rare.ogg"],
	"hit_digital": ["crystal/hit_digital.ogg"],
	"crit_digital": ["crystal/crit_digital.ogg"],
	"shatter": ["crystal/shatter.ogg"],
	"shatter_boss": ["crystal/shatter_boss.ogg"],
	"player_death": ["crystal/player_death.ogg"],
	"respawn": ["crystal/respawn.ogg"],
	"heartbeat": ["crystal/heartbeat.ogg"],
	"realm_announce": ["crystal/realm_announce.ogg"],
	"skill_charge": ["crystal/skill_charge.ogg"],
	"parry": ["crystal/parry.ogg"],
	"block": ["crystal/block.ogg"],
	"guard_break": ["crystal/guard_break.ogg"],
	"stagger": ["crystal/stagger.ogg"],
	# Combat feel pass: the perfect-parry ring (parry + digital crit layer),
	# a dull whiffed parry, the dash-through evade, the wind-up tells (bright
	# tick = parryable, low bell = unparryable) and the combo finisher's whoosh.
	"parry_perfect": ["crystal/parry.ogg"],
	"parry_whiff": ["impact_sounds/impactWood_light_001.ogg", "impact_sounds/impactWood_light_003.ogg"],
	"dodge": ["rpg_audio/cloth4.ogg"],
	"windup_tell": ["impact_sounds/impactGlass_light_002.ogg", "impact_sounds/impactGlass_light_003.ogg"],
	"windup_danger": ["impact_sounds/impactBell_heavy_002.ogg"],
	"swing_heavy": ["rpg_audio/drawKnife2.ogg", "rpg_audio/drawKnife3.ogg"],
	# Floor Guardian (scripts/boss_brain.gd): the roar on engage / enrage, the
	# charge rumble, and the crack of an HP bar breaking.
	"boss_roar": ["crystal/boss_roar.ogg"],
	"boss_charge": ["crystal/boss_charge.ogg"],
	"boss_bar_break": ["crystal/shatter.ogg"],
	# Stingers (gen_crystal.py): the Guardian wakes, his last bar, the floor
	# cleared fanfare, a Last Attack bonus. Played with stinger(), which
	# ducks the music under them.
	"boss_sting": ["crystal/boss_sting.ogg"],
	"boss_phase_sting": ["crystal/boss_phase_sting.ogg"],
	"floor_victory": ["crystal/floor_victory.ogg"],
	"last_attack": ["crystal/last_attack.ogg"],
}

## Extra events that always play with an event (same position): the crisp
## "digital" tick on every hit, the low thud under a boss shatter.
const LAYERS := {
	"hit_flesh": ["hit_digital"], "hit_metal": ["hit_digital"], "hit_heavy": ["hit_digital"],
	"crit": ["crit_digital"], "boss_death": ["slam"], "boss_bar_break": ["slam", "crit_digital"],
	"parry_perfect": ["crit_digital"],
}

## Per-event minimum gap in seconds (bursts of inventory_changed etc.).
const MIN_GAP := {"boss_roar": 0.5, "heartbeat": 0.7, "hit_digital": 0.03, "menu_select": 0.04, "notify": 0.2, "pickup": 0.3, "coins": 0.25, "ui_hover": 0.05, "ui_click": 0.05, "chat": 0.2, "hit_flesh": 0.03, "hit_metal": 0.03, "crit": 0.08, "windup_tell": 0.12, "windup_danger": 0.3}
## Per-event volume offsets in dB.
const GAIN := {"ui_hover": -16.0, "ui_click": -8.0, "ui_tick": -10.0, "menu_select": -8.0, "hit_digital": -9.0, "crit_digital": -5.0,
	"pickup": -6.0, "panel_slide": -6.0, "heartbeat": -2.0, "shatter": -2.0, "step_grass": -8.0, "step_stone": -10.0, "step_wood": -8.0,
	"swing": -4.0, "crit": -3.0, "level_up": -2.0, "quest_complete": -2.0, "grunt": -3.0, "death": -2.0, "anvil": -4.0, "chat": -8.0,
	"windup_tell": -7.0, "windup_danger": -4.0, "parry_whiff": -6.0, "dodge": -4.0, "swing_heavy": -3.0}

const MUSIC := {
	"town": ["music/town_a_new_town.ogg", "music/town_rpg_town.ogg"],
	"field": ["music/field_rpg_overworld.ogg"],
	"boss": ["music/boss_battle_9_metal_loop.ogg"],
}
const AMBIENT := {
	"wind": "ambient/wind_loop.ogg",
	"meadow": "ambient/meadow_birds_loop.ogg",
	"forest": "ambient/forest_birds_wind_loop.ogg",
	"river": "ambient/river_loop.ogg",
	"campfire": "ambient/campfire_loop.ogg",
}
const AMBIENT_GAIN := {"wind": -10.0, "meadow": -8.0, "forest": -8.0, "river": -8.0, "campfire": -6.0}
const MUSIC_GAIN := -8.0
const MUSIC_FADE := 1.6
const AMBIENT_FADE := 1.8
const POOL_2D := 12
const POOL_3D := 16

## Auto music/ambience zones (match world.gd constants; world.gd is not edited).
const TOWN_CENTER := Vector3(0, 0, 15)
const TOWN_RADIUS := 38.0
const HOLLOWBROOK := Vector3(-48, 0, 38)
const VILLAGE_RADIUS := 18.0
const TALVEN := Vector3(-14, 0, -44)
const CAMP_RADIUS := 16.0

var enabled := true
var current_music := ""
var _cache := {}                 # path -> AudioStream
var _last_play := {}             # event -> msec
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _music: Array[AudioStreamPlayer] = []
var _music_idx := 0
var _music_tween: Tween
var _ambient := {}               # name -> AudioStreamPlayer
var _ambient_tweens := {}        # name -> Tween
var _poll := 0.0
var _last_money := -1
var _last_haul := 0
var _last_inv_size := 0
var _quest_snapshot := {}
var _bus := {}                   # name -> index


static func is_silent() -> bool:
	return "--server" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless"


func _ready() -> void:
	enabled = not is_silent()
	if not enabled:
		set_process(false)
		return
	_setup_buses()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 40.0
		p.unit_size = 3.0
		p.attenuation_filter_cutoff_hz = 8000.0
		add_child(p)
		_pool3d.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	_apply_volumes()
	Settings.changed.connect(_apply_volumes)
	# Progression hooks: these are global, so one place serves every scene.
	_last_money = GameState.money
	GameState.leveled_up.connect(func(_l): play("level_up"))
	GameState.class_unlocked.connect(func(_c): play("class_unlock"))
	GameState.money_changed.connect(_on_money)
	GameState.quest_changed.connect(_on_quest)
	_last_haul = _haul()
	_last_inv_size = GameState.inventory.size()
	GameState.inventory_changed.connect(_on_inventory)


func _setup_buses() -> void:
	for n in ["Master", "Music", "SFX", "Ambient"]:
		var idx := AudioServer.get_bus_index(n)
		if idx < 0:
			idx = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, n)
			AudioServer.set_bus_send(idx, "Master")
		_bus[n] = idx


func _apply_volumes() -> void:
	if not enabled:
		return
	var music := clampf(float(Settings.data.get("music_volume", 0.8)), 0.0, 1.0)
	var sfx := clampf(float(Settings.data.get("sfx_volume", 1.0)), 0.0, 1.0)
	_set_bus("Music", music)
	_set_bus("SFX", sfx)
	_set_bus("Ambient", sfx)


func _set_bus(n: String, lin: float) -> void:
	var idx := AudioServer.get_bus_index(n)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(lin, 0.0001)))
	AudioServer.set_bus_mute(idx, lin <= 0.0001)


# --- Streams -------------------------------------------------------------

## Loads and caches a stream; ambient/music loops get loop = true at load.
func stream(rel: String) -> AudioStream:
	if _cache.has(rel):
		return _cache[rel]
	var path := DIR + rel
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	if s == null:
		push_warning("Audio: missing stream " + path)
	elif rel.begins_with("ambient/") or rel.begins_with("music/"):
		if s is AudioStreamOggVorbis or s is AudioStreamWAV or s is AudioStreamMP3:
			s.set("loop", true)
			if s is AudioStreamWAV:
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_cache[rel] = s
	return s


# --- SFX -----------------------------------------------------------------

## Plays a random variant of `event`. pos == null plays flat (UI / own body);
## a Vector3 plays positional on the SFX bus. Returns the player used.
func play(event: String, pos = null, pitch_var := 0.08, volume_db := 0.0, pitch_base := 1.0) -> Node:
	if not enabled or not EVENTS.has(event):
		return null
	var now := Time.get_ticks_msec()
	var gap := float(MIN_GAP.get(event, 0.02)) * 1000.0
	if _last_play.has(event) and now - _last_play[event] < gap:
		return null
	_last_play[event] = now
	var variants: Array = EVENTS[event]
	var s := stream(variants[randi() % variants.size()])
	if s == null:
		return null
	var pitch := pitch_base * (randf_range(1.0 - pitch_var, 1.0 + pitch_var) if pitch_var > 0.0 else 1.0)
	var vol := volume_db + float(GAIN.get(event, 0.0))
	if pos is Vector3:
		var p3 := _free_3d()
		p3.global_position = pos
		p3.stream = s
		p3.pitch_scale = pitch
		p3.volume_db = vol
		p3.play()
		_play_layers(event, pos, volume_db)
		return p3
	var p := _free_2d()
	p.stream = s
	p.pitch_scale = pitch
	p.volume_db = vol
	p.play()
	_play_layers(event, pos, volume_db)
	return p


func _play_layers(event: String, pos, volume_db: float) -> void:
	for extra in LAYERS.get(event, []):
		play(extra, pos, 0.05, volume_db)


func _free_2d() -> AudioStreamPlayer:
	for p in _pool2d:
		if not p.playing:
			return p
	var p: AudioStreamPlayer = _pool2d[randi() % _pool2d.size()]
	p.stop()
	return p


func _free_3d() -> AudioStreamPlayer3D:
	for p in _pool3d:
		if not p.playing:
			return p
	var p: AudioStreamPlayer3D = _pool3d[randi() % _pool3d.size()]
	p.stop()
	return p


## Footstep on "grass", "stone" or "wood". Any other surface falls back to grass.
func footstep(surface: String, pos = null) -> void:
	var ev := "step_" + surface
	if not EVENTS.has(ev):
		ev = "step_grass"
	play(ev, pos, 0.12)


## Surface name for a world XZ position, via WorldArt.ground_kind when it exists.
var _ground_fn: Callable
var _ground_names := {}
var _ground_checked := false


func surface_at(world_pos: Vector3) -> String:
	if world_pos.y > 40.0:
		return "stone"  # Labyrinth terraces and the summit are stone platforms.
	if not _ground_checked:
		_ground_checked = true
		if ResourceLoader.exists("res://scripts/world_art.gd"):
			var ws = load("res://scripts/world_art.gd")
			if ws is Script:
				for m in ws.get_script_method_list():
					if m["name"] == "ground_kind":
						_ground_fn = Callable(ws, "ground_kind")
				var consts: Dictionary = ws.get_script_constant_map()
				if consts.has("Ground") and consts["Ground"] is Dictionary:
					for k in consts["Ground"]:
						_ground_names[consts["Ground"][k]] = str(k)
	if not _ground_fn.is_valid():
		return "grass"
	var kind = _ground_fn.call(Vector2(world_pos.x, world_pos.z))
	match _ground_names.get(kind, "GRASS"):
		"COBBLE", "RIM", "TOWER", "STONE":
			return "stone"
		"WOOD", "PLANK":
			return "wood"
		_:
			return "grass"


# --- Music ---------------------------------------------------------------

## Crossfades to a music track ("town", "field", "boss"); "" fades out.
func music(track: String, fade := MUSIC_FADE) -> void:
	if not enabled or track == current_music:
		return
	current_music = track
	var old: AudioStreamPlayer = _music[_music_idx]
	_music_idx = 1 - _music_idx
	var new: AudioStreamPlayer = _music[_music_idx]
	if _music_tween:
		_music_tween.kill()
		_music_tween = null
	var s: AudioStream = null
	if track != "" and MUSIC.has(track):
		var variants: Array = MUSIC[track]
		s = stream(variants[randi() % variants.size()])
	if not old.playing and s == null:
		return  # Nothing to fade: a Tween with no Tweeners errors when it steps.
	# Both fades run in parallel (a real crossfade); old.stop is chained last so
	# it fires after the fade-out instead of pushing the fade-in behind it.
	_music_tween = create_tween().set_parallel(true)
	if old.playing:
		_music_tween.tween_property(old, "volume_db", -60.0, fade).set_trans(Tween.TRANS_SINE)
	if s != null:
		new.stream = s
		new.volume_db = -60.0
		new.play()
		_music_tween.tween_property(new, "volume_db", MUSIC_GAIN, fade).set_trans(Tween.TRANS_SINE)
	if old.playing:
		_music_tween.chain().tween_callback(old.stop)


## A musical stinger over the soundtrack: the music dips for `secs`, then
## comes back. 2D (everyone near the fight hears it the same).
func stinger(event: String, secs := 2.5, duck_db := -14.0) -> void:
	if play(event, null, 0.0, 0.0) == null:
		return
	var m: AudioStreamPlayer = _music[_music_idx]
	if not m.playing:
		return
	var tw := create_tween()
	tw.tween_property(m, "volume_db", MUSIC_GAIN + duck_db, 0.25)
	tw.tween_interval(maxf(secs - 0.25, 0.0))
	tw.tween_property(m, "volume_db", MUSIC_GAIN, 1.2).set_trans(Tween.TRANS_SINE)


# --- Ambient -------------------------------------------------------------

## Fades an ambient loop in (on) or out (off). Several can layer.
func ambient(layer: String, on := true, fade := AMBIENT_FADE) -> void:
	if not enabled or not AMBIENT.has(layer):
		return
	var p: AudioStreamPlayer = _ambient.get(layer)
	if p == null:
		if not on:
			return
		p = AudioStreamPlayer.new()
		p.bus = "Ambient"
		p.volume_db = -60.0
		add_child(p)
		_ambient[layer] = p
	var target := float(AMBIENT_GAIN.get(layer, -8.0)) if on else -60.0
	if _ambient_tweens.has(layer) and _ambient_tweens[layer]:
		_ambient_tweens[layer].kill()
	if on and not p.playing:
		var s := stream(AMBIENT[layer])
		if s == null:
			return
		p.stream = s
		p.volume_db = -60.0
		p.play()
	elif not on and not p.playing:
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", target, fade).set_trans(Tween.TRANS_SINE)
	if not on:
		tw.tween_callback(p.stop)
	_ambient_tweens[layer] = tw


## Makes exactly these loops audible (others fade out).
func set_ambient(names: Array) -> void:
	if not enabled:
		return
	for n in AMBIENT:
		ambient(n, n in names)


func stop_all(fade := 0.8) -> void:
	if not enabled:
		return
	music("", fade)
	set_ambient([])
	for p in _pool2d:
		p.stop()
	for p in _pool3d:
		p.stop()


# --- Progression hooks ----------------------------------------------------

func _on_money(m: int) -> void:
	if _last_money >= 0 and m > _last_money:
		play("coins")
	_last_money = m


## Items plus materials held; "pickup" only plays when this grows (not on
## spending materials at the forge, equipping or smithing XP).
func _haul() -> int:
	var n := GameState.inventory.size()
	for id in GameState.materials:
		n += int(GameState.materials[id])
	return n


func _on_inventory() -> void:
	var h := _haul()
	if h > _last_haul:
		# Epic rank (2) and above gets the long rare-drop chime.
		var inv: Array = GameState.inventory
		var rare := inv.size() > _last_inv_size and inv.size() > 0 and inv[-1] is Dictionary and int(inv[-1].get("rank", 0)) >= 2
		play("item_rare" if rare else "pickup")
	_last_haul = h
	_last_inv_size = GameState.inventory.size()


func _on_quest() -> void:
	for id in GameState.quests:
		var q: Dictionary = GameState.quests[id]
		var done := bool(q.get("done", false))
		if not _quest_snapshot.has(id):
			if not done:
				play("quest_accept")
		elif done and not _quest_snapshot[id]:
			play("quest_complete")
		_quest_snapshot[id] = done
	for id in _quest_snapshot.keys():
		if not GameState.quests.has(id):
			_quest_snapshot.erase(id)


# --- World polling: music and ambience follow the local player ----------

func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.5
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.is_inside_tree():
		if current_music != "":
			music("")
			set_ambient([])
		return
	var world: Node = player.get_parent()
	while world and not ("day_night" in world):
		world = world.get_parent()
	var pos := player.global_position
	var flat := Vector3(pos.x, 0, pos.z)
	# Music.
	var boss_alive := false
	if world and "_boss" in world:
		var b = world.get("_boss")
		boss_alive = b != null and is_instance_valid(b) and b.visible and pos.y > 150.0
	if boss_alive:
		music("boss")
	elif flat.distance_to(TOWN_CENTER) < TOWN_RADIUS or flat.distance_to(HOLLOWBROOK) < VILLAGE_RADIUS:
		music("town")
	else:
		music("field")
	# Ambience.
	var night := false
	var dn = world.get("day_night") if world else null
	if dn != null and dn.has_method("is_night"):
		night = dn.is_night()
	var layers: Array = []
	if pos.y > 40.0:
		layers = ["wind"]
	elif flat.distance_to(TALVEN) < CAMP_RADIUS:
		layers = ["wind", "campfire"]
	elif night:
		layers = ["wind", "forest"]
	else:
		layers = ["meadow"]
	set_ambient(layers)
