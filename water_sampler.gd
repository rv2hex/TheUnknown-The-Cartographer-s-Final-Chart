class_name WaterSampler
extends RefCounted

## CPU mirror of the boujie water shader's Gerstner wave math.
##
## Invariant: [method height_at] must equal the shader vertex-wave height so the
## boat floats ON the visible surface. It ports P_DEG() from
## addons/boujie_water_shader/shader/water.gdshader exactly:
##   dir = (sin(d*TAU/360), cos(d*TAU/360)); p = phase*TAU/360
##   y = steepness * sin(TAU*dot(freq*dir, xz) + speed*(t+p))
## averaged over all waves. The shader works in global XZ
## (world_vertex_coords), so sample with global positions.
## Vertex-wave distance fade is ignored: the follow camera keeps the boat
## inside the full-strength range.

static func height_at(world_xz: Vector2, time: float, waves: Array) -> float:
	if waves.is_empty():
		return 0.0
	var height := 0.0
	for wave in waves:
		var dir := Vector2(
			sin(wave.direction_degrees * TAU / 360.0),
			cos(wave.direction_degrees * TAU / 360.0)
		)
		var p: float = wave.phase_degrees * TAU / 360.0
		var arg: float = TAU * dir.dot(world_xz) * wave.frequency + wave.speed * (time + p)
		height += wave.steepness * sin(arg)
	return height / float(waves.size())


## CPU mirror of the shader's N_DEG() normal, averaged the same way.
static func normal_at(world_xz: Vector2, time: float, waves: Array) -> Vector3:
	if waves.is_empty():
		return Vector3.UP
	var normal := Vector3.ZERO
	for wave in waves:
		var dir := Vector2(
			sin(wave.direction_degrees * TAU / 360.0),
			cos(wave.direction_degrees * TAU / 360.0)
		)
		var p: float = wave.phase_degrees * TAU / 360.0
		var arg: float = TAU * wave.frequency * dir.dot(world_xz) + wave.speed * (time + p)
		normal.x += -dir.x * wave.frequency * wave.amplitude * cos(arg)
		normal.y += 1.0 - wave.steepness * wave.frequency * wave.amplitude * sin(arg)
		normal.z += -dir.y * wave.frequency * wave.amplitude * cos(arg)
	return (normal / float(waves.size())).normalized()
