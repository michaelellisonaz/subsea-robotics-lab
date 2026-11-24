## Vehicle-mounted manipulator arm with gripper (simulation data; the 3D
## model in ManipulatorVisual reads it).
##
## Kinematics: a serial chain of revolute joints. Each joint frame = previous
## frame · translate(offset) · rotate(axis, angle). Frames are expressed in
## vehicle body axes (+X starboard, +Y up, -Z forward). The tool point is the
## centre between the gripper fingertips.
##
## Inverse kinematics: damped least squares (Levenberg-Marquardt style) on the
## geometric Jacobian. Task = tool position (3) plus, for arms with a wrist
## pitch joint, the tool pointing direction (weighted 0.25 m/rad). The wrist
## roll joint is not used for positioning; it is commanded directly.
##
## Servos: every joint moves toward its target at up to the joint speed;
## backlash makes the final link angle depend on the approach direction.
##
## Loads: link masses and the payload are evaluated for the shoulder moment
## (load capacity) and passed to the vehicle as forces (ManipulatorLoadForce).
## The vehicle is assumed trimmed with the arm STOWED, so arm motion produces
## only the change in moment; a payload adds its full weight in water.
##
## Tools (Stage 5): the vehicle carries a tool skid (cleaning brush, CP
## probe). A tool change stows the arm, swaps the tool in the skid
## (TOOL_CHANGE_TIME) and mounts it in the gripper: the tool point moves out by
## the tool length and the tool's weight moves from the skid to the wrist.
##
## Collision (Stage 5): every step the links (spheres sampled along each link),
## the gripper / tool body, the jaw tips and a held item are checked against
## the seabed and the structures. A joint motion that would push any of them
## more than COLLISION_ALLOWANCE into a surface is refused (the servos stall,
## "Arm blocked"). Contact that remains (the vehicle drifting onto a surface,
## or the allowance) gives penalty forces that act on the vehicle. A mounted
## tool's tip is compliant instead: see WorkTool.
##
## Simplifications: no joint dynamics or link inertia effects on the vehicle,
## no self-collision and no arm-vs-vehicle-frame collision, rigid links,
## kinematic servos that stall instead of having torque limits.
class_name Manipulator
extends RefCounted

const GRIPPER_MAX_OPENING := 0.14  # m
const GRIPPER_SPEED := 0.08  # m/s
const GRASP_TOLERANCE := 0.07  # m, tool point to object grasp point
const DIRECTION_WEIGHT := 0.25  # m/rad
const IK_DAMPING := 0.04
const IK_ITERATIONS := 80
const REACH_TOLERANCE := 0.005  # m
const LINK_DENSITY := 3000.0  # kg/m³ (aluminium structure, oil-filled housings)
const STOW_DEGREES := {"yaw": 0.0, "shoulder": 85.0, "elbow": -165.0, "wrist_pitch": 95.0, "wrist_yaw": 0.0, "wrist_roll": 0.0}
const READY_DEGREES := {"yaw": 0.0, "shoulder": -15.0, "elbow": -70.0, "wrist_pitch": 30.0, "wrist_yaw": 0.0, "wrist_roll": 0.0}
## Accuracy-test targets: tool positions relative to the arm base (body axes).
const TEST_TARGETS := [
	Vector3(0.0, -0.25, -0.60), Vector3(0.20, -0.30, -0.55), Vector3(-0.20, -0.30, -0.55),
	Vector3(0.0, -0.45, -0.45), Vector3(0.15, -0.10, -0.75), Vector3(-0.15, -0.10, -0.75),
	Vector3(0.0, -0.35, -0.80), Vector3(0.10, -0.50, -0.35),
]
const TEST_PITCH := -45.0
const TEST_TIMEOUT := 12.0  # s per target
## Time to swap a tool in the skid once the arm is stowed, s.
const TOOL_CHANGE_TIME := 6.0
## Jaw opening when holding a tool handle, m.
const TOOL_HANDLE_WIDTH := 0.04
## Length of the gripper from the palm to the fingertips, m.
const GRIPPER_LENGTH := 0.16
const LINK_COLLISION_RADIUS := 0.035  # m
const JAW_TIP_RADIUS := 0.02  # m
const COLLISION_SPACING := 0.06  # m between link sample spheres
## Penetration tolerated before a joint motion is refused, m.
const COLLISION_ALLOWANCE := 0.01
const CONTACT_STIFFNESS := 20000.0  # N/m, rigid arm parts
const CONTACT_DAMPING := 300.0  # N·s/m

