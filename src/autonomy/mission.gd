## A mission: an ordered list of tasks the AutonomyController executes, each
## using only the navigation estimate, sensor readings and the tool's force
## measurement (never the simulation truth).
##
## Task types ({"type": ..., parameters}):
##   goto    fly to east / north at a heading, at a depth or altitude; done
##           when the estimate has been within tolerance for HOLD_TO_ARRIVE.
##   survey  fly a line at `north` from east_from to east_to at `speed`,
##           with `heading`, at `depth` (or `altitude`); the defect detector
##           runs on the inspection camera meanwhile. The preset flies along
##           the pipe directly above it, so the camera sees the pipe top.
##   tool    change to a tool ("brush", "cp_probe" or "" for the gripper).
##   clean   for each spot (east, on the pipe top): station keep beside it,
##           put the brush above it, spin, lower it until the contact force is
##           in the working range (force-controlled), dwell, lift.
##   cp      for each point (east, kind "pipe" / "flange" / "anode"): station
##           keep, lower the probe until it touches (force-controlled), wait
##           for a reading and log it; with no metallic contact it retries
##           3 cm to either side along the pipe before giving up.
##   hold    keep station for `seconds`.
## A task that times out fails the mission. Positions of work points come from
## the as-built pipeline (route, diameter, flanges, anode bands).
class_name Mission
extends RefCounted

const HOLD_TO_ARRIVE := 2.0  # s
## Tool point relative to the arm base when working on the pipe top.
const WORK_OFFSET := Vector3(0.0, -0.3, -0.6)
const APPROACH_HEIGHT := 0.12  # m above the surface before descending
const DESCENT_STEP := 0.004  # m per command
const DESCENT_INTERVAL := 0.05  # s
const MAX_SEARCH_DEPTH := 0.15  # m below the expected surface before giving up
## Deepest press into the tool's compliant travel (fraction of the travel).
const MAX_TRAVEL_FRACTION := 0.6
## Along-pipe offsets tried when a CP probe finds no bare metal, m.
const CP_RETRY_SHIFTS := [0.03, -0.03]
const BRUSH_FORCE := 60.0  # N target (working range 40-150 N)
const CLEAN_DWELL := 6.0  # s per spot
const CLEAN_SWEEP := 0.04  # m, brush sweep amplitude along the pipe
const CLEAN_SWEEP_PERIOD := 3.0  # s
const PROBE_FORCE := 28.0  # N target (middle of the 10-45 N range)
## Tool pitch for work on the pipe top: straight down, so the contact force
## is vertical and does not push the vehicle sideways.
const WORK_PITCH := -90.0

var mission_name: String = ""
var tasks: Array[Dictionary] = []
var index: int = 0
## "ready", "running", "done", "failed", "aborted".
var state: String = "ready"
var status: String = ""
var log_lines: Array[String] = []
var start_time: float = NAN
var end_time: float = NAN

# Per-task working state.
var _phase: String = ""
var _timer: float = 0.0
var _task_time: float = 0.0
var _item: int = 0
var _offset: float = 0.0
var _work_time: float = 0.0
var _contact_time: float = 0.0
var _retry_shift: float = 0.0
var _attempt: int = 0
var _retrying: bool = false


func _init(p_name: String = "", p_tasks: Array[Dictionary] = []) -> void:
	mission_name = p_name
	tasks = p_tasks


func current_task() -> Dictionary:
	return tasks[index] if index < tasks.size() else {}


func task_label(task: Dictionary) -> String:
	match task.get("type", ""):
		"goto":
			return "Go to E %.1f N %.1f" % [task["east"], task["north"]]
		"survey":
			return "Survey E %.0f → %.0f" % [task["east_from"], task["east_to"]]
		"tool":
			return "Mount %s" % (task["tool"] if task["tool"] != "" else "gripper")
		"clean":
			return "Clean %d spots" % task["spots"].size()
		"cp":
			return "CP readings at %d points" % task["points"].size()
		"hold":
			return "Hold %.0f s" % task["seconds"]
	return "?"


func _log(now: float, text: String) -> void:
	log_lines.append("%6.1f s  %s" % [now, text])
	status = text


func start(now: float) -> void:
	state = "running"
	index = 0
	start_time = now
	_begin_task(now)


func abort(now: float, reason: String) -> void:
	if state == "running":
		state = "aborted"
		end_time = now
		_log(now, "Aborted: %s" % reason)


