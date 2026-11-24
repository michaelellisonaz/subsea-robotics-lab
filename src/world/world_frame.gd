## Coordinate conventions used throughout the project.
##
## Internal (Godot) world frame - used by all simulation and rendering code:
##   +X = East, +Y = Up, +Z = South   (right-handed, Y-up, metres)
##   Origin: on the sea surface, directly above the test-site origin.
##
## Display / user-input frame - ENU (East, North, Up) plus positive-down depth:
##   east = x,  north = -z,  up = y,  depth = -y
##
## NED (North, East, Down), the usual marine-robotics navigation frame, is
## provided for future vehicle and sensor code.
##
## Headings are compass bearings in degrees: 0 = North, 90 = East, clockwise.
class_name WorldFrame
extends RefCounted

const CARDINALS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


static func godot_to_enu(p: Vector3) -> Vector3:
	return Vector3(p.x, -p.z, p.y)


static func enu_to_godot(enu: Vector3) -> Vector3:
	return Vector3(enu.x, enu.z, -enu.y)


static func godot_to_ned(p: Vector3) -> Vector3:
	return Vector3(-p.z, p.x, -p.y)


static func ned_to_godot(ned: Vector3) -> Vector3:
	return Vector3(ned.y, -ned.z, -ned.x)


## Depth below the sea surface (positive downwards), m.
static func depth_of(p: Vector3) -> float:
	return -p.y


## Horizontal unit vector pointing toward a compass heading.
static func direction_from_heading(heading_deg: float) -> Vector3:
	var r := deg_to_rad(heading_deg)
	return Vector3(sin(r), 0.0, -cos(r))


## Compass heading (0-360 degrees) of the horizontal part of a direction vector.
static func heading_from_direction(direction: Vector3) -> float:
	if Vector2(direction.x, direction.z).length_squared() < 1e-12:
		return 0.0
	return fposmod(rad_to_deg(atan2(direction.x, -direction.z)), 360.0)


## Eight-point compass name for a heading ("N", "NE", ...).
static func cardinal(heading_deg: float) -> String:
	var index := int(round(fposmod(heading_deg, 360.0) / 45.0)) % 8
	return CARDINALS[index]


## Attitude of a body orientation in vehicle conventions, degrees:
## x = roll (+ starboard down), y = pitch (+ nose up), z = heading (compass).
static func attitude_of(q: Quaternion) -> Vector3:
	var forward := q * Vector3.FORWARD
	var right := q * Vector3.RIGHT
	var up := q * Vector3.UP
	return Vector3(
		rad_to_deg(atan2(-right.y, up.y)),
		rad_to_deg(asin(clampf(forward.y, -1.0, 1.0))),
		heading_from_direction(forward))


## Converts a body-axes vector (x starboard, y up, z aft) to vehicle terms
## (forward, starboard, up).
static func body_to_vehicle(v: Vector3) -> Vector3:
	return Vector3(-v.z, v.x, v.y)


## Formats a world position as "E .. N .. D .. m" for display.
static func format_position(p: Vector3) -> String:
	return "E %.1f   N %.1f   D %.1f m" % [p.x, -p.z, -p.y]
