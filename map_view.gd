class_name MapView
extends Control

## Fullscreen chart overlay (M toggles). Shows assets/unseen_reach_map.png
## when the file exists, otherwise a drawn parchment grid; either way the
## ship marker is projected from live lat/long through the calibrated bounds.
## Adds compass heading arrow, island discovery markers, and scale bar.

@export var texture_path := "res://assets/unseen_reach_map.png"
@export var map_north := 35.0
@export var map_south := -10.0
@export var map_west := 140.0
@export var map_east := 170.0

var ship_ll := Vector2.ZERO
var _tex: Texture2D = null
var _discovered: Dictionary = {}
## Off-chart wild islands forwarded by the HUD: [{name, ll}].
var wild_spots: Array = []
## Hand calibration: lore spot name -> {ll, uv} pinning markers onto the
## painted art. Used only when the texture background is active.
var _calibrated: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	if FileAccess.file_exists(texture_path):
		_tex = load(texture_path) as Texture2D
	_discovered = {
		"Twin Spires": false,
		"Teardrop": false,
		"Crescent": false,
		"Iron Gull": false,
		"Crab Reef": false,
		"Jellyfish Valley": false,
	}
	_calibrated = {
		"Twin Spires": {"ll": Geo.TWIN_SPIRES, "uv": Vector2(0.77, 0.13)},
		"Teardrop": {"ll": Geo.TEARDROP, "uv": Vector2(0.82, 0.50)},
		"Crescent": {"ll": Geo.CRESCENT, "uv": Vector2(0.31, 0.73)},
		"Iron Gull": {"ll": Geo.IRON_GULL, "uv": Vector2(0.14, 0.76)},
		"Jellyfish Valley": {"ll": Geo.JELLY_VALLEY, "uv": Vector2(0.58, 0.44)},
		"Crab Reef": {"ll": Geo.CRAB_REEF, "uv": Vector2(0.25, 0.30)},
	}


func latlon_to_uv(ll: Vector2) -> Vector2:
	var u := (ll.y - map_west) / (map_east - map_west)
	var v := (map_north - ll.x) / (map_north - map_south)
	return Vector2(clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0))


## Raw chart position without clamping, so off-chart islands can be pinned
## to the parchment edge instead of collapsing onto a corner.
func _raw_uv(ll: Vector2) -> Vector2:
	var u := (ll.y - map_west) / (map_east - map_west)
	var v := (map_north - ll.x) / (map_north - map_south)
	return Vector2(u, v)


## Warp a linear chart uv through the hand calibration (inverse-distance
## weighting over the calibrated lore spots), so the live ship marker lands
## on the same painted dots the static markers use. Exact on the spots,
## smooth everywhere else.
func _warp_uv(luv: Vector2) -> Vector2:
	var total := Vector2.ZERO
	var weight := 0.0
	for spot_name in _calibrated:
		var entry := _calibrated[spot_name] as Dictionary
		var base := _raw_uv(entry["ll"])
		var off := (entry["uv"] as Vector2) - base
		var d2 := luv.distance_squared_to(base) + 0.000001
		var w := 1.0 / d2
		total += off * w
		weight += w
	if weight <= 0.0:
		return luv
	return luv + total / weight


func set_wild_spots(spots: Array) -> void:
	wild_spots = spots
	queue_redraw()


## Quest entries forwarded by the HUD; redraws only on change.
func sync_entries(entries: Array) -> void:
	var changed := false
	for e in entries:
		var nm := String(e["name"])
		var d := bool(e["done"])
		if _discovered.get(nm, false) != d:
			_discovered[nm] = d
			changed = true
	if changed:
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if _tex != null:
		var ta := float(_tex.get_width()) / float(_tex.get_height())
		var ra := size.x / size.y if size.y > 0.0 else 1.0
		var dest := rect
		if ta > ra:
			var h := size.x / ta
			dest = Rect2(Vector2(0, (size.y - h) * 0.5), Vector2(size.x, h))
		else:
			var w := size.y * ta
			dest = Rect2(Vector2((size.x - w) * 0.5, 0), Vector2(w, size.y))
		draw_texture_rect(_tex, dest, false)
		var tfont: Font = ThemeDB.fallback_font
		_draw_island_marks(dest, tfont)
		_draw_marker(_project_to(ship_ll, dest, true))
		_draw_heading_arrow(dest, tfont, true)
	else:
		draw_rect(rect.grow(-24.0), Color(0.82, 0.74, 0.55))
		draw_rect(rect.grow(-24.0), Color(0.3, 0.22, 0.12), false, 4.0)
		var inner := rect.grow(-40.0)
		var font: Font = ThemeDB.fallback_font
		for lat in range(int(map_south), int(map_north) + 1, 5):
			var p0 := _grid_pos(Vector2(lat, map_west), inner)
			var p1 := _grid_pos(Vector2(lat, map_east), inner)
			draw_line(p0, p1, Color(0.3, 0.22, 0.12, 0.4), 1.0)
		for lon in range(int(map_west), int(map_east) + 1, 5):
			var q0 := _grid_pos(Vector2(map_south, lon), inner)
			var q1 := _grid_pos(Vector2(map_north, lon), inner)
			draw_line(q0, q1, Color(0.3, 0.22, 0.12, 0.4), 1.0)
		_draw_island_marks(inner, font)
		_draw_scale_bar(inner, font)
		_draw_marker(_project_to(ship_ll, inner, false))
		_draw_heading_arrow(inner, font, false)


