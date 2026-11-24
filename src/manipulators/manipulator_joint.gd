## One revolute joint of a manipulator, with a rate-limited servo and
## gear backlash.
##
## The servo drives the MOTOR angle toward the target at up to the joint
## speed (proportional approach, then a clean stop at the target). The LINK
## angle lags the motor by half the backlash in the direction of the last
## motion: link = motor - sign(last motion) · backlash / 2. So the final link
## position depends on the direction it was approached from (hysteresis), as
## with real gearboxes. Inverse kinematics plans motor targets, so backlash
## shows up as tool positioning error.
##
## Simplifications: no motor dynamics or torque limits per joint (the load
## capacity is checked for the whole arm in Manipulator), no compliance.
class_name ManipulatorJoint
extends RefCounted

const SERVO_GAIN := 6.0  # 1/s
const ARRIVAL_TOLERANCE := 1e-5  # rad

var joint_name: String = "J"
## Rotation axis in the joint's own frame.
var axis: Vector3 = Vector3.RIGHT
## Translation from the previous joint frame to this joint, in the previous frame, m.
var offset: Vector3 = Vector3.ZERO
var min_angle: float = -PI  # rad
var max_angle: float = PI  # rad
## True for the wrist roll joint (commanded directly, not used by position IK).
var is_roll: bool = false
## Backlash (total free play), rad.
var backlash: float = 0.0
var motor: float = 0.0
var target: float = 0.0
var _last_direction: float = 0.0


func _init(p_name: String = "J", p_axis: Vector3 = Vector3.RIGHT, p_offset: Vector3 = Vector3.ZERO,
		min_degrees: float = -180.0, max_degrees: float = 180.0, p_is_roll: bool = false) -> void:
	joint_name = p_name
	axis = p_axis.normalized()
	offset = p_offset
	min_angle = deg_to_rad(min_degrees)
	max_angle = deg_to_rad(max_degrees)
	is_roll = p_is_roll


## Actual link angle (motor angle minus backlash lag), rad.
func angle() -> float:
	return motor - _last_direction * backlash * 0.5


func set_target(value: float) -> void:
	target = clampf(value, min_angle, max_angle)


## Places the joint at an angle immediately (no backlash offset).
func place(value: float) -> void:
	set_target(value)
	motor = target
	_last_direction = 0.0


func is_settled() -> bool:
	return absf(target - motor) <= ARRIVAL_TOLERANCE


## Servo state (motor angle, last direction), for undoing a refused motion.
func snapshot() -> Vector2:
	return Vector2(motor, _last_direction)


func restore(state: Vector2) -> void:
	motor = state.x
	_last_direction = state.y


## Advances the servo by dt at up to `speed` rad/s. Returns true while moving.
func step(dt: float, speed: float) -> bool:
	var error := target - motor
	if absf(error) <= ARRIVAL_TOLERANCE:
		motor = target
		return false
	var rate := clampf(error * SERVO_GAIN, -speed, speed)
	if absf(rate * dt) >= absf(error) or absf(error) < deg_to_rad(0.02):
		motor = target
	else:
		motor += rate * dt
	_last_direction = signf(error)
	return true
