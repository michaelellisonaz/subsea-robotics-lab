## Inspection findings from the defect detector, merged into features along
## the pipeline, plus their evaluation against the pipeline's ground truth.
##
## Each detection (type, east, clock) joins an existing feature of the same
## type within MERGE_DISTANCE along the pipe and MERGE_CLOCK around it, or
## starts a new one. A feature counts as confirmed after MIN_HITS detections
## (single-frame noise is ignored).
class_name InspectionLog
extends RefCounted

const MERGE_DISTANCE := 0.4  # m along the pipe
const MERGE_CLOCK := 60.0  # degrees
const MIN_HITS := 3

## Features: {"type", "east_from", "east_to", "east", "clock", "hits", "first_time"}.
var features: Array[Dictionary] = []
var frames_analysed: int = 0
var detections: int = 0
## Crack-like lines ignored because they are edges of known fittings.
var known_fitting_hits: int = 0


func reset() -> void:
	features.clear()
	frames_analysed = 0
	detections = 0
	known_fitting_hits = 0


func add(type: String, east: float, clock: float, time: float) -> void:
	detections += 1
	for f in features:
		if f["type"] != type:
			continue
		if east >= f["east_from"] - MERGE_DISTANCE and east <= f["east_to"] + MERGE_DISTANCE \
				and absf(wrapf(clock - f["clock"], -180.0, 180.0)) <= MERGE_CLOCK:
			f["east_from"] = minf(f["east_from"], east)
			f["east_to"] = maxf(f["east_to"], east)
			f["east"] = (f["east"] * f["hits"] + east) / (f["hits"] + 1)
			f["clock"] = (f["clock"] * f["hits"] + clock) / (f["hits"] + 1)
			f["hits"] += 1
			return
	features.append({"type": type, "east_from": east, "east_to": east, "east": east, "clock": clock, "hits": 1, "first_time": time})


func confirmed(type: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for f in features:
		if f["hits"] >= MIN_HITS and (type == "" or f["type"] == type):
			result.append(f)
	return result


## Scores the confirmed features against the pipeline's true defects:
## {"corrosion_found", "corrosion_coverage" (share of the true extent
## inside detected extents), "crack_found", "crack_error" (m),
## "false_positives", "text"}.
func evaluate(pipeline: Pipeline) -> Dictionary:
	var corrosion := pipeline.defect("corrosion")
	var crack := pipeline.defect("crack")
	var result := {"corrosion_found": false, "corrosion_coverage": 0.0, "crack_found": false, "crack_error": INF, "false_positives": 0}
	var covered := 0.0
	for f in confirmed("corrosion"):
		var lo := maxf(f["east_from"], corrosion["east_from"])
		var hi := minf(f["east_to"], corrosion["east_to"])
		if hi >= lo and f["east_to"] >= corrosion["east_from"] - 0.5 and f["east_from"] <= corrosion["east_to"] + 0.5:
			result["corrosion_found"] = true
			covered += hi - lo
		else:
			result["false_positives"] += 1
	result["corrosion_coverage"] = clampf(covered / (corrosion["east_to"] - corrosion["east_from"]), 0.0, 1.0)
	for f in confirmed("crack"):
		var error := absf(f["east"] - crack["east"])
		if error <= 0.5:
			result["crack_found"] = true
			result["crack_error"] = minf(result["crack_error"], error)
		else:
			result["false_positives"] += 1
	result["text"] = "Corrosion %s (%.0f %% of its length)  ·  crack %s  ·  %d false positive%s" % [
		"found" if result["corrosion_found"] else "not found", result["corrosion_coverage"] * 100.0,
		("found, %.2f m off" % result["crack_error"]) if result["crack_found"] else "not found",
		result["false_positives"], "" if result["false_positives"] == 1 else "s"]
	return result
