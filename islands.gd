class_name WorldIslands
extends Node3D

## All three Unseen Reach islands as natural-looking noise heightfields with
## painted biomes (sand shoreline, moss/rock slopes, obsidian dome), plus
## Miasma glow shells and a toxic lagoon. Shapes follow the chart:
## twin gaussian peaks with a saddle dip, a smooth dome, and a 250-degree
## atoll arc.
##
## Each island is a StaticBody3D with concave collision from the same mesh,
## so the hull runs aground on the visible shoreline. Hazard zones are
## enforced here every physics tick: Twin Spires saddle slows, Teardrop
## skirt and Crescent lagoon corrode the hull via take_damage() on the ship.
##
## Beyond the chart: a few rare naturally-generated wild islands spawn far
## outside the map bounds (seeded, so the layout is stable). They reuse the
## same terrain/collision/fade path and slow the hull in their shallows.

@export var ship_path := NodePath("../Boat")

const TWIN_SLOW_RADIUS := 80.0
const TWIN_SLOW_MULT := 0.4
const TEAR_RING_IN := 55.0
const TEAR_RING_OUT := 90.0
const TEAR_DPS := 6.0
const CRESCENT_LAGOON_R := 88.0
const CRESCENT_DPS := 15.0

var _twin_pos := Vector3.ZERO
var _tear_pos := Vector3.ZERO
var _crescent_pos := Vector3.ZERO

var _noise := FastNoiseLite.new()

var _island_mat: StandardMaterial3D
var _obsidian_mat: StandardMaterial3D
var _miasma_mat: StandardMaterial3D
var _lagoon_mat: StandardMaterial3D

## Distance fade: invisible far away, slowly fading into existence on
## approach. Fully gone beyond HIDE_DIST, fully solid inside SHOW_DIST.
const HIDE_DIST := 1000.0
const SHOW_DIST := 450.0
## Per-island materials (duplicated at build): {mat, base, body}.
var _tracked: Array = []

## Rare off-chart islands: {name, ll, pos, radius}. Seeded for a stable
## layout; kept few and far apart so they feel like genuine discoveries.
const WILD_COUNT := 5
const WILD_SEED := 20260923
const WILD_MIN_SEPARATION := 550.0
const WILD_CLEARANCE := 600.0
const WILD_SLOW_RADIUS_MULT := 0.9
const WILD_SLOW_MULT := 0.6
const WILD_NAMES := ["Drift Reef", "Hollow Stack", "Pale Shoal", "Widow's Rest", "Salt Fall"]
var _wild_islands: Array = []


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.02
	_noise.fractal_octaves = 5
	_make_materials()
	_twin_pos = Geo.world_of_ll(Geo.TWIN_SPIRES)
	_tear_pos = Geo.world_of_ll(Geo.TEARDROP)
	_crescent_pos = Geo.world_of_ll(Geo.CRESCENT)
	_build_twin_spires(_twin_pos)
	_build_teardrop(_tear_pos)
	_build_crescent(_crescent_pos)
	_build_wild_islands()


const LOD_DIST_0 := 600.0
const LOD_DIST_1 := 300.0

