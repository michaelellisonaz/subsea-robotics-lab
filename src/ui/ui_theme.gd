## Dark engineering-software theme for the dashboard, built in code.
class_name UITheme
extends RefCounted

const BG := Color(0.031, 0.051, 0.071, 0.94)
const BG_RAISED := Color(0.055, 0.086, 0.114, 1.0)
const BG_INPUT := Color(0.02, 0.035, 0.05, 1.0)
const BORDER := Color(0.12, 0.25, 0.32, 1.0)
const ACCENT := Color(0.27, 0.80, 0.93, 1.0)
const ACCENT_DIM := Color(0.14, 0.42, 0.52, 1.0)
const TEXT := Color(0.84, 0.89, 0.92, 1.0)
const TEXT_DIM := Color(0.50, 0.59, 0.65, 1.0)
const STATE_READY := Color(0.55, 0.65, 0.72, 1.0)
const STATE_RUNNING := Color(0.32, 0.86, 0.52, 1.0)
const STATE_PAUSED := Color(0.96, 0.74, 0.28, 1.0)
const FONT_SIZE := 13


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE

	theme.set_stylebox("panel", "PanelContainer", box(BG, BORDER, 4, 10.0))
	theme.set_stylebox("panel", "Panel", box(BG, BORDER, 4, 0.0))
	theme.set_color("font_color", "Label", TEXT)

	var normal := _button_box(BG_RAISED, BORDER)
	var hover := _button_box(BG_RAISED.lightened(0.07), ACCENT_DIM)
	var pressed := _button_box(ACCENT_DIM.darkened(0.35), ACCENT)
	var disabled := _button_box(BG_RAISED.darkened(0.25), BORDER.darkened(0.3))
	for type_name in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type_name, normal)
		theme.set_stylebox("hover", type_name, hover)
		theme.set_stylebox("pressed", type_name, pressed)
		theme.set_stylebox("hover_pressed", type_name, pressed)
		theme.set_stylebox("disabled", type_name, disabled)
		theme.set_stylebox("focus", type_name, StyleBoxEmpty.new())
		theme.set_color("font_color", type_name, TEXT)
		theme.set_color("font_hover_color", type_name, Color.WHITE)
		theme.set_color("font_pressed_color", type_name, ACCENT)
		theme.set_color("font_hover_pressed_color", type_name, ACCENT)
		theme.set_color("font_focus_color", type_name, TEXT)
		theme.set_color("font_disabled_color", type_name, TEXT_DIM.darkened(0.25))

	var empty := StyleBoxEmpty.new()
	for style in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		theme.set_stylebox(style, "CheckBox", empty)
	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_color("font_hover_color", "CheckBox", Color.WHITE)
	theme.set_color("font_pressed_color", "CheckBox", TEXT)
	theme.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)
	theme.set_color("font_focus_color", "CheckBox", TEXT)

	var input := box(BG_INPUT, BORDER, 3, 4.0)
	theme.set_stylebox("normal", "LineEdit", input)
	theme.set_stylebox("read_only", "LineEdit", input)
	theme.set_stylebox("focus", "LineEdit", box(BG_INPUT, ACCENT, 3, 4.0))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", ACCENT_DIM)

	theme.set_stylebox("slider", "HSlider", _track_box(BG_INPUT, BORDER))
	theme.set_stylebox("grabber_area", "HSlider", _track_box(ACCENT_DIM, ACCENT_DIM))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _track_box(ACCENT.darkened(0.15), ACCENT))

	theme.set_stylebox("panel", "PopupMenu", box(BG_RAISED, BORDER, 3, 4.0))
	theme.set_stylebox("hover", "PopupMenu", box(ACCENT_DIM.darkened(0.2), ACCENT_DIM, 2, 2.0))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	theme.set_stylebox("panel", "TooltipPanel", box(Color(0.02, 0.04, 0.06, 0.97), ACCENT_DIM, 3, 6.0))
	theme.set_color("font_color", "TooltipLabel", TEXT)

	theme.set_stylebox("panel", "TabContainer", box(BG, BORDER, 4, 10.0))
	var tab_selected := box(BG_RAISED, ACCENT_DIM, 3, 6.0)
	tab_selected.border_width_top = 2
	tab_selected.border_color = ACCENT
	tab_selected.content_margin_left = 12.0
	tab_selected.content_margin_right = 12.0
	var tab_unselected := box(BG, BORDER, 3, 6.0)
	tab_unselected.content_margin_left = 12.0
	tab_unselected.content_margin_right = 12.0
	var tab_hovered := box(BG_RAISED.lightened(0.04), ACCENT_DIM, 3, 6.0)
	tab_hovered.content_margin_left = 12.0
	tab_hovered.content_margin_right = 12.0
	theme.set_stylebox("tab_selected", "TabContainer", tab_selected)
	theme.set_stylebox("tab_unselected", "TabContainer", tab_unselected)
	theme.set_stylebox("tab_hovered", "TabContainer", tab_hovered)
	theme.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	theme.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	theme.set_color("font_selected_color", "TabContainer", ACCENT)
	theme.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	theme.set_color("font_hovered_color", "TabContainer", TEXT)

	var h_line := StyleBoxLine.new()
	h_line.color = BORDER
	h_line.thickness = 1
	theme.set_stylebox("separator", "HSeparator", h_line)
	var v_line := StyleBoxLine.new()
	v_line.color = BORDER
	v_line.thickness = 1
	v_line.vertical = true
	theme.set_stylebox("separator", "VSeparator", v_line)
	return theme


static func box(bg: Color, border: Color, radius: int = 3, margin: float = 6.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style


static func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var style := box(bg, border, 3, 4.0)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	return style


static func _track_box(bg: Color, border: Color) -> StyleBoxFlat:
	var style := box(bg, border, 2, 0.0)
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style
