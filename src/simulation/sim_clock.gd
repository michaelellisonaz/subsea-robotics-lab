## Fixed-step simulation clock.
##
## Real (wall-clock) frame time is multiplied by [member time_scale] and fed
## into an accumulator; the simulation then advances in whole steps of
## [member fixed_dt]. Results therefore do not depend on the rendering frame
## rate, and pause / speed changes are exact. Simulation time is derived from
## the integer step count, so it never drifts through repeated float addition.
class_name SimClock
extends RefCounted

const DEFAULT_FIXED_DT := 0.01

## Duration of one simulation step, s. Treat as constant during a run.
var fixed_dt: float = DEFAULT_FIXED_DT
## Simulated seconds per real second.
var time_scale: float = 1.0
## Upper bound on steps per rendered frame. Protects against a "spiral of
## death" when the machine cannot keep up; excess time is dropped and counted.
var max_steps_per_frame: int = 200
## Completed steps since the last reset.
var step_count: int = 0
## Simulated time discarded because the per-frame step budget was exceeded, s.
var dropped_time: float = 0.0

var _accumulator: float = 0.0

## Current simulation time, s.
var sim_time: float:
	get:
		return step_count * fixed_dt


## Adds a real frame interval and returns how many fixed steps are now due.
## The caller performs the steps and calls [method advance_step] for each.
func consume(real_delta: float) -> int:
	if real_delta <= 0.0 or time_scale <= 0.0:
		return 0
	_accumulator += real_delta * time_scale
	var steps := floori(_accumulator / fixed_dt + 1e-9)
	if steps > max_steps_per_frame:
		dropped_time += (steps - max_steps_per_frame) * fixed_dt
		steps = max_steps_per_frame
		_accumulator = 0.0
	else:
		_accumulator = maxf(_accumulator - steps * fixed_dt, 0.0)
	return steps


func advance_step() -> void:
	step_count += 1


## How far real time has progressed into the next step (0..1). Renderers use
## it to interpolate object poses between the last two steps.
func interpolation_fraction() -> float:
	return clampf(_accumulator / fixed_dt, 0.0, 1.0)


## Forgets partially accumulated time (used when pausing).
func discard_pending() -> void:
	_accumulator = 0.0


func reset() -> void:
	step_count = 0
	dropped_time = 0.0
	_accumulator = 0.0
