## Multibeam swath profile: measured seabed points (across-track offset vs.
## distance below the transducer) with the transducer at the top centre.
class_name MultibeamDisplay
extends Control

var multibeam: MultibeamSonar
var _last_time: float = -1.0


func _init() -> void:
	custom_minimum_size = Vector2(320.0, 110.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(p_multibeam: MultibeamSonar) -> void:
	multibeam = p_multibeam


func _process(_delta: float) -> void:
	if multibeam != null and multibeam.latest != null and multibeam.latest.time != _last_time and is_visible_in_tree():
		_last_time = multibeam.latest.time
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.BG_INPUT)
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.BORDER, false, 1.0)
	var font := get_theme_default_font()
	var dim := Color(0.55, 0.85, 0.95, 0.4)
	if multibeam == null or multibeam.latest == null or not multibeam.latest.valid:
		draw_string(font, Vector2(8.0, 18.0), "No swath (start the simulation; seabed within range?)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim)
		return
	var across: PackedFloat32Array = multibeam.latest.values["across"]
	var below: PackedFloat32Array = multibeam.latest.values["below"]
	var max_below := 1.0
	var max_across := 1.0
	for i in across.size():
		if not is_nan(across[i]):
			max_below = maxf(max_below, below[i])
			max_across = maxf(max_across, absf(across[i]))
	var px_per_m := minf((size.x * 0.5 - 10.0) / max_across, (size.y - 22.0) / max_below)
	var top := Vector2(size.x * 0.5, 8.0)
	draw_circle(top, 3.0, UITheme.ACCENT)
	var previous := Vector2.INF
	for i in across.size():
		if is_nan(across[i]):
			previous = Vector2.INF
			continue
		var p := top + Vector2(across[i], below[i]) * px_per_m
		if previous != Vector2.INF:
			draw_line(previous, p, Color(1.0, 0.6, 0.2), 1.5)
		draw_circle(p, 1.6, Color(1.0, 0.75, 0.35))
		previous = p
	draw_string(font, Vector2(6.0, size.y - 6.0), "swath %.1f m wide · %.1f m deep below transducer" % [2.0 * max_across, max_below],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
