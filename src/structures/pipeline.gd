## Industrial subsea pipeline (reusable structure).
##
## A straight steel pipe running east-west, resting on concrete supports a
## small gap above the seabed, with bolted flange joints at regular intervals
## and blind flanges at both ends. Two defects are defined with their true
## positions:
##   corrosion - external corrosion over a length of pipe (top half)
##   crack     - a short circumferential crack
##
## Geometry is built from solid primitives (pipe cylinder, flange cylinders,
## support boxes, anode bracelets, installed clamps), so sensors, vehicle
## contact and objects all interact with it. The defects do not change the
## shape.
##
## Work / repair state (Stage 5):
##   * Surface deposits on a grid (0.05 m along the pipe x 36 sectors of 10°):
##     2 mm of marine growth over the intact coating everywhere, and 3 mm of
##     corrosion product where the coating has failed (the corroded section,
##     top half). Cleaning tools remove deposit; where the coating has failed
##     a cleaned cell is bare steel.
##   * Cathodic protection: potential (mV vs Ag/AgCl) from working anodes,
##     E = E_free + ΔE · Σ exp(-d_i / λ), with d_i the distance to anode i.
##     Bracelet anodes at E -24 and E +24 work; the one at E 0 is depleted,
##     which leaves the middle of the line under-protected (less negative than
##     the -800 mV criterion). A retrofit anode connected near the line
##     restores protection.
##   * Repair clamps: a clamp seated concentric with the pipe, aligned with
##     its axis and clear of flanges / supports / anodes is installed and
##     becomes part of the structure; it repairs the crack if it covers it
##     with a seal margin.
##
## Simplifications: no wall thickness or internal flow, no pipeline stresses,
## free spans or burial; straight route only. The CP model is an empirical
## attenuation curve, not a solution of the potential field; deposits have no
## effect on CP; clamps have no pressure rating.
class_name Pipeline
extends Structure

const PARAMETER_ORDER := ["diameter", "span_height"]
const PARAMETERS := {
	"diameter": {"label": "Pipeline diameter", "unit": "m", "min": 0.2, "max": 1.2, "default": 0.6, "step": 0.01,
		"description": "Outside diameter of the steel pipe."},
	"span_height": {"label": "Gap above seabed", "unit": "m", "min": 0.1, "max": 1.0, "default": 0.25, "step": 0.01,
		"description": "Height of the supports: gap between the seabed and the pipe bottom."},
}
## Route: from START_EAST to END_EAST metres east, NORTH metres north of the origin.
const START_EAST := -30.0
const END_EAST := 30.0
const NORTH := 6.0
const JOINT_SPACING := 12.0
const SUPPORT_SPACING := 6.0
const FLANGE_THICKNESS := 0.12

# --- Work / repair state ---
const CELL_LENGTH := 0.05  # m along the pipe
const SECTORS := 36  # around the circumference, 10° each
const MARINE_GROWTH_MM := 2.0
const CORROSION_PRODUCT_MM := 3.0
## Deposit below this counts as clean (bare steel where the coating failed), mm.
const CLEAN_THRESHOLD_MM := 0.2
## deposit_bytes: 255 = this thickness, mm.
const DEPOSIT_SCALE_MM := 3.0
const CP_FREE_POTENTIAL := -620.0  # mV vs Ag/AgCl, unprotected steel
const CP_ANODE_DRIVE := -430.0  # mV at an anode
const CP_ATTENUATION_LENGTH := 10.0  # m
const CP_MOST_NEGATIVE := -1100.0  # mV
## Protection criterion for carbon steel in seawater, mV vs Ag/AgCl.
const CP_CRITERION := -800.0
## Bracelet anodes: [east, working].
const BRACELET_ANODES := [[-24.0, true], [0.0, false], [24.0, true]]
const BRACELET_LENGTH := 0.4
const BRACELET_THICKNESS := 0.035
## A clamp must overlap the crack by at least this much on each side, m.
const CLAMP_SEAL_MARGIN := 0.05
const CLAMP_ALIGNMENT_DEGREES := 10.0
const CLAMP_RADIAL_TOLERANCE := 0.03  # m
const CLAMP_DIAMETER_TOLERANCE := 0.02  # m, inner radius - pipe radius