func _physics_process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var ship := get_node_or_null(ship_path)
	if ship == null or not ship.has_method("take_damage"):
		return
	var p: Vector3 = (ship as Node3D).global_position
	var dist_to_cam := cp.distance_to(p)
	# Skip hazard checks when far from camera (islands too far to matter)
	if dist_to_cam > LOD_DIST_0:
		return
	var slow := 1.0
	var dps := 0.0
	var flat_twin := Vector2(p.x - _twin_pos.x, p.z - _twin_pos.z).length()
	if flat_twin < TWIN_SLOW_RADIUS:
		slow = TWIN_SLOW_MULT
	var flat_tear := Vector2(p.x - _tear_pos.x, p.z - _tear_pos.z).length()
	if flat_tear > TEAR_RING_IN and flat_tear < TEAR_RING_OUT:
		dps = maxf(dps, TEAR_DPS)
	var flat_crescent := Vector2(p.x - _crescent_pos.x, p.z - _crescent_pos.z).length()
	if flat_crescent < CRESCENT_LAGOON_R:
		dps = maxf(dps, CRESCENT_DPS)
	for w in _wild_islands:
		var wp := w["pos"] as Vector3
		var flat_wild := Vector2(p.x - wp.x, p.z - wp.z).length()
		if flat_wild < float(w["radius"]) * WILD_SLOW_RADIUS_MULT:
			slow = minf(slow, WILD_SLOW_MULT)
	ship.set("sea_slow_mult", slow)
	ship.call("take_damage", dps * delta)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _tracked.is_empty():
		return
	var cp := cam.global_position
	for t in _tracked:
		var body := t["body"] as Node3D
		var mat := t["mat"] as StandardMaterial3D
		if body == null or mat == null or not is_instance_valid(body):
			continue
		var d: float = cp.distance_to(body.global_position)
		var alpha := clampf((HIDE_DIST - d) / (HIDE_DIST - SHOW_DIST), 0.0, 1.0)
		var base := t["base"] as Color
		mat.albedo_color = Color(base.r, base.g, base.b, base.a * alpha)
		body.visible = alpha > 0.003


func _make_materials() -> void:
	_island_mat = StandardMaterial3D.new()
	_island_mat.vertex_color_use_as_albedo = true
	_island_mat.roughness = 1.0
	_obsidian_mat = StandardMaterial3D.new()
	_obsidian_mat.vertex_color_use_as_albedo = true
	_obsidian_mat.metallic = 0.85
	_obsidian_mat.roughness = 0.25
	_miasma_mat = StandardMaterial3D.new()
	_miasma_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_miasma_mat.albedo_color = Color(0.2, 1.0, 0.3, 0.32)
	_miasma_mat.emission_enabled = true
	_miasma_mat.emission = Color(0.2, 1.0, 0.3)
	_miasma_mat.emission_energy_multiplier = 1.5
	_miasma_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lagoon_mat = StandardMaterial3D.new()
	_lagoon_mat.albedo_color = Color(0.1, 0.5, 0.15)
	_lagoon_mat.emission_enabled = true
	_lagoon_mat.emission = Color(0.25, 1.0, 0.3)
	_lagoon_mat.emission_energy_multiplier = 2.0


# --- height fields ---------------------------------------------------------

func _h_twin(x: float, z: float) -> float:
	var d1 := Vector2(x + 40.0, z).length()
	var d2 := Vector2(x - 40.0, z).length()
	var r := Vector2(x, z).length()
	var h: float = 185.0 * exp(-(d1 * d1) / 968.0) + 185.0 * exp(-(d2 * d2) / 968.0)
	h += 18.0 * exp(-(r * r) / 24200.0)
	h += _noise.get_noise_2d(x + 1000.0, z) * (4.0 + h * 0.08)
	return h - 6.0


