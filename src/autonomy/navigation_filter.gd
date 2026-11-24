## Navigation filter: estimates the vehicle's horizontal position from its
## sensors only (never from the simulation truth).
##
## A linear Kalman filter on the state x = (east, north):
##   predict  x += v_en · dt, with v_en the DVL velocity over the seabed
##            rotated to east / north by the compass heading;
##            P += Q · dt, Q from the DVL and compass noise (datasheet values
##            taken from the sensors' settings) and the speed;
##   update   with each USBL fix z = (east, north), corrected for the
##            transponder's mounting offset from the CG: innovation against the
##            estimate at the time the fix was MEASURED (the filter keeps a
##            short history, because USBL fixes arrive late), Mahalanobis
##            gate (99 %, chi² 2 dof = 9.21) to reject outliers,
##            R from the USBL range / angle noise at the fix's range.
## Without DVL bottom lock the last velocity is kept and Q grows quickly.
## Depth comes from the depth sensor, heading from the compass, pitch / roll
## from the IMU, altitude from the DVL (or the altimeter).
##
## Simplifications: 2-D position only (depth is measured directly), heading is
## taken as exact in the prediction (its noise enters Q), compass deviation
## and the USBL transceiver position are assumed calibrated, no smoothing.
class_name NavigationFilter
extends RefCounted

const GATE := 9.21
const HISTORY_SECONDS := 5.0
const DVL_TIMEOUT := 1.0
const DVL_CORRELATION := 0.2  # s, DVL readings hold their value between pings
const LOST_DVL_Q := 0.0025  # m²/s position random walk without the DVL

var initialized: bool = false
var east: float = 0.0
var north: float = 0.0
## Covariance [[pee, pen], [pen, pnn]], m².
var pee: float = 0.0
var pnn: float = 0.0
var pen: float = 0.0
var depth: float = NAN
var heading: float = NAN  # degrees
var pitch: float = 0.0
var roll: float = 0.0
var altitude: float = NAN
var velocity_en: Vector2 = Vector2.ZERO
var dvl_ok: bool = false
var fixes_used: int = 0
var fixes_rejected: int = 0
var last_innovation: float = 0.0

var _history: Array = []  # [time, east, north]
var _last_dvl_time: float = NAN
var _last_usbl_time: float = NAN


func reset() -> void:
	initialized = false
	east = 0.0
	north = 0.0
	pee = 0.0
	pnn = 0.0
	pen = 0.0
	depth = NAN
	heading = NAN
	altitude = NAN
	velocity_en = Vector2.ZERO
	dvl_ok = false
	fixes_used = 0
	fixes_rejected = 0
	last_innovation = 0.0
	_history.clear()
	_last_dvl_time = NAN
	_last_usbl_time = NAN


## 1-σ horizontal position uncertainty, m (largest axis).
func sigma() -> float:
	var trace := pee + pnn
	var det := pee * pnn - pen * pen
	var largest := trace * 0.5 + sqrt(maxf(0.0, trace * trace * 0.25 - det))
	return sqrt(maxf(largest, 0.0))


## Estimated position in world coordinates (x east, y up, z south).
func world_position() -> Vector3:
	return Vector3(east, -depth if not is_nan(depth) else 0.0, -north)


## Estimated vehicle orientation from compass heading and IMU pitch / roll.
func world_basis() -> Basis:
	var yaw := -deg_to_rad(heading if not is_nan(heading) else 0.0)
	return Basis.from_euler(Vector3(deg_to_rad(pitch), yaw, -deg_to_rad(roll)), EULER_ORDER_YXZ)


## Called after the sensors have updated, every simulation step.
func update(vehicle: RovVehicle, now: float, dt: float) -> void:
	var sensors := vehicle.sensors
	var compass := sensors.get_sensor("Compass")
	if compass != null and compass.latest != null:
		heading = float(compass.latest.values["heading"])
	var depth_sensor := sensors.get_sensor("Depth")
	if depth_sensor != null and depth_sensor.latest != null:
		depth = float(depth_sensor.latest.values["depth"])
	var imu := sensors.get_sensor("IMU")
	if imu != null and imu.latest != null:
		pitch = float(imu.latest.values["pitch"])
		roll = float(imu.latest.values["roll"])
	_read_dvl(sensors, compass, now)
	if initialized:
		_predict(sensors, compass, dt)
		_history.append([now, east, north])
		while _history.size() > 1 and now - _history[0][0] > HISTORY_SECONDS:
			_history.pop_front()
	_read_usbl(sensors, now)


