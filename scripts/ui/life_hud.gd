class_name LifeHUD
extends Node
## HUD pieces of the life layer, kept out of hud.gd: the buff icons under
## the player plate, the fishing minigame widget and the three modal
## screens (cooking, Trader Pell's shop, the cottage chest). The HUD creates
## one with `LifeHUD.attach(hud, root)` and asks `any_open()` / `hide_all()`
## in its menu bookkeeping; everything else is driven from the world.

var fishing: FishingWidget
var _hud: Node
var _root: Control
var _buff_bar: HBoxContainer
var _buff_pills: Array = []  # [{"node", "name", "time", "dot", "sb"}]
var _cook_panel: PanelContainer
var _cook: CookingScreen
var _shop_panel: PanelContainer
var _shop: ShopScreen
var _store_panel: PanelContainer
var _store: StorageScreen
## Hollowbrook market stall screen (P7, scripts/ui/stall_screen.gd).
const StallScreenScript := preload("res://scripts/ui/stall_screen.gd")
var _stall_panel: PanelContainer
var _stall
## Farm plots and guilds (P8, scripts/ui/farm_screen.gd, guild_screen.gd).
const FarmScreenScript := preload("res://scripts/ui/farm_screen.gd")
const GuildScreenScript := preload("res://scripts/ui/guild_screen.gd")
var _farm_panel: PanelContainer
var _farm
var _guild_panel: PanelContainer
var _guild
var _tavern_panel: PanelContainer
var _tavern: TavernScreen
var _tick := 0.0


static func attach(hud: Node, root: Control) -> LifeHUD:
	var l := LifeHUD.new()
	l.name = "LifeHUD"
	l._hud = hud
	l._root = root
	hud.add_child(l)
	l._build()
	return l


func _build() -> void:
	fishing = FishingWidget.attach(_root)
	_build_buff_bar()
	_cook_panel = _hud._modal(_root, 720)
	_cook = CookingScreen.build()
	_cook.cooked.connect(_on_cooked)
	_cook.ate.connect(_on_ate)
	_hud._modal_box(_cook_panel).add_child(_cook)
	_shop_panel = _hud._modal(_root, 680)
	_shop = ShopScreen.build()
	_shop.bought.connect(func(id):
		var nm: String = LifeData.TOOLS[id]["name"] if LifeData.TOOLS.has(id) else LifeData.DECOR[id]["name"]
		_hud.toast(nm, "Bought from Trader Pell", "Purchase", UITheme.GOLD))
	_hud._modal_box(_shop_panel).add_child(_shop)
	_store_panel = _hud._modal(_root, 0)
	_store = StorageScreen.build()
	_hud._modal_box(_store_panel).add_child(_store)
	_stall_panel = _hud._modal(_root, 0)
	_stall = StallScreenScript.build()
	_hud._modal_box(_stall_panel).add_child(_stall)
	_farm_panel = _hud._modal(_root, 0)
	_farm = FarmScreenScript.build()
	_hud._modal_box(_farm_panel).add_child(_farm)
	_tavern_panel = _hud._modal(_root, 0)
	_tavern = TavernScreen.build()
	_hud._modal_box(_tavern_panel).add_child(_tavern)
	_guild_panel = _hud._modal(_root, 0)
	_guild = GuildScreenScript.build()
	_hud._modal_box(_guild_panel).add_child(_guild)
	GameState.buffs_changed.connect(_refresh_buffs)
	GameState.life_skill_up.connect(func(skill, level):
		_hud.toast("%s Lv %d" % [skill.capitalize(), level], "", "Skill up", UITheme.CYAN)
		Audio.play("level_up"))
	_refresh_buffs()


# --- Buff bar -------------------------------------------------------------------

func _build_buff_bar() -> void:
	# Bottom-left, just above the pickup feed (the party panel sits under
	# the player plate, so the buffs keep clear of it).
	_buff_bar = HBoxContainer.new()
	_buff_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_buff_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_buff_bar.offset_left = 24
	_buff_bar.offset_right = 24 + 700
	_buff_bar.offset_bottom = -214
	_buff_bar.offset_top = -244
	_buff_bar.add_theme_constant_override("separation", 6)
	_buff_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_buff_bar)
	for i in 6:
		var p := PanelContainer.new()
		var sb := UITheme.box(Color(UITheme.NAVY.r, UITheme.NAVY.g, UITheme.NAVY.b, 0.72), Color(1, 1, 1, 0.14), 999, 1)
		sb.content_margin_left = 8
		sb.content_margin_right = 12
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var dot := UIGlyph.make("food", UITheme.GOLD, 18, 0.8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dot)
		var nm := UITheme.label("", 12, UITheme.PARCH, true)
		h.add_child(nm)
		var tm := UITheme.label("", 11, UITheme.MUTED, true)
		h.add_child(tm)
		p.add_child(h)
		p.hide()
		_buff_bar.add_child(p)
		_buff_pills.append({"node": p, "name": nm, "time": tm, "dot": dot, "sb": sb})


