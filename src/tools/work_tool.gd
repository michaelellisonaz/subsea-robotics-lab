## Base class for a tool the manipulator can pick up from the vehicle's tool
## skid and hold in its gripper (a T-handle tool interface).
##
## A mounted tool extends the arm's tool point by `length` (inverse
## kinematics, reach and the envelope adapt), adds its weight in water at the
## wrist (vehicle trim and shoulder load), and may touch surfaces with its tip.
##
## Tip contact: the tool sits in a compliant mount (spring `compliance`, travel
## `travel`). Pressing the tip into a surface by d gives a contact force
## F = compliance · min(d, travel) along the surface normal; beyond the travel
## the tool bottoms out and the arm is blocked (see Manipulator). The contact
## force is passed back to the vehicle as a reaction load. The Manipulator
## evaluates the contact each step and fills `contact` / `contact_force`
## before calling step().
class_name WorkTool
extends RefCounted

var tool_id: String = "tool"
var display_name: String = "Tool"
var description: String = ""
## Mass in air, kg, and material density (for the weight in water), kg/m³.
var mass: float = 3.0
var density: float = 3000.0
## Extension of the tool point beyond the gripper fingertips, m.
var length: float = 0.2
## Radius of the tool tip used for surface contact, m.
var tip_radius: float = 0.02
## Compliant mount: spring rate (N/m) and travel (m) before bottoming out.
var compliance: float = 2000.0
var travel: float = 0.05
## Working range of the contact force, N (0 = no requirement).
var min_force: float = 0.0
var max_force: float = 0.0

## Powered / running (brush spinning ...).
var active: bool = false
## Contact force on the tip in the last step, N (0 = no contact).
var contact_force: float = 0.0
## Last tip contact: {"point": world point on the surface, "normal",
## "structure": Structure or null (seabed), "primitive", "surface": name}; {} = none.
var contact: Dictionary = {}
## Torque the tool applies to the vehicle through the arm, world axes, N·m.
var reaction_torque: Vector3 = Vector3.ZERO
## Human-readable state for the UI.
var status: String = "Off"


## Weight in water, N (positive = sinks).
func wet_weight(environment: EnvironmentConfig) -> float:
	return (mass - environment.water_density * mass / density) * environment.gravity


## Label of the tool's G-key action.
func action_label() -> String:
	return "On / off"


## G key: performs the tool's action and returns a message for the operator.
func action(_now: float) -> String:
	active = not active
	return "%s %s" % [display_name, "on" if active else "off"]


## Called by the Manipulator every step after the tip contact was evaluated.
func step(_context: StepContext, _tool_world: Transform3D, _dt: float) -> void:
	reaction_torque = Vector3.ZERO


## Called when the tool goes back into the skid: switched off, no contact.
## Logged data is kept.
func on_unmounted() -> void:
	active = false
	contact_force = 0.0
	contact = {}
	reaction_torque = Vector3.ZERO
	status = "In the skid"


## Full reset (simulation reset): also clears any logged data.
func reset() -> void:
	active = false
	contact_force = 0.0
	contact = {}
	reaction_torque = Vector3.ZERO
	status = "Off"


## Describes the touched surface: "seabed", a pipeline surface kind, or the
## structure's name.
static func surface_name(hit: Dictionary) -> String:
	if hit.is_empty():
		return ""
	var structure: Structure = hit.get("structure")
	if structure == null:
		return "seabed"
	if structure is Pipeline:
		return (structure as Pipeline).surface_kind(hit["point"], hit.get("primitive"))
	return structure.structure_name
