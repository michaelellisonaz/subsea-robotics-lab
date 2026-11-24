## One measurement from a sensor, with the ground truth it was derived from.
## The truth is kept so the dashboard and the tests can show and check the
## measurement error; consumers that model a real system (pilot aids, future
## autonomy) must only use `values`.
class_name SensorReading
extends RefCounted

## Simulation time at which the quantity was measured, s.
var time: float = 0.0
## Simulation time at which the reading is delivered (time + latency), s.
var available_time: float = 0.0
## False when the sensor could not measure (e.g. DVL without bottom lock).
var valid: bool = true
var values: Dictionary = {}
var truth: Dictionary = {}


func age(now: float) -> float:
	return now - time
