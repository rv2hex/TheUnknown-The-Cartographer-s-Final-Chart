class_name DayNightCycle
extends Node

## 20-minute day-night cycle for the inverted JoJo palette.
##
## Normalized time 0..1 maps to Dawn 0.00-0.25, Noon 0.25-0.50, Dusk 0.50-0.75,
## Midnight 0.75-1.00. Four palette keys sit at each band's center and are
## lerped cyclically, so every frame blends smoothly into the next.
##
## One node owns all time-driven visuals: ProceduralSkyMaterial colors, the
## DirectionalLight (sun by day, red moon by night on one shared path),
## boujie water colors via the WaterMaterialDesigner, the hull tint, and the
## starlight starfield fading in after dark.

## Full cycle length in seconds. 1200 = 20 minutes.
@export var cycle_seconds := 1200.0
## Where in the cycle to start. 0.8 = nightfall, so the voyage opens
## under stars and the red moon instead of hiding them a cycle away.
@export_range(0.0, 1.0) var start_time := 0.8
## Global brightness multiplier, owned by the settings menu.
@export_range(0.3, 1.7) var brightness := 1.0

@export var sun_path := NodePath("../Sun")
@export var environment_path := NodePath("../WorldEnvironment")
@export var designer_path := NodePath("../DeepOcean/WaterMaterialDesigner")
@export var stars_path := NodePath("../Stars")
@export var hull_mesh_path := NodePath("../Boat/ShipModel/dutch_ship_medium_hull")

var time_of_day := 0.0

# Palette keys at band centers: dawn 0.125, noon 0.375, dusk 0.625, midnight 0.875.
const KEYS: Array = [
	{
		"at": 0.125,
		"sky_top": "2D1B4E", "sky_horizon": "8B448C", "light": "FFD166",
		"water": "1F1032", "highlight": "DDA0DD", "hull": "4A3F6B",
	},
	{
		"at": 0.375,
		"sky_top": "4B0082", "sky_horizon": "9400D3", "light": "00E5FF",
		"water": "2A085C", "highlight": "FF007F", "hull": "6B2D5C",
	},
	{
		"at": 0.625,
		"sky_top": "3B0033", "sky_horizon": "C71585", "light": "FF4500",
		"water": "200020", "highlight": "FF1493", "hull": "581845",
	},
	{
		"at": 0.875,
		"sky_top": "1A0003", "sky_horizon": "800000", "light": "FF0000",
		"water": "0B0002", "highlight": "FF3333", "hull": "3A0007",
	},
]

var _sun: DirectionalLight3D
var _sky_mat: ProceduralSkyMaterial
var _environment: Environment
var _water: ShaderMaterial
var _stars: Node
var _hull_mat: StandardMaterial3D
var _water_albedo_alpha := 0.0
var _star_base_energy := 2.0e10


func _ready() -> void:
	time_of_day = start_time
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	var env_node := get_node_or_null(environment_path) as WorldEnvironment
	if env_node != null and env_node.environment != null and env_node.environment.sky != null:
		_sky_mat = env_node.environment.sky.sky_material as ProceduralSkyMaterial
	if env_node != null:
		_environment = env_node.environment
	var designer := get_node_or_null(designer_path) as WaterMaterialDesigner
	if designer != null:
		_water = designer.material
		_water_albedo_alpha = float(_water.get_shader_parameter("albedo").a)
	_stars = get_node_or_null(stars_path)
	if _stars != null:
		# Material has no shader until Stars' first _process; guard the read.
		var base_e = _stars.get("shader_params/emission_energy")
		if base_e != null:
			_star_base_energy = float(base_e)
	var hull_mi := get_node_or_null(hull_mesh_path) as MeshInstance3D
	if hull_mi == null:
		# gltf import node names drift; fall back to the first mesh under ShipModel.
		var ship_model := get_node_or_null(NodePath("../Boat/ShipModel")) as Node
		if ship_model != null:
			hull_mi = _find_first_mesh(ship_model) as MeshInstance3D
	if hull_mi != null and hull_mi.mesh != null:
		_hull_mat = hull_mi.get_surface_override_material(0) as StandardMaterial3D
		if _hull_mat == null:
			_hull_mat = hull_mi.mesh.surface_get_material(0) as StandardMaterial3D
		if _hull_mat == null and hull_mi.mesh is PrimitiveMesh:
			_hull_mat = (hull_mi.mesh as PrimitiveMesh).material as StandardMaterial3D
		if _hull_mat != null:
			# Tint a copy so the shared imported material is never mutated.
			_hull_mat = _hull_mat.duplicate() as StandardMaterial3D
			hull_mi.set_surface_override_material(0, _hull_mat)
	apply(time_of_day)


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / cycle_seconds, 1.0)
	apply(time_of_day)


