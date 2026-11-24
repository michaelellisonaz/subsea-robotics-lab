## Thrust allocation: turns a desired body wrench into individual thrusts.
##
## Wrench vector (body axes): [Fx, Fy, Fz, Mx, My, Mz] - forces along x
## (starboard), y (up), z (aft) and moments about those axes.
##
## The configuration matrix B (6 x n) has one column per thruster:
## [d; r × d], with d the thrust direction and r the mounting point relative to
## the CG. The allocation is the minimum-norm least-squares solution
##     u = Bᵀ (B Bᵀ + λI)⁻¹ τ
## (Moore-Penrose pseudo-inverse with tiny regularisation λ). If any thruster
## would exceed its limit, the whole solution is scaled down uniformly, which
## keeps the direction of the demanded wrench. Axes the layout cannot actuate
## receive (near) zero.
##
## Capability: for each wrench axis and sign, the largest magnitude reachable
## with that allocation before a thruster saturates.
class_name ThrustAllocator
extends RefCounted

const AXIS_NAMES := ["Fx", "Fy", "Fz", "Mx", "My", "Mz"]
const REGULARIZATION := 1e-9
## Fraction of a unit demand that must be reproduced for an axis to count as actuated.
const ACTUATION_THRESHOLD := 0.5

var thrusters: Array[Thruster] = []
var configuration_matrix: DenseMatrix
var pseudo_inverse: DenseMatrix
var capability_positive: PackedFloat64Array = PackedFloat64Array()
var capability_negative: PackedFloat64Array = PackedFloat64Array()


func _init(p_thrusters: Array[Thruster] = []) -> void:
	thrusters = p_thrusters
	rebuild()


## Recomputes B, its pseudo-inverse and the axis capabilities.
func rebuild() -> void:
	var n := thrusters.size()
	configuration_matrix = DenseMatrix.new(6, n)
	for i in n:
		var d := thrusters[i].direction.normalized()
		var m := thrusters[i].position.cross(d)
		configuration_matrix.set_at(0, i, d.x)
		configuration_matrix.set_at(1, i, d.y)
		configuration_matrix.set_at(2, i, d.z)
		configuration_matrix.set_at(3, i, m.x)
		configuration_matrix.set_at(4, i, m.y)
		configuration_matrix.set_at(5, i, m.z)
	var bt := configuration_matrix.transposed()
	var bbt := configuration_matrix.multiply(bt)
	for k in 6:
		bbt.set_at(k, k, bbt.at(k, k) + REGULARIZATION)
	var inv := bbt.inverse()
	pseudo_inverse = bt.multiply(inv) if inv != null else DenseMatrix.new(n, 6)
	_compute_capability()


## Thrusts (N, one per thruster) for a desired wrench, saturated uniformly.
func allocate(wrench: PackedFloat64Array) -> PackedFloat64Array:
	var u := pseudo_inverse.multiply_vector(wrench)
	var worst := 1.0
	for i in u.size():
		var limit := thrusters[i].limit_for(u[i])
		if limit <= 0.0:
			u[i] = 0.0
			continue
		worst = maxf(worst, absf(u[i]) / limit)
	if worst > 1.0:
		for i in u.size():
			u[i] /= worst
	return u


## Wrench produced by a set of thrusts.
func achieved_wrench(thrusts: PackedFloat64Array) -> PackedFloat64Array:
	return configuration_matrix.multiply_vector(thrusts)


## Largest achievable magnitude along one wrench axis in one direction
## (N for forces, N·m for moments). 0 if the layout cannot actuate it.
func capability(axis: int, direction_sign: float) -> float:
	return capability_positive[axis] if direction_sign >= 0.0 else capability_negative[axis]


func is_actuated(axis: int) -> bool:
	return capability_positive[axis] > 0.0 or capability_negative[axis] > 0.0


func _compute_capability() -> void:
	capability_positive.resize(6)
	capability_negative.resize(6)
	for axis in 6:
		for direction_sign in [1.0, -1.0]:
			var demand := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
			demand[axis] = direction_sign
			var u := pseudo_inverse.multiply_vector(demand)
			var achieved := achieved_wrench(u)
			var reach := 0.0
			if achieved[axis] * direction_sign > ACTUATION_THRESHOLD:
				var worst := 0.0
				for i in u.size():
					var limit := thrusters[i].limit_for(u[i])
					if limit > 0.0:
						worst = maxf(worst, absf(u[i]) / limit)
				if worst > 1e-12:
					reach = achieved[axis] * direction_sign / worst
			if direction_sign > 0.0:
				capability_positive[axis] = reach
			else:
				capability_negative[axis] = reach
