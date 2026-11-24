## Image-based defect detector for the inspection camera (classical computer
## vision, no learned model).
##
## analyze() works on a camera image:
##   corrosion  (image downsampled to <= 160 px wide) pixels whose colour is
##              rust: hue 0-40°, saturation > 0.45, value > 0.12; grouped into
##              8-connected blobs of >= 6 pixels.
##   crack      (full resolution, <= 320 px wide) pixels much darker than
##              their 7x7 neighbourhood (value < 65 % of the local mean)
##              and than the pixels 2 rows above and below (< 80 %),
##              grouped into blobs that are thin (mean thickness <= 3 px),
##              at least 10 px long and run ACROSS the image (width >= 2 x
##              height). With the survey camera looking along the pipe, a
##              circumferential crack runs across the image while the pipe's
##              shaded edges and shadow boundaries run along it.
## project() turns a blob's centre pixel into a world ray (pinhole model with
## the camera's field of view and the ESTIMATED camera pose) and intersects it
## with the as-built pipeline geometry (operators have the pipeline survey);
## blobs that do not land on the pipe are discarded.
##
## Limitations: colour thresholds are tuned for this renderer's lighting and
## water colour; anything rust-coloured on the pipe counts as corrosion; only
## cracks running across the image (circumferential, seen along the pipe)
## are found, and other thin dark features across the pipe would be taken
## for cracks. A crack is about 1-2 px wide at survey range, so it is found
## only while it is near the camera.
class_name DefectDetector
extends RefCounted

const MAX_WIDTH := 160
const MIN_CORROSION_PIXELS := 6
const CRACK_MAX_WIDTH := 320
const DARK_RATIO := 0.65
const SIDE_RATIO := 0.8
const MIN_LOCAL_MEAN := 0.12
const WINDOW := 3  # half-size of the local-mean window (7 x 7)
const MIN_CRACK_LENGTH := 10
const MAX_CRACK_THICKNESS := 3.0


## Returns {"width", "height", "corrosion": [blob], "crack": [blob]};
## blob = {"center": Vector2 (pixels), "area": int, "box": Rect2i}.
static func analyze(source: Image) -> Dictionary:
	var image := _scaled(source, MAX_WIDTH)
	var w := image.get_width()
	var h := image.get_height()
	var rust := PackedByteArray()
	rust.resize(w * h)
	for y in h:
		for x in w:
			var c := image.get_pixel(x, y)
			var hue := c.h
			rust[y * w + x] = 1 if (hue <= 0.11 or hue >= 0.97) and c.s > 0.45 and c.v > 0.12 else 0
	var corrosion: Array[Dictionary] = []
	for blob in _components(rust, w, h):
		if blob["area"] >= MIN_CORROSION_PIXELS:
			corrosion.append(blob)
	# Cracks at (up to) full resolution; reported in the corrosion image's
	# pixel scale so both lists share one image size.
	var full := _scaled(source, CRACK_MAX_WIDTH)
	var scale := float(w) / full.get_width()
	var cracks: Array[Dictionary] = []
	for blob in _crack_blobs(full):
		blob["center"] = blob["center"] * scale
		cracks.append(blob)
	return {"width": w, "height": h, "corrosion": corrosion, "crack": cracks}


static func _scaled(source: Image, max_width: int) -> Image:
	var image := source.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGB8)
	if image.get_width() > max_width:
		image.resize(max_width, int(round(source.get_height() * float(max_width) / source.get_width())), Image.INTERPOLATE_BILINEAR)
	return image


