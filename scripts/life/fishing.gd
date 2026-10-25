class_name Fishing
extends Node
## Fishing: spots on the shore, a cast, a wait, a bite and the timing
## minigame (FishingWidget on the HUD). State machine owned by the world:
##   IDLE -> (E at a spot with a rod) CASTING -> WAITING (2-5 s) -> BITE
##   (widget shown, E inside the green zone lands the fish) -> IDLE.
## Walking away or pressing E too early/late loses the fish. Catches go
## through LifeData.land_fish (material + skill xp + quests). Online the
## server owns the catch: the cast is a request ("cast": rod, range and the
## fish roll with the server's fishing skill happen there), the bite waits
## for the server's fish, and landing is a second request ("land": the
## server checks the pending cast, the wait and the range, then books the
## fish on the record). Only the timing minigame itself stays on the client.

enum State { IDLE, CASTING, WAITING, BITE }

const CAST_RANGE := 3.2
const WALK_CANCEL := 1.6

var state: int = State.IDLE
var spots: Array = []  # {"pos", "kind", "water", "node"}
var current := -1
var current_fish := ""
var casts := 0
var catches := 0

var _world: Node3D
var _player: Node3D
var _hud: Node
var _timer := 0.0
var _cast_from := Vector3.ZERO
var _rod: Node3D
var _bobber: Node3D
var _bob_tw: Tween
var _rng := RandomNumberGenerator.new()
## Online: the fish the server rolled for the current cast ("" until it answers).
var _server_fish := ""
var _server_wait := 0.0


func setup(world: Node3D, player: Node3D, hud: Node) -> void:
	_world = world
	_player = player
	_hud = hud
	_rng.randomize()


## A fishing spot: a stake with a bucket and a fish on the shore, and a
## ripple ring out on the water where the bobber will land.
func add_spot(pos: Vector3, kind: String, water: Vector3) -> int:
	var n := Node3D.new()
	n.name = "FishingSpot_%s" % kind
	n.position = pos
	_world.add_child(n)
	n.add_to_group("fishing_spots")
	var toward := (water - pos) * Vector3(1, 0, 1)
	var face := atan2(toward.x, toward.z)
	if WorldProps.has("survival", "bucket"):
		AssetLib.prop(n, "survival", "bucket", Vector3(-0.7, 0, 0.1), face, WorldProps.SURVIVAL * 0.9, "none")
	else:
		WorldArt.cyl(n, 0.28, 0.24, 0.42, Vector3(-0.7, 0.21, 0.1), Color("8a8f9a"), 10)
	if WorldProps.has("survival", "fish"):
		AssetLib.prop(n, "survival", "fish", Vector3(0.35, 0.05, -0.3), face + 1.2, WorldProps.SURVIVAL * 0.8, "none")
	# Stake with the hint plank.
	WorldArt.cyl(n, 0.05, 0.07, 1.5, Vector3(0.4, 0.75, 0.25), WorldArt.WOOD, 6)
	WorldArt.box(n, Vector3(0.9, 0.26, 0.05), Vector3(0.4, 1.3, 0.25), WorldArt.WOOD_LIGHT, Vector3(0, face, 0.06))
	var ring := WorldArt.rune_ring(_world, water + Vector3(0, 0.1, 0), 0.9, Color(0.75, 0.95, 1.0), 0.1)
	ring.name = "Ripple_%s" % kind
	var tw := ring.create_tween().set_loops()
	tw.tween_property(ring, "scale", Vector3(1.6, 1, 1.6), 1.6).from(Vector3(0.6, 1, 0.6)).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(ring, "transparency", 0.9, 1.6).from(0.2)
	spots.append({"pos": pos, "kind": kind, "water": water, "node": n})
	return spots.size() - 1


func nearest_spot(from: Vector3, range := CAST_RANGE) -> int:
	var best := -1
	var best_d := range
	for i in spots.size():
		var d: float = from.distance_to(spots[i]["pos"])
		if d < best_d:
			best_d = d
			best = i
	return best


func spot_kind(i: int) -> String:
	return spots[i]["kind"] if i >= 0 and i < spots.size() else ""


