## SimClock and SimulationEngine: fixed stepping, time scale, state machine.
extends "res://tests/test_suite.gd"


func test_clock_fixed_steps() -> void:
	var clock := SimClock.new()
	check(clock.consume(0.05) == 5, "0.05 s -> 5 steps of 10 ms")
	check(clock.consume(0.004) == 0, "partial step accumulates")
	check(clock.consume(0.007) == 1, "accumulated remainder completes a step")
	for i in 7:
		clock.advance_step()
	check_near(clock.sim_time, 0.07, 1e-12, "time derived from step count")
	clock.time_scale = 2.0
	check(clock.consume(0.05) == 10, "time scale doubles the steps")
	clock.time_scale = 0.0
	check(clock.consume(1.0) == 0, "zero time scale advances nothing")


func test_clock_step_budget() -> void:
	var clock := SimClock.new()
	clock.max_steps_per_frame = 50
	check(clock.consume(10.0) == 50, "steps capped per frame")
	check_near(clock.dropped_time, 9.5, 1e-9, "excess time reported as dropped")
	clock.reset()
	check(clock.step_count == 0 and clock.dropped_time == 0.0, "reset clears clock")


func test_clock_no_drift() -> void:
	var clock := SimClock.new()
	var steps := 0
	for i in 6000:
		steps += clock.consume(1.0 / 60.0)
	for i in steps:
		clock.advance_step()
	check(absi(steps - 10000) <= 1, "100 s of 60 Hz frames -> 10000 steps (got %d)" % steps)


func test_engine_state_machine() -> void:
	var engine := SimulationEngine.new()
	engine.auto_advance = false
	var states: Array = []
	engine.state_changed.connect(func(new_state: int, _previous: int) -> void: states.append(new_state))
	check(engine.state == SimulationEngine.State.READY, "engine starts READY")
	check(engine.advance(1.0) == 0, "no stepping before start")
	engine.start()
	check(engine.is_running(), "start -> RUNNING")
	check(engine.advance(0.1) == 10, "advance runs fixed steps")
	check_near(engine.get_sim_time(), 0.1, 1e-12, "sim time after 0.1 s")
	engine.pause()
	check(engine.state == SimulationEngine.State.PAUSED, "pause -> PAUSED")
	check(engine.advance(1.0) == 0, "no stepping while paused")
	check(engine.step_once(), "single step allowed while paused")
	check_near(engine.get_sim_time(), 0.11, 1e-12, "single step adds one dt")
	engine.set_time_scale(2.0)
	engine.start()
	engine.advance(0.1)
	check_near(engine.get_sim_time(), 0.31, 1e-12, "time scale 2 doubles progress")
	check(not engine.step_once(), "single step refused while running")
	engine.set_time_scale(1000.0)
	check_near(engine.clock.time_scale, SimulationEngine.MAX_TIME_SCALE, 1e-12, "time scale clamped")
	var reset_count: Array = [0]
	engine.simulation_reset.connect(func() -> void: reset_count[0] += 1)
	engine.reset()
	check(engine.state == SimulationEngine.State.READY, "reset -> READY")
	check_near(engine.get_sim_time(), 0.0, 1e-12, "reset zeroes time")
	check(reset_count[0] == 1, "reset signal emitted")
	check(engine.step_once() and engine.state == SimulationEngine.State.PAUSED, "step from READY -> PAUSED")
	check(states == [SimulationEngine.State.RUNNING, SimulationEngine.State.PAUSED,
		SimulationEngine.State.RUNNING, SimulationEngine.State.READY, SimulationEngine.State.PAUSED],
		"state change sequence (got %s)" % [states])
	engine.free()


func test_engine_signals_per_step() -> void:
	var engine := SimulationEngine.new()
	engine.auto_advance = false
	var step_times: Array = []
	var frames: Array = []
	engine.step_completed.connect(func(t: float, _dt: float) -> void: step_times.append(t))
	engine.frame_advanced.connect(func(t: float, steps: int) -> void: frames.append([t, steps]))
	engine.start()
	engine.advance(0.03)
	check(step_times.size() == 3, "step_completed once per step")
	check_near(step_times[2], 0.03, 1e-12, "step_completed reports time after step")
	check(frames.size() == 1 and frames[0][1] == 3, "frame_advanced once per frame with step count")
	engine.free()
