@tool
extends EditorScenePostImport
## Keep collision separate from the artist's meshes and regenerate it on reimport.

func _post_import(scene: Node) -> Object:
	var collisions := Node3D.new()
	collisions.name = "GeometryCollisions"
	scene.add_child(collisions)
	collisions.owner = scene
	add_mesh_collisions(scene, Transform3D.IDENTITY, collisions, scene)
	return scene

func add_mesh_collisions(node: Node, parent_transform: Transform3D, collisions: Node3D, scene: Node) -> void:
	if node == collisions:
		return
	var transform := parent_transform
	if node is Node3D:
		transform *= node.transform
	if node is MeshInstance3D and node.mesh != null:
		if node.name in ["Шатер - гримерка", "Шатер - главный"]:
			# The source tents are thin surfaces. Render their existing walls from
			# both sides without changing the mesh or shared materials.
			for surface in node.mesh.get_surface_count():
				var original: Material = node.mesh.surface_get_material(surface)
				var material: BaseMaterial3D = original.duplicate() if original is BaseMaterial3D else StandardMaterial3D.new()
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
				node.set_surface_override_material(surface, material)
		var bounds: AABB = transform * node.get_aabb()
		# Text and tiny dressing details need no player collision. The game scene
		# supplies a continuous floor, including the main tent's missing ground.
		var extras: Dictionary = node.get_meta("extras", {})
		if node.name != "Plane" and not extras.get("decorative", false) and not String(node.name).begins_with("Text") and bounds.size.length() >= 0.25:
			var faces: PackedVector3Array = node.mesh.get_faces()
			if not faces.is_empty():
				# Bake transforms into vertices so scaled/nonuniform meshes retain
				# accurate physics without scaled CollisionShape3D nodes.
				for index in faces.size():
					faces[index] = transform * faces[index]
				var shape := ConcavePolygonShape3D.new()
				shape.set_faces(faces)
				shape.backface_collision = true
				var body := StaticBody3D.new()
				body.name = String(node.name) + "Collision"
				body.set_meta("source_mesh", String(node.name))
				collisions.add_child(body)
				body.owner = scene
				var collision := CollisionShape3D.new()
				collision.name = "CollisionShape3D"
				collision.shape = shape
				body.add_child(collision)
				collision.owner = scene
	for child in node.get_children():
		add_mesh_collisions(child, transform, collisions, scene)