var layout: String = "none"
var joints: Array[ManipulatorJoint] = []
var mount_position: Vector3 = Vector3.ZERO
var tool_offset: Vector3 = Vector3.ZERO
var upper_length: float = 0.42
var forearm_length: float = 0.38
var joint_speed: float = deg_to_rad(30.0)  # rad/s
var rated_payload_kg: float = 12.0
## Shoulder moment capacity derived from the rated payload, N·m (at g = 9.81).
var shoulder_capacity: float = 0.0
## Masses of [base, upper arm, forearm, wrist, gripper], kg.
var link_masses: PackedFloat64Array = PackedFloat64Array()

var gripper_opening: float = GRIPPER_MAX_OPENING
var gripper_closing: bool = false
var grasped: GraspableObject = null
var _grasp_offset: Transform3D = Transform3D.IDENTITY

## Cartesian target of the tool (body axes) and tool angles, degrees.
var tool_target_position: Vector3 = Vector3.ZERO
var tool_target_pitch: float = -30.0
var tool_target_roll: float = 0.0
var ik_status: String = "ok"
var ik_error: float = 0.0
var status_message: String = ""
## Shoulder moment of the arm + payload in the last step, N·m.
var shoulder_moment: float = 0.0
## Link centres of gravity in the stowed pose (body axes), for load trimming.
var stowed_link_points: PackedVector3Array = PackedVector3Array()

## Tools in the skid, the mounted tool (null = bare gripper) and tool change.
var tools: Array[WorkTool] = []
var tool: WorkTool = null
## "", "stowing" or "swapping".
var tool_change_phase: String = ""
var tool_change_remaining: float = 0.0
## Where the tools are stowed on the vehicle (body axes): the skid.
var skid_position: Vector3 = Vector3.ZERO
var _tool_change_target: WorkTool = null
var _base_tool_offset: Vector3 = Vector3.ZERO

## Collision / contact state of the last step.
var blocked: bool = false
## Deepest penetration of a rigid arm part or held item, m.
var collision_depth: float = 0.0
## "forearm touching seabed" etc. ("" = none).
var collision_info: String = ""
## Contact loads for the vehicle: [[world point, world force], ...].
var contact_loads: Array = []

## Accuracy test state and results.
var accuracy_test_running: bool = false
var accuracy_results: Array[Dictionary] = []
var _test_index: int = 0
var _test_elapsed: float = 0.0


func _init(config: VehicleConfig = null) -> void:
	if config != null:
		build(config)


func is_installed() -> bool:
	return not joints.is_empty()


func build(config: VehicleConfig) -> void:
	layout = config.arm_layout
	joints.clear()
	accuracy_results.clear()
	accuracy_test_running = false
	release()
	if layout == "none":
		return
	tool = null
	tool_change_phase = ""
	tools = [CleaningBrush.new(), CpProbe.new()]
	upper_length = config.get_value("arm_upper_length")
	forearm_length = config.get_value("arm_forearm_length")
	joint_speed = deg_to_rad(config.get_value("arm_joint_speed"))
	rated_payload_kg = config.get_value("arm_payload")
	var backlash := deg_to_rad(config.get_value("arm_backlash"))
	mount_position = config.to_body(config.arm_mount_geometric())
	var forward := Vector3.FORWARD
	joints.append(ManipulatorJoint.new("yaw", Vector3.UP, Vector3.ZERO, -80.0, 80.0))
	joints.append(ManipulatorJoint.new("shoulder", Vector3.RIGHT, forward * 0.06, -60.0, 90.0))
	joints.append(ManipulatorJoint.new("elbow", Vector3.RIGHT, forward * upper_length, -170.0, 0.0))
	match layout:
		"arm_3dof":
			tool_offset = forward * (forearm_length + 0.22)
		"arm_4dof":
			joints.append(ManipulatorJoint.new("wrist_pitch", Vector3.RIGHT, forward * forearm_length, -100.0, 100.0))
			tool_offset = forward * 0.22
		"arm_5dof":
			joints.append(ManipulatorJoint.new("wrist_pitch", Vector3.RIGHT, forward * forearm_length, -100.0, 100.0))
			joints.append(ManipulatorJoint.new("wrist_roll", Vector3.FORWARD, forward * 0.06, -180.0, 180.0, true))
			tool_offset = forward * 0.16
		"arm_6dof":
			joints.append(ManipulatorJoint.new("wrist_pitch", Vector3.RIGHT, forward * forearm_length, -100.0, 100.0))
			joints.append(ManipulatorJoint.new("wrist_yaw", Vector3.UP, forward * 0.03, -80.0, 80.0))
			joints.append(ManipulatorJoint.new("wrist_roll", Vector3.FORWARD, forward * 0.03, -180.0, 180.0, true))
			tool_offset = forward * 0.16
	_base_tool_offset = tool_offset
	skid_position = Vector3(-mount_position.x, mount_position.y, mount_position.z + 0.15)
	for joint in joints:
		joint.backlash = backlash
	# Light electric inspection-class arm: ~11 kg in air with default links.
	link_masses = PackedFloat64Array([2.5, 8.0 * upper_length, 6.5 * forearm_length, 1.5, 1.2])
	_apply_pose(STOW_DEGREES, true)
	stowed_link_points = link_points(current_angles())
	shoulder_capacity = rated_payload_kg * 9.81 * full_reach() + _self_moment_extended(9.81, 1025.0)
	_sync_tool_target()


