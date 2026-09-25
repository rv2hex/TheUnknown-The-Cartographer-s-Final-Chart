class_name GameMenu
extends CanvasLayer

## Start screen + pause/settings menu, built in code like ShipHUD.
## The game boots paused on this screen; Set Sail starts the voyage,
## Esc toggles settings afterwards. Owns every player-facing setting and
## persists to user://settings.cfg: brightness (DayNightCycle), mouse
## sensitivity + camera distance (Main rig), field of view (Camera3D),
## day length (DayNightCycle).

const SAVE_PATH := "user://settings.cfg"
const MENU_MUSIC := "res://sounds/menu_music.ogg"
const OCEAN_WAVES := "res://sounds/ocean_waves.ogg"
## Looped TheWave theme under the start screen and the death screen.
const MUSIC_DB := -12.0
## Open-water voyage level: half the amplitude (-6 dB) under the waves.
const MUSIC_VOYAGE_DB := -18.0
const OCEAN_DB := -12.0

@export var cycle_path := NodePath("../DayNightCycle")
@export var camera_path := NodePath("../Camera3D")
@export var boat_path := NodePath("../Boat")

var _rig: Node = null
var _cycle: Node = null
var _camera: Camera3D = null
var _boat: Node = null
var _rows: Dictionary = {}
var _started := false
var _start_btn: Button = null
var _resume_btn: Button = null
var _gameover: Control = null
var _gameover_shown := false
var _music: AudioStreamPlayer = null
var _ocean: AudioStreamPlayer = null
var _main_box: VBoxContainer = null
var _settings_box: VBoxContainer = null
var _test_toggle: CheckButton = null


## Shared audio buses for the whole game. Idempotent: callers (sea-life
## calls included) just route players at "Music" / "Sea" and it holds.
static func ensure_audio_buses() -> void:
	if AudioServer.bus_count < 1:
		return
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
	if AudioServer.get_bus_index("Sea") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Sea")


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rig = get_parent()
	_cycle = get_node_or_null(cycle_path)
	_camera = get_node_or_null(camera_path) as Camera3D
	_boat = get_node_or_null(boat_path)
	_build()
	_build_gameover()
	_build_music()
	_build_ocean()
	ensure_audio_buses()
	_load()
	# Boot state: start screen, world held still behind it.
	_started = false
	_start_btn.visible = true
	_resume_btn.visible = false
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not _started:
		return
	if _gameover_shown:
		return
	if event.is_action_pressed("ui_cancel"):
		visible = not visible
		if visible:
			_show_main()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "THE UNKNOWN"
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "The Cartographer's Final Chart  —  hold still when she wakes"
	sub.add_theme_font_size_override("font_size", 16)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	# Front page: sail, settings, leave. Nothing more.
	_main_box = VBoxContainer.new()
	_main_box.name = "MainBox"
	_main_box.add_theme_constant_override("separation", 10)
	box.add_child(_main_box)

	_start_btn = Button.new()
	_start_btn.name = "Start"
	_start_btn.text = "Set Sail"
	_start_btn.pressed.connect(_on_start)
	_main_box.add_child(_start_btn)

	_resume_btn = Button.new()
	_resume_btn.name = "Resume"
	_resume_btn.text = "Resume  (Esc)"
	_resume_btn.pressed.connect(_on_resume)
	_main_box.add_child(_resume_btn)

	var settings_btn := Button.new()
	settings_btn.name = "Settings"
	settings_btn.text = "Settings"
	settings_btn.pressed.connect(_show_settings)
	_main_box.add_child(settings_btn)

	var quit := Button.new()
	quit.name = "Quit"
	quit.text = "Quit"
	quit.pressed.connect(_on_quit)
	_main_box.add_child(quit)

	# Settings page: everything tunable, audio included.
	_settings_box = VBoxContainer.new()
	_settings_box.name = "SettingsBox"
	_settings_box.add_theme_constant_override("separation", 10)
	_settings_box.visible = false
	box.add_child(_settings_box)

	var settings_title := Label.new()
	settings_title.text = "SETTINGS"
	settings_title.add_theme_font_size_override("font_size", 28)
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_box.add_child(settings_title)

	_add_row(_settings_box, "brightness", "Brightness", 0.3, 1.7, 0.05, "%.2f")
	_add_row(_settings_box, "sound", "Sound", 0.0, 100.0, 1.0, "%.0f")
	_add_row(_settings_box, "music", "Music", 0.0, 100.0, 1.0, "%.0f")
	_add_row(_settings_box, "sensitivity", "Mouse Sensitivity", 0.0005, 0.008, 0.0001, "%.4f")
	_add_row(_settings_box, "distance", "Camera Distance", 15.0, 45.0, 1.0, "%.0f")
	_add_row(_settings_box, "fov", "Field of View", 50.0, 90.0, 1.0, "%.0f")
	_add_row(_settings_box, "day_length", "Day Length (s)", 300.0, 2400.0, 60.0, "%.0f")

	_test_toggle = CheckButton.new()
	_test_toggle.name = "TestMode"
	_test_toggle.text = "Test Mode (100 km/h, no damage)"
	_test_toggle.toggled.connect(_on_test_mode)
	_settings_box.add_child(_test_toggle)

	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	back.pressed.connect(_show_main)
	_settings_box.add_child(back)


