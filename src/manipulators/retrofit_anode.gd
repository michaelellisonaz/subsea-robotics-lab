## Retrofit sacrificial anode (Al-Zn-In) on a small sled, with a pre-attached
## 2 m cable ending in a self-closing clamp connector.
##
## When the anode is set down and comes to rest on the seabed (or a support)
## within CABLE_LENGTH horizontally of the pipeline centreline, the connector
## is taken as attached and the anode joins the pipeline's cathodic
## protection (Pipeline.set_retrofit_anode). Picking it up again, or it being
## moved out of cable reach, disconnects it.
##
## Simplifications: the cable and connector are not simulated physically (the
## connection is a geometric rule); anode output does not decay with time.
class_name RetrofitAnode
extends GraspableObject

const CABLE_LENGTH := 2.0  # m
const REST_SPEED := 0.05  # m/s

var pipeline: Pipeline
var connected: bool = false


func _init(p_pipeline: Pipeline = null, p_position: Vector3 = Vector3.ZERO) -> void:
	super("Retrofit anode", "box", Vector3(0.10, 0.10, 0.55), 15.0, 2700.0, Color(0.60, 0.63, 0.66), p_position)
	pipeline = p_pipeline


## Horizontal distance from the pipeline centreline, m (INF beyond its ends).
func distance_to_pipeline() -> float:
	if pipeline == null or position.x < Pipeline.START_EAST or position.x > Pipeline.END_EAST:
		return INF
	return absf(position.z - pipeline.axis_z())


func post_step(_context: StepContext) -> void:
	if pipeline == null:
		return
	var should_connect := held_by == null and in_seabed_contact and velocity.length() < REST_SPEED \
		and distance_to_pipeline() <= CABLE_LENGTH
	var stays_connected := connected and held_by == null and distance_to_pipeline() <= CABLE_LENGTH
	if should_connect or stays_connected:
		connected = true
		pipeline.set_retrofit_anode(self, position)
	elif connected:
		connected = false
		pipeline.set_retrofit_anode(self, null)


func reset_state() -> void:
	super()
	connected = false


func get_type_name() -> String:
	return "RetrofitAnode"
