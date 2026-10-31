extends "res://scripts/scene_parts.gd"
## Backstage room in the gap between the NW and N stand sectors. A curtain wall
## with a door closes it from the ring; side walls, a back wall and a ceiling
## hide the hollow stands. The service corridor and the dressing passage leave
## from it as walled tunnels with no way out to the yard behind the tents.
const NW_EDGE := -34.0
const N_EDGE := -12.0
const FRONT_RADIUS := 34.6
const BACK_RADIUS := 43.8
const HEIGHT := 3.6
const DOOR_WIDTH := 2.4
const DOOR_HEIGHT := 2.75
const DECK_Y := 5.9
const WALL := "35262a"
const TRIM := "5a4532"
const PASSAGE_ORIGIN := Vector3(-28, 0, 37)
const PASSAGE_DIR := Vector3(-.894427, 0, .447214)
const PASSAGE_ACROSS := Vector3(-.447214, 0, -.894427)
# The room itself is a rectangle aligned with the service corridor; only the
# curtain wall in front follows the stands.
const WEST_X := -21.6
const EAST_X := -12.0
const BACK_Z := 38.4
const DOOR_X := -16.0
var door_center := Vector3.ZERO
var door_normal := Vector3.ZERO

func setup(owner_game: Node3D) -> void:
	game = owner_game
	name = "Backstage"
	front_wall()
	side_walls()
	back_wall()
	ceiling()
	service_vestibule()
	passage_mouth()
	furnish()
	carve_stand_wall()
	close_tent_mouth()
	seal_yard()
	hide_layout_notes()
	batch()

func edge_point(degrees: float, radius: float) -> Vector3:
	var angle := deg_to_rad(degrees)
	return Vector3(sin(angle) * radius, 0, cos(angle) * radius)

func yaw_of(a: Vector3, b: Vector3) -> float:
	return atan2(-(b.z - a.z), b.x - a.x)

func panel(a: Vector3, b: Vector3, height: float, thickness: float, color: String, physical := true, kind := "wood", base := 0.0) -> MeshInstance3D:
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var piece := box(Vector3((a.x + b.x) * .5, base + height * .5, (a.z + b.z) * .5), Vector3(flat.length(), height, thickness), color, physical, 0.0, "BackstagePanel", kind)
	piece.rotation.y = yaw_of(a, b)
	return piece

# A wall from a to b with a doorway between d0 and d1 (both on the line).
func wall_with_opening(a: Vector3, b: Vector3, d0: Vector3, d1: Vector3, opening_height: float) -> void:
	if a.distance_to(d0) > a.distance_to(d1):
		var swap := d0; d0 = d1; d1 = swap
	if a.distance_to(d0) > .05: panel(a, d0, HEIGHT, .2, WALL)
	if d1.distance_to(b) > .05: panel(d1, b, HEIGHT, .2, WALL)
	panel(d0, d1, HEIGHT - opening_height, .2, WALL, true, "wood", opening_height)
	for p in [d0, d1]:
		var jamb := box(Vector3(p.x, opening_height * .5, p.z), Vector3(.16, opening_height, .3), TRIM, false, 0.0, "BackstageJamb", "wood")
		jamb.rotation.y = yaw_of(a, b)
	panel(d0, d1, .18, .3, TRIM, false, "wood", opening_height - .09)

func front_line() -> Array:
	return [edge_point(NW_EDGE - .6, FRONT_RADIUS), edge_point(N_EDGE + 1.6, FRONT_RADIUS)]

func front_z(x: float) -> float:
	var ends := front_line()
	var a: Vector3 = ends[0]; var b: Vector3 = ends[1]
	return lerpf(a.z, b.z, (x - a.x) / (b.x - a.x))

