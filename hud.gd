class_name ShipHUD
extends CanvasLayer

## Ship HUD: live lore coordinates, hull integrity, and the M-key chart
## overlay. Theme-driven styling with panel backgrounds, compass,
## speed/depth indicators, damage feedback, and discovery toast.
## All controls ignore the mouse so click-to-lock mouselook keeps working.

@export var boat_path := NodePath("../Boat")
@export var crab_path := NodePath("../Crab")
@export var quest_path := NodePath("../Quest")
@export var mobs_path := NodePath("../Mobs")
@export var story_path := NodePath("../Story")

var _coords: Label
var _hp: ProgressBar
var _jelly_warn: Label
var _tracker: Label
var _toast: Label
var _map: MapView
var _speed: Label
var _depth: Label
var _panel_coords: PanelContainer
var _panel_hp: PanelContainer
var _panel_tracker: PanelContainer
var _panel_jelly_warn: PanelContainer
var _panel_toast: PanelContainer
var _was_valley_warn := false
var _crab_card_shown := false
var _ending_shown := false
var _clock := 0.0
var _flash := 0.0
var _shown_names: Array = []
var _toast_timer := 0.0
var _hp_target := 100.0
var _hp_current := 100.0
var _damage_timer := 0.0
var _damage_flash := 0.0

@onready var _boat: Node3D = get_node_or_null(boat_path)
@onready var _crab: Node = get_node_or_null(crab_path)
@onready var _quest: Node = get_node_or_null(quest_path)
@onready var _mobs: Node = get_node_or_null(mobs_path)
@onready var _story: Node = get_node_or_null(story_path)
@onready var _darken: ColorRect = null
var _designer: Node = null


func _ready() -> void:
	layer = 10
	_load_theme()
	_build_darken()
	_build_left()
	_build_tracker()
	_build_center()
	_build_map()
	_init_designer()


var _panel_style := StyleBoxFlat.new()
var _progress_fill_style := StyleBoxFlat.new()
var _progress_panel_style := StyleBoxFlat.new()
var _warn_jelly_style := StyleBoxFlat.new()
var _toast_style := StyleBoxFlat.new()
var _tracker_style := StyleBoxFlat.new()


func _load_theme() -> void:
	_panel_style = _make_style(Color(0.05, 0.03, 0.02, 0.75), Color(0.92, 0.86, 0.68, 0.4), 8, 8, 12, 8, 0.4)
	_progress_fill_style = _make_style(Color(0.05, 0.03, 0.02, 0.8), Color(0.92, 0.86, 0.68, 0.5), 8, 8, 12, 8, 0.5)
	_progress_panel_style = _make_style(Color(0.05, 0.03, 0.02, 0.7), Color(0.92, 0.86, 0.68, 0.3), 6, 6, 10, 6, 0.3)
	_warn_jelly_style = _make_style(Color(0.1, 0.05, 0.0, 0.85), Color(1, 0.6, 0.1, 0.8), 8, 10, 16, 10, 0.8)
	_toast_style = _make_style(Color(0.02, 0.1, 0.02, 0.85), Color(0.6, 1, 0.6, 0.8), 8, 10, 16, 10, 0.8)
	_tracker_style = _make_style(Color(0.05, 0.03, 0.02, 0.7), Color(0.92, 0.86, 0.68, 0.4), 8, 8, 12, 8, 0.4)


