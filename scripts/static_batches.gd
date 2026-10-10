extends RefCounted
## Merge immobile environment surfaces by material within four-metre cells.
## Interaction meshes stay separate; collision nodes and source transforms survive.
static func apply(source: Node3D, destination: Node3D) -> Dictionary:
	var groups := {}
	for node in source.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var name := String(mesh_node.name)
		if not mesh_node.mesh or not mesh_node.visible or mesh_node.skeleton != NodePath(""): continue
		if name.contains("Mirror") or name.contains("mirror") or name.begins_with("Crate") or name in ["Cylinder_009", "Cylinder_008"]: continue
		# Multi-surface artist props and transparent surfaces retain independent sorting.
		if mesh_node.mesh.get_surface_count() != 1: continue
		var material := mesh_node.get_active_material(0)
		if not material is StandardMaterial3D or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
		var center: Vector3 = mesh_node.to_global(mesh_node.get_aabb().get_center())
		var cell := Vector2i(floori(center.x / 4.0), floori(center.z / 4.0))
		var key := "%s:%s:%s:%s" % [cell.x,cell.y,material.get_instance_id(),mesh_node.cast_shadow]
		if not groups.has(key): groups[key] = []
		groups[key].append(mesh_node)
	var merged := 0
	var batches := 0
	for key in groups:
		var nodes: Array = groups[key]
		if nodes.size() < 3: continue
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_material(nodes[0].get_active_material(0))
		for node in nodes:
			builder.append_from(node.mesh, 0, destination.global_transform.affine_inverse()*node.global_transform)
		var combined := MeshInstance3D.new()
		combined.name = "StaticBatch"+str(batches)
		combined.mesh = builder.commit()
		combined.cast_shadow = nodes[0].cast_shadow
		destination.add_child(combined)
		for node in nodes: node.hide()
		merged += nodes.size()
		batches += 1
	return {"source_meshes":merged,"batches":batches}
