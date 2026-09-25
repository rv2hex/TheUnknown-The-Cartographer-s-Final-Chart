class_name MobDirector
extends Node3D

## One owner for the living Reach. A valley of sky jellies fills the middle
## of the chart after dark and sinks by day; burn the lamps near it and the
## whole valley glides down on the ship, slow, and a bell that closes over
## the deck drags the hull under. On the water, a shy whale circles singing
## while random ocean voices drift past. Drowning flows through the ship's
## existing add_shove()/wreck path.

@export var ship_path := NodePath("../Boat")
@export var cycle_path := NodePath("../DayNightCycle")
## Bells filling the valley sky, all sizes.
const VALLEY_BELLS := 18
## Valley-ahead caution, well before the lamps can draw the pack.
const VALLEY_WARN_RADIUS := 400.0
## At most this many bells off-orbit at once: the sky never empties.
const MAX_STAGED := 3
## Dusk/dawn hysteresis on sun elevation so the pack doesn't flicker.
const NIGHT_ON_ELEV := -0.06
const NIGHT_OFF_ELEV := 0.03

const WHALE_SOUND := "res://sounds/whale_call.wav"
const OCEAN_AMB_1 := "res://sounds/diving_whales.wav"
const OCEAN_AMB_2 := "res://sounds/dolphin_scream.wav"
const JELLY_SOUND := "res://sounds/jellyfish.wav"
## Valley hum carries this far; full voice at the disc.
const JELLY_HEAR_DIST := 900.0

var _ship: Node3D = null
var _has_api := false
var _jelly_scene: PackedScene
## Read by ShipHUD to flash "TURN LAMPS OFF". True while any valley bell is
## closing in on or grabbing the ship (lamps burning).
var giant_warning_active := false
var _pack: Array = []
## Round-robin kill token: exactly one bell dives at a time.
var _diver: ValleyJelly = null
var _dive_count := 0
var _cycle: DayNightCycle = null
var _night := true
## Peaceful sea life: one shy whale visit at a time, plus random ocean
## voices (deep dives, distant screams) drifting past on their own schedule.
var _whale_sound: AudioStream = null
var _sea: SeaVisit = null
var _sea_timer := 0.0
var _amb_sounds: Array = []
var _amb_timer := 0.0
## Looped valley hum, positional at the disc, swelling on approach.
var _valley_voice: AudioStreamPlayer3D = null
## Flat presence layer: same call, distance-proof, heard while warned.
var _valley_flat: AudioStreamPlayer = null


func _ready() -> void:
	_jelly_scene = load("res://models/jellyfish/scene.gltf") as PackedScene
	_whale_sound = load(WHALE_SOUND) as AudioStream
	for amb in [OCEAN_AMB_1, OCEAN_AMB_2]:
		var stream := load(amb) as AudioStream
		if stream != null:
			_amb_sounds.append(stream)
		else:
			push_warning("MobDirector: ocean voice missing at " + amb)
	_amb_timer = randf_range(20.0, 40.0)
	_sea_timer = randf_range(25.0, 45.0)
	for i in range(VALLEY_BELLS):
		var member := ValleyJelly.new()
		member.director = self
		member.setup_valley(_jelly_scene, float(i) * 2.39996)
		add_child(member)
		_pack.append(member)
	_build_valley_voice()


## The valley hums after dark: looped call pinned to the disc, swelling
## as the ship closes in, silent by day or far away.
func _build_valley_voice() -> void:
	_valley_voice = AudioStreamPlayer3D.new()
	_valley_voice.name = "ValleyVoice"
	var stream := load(JELLY_SOUND) as AudioStreamWAV
	if stream == null:
		push_warning("MobDirector: valley sound missing at " + JELLY_SOUND)
		return
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_valley_voice.stream = stream
	_valley_voice.unit_size = 150.0
	_valley_voice.max_distance = JELLY_HEAR_DIST
	_valley_voice.volume_db = -40.0
	GameMenu.ensure_audio_buses()
	_valley_voice.bus = "Sea"
	_valley_voice.position = ValleyJelly.center()
	add_child(_valley_voice)
	_valley_voice.play()
	_valley_flat = AudioStreamPlayer.new()
	_valley_flat.name = "ValleyPresence"
	_valley_flat.stream = stream
	_valley_flat.volume_db = -40.0
	_valley_flat.bus = "Sea"
	add_child(_valley_flat)


