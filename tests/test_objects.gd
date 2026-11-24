## ObjectRegistry and SimObject lifecycle.
extends "res://tests/test_suite.gd"


class CountingObject extends SimObject:
	var pre_calls := 0
	var post_calls := 0

	func pre_step(_context: StepContext) -> void:
		pre_calls += 1

	func post_step(_context: StepContext) -> void:
		post_calls += 1


func test_registration() -> void:
	var registry := ObjectRegistry.new()
	var added: Array = []
	registry.object_registered.connect(func(o: SimObject) -> void: added.append(o))
	var a := SimObject.new("A", Vector3(1, -2, 3))
	var b := SimBody.new("B")
	var id_a := registry.register(a)
	var id_b := registry.register(b)
	check(id_a > 0 and id_b > 0 and id_a != id_b, "unique ids assigned")
	check(registry.register(a) == id_a, "re-registering keeps id")
	check(registry.count() == 2 and added.size() == 2, "count and signal")
	check(registry.get_object(id_b) == b, "lookup by id")
	check(registry.find_by_name("A") == a, "lookup by name")
	check(registry.get_bodies().size() == 1 and registry.get_bodies()[0] == b, "bodies list filters SimBody")
	check(registry.unregister(a), "unregister succeeds")
	check(a.id == -1 and registry.count() == 1, "unregistered object cleared")
	check(not registry.unregister(a), "double unregister refused")
	registry.clear()
	check(registry.count() == 0 and registry.get_bodies().is_empty(), "clear empties registry")


func test_reset_restores_initial_state() -> void:
	var registry := ObjectRegistry.new()
	var body := SimBody.new("Probe", Vector3(0, -10, 0))
	body.velocity = Vector3(1, 0, 0)
	registry.register(body)
	body.position = Vector3(5, -20, 5)
	body.velocity = Vector3.ZERO
	body.orientation = Quaternion(Vector3.UP, 1.0)
	registry.reset_all()
	check_vec_near(body.position, Vector3(0, -10, 0), 1e-9, "position restored")
	check_vec_near(body.velocity, Vector3(1, 0, 0), 1e-9, "velocity restored")
	check(body.orientation.is_equal_approx(Quaternion.IDENTITY), "orientation restored")


func test_step_hooks_through_engine() -> void:
	var engine := SimulationEngine.new()
	engine.auto_advance = false
	var object := CountingObject.new("Counter")
	engine.objects.register(object)
	engine.start()
	engine.advance(0.05)
	check(object.pre_calls == 5 and object.post_calls == 5, "pre/post hooks run once per step")
	engine.free()
