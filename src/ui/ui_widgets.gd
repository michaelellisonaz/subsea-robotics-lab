## Small factory helpers shared by the dashboard panels.
class_name UIWidgets
extends RefCounted


static func section_header(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_color_override("font_color", UITheme.ACCENT)
	label.add_theme_font_size_override("font_size", 12)
	box.add_child(label)
	box.add_child(HSeparator.new())
	return box


static func button(text: String, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	# No keyboard focus: Space must reach the simulation shortcut, not a button.
	b.focus_mode = Control.FOCUS_NONE
	return b


static func dim_label(text: String, tooltip: String = "") -> Label:
	var label := Label.new()
	label.text = text
	label.tooltip_text = tooltip
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	return label


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func spin_box(min_value: float, max_value: float, step: float, suffix: String, tooltip: String = "") -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.suffix = suffix
	spin.tooltip_text = tooltip
	spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spin.select_all_on_focus = true
	spin.custom_minimum_size = Vector2(132.0, 0.0)
	return spin