func _read_dvl(sensors: SensorSuite, compass: Sensor, now: float) -> void:
	var dvl := sensors.get_sensor("DVL")
	dvl_ok = dvl != null and dvl.has_fresh_reading(now, DVL_TIMEOUT) and compass != null and compass.latest != null
	if not dvl_ok:
		return
	var reading := dvl.latest
	if reading.time == _last_dvl_time:
		return
	_last_dvl_time = reading.time
	# DVL velocity in body axes (x starboard, y up, z aft) is the velocity of
	# the DVL itself: remove the rotation term ω × r (IMU rates, DVL lever arm)
	# and rotate by the full estimated attitude (compass heading, IMU pitch /
	# roll), so pitching while working does not read as horizontal motion.
	var v_body := Vector3(float(reading.values["starboard"]), float(reading.values["up"]), -float(reading.values["forward"]))
	var imu := sensors.get_sensor("IMU")
	if imu != null and imu.latest != null:
		var rates: Dictionary = imu.latest.values
		var omega := Vector3(deg_to_rad(float(rates["pitch_rate"])), -deg_to_rad(float(rates["yaw_rate"])), -deg_to_rad(float(rates["roll_rate"])))
		v_body -= omega.cross(dvl.mount_position)
	var v_world := world_basis() * v_body
	velocity_en = Vector2(v_world.x, -v_world.z)
	altitude = float(reading.values["altitude"])


func _predict(sensors: SensorSuite, compass: Sensor, dt: float) -> void:
	east += velocity_en.x * dt
	north += velocity_en.y * dt
	var q := LOST_DVL_Q
	if dvl_ok:
		var dvl := sensors.get_sensor("DVL")
		var speed := velocity_en.length()
		var sigma_v: float = dvl.get_param("velocity_noise_abs") / 1000.0 + dvl.get_param("velocity_noise_rel") / 100.0 * speed
		var sigma_h := deg_to_rad(compass.get_param("heading_noise")) * speed
		q = (sigma_v * sigma_v + sigma_h * sigma_h) * DVL_CORRELATION + 1e-6
	pee += q * dt
	pnn += q * dt


func _read_usbl(sensors: SensorSuite, now: float) -> void:
	var usbl := sensors.get_sensor("USBL")
	if usbl == null or usbl.latest == null or usbl.latest.time == _last_usbl_time:
		return
	var reading := usbl.latest
	_last_usbl_time = reading.time
	var z := Vector2(float(reading.values["east"]), float(reading.values["north"]))
	# The fix is the transponder's position: remove its lever arm from the CG
	# (known mounting, rotated by the compass heading).
	if not is_nan(heading):
		var h := deg_to_rad(heading)
		var arm: Vector3 = usbl.mount_position
		z -= Vector2(cos(h), -sin(h)) * arm.x + Vector2(sin(h), cos(h)) * (-arm.z)
	var slant := float(reading.values["slant_range"])
	var sigma_r: float = usbl.get_param("range_noise")
	var sigma_a: float = deg_to_rad(usbl.get_param("angle_noise")) * slant
	var r := sigma_r * sigma_r + sigma_a * sigma_a + 1e-4
	if not initialized:
		initialized = true
		east = z.x
		north = z.y
		pee = r * 4.0
		pnn = r * 4.0
		pen = 0.0
		_history = [[now, east, north]]
		return
	# Innovation against the estimate when the fix was measured.
	var past := Vector2(east, north)
	for entry in _history:
		if entry[0] >= reading.time:
			past = Vector2(entry[1], entry[2])
			break
	var y := z - past
	var s_ee := pee + r
	var s_nn := pnn + r
	var s_en := pen
	var det := s_ee * s_nn - s_en * s_en
	if det <= 0.0:
		return
	var inv_ee := s_nn / det
	var inv_nn := s_ee / det
	var inv_en := -s_en / det
	var d2 := y.x * (inv_ee * y.x + inv_en * y.y) + y.y * (inv_en * y.x + inv_nn * y.y)
	last_innovation = y.length()
	if d2 > GATE:
		fixes_rejected += 1
		return
	# K = P S^-1
	var k_ee := pee * inv_ee + pen * inv_en
	var k_en := pee * inv_en + pen * inv_nn
	var k_ne := pen * inv_ee + pnn * inv_en
	var k_nn := pen * inv_en + pnn * inv_nn
	var dx := k_ee * y.x + k_en * y.y
	var dy := k_ne * y.x + k_nn * y.y
	east += dx
	north += dy
	for entry in _history:
		entry[1] += dx
		entry[2] += dy
	# P = (I - K) P
	var new_ee := (1.0 - k_ee) * pee - k_en * pen
	var new_en := (1.0 - k_ee) * pen - k_en * pnn
	var new_nn := -k_ne * pen + (1.0 - k_nn) * pnn
	pee = new_ee
	pen = new_en
	pnn = new_nn
	fixes_used += 1