func reset() -> void:
	if grasped != null:
		grasped.held_by = null
		grasped = null
	gripper_opening = GRIPPER_MAX_OPENING
	gripper_closing = false
	accuracy_test_running = false
	status_message = ""
	ik_status = "ok"
	tool = null
	tool_offset = _base_tool_offset
	tool_change_phase = ""
	for t in tools:
		t.reset()
	blocked = false
	collision_depth = 0.0
	collision_info = ""
	contact_loads = []
	if is_installed():
		_apply_pose(STOW_DEGREES, true)
		_sync_tool_target()


# --- Kinematics --------------------------------------------------------------

func current_angles() -> PackedFloat64Array:
	var q := PackedFloat64Array()
	for joint in joints:
		q.append(joint.angle())
	return q


func target_angles() -> PackedFloat64Array:
	var q := PackedFloat64Array()
	for joint in joints:
		q.append(joint.target)
	return q


## Joint frames (after each joint's rotation) followed by the tool frame, body axes.
func frames(angles: PackedFloat64Array) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var t := Transform3D(Basis.IDENTITY, mount_position)
	for i in joints.size():
		t = t * Transform3D(Basis.IDENTITY, joints[i].offset)
		t = t * Transform3D(Basis(joints[i].axis, angles[i]), Vector3.ZERO)
		result.append(t)
	result.append(t * Transform3D(Basis.IDENTITY, tool_offset))
	return result


func tool_transform(angles: PackedFloat64Array = PackedFloat64Array()) -> Transform3D:
	var f := frames(angles if not angles.is_empty() else current_angles())
	return f[-1]


## Tool pointing direction (body axes) for a pitch and the azimuth of a point.
func tool_direction(position: Vector3, pitch_degrees: float) -> Vector3:
	var rel := position - mount_position
	var azimuth := atan2(-rel.x, -rel.z)
	var pitch := deg_to_rad(pitch_degrees)
	return Vector3(-sin(azimuth) * cos(pitch), sin(pitch), -cos(azimuth) * cos(pitch))


func uses_direction() -> bool:
	return layout != "arm_3dof"


## Damped-least-squares IK. Starts from `seed`; if that does not converge it
## retries from the ready pose and a mid-range pose (avoids local minima) and
## returns the best result: {"angles", "position_error", "reachable"}.
func solve_ik(target_position: Vector3, target_direction: Vector3, seed: PackedFloat64Array) -> Dictionary:
	var best := _solve_from(target_position, target_direction, seed)
	if best["reachable"]:
		return best
	var mid := PackedFloat64Array()
	var ready := PackedFloat64Array()
	for joint in joints:
		mid.append((joint.min_angle + joint.max_angle) * 0.5)
		ready.append(clampf(deg_to_rad(READY_DEGREES.get(joint.joint_name, 0.0)), joint.min_angle, joint.max_angle))
	for alternative in [ready, mid]:
		var result := _solve_from(target_position, target_direction, alternative)
		if result["position_error"] < best["position_error"]:
			best = result
		if best["reachable"]:
			break
	return best


