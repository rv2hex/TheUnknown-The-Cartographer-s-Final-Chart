class_name StoryOverlay
extends CanvasLayer

## Fullscreen story cards for the voyage of Mr. Axiom. Beats are queued by
## id (Menu fires the intro, ShipHUD fires the rest off quest, valley, and
## crab events) and shown one at a time, pausing the world while a card is
## up. Space continues. Session only: fired beats never repeat.

var _beats := {
	"intro": {
		"title": "IRON GULL — CAST OFF",
		"body": "The air at Iron Gull tasted of salt and rusted iron as dusk settled over the Unseen Reach. Mr. Axiom stood at the helm of the lone Dutch tall ship, a notoriously flawed chart rolled out before him — a world between 140–170°E and 10°S–35°N, and he already knew the ink lied.\n\nElara clung to the rigging, eagle-eyed. Silas gripped the great wooden wheel. Finn stood by the deck lamps, striker in hand. Kael listened to the hull, ready to patch the inevitable splintering.\n\n\"Cast off,\" Axiom ordered. \"We chart the Reach before the moon claims the sky.\"",
	},
	"crescent": {
		"title": "THE CRESCENT LAGOON",
		"body": "Their first mark lay south. The darkness was absolute save the crimson moon when the jagged teeth of the Crescent broke the horizon — a shattered atoll, beautiful and treacherous.\n\n\"Keep us wide, Silas!\" Elara shouted. \"The water in the lagoon is thick!\" The dark soup chewed through wood in seconds; Kael roared from below as it scraped the hull. Silas threw the wheel hard over, riding the safe current just long enough for Axiom to strike a green line through the atoll on his map.",
	},
	"teardrop": {
		"title": "THE TEARDROP",
		"body": "Riding an unnatural tailwind they surged north, where an obsidian dome rose from the waves — perfectly smooth, utterly devoid of life. The water around it hissed, a corrosive ring threatening to strip the pitch from their planks. Axiom marked it green and pushed on.",
	},
	"twin": {
		"title": "THE TWIN SPIRES",
		"body": "The Spires pierced the night like the prongs of a tuning fork. As Silas steered the saddle between the peaks, the wind simply died — the ship dragged, slowed to a crawl by the rock's unnatural pull, while toxic skirt-water bubbled against the hull. Kael hammered a brace below as the timbers groaned. They pushed through, the map glowing with charted victories.",
	},
	"valley": {
		"title": "THE JELLYFISH VALLEY",
		"body": "They turned for the dead middle of the chart as midnight took hold — and the surf was drowned by a low hum vibrating in the crew's teeth.\n\n\"Look up,\" Elara whispered. The sky was alive: eighteen bells, runts to leviathans, drifting a glittering starfield.\n\n\"Finn, the lamps are burning!\" — too late. A bell spun up and plummeted, cracking the hull, then another began its dive.\n\n\"Kill the lamps! Kill them now!\" Finn smothered the flames. The deck went pitch black. The barrage stopped, and the valley hummed in frustration as the pack drifted back up into the night.",
	},
	"crab": {
		"title": "THE CRAB REEF",
		"body": "A thousand meters past the map's edge, a buoy lighthouse swept the water, methodical and cold.\n\n\"Kill the throttle. Drop the sails. Do not move a muscle.\" They drifted in. The ocean erupted — a roar that bypassed the ears and shook the soul. Over six agonizing seconds the reef reared twenty meters into the sky: a crab of impossible proportions, the lighthouse bolted to its shell.\n\nThey sat dead in the water. Finding no threat in the motionless splinter, it began to sink, the roar echoing out over the dive until the buoy vanished beneath the foam.\n\nAxiom exhaled. They were alive, holding a map that finally told the truth.",
	},
	"ending": {
		"title": "THE NOBEL — AND THE EMBRACE",
		"body": "The applause was deafening. Under blinding chandeliers, the Nobel's gold rested cold on Axiom's chest. They had charted the unchartable and lived. Wealth scattered the crew to quiet lives; Axiom bought a cliffside estate, married Evelyn, and fathered a daughter with deep-water eyes.\n\nBut the ocean is a jealous mistress. Red moons rose in his dreams. Whalers whispered of the Kraken's Embrace, a trench past the Twin Spires where the map tears into the abyss.\n\nOne starless night he laid his medal on Evelyn's nightstand, took a striker and a fresh roll of parchment, and walked to the private docks — sailing out to find the Embrace, never to return to the shores of men again.",
	},
}

var _queue: Array = []
var _fired := {}
var _showing := false
var _dim: ColorRect
var _title: Label
var _body: RichTextLabel
var _hint: Label


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.75)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.05, 0.03, 0.97)
	style.border_color = Color(0.92, 0.86, 0.68, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color(0.92, 0.86, 0.68))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = true
	_body.custom_minimum_size = Vector2(580, 320)
	_body.add_theme_font_size_override("normal_font_size", 19)
	_body.add_theme_color_override("default_color", Color(0.88, 0.82, 0.66))
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_body)
	_hint = Label.new()
	_hint.text = "press SPACE to continue"
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)


## Queue a beat by id. Unknown, queued, or already-fired ids are ignored.
func queue_beat(beat_id: String) -> void:
	if not _beats.has(beat_id) or _fired.has(beat_id) or _queue.has(beat_id):
		return
	_queue.append(beat_id)
	_pump()


## True once the beat has been shown and dismissed.
func is_beat_done(beat_id: String) -> bool:
	return _fired.has(beat_id)


func _pump() -> void:
	if _showing or _queue.is_empty():
		return
	var beat_id := String(_queue[0])
	_title.text = String((_beats[beat_id] as Dictionary)["title"])
	_body.text = String((_beats[beat_id] as Dictionary)["body"])
	_showing = true
	visible = true
	get_tree().paused = true


func _continue() -> void:
	if _queue.is_empty():
		return
	_fired[String(_queue[0])] = true
	_queue.pop_front()
	_showing = false
	if _queue.is_empty():
		visible = false
		get_tree().paused = false
	else:
		_pump()


func _unhandled_input(event: InputEvent) -> void:
	if not _showing:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_E):
			_continue()
			get_viewport().set_input_as_handled()
		elif k.pressed and not k.echo and _body != null:
			var vbar := _body.get_v_scroll_bar()
			if vbar != null:
				match k.keycode:
					KEY_PAGEDOWN:
						vbar.value += vbar.page - 20.0
						get_viewport().set_input_as_handled()
					KEY_PAGEUP:
						vbar.value -= vbar.page - 20.0
						get_viewport().set_input_as_handled()
					KEY_HOME:
						vbar.value = vbar.min_value
						get_viewport().set_input_as_handled()
					KEY_END:
						vbar.value = vbar.max_value
						get_viewport().set_input_as_handled()
