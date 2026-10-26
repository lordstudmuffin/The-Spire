extends RefCounted
## Wayside landmarks in Floor 1's open country, so the long walks between
## the town, the villages and the Labyrinth pass places worth a look: a
## ruined watchtower, a hunters' camp with a cooking fire, a hillside
## shrine, an abandoned siege camp and a bridge over the mill stream. All
## built from the CC0 kits (Kenney Castle / Survival / Graveyard / Nature);
## each sits in its own flat clearing (WorldArt.FLAT_ZONES). Missing packs
## simply leave a spot empty.

const C := WorldProps.CASTLE
const S := WorldProps.SURVIVAL
const G := WorldProps.GRAVE
const N := WorldProps.NATURE

## [anchor, vegetation keep-clear radius]
const KEEP := [[WorldArt.RUINED_WATCH, 15.0], [WorldArt.HUNTERS_CAMP, 11.0], [WorldArt.SHRINE, 10.0],
	[WorldArt.SIEGE_CAMP, 12.0], [WorldArt.STREAM_BRIDGE, 6.0]]


static func _v(p: Vector2, off := Vector3.ZERO) -> Vector3:
	return Vector3(p.x, 0, p.y) + off


## Builds every landmark under `w` and returns keep-clear pairs [Vector3, r]
## for the vegetation pass, plus the hunters' fire for the cooking spots.
static func build(w: Node3D) -> Dictionary:
	_ruined_watch(w, WorldArt.RUINED_WATCH)
	_hunters_camp(w, WorldArt.HUNTERS_CAMP)
	_shrine(w, WorldArt.SHRINE)
	_siege_camp(w, WorldArt.SIEGE_CAMP)
	_bridge(w, WorldArt.STREAM_BRIDGE)
	var keep := []
	for k in KEEP:
		keep.append([_v(k[0]), k[1]])
	return {"keep": keep, "fire": _v(WorldArt.HUNTERS_CAMP, Vector3(0, 0, 2.5))}


## A watchtower that fell in some old war: the base still stands, its walls
## lie broken round it, a wrecked trebuchet in the grass.
static func _ruined_watch(w: Node3D, c: Vector2) -> void:
	WorldProps.prop(w, "castle", "tower-square-base-border", _v(c), 0.3, C)
	WorldProps.prop(w, "castle", "wall-half", _v(c, Vector3(6.5, 0, 1.0)), 1.9, C)
	WorldProps.prop(w, "castle", "wall-corner-half", _v(c, Vector3(-5.5, 0, 4.5)), -0.6, C)
	WorldProps.prop(w, "castle", "wall-half", _v(c, Vector3(-2.0, 0, -7.0)), 0.1, C)
	WorldProps.prop(w, "castle", "siege-trebuchet-demolished", _v(c, Vector3(9.0, 0, -6.5)), 2.4, C * 0.9)
	WorldProps.prop(w, "castle", "rocks-large", _v(c, Vector3(-8.5, 0, -3.5)), 1.1, C * 0.8, "none")
	WorldProps.prop(w, "castle", "rocks-small", _v(c, Vector3(4.0, 0, 7.0)), 0.4, C, "none")
	WorldProps.prop(w, "castle", "rocks-small", _v(c, Vector3(-3.0, 0, 8.5)), 2.2, C, "none")
	WorldProps.prop(w, "castle", "flag-banner-long", _v(c, Vector3(2.2, 0, 3.4)), 0.3, C * 0.8, "none")