func _solve_from(target_position: Vector3, target_direction: Vector3, seed: PackedFloat64Array) -> Dictionary:
	var q := seed.duplicate()
	var active: Array[int] = []
	for i in joints.size():
		if not joints[i].is_roll:
			active.append(i)
	var use_direction := uses_direction()
	var rows := 6 if use_direction else 3
	var position_error := INF
	for iteration in IK_ITERATIONS:
		var f := frames(q)
		var tool := f[-1]
		var e_pos := target_position - tool.origin
		var e_rot := Vector3.ZERO
		if use_direction:
			e_rot = (-tool.basis.z).normalized().cross(target_direction)
		position_error = e_pos.length()
		if position_error < 1e-4 and e_rot.length() < 1e-3:
			break
		var jacobian := DenseMatrix.new(rows, active.size())
		for c in active.size():
			var j := active[c]
			var axis_body := (f[j].basis * joints[j].axis).normalized()
			var linear := axis_body.cross(tool.origin - f[j].origin)
			for r in 3:
				jacobian.set_at(r, c, linear[r])
				if use_direction:
					jacobian.set_at(r + 3, c, axis_body[r] * DIRECTION_WEIGHT)
		var error := PackedFloat64Array([e_pos.x, e_pos.y, e_pos.z])
		if use_direction:
			error.append_array(PackedFloat64Array([e_rot.x * DIRECTION_WEIGHT, e_rot.y * DIRECTION_WEIGHT, e_rot.z * DIRECTION_WEIGHT]))
		var jt := jacobian.transposed()
		var jjt := jacobian.multiply(jt)
		for k in rows:
			jjt.set_at(k, k, jjt.at(k, k) + IK_DAMPING * IK_DAMPING)
		var inverse := jjt.inverse()
		if inverse == null:
			break
		var dq := jt.multiply_vector(inverse.multiply_vector(error))
		for c in active.size():
			var j := active[c]
			q[j] = clampf(q[j] + clampf(dq[c], -0.2, 0.2), joints[j].min_angle, joints[j].max_angle)
	var final_position := frames(q)[-1].origin
	position_error = (target_position - final_position).length()
	return {"angles": q, "position_error": position_error, "reachable": position_error <= REACH_TOLERANCE}


## Commands the tool to a position (body axes) with a pitch and roll (degrees).
## If the point cannot be reached within 5 mm: with allow_partial the arm moves
## to the closest pose found, otherwise the command is rejected.
func command_tool(position: Vector3, pitch_degrees: float, roll_degrees: float, allow_partial: bool = false) -> bool:
	if not is_installed() or _changing_tool():
		return false
	var result := solve_ik(position, tool_direction(position, pitch_degrees), target_angles())
	ik_error = result["position_error"]
	if not result["reachable"] and not allow_partial:
		ik_status = "out of reach"
		return false
	var angles: PackedFloat64Array = result["angles"]
	for i in joints.size():
		if joints[i].is_roll:
			joints[i].set_target(deg_to_rad(roll_degrees))
		else:
			joints[i].set_target(angles[i])
	tool_target_position = position
	tool_target_pitch = pitch_degrees
	tool_target_roll = roll_degrees
	ik_status = "ok" if result["reachable"] else "closest reachable point"
	return result["reachable"]


## Moves the Cartesian target by a body-axes offset and angle changes.
func jog_tool(delta: Vector3, delta_pitch: float, delta_roll: float) -> bool:
	return command_tool(tool_target_position + delta,
		clampf(tool_target_pitch + delta_pitch, -90.0, 60.0), tool_target_roll + delta_roll)


## Joint mode: sets one joint target (degrees); the Cartesian target follows.
func set_joint_target_degrees(index: int, degrees: float) -> void:
	if _changing_tool():
		return
	joints[index].set_target(deg_to_rad(degrees))
	_sync_tool_target()


func stow() -> void:
	if _changing_tool():
		return
	_apply_pose(STOW_DEGREES, false)
	_sync_tool_target()


func ready_pose() -> void:
	if _changing_tool():
		return
	_apply_pose(READY_DEGREES, false)
	_sync_tool_target()


func is_settled() -> bool:
	for joint in joints:
		if not joint.is_settled():
			return false
	return true


## Horizontal reach from the shoulder joint to the tool with the arm straight, m.
func full_reach() -> float:
	var total := 0.0
	for i in range(2, joints.size()):
		total += joints[i].offset.length()
	return total + tool_offset.length()


## Tool positions over a grid of joint angles (body axes): the reach envelope.
func sample_envelope(steps: int = 9) -> PackedVector3Array:
	var points := PackedVector3Array()
	if not is_installed():
		return points
	var q := current_angles()
	for a in steps:
		for b in steps:
			for c in steps:
				q[0] = lerpf(joints[0].min_angle, joints[0].max_angle, float(a) / (steps - 1))
				q[1] = lerpf(joints[1].min_angle, joints[1].max_angle, float(b) / (steps - 1))
				q[2] = lerpf(joints[2].min_angle, joints[2].max_angle, float(c) / (steps - 1))
				if joints.size() > 3:
					q[3] = 0.0
				points.append(frames(q)[-1].origin)
	return points


# --- Loads -------------------------------------------------------------------

