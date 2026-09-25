class_name CrabMountain
extends Node3D

## Far-reef crab: sleeps until the ship comes close, rears up slowly (+20),
## then one verdict wave if the crew moved — otherwise it sinks back down
## and is gone for the session. The whole reef fades in and out with
## distance exactly like the islands.

const MODEL_PATH := "res://models/crab_mountain/scene.gltf"
const ANIM_NAME := "CINEMA_4D_Main"
const CRAB_SOUND := "res://sounds/crab_roar.mp3"

enum State { SLEEP, WAKE, SUNK }

@export var ship_path := NodePath("../Boat")
## Ship distance that wakes the crab. No warning sounds: the reef gives
## no quarter and no notice.
@export var wake_radius := 260.0
## How high the crab rears (Crab-root units) while waking.
@export var rise_height := 20.0
## Seconds the rise takes: one animation window, one verdict at the top.
@export var rise_seconds := 6.0
## The kill wave at the verdict: lethal, crossing the whole reef.
@export var kill_damage := 9999.0
## Kill-wave shove impulse.
@export var kill_shove := 60000.0
## Ship speed that counts as holding still.
@export var still_speed := 1.5
## Fleeing past this also ends the encounter, for good.
@export var give_up_radius := 700.0
## Seconds the final sink takes.
@export var sink_seconds := 10.0
## How far the reef buries itself when it leaves for good (Crab-root
## units; comfortably deeper than the half-sunk waterline).
const SINK_DEPTH := 250.0
## Contact scrape damage per second.
@export var contact_dps := 4.0
## Roar base level.
@export var sound_db := -10.0
## Island-style distance fade.
const FADE_HIDE := 1000.0
const FADE_SHOW := 450.0
## Far LOD: skip the whole tick beyond this camera distance.
const CRAB_SKIP_DIST := 1200.0

## Read by ShipHUD to fire the reef story card, once.
var has_woken := false

var _state: int = State.SLEEP
var _ship: Node3D = null
var _has_api := false
var _model_root: Node3D = null
var _anim: AnimationPlayer = null
var _sound: AudioStreamPlayer3D = null
## Distance-proof wake roar: same clip, non-positional, always lands.
var _roar_flat: AudioStreamPlayer = null
var _body_radius := 45.0
var _clock := 0.0
var _lift := 0.0
var _moved := false
var _gone := false
var _fade_mats: Array = []
var _fade_lights: Array = []


static func _has_scene_model(n: Node) -> bool:
	if n is MeshInstance3D:
		return true
	for c in n.get_children():
		if _has_scene_model(c):
			return true
	return false


func _ready() -> void:
	var home := Geo.world_of_ll(Geo.CRAB_REEF)
	global_position = Vector3(home.x, 0.0, home.z)
	_model_root = Node3D.new()
	_model_root.name = "CrabModel"
	add_child(_model_root)
	if _has_scene_model(self):
		_adopt_scene_model()
	else:
		var packed := load(MODEL_PATH) as PackedScene
		if packed != null:
			var inst := packed.instantiate() as Node3D
			_model_root.add_child(inst)
			_recenter_model(inst)
			_anim = _find_anim(inst)
	_start_anim()
	_build_sound()
	_check_placements()
	_collect_fade(self)


