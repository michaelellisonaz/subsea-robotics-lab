## Builds and displays the seabed mesh from the WorldModel's bathymetry.
##
## The reference grid and axis lines are drawn by the seabed shader in world
## coordinates, so they follow the terrain exactly and need no extra geometry.
## The mesh is built relative to the seabed reference level; changing the
## water depth only moves this node.
class_name SeabedRenderer
extends Node3D

const SEABED_SHADER := preload("res://src/rendering/shaders/seabed.gdshader")
## Mesh cell size, m. Fine sediment detail comes from the shader instead.
const CELL_SIZE := 4.0

var grid_visible: bool = true

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial


func build(world: WorldModel) -> void:
	_material = ShaderMaterial.new()
	_material.shader = SEABED_SHADER
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "SeabedMesh"
	_mesh_instance.mesh = _build_mesh(world)
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)
	set_reference_y(world.seabed_reference_y())


func set_reference_y(y: float) -> void:
	position.y = y


func set_grid_visible(value: bool) -> void:
	grid_visible = value
	_material.set_shader_parameter("grid_enabled", value)


func _build_mesh(world: WorldModel) -> ArrayMesh:
	var half := world.half_extent
	var cells := int(round(2.0 * half / CELL_SIZE))
	var side := cells + 1

	var heights := PackedFloat32Array()
	heights.resize(side * side)
	for iz in side:
		var z := -half + iz * CELL_SIZE
		for ix in side:
			heights[iz * side + ix] = world.bathymetry.height_offset(-half + ix * CELL_SIZE, z)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(side * side)
	normals.resize(side * side)
	for iz in side:
		for ix in side:
			var i := iz * side + ix
			vertices[i] = Vector3(-half + ix * CELL_SIZE, heights[i], -half + iz * CELL_SIZE)
			# Central differences of the height field give the surface normal.
			var h_west := heights[iz * side + maxi(ix - 1, 0)]
			var h_east := heights[iz * side + mini(ix + 1, side - 1)]
			var h_north := heights[maxi(iz - 1, 0) * side + ix]
			var h_south := heights[mini(iz + 1, side - 1) * side + ix]
			normals[i] = Vector3(h_west - h_east, 2.0 * CELL_SIZE, h_north - h_south).normalized()

	# Two triangles per cell, clockwise when seen from above (Godot front faces).
	var indices := PackedInt32Array()
	indices.resize(cells * cells * 6)
	var k := 0
	for iz in cells:
		for ix in cells:
			var a := iz * side + ix
			var b := a + 1
			var c := a + side
			var d := c + 1
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = d
			indices[k + 3] = a
			indices[k + 4] = d
			indices[k + 5] = c
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
