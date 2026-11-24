## Main (pilot) camera settings. Images are rendered by the engine through
## the onboard Camera3D; this object holds the optical settings the
## renderer applies:
##   fov   - vertical field of view
##   gain  - low-light gain: multiplies exposure and adds image noise
##           (noise strength = NOISE_PER_GAIN x (gain - 1))
## Turbidity and lighting act on the image through the environment fog and
## lights. Lens distortion, motion blur, rolling shutter and colour response
## are not modelled; the noise is a visual approximation, not a sensor model.
class_name CameraSensor
extends Sensor

const NOISE_PER_GAIN := 0.035
const PARAMETERS := {
	"fov": {"label": "Field of view (vertical)", "unit": "°", "min": 40.0, "max": 110.0, "default": 70.0, "step": 1.0,
		"description": "Vertical field of view of the pilot camera."},
	"gain": {"label": "Low-light gain", "unit": "×", "min": 1.0, "max": 8.0, "default": 1.0, "step": 0.1,
		"description": "Brightens the image in dark water at the cost of visible noise."},
}


func _init() -> void:
	sensor_name = "Camera"
	sensor_type = "camera"
	description = "Pilot camera behind the front dome (onboard view)."


func _own_parameters() -> Dictionary:
	return PARAMETERS


func _uses_timing() -> bool:
	return false


## Image noise strength 0..~0.25 implied by the gain.
func noise_amount() -> float:
	return NOISE_PER_GAIN * (get_param("gain") - 1.0) if enabled else 0.0
