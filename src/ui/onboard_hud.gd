## Overlay for the onboard camera view: centre reticle, artificial horizon,
## heading tape and vehicle status. Like a real pilot display, it shows SENSOR
## READINGS (depth sensor, compass, IMU attitude, DVL / altimeter altitude,
## DVL speed), so noise, latency and dropouts are visible; "---" means the
## sensor has no valid reading.
class_name OnboardHud
extends Control

const HUD_COLOR := Color(0.55, 0.95, 1.0, 0.9)
const HUD_DIM := Color(0.55, 0.95, 1.0, 0.45)
const WARN_COLOR := Color(1.0, 0.75, 0.3, 0.95)
const CAMERA_FOV := 70.0
const FONT_SIZE := 14

var vehicle: RovVehicle
var world: WorldModel
var engine: SimulationEngine
## True while the keyboard drives the manipulator.
var arm_mode: bool = false
## Screen space covered by side panels, so readouts stay in the visible view.
var inset_left: float = 0.0
var inset_right: float = 0.0


func _init() -> void:
	name = "OnboardHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(p_vehicle: RovVehicle, p_world: WorldModel, p_engine: SimulationEngine) -> void:
	vehicle = p_vehicle
	world = p_world
	engine = p_engine


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if vehicle == null:
		return
	var view := size
	var c := view * 0.5
	var font := get_theme_default_font()
	var px_per_degree := view.y / CAMERA_FOV

	# Corner brackets of the camera frame.
	var m := 40.0
	var k := 28.0
	var x0 := inset_left + m
	var x1 := view.x - inset_right - m
	for corner in [Vector2(x0, 90.0), Vector2(x1, 90.0), Vector2(x0, view.y - 70.0), Vector2(x1, view.y - 70.0)]:
		var sx := 1.0 if corner.x < c.x else -1.0
		var sy := 1.0 if corner.y < c.y else -1.0
		draw_line(corner, corner + Vector2(k * sx, 0.0), HUD_DIM, 2.0)
		draw_line(corner, corner + Vector2(0.0, k * sy), HUD_DIM, 2.0)

	# Centre reticle.
	draw_arc(c, 5.0, 0.0, TAU, 20, HUD_COLOR, 1.5)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(c + d * 12.0, c + d * 30.0, HUD_COLOR, 2.0)

	var m_values := measured_values()
	# Artificial horizon (IMU attitude): shifted by pitch, rotated by roll.
	var pitch: float = 0.0 if is_nan(m_values["pitch"]) else m_values["pitch"]
	var roll := deg_to_rad(0.0 if is_nan(m_values["roll"]) else m_values["roll"])
	var direction := Vector2(cos(roll), -sin(roll))
	var horizon_center := c + Vector2(0.0, pitch * px_per_degree).rotated(-roll)
	draw_line(horizon_center - direction * 260.0, horizon_center - direction * 70.0, HUD_COLOR, 1.5)
	draw_line(horizon_center + direction * 70.0, horizon_center + direction * 260.0, HUD_COLOR, 1.5)
	for ladder in [-20, -10, 10, 20]:
		var offset := Vector2(0.0, (pitch + ladder) * px_per_degree).rotated(-roll)
		var p := c + offset
		draw_line(p - direction * 40.0, p + direction * 40.0, HUD_DIM, 1.0)
		draw_string(font, p + direction * 46.0 + Vector2(0, 5), "%+d" % -ladder, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HUD_DIM)

	# Heading tape (compass).
	var heading: float = 0.0 if is_nan(m_values["heading"]) else m_values["heading"]
	var tape_y := 112.0
	var tape_half := minf(240.0, (x1 - x0) * 0.3)
	var px_per_heading_degree := tape_half / 45.0
	draw_line(Vector2(c.x - tape_half, tape_y), Vector2(c.x + tape_half, tape_y), HUD_DIM, 1.0)
	var start := int(floor((heading - 45.0) / 5.0)) * 5
	for deg in range(start, int(heading + 45.0) + 1, 5):
		var x := c.x + (deg - heading) * px_per_heading_degree
		if absf(x - c.x) > tape_half:
			continue
		var major := posmod(deg, 30) == 0
		draw_line(Vector2(x, tape_y), Vector2(x, tape_y - (12.0 if major else 6.0)), HUD_COLOR if major else HUD_DIM, 1.5)
		if major:
			var wrapped := posmod(deg, 360)
			var text := WorldFrame.cardinal(wrapped) if wrapped % 90 == 0 else "%03d" % wrapped
			draw_string(font, Vector2(x - 14.0, tape_y - 16.0), text, HORIZONTAL_ALIGNMENT_CENTER, 28, 12, HUD_COLOR)
	draw_colored_polygon(PackedVector2Array([Vector2(c.x, tape_y + 2), Vector2(c.x - 6, tape_y + 12), Vector2(c.x + 6, tape_y + 12)]), HUD_COLOR)
	draw_string(font, Vector2(c.x - 40.0, tape_y + 30.0), "HDG " + _fmt("%05.1f°", m_values["heading"]), HORIZONTAL_ALIGNMENT_CENTER, 80, FONT_SIZE, HUD_COLOR)

	# Left block: depth / altitude / speed (sensor readings).
	var altitude: float = m_values["altitude"]
	var left := Vector2(x0 + 24.0, c.y - 60.0)
	_text(font, left, "DEPTH  " + _fmt("%6.2f m", m_values["depth"]), HUD_COLOR)
	_text(font, left + Vector2(0, 22), "ALT    " + _fmt("%6.2f m", altitude), WARN_COLOR if not is_nan(altitude) and altitude < 0.5 else HUD_COLOR)
	_text(font, left + Vector2(0, 44), "SPEED  " + _fmt("%6.2f m/s", m_values["speed"]), HUD_COLOR)
	_text(font, left + Vector2(0, 66), "SURGE  " + _fmt("%+6.2f m/s", m_values["surge"]), HUD_DIM)

	# Right block: attitude, equipment and pilot aids.
	var right := Vector2(x1 - 190.0, c.y - 60.0)
	_text(font, right, "PITCH  " + _fmt("%+6.1f°", m_values["pitch"]), HUD_COLOR)
	_text(font, right + Vector2(0, 22), "ROLL   " + _fmt("%+6.1f°", m_values["roll"]), HUD_COLOR)
	_text(font, right + Vector2(0, 44), "LIGHTS %s" % ("ON" if vehicle.lights_on else "OFF"), HUD_COLOR)
	if vehicle.autonomy.mission_running():
		_text(font, Vector2(c.x - 120.0, view.y - 156.0), "AUTONOMY · %s" % vehicle.autonomy.mission.status, WARN_COLOR)
	if arm_mode:
		var arm := vehicle.manipulator
		var gripper := "HOLDING" if arm.grasped != null else ("CLOSING" if arm.gripper_closing else "OPEN")
		var line := "ARM CONTROL · GRIPPER %s · IK %s" % [gripper, arm.ik_status.to_upper()]
		if arm.tool_change_phase != "":
			line = "ARM CONTROL · TOOL CHANGE"
		elif arm.tool != null:
			line = "ARM CONTROL · %s %s · %.0f N" % [arm.tool.display_name.to_upper(), "ON" if arm.tool.active else "OFF", arm.tool.contact_force]
		if arm.blocked:
			line += " · BLOCKED"
		_text(font, Vector2(c.x - 120.0, view.y - 112.0), line, WARN_COLOR)
		if arm.tool != null:
			_text(font, Vector2(c.x - 120.0, view.y - 134.0), arm.tool.status, HUD_COLOR)
	if vehicle.aids.depth_hold:
		_text(font, right + Vector2(0, 66), "DEPTH HOLD %.2f m" % vehicle.aids.depth_setpoint, WARN_COLOR)
	if vehicle.aids.heading_hold:
		_text(font, right + Vector2(0, 88), "HDG HOLD %05.1f°" % vehicle.aids.heading_setpoint, WARN_COLOR)
	if vehicle.aids.position_hold:
		_text(font, right + Vector2(0, 110), "POS HOLD %.2f m" % vehicle.aids.position_offset.length(), WARN_COLOR)
	if vehicle.aids.attitude_hold:
		_text(font, right + Vector2(0, 132), "LEVEL HOLD", WARN_COLOR)

	# Bottom status line.
	var status := "CAM 1 · %s · T+ %s" % [engine.get_state_name(), SimulationBar.format_time(engine.get_sim_time())]
	draw_string(font, Vector2(c.x - 200.0, view.y - 84.0), status, HORIZONTAL_ALIGNMENT_CENTER, 400, FONT_SIZE, HUD_DIM)