func _begin_task(now: float) -> void:
	_phase = ""
	_timer = 0.0
	_task_time = 0.0
	_item = 0
	if index >= tasks.size():
		state = "done"
		end_time = now
		_log(now, "Mission complete")
		return
	_log(now, "Task %d/%d: %s" % [index + 1, tasks.size(), task_label(tasks[index])])


func _next(now: float) -> void:
	index += 1
	_begin_task(now)


func _fail(now: float, reason: String) -> void:
	state = "failed"
	end_time = now
	_log(now, "Failed: %s" % reason)


## One simulation step of the mission.
func step(controller: AutonomyController, vehicle: RovVehicle, pipeline: Pipeline, now: float, dt: float) -> void:
	if state != "running":
		return
	var task := tasks[index]
	_task_time += dt
	if _task_time > task.get("timeout", 600.0):
		_fail(now, "%s timed out" % task_label(task))
		return
	var nav := controller.nav
	var pilot := controller.autopilot
	match task["type"]:
		"goto":
			pilot.set_target(task["east"], task["north"], task.get("heading", 0.0), task.get("depth", NAN), task.get("altitude", 1.5))
			pilot.active = true
			_arrive_then_next(pilot, nav, now, dt)
		"hold":
			_hold_here(pilot, nav)
			_timer += dt
			if _timer >= task["seconds"]:
				_next(now)
		"tool":
			_hold_here(pilot, nav)
			var arm := vehicle.manipulator
			var wanted: WorkTool = null
			for t in arm.tools:
				if t.tool_id == task["tool"]:
					wanted = t
			if _phase == "":
				_phase = "changing"
				if not arm.request_tool(wanted):
					_fail(now, "tool change refused: %s" % arm.status_message)
			elif arm.tool_change_phase == "" and arm.tool == wanted:
				_next(now)
		"survey":
			_step_survey(controller, task, pilot, nav, now, dt)
		"clean", "cp":
			_step_work(controller, vehicle, pipeline, task, now, dt)


## Keeps station where the vehicle is when the task starts.
func _hold_here(pilot: Autopilot, nav: NavigationFilter) -> void:
	if not pilot.active or _timer == 0.0 and _phase == "":
		pilot.set_target(nav.east, nav.north, nav.heading, nav.depth)
		pilot.active = true


func _arrive_then_next(pilot: Autopilot, nav: NavigationFilter, now: float, dt: float) -> void:
	if pilot.arrived(nav):
		_timer += dt
		if _timer >= HOLD_TO_ARRIVE:
			_next(now)
	else:
		_timer = 0.0


func _step_survey(controller: AutonomyController, task: Dictionary, pilot: Autopilot, nav: NavigationFilter, now: float, dt: float) -> void:
	var direction := signf(task["east_to"] - task["east_from"])
	if _phase == "":
		_phase = "start"
		_offset = 0.0
	var north: float = task["north"]
	var heading: float = task.get("heading", 0.0)
	var depth: float = task.get("depth", NAN)
	if _phase == "start":
		pilot.set_target(task["east_from"], north, heading, depth, task.get("altitude", 1.5))
		pilot.active = true
		if pilot.arrived(nav):
			_phase = "run"
			controller.vision_active = true
			_log(now, "Surveying (vision on)")
		return
	# Moving target along the route; it waits if the vehicle falls behind.
	if absf(task["east_from"] + _offset * direction - nav.east) < 0.6:
		_offset = minf(_offset + task["speed"] * dt, absf(task["east_to"] - task["east_from"]))
	pilot.set_target(task["east_from"] + _offset * direction, north, heading, depth, task.get("altitude", 1.5))
	if _offset >= absf(task["east_to"] - task["east_from"]) and pilot.position_error(nav) < 0.3:
		controller.vision_active = false
		_next(now)