## Centres of gravity of [base, upper arm, forearm, wrist, gripper] (body axes).
func link_points(angles: PackedFloat64Array) -> PackedVector3Array:
	var f := frames(angles)
	var tip := f[-1]
	var wrist := f[3].origin if joints.size() > 3 else tip.origin
	return PackedVector3Array([
		f[0].origin,
		(f[1].origin + f[2].origin) * 0.5,
		(f[2].origin + wrist) * 0.5,
		wrist,
		tip.origin + tip.basis.z * (tool_extension() + GRIPPER_LENGTH * 0.5),
	])


## How far a mounted tool extends the tool point beyond the fingertips, m.
func tool_extension() -> float:
	return tool.length if tool != null else 0.0


## Centre of gravity of the mounted tool (body axes).
func tool_center_of_gravity(angles: PackedFloat64Array = PackedFloat64Array()) -> Vector3:
	var tip := tool_transform(angles)
	return tip.origin + tip.basis.z * (tool_extension() * 0.5)


## Weight in water of each link, N.
func link_wet_weights(density: float, gravity: float) -> PackedFloat64Array:
	var weights := PackedFloat64Array()
	for m in link_masses:
		weights.append((m - density * m / LINK_DENSITY) * gravity)
	return weights


## Payload capacity in water at a horizontal reach r from the shoulder, kg
## (static shoulder-moment limit; arm self-moment scaled with reach).
func payload_capacity_at(reach: float) -> float:
	if reach <= 0.0 or shoulder_capacity <= 0.0:
		return 0.0
	var self_moment := _self_moment_extended(9.81, 1025.0) * clampf(reach / full_reach(), 0.0, 1.0)
	return maxf(0.0, (shoulder_capacity - self_moment) / (9.81 * reach))


func _self_moment_extended(gravity: float, density: float) -> float:
	var q := PackedFloat64Array()
	for joint in joints:
		q.append(0.0)
	var points := link_points(q)
	var shoulder := frames(q)[1].origin
	var weights := link_wet_weights(density, gravity)
	var moment := 0.0
	for i in points.size():
		moment += weights[i] * Vector2(points[i].x - shoulder.x, points[i].z - shoulder.z).length()
	return moment


# --- Simulation step ------------------------------------------------------------

## Called by the vehicle after each physics step.
func step(context: StepContext, vehicle: RovVehicle) -> void:
	if not is_installed():
		return
	var dt := context.dt
	if _changing_tool():
		_step_tool_change(dt)
	_step_joints_with_collision(context, vehicle, dt)
	var tool_world := Transform3D(Basis(vehicle.orientation), vehicle.position) * tool_transform()
	if tool != null:
		tool.step(context, tool_world, dt)
	elif gripper_closing and grasped == null and not _changing_tool():
		gripper_opening = maxf(0.0, gripper_opening - GRIPPER_SPEED * dt)
		var candidate := _find_graspable(context, tool_world.origin)
		if candidate != null and gripper_opening <= candidate.grasp_width + 0.005:
			_grasp(candidate, tool_world)
	elif not gripper_closing and tool == null:
		if grasped != null:
			release()
		gripper_opening = minf(GRIPPER_MAX_OPENING, gripper_opening + GRIPPER_SPEED * dt)
	_update_loads(context, vehicle, tool_world)
	if grasped != null:
		var pose := tool_world * _grasp_offset
		grasped.position = pose.origin
		grasped.orientation = pose.basis.get_rotation_quaternion()
		grasped.velocity = vehicle.velocity_at_point(pose.origin)
	if accuracy_test_running:
		_step_accuracy_test(dt)


func set_gripper_closed(closed: bool) -> void:
	if tool != null or _changing_tool():
		return
	gripper_closing = closed


func toggle_gripper() -> void:
	set_gripper_closed(not gripper_closing)


## G key: the gripper when no tool is mounted, otherwise the tool's action.
func tool_action(now: float = 0.0) -> void:
	if _changing_tool():
		return
	if tool != null:
		status_message = tool.action(now)
	else:
		toggle_gripper()


func release() -> void:
	if grasped == null:
		return
	var item := grasped
	grasped = null
	item.held_by = null
	item.seat_message = ""
	if not item.on_released():
		item.is_dynamic = true
		# Settle upright, keeping only the heading of the held pose.
		var forward := item.orientation * Vector3.FORWARD
		item.orientation = Quaternion(Vector3.UP, atan2(-forward.x, -forward.z))
	status_message = item.seat_message if item.seat_message != "" else "Released %s" % item.display_name


# --- Tools ---------------------------------------------------------------------

