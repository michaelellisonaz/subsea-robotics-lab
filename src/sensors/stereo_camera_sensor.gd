## Stereo camera pair. Two cameras a `baseline` apart look forward; the
## renderer draws both views (IMAGE_WIDTH x IMAGE_HEIGHT pixels each) into
## off-screen viewports shown in the dashboard. Stage 3 provides the image
## pair and the stereo geometry; depth estimation from disparity belongs to
## the computer-vision stage.
##
## Geometry helpers (pinhole model):
##   focal length f [px] = (width / 2) / tan(hfov / 2)
##   depth from disparity  Z = f · B / d
##   depth resolution for one pixel of disparity  ΔZ ≈ Z² / (f · B)
class_name StereoCameraSensor
extends Sensor

const IMAGE_WIDTH := 320
const IMAGE_HEIGHT := 240
const PARAMETERS := {
	"baseline": {"label": "Baseline", "unit": "m", "min": 0.04, "max": 0.5, "default": 0.12, "step": 0.01,
		"description": "Distance between the two camera centres."},
	"fov": {"label": "Field of view (vertical)", "unit": "°", "min": 30.0, "max": 100.0, "default": 60.0, "step": 1.0,
		"description": "Vertical field of view of each camera."},
}


func _init() -> void:
	sensor_name = "Stereo camera"
	sensor_type = "stereo_camera"
	description = "Forward stereo pair (rendered when enabled)."
	enabled = false


func _own_parameters() -> Dictionary:
	return PARAMETERS


func _uses_timing() -> bool:
	return false


func horizontal_fov_radians() -> float:
	var aspect := float(IMAGE_WIDTH) / IMAGE_HEIGHT
	return 2.0 * atan(tan(deg_to_rad(get_param("fov")) * 0.5) * aspect)


func focal_length_pixels() -> float:
	return (IMAGE_WIDTH * 0.5) / tan(horizontal_fov_radians() * 0.5)


## Depth change corresponding to one pixel of disparity at a distance, m.
func depth_resolution(distance: float) -> float:
	return distance * distance / (focal_length_pixels() * get_param("baseline"))


## Distance at which two objects produce a disparity of `disparity_px`, m.
func depth_from_disparity(disparity_px: float) -> float:
	return focal_length_pixels() * get_param("baseline") / disparity_px if disparity_px > 0.0 else INF