## Emitted when deposits, anodes or clamps change.
signal repair_state_changed()

var _values: Dictionary = {}
var _seabed_y: float = 0.0

## Deposit thickness per cell, mm: index = sector * cell_count() + cell.
var deposit := PackedFloat32Array()
## Same as bytes (0-255 over DEPOSIT_SCALE_MM), for the renderer's texture.
var deposit_bytes := PackedByteArray()
## Incremented whenever deposits change.
var deposit_version: int = 0
## Connected retrofit anodes: owner instance id -> world position (ids, not
## references, so items and the pipeline do not keep each other alive).
var retrofit_anodes: Dictionary = {}
## Installed clamps: {"east", "length", "inner_radius", "outer_radius", "owner" (instance id)}.
var clamps: Array[Dictionary] = []
## Incremented by rebuild(): installed clamps no longer fit after an edit.
var geometry_generation: int = 0

# Running counts kept by clean() so the statistics are cheap to read.
var _clean_cells: int = 0
var _failed_cells: int = 0
var _failed_clean_cells: int = 0
var _least_protected_cache: Dictionary = {}


func _init(seabed_reference_y: float = 0.0) -> void:
	structure_name = "Pipeline PL-01"
	for key in PARAMETER_ORDER:
		_values[key] = float(PARAMETERS[key]["default"])
	_seabed_y = seabed_reference_y
	rebuild()
	_reset_deposits()


static func get_spec(key: String) -> Dictionary:
	return PARAMETERS.get(key, {})


func get_value(key: String) -> float:
	return _values.get(key, 0.0)


func set_value(key: String, value: float) -> float:
	if not PARAMETERS.has(key) or is_nan(value):
		return get_value(key)
	var v := clampf(value, PARAMETERS[key]["min"], PARAMETERS[key]["max"])
	if v != _values[key]:
		_values[key] = v
		rebuild()
	return v


func reset_to_defaults() -> void:
	for key in PARAMETER_ORDER:
		_values[key] = float(PARAMETERS[key]["default"])
	rebuild()


func radius() -> float:
	return _values["diameter"] * 0.5


func flange_radius() -> float:
	return radius() + 0.06 + 0.06 * _values["diameter"]


## Height (world y) of the pipe axis.
func axis_y() -> float:
	return _seabed_y + _values["span_height"] + radius()


func axis_z() -> float:
	return -NORTH


## East positions of the flanged joints (excluding the end flanges).
func joint_positions() -> Array[float]:
	var result: Array[float] = []
	var x := START_EAST + JOINT_SPACING
	while x < END_EAST - 0.1:
		result.append(x)
		x += JOINT_SPACING
	return result


func support_positions() -> Array[float]:
	var result: Array[float] = []
	var x := START_EAST + SUPPORT_SPACING * 0.5
	while x < END_EAST:
		result.append(x)
		x += SUPPORT_SPACING
	return result


func shift(offset: Vector3) -> void:
	_seabed_y += offset.y
	_least_protected_cache = {}
	super(offset)


