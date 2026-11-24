## Base class for anything that exists in the simulation world.
##
## A SimObject holds simulation state only (its pose in the world frame). It
## is deliberately not a Node: simulation objects stay independent of the
## scene tree and the renderer, so they can be stepped headless, unit-tested,
## and later driven by external tools. When visuals are added in later stages,
## a separate Node3D reads this state each frame.
class_name SimObject
extends RefCounted

## Unique id assigned by ObjectRegistry (-1 while unregistered).
var id: int = -1
var display_name: String = "Object"
## Position in the world frame (see WorldFrame), m.
var position: Vector3 = Vector3.ZERO
var orientation: Quaternion = Quaternion.IDENTITY

## Pose at the start of the most recent step; renderers interpolate between
## this and the current pose for smooth motion at any frame rate.
var previous_position: Vector3 = Vector3.ZERO
var previous_orientation: Quaternion = Quaternion.IDENTITY

var _initial_position: Vector3 = Vector3.ZERO
var _initial_orientation: Quaternion = Quaternion.IDENTITY


func _init(p_name: String = "Object", p_position: Vector3 = Vector3.ZERO) -> void:
	display_name = p_name
	position = p_position
	previous_position = p_position


## Records the current state as the state restored by [method reset_state].
## ObjectRegistry calls this when the object is registered.
func capture_initial_state() -> void:
	_initial_position = position
	_initial_orientation = orientation
	store_previous_pose()


func reset_state() -> void:
	position = _initial_position
	orientation = _initial_orientation
	store_previous_pose()


## Called by ObjectRegistry at the start of every step.
func store_previous_pose() -> void:
	previous_position = position
	previous_orientation = orientation


## Pose interpolated between the previous and current step (alpha 0..1).
func get_interpolated_transform(alpha: float) -> Transform3D:
	var p := previous_position.lerp(position, alpha)
	var q := previous_orientation.slerp(orientation, alpha)
	return Transform3D(Basis(q), p)


## Moves the object, its previous pose and its reset pose by an offset (used
## when the seabed moves because the water depth changed).
func shift(offset: Vector3) -> void:
	position += offset
	previous_position += offset
	_initial_position += offset


## Called at the start of every fixed step, before physics.
func pre_step(_context: StepContext) -> void:
	pass


## Called at the end of every fixed step, after physics.
func post_step(_context: StepContext) -> void:
	pass


func get_transform() -> Transform3D:
	return Transform3D(Basis(orientation), position)


func get_type_name() -> String:
	return "SimObject"
