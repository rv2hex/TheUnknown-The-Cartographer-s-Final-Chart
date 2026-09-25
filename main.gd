extends Node3D

## Mouselock orbit camera: click to capture the mouse and look freely around
## the ship, Esc releases. WASD keeps sailing the ship in boat.gd.
## When idle, the orbit eases back behind the ship's heading.

@export var boat_path := NodePath("Boat")
@export var camera_path := NodePath("Camera3D")
@export var distance := 28.0
@export var height := 14.0
@export var mouse_sensitivity := 0.0025
## Seconds without mouse input before the view drifts back behind the ship.
@export var recenter_delay := 3.0

var _base_yaw := 0.0
var _orbit_yaw := 0.0
var _pitch := 0.45
var _idle := 99.0

@onready var _boat: Node3D = get_node_or_null(boat_path)
@onready var _camera: Camera3D = get_node_or_null(camera_path)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_orbit_yaw -= mm.relative.x * mouse_sensitivity
			_pitch = clampf(_pitch + mm.relative.y * mouse_sensitivity, 0.05, 1.25)
			_idle = 0.0
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if _boat == null or _camera == null:
		return
	_idle += delta
	if _idle > recenter_delay:
		_orbit_yaw = lerp_angle(_orbit_yaw, 0.0, min(1.0, 0.6 * delta))
	var boat_yaw: float = _boat.global_transform.basis.get_euler().y
	_base_yaw = lerp_angle(_base_yaw, boat_yaw, min(1.0, 2.0 * delta))
	var yaw := _base_yaw + _orbit_yaw
	var horiz := cos(_pitch) * distance
	var lift := height + sin(_pitch - 0.45) * distance
	var target: Vector3 = _boat.global_position + Vector3(sin(yaw) * horiz, lift, cos(yaw) * horiz)
	_camera.global_position = _camera.global_position.lerp(target, min(1.0, 5.0 * delta))
	_camera.look_at(_boat.global_position + Vector3.UP * 3.0)