## Distance culling: when the ship is far from the camera,
## skip expensive AI tick for mobs. Night state still updates.
const MOB_SKIP_DIST := 1500.0

func _physics_process(delta: float) -> void:
	_update_night()
	if _ship == null:
		_ship = get_node_or_null(ship_path) as Node3D
		if _ship != null:
			_has_api = _ship.has_method("take_damage")
		for member in _pack:
			(member as ValleyJelly).ship = _ship
		if _sea != null:
			_sea.ship = _ship
		return
	if not _has_api:
		giant_warning_active = false
		return
	# Distance culling: skip heavy AI when far from camera. The valley
	# voice stays fresh regardless so the hum never freezes mid-swell.
	_tick_valley_voice()
	var cam := get_viewport().get_camera_3d()
	if cam != null and _ship is Node3D:
		if cam.global_position.distance_to(_ship.global_position) > MOB_SKIP_DIST:
			return
	giant_warning_active = false
	for member in _pack:
		var bell := member as ValleyJelly
		bell.tick(delta, _night)
		if bell.warning:
			giant_warning_active = true
	_manage_diver()
	_early_valley_warning()
	_tick_sea(delta)
	_tick_ambient(delta)


## One diver at a time, round-robin over the staged bells. Every fourth
## dive is a grab run instead of a strike.
func _manage_diver() -> void:
	if _diver != null and (not is_instance_valid(_diver) or _diver.dive_done()):
		_diver = null
	if _diver != null:
		return
	for member in _pack:
		var bell := member as ValleyJelly
		if bell.ready_to_dive():
			_diver = bell
			_dive_count += 1
			bell.start_dive(_dive_count % 4 == 0)
			return


## Bells currently off-orbit (staging, diving, striking, grabbing).
func staged_count() -> int:
	var n := 0
	for member in _pack:
		if (member as ValleyJelly).is_off_orbit():
			n += 1
	return n


func _early_valley_warning() -> void:
	if giant_warning_active or not _night or not _ship is Node3D:
		return
	var c := ValleyJelly.center()
	var sp: Vector3 = _ship.global_position
	if Vector2(sp.x - c.x, sp.z - c.z).length() < VALLEY_WARN_RADIUS:
		giant_warning_active = true


## Hum follows the ship: full voice at the disc, gone by hear range,
## silent while the valley sleeps by day.
func _tick_valley_voice() -> void:
	if _valley_voice == null or _ship == null:
		return
	if not _valley_voice.playing:
		_valley_voice.play()
	var target_db := -40.0
	if _night and _ship is Node3D:
		var c := ValleyJelly.center()
		var sp: Vector3 = _ship.global_position
		var d := Vector2(sp.x - c.x, sp.z - c.z).length()
		if d < JELLY_HEAR_DIST:
			target_db = lerpf(0.0, -12.0, clampf(d / JELLY_HEAR_DIST, 0.0, 1.0))
	_valley_voice.volume_db = lerpf(_valley_voice.volume_db, target_db, 0.1)
	if _valley_flat != null:
		if giant_warning_active and not _valley_flat.playing:
			_valley_flat.play()
			_valley_flat.volume_db = -14.0
		elif not giant_warning_active and _valley_flat.playing:
			_valley_flat.stop()


## Peaceful rotation: one shy whale at a time, cruising past the ship,
## then a quiet cooldown before the next.
func _tick_sea(delta: float) -> void:
	if _sea != null:
		_sea.tick(delta)
		if _sea.done:
			_sea.queue_free()
			_sea = null
			_sea_timer = randf_range(60.0, 140.0)
		return
	if _ship == null or not _seas_ready():
		return
	_sea_timer -= delta
	if _sea_timer <= 0.0:
		_spawn_sea()


func _seas_ready() -> bool:
	return _whale_sound != null