## Clean / CP point work with the arm. Work points are on the as-built pipe.
func _step_work(controller: AutonomyController, vehicle: RovVehicle, pipeline: Pipeline, task: Dictionary, now: float, dt: float) -> void:
	var arm := vehicle.manipulator
	var nav := controller.nav
	var pilot := controller.autopilot
	var points: Array = task["spots"] if task["type"] == "clean" else task["points"]
	if _item >= points.size():
		if arm.tool != null:
			arm.tool.active = false
		arm.stow()
		_next(now)
		return
	var tool := arm.tool
	var needed := "brush" if task["type"] == "clean" else "cp_probe"
	if tool == null or tool.tool_id != needed:
		_fail(now, "%s needs the %s mounted" % [task_label(task), needed])
		return
	var point_spec = points[_item]
	var east: float = point_spec if task["type"] == "clean" else point_spec["east"]
	var kind: String = "pipe" if task["type"] == "clean" else point_spec["kind"]
	var surface := _surface_point(pipeline, east, kind) + Vector3.RIGHT * _retry_shift
	_timer += dt
	match _phase:
		"":
			# Station: the work point at WORK_OFFSET from the arm base, facing north.
			var station := surface - (arm.mount_position + WORK_OFFSET)
			pilot.set_target(station.x, -station.z, 0.0, -station.y)
			pilot.active = true
			_phase = "station"
			_timer = 0.0
			arm.stow()
		"station":
			if pilot.arrived(nav):
				if _timer > 1.0:
					_command_tool(arm, nav, surface + Vector3.UP * (APPROACH_HEIGHT + tool.tip_radius))
					_phase = "approach"
					_timer = 0.0
			else:
				_timer = 0.0
		"approach":
			if arm.is_settled() and _timer > 0.5:
				_offset = APPROACH_HEIGHT
				if task["type"] == "clean":
					tool.active = true
				_phase = "descend"
				_timer = 0.0
		"descend":
			var goal := BRUSH_FORCE if task["type"] == "clean" else PROBE_FORCE
			if tool.contact_force >= goal * 0.9:
				_phase = "work"
				_timer = 0.0
			elif _timer >= DESCENT_INTERVAL:
				_timer = 0.0
				_offset -= DESCENT_STEP
				if _offset < -tool.travel * MAX_TRAVEL_FRACTION and tool.contact_force > 0.0:
					_offset = -tool.travel * MAX_TRAVEL_FRACTION
				if _offset < -MAX_SEARCH_DEPTH:
					_log(now, "No contact at E %.2f" % east)
					_retract(arm, nav, surface, tool)
					return
				_command_tool(arm, nav, surface + Vector3.UP * (_offset + tool.tip_radius))
		"work":
			# Force control: small corrections keep the force in the working range.
			if _timer >= DESCENT_INTERVAL * 2.0:
				_timer = 0.0
				var goal := BRUSH_FORCE if task["type"] == "clean" else PROBE_FORCE
				if tool.contact_force < goal * 0.7:
					_offset -= DESCENT_STEP * 0.5
				elif tool.contact_force > goal * 1.5:
					_offset += DESCENT_STEP * 0.5
				# Never press further than part of the tool's compliant travel, so
				# it cannot bottom out and shove the vehicle.
				_offset = maxf(_offset, -tool.travel * MAX_TRAVEL_FRACTION)
				# The brush sweeps along the pipe so the cleaned patch is wider
				# than the brush and later probe readings land on bare steel.
				var sweep := Vector3.ZERO
				if task["type"] == "clean":
					sweep = Vector3.RIGHT * CLEAN_SWEEP * sin(TAU * _work_time / CLEAN_SWEEP_PERIOD)
				_command_tool(arm, nav, surface + sweep + Vector3.UP * (_offset + tool.tip_radius))
			if task["type"] == "clean":
				# Only time with the brush biting (force in range) counts.
				_work_time += dt
				if tool.contact_force >= tool.min_force:
					_contact_time += dt
				if _contact_time >= CLEAN_DWELL:
					_log(now, "Cleaned E %.2f (%.1f s in contact)" % [east, _contact_time])
					_retract(arm, nav, surface, tool)
				elif _work_time > CLEAN_DWELL * 4.0:
					_log(now, "Cleaning at E %.2f incomplete: %.1f s in contact" % [east, _contact_time])
					_retract(arm, nav, surface, tool)
			else:
				var probe := tool as CpProbe
				if not is_nan(probe.reading):
					probe.action(now)
					_log(now, "CP %.0f mV at E %.2f (%s)" % [probe.reading, east, probe.log[-1]["surface"]])
					_retract(arm, nav, surface, tool)
				elif _work_elapsed(dt) > 6.0:
					if probe.status.begins_with("No metallic contact") and _attempt < CP_RETRY_SHIFTS.size():
						# Probe the bare patch a little to either side before giving up.
						_retry_shift = CP_RETRY_SHIFTS[_attempt]
						_attempt += 1
						_retract(arm, nav, surface, tool)
						_retrying = true
					else:
						_log(now, "No CP reading at E %.2f: %s" % [east, probe.status])
						_retract(arm, nav, surface, tool)
		"retract":
			if arm.is_settled():
				_work_time = 0.0
				_contact_time = 0.0
				if _retrying:
					_retrying = false
					_phase = "station"
					_timer = 2.0
					return
				_item += 1
				_retry_shift = 0.0
				_attempt = 0
				_phase = ""
				_work_time = 0.0
				_contact_time = 0.0



