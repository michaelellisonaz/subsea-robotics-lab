## Draws every GraspableObject in the registry (box or cylinder in its
## colour, with a small name label) and keeps it at the object's pose,
## interpolated between simulation steps. A RepairClamp is drawn as two
## hinged half-shells (open until installed); a connected RetrofitAnode shows
## its cable to the pipeline.
class_name ObjectVisuals
extends Node3D

var _alpha_source: Callable
var _nodes: Dictionary = {}  # GraspableObject -> Node3D
var _clamp_halves: Dictionary = {}  # RepairClamp -> [Node3D, Node3D]
var _cables: Dictionary = {}  # RetrofitAnode -> MeshInstance3D

const CLAMP_OPEN_DEGREES := 28.0


func bind(registry: ObjectRegistry, alpha_source: Callable) -> void:
	_alpha_source = alpha_source
	registry.object_registered.connect(_add)
	registry.object_unregistered.connect(_remove)
	for object in registry.get_all():
		_add(object)


func node_for(object: SimObject) -> Node3D:
	return _nodes.get(object)


func _process(_delta: float) -> void:
	var alpha: float = _alpha_source.call() if _alpha_source.is_valid() else 1.0
	for object in _nodes:
		_nodes[object].transform = object.get_interpolated_transform(alpha)
	for clamp in _clamp_halves:
		var opening := 0.0 if clamp.installed else deg_to_rad(CLAMP_OPEN_DEGREES)
		_clamp_halves[clamp][0].basis = Basis(Vector3.RIGHT, opening)
		_clamp_halves[clamp][1].basis = Basis(Vector3.RIGHT, -opening)
	for anode in _cables:
		var cable: MeshInstance3D = _cables[anode]
		cable.visible = anode.connected
		if anode.connected and anode.pipeline != null:
			var start: Vector3 = anode.get_interpolated_transform(alpha).origin
			var side := signf(start.z - anode.pipeline.axis_z())
			var finish := Vector3(start.x + 0.3, anode.pipeline.axis_y() - anode.pipeline.radius() * 0.3,
				anode.pipeline.axis_z() + side * anode.pipeline.radius() * 0.95)
			var span := finish - start
			cable.global_transform = Transform3D(ManipulatorVisual._basis_up_to(span) * Basis.from_scale(Vector3(1.0, span.length(), 1.0)), start + span * 0.5)


func _add(object: SimObject) -> void:
	var item := object as GraspableObject
	if item == null or _nodes.has(item):
		return
	var root := Node3D.new()
	root.name = item.display_name
	if item is RepairClamp:
		_build_clamp(root, item as RepairClamp)
		add_child(root)
		_nodes[item] = root
		return
	if item is RetrofitAnode:
		var cable := MeshInstance3D.new()
		var cable_mesh := CylinderMesh.new()
		cable_mesh.top_radius = 0.008
		cable_mesh.bottom_radius = 0.008
		cable_mesh.height = 1.0
		cable_mesh.radial_segments = 6
		cable.mesh = cable_mesh
		var cable_material := StandardMaterial3D.new()
		cable_material.albedo_color = Color(0.9, 0.75, 0.1)
		cable.material_override = cable_material
		cable.top_level = true
		cable.visible = false
		root.add_child(cable)
		_cables[item] = cable
	var mesh: Mesh
	if item.shape == "cylinder":
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = item.size.x * 0.5
		cylinder.bottom_radius = item.size.x * 0.5
		cylinder.height = item.size.y
		mesh = cylinder
	else:
		var box := BoxMesh.new()
		box.size = item.size
		mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = item.color
	material.roughness = 0.75
	material.metallic = 0.3 if item.color.s < 0.2 else 0.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	root.add_child(instance)
	var label := Label3D.new()
	label.text = item.display_name
	label.font_size = 32
	label.pixel_size = 0.0022
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.9, 0.95, 1.0, 0.85)
	label.outline_size = 6
	label.position = Vector3(0.0, item.size.y * 0.5 + 0.12, 0.0)
	label.visibility_range_end = 8.0
	root.add_child(label)
	add_child(root)
	_nodes[item] = root


func _remove(object: SimObject) -> void:
	if _nodes.has(object):
		_nodes[object].queue_free()
		_nodes.erase(object)
	_clamp_halves.erase(object)
	_cables.erase(object)


## Two half-shells hinged along the crown (local +X axis = clamp axis), with
## bolting flanges along the split line and a lifting handle on top.
func _build_clamp(root: Node3D, clamp: RepairClamp) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = clamp.color
	material.roughness = 0.6
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var halves: Array = []
	for side in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(0.0, clamp.outer_radius, 0.0)
		root.add_child(hinge)
		var shell := MeshInstance3D.new()
		shell.mesh = _half_shell(clamp.inner_radius, clamp.outer_radius, RepairClamp.CLAMP_LENGTH, side)
		shell.material_override = material
		shell.position = Vector3(0.0, -clamp.outer_radius, 0.0)
		hinge.add_child(shell)
		var flange := MeshInstance3D.new()
		var flange_mesh := BoxMesh.new()
		flange_mesh.size = Vector3(RepairClamp.CLAMP_LENGTH, 0.012, 0.045)
		flange.mesh = flange_mesh
		flange.material_override = material
		flange.position = Vector3(0.0, -clamp.outer_radius * 2.0 + 0.006, side * 0.03)
		hinge.add_child(flange)
		halves.append(hinge)
	var handle := MeshInstance3D.new()
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.12, RepairClamp.HANDLE_HEIGHT, 0.03)
	handle.mesh = handle_mesh
	var handle_material := StandardMaterial3D.new()
	handle_material.albedo_color = Color(0.2, 0.2, 0.22)
	handle.material_override = handle_material
	handle.position = Vector3(0.0, clamp.outer_radius + RepairClamp.HANDLE_HEIGHT * 0.5, 0.0)
	root.add_child(handle)
	_clamp_halves[clamp] = halves
	var label := Label3D.new()
	label.text = clamp.display_name
	label.pixel_size = 0.0022
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.9, 0.95, 1.0, 0.85)
	label.outline_size = 6
	label.position = Vector3(0.0, clamp.outer_radius + 0.2, 0.0)
	label.visibility_range_end = 8.0
	root.add_child(label)


## Half of a tube along X: from the crown (top) round to the bottom on one side.
static func _half_shell(inner: float, outer: float, length: float, side: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 16
	for radius in [outer, inner]:
		for k in segments:
			var a0 := PI * k / segments
			var a1 := PI * (k + 1) / segments
			var p0 := Vector3(0.0, radius * cos(a0), side * radius * sin(a0))
			var p1 := Vector3(0.0, radius * cos(a1), side * radius * sin(a1))
			var x0 := Vector3(-length * 0.5, 0.0, 0.0)
			var x1 := Vector3(length * 0.5, 0.0, 0.0)
			for v in [p0 + x0, p1 + x0, p1 + x1, p0 + x0, p1 + x1, p0 + x1]:
				st.set_normal((v - Vector3(v.x, 0.0, 0.0)).normalized())
				st.add_vertex(v)
	return st.commit()
