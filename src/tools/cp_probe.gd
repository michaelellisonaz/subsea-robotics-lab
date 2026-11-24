## Cathodic-protection (CP) contact probe: measures the steel's protection
## potential against a built-in Ag/AgCl reference electrode.
##
## A reading needs metallic contact: the probe tip pressed (at least
## min_force) onto bare metal - a flange, an anode bracelet, or pipe steel
## where the coating has failed AND the deposit has been cleaned off. On
## coating, marine growth or corrosion product there is no electrical contact.
## After SETTLE_TIME of steady contact the reading is the pipeline's
## potential at the contact point plus Gaussian noise (fixed seed, so a run
## repeats). G logs the current reading with its position.
##
## Simplifications: no IR drop, reference-electrode drift or temperature
## effect; the potential comes from Pipeline.cp_potential().
class_name CpProbe
extends WorkTool

const NOISE_MV := 3.0
const SETTLE_TIME := 1.0  # s
const SAMPLE_INTERVAL := 0.5  # s
const SEED := 4242

## Current reading in mV (NAN = no valid reading).
var reading: float = NAN
## Logged readings: {"time", "east", "north", "depth", "clock", "surface",
## "potential", "truth"}.
var log: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _contact_time: float = 0.0
var _sample_timer: float = 0.0
var _truth: float = NAN


func _init() -> void:
	tool_id = "cp_probe"
	display_name = "CP probe"
	description = "Contact probe with Ag/AgCl reference. Touch bare metal (flange, anode, cleaned corroded steel) with at least 10 N; G logs the reading."
	mass = 2.5
	density = 2000.0
	length = 0.30
	tip_radius = 0.012
	compliance = 1500.0
	travel = 0.03
	min_force = 10.0
	max_force = 45.0
	_rng.seed = SEED


func action_label() -> String:
	return "Log reading"


func action(now: float) -> String:
	if is_nan(reading):
		return "No valid CP reading to log"
	var p: Vector3 = contact["point"]
	var pipeline := contact.get("structure") as Pipeline
	var entry := {
		"time": now, "east": p.x, "north": -p.z, "depth": -p.y,
		"clock": pipeline.clock_degrees(p) if pipeline != null else 0.0,
		"surface": surface_name(contact), "potential": reading, "truth": _truth,
	}
	log.append(entry)
	return "Logged %.0f mV at E %.2f" % [reading, p.x]


func step(_context: StepContext, _tool_world: Transform3D, dt: float) -> void:
	reaction_torque = Vector3.ZERO
	var pipeline := contact.get("structure") as Pipeline if not contact.is_empty() else null
	if contact.is_empty():
		_lose_contact("No contact")
		return
	var surface := surface_name(contact)
	if pipeline == null or not pipeline.is_bare_metal(contact["point"], contact.get("primitive")):
		_lose_contact("No metallic contact (touching %s)" % surface)
		return
	if contact_force < min_force:
		_lose_contact("Contact force too low: %.0f N (needs %.0f N)" % [contact_force, min_force])
		return
	_contact_time += dt
	if _contact_time < SETTLE_TIME:
		reading = NAN
		status = "Settling on %s ..." % surface
		return
	_sample_timer -= dt
	if is_nan(reading) or _sample_timer <= 0.0:
		_sample_timer = SAMPLE_INTERVAL
		_truth = pipeline.cp_potential(contact["point"])
		reading = _truth + _rng.randfn(0.0, NOISE_MV)
	status = "%.0f mV vs Ag/AgCl on %s" % [reading, surface]


func _lose_contact(message: String) -> void:
	_contact_time = 0.0
	reading = NAN
	status = message


func reset() -> void:
	super()
	_rng.seed = SEED
	log.clear()
	reading = NAN
	_contact_time = 0.0
	_sample_timer = 0.0
