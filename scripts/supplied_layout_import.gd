@tool
extends EditorScenePostImport
## Collisions are rebuilt from the prepared artist scene, in world coordinates.
func _post_import(scene: Node) -> Object:
	var collisions:=Node3D.new()
	collisions.name="GeometryCollisions"
	scene.add_child(collisions);collisions.owner=scene
	collect(scene,Transform3D.IDENTITY,collisions,scene)
	return scene

func collect(node: Node, parent: Transform3D, collisions: Node3D, scene: Node) -> void:
	if node==collisions:return
	var transform:=parent
	if node is Node3D:transform*=node.transform
	if node is MeshInstance3D and node.mesh:
		var source_name:=String(node.name)
		if source_name.contains("Tent") or source_name.contains("Шатер"):
			for index in node.mesh.get_surface_count():
				var original: Material=node.get_active_material(index)
				if original is BaseMaterial3D:
					var mat:BaseMaterial3D=original.duplicate()
					mat.cull_mode=BaseMaterial3D.CULL_DISABLED
					node.set_surface_override_material(index,mat)
		var bounds:AABB=transform*node.get_aabb()
		if not source_name.begins_with("Text") and bounds.size.length()>=.25:
			var faces:PackedVector3Array=node.mesh.get_faces()
			if not faces.is_empty():
				for i in faces.size():faces[i]=transform*faces[i]
				var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces);shape.backface_collision=true
				var body:=StaticBody3D.new();body.name=source_name+"Collision"
				body.set_meta("source_mesh",source_name)
				collisions.add_child(body);body.owner=scene
				var collision:=CollisionShape3D.new();collision.shape=shape
				body.add_child(collision);collision.owner=scene
	for child in node.get_children():collect(child,transform,collisions,scene)
