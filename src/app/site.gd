## Builds the test site's content: the pipeline, the loose items the
## manipulator can pick up, and the repair materials staged near the pipeline
## (a repair clamp near the crack, a retrofit anode near the under-protected
## middle section). Used by main.gd and by tests that need the site.
class_name Site
extends RefCounted

## [name, shape, size (m), mass (kg), density (kg/m³), colour, east, north]
const ITEMS := [
	["Debris block", "box", Vector3(0.10, 0.12, 0.22), 6.0, 2400.0, Color(0.42, 0.40, 0.36), 4.0, -4.6],
	["Survey marker", "cylinder", Vector3(0.08, 0.40, 0.08), 2.5, 3000.0, Color(0.95, 0.55, 0.10), 4.8, -4.4],
]
## Repair materials: east, north.
const CLAMP_EAST := -10.5
const CLAMP_NORTH := 4.4
const ANODE_EAST := 1.0
const ANODE_NORTH := 2.5


## Adds the pipeline to the world and the items to the object registry.
static func populate(engine: SimulationEngine) -> Dictionary:
	var pipeline := Pipeline.new(engine.world.seabed_reference_y())
	engine.world.add_structure(pipeline)
	var items: Array[GraspableObject] = []
	for spec in ITEMS:
		var size: Vector3 = spec[2]
		var position := engine.world.place_on_seabed(spec[6], spec[7], size.y * 0.5)
		var item := GraspableObject.new(spec[0], spec[1], size, spec[3], spec[4], spec[5], position)
		engine.objects.register(item)
		items.append(item)
	var clamp := RepairClamp.new(pipeline, pipeline.radius(), Vector3.ZERO)
	clamp.position = engine.world.place_on_seabed(CLAMP_EAST, CLAMP_NORTH, clamp.outer_radius)
	engine.objects.register(clamp)
	items.append(clamp)
	var anode := RetrofitAnode.new(pipeline, Vector3.ZERO)
	anode.position = engine.world.place_on_seabed(ANODE_EAST, ANODE_NORTH, anode.size.y * 0.5)
	engine.objects.register(anode)
	items.append(anode)
	return {"pipeline": pipeline, "items": items, "clamp": clamp, "anode": anode}