func front_wall() -> void:
	# The curtain wall runs a little into both stand foundations.
	var ends := front_line()
	var a: Vector3 = ends[0]; var b: Vector3 = ends[1]
	var along := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	door_normal = Vector3(along.z, 0, -along.x)
	if door_normal.dot(-((a + b) * .5)) < 0: door_normal = -door_normal
	door_center = Vector3(DOOR_X, 0, front_z(DOOR_X))
	var half := DOOR_WIDTH * .5
	wall_with_opening(a, b, door_center - along * half, door_center + along * half, DOOR_HEIGHT)
	var yaw := yaw_of(a, b)
	# Battens on the ring side and a cornice make it read as a built flat.
	var length := a.distance_to(b)
	var count := int(length / 1.15)
	for i in count + 1:
		var p := a.lerp(b, float(i) / count) + door_normal * .12
		if p.distance_to(door_center) < half + .45: continue
		var batten := box(p + Vector3(0, HEIGHT * .5, 0), Vector3(.09, HEIGHT, .05), "4d3a2c", false, 0.0, "BackstageBatten", "wood")
		batten.rotation.y = yaw
	var cornice := box((a + b) * .5 + door_normal * .13 + Vector3(0, HEIGHT - .06, 0), Vector3(length, .12, .08), "6d5638", false, 0.0, "BackstageCornice", "wood")
	cornice.rotation.y = yaw
	# Velvet drapes tied back at the jambs and a valance across the head.
	for side in [-1.0, 1.0]:
		var jamb: Vector3 = door_center + along * side * (half + .24) + door_normal * .18
		var drape := box(jamb + Vector3(0, DOOR_HEIGHT * .5 + .12, 0), Vector3(.44, DOOR_HEIGHT + .24, .1), "5b1d2b", false, 0.0, "BackstageDrape", "cloth")
		drape.rotation.y = yaw
		var tie := box(jamb + Vector3(0, 1.05, 0) + door_normal * .06, Vector3(.48, .07, .04), "b49863", false, .4)
		tie.rotation.y = yaw
	var valance := box(door_center + door_normal * .18 + Vector3(0, DOOR_HEIGHT + .24, 0), Vector3(DOOR_WIDTH + 1.0, .46, .1), "5b1d2b", false, 0.0, "BackstageValance", "cloth")
	valance.rotation.y = yaw
	for side in [-1.0, 1.0]:
		sconce(door_center + along * side * (half + 1.0) + Vector3(0, 2.45, 0), door_normal)

func side_walls() -> void:
	# Short stretch of stand side face between the curtain wall and the room.
	var corner := Vector3(WEST_X, 0, WEST_X / tan(deg_to_rad(NW_EDGE)))
	panel(edge_point(NW_EDGE, FRONT_RADIUS - .3), corner, HEIGHT, .2, WALL)
	# West wall with the dressing passage, east wall plain.
	var near := passage_crossing(PASSAGE_ORIGIN + PASSAGE_ACROSS * 1.48)
	var far := passage_crossing(PASSAGE_ORIGIN - PASSAGE_ACROSS * 1.48)
	wall_with_opening(corner, Vector3(WEST_X, 0, BACK_Z + .1), near, far, 3.1)
	panel(Vector3(EAST_X, 0, front_z(EAST_X) - .2), Vector3(EAST_X, 0, BACK_Z + .1), HEIGHT, .2, WALL)
	# Behind the east wall, close the remaining strip of curtain wall.
	panel(Vector3(EAST_X, 0, BACK_Z), edge_point(N_EDGE, BACK_RADIUS), HEIGHT, .2, WALL)

func back_wall() -> void:
	var x0: float = game.layout.SERVICE_X - 1.4
	var x1: float = game.layout.SERVICE_X + 1.4
	wall_with_opening(Vector3(WEST_X - .1, 0, BACK_Z), Vector3(EAST_X + .1, 0, BACK_Z), Vector3(x0, 0, BACK_Z), Vector3(x1, 0, BACK_Z), 3.0)

func ceiling() -> void:
	var corners := [Vector3(WEST_X, 0, BACK_Z), Vector3(WEST_X, 0, WEST_X / tan(deg_to_rad(NW_EDGE))), front_line()[0], Vector3(EAST_X, 0, front_z(EAST_X)), Vector3(EAST_X, 0, BACK_Z)]
	var builder := SurfaceTool.new(); builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_normal(Vector3.DOWN)
	for i in range(1, corners.size() - 1):
		for index in [0, i + 1, i]:
			builder.add_vertex(corners[index] + Vector3(0, HEIGHT, 0))
	var plane := mesh_node(builder.commit(), Vector3.ZERO, material("2c2523", 0, 1.0, 0.0, "wood"), "BackstageCeiling")
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	# Joists run straight across, parallel to the back wall.
	for z in [33.0, 34.6, 36.2, 37.8]:
		var joist := box(Vector3((WEST_X + EAST_X) * .5, HEIGHT - .07, z), Vector3(EAST_X - WEST_X, .14, .12), "3f322a", false, 0.0, "BackstageJoist", "wood")
		joist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for at in [Vector3(-18.6, HEIGHT, 33.8), Vector3(-15.0, HEIGHT, 36.2)]:
		pendant(at)

func pendant(top: Vector3) -> void:
	rod(top, top - Vector3(0, .7, 0), .012, "40403a")
	var hood := cylinder(top - Vector3(0, .74, 0), .28, .14, "2b2c27", .4)
	hood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bulb := sphere(top - Vector3(0, .84, 0), Vector3.ONE * .1, "f0d3a0")
	bulb.material_override = material("f0d3a0", 0, .5, 1.1)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	point_light(top - Vector3(0, 1.0, 0), "e8c592", 1.15, 9.0)