func _work_elapsed(dt: float) -> float:
	_work_time += dt
	return _work_time


func _retract(arm: Manipulator, nav: NavigationFilter, surface: Vector3, tool: WorkTool) -> void:
	tool.active = false
	_work_time = 0.0
	_contact_time = 0.0
	_command_tool(arm, nav, surface + Vector3.UP * (APPROACH_HEIGHT + tool.tip_radius))
	_phase = "retract"


## Commands the tool to a world point, using the ESTIMATED vehicle pose.
func _command_tool(arm: Manipulator, nav: NavigationFilter, world_point: Vector3) -> void:
	var local := nav.world_basis().inverse() * (world_point - nav.world_position())
	arm.command_tool(local, WORK_PITCH, 0.0, true)


## Top of the pipe (or flange / anode band) at `east`, from the as-built model.
static func _surface_point(pipeline: Pipeline, east: float, kind: String) -> Vector3:
	var r := pipeline.radius()
	if kind == "flange":
		r = pipeline.flange_radius()
	elif kind == "anode":
		r = pipeline.radius() + Pipeline.BRACELET_THICKNESS
	return Vector3(east, pipeline.axis_y() + r, pipeline.axis_z())


# --- Preset missions ----------------------------------------------------------------

const PRESETS := ["Pipeline survey (vision)", "Clean and measure corrosion", "CP survey (flanges and anodes)", "Return to start"]


static func preset(preset_name: String, pipeline: Pipeline, home: Vector3) -> Mission:
	var tasks: Array[Dictionary] = []
	var standoff_north := Pipeline.NORTH - 2.2
	var work_north := Pipeline.NORTH - 1.2
	match preset_name:
		"Pipeline survey (vision)":
			# Directly above the pipe, facing along it, the camera 1.4 m
			# above the pipe top (as-built depth), looking 50° down ahead.
			var survey_depth := -(pipeline.axis_y() + pipeline.radius() + 1.4)
			tasks.append({"type": "goto", "east": -16.0, "north": standoff_north, "heading": 90.0, "altitude": 1.5, "timeout": 240.0})
			tasks.append({"type": "goto", "east": -16.0, "north": Pipeline.NORTH, "heading": 90.0, "depth": survey_depth, "timeout": 120.0})
			tasks.append({"type": "survey", "east_from": -16.0, "east_to": 13.0, "north": Pipeline.NORTH, "heading": 90.0, "depth": survey_depth, "speed": 0.2, "timeout": 400.0})
			tasks.append({"type": "goto", "east": 13.0, "north": standoff_north, "heading": 90.0, "altitude": 1.5, "timeout": 120.0})
		"Clean and measure corrosion":
			tasks.append({"type": "goto", "east": 9.0, "north": work_north - 1.0, "heading": 0.0, "altitude": 1.5, "timeout": 240.0})
			tasks.append({"type": "tool", "tool": "brush", "timeout": 60.0})
			tasks.append({"type": "clean", "spots": [9.0, 9.4, 9.8, 10.2], "timeout": 400.0})
			tasks.append({"type": "tool", "tool": "cp_probe", "timeout": 60.0})
			tasks.append({"type": "cp", "points": [{"east": 9.0, "kind": "pipe"}, {"east": 9.8, "kind": "pipe"}, {"east": 6.0, "kind": "flange"}], "timeout": 400.0})
			tasks.append({"type": "tool", "tool": "", "timeout": 60.0})
		"CP survey (flanges and anodes)":
			tasks.append({"type": "goto", "east": -6.0, "north": work_north - 1.0, "heading": 0.0, "altitude": 1.5, "timeout": 240.0})
			tasks.append({"type": "tool", "tool": "cp_probe", "timeout": 60.0})
			tasks.append({"type": "cp", "points": [{"east": -6.0, "kind": "flange"}, {"east": 0.0, "kind": "anode"},
				{"east": 6.0, "kind": "flange"}, {"east": 12.0, "kind": "flange"}], "timeout": 600.0})
			tasks.append({"type": "tool", "tool": "", "timeout": 60.0})
		"Return to start":
			tasks.append({"type": "goto", "east": home.x, "north": -home.z, "heading": 0.0, "altitude": 1.5, "timeout": 300.0})
	return Mission.new(preset_name, tasks)