func rebuild() -> void:
	geometry_generation += 1
	_least_protected_cache = {}
	clamps.clear()
	primitives.clear()
	defects.clear()
	var r := radius()
	var y := axis_y()
	var z := axis_z()
	primitives.append(CylinderPrimitive.new(Vector3(START_EAST, y, z), Vector3(END_EAST, y, z), r, "pipe"))
	var flange_r := flange_radius()
	var flanges: Array[float] = joint_positions()
	flanges.push_front(START_EAST + FLANGE_THICKNESS * 0.5)
	flanges.append(END_EAST - FLANGE_THICKNESS * 0.5)
	for x in flanges:
		primitives.append(CylinderPrimitive.new(Vector3(x - FLANGE_THICKNESS * 0.5, y, z), Vector3(x + FLANGE_THICKNESS * 0.5, y, z), flange_r, "flange"))
	var support_height: float = _values["span_height"] + r * 0.5
	for x in support_positions():
		primitives.append(BoxPrimitive.new(
			Vector3(x, _seabed_y + support_height * 0.5, z),
			Vector3(0.25, support_height * 0.5, r + 0.25), "support"))
	for spec in BRACELET_ANODES:
		var ax: float = spec[0]
		primitives.append(CylinderPrimitive.new(Vector3(ax - BRACELET_LENGTH * 0.5, y, z), Vector3(ax + BRACELET_LENGTH * 0.5, y, z),
			r + BRACELET_THICKNESS, "anode"))
	defects.append({
		"type": "corrosion", "east_from": 8.5, "east_to": 11.5,
		"position": Vector3(10.0, y + r, z),
		"description": "External corrosion, top half of the pipe, 3 m long",
	})
	defects.append({
		"type": "crack", "east": -10.5, "length": 0.35, "clock_degrees": 25.0,
		"position": Vector3(-10.5, y + r * cos(deg_to_rad(25.0)), z - r * sin(deg_to_rad(25.0))),
		"description": "Circumferential crack, 0.35 m long, near the 1 o'clock position (north side)",
	})
	_update_aabb()
	geometry_changed.emit()


func reset_state() -> void:
	retrofit_anodes.clear()
	rebuild()
	_reset_deposits()
	repair_state_changed.emit()


# --- Surface deposits and cleaning ------------------------------------------------

func cell_count() -> int:
	return int(round((END_EAST - START_EAST) / CELL_LENGTH))


## Clock position of a point around the pipe, degrees: 0 = top, +90 = north
## side, -90 = south side, ±180 = bottom.
func clock_degrees(point: Vector3) -> float:
	return rad_to_deg(atan2(-(point.z - axis_z()), point.y - axis_y()))


## True where the coating has failed (corroded section, top half).
func coating_failed(east: float, clock: float) -> bool:
	var corrosion := _defect("corrosion")
	return not corrosion.is_empty() and east >= corrosion["east_from"] and east <= corrosion["east_to"] and absf(clock) <= 90.0


func deposit_at(point: Vector3) -> float:
	var index := _cell_index(point.x, clock_degrees(point))
	return deposit[index] if index >= 0 else 0.0


## What a tool touching `point` on `primitive` is in contact with:
## "bare steel", "corrosion product", "marine growth", "coating", or the
## primitive tag ("flange", "anode", "support", "clamp").
func surface_kind(point: Vector3, primitive: StructurePrimitive) -> String:
	if primitive == null:
		return ""
	if primitive.tag != "pipe":
		return primitive.tag
	var clock := clock_degrees(point)
	var is_clean := deposit_at(point) < CLEAN_THRESHOLD_MM
	if coating_failed(point.x, clock):
		return "bare steel" if is_clean else "corrosion product"
	return "coating" if is_clean else "marine growth"


## Metallic contact for a CP probe: flanges and anodes are bare metal, the pipe
## only where the coating failed and the deposit has been cleaned off.
func is_bare_metal(point: Vector3, primitive: StructurePrimitive) -> bool:
	return surface_kind(point, primitive) in ["bare steel", "flange", "anode"]


