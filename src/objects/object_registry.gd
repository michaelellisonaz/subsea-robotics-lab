## Object management: the single list of everything that exists in the simulation.
##
## Objects are plain simulation data (SimObject / SimBody). The registry
## assigns stable integer ids, drives the per-step hooks in registration
## order, and restores each object's initial state on reset. Rendering code
## may listen to the signals to create or remove visuals.
class_name ObjectRegistry
extends RefCounted

signal object_registered(object: SimObject)
signal object_unregistered(object: SimObject)

var _objects: Array[SimObject] = []
var _bodies: Array[SimBody] = []
var _by_id: Dictionary = {}
var _next_id: int = 1


## Adds an object, records its current state as its reset state and returns
## its id. Registering an already-registered object returns its existing id.
func register(object: SimObject) -> int:
	if object.id > 0 and _by_id.get(object.id) == object:
		return object.id
	object.id = _next_id
	_next_id += 1
	object.capture_initial_state()
	_objects.append(object)
	_by_id[object.id] = object
	if object is SimBody:
		_bodies.append(object)
	object_registered.emit(object)
	return object.id


func unregister(object: SimObject) -> bool:
	if _by_id.get(object.id) != object:
		return false
	_by_id.erase(object.id)
	_objects.erase(object)
	if object is SimBody:
		_bodies.erase(object)
	object_unregistered.emit(object)
	object.id = -1
	return true


func get_object(object_id: int) -> SimObject:
	return _by_id.get(object_id)


func find_by_name(display_name: String) -> SimObject:
	for object in _objects:
		if object.display_name == display_name:
			return object
	return null


## All registered objects in registration order (do not modify the array).
func get_all() -> Array[SimObject]:
	return _objects


## Registered objects that have dynamics (do not modify the array).
func get_bodies() -> Array[SimBody]:
	return _bodies


func count() -> int:
	return _objects.size()


func clear() -> void:
	for object in _objects.duplicate():
		unregister(object)


func reset_all() -> void:
	for object in _objects:
		object.reset_state()


## Moves every object (and its reset pose) by an offset.
func shift_all(offset: Vector3) -> void:
	for object in _objects:
		object.shift(offset)


func pre_step(context: StepContext) -> void:
	for object in _objects:
		object.store_previous_pose()
		object.pre_step(context)


func post_step(context: StepContext) -> void:
	for object in _objects:
		object.post_step(context)