func _draw_island_marks(inner: Rect2, font: Font) -> void:
	var spots: Dictionary = {
		"Twin Spires": Geo.TWIN_SPIRES, "Teardrop": Geo.TEARDROP,
		"Crescent": Geo.CRESCENT, "Iron Gull": Geo.IRON_GULL,
		"Jellyfish Valley": Geo.JELLY_VALLEY, "Crab Reef": Geo.CRAB_REEF,
	}
	for spot_name in spots:
		_draw_spot(inner, font, spot_name, spots[spot_name], 7.0, 18, Color(0.2, 0.8, 0.2), Color(0.5, 0.1, 0.1))
	for w in wild_spots:
		_draw_spot(inner, font, String(w.get("name", "?")), w.get("ll", Vector2.ZERO), 6.0, 16, Color(0.3, 0.9, 0.9), Color(0.6, 0.5, 0.2))


## One marker: on-chart showing as a dot, off-chart pinned to the parchment
## edge as a diamond with an "(off-chart)" tag. On the painted art,
## calibrated lore spots sit exactly on their drawings instead.
func _draw_spot(inner: Rect2, font: Font, spot_name: String, ll: Vector2, dot: float, fsize: int, col_disc: Color, col_new: Color) -> void:
	var raw := _raw_uv(ll)
	var inside := raw.x >= 0.0 and raw.x <= 1.0 and raw.y >= 0.0 and raw.y <= 1.0
	var rp := Vector2(clampf(raw.x, 0.04, 0.96), clampf(raw.y, 0.07, 0.93))
	if _tex != null and _calibrated.has(spot_name):
		rp = (_calibrated[spot_name] as Dictionary)["uv"]
		inside = true
	var sp := inner.position + rp * inner.size
	var disc: bool = _discovered.get(spot_name, false)
	var col: Color = col_disc if disc else col_new
	var label := spot_name
	if inside:
		draw_circle(sp, dot, col)
	else:
		var s := dot + 1.0
		draw_line(sp + Vector2(0, -s), sp + Vector2(s, 0), col, 2.0)
		draw_line(sp + Vector2(s, 0), sp + Vector2(0, s), col, 2.0)
		draw_line(sp + Vector2(0, s), sp + Vector2(-s, 0), col, 2.0)
		draw_line(sp + Vector2(-s, 0), sp + Vector2(0, -s), col, 2.0)
		label += " (off-chart)"
	draw_string(font, sp + Vector2(10, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize, col)


func _draw_scale_bar(inner: Rect2, font: Font) -> void:
	var bar_w := 120.0
	var bar_h := 8.0
	var bar_x := inner.position.x + inner.size.x - bar_w - 10.0
	var bar_y := inner.position.y + inner.size.y - 30.0
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.3, 0.22, 0.12, 0.6), false, 1.0)
	draw_line(Vector2(bar_x, bar_y + bar_h / 2), Vector2(bar_x + bar_w, bar_y + bar_h / 2), Color(0.92, 0.86, 0.68), 1.0)
	var dist_km: float = float(map_east - map_west) * 111.0
	var step_km_actual: int = roundi(dist_km * 0.5)
	draw_string(font, Vector2(bar_x, bar_y - 4), "%d km" % step_km_actual, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 14, Color(0.92, 0.86, 0.68))


func _draw_heading_arrow(inner: Rect2, font: Font, warp: bool) -> void:
	var ship_pos := _project_to(ship_ll, inner, warp)
	var north_pos := _project_to(Vector2(map_north, ship_ll.y), inner, warp)
	var arrow_len := 20.0
	var dir := (north_pos - ship_pos).normalized()
	if dir.length() < 0.01:
		return
	var end := ship_pos + dir * arrow_len
	draw_line(ship_pos, end, Color(0.92, 0.86, 0.68), 2.0)
	var perp := Vector2(-dir.y, dir.x)
	var tip := end + perp * 4.0
	draw_line(end, tip, Color(0.92, 0.86, 0.68), 2.0)
	var tip2 := end - perp * 4.0
	draw_line(end, tip2, Color(0.92, 0.86, 0.68), 2.0)


func _grid_pos(ll: Vector2, inner: Rect2) -> Vector2:
	return inner.position + latlon_to_uv(ll) * inner.size


## Ship projection: linear chart uv, warped through the hand calibration
## on the painted art so the marker lands on the calibrated dots.
func _project_to(ll: Vector2, inner: Rect2, warp: bool) -> Vector2:
	var uv := _raw_uv(ll)
	if warp and _tex != null:
		uv = _warp_uv(uv)
	uv = Vector2(clampf(uv.x, 0.0, 1.0), clampf(uv.y, 0.0, 1.0))
	return inner.position + uv * inner.size


func _draw_marker(p: Vector2) -> void:
	draw_circle(p, 7.0, Color(0.9, 0.1, 0.1))
	draw_arc(p, 7.0, 0.0, TAU, 24, Color.WHITE, 2.0)