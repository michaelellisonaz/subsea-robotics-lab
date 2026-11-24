## Inspection-class ROV: a 6-DOF rigid body built from a VehicleConfig, with
## thrusters, thrust allocation, its own hydrodynamic damping and seabed
## contact. Pure simulation data - the 3D model (RovVisual) reads its state.
##
## Pilot commands are normalised per degree of freedom (-1..1):
##   surge  + forward      sway  + starboard     heave + up
##   roll   + starboard down   pitch + nose up    yaw   + clockwise (to starboard)
## Each step the commands are scaled by the layout's capability in that axis,
## combined into a body wrench, allocated to the thrusters, and the thrusters
## respond with their first-order lag.
class_name RovVehicle
extends RigidSimBody

signal configuration_applied()

enum Axis { SURGE, SWAY, HEAVE, ROLL, PITCH, YAW }
const AXIS_NAMES := ["Surge", "Sway", "Heave", "Roll", "Pitch", "Yaw"]
## Pilot axis -> [wrench index, sign] (body axes: x starboard, y up, z aft).
const AXIS_TO_WRENCH := [[2, -1.0], [0, 1.0], [1, 1.0], [5, -1.0], [3, 1.0], [4, -1.0]]

var config: VehicleConfig
var thrusters: Array[Thruster] = []
var allocator: ThrustAllocator
var damping: HydrodynamicDamping
var contact: HullContactForce
## Instrument package (sampled after every physics step).
var sensors: SensorSuite
## Manipulator arm with gripper (not installed when the layout is "none").
var manipulator: Manipulator = Manipulator.new()
## Navigation filter, autopilot and missions (Stage 6).
var autonomy := AutonomyController.new()
## Automatic depth / heading hold driven by sensor readings.
var aids: PilotAids = PilotAids.new()
## Commands actually allocated in the last step (pilot commands + pilot aids).
var applied_command: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
## Simulation time at the end of the last step, s.
var last_update_time: float = 0.0
## Vehicle work lights (equipment state; drawn by the visual).
var lights_on: bool = true
## Normalised pilot command per Axis.
var pilot_command: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
## Path length travelled since the last reset, m.
var distance_travelled: float = 0.0
## Highest speed over ground since the last reset, m/s.
var max_speed: float = 0.0


func _init(p_config: VehicleConfig = null, start_position: Vector3 = Vector3.ZERO) -> void:
	super("ROV", start_position)
	sensors = SensorSuite.create_default()
	apply_config(p_config if p_config != null else VehicleConfig.new())


## Rebuilds mass properties, thrusters and force models from a configuration.
func apply_config(p_config: VehicleConfig) -> void:
	config = p_config
	display_name = config.vehicle_name
	mass = config.dry_mass
	displaced_volume = config.displaced_volume()
	inertia = config.inertia()
	added_mass_linear = config.added_mass()
	added_inertia = config.added_inertia()
	center_of_buoyancy = config.cb_relative_to_cg()
	submersion_height = config.height
	bottom_clearance = 0.0
	thrusters = config.build_thrusters()
	allocator = ThrustAllocator.new(thrusters)
	damping = config.build_damping()
	contact = HullContactForce.new(config.contact_points())
	local_force_models.clear()
	local_force_models.append(damping)
	local_force_models.append(ThrusterForceModel.new(thrusters))
	local_force_models.append(contact)
	manipulator.build(config)
	if manipulator.is_installed():
		local_force_models.append(ManipulatorLoadForce.new(manipulator))
	sensors.update_mounts(config)
	configuration_applied.emit()


## Toggles depth hold; returns false (see aids.status) if it cannot engage.
func toggle_depth_hold() -> bool:
	return aids.set_depth_hold(not aids.depth_hold, self, last_update_time)


## Toggles attitude hold (keep level); returns false if it cannot engage.
func toggle_attitude_hold() -> bool:
	return aids.set_attitude_hold(not aids.attitude_hold, self, last_update_time)


