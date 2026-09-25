class_name ShipBoat
extends RigidBody3D

## A Dutch tall ship sailed as a boat. Floats on the boujie shader waves by
## sampling the same Gerstner math on the CPU (see WaterSampler) at hull
## probe points laid along the 22 m hull.
##
## Why probes and a box shape: the visible surface is displaced in the GPU
## vertex shader, so no static shape can match it. Buoyancy probes against the
## shared wave resources ARE the realistic collision here, and they stay exact
## because both sides read the same GerstnerWave resources from the designer.
## The box collision only handles ship-vs-world contact, never the water.

@export var designer_path := NodePath("../DeepOcean/WaterMaterialDesigner")
## Upward acceleration per meter of probe submersion
## (equilibrium draft = g / (n * gain); 9.8 / (5 * 2.0) ~= 1 m).
@export var buoyancy_gain := 2.0
## Velocity damping per submerged probe, scaled by mass.
@export var water_drag := 6.0
## Torque aligning the hull with the wave normal.
@export var align_strength := 4.0
## Forward acceleration at full throttle (strong following wind).
@export var engine_power := 8.0
## Turn acceleration at full rudder.
@export var rudder_power := 6.0
## Always-on self-righting (metacentric stiffness): pulls the mast back to
## vertical at any heel, so the ship sways but never sits heeled over.
@export var righting_gain := 50.0
## Forward water drag as a fraction of sideways drag. The hull glides ahead
## but the keel bites sideways, like a real sailing ship.
@export var forward_drag_factor := 0.15
## Max lean from vertical, degrees. The ship may wobble this far, never further.
@export var max_tilt_deg := 40.0
## Upright wall once past max tilt (square-root: stiff right at the cap,
## saturating beyond; always active even airborne). Wobble inside the cap is
## pure wave physics, untouched.
@export var rescue_gain := 200.0
## Hard cap on spin rate so a wave slam can't windmill the hull.
@export var max_spin := 1.0
## Per-probe submersion that counts (deck awash sheds water, caps slam torque).
@export var max_probe_depth := 2.0
## Hull integrity. Miasma zones corrode it; wreck at zero respawns at Iron Gull.
@export var max_hull_hp := 100.0
## Hull regained per second after 5 s without damage.
@export var hull_regen := 2.0

var hull_hp := 100.0
## Set the moment the hull gives out (or the sea takes the ship). The
## game-over screen owns what happens next; physics just holds the wreck.
var wrecked := false
var _respawn_queued := false
## Speed multiplier set by the islands (saddle miasma slows the ship).
var sea_slow_mult := 1.0
var _hurt_timer := 99.0

@export var front_lamp_path := NodePath("FrontLamp")
@export var back_lamp_path := NodePath("Backlamp")

## Deck lamps. L toggles them for night sailing.
var lamps_on := true

## Test mode (settings menu toggle): ~3.2x thrust for ~100 km/h runs
## plus an invulnerable hull. Depth wreck still applies so sinking stays
## testable.
var test_mode := false
## Thrust multiplier that lands top speed near 100 km/h (drag is linear,
## so velocity scales with thrust; base tops out near 32 km/h).
const TEST_THRUST_MULT := 3.2

# Bow faces -Z (ship visual is rotated +90 deg about Y). Probes sit just
# above the keel (keel at y = -2) at bow, stern, both beams, and midships.
const PROBES: Array[Vector3] = [
	Vector3(0.0, -1.5, -9.0),
	Vector3(0.0, -1.5, 9.0),
	Vector3(-2.0, -1.5, 0.0),
	Vector3(2.0, -1.5, 0.0),
	Vector3(0.0, -1.5, 0.0),
]

@onready var _designer: WaterMaterialDesigner = get_node_or_null(designer_path) as WaterMaterialDesigner


func _ready() -> void:
	_apply_lamps()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_L:
			lamps_on = not lamps_on
			_apply_lamps()


func _apply_lamps() -> void:
	var front := get_node_or_null(front_lamp_path)
	if front is VisualInstance3D:
		(front as VisualInstance3D).visible = lamps_on
	var back := get_node_or_null(back_lamp_path)
	if back is VisualInstance3D:
		(back as VisualInstance3D).visible = lamps_on


func take_damage(amount: float) -> void:
	if wrecked or test_mode:
		return
	if amount > 0.0:
		hull_hp = maxf(0.0, hull_hp - amount)
		_hurt_timer = 0.0


## Called by the game-over screen: restore the hull now, teleport on the
## next physics tick (transform writes belong in _integrate_forces).
func request_respawn() -> void:
	hull_hp = max_hull_hp
	_hurt_timer = 99.0
	wrecked = false
	freeze = false
	_respawn_queued = true


## Knock impulse queued by mob attacks, applied on the next physics tick.
var _pending_shove := Vector3.ZERO


