extends "res://scripts/scene_parts.gd"
## Small finish details for the existing makeup tent and clinic.
## The source layout, interactables, route and all imported props stay in place.

func setup(owner_game) -> void:
	game = owner_game
	name = "WorkroomFinish"
	dressing_finish()
	wardrobe_prep_cluster()
	clinic_finish()

func wardrobe_prep_cluster() -> void:
	replace_flat_costumes()

func replace_flat_costumes() -> void:
	# circus_set currently hangs four thin box shapes on its staff rail. Keep the
	# rail in place and replace only those generated flat garments with cloth forms.
	var rack := get_parent()
	var replaced := 0
	for child in rack.get_children():
		if not child is MeshInstance3D:
			continue
		if not child.mesh is BoxMesh or child.mesh.size.distance_to(Vector3(.35, 1.45, .16)) > .01:
			continue
		if absf(child.global_position.z - 46.0) > .04 or child.global_position.x < -53.0 or child.global_position.x > -50.5:
			continue
		child.visible = false
		replaced += 1
	set_meta("replaced_flat_costumes",replaced)
	var colors := ["563a43", "344b4b", "77634c", "3a3c46"]
	var lengths := [1.03, 1.23, .94, 1.16]
	for index in 4:
		# All four hooks meet the unchanged 2.5m-high rail, even for short coats.
		var bottom := Vector3(-52.55 + index * .46, 2.29-lengths[index], 45.87)
		hanging_costume(bottom, colors[index], lengths[index], index)

func hanging_costume(bottom: Vector3, color: String, length: float, style: int) -> void:
	var width: float = [.43, .39, .46, .40][style]
	var body := ArrayMesh.new()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0 := 0.0
	var y1 := length * .38
	var y2 := length * .78
	var y3 := length * .93
	var widths := [width, width * .76, width * 1.12, width * .34]
	var ys := [y0, y1, y2, y3]
	for segment in 3:
		var lower: float = widths[segment] * .5
		var upper: float = widths[segment + 1] * .5
		var z_front := .115
		var z_back := -.115
		var left_lower := Vector3(-lower, ys[segment], z_front)
		var right_lower := Vector3(lower, ys[segment], z_front)
		var right_upper := Vector3(upper, ys[segment + 1], z_front)
		var left_upper := Vector3(-upper, ys[segment + 1], z_front)
		add_quad(tool, left_lower, right_lower, right_upper, left_upper)
		add_quad(tool, Vector3(lower, ys[segment], z_back), Vector3(-lower, ys[segment], z_back), Vector3(-upper, ys[segment + 1], z_back), Vector3(upper, ys[segment + 1], z_back))
		add_quad(tool, left_lower, left_upper, Vector3(-upper, ys[segment + 1], z_back), Vector3(-lower, ys[segment], z_back))
		add_quad(tool, right_lower, Vector3(upper, ys[segment], z_back), Vector3(upper, ys[segment + 1], z_back), right_upper)
	tool.generate_normals()
	body = tool.commit()
	var coat_material := material(color,0.0,-1.0,0.0,"cloth")
	coat_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var coat := mesh_node(body, bottom, coat_material, "HangingCostume")
	coat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Loose sleeves give the silhouettes a readable shoulder and hem shape.
	for side in [-1.0, 1.0]:
		var shoulder := bottom + Vector3(side * width * .42, length * .78, 0)
		var cuff := bottom + Vector3(side * width * .72, length * .36, .015)
		var sleeve := rod(shoulder, cuff, .065, color)
		sleeve.material_override=coat_material
	# Each coat hangs from a small old brass triangle, still using the supplied rail.
	var apex := bottom + Vector3(0, length + .08, .13)
	var left := bottom + Vector3(-width * .56, length * .81, .13)
	var right := bottom + Vector3(width * .56, length * .81, .13)
	rod(apex, left, .012, "9b8057", .45)
	rod(apex, right, .012, "9b8057", .45)
	rod(left, right, .012, "9b8057", .45)
	rod(apex + Vector3(0, .015, 0), apex + Vector3(0, .13, 0), .012, "9b8057", .45)
	# Muted piping and buttons distinguish this from a row of plain cubes.
	var placket := box(bottom + Vector3(width * .13, length * .49, .121), Vector3(.018, length * .44, .012), "a08a63", false, .2)
	for button_index in 3:
		sphere(bottom + Vector3(width * .13, length * (.36 + button_index * .14), .135), Vector3(.026, .026, .018), "c1a779")
	var collar := box(bottom + Vector3(0, length * .89, .14), Vector3(.16, .11, .045), ["765b52", "58665d", "947f5d", "5c5962"][style])
	collar.rotation.z = -.08 if style % 2 == 0 else .08

func add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	tool.add_vertex(a); tool.add_vertex(b); tool.add_vertex(c)
	tool.add_vertex(a); tool.add_vertex(c); tool.add_vertex(d)

func dressing_finish() -> void:
	# The supplied room has two real vanities and an open center around its pole.
	# Give each vanity a matching low stool and a few bulbs without crowding the aisle.
	var vanity_mirrors: Array = []
	for mirror in game.mirror_system.mirrors:
		if mirror.center.x > -35.0 or mirror.center.z > 48.0 or mirror.size.x >= .8 or mirror.size.y >= 1.0:
			continue
		vanity_mirrors.append(mirror)
		vanity_bulbs(mirror)
		if mirror.center.z < 38.0:
			vanity_prep_details(mirror)
	vanity_mirrors.sort_custom(func(a, b): return a.center.z < b.center.z)
	for mirror in vanity_mirrors:
		var face: Vector3 = mirror.normal
		var stool_at: Vector3 = mirror.center + face * .78
		stool_at.y = .0
		stool(stool_at, atan2(face.x, face.z))