## Removes up to `removal_mm` of deposit from every cell whose surface centre
## lies within `reach` of `point`. Returns the number of cells changed.
func clean(point: Vector3, reach: float, removal_mm: float) -> int:
	var n := cell_count()
	var r := radius()
	var first := maxi(0, int(floor((point.x - reach - START_EAST) / CELL_LENGTH)))
	var last := mini(n - 1, int(floor((point.x + reach - START_EAST) / CELL_LENGTH)))
	var touched := 0
	for cell in range(first, last + 1):
		var x := START_EAST + (cell + 0.5) * CELL_LENGTH
		for sector in SECTORS:
			var clock := deg_to_rad(-180.0 + (sector + 0.5) * 360.0 / SECTORS)
			var surface := Vector3(x, axis_y() + r * cos(clock), axis_z() - r * sin(clock))
			if surface.distance_to(point) > reach:
				continue
			var index := sector * n + cell
			if deposit[index] <= 0.0:
				continue
			var was_clean := deposit[index] < CLEAN_THRESHOLD_MM
			deposit[index] = maxf(0.0, deposit[index] - removal_mm)
			deposit_bytes[index] = _to_byte(deposit[index])
			touched += 1
			if not was_clean and deposit[index] < CLEAN_THRESHOLD_MM:
				_clean_cells += 1
				if coating_failed(x, rad_to_deg(clock)):
					_failed_clean_cells += 1
	if touched > 0:
		deposit_version += 1
	return touched


## Area cleaned down to below CLEAN_THRESHOLD_MM, m².
func cleaned_area() -> float:
	return _clean_cells * _cell_area()


## Fraction of the failed-coating area that has been cleaned to bare steel.
func corrosion_exposed_fraction() -> float:
	return float(_failed_clean_cells) / _failed_cells if _failed_cells > 0 else 0.0


func _reset_deposits() -> void:
	var n := cell_count()
	deposit.resize(n * SECTORS)
	deposit_bytes.resize(n * SECTORS)
	_clean_cells = 0
	_failed_cells = 0
	_failed_clean_cells = 0
	for sector in SECTORS:
		var clock := -180.0 + (sector + 0.5) * 360.0 / SECTORS
		for cell in n:
			var x := START_EAST + (cell + 0.5) * CELL_LENGTH
			var failed := coating_failed(x, clock)
			if failed:
				_failed_cells += 1
			var value := CORROSION_PRODUCT_MM if failed else MARINE_GROWTH_MM
			deposit[sector * n + cell] = value
			deposit_bytes[sector * n + cell] = _to_byte(value)
	deposit_version += 1


func _cell_index(east: float, clock: float) -> int:
	var cell := int(floor((east - START_EAST) / CELL_LENGTH))
	if cell < 0 or cell >= cell_count():
		return -1
	var sector := int(floor((clock + 180.0) / (360.0 / SECTORS))) % SECTORS
	return sector * cell_count() + cell


func _cell_area() -> float:
	return CELL_LENGTH * TAU * radius() / SECTORS


static func _to_byte(mm: float) -> int:
	return clampi(int(round(mm / DEPOSIT_SCALE_MM * 255.0)), 0, 255)


## True if a fitting on the as-built drawing (flange, anode band, clamp) lies
## within `margin` of `east`: its edges look like circumferential lines.
func known_fitting_near(east: float, margin: float) -> bool:
	for primitive in primitives:
		if primitive.tag in ["flange", "anode", "clamp"]:
			if east >= primitive.aabb.position.x - margin and east <= primitive.aabb.end.x + margin:
				return true
	return false


## Ground-truth defect of a type ({} if none).
func defect(type: String) -> Dictionary:
	return _defect(type)


func _defect(type: String) -> Dictionary:
	for defect in defects:
		if defect["type"] == type:
			return defect
	return {}


# --- Cathodic protection ----------------------------------------------------------

## World positions of the working anodes (bracelets and connected retrofits).
func working_anodes() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for spec in BRACELET_ANODES:
		if spec[1]:
			result.append(Vector3(spec[0], axis_y(), axis_z()))
	for owner in retrofit_anodes:
		result.append(retrofit_anodes[owner])
	return result


## Protection potential of the pipe steel near `point`, mV vs Ag/AgCl (ground truth).
func cp_potential(point: Vector3) -> float:
	var total := 0.0
	for anode in working_anodes():
		total += exp(-anode.distance_to(point) / CP_ATTENUATION_LENGTH)
	return maxf(CP_MOST_NEGATIVE, CP_FREE_POTENTIAL + CP_ANODE_DRIVE * total)