## Where the hunters who work the northern woods sleep: two tents, bedrolls,
## a log seat and a fire pit you can cook at.
static func _hunters_camp(w: Node3D, c: Vector2) -> void:
	WorldProps.prop(w, "survival", "tent-canvas", _v(c, Vector3(-4.0, 0, -2.5)), 0.6, S)
	WorldProps.prop(w, "survival", "tent", _v(c, Vector3(3.8, 0, -3.0)), -0.5, S)
	WorldProps.prop(w, "survival", "campfire-pit", _v(c, Vector3(0, 0, 2.5)), 0.0, S, "none")
	WorldProps.prop(w, "survival", "campfire-stand", _v(c, Vector3(0, 0, 2.5)), 0.0, S, "none")
	WorldProps.prop(w, "survival", "bedroll", _v(c, Vector3(-2.6, 0, 3.6)), 1.2, S, "none")
	WorldProps.prop(w, "survival", "bedroll-packed", _v(c, Vector3(2.8, 0, 4.4)), -0.4, S, "none")
	WorldProps.prop(w, "survival", "tree-log", _v(c, Vector3(0.2, 0, 5.4)), 1.57, S)
	WorldProps.prop(w, "survival", "box-large", _v(c, Vector3(5.6, 0, 0.6)), 0.3, S)
	WorldProps.prop(w, "survival", "resource-wood", _v(c, Vector3(-5.8, 0, 1.6)), 0.9, S, "none")
	WorldProps.prop(w, "survival", "signpost", _v(c, Vector3(7.5, 0, 5.5)), -0.8, S)
	var glow := OmniLight3D.new()
	glow.light_color = Color("ff9a4a")
	glow.light_energy = 1.4
	glow.omni_range = 7.0
	glow.position = _v(c, Vector3(0, 1.2, 2.5))
	w.add_child(glow)


## A small hillside shrine: an altar in a ring of old pillars, candles and
## offerings, a few weathered stones.
static func _shrine(w: Node3D, c: Vector2) -> void:
	WorldProps.prop(w, "graveyard", "altar-stone", _v(c), 0.0, G * 1.2)
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		WorldProps.prop(w, "graveyard", "pillar-large" if i % 2 == 0 else "column-large", _v(c, Vector3(cos(a), 0, sin(a)) * 6.0), -a, G * 1.1)
	WorldProps.prop(w, "graveyard", "candle-multiple", _v(c, Vector3(0.9, 0, 1.2)), 0.0, G, "none")
	WorldProps.prop(w, "graveyard", "urn-round", _v(c, Vector3(-1.4, 0, 1.0)), 0.0, G, "none")
	WorldProps.prop(w, "graveyard", "stone-wall-damaged", _v(c, Vector3(0, 0, -8.5)), 0.0, G * 1.1)
	WorldProps.prop(w, "graveyard", "gravestone-broken", _v(c, Vector3(5.5, 0, 6.0)), 0.7, G, "none")
	WorldProps.prop(w, "graveyard", "lantern-candle", _v(c, Vector3(-3.0, 0, 3.5)), 0.0, G, "none")


## Siege engines left to rot where an army once camped against the tower.
static func _siege_camp(w: Node3D, c: Vector2) -> void:
	WorldProps.prop(w, "castle", "siege-tower-demolished", _v(c, Vector3(-3.0, 0, -2.0)), 0.8, C)
	WorldProps.prop(w, "castle", "siege-ram-demolished", _v(c, Vector3(6.0, 0, 3.0)), -1.2, C)
	WorldProps.prop(w, "castle", "siege-catapult-demolished", _v(c, Vector3(-7.0, 0, 6.0)), 2.6, C)
	WorldProps.prop(w, "castle", "flag-pennant", _v(c, Vector3(2.5, 0, -6.5)), 0.0, C, "none")
	WorldProps.prop(w, "castle", "rocks-small", _v(c, Vector3(8.0, 0, -5.0)), 1.0, C, "none")
	WorldProps.prop(w, "survival", "box-large-open", _v(c, Vector3(1.0, 0, 5.5)), 0.5, S)


## A plank bridge over the mill stream, east of the pond.
static func _bridge(w: Node3D, c: Vector2) -> void:
	# The stream runs east-west here; the bridge spans it north-south.
	WorldProps.prop(w, "nature", "bridge_wood", _v(c, Vector3(0, 0.05, 0)), PI / 2, N, "none")