func active() -> bool:
	return state != State.IDLE


## E at a spot. Returns false (with a HUD line) when there is no rod.
func start(i: int) -> bool:
	if state != State.IDLE or i < 0 or i >= spots.size():
		return false
	if not LifeData.has_rod():
		if _hud and _hud.has_method("show_dialogue"):
			_hud.show_dialogue("Fishing spot", "You need a rod. The fishers by the water lend one with their quest, Trader Pell in the plaza sells a Willow Rod, or forge one at Haldor's anvil.")
		return false
	current = i
	current_fish = ""
	_server_fish = ""
	_server_wait = 0.0
	casts += 1
	_cast_from = _player.global_position
	if Net.remote_client():
		Net.request_action("cast", {"spot": i})
	_show_rod(true)
	Audio.play("cast", _player.global_position)
	state = State.CASTING
	_timer = 0.6
	if _hud and _hud.has_method("toast"):
		_hud.toast("Cast at %s" % LifeData.SPOT_NAMES.get(spots[i]["kind"], "the water"), "Wait for the bite, then press E on the green", "Fishing", UITheme.CYAN)
	return true


## E while fishing. Returns true when the press was consumed.
func handle_interact() -> bool:
	match state:
		State.IDLE:
			return false
		State.CASTING, State.WAITING:
			_finish(false, "Reeled in too early.")
			return true
		State.BITE:
			var w := _widget()
			if w and w.in_zone():
				_land()
			else:
				_finish(false, "The %s slipped the hook." % LifeData.FISH[current_fish]["name"])
			return true
	return false


func cancel() -> void:
	if state != State.IDLE:
		_finish(false, "")


func _process(delta: float) -> void:
	if state == State.IDLE or _player == null:
		return
	if _player.global_position.distance_to(_cast_from) > WALK_CANCEL:
		_finish(false, "You walked off and lost the line.")
		return
	match state:
		State.CASTING:
			_timer -= delta
			if _timer <= 0.0:
				state = State.WAITING
				_timer = _rng.randf_range(2.0, 5.0)
				_drop_bobber()
		State.WAITING:
			_timer -= delta
			if _timer <= 0.0:
				if Net.remote_client() and _server_fish == "":
					# The server has not answered the cast yet: keep waiting a
					# little, then give up (lost packet, refused cast).
					_server_wait += delta
					if _server_wait > 8.0:
						_finish(false, "Nothing bit.")
					return
				_bite()
		State.BITE:
			var w := _widget()
			if w == null or w.expired():
				_finish(false, "It got away.")


## Rolls the fish now so the minigame can be as hard as it is rare.
func _bite() -> void:
	state = State.BITE
	current_fish = _server_fish if Net.remote_client() else LifeData.roll_fish(spots[current]["kind"], GameState.fishing_level, _rng)
	var diff := LifeData.difficulty(current_fish, GameState.fishing_level)
	var w := _widget()
	if w:
		w.start(diff, LifeData.FISH[current_fish]["name"])
	_splash(spots[current]["water"], 1.0)
	if _bobber:
		var tw := _bobber.create_tween()
		tw.tween_property(_bobber, "position:y", _bobber.position.y - 0.35, 0.12)
		tw.tween_property(_bobber, "position:y", _bobber.position.y, 0.25).set_trans(Tween.TRANS_BOUNCE)


func _land() -> void:
	var fish := current_fish
	var info: Dictionary = LifeData.FISH[fish]
	_splash(spots[current]["water"], 1.6)
	Audio.play("pickup", _player.global_position)
	if int(info["rarity"]) >= 2:
		Audio.play("craft_success")
	var w := _widget()
	if w:
		w.finish(true, "Caught a %s!" % info["name"])
	if Net.remote_client():
		# The server books the catch and answers with "land" (on_net).
		Net.request_action("land", {"spot": current})
		_finish(true, "")
		return
	var res := LifeData.land_fish(fish)
	catches += 1
	_toast_catch(fish, bool(res.get("skill_up", false)))
	_finish(true, "")