func _spawn_sea() -> void:
	var sp: Vector3 = _ship.global_position
	var bearing := randf() * TAU
	var swim := Vector3(cos(bearing), 0, sin(bearing))
	var side := Vector3(-swim.z, 0, swim.x)
	# Far berth: beyond whale hearing, so visits fade in, never pop in.
	var from := Vector3(sp.x + swim.x * 700.0, 0, sp.z + swim.z * 700.0)
	# Straight line past the ship, offset ~35 m abeam so the lit pod
	# stays near the player without ever touching the hull.
	var to := Vector3(sp.x - swim.x * 900.0 + side.x * 35.0, 0, sp.z - swim.z * 900.0 + side.z * 35.0)
	_sea = SeaVisit.new()
	_sea.ship = _ship
	_sea.setup_whale(_whale_sound, from, to)
	add_child(_sea)


## Random ocean voices: deep dives and distant screams drift past on their
## own schedule — positional one-shots that free themselves on finish.
func _tick_ambient(delta: float) -> void:
	if _ship == null or _amb_sounds.is_empty():
		return
	_amb_timer -= delta
	if _amb_timer > 0.0:
		return
	_amb_timer = randf_range(45.0, 110.0)
	var stream := _amb_sounds[randi() % _amb_sounds.size()] as AudioStream
	if stream == null:
		return
	var sp: Vector3 = _ship.global_position
	var bearing := randf() * TAU
	var dist := randf_range(300.0, 700.0)
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = 120.0
	p.max_distance = 900.0
	p.volume_db = -8.0
	GameMenu.ensure_audio_buses()
	p.bus = "Sea"
	add_child(p)
	p.global_position = Vector3(sp.x + cos(bearing) * dist, 0.0, sp.z + sin(bearing) * dist)
	p.play()
	p.finished.connect(p.queue_free)


## Day hides the pack: hysteresis on sun elevation, defaulting to night
## if the cycle is unreachable so nothing vanishes by accident.
func _update_night() -> void:
	if _cycle == null:
		_cycle = get_node_or_null(cycle_path) as DayNightCycle
		if _cycle == null:
			return
	var elev := _cycle.sun_elevation(float(_cycle.time_of_day))
	if _night and elev > NIGHT_OFF_ELEV:
		_night = false
	elif not _night and elev < NIGHT_ON_ELEV:
		_night = true


static func find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f := find_player(c)
		if f != null:
			return f
	return null


