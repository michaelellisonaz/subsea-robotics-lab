## Autopilot: drives the vehicle to a target pose using only estimated /
## measured quantities (NavigationFilter position and velocity, compass,
## depth sensor, altitude).
##
## Horizontal: PID on the estimated east / north error, rotated into surge /
## sway commands (command = clamp(Kp·e, accel) + Ki·∫e - Kd·v). The clamp
## limits the transit speed (≈ 0.3 m/s with the defaults).
## Depth and heading: the existing sensor-based depth and heading holds do
## the work; the autopilot only moves their setpoints (in altitude mode the
## depth setpoint follows the measured altitude). Attitude hold keeps the
## vehicle level.
class_name Autopilot
extends RefCounted

const KP := 0.5  # command per m
const KI := 0.03  # per m·s
const KD := 1.5  # per m/s
const INTEGRAL_LIMIT := 6.0  # m·s
const DEFAULT_MAX_COMMAND := 0.35
## Arrival tolerances.
const POSITION_TOLERANCE := 0.15  # m
const HEADING_TOLERANCE := 4.0  # degrees
const SPEED_TOLERANCE := 0.05  # m/s

var active: bool = false
var target_east: float = 0.0
var target_north: float = 0.0
var target_heading: float = 0.0
## Depth target, or NAN in altitude mode.
var target_depth: float = NAN
## Altitude target (used when target_depth is NAN), m.
var target_altitude: float = 1.5
var max_command: float = DEFAULT_MAX_COMMAND

var _integral: Vector2 = Vector2.ZERO


func reset() -> void:
	active = false
	_integral = Vector2.ZERO


func set_target(east: float, north: float, heading: float, depth: float = NAN, altitude: float = 1.5) -> void:
	target_east = east
	target_north = north
	target_heading = fposmod(heading, 360.0)
	target_depth = depth
	target_altitude = altitude


## Horizontal distance from the estimate to the target, m.
func position_error(nav: NavigationFilter) -> float:
	return Vector2(target_east - nav.east, target_north - nav.north).length()


func heading_error(nav: NavigationFilter) -> float:
	return absf(wrapf(target_heading - nav.heading, -180.0, 180.0))


func arrived(nav: NavigationFilter) -> bool:
	return nav.initialized and position_error(nav) < POSITION_TOLERANCE \
		and heading_error(nav) < HEADING_TOLERANCE and nav.velocity_en.length() < SPEED_TOLERANCE


## Writes surge / sway into `commands` and moves the depth / heading
## setpoints. Returns false (and does nothing) without a position estimate.
func apply(vehicle: RovVehicle, nav: NavigationFilter, commands: PackedFloat64Array, now: float, dt: float) -> bool:
	if not active or not nav.initialized or is_nan(nav.heading) or is_nan(nav.depth):
		return false
	var aids := vehicle.aids
	if not aids.heading_hold:
		aids.set_heading_hold(true, vehicle, now)
	if not aids.depth_hold:
		aids.set_depth_hold(true, vehicle, now)
	if not aids.attitude_hold:
		aids.set_attitude_hold(true, vehicle, now)
	if aids.position_hold:
		aids.set_position_hold(false, vehicle, now)
	aids.heading_setpoint = target_heading
	if not is_nan(target_depth):
		aids.depth_setpoint = target_depth
	elif not is_nan(nav.altitude) and nav.dvl_ok:
		aids.depth_setpoint = nav.depth + (nav.altitude - target_altitude)
	var error := Vector2(target_east - nav.east, target_north - nav.north)
	_integral = (_integral + error * dt).limit_length(INTEGRAL_LIMIT)
	var demand := (error * KP).limit_length(max_command) + _integral * KI - nav.velocity_en * KD
	var h := deg_to_rad(nav.heading)
	var forward_en := Vector2(sin(h), cos(h))
	var starboard_en := Vector2(cos(h), -sin(h))
	commands[RovVehicle.Axis.SURGE] = clampf(demand.dot(forward_en), -1.0, 1.0)
	commands[RovVehicle.Axis.SWAY] = clampf(demand.dot(starboard_en), -1.0, 1.0)
	commands[RovVehicle.Axis.HEAVE] = 0.0
	commands[RovVehicle.Axis.YAW] = 0.0
	return true
