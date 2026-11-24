## Rotary wire / nylon cleaning brush (hydraulic or electric drive) for
## removing marine growth and corrosion product before inspection.
##
## Cleaning model: while spinning and pressed onto the pipeline with a contact
## force F inside the working range, deposit is removed from every surface
## cell within the brush footprint at
##   rate = REMOVAL_RATE · F / REFERENCE_FORCE   (mm/s).
## Below the minimum force the bristles do not bite (no cleaning). Friction
## between the spinning brush and the surface gives a reaction torque about
## the tool axis, T = FRICTION · F · EFFECTIVE_RADIUS, felt by the vehicle.
##
## Simplifications: removal is uniform over the footprint and independent of
## deposit type; brush wear, stall and the hydraulic supply are not modelled;
## the footprint is a sphere around the contact point.
class_name CleaningBrush
extends WorkTool

const REMOVAL_RATE := 1.2  # mm/s at the reference force
const REFERENCE_FORCE := 100.0  # N
const FOOTPRINT_RADIUS := 0.06  # m
const FRICTION := 0.35
const EFFECTIVE_RADIUS := 0.04  # m

## Accumulated time spent cleaning the pipeline, s.
var cleaning_time: float = 0.0


func _init() -> void:
	tool_id = "brush"
	display_name = "Cleaning brush"
	description = "Rotary brush, Ø 0.12 m. Press onto the pipe with 40-150 N while spinning to remove marine growth and corrosion product."
	mass = 6.0
	density = 2500.0
	length = 0.22
	tip_radius = FOOTPRINT_RADIUS
	compliance = 2500.0
	travel = 0.06
	min_force = 40.0
	max_force = 150.0


func action_label() -> String:
	return "Spin on / off"


func step(_context: StepContext, tool_world: Transform3D, dt: float) -> void:
	reaction_torque = Vector3.ZERO
	if not active:
		status = "Off" if contact.is_empty() else "Off, touching %s (%.0f N)" % [surface_name(contact), contact_force]
		return
	if contact.is_empty():
		status = "Spinning, no contact"
		return
	var axis := -tool_world.basis.z
	reaction_torque = -axis * FRICTION * contact_force * EFFECTIVE_RADIUS
	var surface := surface_name(contact)
	if contact_force < min_force:
		status = "Contact force too low: %.0f N (needs %.0f N)" % [contact_force, min_force]
		return
	var pipeline := contact.get("structure") as Pipeline
	if pipeline == null or contact["primitive"].tag != "pipe":
		status = "Brushing %s (%.0f N): nothing to clean" % [surface, contact_force]
		return
	var removal := REMOVAL_RATE * contact_force / REFERENCE_FORCE * dt
	pipeline.clean(contact["point"], FOOTPRINT_RADIUS, removal)
	cleaning_time += dt
	status = "Cleaning %s, %.0f N" % [surface, contact_force]


func reset() -> void:
	super()
	cleaning_time = 0.0
