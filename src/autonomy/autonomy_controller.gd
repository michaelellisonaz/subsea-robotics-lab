## The vehicle's autonomy: navigation filter (always running), autopilot,
## mission execution and the inspection log fed by the defect detector.
##
## Owned by RovVehicle: pre_step() runs before the pilot aids (the mission
## steps and the autopilot writes surge / sway and moves the aid setpoints),
## post_step() after the sensors (the filter reads the new readings).
## Any manual pilot input while a mission runs aborts it (operator override).
##
## The navigation error against the simulation truth is recorded for
## EVALUATION only; nothing that steers the vehicle reads it.
class_name AutonomyController
extends RefCounted

const OVERRIDE_THRESHOLD := 0.05
## Crack-like detections this close to a known fitting are ignored, m.
const KNOWN_FITTING_MARGIN := 0.35

var nav := NavigationFilter.new()
var autopilot := Autopilot.new()
var inspection := InspectionLog.new()
var mission: Mission = null
## Pipeline as-built data used for work points and detection projection.
var pipeline: Pipeline = null
## True while a survey wants the defect detector to run (InspectionCamera reads it).
var vision_active: bool = false
## Evaluation: horizontal estimate error vs truth while the filter runs, m.
var nav_error: float = 0.0
var nav_error_max: float = 0.0
var _nav_error_sum: float = 0.0
var _nav_error_count: int = 0


func reset() -> void:
	nav.reset()
	autopilot.reset()
	inspection.reset()
	mission = null
	vision_active = false
	nav_error = 0.0
	nav_error_max = 0.0
	_nav_error_sum = 0.0
	_nav_error_count = 0


func mission_running() -> bool:
	return mission != null and mission.state == "running"


func nav_error_mean() -> float:
	return _nav_error_sum / _nav_error_count if _nav_error_count > 0 else 0.0


func start_mission(new_mission: Mission, now: float) -> bool:
	if pipeline == null or not nav.initialized:
		return false
	mission = new_mission
	_nav_error_sum = 0.0
	_nav_error_count = 0
	nav_error_max = 0.0
	mission.start(now)
	return true


func abort(now: float, reason: String) -> void:
	if mission != null:
		mission.abort(now, reason)
	_stop()


func _stop() -> void:
	autopilot.active = false
	vision_active = false


func pre_step(vehicle: RovVehicle, commands: PackedFloat64Array, now: float, dt: float) -> void:
	if not mission_running() and not autopilot.active:
		return
	if mission_running():
		for i in commands.size():
			if absf(commands[i]) > OVERRIDE_THRESHOLD:
				abort(now, "manual pilot input")
				return
		mission.step(self, vehicle, pipeline, now, dt)
		if not mission_running():
			_stop()
			return
	if not autopilot.apply(vehicle, nav, commands, now, dt) and mission_running():
		abort(now, "no navigation estimate")


func post_step(vehicle: RovVehicle, now: float, dt: float) -> void:
	nav.update(vehicle, now, dt)
	if nav.initialized:
		nav_error = Vector2(nav.east - vehicle.position.x, nav.north + vehicle.position.z).length()
		if mission_running():
			nav_error_max = maxf(nav_error_max, nav_error)
			_nav_error_sum += nav_error
			_nav_error_count += 1


## Adds the detections of one analysed camera frame (called by InspectionCamera).
## `camera_pose` is the ESTIMATED camera pose.
func add_vision_frame(result: Dictionary, camera_pose: Transform3D, fov: float, now: float) -> void:
	if pipeline == null:
		return
	inspection.frames_analysed += 1
	for type in ["corrosion", "crack"]:
		for blob in result[type]:
			var hit := DefectDetector.project_to_pipe(blob["center"], result["width"], result["height"], fov, camera_pose, pipeline)
			if hit.is_empty():
				continue
			# Crack-like lines at fittings on the as-built drawing are their edges.
			if type == "crack" and pipeline.known_fitting_near(hit["east"], KNOWN_FITTING_MARGIN):
				inspection.known_fitting_hits += 1
				continue
			inspection.add(type, hit["east"], hit["clock"], now)