## Scene-model adoption: the scene already holds the crab model. It is
## recentered under an inner node. Nothing here rescales anything: the
## Crab root carries the overall 0.5 scale.
func _adopt_scene_model() -> void:
	var inner := Node3D.new()
	inner.name = "CrabInner"
	_model_root.add_child(inner)
	for c in get_children():
		if c == _model_root or c is Light3D:
			continue
		remove_child(c)
		inner.add_child(c)
	var boxes: Array = []
	_collect_aabbs(inner, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return
	var box: AABB = boxes[0]
	for i in range(1, boxes.size()):
		box = box.merge(boxes[i])
	_place_model(inner, box)
	_anim = _find_anim(inner)


## Fallback path: center the loaded instance the same way.
func _recenter_model(inst: Node3D) -> void:
	var boxes: Array = []
	_collect_aabbs(inst, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return
	var box: AABB = boxes[0]
	for i in range(1, boxes.size()):
		box = box.merge(boxes[i])
	_place_model(inst, box)


## Center the model on the root with its base halfway below the waterline.
func _place_model(holder: Node3D, box: AABB) -> void:
	var center := box.get_center()
	holder.position = Vector3(-center.x, -box.position.y - box.size.y * 0.5, -center.z)
	_body_radius = maxf(box.size.x, box.size.z) * 0.5 * global_transform.basis.get_scale().x


func _collect_aabbs(n: Node, parent_xf: Transform3D, out: Array) -> void:
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mesh := (n as MeshInstance3D).mesh
		if mesh != null:
			out.append(xf * mesh.get_aabb())
	for c in n.get_children():
		_collect_aabbs(c, xf, out)


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		var ap := n as AnimationPlayer
		if ap.has_animation(ANIM_NAME):
			return ap
	for c in n.get_children():
		var f := _find_anim(c)
		if f != null:
			return f
	if n is AnimationPlayer:
		return n as AnimationPlayer
	return null


func _start_anim() -> void:
	if _anim == null:
		push_warning("CrabMountain: no '%s' AnimationPlayer found; the reef will sit still." % ANIM_NAME)
		return
	var clip := _anim.get_animation(ANIM_NAME)
	if clip != null:
		clip.loop_mode = Animation.LOOP_LINEAR
	# Asleep means asleep: hold frame zero until the wake call plays it.
	_anim.play(ANIM_NAME)
	_anim.pause()
	_anim.speed_scale = 0.6


func _build_sound() -> void:
	_sound = AudioStreamPlayer3D.new()
	_sound.name = "CrabVoice"
	_sound.stream = load(CRAB_SOUND) as AudioStreamMP3
	_sound.unit_size = 60.0
	_sound.max_distance = 1500.0
	_sound.volume_db = sound_db
	GameMenu.ensure_audio_buses()
	_sound.bus = "Sea"
	add_child(_sound)
	_roar_flat = AudioStreamPlayer.new()
	_roar_flat.name = "CrabRoarFlat"
	_roar_flat.stream = _sound.stream
	_roar_flat.volume_db = 0.0
	_roar_flat.bus = "Sea"
	add_child(_roar_flat)


func _roar() -> void:
	if _roar_flat != null and _roar_flat.stream != null and not _roar_flat.playing:
		_roar_flat.play()
	if _sound == null or _sound.stream == null or _sound.playing:
		return
	_sound.play()


## Island-style fade over the whole reef, exactly like the islands.
func _collect_fade(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null:
			for i in range(mesh.get_surface_count()):
				var src := mi.get_surface_override_material(i)
				if src == null:
					src = mesh.surface_get_material(i)
				if src is StandardMaterial3D:
					var dup := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mi.set_surface_override_material(i, dup)
					_fade_mats.append({"mat": dup, "base_a": dup.albedo_color.a})
	if n is Light3D:
		_fade_lights.append({"light": n, "base_e": (n as Light3D).light_energy})
	for c in n.get_children():
		_collect_fade(c)


func _process(_delta: float) -> void:
	if _gone:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or (_fade_mats.is_empty() and _fade_lights.is_empty()):
		return
	var d: float = cam.global_position.distance_to(global_position)
	var alpha := clampf((FADE_HIDE - d) / (FADE_HIDE - FADE_SHOW), 0.0, 1.0)
	for f in _fade_mats:
		var mat := f["mat"] as StandardMaterial3D
		if mat != null and is_instance_valid(mat):
			var c := mat.albedo_color
			mat.albedo_color = Color(c.r, c.g, c.b, float(f["base_a"]) * alpha)
	for l in _fade_lights:
		var light := l["light"] as Light3D
		if light != null and is_instance_valid(light):
			light.light_energy = float(l["base_e"]) * alpha
	visible = alpha > 0.003


func _physics_process(delta: float) -> void:
	if _gone:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		if cam.global_position.distance_to(global_position) > CRAB_SKIP_DIST:
			return
	if _ship == null:
		_ship = get_node_or_null(ship_path) as Node3D
		if _ship != null:
			_has_api = _ship.has_method("take_damage")
		return
	if _ship == null or not _has_api:
		return
	_clock += delta
	var to_ship: Vector3 = _ship.global_position - global_position
	to_ship.y = 0.0
	var dist := to_ship.length()
	var dir := Vector3.ZERO
	if dist > 0.01:
		dir = to_ship / dist
	var ship_speed := 0.0
	if _ship is RigidBody3D:
		ship_speed = (_ship as RigidBody3D).linear_velocity.length()

	match _state:
		State.SLEEP:
			if dist < wake_radius:
				_state = State.WAKE
				_moved = false
				has_woken = true
				_roar()
				if _anim != null:
					_anim.play(ANIM_NAME)
		State.WAKE:
			_lift = minf(_lift + rise_height * delta / rise_seconds, rise_height)
			_face(dir, delta, 0.6)
			_scrape(dist, dir, delta)
			if ship_speed > still_speed:
				_moved = true
			if dist > give_up_radius:
				_state = State.SUNK
			elif _lift >= rise_height:
				# One animation, one verdict: moved and the wave takes you
				# in this frame; held still and the reef goes back down.
				if _moved:
					_kill_wave(dir)
				_state = State.SUNK
		State.SUNK:
			_lift = maxf(_lift - SINK_DEPTH * delta / sink_seconds, -SINK_DEPTH)
			if _anim != null:
				_anim.speed_scale = maxf(_anim.speed_scale - delta * 0.4, 0.1)
			if _lift <= -SINK_DEPTH + 1.0:
				_sink_forever()
				return
	var bob := 0.0
	if _state == State.WAKE:
		bob = sin(_clock * 0.5) * 1.5
	_model_root.position.y = bob + _lift


## The verdict wave: lethal and reef-wide. The roar is already playing and
## nothing stops it — it sounds out over the dive until the clip ends.
func _kill_wave(dir_from_crab: Vector3) -> void:
	_roar()
	if _ship == null or not _has_api:
		return
	_ship.call("take_damage", kill_damage)
	if _ship.has_method("add_shove"):
		var away: Vector3 = dir_from_crab.normalized()
		_ship.call("add_shove", away * kill_shove + Vector3.UP * kill_shove * 0.4)


## Cheap radial body block: push + scrape, never lethal by itself.
func _scrape(dist: float, dir: Vector3, delta: float) -> void:
	if dist >= _body_radius or _ship == null:
		return
	_ship.call("take_damage", contact_dps * delta)
	if _ship.has_method("add_shove"):
		_ship.call("add_shove", dir * 3000.0 * delta)


func _face(dir: Vector3, delta: float, rate: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, rate * delta))


## Gone for the session: buried, silent, still, and out of every tick.
func _sink_forever() -> void:
	_gone = true
	visible = false
	if _anim != null:
		_anim.stop()
	set_physics_process(false)


## Spec guard: editor saves silently rewrite scene transforms, so the reef
## audits its root on every boot. Root y 0 scale 0.5 — drift is a warning.
func _check_placements() -> void:
	var rs := global_transform.basis.get_scale()
	if absf(global_position.y) > 0.01 or absf(rs.x - 0.5) > 0.01:
		push_warning("CrabMountain: root off spec (y=%.2f scale=%.2f); want y 0 scale 0.5." % [global_position.y, rs.x])