func vanity_bulbs(mirror: Dictionary) -> void:
	var center: Vector3 = mirror.center
	var normal: Vector3 = mirror.normal.normalized()
	var right: Vector3 = mirror.right.normalized()
	var up: Vector3 = mirror.up.normalized()
	var width: float = mirror.size.x
	var height: float = mirror.size.y
	for side in [-1.0, 1.0]:
		for fraction in [-.30, 0.0, .30]:
			var at: Vector3 = center + normal * .052 + right * side * (width * .5 + .045) + up * (height * fraction)
			var bulb := sphere(at, Vector3(.075, .075, .075), "e8c995")
			bulb.material_override = material("e8c995", 0.0, .42, .36)
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func vanity_prep_details(mirror: Dictionary) -> void:
	# This vanity already carries its makeup palette and vial; the small towel
	# and upright brushes finish that existing station without hiding either.
	var center: Vector3 = mirror.center
	var normal: Vector3 = mirror.normal.normalized()
	var right: Vector3 = mirror.right.normalized()
	var top_y := center.y - .58
	var towel_at := center + normal * .34 + right * .29
	towel_at.y = top_y + .025
	var towel := box(towel_at, Vector3(.28, .045, .20), "b8ae9b")
	towel.rotation.y = atan2(normal.x, normal.z)
	var fold := box(towel_at + Vector3(0, .025, 0), Vector3(.23, .008, .12), "d3c9b4")
	fold.rotation.y = towel.rotation.y
	var cup_at := center + normal * .32 - right * .29
	cup_at.y = top_y + .08
	cylinder(cup_at, .075, .16, "4b5150", .32, 16)
	for index in 3:
		var tilt: Vector3 = right * ((float(index) - 1.0) * .025)
		var bottom := cup_at + Vector3(0, .07, 0) + tilt
		var tip := cup_at + Vector3(0, .34, 0) + tilt * 1.5
		rod(bottom, tip, .012, ["79675c", "8b765e", "60575a"][index])
		sphere(tip, Vector3(.034, .05, .034), "c9b99a")

func stool(at: Vector3, yaw: float) -> void:
	var seat := cylinder(at + Vector3(0, .52, 0), .34, .14, "68464a", .04, 20)
	seat.rotation.y = yaw
	for offset in [-1.0, 1.0]:
		var foot: Vector3 = Vector3(cos(yaw), 0, -sin(yaw)) * offset * .19
		for z_side in [-1.0, 1.0]:
			var leg_offset := foot + Vector3(0, 0, z_side * .13)
			rod(at + leg_offset + Vector3(0, .08, 0), at + leg_offset + Vector3(0, .46, 0), .018, "46504e", .55)
	var ring_node := ring(at + Vector3(0, .22, 0), .23, .018, "9b825e")
	ring_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func clinic_finish() -> void:
	var c: Vector3 = game.layout.CLINIC_CENTER
	# Low, washable wall protection makes the room read as a clinic while staying
	# under the existing photo display and the worktable.
	var wall_faces: Array = [
		[Vector3(-20.1, 0, 59.89), 6.7, false, Vector3(0, 0, -1)],
		[Vector3(-23.49, 0, 57.0), 5.65, true, Vector3(1, 0, 0)],
		[Vector3(-16.71, 0, 57.0), 5.65, true, Vector3(-1, 0, 0)]
	]
	for face in wall_faces:
		var center: Vector3 = face[0]
		var span: float = face[1]
		var along_z: bool = face[2]
		var normal: Vector3 = face[3]
		var yaw: float = PI / 2 if along_z else 0.0
		var panel_center := center + normal * .04 + Vector3(0, .255, 0)
		var panels := roundi(span / .9)
		for index in panels:
			var along: float = (float(index) + .5) / panels - .5
			var offset := Vector3(0, 0, along * span) if along_z else Vector3(along * span, 0, 0)
			var panel_size := Vector3(span / panels - .025, .48, .055)
			if along_z: panel_size = Vector3(span / panels - .025, .48, .055)
			var pos := panel_center + offset
			var tile := box(pos, panel_size, "536d68", false, .08)
			tile.rotation.y = yaw
			var seam := box(pos + normal * .035 + Vector3(0, -.235, 0), Vector3(span / panels - .04, .018, .015), "85918a")
			seam.rotation.y = yaw
		var rail_size := Vector3(span, .045, .07)
		var rail := box(center + normal * .05 + Vector3(0, .53, 0), rail_size, "b19a68", false, .28)
		rail.rotation.y = yaw
	# A shallow stainless tray and folded linen complete the existing treatment
	# table. The three source jars, contract and key remain visible and reachable.
	var table_center: Vector3 = c + Vector3(-2.6, 0, -.8)
	var tray_at := table_center + Vector3(.22, .98, .45)
	box(tray_at, Vector3(.30, .025, .50), "8b9992", false, .7)
	for side in [-1.0, 1.0]:
		rod(tray_at + Vector3(-.14, .025, side * .23), tray_at + Vector3(.14, .025, side * .23), .012, "b9c0b5", .8)
	# Two neat gauze rolls and a folded towel stay grouped at the rear corner.
	var roll := cylinder(table_center + Vector3(.30, 1.04, -.24), .05, .19, "d9d7c9", .0, 16)
	roll.rotation.z = PI / 2
	box(table_center + Vector3(-.31, .96, -.43), Vector3(.28, .055, .24), "b8c7be")
	box(table_center + Vector3(-.31, .991, -.43), Vector3(.23, .009, .18), "d3d0c3")

func angular_distance(a: float, b: float) -> float:
	return absf(wrapf(a - b + PI, -PI, PI))
