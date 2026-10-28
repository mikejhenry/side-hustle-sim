class_name Roads
extends RefCounted
## Roads that aren't part of the straight street grid. Each link joins two grid
## intersections along a curved center line, so the GPS can route over it and AI traffic
## can drive it. The town builds their pavement and the buildings along them.
##
## Churchmans Loop: leaves the east end of Concord Pike, crosses the beltway, sweeps around
## the Route 40 strip in a long curve and comes back in on Pennsylvania Ave.

const STEP := 4.0   # meters between center line points


## [{name, from (Vector2i), to (Vector2i), pts (PackedVector3Array, from -> to)}]
static func links(B: float, N: int) -> Array:
	return [{"name": "Churchmans Loop", "from": Vector2i(N, 1), "to": Vector2i(N, 3),
		"pts": _loop(Vector3(N * B, 0, B), Vector3(N * B, 0, 3 * B))}]


## East from `a`, around a half ellipse, and back west into `b`.
static func _loop(a: Vector3, b: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var x0 := a.x + 95.0                    # where the curve starts (past the beltway)
	var cz := (a.z + b.z) / 2.0
	var rz := (b.z - a.z) / 2.0
	var rx := 150.0
	var x := a.x
	while x < x0:
		pts.append(Vector3(x, 0, a.z))
		x += STEP
	# Half ellipse, sampled by angle but spaced roughly evenly.
	var steps := 90
	for i in steps + 1:
		var t := -PI / 2.0 + PI * float(i) / steps
		# A gentle S in the middle so it isn't a perfect arc.
		var wob := sin(t * 3.0) * 10.0
		pts.append(Vector3(x0 + (rx + wob) * cos(t), 0, cz + rz * sin(t)))
	x = x0 - STEP
	while x > b.x:
		pts.append(Vector3(x, 0, b.z))
		x -= STEP
	pts.append(b)
	return pts


static func length(pts: PackedVector3Array) -> float:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	return total


## Point and direction at distance `s` along the polyline: [pos, dir].
static func sample(pts: PackedVector3Array, s: float) -> Array:
	var acc := 0.0
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if acc + seg >= s or i == pts.size() - 2:
			var t := clampf((s - acc) / maxf(seg, 0.001), 0.0, 1.0)
			return [pts[i].lerp(pts[i + 1], t), (pts[i + 1] - pts[i]).normalized()]
		acc += seg
	return [pts[0], Vector3.FORWARD]


## The part of the polyline between distances s0 and s1 (s0 < s1).
static func cut(pts: PackedVector3Array, s0: float, s1: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.append(sample(pts, s0)[0])
	var acc := 0.0
	for i in pts.size() - 1:
		acc += pts[i].distance_to(pts[i + 1])
		if acc > s0 + 0.01 and acc < s1 - 0.01:
			out.append(pts[i + 1])
	out.append(sample(pts, s1)[0])
	return out


## The polyline shifted sideways: + is to the right of the direction of travel.
static func offset(pts: PackedVector3Array, d: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var dir := (b - a).normalized()
		out.append(pts[i] + Vector3(-dir.z, 0, dir.x) * d)
	return out


static func reversed(pts: PackedVector3Array) -> PackedVector3Array:
	var out := pts.duplicate()
	out.reverse()
	return out