func add_shove(impulse: Vector3) -> void:
	_pending_shove += impulse


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _designer == null:
		_designer = get_node_or_null(designer_path) as WaterMaterialDesigner
		if _designer == null:
			return
	var waves: Array = _designer.height_waves
	if _pending_shove.length_squared() > 0.0:
		state.apply_central_impulse(_pending_shove)
		_pending_shove = Vector3.ZERO
	if waves.is_empty():
		return

	var time := Time.get_ticks_msec() / 1000.0
	_hurt_timer += state.step
	if _hurt_timer > 5.0:
		hull_hp = minf(max_hull_hp, hull_hp + hull_regen * state.step)
	var basis_t := state.transform.basis
	var origin := state.transform.origin
	var submerged := 0

	for offset in PROBES:
		var probe := origin + basis_t * offset
		var raw_depth: float = WaterSampler.height_at(Vector2(probe.x, probe.z), time, waves) - probe.y
		if raw_depth <= 0.0:
			continue
		submerged += 1
		var depth: float = minf(raw_depth, max_probe_depth)
		var rel := probe - origin
		var point_vel := state.linear_velocity + state.angular_velocity.cross(rel)
		var fwd := -basis_t.z
		var v_fwd := fwd * point_vel.dot(fwd)
		var v_grip := point_vel - v_fwd
		var force := Vector3.UP * (buoyancy_gain * depth * mass)
		force -= (v_grip + v_fwd * forward_drag_factor) * (water_drag * mass / PROBES.size())
		state.apply_force(force, rel)

	var up_now := basis_t.y
	var tilt: float = up_now.angle_to(Vector3.UP)
	var max_tilt := deg_to_rad(max_tilt_deg)

	if submerged > 0:
		var fraction := float(submerged) / PROBES.size()
		var center_y := WaterSampler.height_at(Vector2(origin.x, origin.z), time, waves)
		var wave_normal := WaterSampler.normal_at(Vector2(origin.x, origin.z), time, waves)
		# Follow the swell but biased upright, so a steep wave face can't flip us.
		var target_up := (wave_normal + Vector3.UP).normalized()
		var torque := up_now.cross(target_up) * (align_strength * mass * fraction)
		# Metacentric righting: always pulls the mast back to vertical.
		torque += up_now.cross(Vector3.UP) * (righting_gain * mass * fraction)
		torque -= state.angular_velocity * (water_drag * mass * 0.4 * fraction)
		state.apply_torque(torque)
		_apply_drive(state, basis_t, fraction)
		# Extra heave damping toward the surface keeps the ride from ringing.
		var heave_error := center_y - origin.y
		state.apply_central_force(Vector3.UP * (heave_error * mass * fraction))

	# Anti-capsize: always active (even airborne), quadratic past the cap,
	# so the hull wobbles to max_tilt but can never settle inverted.
	if tilt > max_tilt:
		var over: float = (tilt - max_tilt) / (PI - max_tilt)
		var rescue_axis := up_now.cross(Vector3.UP)
		if rescue_axis.length() < 0.001:
			rescue_axis = (basis_t.x + basis_t.z).normalized()
		else:
			rescue_axis = rescue_axis.normalized()
		state.apply_torque(rescue_axis * (sqrt(over) * rescue_gain * mass))
	# Angular damping always on, growing with spin rate and doubled past the
	# cap: gentle wobble stays lively, tumble energy dies fast.
	var spin: float = state.angular_velocity.length()
	var damp := water_drag * mass * (1.0 + 4.0 * spin) * (1.0 if tilt <= max_tilt else 2.0)
	state.apply_torque(-state.angular_velocity * damp)

	# Cap spin always (even airborne) so a slam can't windmill the hull.
	if state.angular_velocity.length() > max_spin:
		state.angular_velocity = state.angular_velocity.normalized() * max_spin

	# Pitch lock: the bow never dips or rears, not even a little. Rebuild
	# the basis from yaw + roll only (YXZ euler, pitch forced to zero)
	# and bleed off any pitch spin, so no tilt can accumulate or stick.
	# Roll, rescue, and damping above are untouched.
	if not wrecked:
		var e := basis_t.get_euler()
		var flat := Basis.from_euler(Vector3(0.0, e.y, e.z))
		var xf := state.transform
		xf.basis = flat
		state.transform = xf
		var ang := state.angular_velocity
		ang -= flat.x * ang.dot(flat.x)
		state.angular_velocity = ang

	# The ocean is infinite but physics is not: a lost ship or an empty hull
	# wrecks the voyage. No silent respawn — the game-over screen answers.
	if _respawn_queued:
		var reset := state.transform
		var home := Geo.world_of_ll(Geo.IRON_GULL)
		reset.origin = Vector3(home.x, 3.0, home.z)
		reset.basis = Basis.IDENTITY
		state.transform = reset
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_respawn_queued = false
	elif not wrecked and (origin.y < -30.0 or hull_hp <= 0.0):
		wrecked = true
		freeze = true
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO


func _apply_drive(state: PhysicsDirectBodyState3D, basis_t: Basis, fraction: float) -> void:
	var throttle := _axis(KEY_W, KEY_S, "ui_up", "ui_down")
	var rudder := _axis(KEY_A, KEY_D, "ui_left", "ui_right")
	if throttle != 0.0:
		var thrust := throttle * engine_power * sea_slow_mult * mass * fraction
		if test_mode:
			thrust *= TEST_THRUST_MULT
		state.apply_central_force(-basis_t.z * thrust)
	if rudder != 0.0:
		state.apply_torque(Vector3.UP * (rudder * rudder_power * mass * fraction))


func _axis(pos_key: Key, neg_key: Key, pos_action: StringName, neg_action: StringName) -> float:
	var value := 0.0
	if Input.is_key_pressed(pos_key) or Input.is_action_pressed(pos_action):
		value += 1.0
	if Input.is_key_pressed(neg_key) or Input.is_action_pressed(neg_action):
		value -= 1.0
	return value
