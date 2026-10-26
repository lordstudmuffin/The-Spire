extends Node
## Post-battle results, as in Aincrad: when a fight is over, one window sums
## up what it paid (EXP, Col, items) instead of a toast per kill. Each kill's
## share is noted here on the machine that receives it (Enemy._grant_share;
## online drops arrive with the server's "loot" event). QUIET seconds after
## the last kill the tally closes and goes to hud.show_battle_result(data)
## when the HUD has one, else to a toast.
##
## data = {"kills": int, "foes": {name: count}, "xp": int, "col": int,
##         "items": {material_id: count}, "level_ups": int}

const QUIET := 4.0

var hud: Node
var _tally := {}
var _quiet := 0.0
var _level0 := 0


static func build(w: Node) -> Node:
	var n := Node.new()
	n.set_script(load("res://scripts/battle_results.gd"))
	n.name = "BattleResults"
	n.add_to_group("battle_results")
	w.add_child(n)
	return n


func note_kill(foe: String, xp: int, col: int) -> void:
	_open()
	_tally["kills"] = int(_tally["kills"]) + 1
	var foes: Dictionary = _tally["foes"]
	foes[foe] = int(foes.get(foe, 0)) + 1
	_tally["xp"] = int(_tally["xp"]) + maxi(xp, 0)
	_tally["col"] = int(_tally["col"]) + maxi(col, 0)


func note_item(id: String, n := 1) -> void:
	_open()
	var items: Dictionary = _tally["items"]
	items[id] = int(items.get(id, 0)) + n


func _open() -> void:
	_quiet = QUIET
	if _tally.is_empty():
		_level0 = GameState.level
		_tally = {"kills": 0, "foes": {}, "xp": 0, "col": 0, "items": {}, "level_ups": 0}


func _process(delta: float) -> void:
	if _tally.is_empty():
		return
	_quiet -= delta
	if _quiet <= 0.0:
		close()


## Ends the tally now and shows it. Returns the data (tests read it).
func close() -> Dictionary:
	var data := _tally
	_tally = {}
	if data.is_empty() or (int(data["kills"]) == 0 and (data["items"] as Dictionary).is_empty()):
		return {}
	data["level_ups"] = maxi(GameState.level - _level0, 0)
	if hud and hud.has_method("show_battle_result"):
		hud.show_battle_result(data)
	elif hud and hud.has_method("toast"):
		hud.toast("Battle results", summary(data), "Victory", UITheme.GOLD)
	return data


static func summary(data: Dictionary) -> String:
	var parts: Array = ["+%d EXP" % int(data["xp"]), "+%d Col" % int(data["col"])]
	for id in data["items"]:
		parts.append("%s x%d" % [GameState.MATERIAL_NAMES.get(id, id), int(data["items"][id])])
	return "  ·  ".join(parts)