func sconce(at: Vector3, outward: Vector3) -> void:
	var plate := box(at + outward * .11, Vector3(.14, .22, .03), "2f2a24", false, .5, "SconcePlate")
	plate.rotation.y = atan2(outward.x, outward.z)
	rod(at + outward * .11, at + outward * .3 + Vector3(0, .05, 0), .015, "3b352c", .6)
	var shade := cylinder(at + outward * .3 + Vector3(0, .07, 0), .09, .12, "2b2c27", .4)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bulb := sphere(at + outward * .3, Vector3.ONE * .07, "f1d7a8")
	bulb.material_override = material("f1d7a8", 0, .5, 1.1)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	point_light(at + outward * .45, "f0c891", .5, 5.0)

func service_vestibule() -> void:
	# The service corridor's own walls stop at the canvas. Carry them straight
	# back to the backstage wall so the corridor starts there.
	var finish: float = game.layout.SERVICE_START + .15
	for x in [game.layout.SERVICE_X - 1.4, game.layout.SERVICE_X + 1.4]:
		panel(Vector3(x, 0, BACK_Z), Vector3(x, 0, finish), DECK_Y, .14, "3a3330", true, "wood")
	box(Vector3(game.layout.SERVICE_X, 3.05, (BACK_Z + .1 + finish) * .5), Vector3(2.66, .1, finish - BACK_Z - .1), "4a4440", false, 0.0, "VestibuleCeiling", "wood")
	var z := BACK_Z + 3.6
	rod(Vector3(game.layout.SERVICE_X, 3.0, z), Vector3(game.layout.SERVICE_X, 2.8, z), .012, "40403a")
	var shade := cylinder(Vector3(game.layout.SERVICE_X, 2.77, z), .2, .1, "343631", .3)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bulb := sphere(Vector3(game.layout.SERVICE_X, 2.69, z), Vector3.ONE * .08, "e8dcc0")
	bulb.material_override = material("e8dcc0", 0, .5, 1.1)
	point_light(Vector3(game.layout.SERVICE_X, 2.55, z), "e1d3b4", .7, 5.0)

func passage_mouth() -> void:
	# The dressing passage runs through a slot cut in the NW stand foundation.
	# Its walls and roof now start at the backstage side wall.
	for side in [-1.48, 1.48]:
		var start := passage_crossing(PASSAGE_ORIGIN + PASSAGE_ACROSS * side)
		panel(start, PASSAGE_ORIGIN + PASSAGE_ACROSS * side, 3.22, .12, "3b3037", true, "paint")
	var mid := passage_crossing(PASSAGE_ORIGIN)
	var reach := PASSAGE_ORIGIN.distance_to(mid)
	var roof := box(PASSAGE_ORIGIN - PASSAGE_DIR * (reach * .5 - .2) + Vector3(0, 3.29, 0), Vector3(reach - .3, .16, 2.92), "423b3c", false)
	roof.rotation.y = atan2(-PASSAGE_DIR.z, PASSAGE_DIR.x)
	var lamp_at := PASSAGE_ORIGIN - PASSAGE_DIR * (reach * .5)
	rod(lamp_at + Vector3(0, 3.21, 0), lamp_at + Vector3(0, 2.86, 0), .012, "655a49")
	var shade := cylinder(lamp_at + Vector3(0, 2.81, 0), .2, .1, "5c5144", .2)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bulb := sphere(lamp_at + Vector3(0, 2.73, 0), Vector3.ONE * .09, "f1dfbf")
	bulb.material_override = material("f1dfbf", 0, .5, 1.2)
	point_light(lamp_at + Vector3(0, 2.6, 0), "f1dfbf", .7, 5.0)

func passage_crossing(point: Vector3) -> Vector3:
	# Where the passage line through point meets the room's west wall.
	return point + PASSAGE_DIR * ((WEST_X - point.x) / PASSAGE_DIR.x)

func furnish() -> void:
	# A few working pieces along the side walls; the route between doors is clear.
	crate(Vector3(EAST_X + .6, 0, 36.6), Vector3(.9, .75, .75), .05)
	crate(Vector3(EAST_X + .55, 0, 37.6), Vector3(.8, .6, .7), -.04)
	crate(Vector3(EAST_X + .6, .75, 36.7), Vector3(.7, .5, .6), .12)
	asset("rope_coil", Vector3(EAST_X + .9, 0, 34.6), .8, .7, false)
	asset("wardrobe", Vector3(WEST_X + .45, 0, 37.2), PI / 2, 1.0, true)

func in_passage_slot(p: Vector3) -> bool:
	var offset := p - PASSAGE_ORIGIN
	var along := offset.dot(PASSAGE_DIR)
	var side := offset.dot(PASSAGE_ACROSS)
	return along > -8.5 and along < 4.0 and absf(side) < 1.42 and p.y < 3.25

