## WorldFrame conversions, WorldModel queries and Bathymetry.
extends "res://tests/test_suite.gd"


func test_frame_conversions() -> void:
	var p := Vector3(1.0, 2.0, 3.0)
	check_vec_near(WorldFrame.godot_to_enu(p), Vector3(1.0, -3.0, 2.0), 1e-9, "Godot -> ENU")
	check_vec_near(WorldFrame.enu_to_godot(WorldFrame.godot_to_enu(p)), p, 1e-9, "ENU round trip")
	check_vec_near(WorldFrame.godot_to_ned(p), Vector3(-3.0, 1.0, -2.0), 1e-9, "Godot -> NED")
	check_vec_near(WorldFrame.ned_to_godot(WorldFrame.godot_to_ned(p)), p, 1e-9, "NED round trip")
	check_near(WorldFrame.depth_of(Vector3(0, -12.5, 0)), 12.5, 1e-9, "depth is -y")


func test_headings() -> void:
	check_vec_near(WorldFrame.direction_from_heading(0.0), Vector3(0, 0, -1), 1e-9, "north = -Z")
	check_vec_near(WorldFrame.direction_from_heading(90.0), Vector3(1, 0, 0), 1e-9, "east = +X")
	for h in [0.0, 45.0, 90.0, 135.0, 180.0, 270.0, 359.0]:
		check_near(WorldFrame.heading_from_direction(WorldFrame.direction_from_heading(h)), h, 1e-6, "heading round trip %s" % h)
	check(WorldFrame.cardinal(90.0) == "E", "cardinal E")
	check(WorldFrame.cardinal(359.0) == "N", "cardinal wraps to N")
	check(WorldFrame.cardinal(225.0) == "SW", "cardinal SW")


func test_world_model() -> void:
	var env := EnvironmentConfig.new()
	var world := WorldModel.new(env)
	check_near(world.seabed_y_at(0.0, 0.0), -30.0, 1e-9, "flat test area at reference depth")
	env.water_depth = 80.0
	check_near(world.seabed_y_at(5.0, -5.0), -80.0, 1e-9, "seabed follows water depth")
	var p := world.position_from_enu_depth(10.0, 20.0, 5.0)
	check_vec_near(p, Vector3(10.0, -5.0, -20.0), 1e-9, "position from east/north/depth")
	check(world.is_in_water(p), "point in water column")
	check(not world.is_in_water(Vector3(0, 1, 0)), "above surface is not in water")
	check(not world.is_in_water(Vector3(0, -81, 0)), "below seabed is not in water")
	check(not world.is_within_bounds(Vector3(600, -10, 0)), "outside domain")
	var clamped := world.clamp_to_water(Vector3(900.0, -500.0, -900.0), 0.5, 0.3)
	check(world.is_within_bounds(clamped), "clamp_to_water stays in bounds")
	check_near(clamped.y, world.seabed_y_at(clamped.x, clamped.z) + 0.5, 1e-6, "clamp_to_water respects seabed margin")
	# Vector3 components are 32-bit floats, so positions compare at ~1e-5 m.
	check_near(world.clamp_to_water(Vector3(0, 5, 0), 0.0, 0.3).y, -0.3, 1e-5, "clamp_to_water respects surface margin")
	var on_bed := world.place_on_seabed(200.0, 150.0, 1.0)
	check_near(on_bed.y, world.seabed_y_at(200.0, -150.0) + 1.0, 1e-4, "place_on_seabed")


func test_bathymetry() -> void:
	var a := Bathymetry.new(7)
	var b := Bathymetry.new(7)
	var max_abs := 0.0
	var differs := false
	for i in 200:
		var x := -450.0 + i * 4.5
		var z := 300.0 - i * 3.0
		var h := a.height_offset(x, z)
		max_abs = maxf(max_abs, absf(h))
		if h != b.height_offset(x, z):
			differs = true
	check(not differs, "bathymetry deterministic for a seed")
	check(max_abs > 0.2, "relief exists outside the test area")
	check(max_abs <= a.max_relief() + 1e-6, "relief within declared amplitude")
	check_near(a.height_offset(20.0, -20.0), 0.0, 1e-12, "test area is level")
