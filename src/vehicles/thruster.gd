## One thruster: mounting geometry, limits and a first-order thrust response.
##
## The command is a normalised thrust demand (-1..1). Thrust follows the
## demand with time constant tau:  T += (T_target - T) · (1 - exp(-dt / tau)),
## where T_target = command · max forward (or reverse) thrust.
##
## Simplifications: thrust is linear in the command (no propeller curve or
## rpm model), independent of the vehicle's speed through the water (no
## advance-ratio losses) and has no thruster-thruster or hull interaction.
## Thrust figures are bollard-pull style ratings.
class_name Thruster
extends RefCounted

var thruster_name: String = "T"
## Mounting point relative to the vehicle CG, body axes, m.
var position: Vector3 = Vector3.ZERO
## Unit direction of the force on the vehicle for a positive command, body axes.
var direction: Vector3 = Vector3.FORWARD
## Maximum thrust for a positive command, N.
var max_forward_thrust: float = 90.0
## Maximum thrust magnitude for a negative command, N.
var max_reverse_thrust: float = 72.0
## First-order response time constant, s (0 = instantaneous).
var time_constant: float = 0.15
## Normalised thrust demand, -1..1.
var command: float = 0.0
## Current thrust (signed, along direction), N.
var thrust: float = 0.0


func _init(p_name: String = "T", p_position: Vector3 = Vector3.ZERO, p_direction: Vector3 = Vector3.FORWARD,
		p_max_forward: float = 90.0, p_max_reverse: float = 72.0, p_time_constant: float = 0.15) -> void:
	thruster_name = p_name
	position = p_position
	direction = p_direction.normalized()
	max_forward_thrust = p_max_forward
	max_reverse_thrust = p_max_reverse
	time_constant = p_time_constant


## Thrust limit applying to a signed thrust value, N.
func limit_for(signed_thrust: float) -> float:
	return max_forward_thrust if signed_thrust >= 0.0 else max_reverse_thrust


## Sets the command that requests a given thrust in newtons (clamped to limits).
func set_thrust_demand(newtons: float) -> void:
	var limit := limit_for(newtons)
	command = clampf(newtons / limit, -1.0, 1.0) if limit > 0.0 else 0.0


func target_thrust() -> float:
	var c := clampf(command, -1.0, 1.0)
	return c * (max_forward_thrust if c >= 0.0 else max_reverse_thrust)


func update(dt: float) -> void:
	var target := target_thrust()
	if time_constant <= 0.0:
		thrust = target
	else:
		thrust += (target - thrust) * (1.0 - exp(-dt / time_constant))


## Thrust as a fraction of the applicable limit (-1..1).
func thrust_fraction() -> float:
	var limit := limit_for(thrust)
	return thrust / limit if limit > 0.0 else 0.0


func reset() -> void:
	command = 0.0
	thrust = 0.0
