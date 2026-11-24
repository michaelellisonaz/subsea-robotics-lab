## Inertial measurement unit with attitude output (AHRS-style).
##
## Gyro: body angular rates + bias + white noise; the bias follows a random
## walk (bias instability). Accelerometer: specific force (acceleration minus
## gravity) of the vehicle, from the change in velocity per physics step, plus
## white noise. Attitude: roll and pitch with white noise (a real AHRS would
## estimate these by fusing gyro and accelerometer; that filter is not
## modelled). Heading comes from the compass.
##
## Outputs use vehicle conventions: rates for roll (+ starboard down), pitch
## (+ nose up) and yaw (+ clockwise) in deg/s; accelerations forward,
## starboard and up in m/s². The IMU is assumed aligned with the body axes
## and close to the CG (lever-arm effects ignored).
class_name ImuSensor
extends Sensor

const PARAMETERS := {
	"gyro_noise": {"label": "Gyro noise (1σ)", "unit": "°/s", "min": 0.0, "max": 2.0, "default": 0.05, "step": 0.01,
		"description": "White noise on each angular-rate reading."},
	"gyro_bias_walk": {"label": "Gyro bias walk", "unit": "°/s/√s", "min": 0.0, "max": 0.2, "default": 0.005, "step": 0.001,
		"description": "Random-walk growth of the gyro bias (bias instability)."},
	"accel_noise": {"label": "Accel noise (1σ)", "unit": "m/s²", "min": 0.0, "max": 1.0, "default": 0.02, "step": 0.005,
		"description": "White noise on each acceleration reading."},
	"attitude_noise": {"label": "Roll / pitch noise (1σ)", "unit": "°", "min": 0.0, "max": 5.0, "default": 0.1, "step": 0.01,
		"description": "Error of the roll and pitch outputs."},
}

## Current gyro bias (roll, pitch, yaw rates), deg/s.
var gyro_bias: Vector3 = Vector3.ZERO
var _last_velocity: Vector3 = Vector3.ZERO
var _has_last_velocity: bool = false
var _acceleration: Vector3 = Vector3.ZERO


func _init() -> void:
	sensor_name = "IMU"
	sensor_type = "imu"
	description = "Angular rates, accelerations and roll / pitch."
	define_default("rate_hz", 50.0)
	define_default("latency", 0.01)


func _own_parameters() -> Dictionary:
	return PARAMETERS


func _reset_state() -> void:
	gyro_bias = Vector3.ZERO
	_has_last_velocity = false
	_acceleration = Vector3.ZERO


func _on_step(context: StepContext, host: RigidSimBody) -> void:
	if _has_last_velocity:
		_acceleration = (host.velocity - _last_velocity) / context.dt
	_last_velocity = host.velocity
	_has_last_velocity = true
	var walk := get_param("gyro_bias_walk") * sqrt(context.dt)
	if walk > 0.0:
		gyro_bias += Vector3(gaussian(walk), gaussian(walk), gaussian(walk))


func _measure(reading: SensorReading, context: StepContext, host: RigidSimBody) -> void:
	var w := host.angular_velocity
	var rates := Vector3(rad_to_deg(-w.z), rad_to_deg(w.x), rad_to_deg(-w.y))
	var gyro_sigma := get_param("gyro_noise")
	var measured_rates := rates + gyro_bias + Vector3(gaussian(gyro_sigma), gaussian(gyro_sigma), gaussian(gyro_sigma))
	var specific_force := host.orientation.inverse() * (_acceleration + Vector3(0.0, context.environment.gravity, 0.0))
	var accel := WorldFrame.body_to_vehicle(specific_force)
	var accel_sigma := get_param("accel_noise")
	var measured_accel := accel + Vector3(gaussian(accel_sigma), gaussian(accel_sigma), gaussian(accel_sigma))
	var attitude := WorldFrame.attitude_of(host.orientation)
	var attitude_sigma := get_param("attitude_noise")
	reading.values = {
		"roll_rate": measured_rates.x, "pitch_rate": measured_rates.y, "yaw_rate": measured_rates.z,
		"accel_forward": measured_accel.x, "accel_starboard": measured_accel.y, "accel_up": measured_accel.z,
		"roll": attitude.x + gaussian(attitude_sigma), "pitch": attitude.y + gaussian(attitude_sigma),
	}
	reading.truth = {
		"roll_rate": rates.x, "pitch_rate": rates.y, "yaw_rate": rates.z,
		"accel_forward": accel.x, "accel_starboard": accel.y, "accel_up": accel.z,
		"roll": attitude.x, "pitch": attitude.y,
	}