## Starts changing to `new_tool` (one of `tools`, or null for the bare
## gripper). Returns false if a change is not possible now.
func request_tool(new_tool: WorkTool) -> bool:
	if not is_installed() or _changing_tool():
		return false
	if new_tool == tool:
		return true
	if grasped != null:
		status_message = "Release the held item before changing tools"
		return false
	accuracy_test_running = false
	_tool_change_target = new_tool
	tool_change_phase = "stowing"
	_apply_pose(STOW_DEGREES, false)
	_sync_tool_target()
	status_message = "Tool change: stowing the arm"
	return true


## Next entry of [gripper, tools...] after the current one.
func next_tool() -> WorkTool:
	var options: Array = [null]
	options.append_array(tools)
	return options[(options.find(tool) + 1) % options.size()]


func _changing_tool() -> bool:
	return tool_change_phase != ""


func _step_tool_change(dt: float) -> void:
	if tool_change_phase == "stowing":
		if is_settled():
			if tool != null:
				tool.on_unmounted()
			tool = null
			tool_offset = _base_tool_offset
			gripper_closing = false
			tool_change_phase = "swapping"
			tool_change_remaining = TOOL_CHANGE_TIME
			status_message = "Tool change: at the skid"
		return
	tool_change_remaining -= dt
	if tool_change_remaining > 0.0:
		return
	tool = _tool_change_target
	tool_change_phase = ""
	if tool != null:
		tool.on_unmounted()
		tool.status = "Off"
		tool_offset = _base_tool_offset + Vector3.FORWARD * tool.length
		gripper_closing = true
		gripper_opening = TOOL_HANDLE_WIDTH
		status_message = "%s mounted" % tool.display_name
	else:
		status_message = "Gripper free"
	_sync_tool_target()


# --- Collision and contact ---------------------------------------------------------

func _step_joints_with_collision(context: StepContext, vehicle: RovVehicle, dt: float) -> void:
	var saved: Array[Vector2] = []
	for joint in joints:
		saved.append(joint.snapshot())
	var before := collision_depth
	var moved := false
	for joint in joints:
		if joint.step(dt, joint_speed):
			moved = true
	var result := _evaluate_contacts(context, vehicle)
	blocked = false
	if moved and _worse(result["depth"], before):
		# Refused as a whole: retry joint by joint, keeping each joint's step
		# only if it does not push further in (so joints that lift the arm
		# away from the surface still move).
		for i in joints.size():
			joints[i].restore(saved[i])
		result = _evaluate_contacts(context, vehicle)
		var baseline: float = result["depth"]
		for i in joints.size():
			var state := joints[i].snapshot()
			if not joints[i].step(dt, joint_speed):
				continue
			var trial := _evaluate_contacts(context, vehicle)
			if _worse(trial["depth"], baseline):
				joints[i].restore(state)
				blocked = true
			else:
				result = trial
				baseline = trial["depth"]
		if blocked:
			result = _evaluate_contacts(context, vehicle)
	collision_depth = result["depth"]
	collision_info = result["info"]
	contact_loads = result["loads"]
	if tool != null:
		tool.contact = result["tip"]
		tool.contact_force = result["tip_force"]


func _worse(depth: float, reference: float) -> bool:
	return depth > COLLISION_ALLOWANCE and depth > reference + 1e-5