## Blend of the palette at normalized time t.
func sample(t: float) -> Dictionary:
	var count := KEYS.size()
	var i := 0
	for k in range(count):
		var cur: float = KEYS[k]["at"]
		var nxt: float = KEYS[(k + 1) % count]["at"]
		if k == count - 1:
			nxt += 1.0
		var tt := t
		if tt < cur:
			tt += 1.0
		if tt >= cur and tt < nxt:
			i = k
			var u: float = (tt - cur) / (nxt - cur)
			return _blend(KEYS[i], KEYS[(i + 1) % count], u)
	return _blend(KEYS[count - 1], KEYS[0], 0.0)


func _blend(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var out := {}
	for key in ["sky_top", "sky_horizon", "light", "water", "highlight", "hull"]:
		out[key] = Color.html(a[key]).lerp(Color.html(b[key]), u)
	return out


static func _find_first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var f := _find_first_mesh(c)
		if f != null:
			return f
	return null


## Sun elevation: +1 zenith at noon band center, -1 nadir at midnight center.
func sun_elevation(t: float) -> float:
	return sin((t - 0.125) * TAU)


func apply(t: float) -> void:
	var pal := sample(t)
	var elev := sun_elevation(t)
	var day_factor: float = smoothstep(-0.08, 0.2, elev)
	var night_factor := 1.0 - smoothstep(-0.2, 0.05, elev)

	if _sky_mat != null:
		_sky_mat.sky_top_color = pal["sky_top"]
		_sky_mat.sky_horizon_color = pal["sky_horizon"]
		_sky_mat.ground_horizon_color = (pal["sky_horizon"] as Color).darkened(0.55)
		_sky_mat.ground_bottom_color = (pal["sky_top"] as Color).darkened(0.7)
		_sky_mat.sky_energy_multiplier = lerpf(0.3, 1.0, day_factor) * brightness

	if _environment != null:
		_environment.fog_light_color = pal["sky_horizon"]

	if _sun != null:		# One shared sun/moon path: dawn rises east, noon peaks, dusk sets,
		# midnight sits below as the red moon. Palette light color covers both.
		var azimuth := (t - 0.125) * TAU
		# Clamped so Basis.looking_at never gets a direction parallel to up.
		var e := clampf(elev, -0.999, 0.999)
		var horiz := cos(asin(e))
		var sun_dir := Vector3(cos(azimuth) * horiz, e, sin(azimuth) * horiz)
		_sun.global_transform = Transform3D(Basis.looking_at(-sun_dir.normalized()), _sun.global_position)
		_sun.light_color = pal["light"]
		_sun.light_energy = lerpf(0.25, 1.35, day_factor) * brightness

	if _water != null:
		_water.set_shader_parameter("albedo", Color(pal["water"], _water_albedo_alpha))
		_water.set_shader_parameter("albedo_fresnel", pal["highlight"])
		_water.set_shader_parameter("color_deep", (pal["water"] as Color).darkened(0.65))

	if _hull_mat != null:
		_hull_mat.albedo_color = pal["hull"]

	if _stars != null:
		# Stars stay visible around the clock; night just burns them brighter.
		_stars.set("shader_params/emission_energy", _star_base_energy * maxf(night_factor, 0.45))
		_stars.visible = true