class ValleyJelly:
	extends Node3D
	## One valley bell. Fills the sky on a wide slow orbit after dark and
	## sinks by day. Burning lamps near the valley stages the pack; the
	## director then sends divers down one at a time — a diving bell spins
	## up and strikes the hull, climbs back, and the token passes on until
	## the ship dies. Every fourth dive grabs and drowns instead. Kill the
	## lamps (or leave the leash) and everyone climbs home. Never ranges:
	## ship and bell both past the leash breaks every chase, so the pack
	## can't reach the islands.
	## Native bell is ~8 m; valley scales run 2..20 for a sky of all sizes.
	enum Phase { ORBIT, STAGE, DIVE, GRAB, RETURN }

	## The disc the bells call home.
	const VALLEY_RADIUS := 220.0
	## Chase, dive, and grab all die past this distance from the valley center.
	const LEASH_RADIUS := 300.0
	## Lamp-lit ship inside this range of the center stages the pack.
	const ATTRACT_RADIUS := 250.0
	## Staging hover height over the ship.
	const STAGE_ALT := 60.0
	## Slow station-keeping glide for orbit and return legs.
	const ORBIT_SPEED := 6.0
	## Run-in to the staging hover: fast enough to read as intent.
	const STAGE_SPEED := 18.0
	## The dive: fast, spinning, single bell at a time.
	const DIVE_SPEED := 35.0
	## Strike damage per hit; the cycle repeats until the hull gives out.
	const STRIKE_DAMAGE := 15.0
	const STRIKE_SHOVE := 12000.0
	## Bell-over-deck distance that counts as a hit or grab.
	const GRAB_RADIUS := 22.0
	## Per-second drowning force while grabbed: down plus inward.
	const GRAB_DOWN := 60000.0
	const GRAB_IN := 20000.0
	## Fade band: invisible past 500 m, fully solid inside 250 m.
	const FADE_HIDE := 500.0
	const FADE_SHOW := 250.0
	## Day migration: sink to this depth, rise back after dark.
	const SINK_DEPTH := -40.0
	const SINK_RATE := 12.0
	const RISE_SPEED := 8.0
	const SURFACE_Y := -5.0

	static func center() -> Vector3:
		return Geo.world_of_ll(Geo.JELLY_VALLEY)

	var director: MobDirector = null
	var ship: Node3D = null
	var warning := false
	var _scale := 7.0
	var _node: Node3D = null
	var _clock := 0.0
	var _orbit := 0.0
	var _orbit_rate := 0.05
	var _phase: int = Phase.ORBIT
	var _grab_run := false
	var _radius := 120.0
	var _alt := 150.0
	## Faded materials/lights: {mat, base_a} and {light, base_e}.
	var _fade_mats: Array = []
	var _fade_lights: Array = []

	func setup_valley(scene: PackedScene, seed: float) -> void:
		_node = scene.instantiate() as Node3D
		add_child(_node)
		_scale = 0.5 + pow(randf(), 2.0) * 19.5
		_node.scale = Vector3.ONE * _scale
		var ap := MobDirector.find_player(_node)
		if ap != null and ap.has_animation("200"):
			ap.play("200")
		_collect_fade(self)
		visible = false
		# Scattered over the disc and the heights, each on its own slow
		# ring, so the night sky fills like stars instead of one clump.
		_orbit = seed
		_orbit_rate = randf_range(0.03, 0.09)
		_radius = sqrt(randf()) * VALLEY_RADIUS
		_alt = randf_range(80.0, 260.0)
		# Local position: the director sits at the origin, and this runs
		# before add_child, so global access is off-limits here.
		position = _slot()


	func _slot() -> Vector3:
		return center() + Vector3(cos(_orbit) * _radius, _alt + sin(_clock * 0.5) * 4.0, sin(_orbit) * _radius)


	## Director hooks for the single-diver token.
	func is_off_orbit() -> bool:
		return _phase != Phase.ORBIT


	func ready_to_dive() -> bool:
		return _phase == Phase.STAGE


	func dive_done() -> bool:
		return _phase == Phase.ORBIT or _phase == Phase.RETURN


	func start_dive(grab: bool) -> void:
		_grab_run = grab
		_phase = Phase.DIVE

	func tick(delta: float, night: bool) -> void:
		if ship == null or _node == null:
			warning = false
			return
		_clock += delta
		if not night:
			# Day: the valley sinks under the sea, machine frozen.
			warning = false
			if _phase == Phase.GRAB:
				_phase = Phase.ORBIT
			_sink(delta)
			return
		if global_position.y < SURFACE_Y:
			# Night but still submerged: float back up to the orbit slot.
			warning = false
			_rise(delta)
			return
		_orbit += delta * _orbit_rate
		_tick_valley(delta)
		# Bird-like bell: slow wingbeat on station, frantic spinning dive.
		var diving := _phase == Phase.DIVE
		var beat := 2.2 if diving else 0.9
		var amp := 0.12 if diving else 0.06
		_node.scale = Vector3.ONE * (_scale * (1.0 + amp * sin(_clock * beat)))
		_node.rotation.y += delta * (0.6 if diving else 0.08)
		_node.rotation.z = lerpf(_node.rotation.z, sin(_orbit) * 0.15, minf(1.0, 2.0 * delta))
		# Distance fade: invisible past 500 m, fading in as you close.
		var alpha := _fade_alpha()
		_apply_fade(alpha)
		visible = alpha > 0.003

	func _tick_valley(delta: float) -> void:
		var sp: Vector3 = ship.global_position
		var c := center()
		var ship_home := Vector2(sp.x - c.x, sp.z - c.z).length()
		var self_home := Vector2(global_position.x - c.x, global_position.z - c.z).length()
		var lamps := bool(ship.get("lamps_on"))
		match _phase:
			Phase.ORBIT:
				warning = false
				_glide(_slot(), ORBIT_SPEED, delta)
				if lamps and ship_home < ATTRACT_RADIUS and self_home < LEASH_RADIUS:
					if director == null or director.staged_count() < MobDirector.MAX_STAGED:
						_phase = Phase.STAGE
						warning = true
			Phase.STAGE:
				if not lamps or ship_home > LEASH_RADIUS or self_home > LEASH_RADIUS + 50.0:
					# Leash holds both ends: the pack never reaches the islands.
					_phase = Phase.ORBIT
					warning = false
					return
				warning = true
				_glide(sp + Vector3(0, STAGE_ALT, 0), STAGE_SPEED, delta)
			Phase.DIVE:
				if not lamps or bool(ship.get("wrecked")) or ship_home > LEASH_RADIUS or self_home > LEASH_RADIUS + 50.0:
					_phase = Phase.RETURN
					warning = false
					return
				warning = true
				var desired := sp + Vector3(0, 9, 0)
				_glide(desired, DIVE_SPEED, delta)
				if _node.global_position.distance_to(sp) < GRAB_RADIUS:
					if _grab_run:
						_phase = Phase.GRAB
					else:
						_strike()
						_phase = Phase.RETURN
			Phase.GRAB:
				if not lamps or bool(ship.get("wrecked")) or self_home > LEASH_RADIUS:
					_phase = Phase.RETURN
					warning = false
					return
				warning = true
				_drown(delta)
			Phase.RETURN:
				warning = false
				_glide(_slot(), ORBIT_SPEED, delta)
				if global_position.distance_to(_slot()) < 15.0:
					_phase = Phase.ORBIT


	## One bell strike: hull damage plus a shove. The cycle sends the next
	## bell until the ship dies or the lamps go out.
	func _strike() -> void:
		if ship == null:
			return
		ship.call("take_damage", STRIKE_DAMAGE)
		if ship.has_method("add_shove"):
			var away: Vector3 = ship.global_position - global_position
			away.y = 0.0
			if away.length() > 0.01:
				away = away.normalized()
			ship.call("add_shove", away * STRIKE_SHOVE + Vector3.UP * STRIKE_SHOVE * 0.3)

	func _glide(target: Vector3, speed: float, delta: float) -> void:
		var to := target - global_position
		var dist := to.length()
		if dist < 0.01:
			return
		global_position += to / dist * minf(speed * delta, dist)

	## The grab: no damage, just water. Sustained downward + inward force
	## overpowers buoyancy and the engine until the hull trips the wreck
	## depth and the sea takes it. Lamps out or leash crossed lets go.
	func _drown(delta: float) -> void:
		if ship == null or not ship.has_method("add_shove"):
			return
		var sp: Vector3 = ship.global_position
		var inward: Vector3 = sp - global_position
		inward.y = 0.0
		if inward.length() > 0.01:
			inward = inward.normalized()
		ship.call("add_shove", Vector3.DOWN * GRAB_DOWN * delta + inward * GRAB_IN * delta)

	## Day: sink straight down. The bell dissolves as it goes under,
	## gone once the node drops below the surface.
	func _sink(delta: float) -> void:
		global_position.y = maxf(SINK_DEPTH, global_position.y - SINK_RATE * delta)
		var alpha := _fade_alpha() * clampf(global_position.y / 60.0, 0.0, 1.0)
		_apply_fade(alpha)
		visible = global_position.y > SURFACE_Y and alpha > 0.003

	## Night: float back up to the orbit slot, fading in as the
	## bell breaks the surface.
	func _rise(delta: float) -> void:
		_glide(_slot(), RISE_SPEED, delta)
		var alpha := _fade_alpha() * clampf(global_position.y / 60.0, 0.0, 1.0)
		_apply_fade(alpha)
		visible = global_position.y > SURFACE_Y and alpha > 0.003

	## Walk the bell once: duplicate every surface material transparent for
	## distance fading, record beacon lights.
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

	func _fade_alpha() -> float:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return 1.0
		var d: float = cam.global_position.distance_to(global_position)
		return clampf((FADE_HIDE - d) / (FADE_HIDE - FADE_SHOW), 0.0, 1.0)

	func _apply_fade(alpha: float) -> void:
		for f in _fade_mats:
			var mat := f["mat"] as StandardMaterial3D
			if mat != null and is_instance_valid(mat):
				var c := mat.albedo_color
				mat.albedo_color = Color(c.r, c.g, c.b, float(f["base_a"]) * alpha)
		for l in _fade_lights:
			var light := l["light"] as Light3D
			if light != null and is_instance_valid(light):
				light.light_energy = float(l["base_e"]) * alpha