func _h_tear(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var h: float = 44.0 * (1.0 - smoothstep(8.0, 60.0, r))
	h += _noise.get_noise_2d(x - 500.0, z + 300.0) * 2.0 * clampf(h / 10.0, 0.0, 1.0)
	return h - 4.0


func _h_crescent(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var b := rad_to_deg(atan2(x, -z))
	if b < 0.0:
		b += 360.0
	# Arc spans bearings 100..350 (gap faces NE); feather 6 deg at the tips.
	var inside := 0.0
	if b >= 94.0 and b <= 356.0:
		inside = 1.0 - smoothstep(0.0, 6.0, minf(absf(b - 100.0), absf(b - 350.0)))
	var mask := (1.0 - smoothstep(14.0, 22.0, absf(r - 112.0))) * inside
	var h: float = 16.0 * mask
	h += _noise.get_noise_2d(x + 200.0, z - 700.0) * 1.5 * mask
	return h - 3.5


## Natural wild-island heightfield: fractal noise on a radial island mask
## with a sandy falloff to the surf line. Extra args arrive via bind().
func _h_wild(x: float, z: float, ox: float, oz: float, radius: float, peak: float) -> float:
	var r := Vector2(x, z).length()
	var mask := 1.0 - smoothstep(radius * 0.55, radius, r)
	var h: float = peak * mask
	h += _noise.get_noise_2d(x * 0.06 + ox, z * 0.06 + oz) * (2.0 + peak * 0.12) * mask
	return h - 4.0


## Off-chart islands the QuestLog can chart: {name, ll, pos, radius}.
func get_wild_islands() -> Array:
	return _wild_islands


func _build_wild_islands() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = WILD_SEED
	var anchors: Array = [
		_twin_pos, _tear_pos, _crescent_pos,
		Geo.world_of_ll(Geo.IRON_GULL),
	]
	var placed := 0
	var attempts := 0
	while placed < WILD_COUNT and attempts < WILD_COUNT * 40:
		attempts += 1
		var ll := _wild_candidate_ll(rng)
		var pos := Geo.world_of_ll(ll)
		var clear := true
		for a in anchors:
			if Vector2(pos.x - (a as Vector3).x, pos.z - (a as Vector3).z).length() < WILD_CLEARANCE:
				clear = false
				break
		if clear:
			for w in _wild_islands:
				var wp := w["pos"] as Vector3
				if Vector2(pos.x - wp.x, pos.z - wp.z).length() < WILD_MIN_SEPARATION:
					clear = false
					break
		if not clear:
			continue
		var radius := rng.randf_range(55.0, 110.0)
		var peak := rng.randf_range(18.0, 60.0)
		var wild_name := String(WILD_NAMES[placed % WILD_NAMES.size()])
		_build_wild(wild_name, pos, ll, radius, peak, rng, placed)
		anchors.append(pos)
		placed += 1


## Candidate lat/lon strictly outside the chart (map spans 140-170E,
## -10..35N) but inside ocean/camera range (~2km from the origin).
func _wild_candidate_ll(rng: RandomNumberGenerator) -> Vector2:
	match rng.randi_range(0, 3):
		0:
			return Vector2(rng.randf_range(-15.0, 40.0), rng.randf_range(132.0, 137.0))
		1:
			return Vector2(rng.randf_range(-8.0, 32.0), rng.randf_range(173.0, 174.5))
		2:
			return Vector2(rng.randf_range(38.0, 43.0), rng.randf_range(140.0, 152.0))
		_:
			return Vector2(rng.randf_range(-18.0, -13.0), rng.randf_range(140.0, 152.0))


func _build_wild(wild_name: String, pos: Vector3, ll: Vector2, radius: float, peak: float, rng: RandomNumberGenerator, idx: int) -> void:
	var body := _static_root(pos, "Wild" + wild_name.replace(" ", "").replace("'", ""))
	var ox := rng.randf_range(-2000.0, 2000.0)
	var oz := rng.randf_range(-2000.0, 2000.0)
	var h_fn := Callable(self, "_h_wild").bind(ox, oz, radius, peak)
	var paint_fn := Callable(self, "_paint_shore")
	var mat: Material = _island_mat
	if idx % 2 == 1:
		paint_fn = Callable(self, "_paint_obsidian")
		mat = _obsidian_mat
	_build_terrain(body, "Ground", radius + 40.0, 56, h_fn, paint_fn, mat)
	_flat_glow(body, "WildMiasma", radius * 0.7, radius * 1.05, 0.0, 360.0, 2.0)
	_wild_islands.append({"name": wild_name, "ll": ll, "pos": pos, "radius": radius})


func _slope(h_fn: Callable, x: float, z: float) -> float:
	var e := 2.0
	var dx: float = h_fn.call(x + e, z) - h_fn.call(x - e, z)
	var dz: float = h_fn.call(x, z + e) - h_fn.call(x, z - e)
	return Vector2(dx, dz).length() / (2.0 * e)


func _paint_shore(x: float, h: float, slope: float) -> Color:
	var n := _noise.get_noise_2d(x * 0.05 + 500.0, h * 0.05) * 0.5 + 0.5
	var detail := _noise.get_noise_2d(x * 0.35, h * 0.35) * 0.5 + 0.5
	var strata := 0.5 + 0.5 * sin(h * 0.55 + n * 4.0)
	var sand := Color(0.62, 0.56, 0.42)
	var grass := Color(0.24, 0.42, 0.19)
	var rock := Color(0.38, 0.33, 0.29)
	var dark_rock := Color(0.2, 0.17, 0.15)
	var deep := Color(0.1, 0.16, 0.19)
	var foam := Color(0.85, 0.88, 0.85)
	if h < -2.0:
		return deep
	# Wet shoreline + foam edge reads as surf up close.
	if h < 0.6:
		return sand.darkened(0.35).lerp(deep, clampf(-h / 2.0, 0.0, 1.0) * 0.6)
	if h < 1.6:
		return foam.lerp(sand, clampf((h - 0.6) / 1.0, 0.0, 1.0) * 0.7)
	if h < 2.5:
		return sand.lerp(grass, (h - 1.6) * 0.5)
	if slope > 0.6 or h > 45.0:
		var cliff := rock.lerp(dark_rock, strata * 0.6)
		return cliff.lerp(cliff.darkened(0.3), detail * 0.4)
	var g := grass.lerp(rock, clampf(n * 0.7 + slope * 0.5, 0.0, 1.0))
	return g.lerp(g.darkened(0.25), detail * strata * 0.35)


func _paint_obsidian(x: float, h: float, _slope: float) -> Color:
	var n := _noise.get_noise_2d(x * 0.08 - 300.0, h * 0.08) * 0.5 + 0.5
	var detail := _noise.get_noise_2d(x * 0.3 + 100.0, h * 0.3) * 0.5 + 0.5
	var strata := 0.5 + 0.5 * sin(h * 0.7 + n * 5.0)
	var base := Color(0.02, 0.02, 0.03).lerp(Color(0.07, 0.08, 0.08), n)
	var foam := Color(0.85, 0.88, 0.85)
	if h < 0.6:
		return base.darkened(0.4)
	if h < 1.1:
		return foam.lerp(base, clampf((h - 0.6) / 0.5, 0.0, 1.0) * 0.7)
	if h < 1.6:
		return Color(0.5, 0.48, 0.34)
	if h < 6.0:
		return base.lerp(Color(0.1, 0.3, 0.12), n * 0.5)
	return base.lerp(Color(0.09, 0.1, 0.11), strata * 0.5).lerp(Color.BLACK, detail * 0.25)


# --- mesh builders ---------------------------------------------------------

func _static_root(pos: Vector3, island_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = island_name
	body.position = pos
	add_child(body)
	return body


func _build_terrain(body: StaticBody3D, mesh_name: String, half: float, res: int, h_fn: Callable, paint_fn: Callable, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Collision rides a second mesh built from above-water faces only, so
	# the hull grounds on the visible shoreline instead of an invisible
	# submerged shelf far outside it.
	var cst := SurfaceTool.new()
	cst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := half * 2.0 / res
	for j in range(res):
		for i in range(res):
			var x0 := -half + i * step
			var z0 := -half + j * step
			var corners := [Vector2(x0, z0), Vector2(x0, z0 + step), Vector2(x0 + step, z0 + step), Vector2(x0 + step, z0)]
			var verts: Array[Vector3] = []
			var cols: Array[Color] = []
			var top := -1000.0
			for corner in corners:
				var h: float = h_fn.call(corner.x, corner.y)
				top = maxf(top, h)
				verts.append(Vector3(corner.x, h, corner.y))
				cols.append(paint_fn.call(corner.x, h, _slope(h_fn, corner.x, corner.y)))
			_add_tri_c(st, verts[0], cols[0], verts[1], cols[1], verts[2], cols[2])
			_add_tri_c(st, verts[0], cols[0], verts[2], cols[2], verts[3], cols[3])
			if top > -1.5:
				_add_tri_v(cst, verts[0], verts[1], verts[2])
				_add_tri_v(cst, verts[0], verts[2], verts[3])
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	if mat != null:
		# Duplicate per island so distance fading never touches a sibling.
		var own := mat
		if mat is StandardMaterial3D:
			own = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			(own as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.set_surface_override_material(0, own)
		if own is StandardMaterial3D:
			_tracked.append({"mat": own, "base": (own as StandardMaterial3D).albedo_color, "body": body})
	body.add_child(mi)
	var cmesh := cst.commit()
	var cs := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	if cmesh != null:
		concave.set_faces(cmesh.get_faces())
	else:
		concave.set_faces(mesh.get_faces())
	cs.shape = concave
	body.add_child(cs)


func _add_tri_c(st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


## Position-only triangle for the collision mesh (no color/normal needed).
func _add_tri_v(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _flat_glow(body: StaticBody3D, glow_name: String, r_in: float, r_out: float, a0_deg: float, a1_deg: float, y: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 64
	for i in range(segs):
		var b0 := deg_to_rad(lerpf(a0_deg, a1_deg, float(i) / segs))
		var b1 := deg_to_rad(lerpf(a0_deg, a1_deg, float(i + 1) / segs))
		var p := [
			Vector3(sin(b0) * r_in, y, -cos(b0) * r_in),
			Vector3(sin(b0) * r_out, y, -cos(b0) * r_out),
			Vector3(sin(b1) * r_out, y, -cos(b1) * r_out),
			Vector3(sin(b1) * r_in, y, -cos(b1) * r_in),
		]
		st.add_vertex(p[0])
		st.add_vertex(p[1])
		st.add_vertex(p[2])
		st.add_vertex(p[0])
		st.add_vertex(p[2])
		st.add_vertex(p[3])
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = glow_name
	mi.mesh = mesh
	var glow_mat := _miasma_mat.duplicate() as StandardMaterial3D
	mi.set_surface_override_material(0, glow_mat)
	_tracked.append({"mat": glow_mat, "base": glow_mat.albedo_color, "body": body})
	body.add_child(mi)


func _build_twin_spires(c: Vector3) -> void:
	var body := _static_root(c, "TwinSpires")
	_build_terrain(body, "Peaks", 200.0, 104, Callable(self, "_h_twin"), Callable(self, "_paint_shore"), _island_mat)
	_flat_glow(body, "BaseMiasma", 120.0, 150.0, 0.0, 360.0, 2.0)


func _build_teardrop(c: Vector3) -> void:
	var body := _static_root(c, "Teardrop")
	_build_terrain(body, "Dome", 100.0, 80, Callable(self, "_h_tear"), Callable(self, "_paint_obsidian"), _obsidian_mat)
	_flat_glow(body, "SkirtMiasma", 58.0, 88.0, 0.0, 360.0, 2.0)


func _build_crescent(c: Vector3) -> void:
	var body := _static_root(c, "Crescent")
	_build_terrain(body, "Rim", 190.0, 112, Callable(self, "_h_crescent"), Callable(self, "_paint_shore"), _island_mat)
	_flat_glow(body, "RimMiasma", 100.0, 160.0, 90.0, 360.0, 2.0)
	var lagoon := CylinderMesh.new()
	lagoon.top_radius = 95.0
	lagoon.bottom_radius = 95.0
	lagoon.height = 1.0
	var mi := MeshInstance3D.new()
	mi.name = "Lagoon"
	mi.mesh = lagoon
	mi.position = Vector3(0, 0.3, 0)
	var lagoon_own := _lagoon_mat.duplicate() as StandardMaterial3D
	lagoon_own.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.set_surface_override_material(0, lagoon_own)
	_tracked.append({"mat": lagoon_own, "base": lagoon_own.albedo_color, "body": body})
	body.add_child(mi)
