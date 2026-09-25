class_name QuestLog
extends Node

## "Chart the Reach": sail within charting range of the three islands —
## Twin Spires, Teardrop, Crescent — plus rare wild islands far off-chart.
## Proximity marks an entry visited; ShipHUD flips it to done (tracker X,
## toast, green marker) only after its story card has been shown. Entries
## without a card chart immediately on visit. Session only.

@export var ship_path := NodePath("../Boat")

var entries: Array = []
var all_done := false

var _ship: Node3D = null
var _wild_added := false


func _ready() -> void:
	entries = [
		{"name": "Twin Spires", "ll": Geo.TWIN_SPIRES, "radius": 320.0, "visited": false, "done": false},
		{"name": "Teardrop", "ll": Geo.TEARDROP, "radius": 200.0, "visited": false, "done": false},
		{"name": "Crescent", "ll": Geo.CRESCENT, "radius": 260.0, "visited": false, "done": false},
	]


## Called by ShipHUD once the entry's story card has been shown (or at
## once for entries with no card).
func force_done(spot_name: String) -> void:
	for e in entries:
		if String(e["name"]) == spot_name:
			e["done"] = true
	if done_count() >= entries.size():
		all_done = true


func done_count() -> int:
	var n := 0
	for e in entries:
		if bool(e["done"]):
			n += 1
	return n


func _physics_process(_delta: float) -> void:
	if all_done:
		return
	if _ship == null:
		_ship = get_node_or_null(ship_path) as Node3D
		return
	_pull_wild_islands()
	var sp: Vector3 = _ship.global_position
	for e in entries:
		if bool(e["visited"]):
			continue
		var home := Geo.world_of_ll(e["ll"])
		if Vector2(sp.x - home.x, sp.z - home.z).length() < float(e["radius"]):
			e["visited"] = true
	if done_count() >= entries.size():
		all_done = true


## Off-chart wild islands become chartable once WorldIslands has built them.
## Retried until the sibling is ready; entries stay stable afterwards.
func _pull_wild_islands() -> void:
	if _wild_added:
		return
	var wi := get_parent().get_node_or_null("WorldIslands")
	if wi == null or not wi.has_method("get_wild_islands"):
		return
	var wilds: Array = wi.call("get_wild_islands")
	if wilds.is_empty():
		return
	for w in wilds:
		entries.append({
			"name": String(w["name"]),
			"ll": w["ll"],
			"radius": float(w["radius"]) + 150.0,
			"visited": false,
			"done": false,
		})
	_wild_added = true