## Thin, across-the-image lines of pixels much darker than their surroundings.
static func _crack_blobs(image: Image) -> Array[Dictionary]:
	var w := image.get_width()
	var h := image.get_height()
	var data := image.get_data()
	# Value (max channel) and its integral image for fast local means.
	var value := PackedFloat32Array()
	value.resize(w * h)
	var integral := PackedFloat64Array()
	integral.resize((w + 1) * (h + 1))
	for y in h:
		var row_sum := 0.0
		for x in w:
			var i := (y * w + x) * 3
			var v := maxf(data[i], maxf(data[i + 1], data[i + 2])) / 255.0
			value[y * w + x] = v
			row_sum += v
			integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + row_sum
	var dark := PackedByteArray()
	dark.resize(w * h)
	for y in h:
		var y0 := maxi(0, y - WINDOW)
		var y1 := mini(h, y + WINDOW + 1)
		for x in w:
			var x0 := maxi(0, x - WINDOW)
			var x1 := mini(w, x + WINDOW + 1)
			var total := integral[y1 * (w + 1) + x1] - integral[y0 * (w + 1) + x1] - integral[y1 * (w + 1) + x0] + integral[y0 * (w + 1) + x0]
			var mean := total / ((x1 - x0) * (y1 - y0))
			var v := value[y * w + x]
			# A line is darker than the pixels on BOTH sides of it (not just the
			# dark side of an edge).
			var above := value[maxi(0, y - 2) * w + x]
			var below := value[mini(h - 1, y + 2) * w + x]
			dark[y * w + x] = 1 if mean > MIN_LOCAL_MEAN and v < DARK_RATIO * mean 				and v < SIDE_RATIO * above and v < SIDE_RATIO * below else 0
	var result: Array[Dictionary] = []
	for blob in _components(dark, w, h):
		var box: Rect2i = blob["box"]
		if box.size.x >= MIN_CRACK_LENGTH and box.size.x >= 2 * box.size.y \
				and float(blob["area"]) / box.size.x <= MAX_CRACK_THICKNESS:
			result.append(blob)
	return result


## World ray from a pixel: [origin, unit direction]. `camera_pose` is the
## camera's transform (looking along its -Z), `fov` the vertical field of view.
static func pixel_ray(pixel: Vector2, width: int, height: int, fov_degrees: float, camera_pose: Transform3D) -> Array:
	var t := tan(deg_to_rad(fov_degrees) * 0.5)
	var aspect := float(width) / height
	var local := Vector3((2.0 * (pixel.x + 0.5) / width - 1.0) * t * aspect, -(2.0 * (pixel.y + 0.5) / height - 1.0) * t, -1.0)
	return [camera_pose.origin, (camera_pose.basis * local).normalized()]


## Where a pixel lands on the as-built pipe: {"point", "east", "clock"} or {}.
static func project_to_pipe(pixel: Vector2, width: int, height: int, fov_degrees: float, camera_pose: Transform3D,
		pipeline: Pipeline, max_range: float = 8.0) -> Dictionary:
	var ray := pixel_ray(pixel, width, height, fov_degrees, camera_pose)
	var pipe: StructurePrimitive = null
	for primitive in pipeline.primitives:
		if primitive.tag == "pipe":
			pipe = primitive
	if pipe == null:
		return {}
	var t := pipe.intersect_ray(ray[0], ray[1], max_range)
	if t == INF:
		return {}
	var point: Vector3 = ray[0] + ray[1] * t
	return {"point": point, "east": point.x, "clock": pipeline.clock_degrees(point)}


static func _components(mask: PackedByteArray, w: int, h: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack := PackedInt32Array()
	for start in w * h:
		if mask[start] == 0 or seen[start] == 1:
			continue
		seen[start] = 1
		stack.clear()
		stack.append(start)
		var area := 0
		var sum := Vector2.ZERO
		var lo := Vector2i(w, h)
		var hi := Vector2i(-1, -1)
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var x := i % w
			var y := i / w
			area += 1
			sum += Vector2(x, y)
			lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
			hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = x + dx
					var ny: int = y + dy
					if (dx == 0 and dy == 0) or nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var n := ny * w + nx
					if mask[n] == 1 and seen[n] == 0:
						seen[n] = 1
						stack.append(n)
		result.append({"center": sum / area, "area": area, "box": Rect2i(lo, hi - lo + Vector2i.ONE)})
	return result
