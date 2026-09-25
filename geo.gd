class_name Geo
extends RefCounted

## Single source of truth mapping the Unseen Reach lore coordinates to world
## space. Convention: -Z = north, +X = east (ship sails bow-first into -Z).
## x = (lon - LON0) * K * cos(LAT0), z = -(lat - LAT0) * K.

const K := 50.0
const LAT0 := 8.0
const LON0 := 146.0

# Lore anchor points (decimal degrees). The ABC islands sit far from Iron
## Gull (950-1500m), so a new voyage sees only black silhouettes.
const TWIN_SPIRES := Vector2(34.0, 149.0)
const TEARDROP := Vector2(17.0, 166.0)
const CRESCENT := Vector2(-9.5, 156.0)
const IRON_GULL := Vector2(5.0, 143.5)
## Far crab reef, way off-chart NW (~1850m out, past the wild islands).
const CRAB_REEF := Vector2(41.0, 129.0)
## Jellyfish valley: dead middle of the chart, clear of every island.
const JELLY_VALLEY := Vector2(12.5, 155.0)


static func _kx() -> float:
	return K * cos(deg_to_rad(LAT0))


static func world_of(lat: float, lon: float) -> Vector3:
	return Vector3((lon - LON0) * _kx(), 0.0, -(lat - LAT0) * K)


static func world_of_ll(ll: Vector2) -> Vector3:
	return world_of(ll.x, ll.y)


static func latlon_of(pos: Vector3) -> Vector2:
	return Vector2(LAT0 - pos.z / K, LON0 + pos.x / _kx())


static func format_ll(ll: Vector2) -> String:
	return format_coord(ll.x, true) + " " + format_coord(ll.y, false)


static func format_coord(v: float, is_lat: bool) -> String:
	var hemi := ""
	if is_lat:
		hemi = "N" if v >= 0.0 else "S"
	else:
		hemi = "E" if v >= 0.0 else "W"
	var a := absf(v)
	var deg := int(a)
	var minutes := int(round((a - deg) * 60.0))
	if minutes == 60:
		deg += 1
		minutes = 0
	return "%02d°%02d'%s" % [deg, minutes, hemi]