func _show_main() -> void:
	if _main_box != null:
		_main_box.visible = true
	if _settings_box != null:
		_settings_box.visible = false


func _show_settings() -> void:
	if _main_box != null:
		_main_box.visible = false
	if _settings_box != null:
		_settings_box.visible = true


func _add_row(box: VBoxContainer, key: String, label_text: String, lo: float, hi: float, step: float, fmt: String) -> void:
	var row := HBoxContainer.new()
	row.name = key
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(170, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size = Vector2(260, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_slider.bind(key))
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(70, 0)
	row.add_child(value_label)
	_rows[key] = {"slider": slider, "value": value_label, "fmt": fmt}


func _refresh() -> void:
	_set_row("brightness", float(_cycle.get("brightness")) if _cycle != null else 1.0)
	_set_row("sound", _bus_pct("Sea", 80.0))
	_set_row("music", _bus_pct("Music", 80.0))
	_set_row("sensitivity", float(_rig.get("mouse_sensitivity")) if _rig != null else 0.0025)
	_set_row("distance", float(_rig.get("distance")) if _rig != null else 28.0)
	_set_row("fov", _camera.fov if _camera != null else 70.0)
	_set_row("day_length", float(_cycle.get("cycle_seconds")) if _cycle != null else 1200.0)
	if _test_toggle != null:
		_test_toggle.set_pressed_no_signal(bool(_boat.get("test_mode")) if _boat != null else false)


func _set_row(key: String, v: float) -> void:
	var slider: HSlider = _rows[key]["slider"]
	slider.set_value_no_signal(v)
	(_rows[key]["value"] as Label).text = (_rows[key]["fmt"] as String) % v


func _on_slider(v: float, key: String) -> void:
	(_rows[key]["value"] as Label).text = (_rows[key]["fmt"] as String) % v
	match key:
		"brightness":
			if _cycle != null:
				_cycle.set("brightness", v)
		"sensitivity":
			if _rig != null:
				_rig.set("mouse_sensitivity", v)
		"distance":
			if _rig != null:
				_rig.set("distance", v)
		"fov":
			if _camera != null:
				_camera.fov = v
		"day_length":
			if _cycle != null:
				_cycle.set("cycle_seconds", v)
		"sound", "music":
			_apply_audio_volumes()
	_save()


## Percent rows (0-100) drive the shared buses; context (menu/voyage)
## lives on the players. Missing rows fall back to 80.
func _row_value(key: String, fallback: float) -> float:
	if _rows.has(key):
		return float((_rows[key] as Dictionary)["slider"].value)
	return fallback


func _pct_to_db(v: float) -> float:
	if v <= 0.5:
		return -40.0
	return linear_to_db(v / 100.0)


func _bus_pct(bus: String, fallback: float) -> float:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return fallback
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)) * 100.0, 0.0, 100.0)


func _apply_audio_volumes() -> void:
	ensure_audio_buses()
	var sea := AudioServer.get_bus_index("Sea")
	var mus := AudioServer.get_bus_index("Music")
	if sea != -1:
		AudioServer.set_bus_volume_db(sea, _pct_to_db(_row_value("sound", 80.0)))
	if mus != -1:
		AudioServer.set_bus_volume_db(mus, _pct_to_db(_row_value("music", 80.0)))


func _on_test_mode(on: bool) -> void:
	if _boat != null:
		_boat.set("test_mode", on)
	_save()


func _on_start() -> void:
	_started = true
	get_tree().paused = false
	_start_btn.visible = false
	_resume_btn.visible = true
	visible = false
	_test_spawn_near_valley()
	_music_voyage()
	var story := get_parent().get_node_or_null("Story")
	if story != null and story.has_method("queue_beat"):
		story.call("queue_beat", "intro")