func _make_style(bg: Color, border: Color, radius: int, margin_v: int, margin_h: int, border_w: int, border_a: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_bottom = border_w
	s.border_width_left = border_w
	s.border_width_right = border_w
	s.border_width_top = border_w
	s.border_color = Color(border.r, border.g, border.b, border_a)
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.content_margin_bottom = margin_v
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	return s


func _get_stylebox(name: String) -> StyleBoxFlat:
	match name:
		"panel": return _panel_style
		"fill": return _progress_fill_style
		"progress_bar_panel": return _progress_panel_style
		"warn_jelly": return _warn_jelly_style
		"toast": return _toast_style
		"tracker": return _tracker_style
		_: return StyleBoxFlat.new()


func _build_panel(name: String, style: String, min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = name
	p.add_theme_stylebox_override("panel", _get_stylebox(style))
	if min_size.x > 0.0 or min_size.y > 0.0:
		p.custom_minimum_size = min_size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Left instrument column, anchored top-left.
func _build_left() -> void:
	var col := VBoxContainer.new()
	col.name = "LeftColumn"
	col.add_theme_constant_override("separation", 4)
	col.position = Vector2(8, 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	_panel_coords = _build_panel("PanelCoords", "panel", Vector2(210, 36))
	_coords = _hud_label("CoordsLabel", "00\u00b000'N 000\u00b000'E", 20, Color(0.92, 0.86, 0.68))
	_panel_coords.add_child(_coords)
	col.add_child(_panel_coords)

	_panel_hp = _build_panel("PanelHull", "panel", Vector2(240, 0))
	var hull_box := VBoxContainer.new()
	hull_box.add_theme_constant_override("separation", 2)
	hull_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_hp.add_child(hull_box)
	var hull_label := _hud_label("HullLabel", "HULL", 11, Color(0.7, 0.65, 0.55))
	hull_box.add_child(hull_label)
	_hp = ProgressBar.new()
	_hp.name = "HullBar"
	_hp.min_value = 0.0
	_hp.max_value = 100.0
	_hp.value = 100.0
	_hp.show_percentage = false
	_hp.custom_minimum_size = Vector2(220, 16)
	_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp.add_theme_stylebox_override("fill", _get_stylebox("fill"))
	_hp.add_theme_stylebox_override("background", _get_stylebox("progress_bar_panel"))
	hull_box.add_child(_hp)

	_speed = _hud_label("SpeedLabel", "0.0 kn", 16, Color(0.7, 1.0, 0.7))
	col.add_child(_speed)
	_depth = _hud_label("DepthLabel", "0.0 m", 14, Color(0.6, 0.8, 1.0))
	col.add_child(_depth)


func _hud_label(label_name: String, text: String, fsize: int, color: Color) -> Label:
	var l := Label.new()
	l.name = label_name
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return l


func _build_darken() -> void:
	_darken = ColorRect.new()
	_darken.name = "DamageDarken"
	_darken.color = Color(0.5, 0.0, 0.0, 0.0)
	_darken.set_anchors_preset(Control.PRESET_FULL_RECT)
	_darken.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_darken.visible = false
	add_child(_darken)


func _build_tracker() -> void:
	_panel_tracker = _build_panel("PanelTracker", "tracker", Vector2(300, 0))
	_panel_tracker.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel_tracker.offset_left = -308.0
	_panel_tracker.offset_right = -8.0
	_panel_tracker.offset_top = 6.0
	add_child(_panel_tracker)
	_tracker = _hud_label("QuestTracker", "", 16, Color(0.92, 0.86, 0.68))
	_panel_tracker.visible = false
	_panel_tracker.add_child(_tracker)


## Center alert stack, anchored top-center: warnings and toast can never
## overlap each other or slide off-screen.
func _build_center() -> void:
	var col := VBoxContainer.new()
	col.name = "CenterColumn"
	col.set_anchors_preset(Control.PRESET_CENTER_TOP)
	col.offset_left = -220.0
	col.offset_right = 220.0
	col.offset_top = 120.0
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	_panel_jelly_warn = _build_panel("PanelJellyWarn", "warn_jelly", Vector2(440, 0))
	_jelly_warn = _alert_label("JellyWarning", "JELLYFISH VALLEY — TURN LAMPS OFF (L)", Color(1.0, 0.6, 0.1))
	_panel_jelly_warn.visible = false
	_panel_jelly_warn.add_child(_jelly_warn)
	col.add_child(_panel_jelly_warn)

	_panel_toast = _build_panel("PanelToast", "toast", Vector2(440, 0))
	_toast = _alert_label("QuestToast", "", Color(0.6, 1.0, 0.6))
	_panel_toast.visible = false
	_panel_toast.add_child(_toast)
	col.add_child(_panel_toast)


func _alert_label(label_name: String, text: String, color: Color) -> Label:
	var l := _hud_label(label_name, text, 22, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _build_map() -> void:
	_map = MapView.new()
	_map.name = "MapView"
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_M:
			_map.visible = not _map.visible


func _process(delta: float) -> void:
	if _boat == null:
		return
	var hull := float(_boat.get("hull_hp"))
	_hp_target = clampf(hull, 0.0, 100.0)
	_hp_current = lerp(_hp_current, _hp_target, min(1.0, 8.0 * delta))
	_hp.value = _hp_current
	if abs(_hp_target - _hp_current) > 2.0:
		_damage_timer = 0.5
	if _damage_timer > 0.0:
		_damage_timer -= delta
		_damage_flash = clampf(1.0 - _damage_timer, 0.0, 0.4)
		_darken.color = Color(0.5, 0.0, 0.0, _damage_flash)
		_darken.visible = _damage_flash > 0.01
	else:
		_darken.visible = false
	_flash += delta
	_update_quest(delta)
	var boat_speed := 0.0
	if _boat is RigidBody3D:
		boat_speed = (_boat as RigidBody3D).linear_velocity.length()
	var knots := boat_speed * 1.944
	if _boat != null and bool(_boat.get("test_mode")):
		_speed.text = "TEST %.1f kn" % knots
	else:
		_speed.text = "%.1f kn" % knots
	if _boat is Node3D and _designer != null:
		var wd := WaterSampler.height_at(Vector2(_boat.global_position.x, _boat.global_position.z), Time.get_ticks_msec() / 1000.0, _designer.height_waves)
		_depth.text = "%.1f m" % wd
	var valley_warn := _mobs != null and bool(_mobs.get("giant_warning_active"))
	if valley_warn and not _was_valley_warn:
		_story_beat("valley")
	_was_valley_warn = valley_warn
	if valley_warn:
		_panel_jelly_warn.visible = true
		_jelly_warn.modulate.a = 1.0 if fmod(_flash * 4.0, 1.0) < 0.6 else 0.15
	else:
		_panel_jelly_warn.visible = false
	if _crab != null and bool(_crab.get("has_woken")) and not _crab_card_shown:
		_crab_card_shown = true
		_story_beat("crab")
	if _quest != null and bool(_quest.get("all_done")) and not _ending_shown:
		_ending_shown = true
		_story_beat("ending")
	_clock += delta
	if _clock >= 0.2:
		_clock = 0.0
		_coords.text = Geo.format_ll(Geo.latlon_of(_boat.global_position))
		_map.ship_ll = Geo.latlon_of(_boat.global_position)
		_sync_map_spots()
		if _map.visible:
			_map.queue_redraw()


func _update_quest(delta: float) -> void:
	if _quest == null or not _quest.has_method("done_count"):
		_panel_tracker.visible = false
		return
	_resolve_charting()
	var total: int = (_quest.get("entries") as Array).size()
	var done: int = int(_quest.call("done_count"))
	var lines := ["CHART THE REACH  %d/%d" % [done, total]]
	for e in (_quest.get("entries") as Array):
		var mark := "X" if bool(e["done"]) else "-"
		lines.append("[%s] %s" % [mark, String(e["name"])])
	if bool(_quest.get("all_done")):
		lines.append("Sector charted.")
	_tracker.text = "\n".join(lines)
	_panel_tracker.visible = true
	for e in (_quest.get("entries") as Array):
		var nm := String(e["name"])
		if bool(e["done"]) and not _shown_names.has(nm):
			_shown_names.append(nm)
			_story_beat(_beat_for(nm))
			_toast.text = "Charted: %s  (%d/%d)" % [nm, done, total]
			if bool(_quest.get("all_done")):
				_toast.text = "SECTOR CHARTED — the Reach is mapped."
			_panel_toast.visible = true
			_toast_timer = 4.0
	if _panel_toast.visible:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_panel_toast.visible = false


func _init_designer() -> void:
	if _designer != null or _boat == null:
		return
	_designer = _boat.get_node_or_null(NodePath("../DeepOcean/WaterMaterialDesigner"))


## Forward wild-island spots and quest discovery state to the chart.
## Spots are static after build, so they are pushed once.
func _sync_map_spots() -> void:
	if _map == null:
		return
	if _map.wild_spots.is_empty():
		var wi := get_parent().get_node_or_null("WorldIslands")
		if wi != null and wi.has_method("get_wild_islands"):
			var spots: Array = []
			for w in wi.call("get_wild_islands"):
				spots.append({"name": String(w["name"]), "ll": w["ll"]})
			if not spots.is_empty():
				_map.set_wild_spots(spots)
	if _quest != null:
		_map.sync_entries(_quest.get("entries") as Array)


## Story beats: island names map to chapters, everything else is ignored.
## Charting resolution order: a visited entry queues its story card, and
## only counts as charted (tracker, toast, green marker) after the card
## has been shown. Card-less entries chart on visit.
func _resolve_charting() -> void:
	if _quest == null or not _quest.has_method("force_done"):
		return
	for e in (_quest.get("entries") as Array):
		if bool(e["done"]) or not bool(e.get("visited", false)):
			continue
		var beat := _beat_for(String(e["name"]))
		if beat.is_empty():
			_quest.call("force_done", String(e["name"]))
			continue
		_story_beat(beat)
		if _story != null and _story.has_method("is_beat_done") and bool(_story.call("is_beat_done", beat)):
			_quest.call("force_done", String(e["name"]))


func _story_beat(beat_id: String) -> void:
	if beat_id.is_empty() or _story == null or not _story.has_method("queue_beat"):
		return
	_story.call("queue_beat", beat_id)


func _beat_for(spot_name: String) -> String:
	match spot_name:
		"Twin Spires":
			return "twin"
		"Teardrop":
			return "teardrop"
		"Crescent":
			return "crescent"
	return ""
