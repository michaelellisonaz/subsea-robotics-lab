## 3D model of the manipulator, placed in the vehicle body frame (child of
## RovVisual, whose origin is the CG). Every frame it poses the joint
## housings, links and gripper jaws from the simulated joint angles. It can
## also show the Cartesian target and the sampled reach envelope.
class_name ManipulatorVisual
extends Node3D

const LINK_RADIUS := 0.032
const HOUSING_RADIUS := 0.048
const GRIPPER_LENGTH := 0.16

var manipulator: Manipulator
var target_visible: bool = false
var envelope_visible: bool = false

var _housings: Array[MeshInstance3D] = []
var _links: Array[MeshInstance3D] = []
var _palm: MeshInstance3D
var _jaws: Array[MeshInstance3D] = []
var _target: MeshInstance3D
var _tool_root: Node3D
var _shown_tool: WorkTool = null
var _brush_disc: Node3D
var _brush_angle: float = 0.0
var _skid: Node3D
var _envelope: MeshInstance3D
var _envelope_mesh := ImmediateMesh.new()


func build(p_manipulator: Manipulator) -> void:
	manipulator = p_manipulator
	for child in get_children():
		child.free()
	_housings.clear()
	_links.clear()
	_jaws.clear()
	if not manipulator.is_installed():
		return
	var housing_material := _material(Color(0.92, 0.55, 0.10), 0.3, 0.5)
	var link_material := _material(Color(0.16, 0.17, 0.18), 0.5, 0.45)
	var steel := _material(Color(0.62, 0.64, 0.66), 0.85, 0.3)
	for joint in manipulator.joints:
		var housing := _mesh(_cylinder_mesh(HOUSING_RADIUS, 0.11), housing_material)
		_housings.append(housing)
	for i in manipulator.joints.size():
		_links.append(_mesh(_cylinder_mesh(LINK_RADIUS, 1.0), link_material))
	var palm_mesh := BoxMesh.new()
	palm_mesh.size = Vector3(0.10, 0.05, 0.05)
	_palm = _mesh(palm_mesh, link_material)
	for k in 2:
		var jaw_mesh := BoxMesh.new()
		jaw_mesh.size = Vector3(0.016, 0.035, GRIPPER_LENGTH - 0.03)
		_jaws.append(_mesh(jaw_mesh, steel))
	var target_mesh := SphereMesh.new()
	target_mesh.radius = 0.02
	target_mesh.height = 0.04
	var target_material := _material(Color(0.3, 0.95, 1.0), 0.0, 0.5)
	target_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target_material.no_depth_test = true
	_target = _mesh(target_mesh, target_material)
	_tool_root = Node3D.new()
	add_child(_tool_root)
	_skid = Node3D.new()
	_skid.position = manipulator.skid_position
	add_child(_skid)
	_shown_tool = null
	_rebuild_tool()
	_envelope = MeshInstance3D.new()
	_envelope.mesh = _envelope_mesh
	var envelope_material := StandardMaterial3D.new()
	envelope_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	envelope_material.albedo_color = Color(0.3, 0.95, 1.0, 0.35)
	envelope_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_envelope.material_override = envelope_material
	add_child(_envelope)
	set_envelope_visible(envelope_visible)
	update_pose()


func set_envelope_visible(value: bool) -> void:
	envelope_visible = value
	if _envelope == null:
		return
	_envelope_mesh.clear_surfaces()
	_envelope.visible = value
	if not value or manipulator == null or not manipulator.is_installed():
		return
	var points := manipulator.sample_envelope(9)
	_envelope_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for p in points:
		for axis in [Vector3(0.01, 0, 0), Vector3(0, 0.01, 0), Vector3(0, 0, 0.01)]:
			_envelope_mesh.surface_add_vertex(p - axis)
			_envelope_mesh.surface_add_vertex(p + axis)
	_envelope_mesh.surface_end()


