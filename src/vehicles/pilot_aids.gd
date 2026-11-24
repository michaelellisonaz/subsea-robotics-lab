## Pilot aids: automatic depth hold and heading hold, using SENSOR READINGS
## only (never the true state), so sensor noise, bias and latency affect the
## control loops exactly as they would on a real vehicle.
##
## Depth hold (PID): measured depth from the depth sensor; depth rate from the
## DVL vertical velocity when it has bottom lock, otherwise from successive
## depth readings (filtered). Output: heave command.
## Heading hold (PD): measured heading from the compass, yaw rate from the
## IMU gyro. Output: yaw command.
##
## Position hold / station keeping (PID): DVL dead reckoning. The DVL
## velocity over the seabed, rotated to east/north with the compass heading,
## is integrated into an estimated displacement since the hold was engaged;
## surge and sway commands drive that estimate back to zero. Because it uses
## sensor readings, DVL noise and compass error make the held position wander
## slowly (dead-reckoning drift), as on a real vehicle.
##
## Attitude hold / auto-trim (PID): keeps the vehicle level (pitch and roll
## zero) using the IMU attitude and rates, driving the pitch and roll
## commands. Needed for manipulator work: an outstretched arm or a payload
## would otherwise trim the vehicle nose-down.
##
## Engaging captures the current measured value as the setpoint. While the
## pilot gives a heave (or yaw) command, that axis is flown manually and the
## setpoint follows; when the pilot lets go, the new value is held. An aid
## disengages itself if its sensor stops delivering readings.
##
## Gains are tuned for the default SRL-1 configuration (critically damped to
## slightly overdamped); other configurations may need retuning.
class_name PilotAids
extends RefCounted

const DEPTH_KP := 0.5  # heave command per m
const DEPTH_KI := 0.05  # per m·s
const DEPTH_KD := 1.2  # per m/s
const DEPTH_INTEGRAL_LIMIT := 4.0  # m·s
const HEADING_KP := 0.02  # yaw command per degree
const HEADING_KD := 0.012  # per °/s
const POSITION_KP := 0.6  # surge / sway command per m
const POSITION_KI := 0.04  # per m·s
const POSITION_KD := 1.5  # per m/s
const POSITION_INTEGRAL_LIMIT := 5.0  # m·s
const ATTITUDE_KP := 0.05  # pitch / roll command per degree
const ATTITUDE_KI := 0.02  # per degree·s
const ATTITUDE_KD := 0.03  # per °/s
const ATTITUDE_INTEGRAL_LIMIT := 40.0  # degree·s
const OVERRIDE_THRESHOLD := 0.05
const SENSOR_TIMEOUT := 1.0  # s

var depth_hold: bool = false
var heading_hold: bool = false
var position_hold: bool = false
var attitude_hold: bool = false
## Estimated horizontal displacement (east, north) since position hold was
## engaged, from DVL dead reckoning, m.
var position_offset: Vector2 = Vector2.ZERO
var depth_setpoint: float = 0.0
var heading_setpoint: float = 0.0
## Last message about an aid that could not engage or was dropped.
var status: String = ""

var _depth_integral: float = 0.0
var _depth_rate: float = 0.0
var _last_depth: float = NAN
var _last_depth_time: float = NAN
var _position_integral: Vector2 = Vector2.ZERO
var _attitude_integral: Vector2 = Vector2.ZERO  # (pitch, roll)
var _velocity_en: Vector2 = Vector2.ZERO
var _last_dvl_time: float = NAN
## Depth readings measured before this time are ignored (site shifted).
var _ignore_depth_before: float = -INF


## Moves the depth setpoint (the site moved vertically at time `now`).
## Readings measured before the move are still in the sensor pipeline and
## are ignored, so they cannot produce a false error.
func shift_depth(delta_depth: float, now: float) -> void:
	depth_setpoint += delta_depth
	_last_depth = NAN
	_last_depth_time = NAN
	_ignore_depth_before = now


func reset() -> void:
	depth_hold = false
	heading_hold = false
	position_hold = false
	attitude_hold = false
	_attitude_integral = Vector2.ZERO
	_reset_position_filter()
	status = ""
	_reset_depth_filter()


## Engages / disengages depth hold. Returns false if it cannot engage.
func set_depth_hold(enable: bool, vehicle: RovVehicle, now: float) -> bool:
	if not enable:
		depth_hold = false
		return true
	var sensor := vehicle.sensors.get_sensor("Depth")
	if sensor == null or not sensor.has_fresh_reading(now, SENSOR_TIMEOUT):
		status = "Depth hold needs readings from the depth sensor (is the simulation running and the sensor enabled?)."
		depth_hold = false
		return false
	depth_setpoint = sensor.latest.values["depth"]
	_reset_depth_filter()
	depth_hold = true
	status = ""
	return true