## Toggles position hold (DVL station keeping); returns false if it cannot engage.
func toggle_position_hold() -> bool:
	return aids.set_position_hold(not aids.position_hold, self, last_update_time)


## Toggles heading hold; returns false (see aids.status) if it cannot engage.
func toggle_heading_hold() -> bool:
	return aids.set_heading_hold(not aids.heading_hold, self, last_update_time)


func set_pilot_command(axis: int, value: float) -> void:
	pilot_command[axis] = clampf(value, -1.0, 1.0)


func set_pilot_commands(values: PackedFloat64Array) -> void:
	for axis in mini(values.size(), 6):
		pilot_command[axis] = clampf(values[axis], -1.0, 1.0)


func clear_pilot_commands() -> void:
	pilot_command.fill(0.0)


## Body wrench [Fx, Fy, Fz, Mx, My, Mz] requested by axis commands
## (default: the current pilot commands).
func demanded_wrench(commands: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:
	if commands.is_empty():
		commands = pilot_command
	var wrench := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for axis in 6:
		var c := clampf(commands[axis], -1.0, 1.0)
		if c == 0.0:
			continue
		var index: int = AXIS_TO_WRENCH[axis][0]
		var wrench_sign: float = AXIS_TO_WRENCH[axis][1] * signf(c)
		wrench[index] += wrench_sign * absf(c) * allocator.capability(index, wrench_sign)
	return wrench


func pre_step(context: StepContext) -> void:
	var commands := pilot_command.duplicate()
	autonomy.pre_step(self, commands, context.sim_time, context.dt)
	applied_command = aids.apply(self, commands, context.sim_time, context.dt)
	var thrusts := allocator.allocate(demanded_wrench(applied_command))
	for i in thrusters.size():
		thrusters[i].set_thrust_demand(thrusts[i])
		thrusters[i].update(context.dt)


func post_step(context: StepContext) -> void:
	var speed := velocity.length()
	distance_travelled += speed * context.dt
	max_speed = maxf(max_speed, speed)
	last_update_time = context.sim_time + context.dt
	manipulator.step(context, self)
	sensors.update(context, self)
	autonomy.post_step(self, context.sim_time + context.dt, context.dt)


func reset_state() -> void:
	super()
	for thruster in thrusters:
		thruster.reset()
	distance_travelled = 0.0
	max_speed = 0.0
	last_update_time = 0.0
	applied_command.fill(0.0)
	aids.reset()
	sensors.reset()
	manipulator.reset()
	autonomy.reset()


func get_type_name() -> String:
	return "RovVehicle"


## Keeps an engaged depth hold at the same height above the seabed when the
## whole site moves vertically (water depth changed).
func shift(offset: Vector3) -> void:
	super(offset)
	if aids.depth_hold:
		aids.shift_depth(-offset.y, last_update_time)


# --- Telemetry -------------------------------------------------------------------

func forward_vector() -> Vector3:
	return orientation * Vector3.FORWARD


func heading_degrees() -> float:
	return WorldFrame.heading_from_direction(forward_vector())


## Pitch angle, positive nose up, degrees.
func pitch_degrees() -> float:
	return rad_to_deg(asin(clampf(forward_vector().y, -1.0, 1.0)))


## Roll angle, positive starboard down, degrees.
func roll_degrees() -> float:
	var right := orientation * Vector3.RIGHT
	var up := orientation * Vector3.UP
	return rad_to_deg(atan2(-right.y, up.y))


func depth() -> float:
	return -position.y


## Height of the lowest hull point above the local seabed, m.
func altitude(world: WorldModel) -> float:
	var lowest := INF
	for local_point in contact.contact_points:
		var p := local_to_world_point(local_point)
		lowest = minf(lowest, p.y - world.seabed_y_at(p.x, p.z))
	return lowest


## Velocity components in vehicle terms: (surge forward, sway starboard, heave up), m/s.
func body_velocity_components() -> Vector3:
	var v := body_velocity()
	return Vector3(-v.z, v.x, v.y)


func water_relative_velocity(world: WorldModel) -> Vector3:
	return velocity - world.current_velocity_at(position)


## Yaw rate, positive clockwise seen from above, degrees per second.
func yaw_rate_degrees() -> float:
	return rad_to_deg(-angular_velocity.y)


## Buoyancy minus weight in the given water, N (positive = rises).
func net_buoyancy(environment: EnvironmentConfig) -> float:
	return (environment.water_density * displaced_volume - mass) * environment.gravity


## Static and performance characteristics in the given environment.
## Predicted speeds assume still water, steady state and one axis at a time.
func characteristics(environment: EnvironmentConfig) -> Dictionary:
	var g := environment.gravity
	var rho := environment.water_density
	var weight := mass * g
	var buoyancy := rho * g * displaced_volume
	var net := buoyancy - weight
	var bg := center_of_buoyancy.y
	var restoring := buoyancy * bg
	var viscosity_ratio := environment.dynamic_viscosity / HydrodynamicDamping.REFERENCE_VISCOSITY
	var density_ratio := rho / HydrodynamicDamping.REFERENCE_DENSITY
	var k_lin := damping.linear_translational * viscosity_ratio
	var k_quad := damping.quadratic_translational(rho)
	var k_lin_rot := damping.linear_rotational * viscosity_ratio
	var k_quad_rot := damping.quadratic_rotational * density_ratio
	var surge_forward := allocator.capability(2, -1.0)
	var surge_reverse := allocator.capability(2, 1.0)
	var sway := allocator.capability(0, 1.0)
	var heave_up := allocator.capability(1, 1.0)
	var heave_down := allocator.capability(1, -1.0)
	var yaw := allocator.capability(4, -1.0)
	var pitch := allocator.capability(3, 1.0)
	var roll := allocator.capability(5, -1.0)
	return {
		"weight": weight,
		"buoyancy": buoyancy,
		"net_buoyancy": net,
		"displaced_volume": displaced_volume,
		"bg": bg,
		"static_pitch_trim": rad_to_deg(atan2(-center_of_buoyancy.z, bg)) if restoring > 0.0 else NAN,
		"restoring_stiffness": restoring,
		"roll_period": TAU * sqrt((inertia.z + added_inertia.z) / restoring) if restoring > 0.0 else INF,
		"pitch_period": TAU * sqrt((inertia.x + added_inertia.x) / restoring) if restoring > 0.0 else INF,
		"thrust_surge_forward": surge_forward,
		"thrust_surge_reverse": surge_reverse,
		"thrust_sway": sway,
		"thrust_heave_up": heave_up,
		"thrust_heave_down": heave_down,
		"moment_yaw": yaw,
		"moment_pitch": pitch,
		"moment_roll": roll,
		"speed_surge": terminal_speed(surge_forward, k_lin.z, k_quad.z),
		"speed_surge_reverse": terminal_speed(surge_reverse, k_lin.z, k_quad.z),
		"speed_sway": terminal_speed(sway, k_lin.x, k_quad.x),
		"speed_heave_up": terminal_speed(heave_up + net, k_lin.y, k_quad.y),
		"speed_heave_down": terminal_speed(heave_down - net, k_lin.y, k_quad.y),
		"yaw_rate": rad_to_deg(terminal_speed(yaw, k_lin_rot.y, k_quad_rot.y)),
	}


## Steady speed where k_lin·v + k_quad·v² equals the driving force (0 if none).
static func terminal_speed(force: float, k_lin: float, k_quad: float) -> float:
	if force <= 0.0:
		return 0.0
	if k_quad <= 1e-12:
		return force / k_lin if k_lin > 0.0 else INF
	return (-k_lin + sqrt(k_lin * k_lin + 4.0 * k_quad * force)) / (2.0 * k_quad)
