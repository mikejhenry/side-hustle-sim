class_name ParkedCars
extends Node3D
## Cars parked along the curbs of the cross streets (no front doors face them, so they
## never block a delivery stop). They're solid: clip one and you'll know it. Uses the
## Quaternius car models (CC0) when they're present, and draws nothing past a couple of
## blocks away to stay cheap.

const MODELS := ["NormalCar1", "NormalCar2", "SUV", "SportsCar", "Taxi"]
const OFFSET := 5.85         # parking lane center, meters from the road center line
const SPACING := 7.0
const FILL := 0.22           # share of parking spots taken
const SCALE := 1.1
const VIS := 170.0

var town: Node = null
var main: Node = null
var cars: Array = []         # Node3D per parked car


func build() -> void:
	var have := MODELS.filter(func(m): return ResourceLoader.exists("res://assets/quaternius/%s.fbx" % m))
	if have.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var scenes := {}
	for m in have:
		scenes[m] = load("res://assets/quaternius/%s.fbx" % m)
	var N: int = town.N
	var B: float = town.B
	var avoid: Vector3 = town.car_spawn.origin
	for x in N + 1:
		for z in N:
			var a := Vector3(x * B, 0, z * B)
			# Leave room at the corners for turning and the crosswalks.
			var s := Traffic.HALF + 7.0
			while s < B - Traffic.HALF - 7.0:
				for side in [-1.0, 1.0]:
					if rng.randf() > FILL:
						continue
					# Facing the way traffic in that lane drives (+Z on the west side).
					var fwd := Vector3(0, 0, 1) if side < 0.0 else Vector3(0, 0, -1)
					var pos := a + Vector3(side * OFFSET, 0, s + rng.randf_range(-0.6, 0.6))
					if pos.distance_to(avoid) < 25.0:
						continue
					var m: String = have[rng.randi() % have.size()]
					_place(scenes[m].instantiate(), pos, fwd, rng.randf_range(-0.04, 0.04))
				s += SPACING


func _place(model: Node3D, pos: Vector3, fwd: Vector3, wobble: float) -> void:
	var body := StaticBody3D.new()
	add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP.cross(fwd).normalized(), Vector3.UP, fwd).rotated(Vector3.UP, wobble), pos)
	model.scale = Vector3.ONE * SCALE
	body.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = VIS
		(mi as MeshInstance3D).visibility_range_end_margin = 4.0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.3, 4.4)
	col.shape = box
	col.position.y = 0.75
	body.add_child(col)
	cars.append(body)
