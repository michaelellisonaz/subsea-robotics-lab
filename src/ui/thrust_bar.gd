## Bidirectional bar for a thruster: fills from the centre to the right for
## forward thrust and to the left for reverse thrust (fraction -1..1).
class_name ThrustBar
extends Control

var fraction: float = 0.0:
	set(value):
		var clamped := clampf(value, -1.0, 1.0)
		if clamped != fraction:
			fraction = clamped
			queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(110.0, 12.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, UITheme.BG_INPUT)
	draw_rect(rect, UITheme.BORDER, false, 1.0)
	var half := size.x * 0.5
	var width := half * absf(fraction)
	var color := UITheme.ACCENT if fraction >= 0.0 else UITheme.STATE_PAUSED
	var x := half if fraction >= 0.0 else half - width
	if width > 0.5:
		draw_rect(Rect2(x, 2.0, width, size.y - 4.0), color)
	draw_line(Vector2(half, 0.0), Vector2(half, size.y), UITheme.TEXT_DIM, 1.0)