## Engages / disengages heading hold. Returns false if it cannot engage.
func set_heading_hold(enable: bool, vehicle: RovVehicle, now: float) -> bool:
	if not enable:
		heading_hold = false
		return true
	var sensor := vehicle.sensors.get_sensor("Compass")
	if sensor == null or not sensor.has_fresh_reading(now, SENSOR_TIMEOUT):
		status = "Heading hold needs readings from the compass (is the simulation running and the sensor enabled?)."
		heading_hold = false
		return false
	heading_setpoint = sensor.latest.values["heading"]
	heading_hold = true
	status = ""
	return true


## Engages / disengages position hold (needs DVL bottom lock and compass).
func set_position_hold(enable: bool, vehicle: RovVehicle, now: float) -> bool:
	if not enable:
		position_hold = false
		return true
	var dvl := vehicle.sensors.get_sensor("DVL")
	var compass := vehicle.sensors.get_sensor("Compass")
	if dvl == null or compass == null or not dvl.has_fresh_reading(now, SENSOR_TIMEOUT) or not compass.has_fresh_reading(now, SENSOR_TIMEOUT):
		status = "Position hold needs DVL bottom lock and compass readings."
		position_hold = false
		return false
	_reset_position_filter()
	position_hold = true
	status = ""
	return true


## Engages / disengages attitude hold (needs IMU readings). Target: level.
func set_attitude_hold(enable: bool, vehicle: RovVehicle, now: float) -> bool:
	if not enable:
		attitude_hold = false
		return true
	var imu := vehicle.sensors.get_sensor("IMU")
	if imu == null or not imu.has_fresh_reading(now, SENSOR_TIMEOUT):
		status = "Attitude hold needs IMU readings."
		attitude_hold = false
		return false
	_attitude_integral = Vector2.ZERO
	attitude_hold = true
	status = ""
	return true


## Returns the commands with the held axes replaced by the controllers' output.
func apply(vehicle: RovVehicle, commands: PackedFloat64Array, now: float, dt: float) -> PackedFloat64Array:
	if depth_hold:
		_apply_depth_hold(vehicle, commands, now, dt)
	if heading_hold:
		_apply_heading_hold(vehicle, commands, now)
	if position_hold:
		_apply_position_hold(vehicle, commands, now, dt)
	if attitude_hold:
		_apply_attitude_hold(vehicle, commands, now, dt)
	return commands


func _apply_attitude_hold(vehicle: RovVehicle, commands: PackedFloat64Array, now: float, dt: float) -> void:
	var imu := vehicle.sensors.get_sensor("IMU")
	if not imu.has_fresh_reading(now, SENSOR_TIMEOUT):
		attitude_hold = false
		status = "Attitude hold released: no IMU data."
		return
	var values := imu.latest.values
	if absf(commands[RovVehicle.Axis.PITCH]) > OVERRIDE_THRESHOLD or absf(commands[RovVehicle.Axis.ROLL]) > OVERRIDE_THRESHOLD:
		_attitude_integral = Vector2.ZERO
		return
	var error := Vector2(-float(values["pitch"]), -float(values["roll"]))
	_attitude_integral = (_attitude_integral + error * dt).clamp(
		Vector2(-ATTITUDE_INTEGRAL_LIMIT, -ATTITUDE_INTEGRAL_LIMIT), Vector2(ATTITUDE_INTEGRAL_LIMIT, ATTITUDE_INTEGRAL_LIMIT))
	var rates := Vector2(float(values["pitch_rate"]), float(values["roll_rate"]))
	var output := error * ATTITUDE_KP + _attitude_integral * ATTITUDE_KI - rates * ATTITUDE_KD
	commands[RovVehicle.Axis.PITCH] = clampf(output.x, -1.0, 1.0)
	commands[RovVehicle.Axis.ROLL] = clampf(output.y, -1.0, 1.0)