## Test mode starts at the valley: 220 m south of the jellyfish disc, bow
## toward it — inside the 250 m lamp attraction with night forced, so the
## pack stages on arrival and the first dive lands within seconds.
func _test_spawn_near_valley() -> void:
	if _boat == null or not bool(_boat.get("test_mode")):
		return
	var vc := Geo.world_of_ll(Geo.JELLY_VALLEY)
	_boat.global_position = Vector3(vc.x, 3.0, vc.z + 220.0)
	if _boat is RigidBody3D:
		(_boat as RigidBody3D).linear_velocity = Vector3.ZERO
		(_boat as RigidBody3D).angular_velocity = Vector3.ZERO
	if _boat is Node3D:
		(_boat as Node3D).look_at(Vector3(vc.x, 3.0, vc.z), Vector3.UP)
	if _cycle != null:
		_cycle.set("time_of_day", 0.875)


func _on_resume() -> void:
	if _started:
		visible = false


func _on_quit() -> void:
	get_tree().quit()


## Wreck polling: the boat raises `wrecked` and freezes; this screen
## answers it. Runs while paused (PROCESS_MODE_ALWAYS) so nothing slips.
func _process(_delta: float) -> void:
	if not _started or _gameover_shown:
		return
	if _boat == null:
		_boat = get_node_or_null(boat_path)
		return
	if bool(_boat.get("wrecked")):
		_show_gameover()


func _build_gameover() -> void:
	_gameover = Control.new()
	_gameover.name = "GameOver"
	_gameover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gameover.visible = false

	var dim := ColorRect.new()
	dim.name = "GameoverDim"
	dim.color = Color(0.05, 0.0, 0.0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gameover.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gameover.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "THE REACH CLAIMS YOU"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "The hull is gone. The waters keep what they catch."
	sub.add_theme_font_size_override("font_size", 16)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var again := Button.new()
	again.name = "SailAgain"
	again.text = "Sail Again  (Iron Gull)"
	again.pressed.connect(_on_sail_again)
	box.add_child(again)

	var quit := Button.new()
	quit.name = "Quit"
	quit.text = "Quit"
	quit.pressed.connect(_on_quit)
	box.add_child(quit)

	add_child(_gameover)


func _show_gameover() -> void:
	_gameover_shown = true
	if _gameover != null:
		_gameover.visible = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_music_play()


func _on_sail_again() -> void:
	if _boat != null and _boat.has_method("request_respawn"):
		_boat.call("request_respawn")
	_gameover_shown = false
	if _gameover != null:
		_gameover.visible = false
	visible = false
	get_tree().paused = false
	_music_voyage()


## Menu theme: looped under the start screen and the death screen,
## silent on open water. Short fades so starts and stops never click.
func _build_music() -> void:
	_music = AudioStreamPlayer.new()
	_music.name = "MenuMusic"
	_music.volume_db = MUSIC_DB
	var stream := load(MENU_MUSIC) as AudioStreamOggVorbis
	if stream != null:
		stream.loop = true
	_music.stream = stream
	add_child(_music)
	_music_play()


func _music_play() -> void:
	if _music == null or _music.stream == null:
		return
	if _music.playing:
		return
	_music.volume_db = MUSIC_DB - 24.0
	_music.play()
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", MUSIC_DB, 1.5)


func _music_voyage() -> void:
	if _music == null or _music.stream == null:
		return
	if not _music.playing:
		_music.volume_db = MUSIC_VOYAGE_DB - 24.0
		_music.play()
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", MUSIC_VOYAGE_DB, 1.5)


## Ocean surf: always on, carried by the Sound setting like the calls.
func _build_ocean() -> void:
	_ocean = AudioStreamPlayer.new()
	_ocean.name = "OceanWaves"
	_ocean.volume_db = OCEAN_DB
	_ocean.bus = "Sea"
	var stream := load(OCEAN_WAVES) as AudioStreamOggVorbis
	if stream != null:
		stream.loop = true
	_ocean.stream = stream
	add_child(_ocean)
	if _ocean.stream != null:
		_ocean.play()


func _save() -> void:
	var cfg := ConfigFile.new()
	for key in _rows:
		cfg.set_value("settings", key, (_rows[key]["slider"] as HSlider).value)
	if _test_toggle != null:
		cfg.set_value("settings", "test_mode", _test_toggle.button_pressed)
	cfg.save(SAVE_PATH)


func _load() -> void:
	_refresh()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in _rows:
		if cfg.has_section_key("settings", key):
			var v := float(cfg.get_value("settings", key))
			_set_row(key, v)
			_on_slider(v, key)
	if cfg.has_section_key("settings", "test_mode"):
		var t := bool(cfg.get_value("settings", "test_mode"))
		if _test_toggle != null:
			_test_toggle.set_pressed_no_signal(t)
		_on_test_mode(t)