class SeaVisit:
	extends Node3D
	## One peaceful visit: a shy whale circling the ship, singing as it
	## goes. Steady swim, gentle surfacing, no damage, no lamp games. The
	## call is positional, swelling in and out so starts never click.
	## The whale is shy: it keeps a ~400 m ring, awash with its back out,
	## and only once per visit dives deep to pass beneath the hull.
	enum WPhase { ARRIVE, CIRCLE, PASS, LEAVE }
	const WHALE_SPEED := 4.0
	const ARRIVE_SPEED := 7.0
	const PASS_SPEED := 6.0
	const RING_R := 400.0
	const WHALE_AWASH := -5.0
	const WHALE_DEEP := -10.0
	const WHALE_MAX_DIST := 600.0
	const WHALE_DB := -8.0
	## Spawn fade: invisible past 650 m, solid inside 350 m. Visits
	## arrive from 700 m out, so they fade in, never pop in.
	const SEA_FADE_HIDE := 650.0
	const SEA_FADE_SHOW := 350.0

	var ship: Node3D = null
	var done := false
	var _animals: Array = []
	var _exit := Vector3.ZERO
	var _clock := 0.0
	var _fade_mats: Array = []
	var _wphase: int = WPhase.ARRIVE
	var _wtimer := 0.0
	var _wangle := 0.0
	var _winit := false
	var _crossed := false

	func setup_whale(sound: AudioStream, from: Vector3, to: Vector3) -> void:
		position = from
		_exit = to
		# Ghost singer: no body, only the distant call running the same
		# shy circuit. The fade walk finds no meshes and no-ops.
		var holder := Node3D.new()
		holder.name = "GhostWhale"
		holder.position = Vector3(0, WHALE_AWASH, 0)
		add_child(holder)
		_collect_sea_fade(holder)
		var player := AudioStreamPlayer3D.new()
		player.stream = sound
		player.unit_size = 150.0
		player.max_distance = WHALE_MAX_DIST
		player.volume_db = WHALE_DB - 28.0
		GameMenu.ensure_audio_buses()
		player.bus = "Sea"
		holder.add_child(player)
		_animals.append({"node": holder, "home": holder.position, "player": player, "speed": WHALE_SPEED, "phase": randf() * TAU, "base_db": WHALE_DB, "depth": WHALE_AWASH, "call_t": randf_range(10.0, 20.0), "stop_t": -1.0})

	func tick(delta: float) -> void:
		if ship == null or done:
			return
		_clock += delta
		_tick_whale(delta)
		var alpha := _sea_alpha()
		_apply_sea_fade(alpha)
		visible = alpha > 0.003
		for a in _animals:
			_tick_animal(a as Dictionary, delta)

	func _sea_alpha() -> float:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return 1.0
		var d: float = cam.global_position.distance_to(global_position)
		return clampf((SEA_FADE_HIDE - d) / (SEA_FADE_HIDE - SEA_FADE_SHOW), 0.0, 1.0)

	func _collect_sea_fade(n: Node) -> void:
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
		for c in n.get_children():
			_collect_sea_fade(c)

	func _apply_sea_fade(alpha: float) -> void:
		for f in _fade_mats:
			var mat := f["mat"] as StandardMaterial3D
			if mat != null and is_instance_valid(mat):
				var c := mat.albedo_color
				mat.albedo_color = Color(c.r, c.g, c.b, float(f["base_a"]) * alpha)

	## Shy circuit: join the 400 m ring awash, circle a while, dive for
	## one pass beneath the hull (calling as it goes down), then leave.
	func _tick_whale(delta: float) -> void:
		var sp: Vector3 = ship.global_position
		if not _winit:
			_winit = true
			var rel := global_position - sp
			_wangle = atan2(rel.z, rel.x)
		var to_ship := sp - global_position
		to_ship.y = 0.0
		if (_wphase == WPhase.ARRIVE or _wphase == WPhase.CIRCLE) and to_ship.length() < 80.0:
			# Shy: never let the hull inside the body. Veer off and the
			# ring re-catches it; only the deep PASS goes under the ship.
			var away := -to_ship.normalized() if to_ship.length() > 0.01 else Vector3(1, 0, 0)
			_swim_toward(global_position + away * 250.0, ARRIVE_SPEED, delta)
			return
		var a := _animals[0] as Dictionary
		match _wphase:
			WPhase.ARRIVE:
				var ring := _ring_point(sp)
				_swim_toward(ring, ARRIVE_SPEED, delta)
				var flat := Vector2(global_position.x - ring.x, global_position.z - ring.z).length()
				if flat < 40.0:
					_wphase = WPhase.CIRCLE
					_wtimer = randf_range(30.0, 60.0)
			WPhase.CIRCLE:
				a["depth"] = WHALE_AWASH
				_wangle += WHALE_SPEED / RING_R * delta
				_swim_toward(_ring_point(sp), WHALE_SPEED, delta)
				_wtimer -= delta
				if _wtimer <= 0.0:
					_wphase = WPhase.PASS
					_crossed = false
					_play_call(a)
			WPhase.PASS:
				a["depth"] = WHALE_DEEP
				var through := sp - global_position
				through.y = 0.0
				var leg := through.normalized() * 300.0 + sp
				_swim_toward(leg, PASS_SPEED, delta)
				var dist := through.length()
				if dist < 60.0:
					_crossed = true
				if _crossed and dist > 150.0:
					_wphase = WPhase.LEAVE
					var away := global_position - sp
					away.y = 0.0
					_exit = sp + away.normalized() * 800.0
			WPhase.LEAVE:
				a["depth"] = WHALE_AWASH
				var to_exit := _exit - global_position
				to_exit.y = 0.0
				if to_exit.length() < 40.0:
					_stop_all_calls()
					done = true
					return
				_swim_toward(_exit, PASS_SPEED, delta)

	func _ring_point(sp: Vector3) -> Vector3:
		return Vector3(sp.x + cos(_wangle) * RING_R, 0, sp.z + sin(_wangle) * RING_R)

	func _swim_toward(target: Vector3, speed: float, delta: float) -> void:
		var to := target - global_position
		to.y = 0.0
		if to.length() < 0.01:
			return
		var dir := to.normalized()
		global_position += dir * minf(speed * delta, to.length())
		global_transform = Transform3D(Basis.looking_at(dir), global_position)

	func _tick_animal(a: Dictionary, delta: float) -> void:
		var node := a["node"] as Node3D
		var player := a["player"] as AudioStreamPlayer3D
		if node == null or player == null:
			return
		var home := a["home"] as Vector3
		var phase := float(a["phase"])
		# Gentle porpoising around the commanded depth, never breaching far.
		var bob := sin(_clock * 1.1 + phase)
		node.position = Vector3(home.x + sin(_clock * 0.5 + phase) * 2.0, float(a.get("depth", home.y)) + bob * 2.0, home.z)
		node.rotation.z = sin(_clock * 1.1 + phase) * 0.12
		_tick_call(a, player, delta)

	func _play_call(a: Dictionary) -> void:
		var player := a["player"] as AudioStreamPlayer3D
		if player == null or player.playing or player.stream == null:
			return
		var base_db := float(a["base_db"])
		var length := player.stream.get_length()
		player.play(maxf(0.0, randf_range(0.0, maxf(0.0, length - 12.0))))
		player.volume_db = base_db - 28.0
		var swell := player.create_tween()
		swell.tween_property(player, "volume_db", base_db, 2.0)
		a["stop_t"] = randf_range(6.0, 10.0)
		a["call_t"] = randf_range(25.0, 45.0) if base_db <= -9.0 else randf_range(8.0, 15.0)

	func _tick_call(a: Dictionary, player: AudioStreamPlayer3D, delta: float) -> void:
		var base_db := float(a["base_db"])
		var call_t := float(a["call_t"])
		var stop_t := float(a["stop_t"])
		if stop_t >= 0.0:
			stop_t -= delta
			a["stop_t"] = stop_t
			if stop_t <= 0.0 and player.playing:
				var tw := player.create_tween()
				tw.tween_property(player, "volume_db", base_db - 28.0, 2.0)
				tw.tween_callback(player.stop)
			return
		call_t -= delta
		a["call_t"] = call_t
		if call_t > 0.0 or player.playing:
			return
		_play_call(a)

	func _stop_all_calls() -> void:
		for a in _animals:
			var player := (a as Dictionary)["player"] as AudioStreamPlayer3D
			if player != null and player.playing:
				player.stop()