func crosses_slot(corners: Array) -> bool:
	# Large wall triangles have their centre outside the slot; test samples.
	var a: Vector3 = corners[0]; var b: Vector3 = corners[1]; var c: Vector3 = corners[2]
	for u in [0.0, .25, .5, .75, 1.0]:
		for v in [0.0, .25, .5, .75, 1.0]:
			if u + v > 1.0: continue
			if in_passage_slot(a + (b - a) * u + (c - a) * v): return true
	return false

func carve_stand_wall() -> void:
	# The supplied stand mesh has a riser wall under the deck edge that crosses
	# the passage. Drop its triangles inside the passage, visual and collision.
	var stand := game.model.find_child("Circle_002", true, false) as MeshInstance3D
	if stand == null: return
	var to_world := stand.global_transform
	var carved := ArrayMesh.new()
	for index in stand.mesh.get_surface_count():
		var arrays: Array = stand.mesh.surface_get_arrays(index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for v in vertices.size(): indices.append(v)
		var kept := PackedInt32Array()
		for t in range(0, indices.size(), 3):
			if crosses_slot([to_world * vertices[indices[t]], to_world * vertices[indices[t + 1]], to_world * vertices[indices[t + 2]]]): continue
			kept.append(indices[t]); kept.append(indices[t + 1]); kept.append(indices[t + 2])
		arrays[Mesh.ARRAY_INDEX] = kept
		carved.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		carved.surface_set_material(index, stand.get_active_material(index))
	stand.mesh = carved
	for body in game.model.get_node("GeometryCollisions").get_children():
		if body.get_meta("source_mesh", "") != "Circle_002": continue
		for shape in body.get_children():
			if not shape is CollisionShape3D or not shape.shape is ConcavePolygonShape3D: continue
			var faces: PackedVector3Array = shape.shape.get_faces()
			var to_body: Transform3D = shape.global_transform
			var kept_faces := PackedVector3Array()
			for t in range(0, faces.size(), 3):
				if crosses_slot([to_body * faces[t], to_body * faces[t + 1], to_body * faces[t + 2]]): continue
				kept_faces.append(faces[t]); kept_faces.append(faces[t + 1]); kept_faces.append(faces[t + 2])
			var collision := ConcavePolygonShape3D.new(); collision.set_faces(kept_faces); collision.backface_collision = true
			shape.shape = collision

func close_tent_mouth() -> void:
	# The dressing tent's supplied doorway is far wider than the passage. Close
	# the rest of it with a plain flap just outside the canvas.
	var centre := Vector3(-48.1356, 0, 40.1154)
	var mouth := PASSAGE_ORIGIN + PASSAGE_DIR * 11.32
	var normal := (mouth - centre).normalized()
	var tangent := Vector3(-normal.z, 0, normal.x)
	var base := centre + normal * 10.45
	var cuts: Array[float] = []
	for side in [-1.56, 1.56]:
		var point: Vector3 = PASSAGE_ORIGIN + PASSAGE_ACROSS * side
		var along := (base - point).dot(normal) / PASSAGE_DIR.dot(normal)
		cuts.append((point + PASSAGE_DIR * along - base).dot(tangent))
	cuts.sort()
	for span in [[-4.6, cuts[0]], [cuts[1], 4.6]]:
		panel(base + tangent * span[0], base + tangent * span[1], 6.0, .12, "4a1d29", true, "cloth")
	panel(base + tangent * cuts[0], base + tangent * cuts[1], 2.7, .12, "4a1d29", true, "cloth", 3.3)

func seal_yard() -> void:
	# The open ground between the tents, the passage and the service corridor is
	# not part of the game. Fill it with solid volumes that hug the outside of
	# the passage wall, the dressing canvas, the storage fence and the corridor.
	var body := StaticBody3D.new(); body.name = "ClosedYard"; add_child(body)
	var outline := [Vector2(-21.47, 45.75), Vector2(-30.84, 40.26), Vector2(-38.26, 43.98), Vector2(-40.6, 47.27), Vector2(-21.47, 47.27)]
	var points := PackedVector3Array()
	for p in outline:
		points.append(Vector3(p.x, -.2, p.y)); points.append(Vector3(p.x, 4.0, p.y))
	var hull := ConvexPolygonShape3D.new(); hull.points = points
	var shape := CollisionShape3D.new(); shape.shape = hull; body.add_child(shape)
	blocker(Vector3(-22.6, 1.9, 50.6), Vector3(2.2, 4.2, 6.7), 0.0, body)

func hide_layout_notes() -> void:
	# The supplied layout carries the modeller's 3D text notes beside the prop pile.
	for source in game.model.find_children("Text*", "MeshInstance3D", true, false):
		source.hide()
	for body in game.model.get_node("GeometryCollisions").get_children():
		if String(body.get_meta("source_mesh", "")).begins_with("Text"):
			body.collision_layer = 0
