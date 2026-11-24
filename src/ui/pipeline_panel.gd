## Pipeline settings in the Environment tab: diameter and gap above the
## seabed (applied immediately), the ground-truth defect markers, and the
## work / repair status (cleaning, crack clamp, cathodic protection).
class_name PipelinePanel
extends VBoxContainer

var markers_toggle: CheckBox

var _pipeline: Pipeline
var _rows: Dictionary = {}
var _updating: bool = false
var _status: Dictionary = {}
var _elapsed: float = 0.0


func _init() -> void:
	name = "PipelinePanel"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func bind(pipeline: Pipeline, renderer: PipelineRenderer) -> void:
	_pipeline = pipeline
	add_child(UIWidgets.section_header(pipeline.structure_name))
	var note := UIWidgets.dim_label("Steel pipe on concrete supports, 60 m long, 6 m north of the site origin. Flanged joints every 12 m.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	for key in Pipeline.PARAMETER_ORDER:
		var spec := Pipeline.get_spec(key)
		var header := HBoxContainer.new()
		var label := Label.new()
		label.text = spec["label"]
		label.tooltip_text = spec["description"]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(label)
		var spin := UIWidgets.spin_box(spec["min"], spec["max"], spec["step"], spec["unit"], spec["description"])
		header.add_child(spin)
		add_child(header)
		var slider := HSlider.new()
		slider.min_value = spec["min"]
		slider.max_value = spec["max"]
		slider.step = spec["step"]
		slider.focus_mode = Control.FOCUS_NONE
		add_child(slider)
		_rows[key] = {"spin": spin, "slider": slider}
		spin.value_changed.connect(_on_changed.bind(key))
		slider.value_changed.connect(_on_changed.bind(key))
		_sync(key)
	markers_toggle = CheckBox.new()
	markers_toggle.text = "Show defect locations (ground truth)"
	markers_toggle.tooltip_text = "Labels the corrosion and the crack. Leave off to search for them yourself."
	markers_toggle.focus_mode = Control.FOCUS_NONE
	markers_toggle.toggled.connect(renderer.set_defect_markers_visible)
	add_child(markers_toggle)
	var edit_note := UIWidgets.dim_label("Editing the diameter or gap rebuilds the pipe: an installed clamp no longer fits and is released.")
	edit_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(edit_note)

	add_child(UIWidgets.spacer(4.0))
	add_child(UIWidgets.section_header("Work and repair status"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	for row in [["cleaned", "Area cleaned", "Pipe surface cleaned to below 0.2 mm of deposit."],
			["exposed", "Corroded area exposed", "Share of the failed-coating area cleaned to bare steel (needed for CP readings and inspection)."],
			["crack", "Crack", "Open, or repaired by a clamp covering it with 50 mm margin each side."],
			["anodes", "Working anodes", "Bracelet anodes plus connected retrofit anodes."],
			["cp", "Least protected (truth)", "Ground-truth potential of the least protected point (criterion -800 mV vs Ag/AgCl)."]]:
		grid.add_child(UIWidgets.dim_label(row[1], row[2]))
		var value := Label.new()
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(value)
		_status[row[0]] = value
	add_child(grid)
	refresh_status()


func get_status_text(key: String) -> String:
	return _status[key].text


func _process(delta: float) -> void:
	if _pipeline == null:
		return
	_elapsed += delta
	if _elapsed >= 0.25 and is_visible_in_tree():
		_elapsed = 0.0
		refresh_status()


func refresh_status() -> void:
	_status["cleaned"].text = "%.2f m²" % _pipeline.cleaned_area()
	_status["exposed"].text = "%.0f %%" % (_pipeline.corrosion_exposed_fraction() * 100.0)
	var crack := _pipeline.crack_status()
	var clamp_text := ""
	for c in _pipeline.clamps:
		clamp_text += " · clamp at E %.2f" % c["east"]
	_status["crack"].text = ("REPAIRED (clamped)" if crack == "clamped" else "open") + clamp_text
	var bracelets := 0
	for spec in Pipeline.BRACELET_ANODES:
		if spec[1]:
			bracelets += 1
	_status["anodes"].text = "%d bracelets + %d retrofit (bracelet at E 0 depleted)" % [bracelets, _pipeline.retrofit_anodes.size()]
	var worst := _pipeline.least_protected()
	var ok: bool = worst["potential"] <= Pipeline.CP_CRITERION
	_status["cp"].text = "%.0f mV at E %.1f  %s" % [worst["potential"], worst["east"], "protected" if ok else "UNDER-PROTECTED"]


func get_spin(key: String) -> SpinBox:
	return _rows[key]["spin"]


func _on_changed(value: float, key: String) -> void:
	if _updating:
		return
	_pipeline.set_value(key, value)
	_sync(key)


func _sync(key: String) -> void:
	_updating = true
	_rows[key]["spin"].value = _pipeline.get_value(key)
	_rows[key]["slider"].value = _pipeline.get_value(key)
	_updating = false