func update_pose() -> void:
	if manipulator == null or not manipulator.is_installed():
		return
	var f := manipulator.frames(manipulator.current_angles())
	var tip := f[-1]
	# Fingertips: with a tool mounted the tool point is further out.
	var tool := Transform3D(tip.basis, tip.origin + tip.basis.z * manipulator.tool_extension())
	var tool_base := tool.origin + tool.basis.z * GRIPPER_LENGTH
	for i in manipulator.joints.size():
		var axis := (f[i].basis * manipulator.joints[i].axis).normalized()
		_housings[i].transform = Transform3D(_basis_up_to(axis), f[i].origin)
		var start := f[i].origin
		var finish := f[i + 1].origin if i + 1 < manipulator.joints.size() else tool_base
		var span := finish - start
		_links[i].visible = span.length() > 0.005
		if _links[i].visible:
			_links[i].transform = Transform3D(_basis_up_to(span) * Basis.from_scale(Vector3(1.0, span.length(), 1.0)), start + span * 0.5)
	_palm.transform = Transform3D(tool.basis, tool_base)
	var half := manipulator.gripper_opening * 0.5 + 0.008
	for k in 2:
		var side := -1.0 if k == 0 else 1.0
		_jaws[k].transform = Transform3D(tool.basis, tool.origin + tool.basis.z * (GRIPPER_LENGTH - 0.03) * 0.5 + tool.basis.x * side * half)
	_target.visible = target_visible
	_target.position = manipulator.tool_target_position
	if manipulator.tool != _shown_tool:
		_rebuild_tool()
	if manipulator.tool != null:
		_tool_root.transform = tool
		if _brush_disc != null and manipulator.tool.active:
			_brush_angle += get_process_delta_time() * 20.0
			_brush_disc.basis = Basis(Vector3.FORWARD, _brush_angle)


## Builds the mounted tool (at the fingertips, pointing along the tool axis)
## and the tools resting in the skid.
func _rebuild_tool() -> void:
	_shown_tool = manipulator.tool
	_brush_disc = null
	for child in _tool_root.get_children():
		child.free()
	for child in _skid.get_children():
		child.free()
	if manipulator.tool != null:
		_tool_root.add_child(_tool_model(manipulator.tool))
	var x := 0.0
	for t in manipulator.tools:
		if t == manipulator.tool:
			continue
		var stored := _tool_model(t, false)
		# Stored pointing forward, side by side.
		stored.position = Vector3(x, 0.0, t.length * 0.5)
		_skid.add_child(stored)
		x -= 0.09


## A tool model whose origin is at the gripper fingertips and whose tip is
## `length` along -Z.
func _tool_model(t: WorkTool, live: bool = true) -> Node3D:
	var root := Node3D.new()
	var body_material := _material(Color(0.85, 0.85, 0.82), 0.3, 0.5)
	var handle := _cylinder_node(0.02, 0.06, Vector3(0, 0, 0.03), _material(Color(0.15, 0.15, 0.15), 0.2, 0.6))
	root.add_child(handle)
	if t is CleaningBrush:
		root.add_child(_cylinder_node(0.03, t.length - 0.04, Vector3(0, 0, -(t.length - 0.04) * 0.5), body_material))
		var disc := Node3D.new()
		disc.position = Vector3(0, 0, -t.length + 0.02)
		disc.add_child(_cylinder_node(CleaningBrush.FOOTPRINT_RADIUS, 0.04, Vector3.ZERO, _material(Color(0.55, 0.45, 0.3), 0.0, 0.95)))
		for k in 6:
			var bar := MeshInstance3D.new()
			var bar_mesh := BoxMesh.new()
			bar_mesh.size = Vector3(0.008, 0.11, 0.045)
			bar.mesh = bar_mesh
			bar.material_override = _material(Color(0.25, 0.2, 0.15), 0.0, 1.0)
			bar.basis = Basis(Vector3.FORWARD, PI * k / 6.0)
			disc.add_child(bar)
		root.add_child(disc)
		if live:
			_brush_disc = disc
	elif t is CpProbe:
		root.add_child(_cylinder_node(0.03, 0.12, Vector3(0, 0, -0.06), _material(Color(0.95, 0.75, 0.1), 0.1, 0.5)))
		root.add_child(_cylinder_node(0.008, t.length - 0.12, Vector3(0, 0, -0.12 - (t.length - 0.12) * 0.5), _material(Color(0.7, 0.7, 0.72), 0.8, 0.3)))
		var tip := MeshInstance3D.new()
		var tip_mesh := SphereMesh.new()
		tip_mesh.radius = t.tip_radius
		tip_mesh.height = t.tip_radius * 2.0
		tip.mesh = tip_mesh
		tip.material_override = _material(Color(0.8, 0.5, 0.2), 0.9, 0.3)
		tip.position = Vector3(0, 0, -t.length + t.tip_radius)
		root.add_child(tip)
	return root


## Cylinder whose axis is along Z.
func _cylinder_node(radius: float, height: float, center: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = _cylinder_mesh(radius, height)
	instance.material_override = material
	instance.basis = Basis(Vector3.RIGHT, PI * 0.5)
	instance.position = center
	return instance


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)
	return instance


func _cylinder_mesh(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 1
	return mesh


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


static func _basis_up_to(direction: Vector3) -> Basis:
	var d := direction.normalized()
	if d.dot(Vector3.UP) < -0.9999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, d))
