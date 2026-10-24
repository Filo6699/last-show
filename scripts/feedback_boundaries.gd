extends "res://scripts/scene_parts.gd"
## Close the unused storage yard behind the dressing tent and clinic route.
## The diagonal dressing passage and the x=-20 service corridor stay open.
func setup(owner_game: Node3D) -> void:
	game = owner_game
	name = "ClosedStorageYard"
	# This twenty-metre reference tree sits beyond the playable canvas and used
	# to protrude above the closed yard, making the upper tent look broken.
	for source in game.model.find_children("*", "MeshInstance3D", true, false):
		if String(source.name) == "DeadTree2": source.hide()
	for body in game.model.get_node("GeometryCollisions").get_children():
		if String(body.get_meta("source_mesh", "")) == "DeadTree2": body.collision_layer = 0
	fence(Vector3(-41.6, 0, 47.35), Vector3(-23.6, 0, 47.35))
	fence(Vector3(-23.6, 0, 47.35), Vector3(-23.6, 0, 54.0))
	plaque("СЛУЖЕБНЫЙ СКЛАД\nПРОХОД ЗАКРЫТ", Vector3(-31.5, 1.65, 47.18), 2.6, .65, PI)
	batch()

func fence(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var center := (a + b) * .5
	var yaw := atan2(-(b.z - a.z), b.x - a.x)
	# One continuous solid panel: no gaps between slats or invisible blockers.
	var backing := box(center + Vector3(0, 1.5, 0), Vector3(length, 3.0, .16), "4a392c", true, 0.0, "ClosedStorageFence", "wood")
	backing.rotation.y = yaw
	var count := maxi(1, ceili(length / .65))
	for i in count + 1:
		var p := a.lerp(b, float(i) / count)
		var batten := box(p + Vector3(0, 1.5, 0), Vector3(.075, 3.05, .22), "70543b", false, 0.0, "StorageBatten", "wood")
		batten.rotation.y = yaw
	for height in [.3, 2.7]:
		var rail := box(center + Vector3(0, height, 0), Vector3(length, .12, .23), "7b5b3c", false, 0.0, "StorageRail", "wood")
		rail.rotation.y = yaw