func _refresh_buffs() -> void:
	var ids := GameState.buffs.keys()
	for i in _buff_pills.size():
		var pill: Dictionary = _buff_pills[i]
		if i >= ids.size():
			(pill["node"] as Control).hide()
			continue
		var b: Dictionary = GameState.buffs[ids[i]]
		var c := Color(str(b.get("color", "f0c060")))
		(pill["node"] as Control).show()
		(pill["name"] as Label).text = str(b.get("name", ids[i]))
		(pill["name"] as Label).add_theme_color_override("font_color", c)
		(pill["dot"] as UIGlyph).set_glyph("rest" if ids[i] == "rested" else "food", c)
		(pill["sb"] as StyleBoxFlat).border_color = Color(c.r, c.g, c.b, 0.5)
		(pill["time"] as Label).text = _time_text(float(b.get("left", 0.0)))
		(pill["node"] as Control).tooltip_text = LifeData.buff_text(b)


func _time_text(s: float) -> String:
	var t := int(ceil(s))
	return "%d:%02d" % [t / 60, t % 60]


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or GameState.buffs.is_empty():
		return
	_tick = 0.5
	var ids := GameState.buffs.keys()
	for i in mini(ids.size(), _buff_pills.size()):
		(_buff_pills[i]["time"] as Label).text = _time_text(float(GameState.buffs[ids[i]].get("left", 0.0)))


# --- Screens --------------------------------------------------------------------

func any_open() -> bool:
	return _cook_panel.visible or _shop_panel.visible or _store_panel.visible or (_stall_panel != null and _stall_panel.visible) \
		or (_farm_panel != null and _farm_panel.visible) or (_guild_panel != null and _guild_panel.visible) \
		or (_tavern_panel != null and _tavern_panel.visible)


func cooking_open() -> bool:
	return _cook_panel.visible


func hide_all() -> void:
	_cook_panel.hide()
	_shop_panel.hide()
	_store_panel.hide()
	if _stall_panel:
		_stall_panel.hide()
	if _farm_panel:
		_farm_panel.hide()
	if _guild_panel:
		_guild_panel.hide()
	if _tavern_panel:
		_tavern_panel.hide()


func _open(panel: PanelContainer) -> void:
	_hud._hide_screens()
	if _hud.has_method("_hide_craft"):
		_hud._hide_craft()
	panel.show()
	_hud._pop_in(panel)
	UITheme.focus_first_in(panel)  # D-pad / keyboard start on the first button
	Audio.play("ui_open")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.input_enabled = false


func toggle_cooking(where := "Camp fire") -> bool:
	if _cook_panel.visible:
		_hud.close_screens()
		return false
	_cook.set_where(where)
	_cook.refresh()
	_open(_cook_panel)
	return true


func open_shop() -> void:
	_shop.refresh()
	_open(_shop_panel)


func open_storage() -> void:
	_store.refresh()
	_open(_store_panel)


func refresh() -> void:
	if _cook_panel.visible:
		_cook.refresh()
	if _shop_panel.visible:
		_shop.refresh()
	if _store_panel.visible:
		_store.refresh()
	if _stall_panel and _stall_panel.visible:
		_stall.refresh()
	if _farm_panel and _farm_panel.visible:
		_farm.refresh()
	if _guild_panel and _guild_panel.visible:
		_guild.refresh()


## Opens the market stall screen on stall `i` of the world's MarketStalls
## node and returns the screen (the node forwards server answers to it).
func open_stall(stalls: Node, i: int):
	_stall.open(stalls, i)
	_open(_stall_panel)
	return _stall


func stall_open() -> bool:
	return _stall_panel != null and _stall_panel.visible


## Opens the farm screen on plot `i` (-1 = the seed cart) of the FarmField node.
func open_farm(farms: Node, i: int):
	_farm.open(farms, i)
	_open(_farm_panel)
	return _farm


func farm_open() -> bool:
	return _farm_panel != null and _farm_panel.visible


## Opens the guild panel (notice board or /guild).
func open_guild(guilds: Node):
	_guild.open(guilds)
	_open(_guild_panel)
	return _guild


func open_tavern(tavern: Node, tab := "counter"):
	_open(_tavern_panel)
	_tavern.open(tavern, tab)
	return _tavern


func tavern_open() -> bool:
	return _tavern_panel != null and _tavern_panel.visible


func guild_open() -> bool:
	return _guild_panel != null and _guild_panel.visible


func _on_cooked(res: Dictionary) -> void:
	if res.has("error"):
		_hud.toast(str(res["error"]), "", "", UITheme.ROSE)
		return
	var sub := "Cooking Lv %d" % GameState.cooking_level if res.get("skill_up", false) else LifeData.buff_text(LifeData.RECIPES[res["id"]]["buff"])
	_hud.toast(str(res["name"]), sub, "Cooked", LifeData.item_color(res["id"]))


func _on_ate(id: String) -> void:
	var r: Dictionary = LifeData.RECIPES[id]
	_hud.toast(str(r["name"]), LifeData.buff_text(r["buff"]), "Eaten", LifeData.item_color(id))