func _apply_position_hold(vehicle: RovVehicle, commands: PackedFloat64Array, now: float, dt: float) -> void:
	var dvl := vehicle.sensors.get_sensor("DVL")
	var compass := vehicle.sensors.get_sensor("Compass")
	if not dvl.has_fresh_reading(now, SENSOR_TIMEOUT) or not compass.has_fresh_reading(now, SENSOR_TIMEOUT):
		position_hold = false
		status = "Position hold released: no DVL bottom lock or compass data."
		return
	var h := deg_to_rad(float(compass.latest.values["heading"]))
	var forward_en := Vector2(sin(h), cos(h))
	var starboard_en := Vector2(cos(h), -sin(h))
	var reading := dvl.latest
	if reading.time != _last_dvl_time:
		var v: Vector2 = forward_en * float(reading.values["forward"]) + starboard_en * float(reading.values["starboard"])
		if not is_nan(_last_dvl_time):
			position_offset += v * (reading.time - _last_dvl_time)
		_velocity_en = v
		_last_dvl_time = reading.time
	if absf(commands[RovVehicle.Axis.SURGE]) > OVERRIDE_THRESHOLD or absf(commands[RovVehicle.Axis.SWAY]) > OVERRIDE_THRESHOLD:
		position_offset = Vector2.ZERO
		_position_integral = Vector2.ZERO
		return
	var error := -position_offset
	_position_integral = (_position_integral + error * dt).limit_length(POSITION_INTEGRAL_LIMIT)
	var demand := error * POSITION_KP + _position_integral * POSITION_KI - _velocity_en * POSITION_KD
	commands[RovVehicle.Axis.SURGE] = clampf(demand.dot(forward_en), -1.0, 1.0)
	commands[RovVehicle.Axis.SWAY] = clampf(demand.dot(starboard_en), -1.0, 1.0)


func _reset_position_filter() -> void:
	position_offset = Vector2.ZERO
	_position_integral = Vector2.ZERO
	_velocity_en = Vector2.ZERO
	_last_dvl_time = NAN


func _apply_depth_hold(vehicle: RovVehicle, commands: PackedFloat64Array, now: float, dt: float) -> void:
	var sensor := vehicle.sensors.get_sensor("Depth")
	if not sensor.has_fresh_reading(now, SENSOR_TIMEOUT):
		depth_hold = false
		status = "Depth hold released: no depth sensor data."
		return
	var reading := sensor.latest
	if reading.time <= _ignore_depth_before:
		return
	var depth: float = reading.values["depth"]
	var rate := NAN
	var dvl := vehicle.sensors.get_sensor("DVL")
	if dvl != null and dvl.has_fresh_reading(now, SENSOR_TIMEOUT):
		rate = -float(dvl.latest.values["up"])
	if reading.time != _last_depth_time:
		if not is_nan(_last_depth):
			var differenced := (depth - _last_depth) / (reading.time - _last_depth_time)
			_depth_rate = lerpf(_depth_rate, differenced, 0.3)
		_last_depth = depth
		_last_depth_time = reading.time
	if is_nan(rate):
		rate = _depth_rate
	if absf(commands[RovVehicle.Axis.HEAVE]) > OVERRIDE_THRESHOLD:
		depth_setpoint = depth
		_depth_integral = 0.0
		return
	var error := depth - depth_setpoint  # positive = too deep -> heave up
	_depth_integral = clampf(_depth_integral + error * dt, -DEPTH_INTEGRAL_LIMIT, DEPTH_INTEGRAL_LIMIT)
	commands[RovVehicle.Axis.HEAVE] = clampf(DEPTH_KP * error + DEPTH_KI * _depth_integral + DEPTH_KD * rate, -1.0, 1.0)


func _apply_heading_hold(vehicle: RovVehicle, commands: PackedFloat64Array, now: float) -> void:
	var compass := vehicle.sensors.get_sensor("Compass")
	if not compass.has_fresh_reading(now, SENSOR_TIMEOUT):
		heading_hold = false
		status = "Heading hold released: no compass data."
		return
	var heading: float = compass.latest.values["heading"]
	if absf(commands[RovVehicle.Axis.YAW]) > OVERRIDE_THRESHOLD:
		heading_setpoint = heading
		return
	var yaw_rate := 0.0
	var imu := vehicle.sensors.get_sensor("IMU")
	if imu != null and imu.has_fresh_reading(now, SENSOR_TIMEOUT):
		yaw_rate = imu.latest.values["yaw_rate"]
	var error := wrapf(heading_setpoint - heading, -180.0, 180.0)  # positive -> turn clockwise
	commands[RovVehicle.Axis.YAW] = clampf(HEADING_KP * error - HEADING_KD * yaw_rate, -1.0, 1.0)


func _reset_depth_filter() -> void:
	_ignore_depth_before = -INF
	_depth_integral = 0.0
	_depth_rate = 0.0
	_last_depth = NAN
	_last_depth_time = NAN