## Values shown on the HUD, from sensor readings (NAN when unavailable).
func measured_values() -> Dictionary:
	var now := vehicle.last_update_time
	var result := {"depth": NAN, "heading": NAN, "pitch": NAN, "roll": NAN, "altitude": NAN, "speed": NAN, "surge": NAN}
	var depth := vehicle.sensors.get_sensor("Depth")
	if depth.has_fresh_reading(now, 2.0):
		result["depth"] = depth.latest.values["depth"]
	var compass := vehicle.sensors.get_sensor("Compass")
	if compass.has_fresh_reading(now, 2.0):
		result["heading"] = compass.latest.values["heading"]
	var imu := vehicle.sensors.get_sensor("IMU")
	if imu.has_fresh_reading(now, 2.0):
		result["pitch"] = imu.latest.values["pitch"]
		result["roll"] = imu.latest.values["roll"]
	var dvl := vehicle.sensors.get_sensor("DVL")
	if dvl.has_fresh_reading(now, 2.0):
		var v := Vector3(dvl.latest.values["forward"], dvl.latest.values["starboard"], dvl.latest.values["up"])
		result["altitude"] = dvl.latest.values["altitude"]
		result["speed"] = v.length()
		result["surge"] = v.x
	else:
		var altimeter := vehicle.sensors.get_sensor("Altimeter")
		if altimeter.has_fresh_reading(now, 2.0):
			result["altitude"] = altimeter.latest.values["range"]
	return result


static func _fmt(fmt: String, value: float) -> String:
	return "---" if is_nan(value) or is_inf(value) else fmt % value


func _text(font: Font, at: Vector2, text: String, color: Color) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