## Least protected point along the pipe top (0.5 m sampling): {"east", "potential"}.
## Cached until the anodes or the geometry change.
func least_protected() -> Dictionary:
	if not _least_protected_cache.is_empty():
		return _least_protected_cache
	var worst := {"east": START_EAST, "potential": -INF}
	var x := START_EAST
	while x <= END_EAST + 1e-6:
		var e := cp_potential(Vector3(x, axis_y() + radius(), axis_z()))
		if e > worst["potential"]:
			worst = {"east": x, "potential": e}
		x += 0.5
	_least_protected_cache = worst
	return worst


## Connects (position = Vector3) or disconnects (position = null) a retrofit anode.
func set_retrofit_anode(owner: Object, position: Variant) -> void:
	var key := owner.get_instance_id()
	if position == null:
		if retrofit_anodes.erase(key):
			_least_protected_cache = {}
			repair_state_changed.emit()
		return
	var is_new := not retrofit_anodes.has(key)
	if is_new or (retrofit_anodes[key] as Vector3).distance_to(position) > 0.01:
		_least_protected_cache = {}
	retrofit_anodes[key] = position
	if is_new:
		repair_state_changed.emit()


# --- Repair clamps ----------------------------------------------------------------

## Checks whether a clamp centred at `center` with its axis along `axis_dir`
## can close around the pipe there: {"ok": bool, "reason": String}.
func clamp_fit(center: Vector3, axis_dir: Vector3, inner_radius: float, length: float) -> Dictionary:
	if center.x - length * 0.5 < START_EAST + 0.2 or center.x + length * 0.5 > END_EAST - 0.2:
		return {"ok": false, "reason": "not over the pipeline"}
	var radial := Vector2(center.y - axis_y(), center.z - axis_z()).length()
	if radial > 0.3:
		return {"ok": false, "reason": "not around the pipe"}
	var misalignment := rad_to_deg(acos(clampf(absf(axis_dir.normalized().x), 0.0, 1.0)))
	if misalignment > CLAMP_ALIGNMENT_DEGREES:
		return {"ok": false, "reason": "clamp axis %.0f° off the pipe axis (max %.0f°)" % [misalignment, CLAMP_ALIGNMENT_DEGREES]}
	if radial > CLAMP_RADIAL_TOLERANCE:
		return {"ok": false, "reason": "not seated: %.0f mm off the pipe centreline (max %.0f mm)" % [radial * 1000.0, CLAMP_RADIAL_TOLERANCE * 1000.0]}
	var gap := inner_radius - radius()
	if gap < 0.0 or gap > CLAMP_DIAMETER_TOLERANCE:
		return {"ok": false, "reason": "clamp bore does not fit a Ø %.2f m pipe" % get_value("diameter")}
	for primitive in primitives:
		if primitive.tag in ["flange", "support", "anode", "clamp"]:
			if primitive.aabb.position.x < center.x + length * 0.5 and primitive.aabb.end.x > center.x - length * 0.5:
				return {"ok": false, "reason": "obstructed by a %s" % primitive.tag}
	return {"ok": true, "reason": ""}


func install_clamp(east: float, length: float, inner_radius: float, outer_radius: float, owner: Object) -> void:
	clamps.append({"east": east, "length": length, "inner_radius": inner_radius, "outer_radius": outer_radius, "owner": owner.get_instance_id()})
	primitives.append(CylinderPrimitive.new(Vector3(east - length * 0.5, axis_y(), axis_z()),
		Vector3(east + length * 0.5, axis_y(), axis_z()), outer_radius, "clamp"))
	_update_aabb()
	geometry_changed.emit()
	repair_state_changed.emit()


## "open", or "clamped" when an installed clamp covers the crack with the seal margin.
func crack_status() -> String:
	var crack := _defect("crack")
	if crack.is_empty():
		return "none"
	for c in clamps:
		if absf(c["east"] - crack["east"]) <= c["length"] * 0.5 - CLAMP_SEAL_MARGIN:
			return "clamped"
	return "open"
