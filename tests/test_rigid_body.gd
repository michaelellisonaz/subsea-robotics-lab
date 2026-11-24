## RigidSimBody: rotation integration, torques, added mass and the buoyancy
## restoring moment, checked against closed-form results.
extends "res://tests/test_suite.gd"


class ConstantLoad extends ForceModel:
	var force: Vector3
	var local_point: Vector3

	func _init(p_force: Vector3, p_local_point: Vector3) -> void:
		model_name = "constant"
		force = p_force
		local_point = p_local_point

	func apply(body: SimBody, _context: StepContext) -> void:
		body.add_force_at_point(force, body.local_to_world_point(local_point), model_name)


var env: EnvironmentConfig
var world: WorldModel
var physics: PhysicsWorld
var context: StepContext


func _setup(with_default_models: bool) -> void:
	env = EnvironmentConfig.new()
	env.current_speed = 0.0
	env.water_depth = 200.0
	world = WorldModel.new(env)
	physics = PhysicsWorld.new()
	if with_default_models:
		physics.add_default_models()
	context = StepContext.new()
	context.environment = env
	context.world = world
	context.dt = 0.01


func _body(mass: float, inertia: Vector3) -> RigidSimBody:
	var body := RigidSimBody.new("Rigid", Vector3(0.0, -100.0, 0.0))
	body.mass = mass
	body.inertia = inertia
	body.drag_coefficient = 0.0
	body.reference_area = 0.0
	body.characteristic_length = 0.0
	return body


func _simulate(body: SimBody, seconds: float, each_step: Callable = Callable()) -> void:
	var bodies: Array[SimBody] = [body]
	for i in int(round(seconds / context.dt)):
		physics.step(bodies, context)
		context.sim_time += context.dt
		if each_step.is_valid():
			each_step.call()


func test_spin_about_principal_axis() -> void:
	_setup(false)
	var body := _body(10.0, Vector3(1.0, 2.0, 3.0))
	body.angular_velocity = Vector3(0.0, 1.0, 0.0)
	_simulate(body, 2.0)
	check_vec_near(body.angular_velocity, Vector3(0.0, 1.0, 0.0), 1e-5, "torque-free spin about a principal axis is steady")
	check_near(body.orientation.angle_to(Quaternion(Vector3.UP, 2.0)), 0.0, 1e-3, "orientation advances by omega * t")
	check_near(body.orientation.length(), 1.0, 1e-5, "quaternion stays normalised")


func test_tumbling_conserves_momentum_and_energy() -> void:
	_setup(false)
	var body := _body(10.0, Vector3(2.0, 3.0, 5.0))
	body.angular_velocity = Vector3(0.3, 0.1, 0.8)
	var momentum_0 := body.orientation * (body.inertia * body.angular_velocity)
	var energy_0 := 0.5 * (body.inertia * body.angular_velocity).dot(body.angular_velocity)
	_simulate(body, 5.0)
	var momentum := body.orientation * (body.inertia * body.angular_velocity)
	var energy := 0.5 * (body.inertia * body.angular_velocity).dot(body.angular_velocity)
	check(momentum.distance_to(momentum_0) / momentum_0.length() < 0.02, "angular momentum conserved within 2 %% (drift %.3f %%)" % (100.0 * momentum.distance_to(momentum_0) / momentum_0.length()))
	check(absf(energy - energy_0) / energy_0 < 0.02, "rotational energy conserved within 2 %% (drift %.3f %%)" % (100.0 * absf(energy - energy_0) / energy_0))


func test_off_centre_force_produces_torque() -> void:
	_setup(false)
	var body := _body(10.0, Vector3(2.0, 2.0, 2.0))
	body.local_force_models.append(ConstantLoad.new(Vector3(0.0, 0.0, -10.0), Vector3(1.0, 0.0, 0.0)))
	_simulate(body, 0.01)
	# r × F = (1,0,0) × (0,0,-10) = (0, 10, 0); alpha = 10 / 2 = 5 rad/s².
	check_vec_near(body.angular_velocity, Vector3(0.0, 0.05, 0.0), 1e-6, "angular acceleration = (r × F) / J")
	# 1e-5: the body also turns by 5e-4 rad during the step, which tilts v slightly.
	check_vec_near(body.velocity, Vector3(0.0, 0.0, -0.01), 1e-5, "linear acceleration = F / m")
	check(body.torque_breakdown.has("constant"), "torque recorded per model")


func test_added_mass_slows_acceleration() -> void:
	_setup(false)
	var body := _body(50.0, Vector3.ONE)
	body.added_mass_linear = Vector3(0.0, 0.0, 50.0)
	body.local_force_models.append(ConstantLoad.new(Vector3(0.0, 0.0, -100.0), Vector3.ZERO))
	_simulate(body, 1.0)
	check_near(-body.velocity.z, 1.0, 1e-3, "a = F / (m + m_added)")


func test_buoyancy_restoring_period() -> void:
	_setup(true)
	var body := _body(100.0, Vector3(10.0, 10.0, 10.0))
	body.displaced_volume = 100.0 / env.water_density
	body.center_of_buoyancy = Vector3(0.0, 0.1, 0.0)
	body.orientation = Quaternion(Vector3.BACK, deg_to_rad(10.0))
	var crossings: Array = []
	var peak: Array = [0.0]
	var previous: Array = [(body.orientation * Vector3.UP).x]
	_simulate(body, 10.0, func() -> void:
		var tilt := (body.orientation * Vector3.UP).x
		if signf(tilt) != signf(previous[0]) and previous[0] != 0.0:
			crossings.append(context.sim_time - context.dt * absf(tilt) / absf(tilt - previous[0]))
		previous[0] = tilt
		if context.sim_time > 8.0:
			peak[0] = maxf(peak[0], absf(asin(clampf(tilt, -1.0, 1.0)))))
	var expected := TAU * sqrt(10.0 / (env.water_density * env.gravity * body.displaced_volume * 0.1))
	check(crossings.size() >= 6, "body oscillates about upright (%d crossings)" % crossings.size())
	if crossings.size() >= 2:
		var period: float = 2.0 * (crossings[-1] - crossings[0]) / (crossings.size() - 1)
		check_near(period, expected, expected * 0.02, "roll period = 2π sqrt(J / (ρ g V BG))")
	check_near(rad_to_deg(peak[0]), 10.0, 1.0, "undamped oscillation keeps its amplitude")
