## PhysicsWorld and force models, checked against closed-form results.
## These test bodies exist only inside the tests; the application creates none.
extends "res://tests/test_suite.gd"

var env: EnvironmentConfig
var world: WorldModel
var physics: PhysicsWorld
var context: StepContext


func _setup() -> void:
	env = EnvironmentConfig.new()
	env.current_speed = 0.0
	world = WorldModel.new(env)
	physics = PhysicsWorld.new()
	physics.add_default_models()
	context = StepContext.new()
	context.environment = env
	context.world = world
	context.dt = 0.01


func _make_body(mass: float, volume: float, start: Vector3) -> SimBody:
	var body := SimBody.new("TestBody", start)
	body.mass = mass
	body.displaced_volume = volume
	body.drag_coefficient = 1.0
	body.reference_area = 0.1
	body.characteristic_length = 0.35
	return body


func _simulate(bodies: Array, seconds: float) -> void:
	var typed: Array[SimBody] = []
	typed.assign(bodies)
	for i in int(round(seconds / context.dt)):
		physics.step(typed, context)
		context.sim_time += context.dt


func test_neutral_buoyancy_holds_position() -> void:
	_setup()
	var body := _make_body(1025.0 * 0.02, 0.02, Vector3(0, -10, 0))
	_simulate([body], 10.0)
	check_vec_near(body.position, Vector3(0, -10, 0), 1e-6, "neutrally buoyant body stays put")
	check(body.force_breakdown.has("gravity") and body.force_breakdown.has("buoyancy")
		and body.force_breakdown.has("hydrodynamic_drag"), "force breakdown recorded per model")


func test_terminal_sinking_velocity() -> void:
	_setup()
	var body := _make_body(50.0, 0.02, Vector3(0, -2, 0))
	_simulate([body], 4.0)
	# Solve k_quad * v^2 + k_lin * v = W' for the analytic terminal velocity.
	var w := body.submerged_weight(env)
	var k_lin := HydrodynamicDragForce.STOKES_FACTOR * env.dynamic_viscosity * body.characteristic_length
	var k_quad := 0.5 * env.water_density * body.drag_coefficient * body.reference_area
	var v_terminal := (-k_lin + sqrt(k_lin * k_lin + 4.0 * k_quad * w)) / (2.0 * k_quad)
	check_near(-body.velocity.y, v_terminal, v_terminal * 0.005, "sinking speed matches analytic terminal velocity")


func test_current_entrains_neutral_body() -> void:
	_setup()
	env.current_speed = 0.5
	env.current_heading = 90.0
	var body := _make_body(1025.0 * 0.02, 0.02, Vector3(0, -10, 0))
	_simulate([body], 60.0)
	check_near(body.velocity.x, 0.5, 0.01, "body approaches current velocity")
	check_near(body.velocity.y, 0.0, 1e-6, "no vertical drift for neutral body")


func test_free_fall_without_drag() -> void:
	_setup()
	physics.get_force_model("hydrodynamic_drag").enabled = false
	var body := _make_body(50.0, 0.02, Vector3(0, -2, 0))
	_simulate([body], 1.0)
	var a := body.submerged_weight(env) / body.mass
	# Velocity is a 32-bit Vector3 accumulated over 100 steps: compare at 1e-4.
	check_near(-body.velocity.y, a * 1.0, 1e-4, "drag disabled: v = (W'/m) t")


func test_seabed_contact() -> void:
	_setup()
	var body := _make_body(50.0, 0.02, Vector3(0, -25, 0))
	body.bottom_clearance = 0.2
	_simulate([body], 10.0)
	check_near(body.position.y, -30.0 + 0.2, 1e-5, "body rests on seabed plus clearance")
	check(body.in_seabed_contact, "contact flag set")
	check_near(body.velocity.y, 0.0, 1e-12, "no downward velocity in contact")


func test_gravity_parameter_used() -> void:
	_setup()
	env.gravity = 0.0
	var body := _make_body(50.0, 0.02, Vector3(0, -10, 0))
	_simulate([body], 5.0)
	check_vec_near(body.position, Vector3(0, -10, 0), 1e-9, "zero gravity: heavy body does not sink")


func test_engine_integration_and_reset() -> void:
	var engine := SimulationEngine.new()
	engine.auto_advance = false
	engine.environment.current_speed = 0.0
	var body := SimBody.new("Sinker", Vector3(0, -5, 0))
	body.mass = 50.0
	body.displaced_volume = 0.02
	body.reference_area = 0.1
	body.characteristic_length = 0.35
	engine.objects.register(body)
	engine.start()
	engine.advance(1.0)
	check(body.position.y < -5.5, "engine steps registered bodies")
	engine.reset()
	check_vec_near(body.position, Vector3(0, -5, 0), 1e-9, "engine reset restores body")
	check_vec_near(body.velocity, Vector3.ZERO, 1e-9, "engine reset restores velocity")
	engine.free()