## Checks the arm, gripper / tool and held item against the seabed and the
## structures. Returns {"depth" (rigid parts, m), "info", "loads", "tip",
## "tip_force"}.
func _evaluate_contacts(context: StepContext, vehicle: RovVehicle) -> Dictionary:
	var result := {"depth": 0.0, "info": "", "loads": [], "tip": {}, "tip_force": 0.0}
	var world := context.world
	if world == null:
		return result
	var to_world := Transform3D(Basis(vehicle.orientation), vehicle.position)
	var f := frames(current_angles())
	var tip := f[-1]
	var palm := tip.origin + tip.basis.z * (tool_extension() + GRIPPER_LENGTH)
	# Only the primitives within reach of the arm (plus a held item) are tested.
	var shoulder_world := to_world * f[1].origin
	var reach := full_reach() + 0.8
	var near: Array = []  # [structure, primitive]
	for structure in world.structures_near(shoulder_world, reach):
		for primitive in structure.primitives:
			if primitive.aabb.grow(reach).has_point(shoulder_world):
				near.append([structure, primitive])
	var seabed_reference := world.seabed_y_at(vehicle.position.x, vehicle.position.z)
	if near.is_empty() and shoulder_world.y - reach > seabed_reference + 0.5:
		return result
	# Rigid samples: [body point or world point, radius, clearance, name, is_world].
	var samples: Array = []
	for i in joints.size():
		var start := f[i].origin
		var finish := f[i + 1].origin if i + 1 < joints.size() else palm
		_sample_segment(samples, start, finish, LINK_COLLISION_RADIUS, joints[i].joint_name.replace("_", " "))
	_sample_segment(samples, palm, tip.origin + tip.basis.z * tool_extension(), 0.025, "gripper")
	if tool == null:
		samples.append([tip.origin, JAW_TIP_RADIUS, JAW_TIP_RADIUS, "gripper jaws", false])
	else:
		_sample_segment(samples, tip.origin + tip.basis.z * tool_extension(), tip.origin + tip.basis.z * (tool.tip_radius + 0.02), 0.025, tool.display_name.to_lower())
	if grasped != null:
		# Pose the held item for the joint angles being checked.
		var pose := to_world * Transform3D(tip.basis, tip.origin) * _grasp_offset
		grasped.position = pose.origin
		grasped.orientation = pose.basis.get_rotation_quaternion()
		for sphere in grasped.contact_spheres():
			samples.append([sphere["point"], sphere["radius"], sphere["clearance"], grasped.display_name, true])
	for sample in samples:
		var point: Vector3 = sample[0] if sample[4] else to_world * sample[0]
		var hit := _surface_hit(world, near, point, sample[1], sample[2])
		if hit.is_empty():
			continue
		var depth: float = hit["depth"]
		if depth > result["depth"]:
			result["depth"] = depth
			result["info"] = "%s touching %s" % [sample[3], hit["name"]]
		var normal: Vector3 = hit["normal"]
		var approach := vehicle.velocity_at_point(point).dot(normal)
		var force := maxf(0.0, CONTACT_STIFFNESS * depth - CONTACT_DAMPING * approach)
		if force > 0.0:
			result["loads"].append([point - normal * sample[1], normal * force])
	if tool != null:
		var tip_world := to_world * tip.origin
		var hit := _surface_hit(world, near, tip_world, tool.tip_radius, tool.tip_radius)
		if not hit.is_empty():
			var depth: float = hit["depth"]
			var normal: Vector3 = hit["normal"]
			var force := tool.compliance * minf(depth, tool.travel)
			var excess := depth - tool.travel
			if excess > 0.0:
				force += CONTACT_STIFFNESS * excess
				if excess > result["depth"]:
					result["depth"] = excess
					result["info"] = "%s bottomed out on %s" % [tool.display_name, hit["name"]]
			var surface_point := tip_world - normal * (tool.tip_radius - depth)
			result["tip"] = {"point": surface_point, "normal": normal, "structure": hit["structure"],
				"primitive": hit["primitive"], "depth": depth}
			result["tip_force"] = force
			result["loads"].append([surface_point, normal * force])
	return result


func _sample_segment(samples: Array, start: Vector3, finish: Vector3, radius: float, part: String) -> void:
	var span := finish - start
	var count := maxi(1, int(ceil(span.length() / COLLISION_SPACING)))
	for k in count + 1:
		samples.append([start + span * (float(k) / count), radius, radius, part, false])


## Deepest overlap of a sphere with the seabed or a structure:
## {"depth", "normal", "structure" (null = seabed), "primitive", "name"} or {}.
func _surface_hit(world: WorldModel, near: Array, point: Vector3, radius: float, clearance: float) -> Dictionary:
	var best := {}
	if clearance >= 0.0:
		var seabed_depth := world.seabed_y_at(point.x, point.z) + clearance - point.y
		if seabed_depth > 0.0:
			best = {"depth": seabed_depth, "normal": Vector3.UP, "structure": null, "primitive": null, "name": "seabed"}
	if radius > 0.0:
		for pair in near:
			var primitive: StructurePrimitive = pair[1]
			if not primitive.aabb.grow(radius).has_point(point):
				continue
			var hit := primitive.penetration(point, radius)
			if not hit.is_empty() and (best.is_empty() or hit["depth"] > best["depth"]):
				best = hit
				best["structure"] = pair[0]
				best["primitive"] = primitive
				best["name"] = (pair[0] as Structure).structure_name
	return best


func _find_graspable(context: StepContext, tool_point: Vector3) -> GraspableObject:
	if context.objects == null:
		return null
	var best: GraspableObject = null
	var best_distance := GRASP_TOLERANCE
	for object in context.objects.get_all():
		var item := object as GraspableObject
		if item == null or not item.can_be_grasped():
			continue
		var distance := item.grasp_point().distance_to(tool_point)
		if distance < best_distance:
			best = item
			best_distance = distance
	return best


