## Small dense matrix (row-major, 64-bit floats) for control-allocation maths.
## Sized for the 6 x n problems in this project, not for large systems.
class_name DenseMatrix
extends RefCounted

var rows: int = 0
var cols: int = 0
var data: PackedFloat64Array = PackedFloat64Array()


func _init(p_rows: int = 0, p_cols: int = 0) -> void:
	rows = p_rows
	cols = p_cols
	data.resize(rows * cols)
	data.fill(0.0)


static func identity(n: int) -> DenseMatrix:
	var m := DenseMatrix.new(n, n)
	for i in n:
		m.data[i * n + i] = 1.0
	return m


func at(r: int, c: int) -> float:
	return data[r * cols + c]


func set_at(r: int, c: int, value: float) -> void:
	data[r * cols + c] = value


func transposed() -> DenseMatrix:
	var t := DenseMatrix.new(cols, rows)
	for r in rows:
		for c in cols:
			t.data[c * rows + r] = data[r * cols + c]
	return t


func multiply(other: DenseMatrix) -> DenseMatrix:
	assert(cols == other.rows, "DenseMatrix.multiply: dimension mismatch")
	var result := DenseMatrix.new(rows, other.cols)
	for r in rows:
		for c in other.cols:
			var total := 0.0
			for k in cols:
				total += data[r * cols + k] * other.data[k * other.cols + c]
			result.data[r * other.cols + c] = total
	return result


func multiply_vector(v: PackedFloat64Array) -> PackedFloat64Array:
	assert(v.size() == cols, "DenseMatrix.multiply_vector: dimension mismatch")
	var result := PackedFloat64Array()
	result.resize(rows)
	for r in rows:
		var total := 0.0
		for c in cols:
			total += data[r * cols + c] * v[c]
		result[r] = total
	return result


## Inverse by Gauss-Jordan elimination with partial pivoting.
## Returns null if the matrix is not square or is (numerically) singular.
func inverse() -> DenseMatrix:
	if rows != cols:
		return null
	var n := rows
	var a := data.duplicate()
	var b := DenseMatrix.identity(n).data
	for col in n:
		var pivot := col
		var best := absf(a[col * n + col])
		for r in range(col + 1, n):
			var candidate := absf(a[r * n + col])
			if candidate > best:
				best = candidate
				pivot = r
		if best < 1e-12:
			return null
		if pivot != col:
			for k in n:
				var tmp := a[col * n + k]
				a[col * n + k] = a[pivot * n + k]
				a[pivot * n + k] = tmp
				tmp = b[col * n + k]
				b[col * n + k] = b[pivot * n + k]
				b[pivot * n + k] = tmp
		var p := a[col * n + col]
		for k in n:
			a[col * n + k] /= p
			b[col * n + k] /= p
		for r in n:
			if r == col:
				continue
			var factor := a[r * n + col]
			if factor == 0.0:
				continue
			for k in n:
				a[r * n + k] -= factor * a[col * n + k]
				b[r * n + k] -= factor * b[col * n + k]
	var result := DenseMatrix.new(n, n)
	result.data = b
	return result