func _toast_catch(fish: String, skill_up: bool) -> void:
	var info: Dictionary = LifeData.FISH[fish]
	if _hud and _hud.has_method("toast"):
		var sub := "%s  ·  +%d fishing xp" % [LifeData.RARITY_NAMES[int(info["rarity"])], int(info["xp"])]
		if skill_up:
			sub += "  ·  Fishing Lv %d" % GameState.fishing_level
		_hud.toast(info["name"], sub, "Catch!", LifeData.rarity_color(fish))


## Online client: the server answered a cast or a landing.
func on_net(kind: String, res: Dictionary) -> void:
	if res.has("error"):
		if kind == "cast" and state != State.IDLE:
			_finish(false, str(res["error"]))
		elif _hud and _hud.has_method("toast"):
			_hud.toast(str(res["error"]), "", "Fishing", UITheme.MUTED)
		return
	if kind == "cast":
		var fish := str(res.get("fish", ""))
		if LifeData.FISH.has(fish) and state in [State.CASTING, State.WAITING]:
			_server_fish = fish
	elif kind == "land":
		var fish := str(res.get("fish", ""))
		if LifeData.FISH.has(fish):
			catches += 1
			_toast_catch(fish, bool(res.get("skill_up", false)))


func _finish(success: bool, why: String) -> void:
	var w := _widget()
	if w and not success:
		if why != "" and state == State.BITE:
			w.finish(false, why)
		else:
			w.cancel()
	if not success and why != "" and _hud and _hud.has_method("toast") and state != State.BITE:
		_hud.toast(why, "", "Fishing", UITheme.MUTED)
	state = State.IDLE
	current = -1
	current_fish = ""
	_show_rod(false)


# --- Visuals -----------------------------------------------------------------

func _widget() -> FishingWidget:
	if _hud == null or not is_instance_valid(_hud):
		return null
	var life = _hud.get("life")
	if life == null:
		return null
	return life.get("fishing")


func _show_rod(on: bool) -> void:
	if not on:
		if _rod:
			_rod.queue_free()
			_rod = null
		if _bobber:
			_bobber.queue_free()
			_bobber = null
		return
	if _rod:
		return
	_rod = Node3D.new()
	_rod.name = "Rod"
	_player.add_child(_rod)
	var water: Vector3 = spots[current]["water"]
	var toward := (water - _player.global_position) * Vector3(1, 0, 1)
	_rod.rotation.y = atan2(toward.x, toward.z)
	# Pole held low at the right hip, angled out over the water.
	WorldArt.cyl(_rod, 0.014, 0.024, 1.9, Vector3(0.3, 1.15, 0.7), WorldArt.WOOD_LIGHT, 6, Vector3(-1.0, 0, 0))
	WorldArt.cyl(_rod, 0.03, 0.03, 0.22, Vector3(0.3, 0.86, 0.2), Color("3b2a1e"), 6, Vector3(-1.0, 0, 0))


func _drop_bobber() -> void:
	if _bobber or current < 0:
		return
	var water: Vector3 = spots[current]["water"]
	_bobber = Node3D.new()
	_bobber.name = "Bobber"
	_bobber.position = water + Vector3(0, 0.12, 0)
	_world.add_child(_bobber)
	WorldArt.sphere(_bobber, 0.1, Vector3.ZERO, Color("e63946"))
	WorldArt.sphere(_bobber, 0.1, Vector3(0, 0.1, 0), Color("f3eee4"))
	_splash(water, 0.6)
	_bob_tw = _bobber.create_tween().set_loops()
	_bob_tw.tween_property(_bobber, "position:y", water.y + 0.06, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tw.tween_property(_bobber, "position:y", water.y + 0.16, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _splash(at: Vector3, size: float) -> void:
	Audio.play("splash", at, 0.1, -4.0, 0.75)
	var fx := VFX.get_for(_world)
	if fx:
		fx.ring(at + Vector3(0, 0.15, 0), Color(0.8, 0.95, 1.0), 1.4 * size, 0.45)
		fx.puff(at + Vector3(0, 0.3, 0), 0.7 * size, Color(0.85, 0.95, 1.0, 0.6))
		if size > 1.2:
			fx.sparkle(at + Vector3(0, 0.6, 0), Color(0.7, 0.9, 1.0))