func _grasp(item: GraspableObject, tool_world: Transform3D) -> void:
	grasped = item
	item.held_by = self
	item.is_dynamic = false
	item.velocity = Vector3.ZERO
	_grasp_offset = tool_world.affine_inverse() * item.get_transform()
	gripper_opening = item.grasp_width
	status_message = "Holding %s" % item.display_name


func _update_loads(context: StepContext, vehicle: RovVehicle, tool_world: Transform3D) -> void:
	var env := context.environment
	var to_world := Transform3D(Basis(vehicle.orientation), vehicle.position)
	var points := link_points(current_angles())
	var weights := link_wet_weights(env.water_density, env.gravity)
	var shoulder := to_world * frames(current_angles())[1].origin
	var moment := 0.0
	for i in points.size():
		var p := to_world * points[i]
		moment += weights[i] * Vector2(p.x - shoulder.x, p.z - shoulder.z).length()
	if tool != null:
		var cg := to_world * tool_center_of_gravity()
		moment += maxf(tool.wet_weight(env), 0.0) * Vector2(cg.x - shoulder.x, cg.z - shoulder.z).length()
	if grasped != null:
		var payload_weight := grasped.submerged_weight(env)
		moment += maxf(payload_weight, 0.0) * Vector2(tool_world.origin.x - shoulder.x, tool_world.origin.z - shoulder.z).length()
		var capacity := shoulder_capacity * env.gravity / 9.81
		if moment > capacity:
			var message := "Dropped %s: %.1f kg in water exceeds the arm capacity at %.2f m reach" % [
				grasped.display_name, payload_weight / env.gravity,
				Vector2(tool_world.origin.x - shoulder.x, tool_world.origin.z - shoulder.z).length()]
			release()
			status_message = message
			gripper_closing = false
	shoulder_moment = moment


# --- Accuracy test -------------------------------------------------------------

## Drives the tool through TEST_TARGETS (relative to the arm base) and records
## the final position error of each move once the joints have settled.
func start_accuracy_test() -> void:
	if not is_installed():
		return
	accuracy_results.clear()
	_test_index = 0
	accuracy_test_running = true
	_command_test_target()


func accuracy_summary() -> Dictionary:
	var reached := accuracy_results.filter(func(r): return r["reachable"])
	if reached.is_empty():
		return {"count": accuracy_results.size(), "reached": 0}
	var total := 0.0
	var worst := 0.0
	var time := 0.0
	for r in reached:
		total += r["error"]
		worst = maxf(worst, r["error"])
		time += r["time"]
	return {"count": accuracy_results.size(), "reached": reached.size(),
		"mean_error": total / reached.size(), "max_error": worst, "mean_time": time / reached.size()}


func _command_test_target() -> void:
	_test_elapsed = 0.0
	command_tool(mount_position + TEST_TARGETS[_test_index], TEST_PITCH, 0.0, true)


func _step_accuracy_test(dt: float) -> void:
	_test_elapsed += dt
	if not is_settled() and _test_elapsed < TEST_TIMEOUT:
		return
	var commanded: Vector3 = mount_position + TEST_TARGETS[_test_index]
	var reachable := ik_status == "ok"
	accuracy_results.append({
		"target": commanded,
		"actual": tool_transform().origin,
		"error": tool_transform().origin.distance_to(commanded),
		"time": _test_elapsed,
		"reachable": reachable,
	})
	_test_index += 1
	if _test_index >= TEST_TARGETS.size():
		accuracy_test_running = false
		var summary := accuracy_summary()
		status_message = "Accuracy test: mean %.1f mm, max %.1f mm over %d targets" % [
			summary.get("mean_error", 0.0) * 1000.0, summary.get("max_error", 0.0) * 1000.0, summary.get("reached", 0)]
	else:
		_command_test_target()


func _apply_pose(degrees: Dictionary, immediate: bool) -> void:
	for joint in joints:
		var value := deg_to_rad(degrees.get(joint.joint_name, 0.0))
		if immediate:
			joint.place(value)
		else:
			joint.set_target(value)


func _sync_tool_target() -> void:
	if not is_installed():
		return
	var tool := tool_transform(target_angles())
	tool_target_position = tool.origin
	var direction := -tool.basis.z
	tool_target_pitch = rad_to_deg(asin(clampf(direction.y, -1.0, 1.0)))
	for i in joints.size():
		if joints[i].is_roll:
			tool_target_roll = rad_to_deg(joints[i].target)
