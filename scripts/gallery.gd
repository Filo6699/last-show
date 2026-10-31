extends "res://scripts/scene_parts.gd"
## Finished seating follows the actual imported treads, with clear radial aisles.
var occupied: Array[Vector3] = []
var seat_bases: Array[Basis] = []
var parts := {}
var hands: MultiMeshInstance3D
var show
var aisle_lights: Array[OmniLight3D] = []
const AISLE_HALF := .024

func close_sector_ends(row_guard: StaticBody3D) -> void:
	# Later set pieces extend some stand edges; measure after they exist.
	await get_tree().physics_frame
	if not is_instance_valid(game): return
	# Where a stand sector ends, close its side so the deck end and the open
	# floor beside it don't lead onto the benches. Boxes sit just inside the
	# seating footprint, following the rake.
	var steps := 1800
	var previous := not tread(40.0, -TAU / steps).is_empty()
	for index in steps:
		var angle := TAU * index / steps
		var seated := not tread(40.0, angle).is_empty()
		if seated != previous:
			for radius in range(34, 50):
				# The stand side is not exactly radial; find its edge at each radius.
				var r := float(radius) + .5
				var found := NAN
				var was := walkable(r, angle - .07)
				for sample in range(-140, 141):
					var probe := angle + sample * .0005
					var now := walkable(r, probe)
					if now != was and (is_nan(found) or absf(probe - angle) < absf(found - angle)): found = probe
					was = now
				if is_nan(found): continue
				var edge := found + (1.0 if seated else -1.0) * .25 / r
				var hit := surface(r, edge)
				if hit.is_empty() or hit.position.y < .3: continue
				var guard := CollisionShape3D.new(); var bounds := BoxShape3D.new()
				bounds.size = Vector3(.12, 2.0, 1.1); guard.shape = bounds
				guard.transform = Transform3D(Basis(Vector3.UP, edge), hit.position + Vector3(0, .8, 0))
				row_guard.add_child(guard)
		previous = seated

func surface(radius: float, angle: float) -> Dictionary:
	var at := Vector3(sin(angle) * radius, 12, cos(angle) * radius)
	var query := PhysicsRayQueryParameters3D.create(at, at - Vector3(0, 13, 0), 1, [game.player.get_rid()])
	return game.get_world_3d().direct_space_state.intersect_ray(query)

# Raised seating or deck, as opposed to the arena floor beside a stand.
func walkable(radius: float, angle: float) -> bool:
	var hit := surface(radius, angle)
	return not hit.is_empty() and hit.position.y > (4.0 if radius >= 44.0 else .5)

func tread(radius: float, angle: float) -> Dictionary:
	var at := Vector3(sin(angle) * radius, 12, cos(angle) * radius)
	var query := PhysicsRayQueryParameters3D.create(at, at - Vector3(0, 13, 0), 1, [game.player.get_rid()])
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	return hit if not hit.is_empty() and String(hit.collider.get_meta("source_mesh", "")) == "Circle_002" else {}

func setup(owner_game, owner_show) -> void:
	game = owner_game; show = owner_show; name = "FinishedGallery"
	build_foundation()
	var rng := RandomNumberGenerator.new(); rng.seed = 77429
	for row in 8:
		var radius := 35.3 + row * 1.2
		# Curved benches, open aisles and supported backs make the seating read
		# as a built amphitheatre even when the audience has left after the show.
		for section in 12:
			var start := section * TAU / 12 + AISLE_HALF
			var end := (section + 1) * TAU / 12 - AISLE_HALF
			for segment in 5:
				var angle := lerpf(start, end, (segment + .5) / 5.0)
				var hit := tread(radius, angle)
				if hit.is_empty(): continue
				var base: Vector3 = hit.position
				var tangent := Basis(Vector3.UP, angle)
				var length := radius * (end - start) / 5 - .035
				var seat := box(base + Vector3(0, .45, 0), Vector3(length, .10, .52), "65503a")
				seat.basis = tangent
				var back := box(base + tangent * Vector3(0, .85, .28), Vector3(length, .35, .09), "503c30")
				back.basis = tangent
				for side in [-1, 1]:
					var leg := box(base + tangent * Vector3(side * length * .4, .22, .17), Vector3(.065, .44, .09), "333a38")
					leg.basis = tangent
		var count := int(TAU * radius / 1.12)
		for index in count:
			var angle := TAU * (index + .5) / count
			var aisle_distance := absf(wrapf(angle + TAU / 24, 0, TAU / 12) - TAU / 24)
			if aisle_distance < AISLE_HALF + .012 or rng.randf() > .58: continue
			var hit := tread(radius, angle)
			if hit.is_empty(): continue
			var at: Vector3 = hit.position + Vector3(0, .50, 0)
			var basis := Basis(Vector3.UP, angle + PI)
			occupied.append(at); seat_bases.append(basis)
			var coat: String = ["33343d", "4c383c", "394541", "514536", "303d4c"][rng.randi_range(0, 4)]
			var skin: String = ["a38c76", "806455", "c0a48b"][rng.randi_range(0, 2)]
			part("torso", coat, Transform3D(basis.scaled(Vector3(1, rng.randf_range(.92, 1.08), 1)), at + Vector3(0, .38, 0)))
			part("head", skin, Transform3D(basis, at + Vector3(0, .88, 0)))
			part("hair", ["342e2a", "514338", "777266"][rng.randi_range(0, 2)], Transform3D(basis, at + Vector3(0, .99, -.015)))
			for side in [-1, 1]:
				part("thigh", "292c32", Transform3D(basis, at + basis * Vector3(side * .12, .06, .23)))
				part("shin", "292c32", Transform3D(basis, at + basis * Vector3(side * .12, -.21, .39)))
				part("shoe", "242326", Transform3D(basis, at + basis * Vector3(side * .12, -.41, .44)))
				part("arm", coat, Transform3D(basis, at + basis * Vector3(side * .24, .33, .08)))
	for section in 12: aisle(section * TAU / 12)
	# Finish the back edge instead of leaving an exposed, apparently endless slab.
	for index in 144:
		var angle := TAU * (index + .5) / 144
		var hit := tread(45.5, angle)
		if hit.is_empty(): continue
		var at: Vector3 = hit.position
		var rail := box(at + Vector3(0,1.3,0), Vector3(2.04,.12,.10), "8a7150", true, 0.0, "GalleryRearRail")
		rail.rotation.y = angle
		if index % 3 == 0:
			box(at+Vector3(0,.7,0),Vector3(.10,1.4,.10),"483e32",true)
	# The rows are scenery. An invisible wall just inside the rear rail keeps the
	# 6 m deck from leaking onto the benches; only the aisle ramps cross it.
	var row_guard := StaticBody3D.new(); row_guard.name = "GalleryRowGuard"; add_child(row_guard)
	for index in 288:
		var angle := TAU * (index + .5) / 288
		var aisle_offset := absf(wrapf(angle + TAU / 24, 0, TAU / 12) - TAU / 24) * 45.0
		if aisle_offset < .95: continue
		var hit := tread(45.0, angle)
		if hit.is_empty(): continue
		var guard := CollisionShape3D.new(); var bounds := BoxShape3D.new()
		bounds.size = Vector3(1.05, 1.8, .12); guard.shape = bounds
		guard.transform = Transform3D(Basis(Vector3.UP, angle), hit.position + Vector3(0, .9, 0))
		row_guard.add_child(guard)
	close_sector_ends.call_deferred(row_guard)
	for section in 8:
		var angle := TAU * (section + .5) / 8
		if tread(41, angle).is_empty(): continue
		var fill := point_light(Vector3(sin(angle)*40,8,cos(angle)*40), "cdc7b6", 1.10, 18)
		aisle_lights.append(fill)
	# The imported grandstand still casts its structural shadows. These small
	# added bench legs/backs are subpixel at ring distance; avoid drawing every
	# one into each theatrical shadow map. They continue receiving light/shadows.
	for visual in find_children("*","MeshInstance3D",true,false):
		visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch()
	build_parts()
	sync_lighting()

func sync_lighting() -> void:
	var empty_night: bool = game.phase in ["return_arena","roof_access","roof","home","bathroom","captured","trapped","complete"] and not game.flags.get("roof_audience",false)
	for fill in aisle_lights:
		fill.light_energy = .06 if empty_night else 1.10

func part(kind: String, color: String, at: Transform3D) -> void:
	var key := kind + ":" + color
	if not parts.has(key): parts[key] = []
	parts[key].append(at)

func build_parts() -> void:
	for key in parts:
		var kind: String = key.split(":")[0]
		var mesh: Mesh
		if kind in ["head", "hair"]:
			var head := SphereMesh.new(); head.radius = .125; head.height = .28
			head.radial_segments = 8; head.rings = 4
			if kind == "hair": head.height = .14; head.radius = .13
			mesh = head
		elif kind in ["torso", "arm"]:
			var body := CapsuleMesh.new(); body.radius = .20 if kind == "torso" else .065
			body.height = .58 if kind == "torso" else .39
			body.radial_segments = 8; body.rings = 3; mesh = body
		else:
			var block := BoxMesh.new()
			block.size = {"thigh": Vector3(.16, .17, .43), "shin": Vector3(.12, .46, .13), "shoe": Vector3(.16, .11, .29)}[kind]
			mesh = block
		var multi := MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh; multi.instance_count = parts[key].size()
		for index in multi.instance_count: multi.set_instance_transform(index, parts[key][index])
		var node := MultiMeshInstance3D.new(); node.name = "Audience_" + kind
		node.multimesh = multi; node.material_override = material(key.split(":")[1])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node); show.audience.append(node)
	var palm := SphereMesh.new(); palm.radius = .055; palm.height = .13; palm.radial_segments = 6; palm.rings = 3
	var multi := MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_3D; multi.mesh = palm
	multi.instance_count = occupied.size() * 2
	for index in occupied.size():
		for side in 2:
			var at := occupied[index] + seat_bases[index] * Vector3(-.15 if side == 0 else .15, .27, .30)
			multi.set_instance_transform(index * 2 + side, Transform3D(seat_bases[index], at))
	hands = MultiMeshInstance3D.new(); hands.multimesh = multi; hands.material_override = material("a38c76")
	hands.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hands); show.audience.append(hands)

func build_foundation() -> void:
	# The imported treads are thin open sheets. Fill the volume below each real
	# tread, including the front and sector ends; never build over service rooms.
	# One mesh/collider keeps this inexpensive on mobile.
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := 0
	for angular in 180:
		var angle := TAU * (angular + .5) / 180.0
		var half_angle := TAU / 360.0
		# The half-width matches the actual 1.7m opening cut in the source GLB.
		var in_aisle := absf(wrapf(angle + TAU / 24, 0, TAU / 12) - TAU / 24) < .028
		# Rows continue out to the canvas: the 6m promenade behind the last tread
		# used to leave a dark, walkable ring at ground level under its deck.
		for radial in 35:
			var radius := 34.3 + radial * .45
			# Aisle ramps and their top landings are closed blocks of their own.
			if in_aisle and radius < 46.8: continue
			var center := Vector3(sin(angle)*radius,0,cos(angle)*radius)
			if reserved_passage(center): continue
			var hit := tread(radius, angle)
			if hit.is_empty(): continue
			var height: float = hit.position.y - .055
			# Respect the faceted source steps at every cell corner. A centre
			# sample alone can raise a block above the neighbouring lower tread.
			for r in [radius - .226, radius + .226]:
				for a in [angle - half_angle, angle + half_angle]:
					var edge := tread(r, a)
					if not edge.is_empty(): height = minf(height, edge.position.y - .055)
			if height <= .1: continue
			var points: Array[Vector3] = []
			for r in [radius - .226, radius + .226]:
				for a in [angle - half_angle, angle + half_angle]:
					points.append(Vector3(sin(a) * r, .015, cos(a) * r))
			# Quad order: inner left, inner right, outer left, outer right.
			add_closed_block(builder, points, [height, height, height, height])
			cells += 1
	if cells == 0: return
	builder.generate_normals()
	var mesh := builder.commit()
	var shell := mesh_node(mesh, Vector3.ZERO, material("44382f", 0, -1, 0, "wood"), "GallerySolidFoundation")
	shell.set_meta("dynamic_set", true)
	add_mesh_collision(shell)
	set_meta("foundation_cells", cells)

func reserved_passage(at: Vector3) -> bool:
	# The authored floor route passes beneath the NW stands to the dressing
	# room and doctor. Keep a visible, capsule-wide underpass instead of
	# filling those existing story routes with the seating foundation.
	# Only the slot under the deck to the service door; the backstage walls
	# (backstage.gd) line it, so no hollow is left under the NW rows.
	if at.x > -22.6 and at.x < -17.4 and at.z > 37.8 and at.z < 48.5: return true
	var offset := Vector2(at.x+28,at.z-37)
	var along := offset.dot(Vector2(-.894427,.447214))
	var across := offset.dot(Vector2(-.447214,-.894427))
	return along > -8 and along < 17 and absf(across) < 3.1

func add_closed_block(builder: SurfaceTool, bottom: Array[Vector3], heights: Array) -> void:
	var points := bottom.duplicate()
	for i in 4:
		points.append(Vector3(bottom[i].x, float(heights[i]), bottom[i].z))
	# Double-sided material handles both outer faces and the underside of stairs.
	for face in [[0,1,3,2], [4,6,7,5], [0,4,5,1], [2,3,7,6], [0,2,6,4], [1,5,7,3]]:
		for i in [0,1,2,0,2,3]: builder.add_vertex(points[face[i]])

func add_mesh_collision(node: MeshInstance3D) -> void:
	node.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = node.mesh.create_trimesh_shape()
	shape.shape.backface_collision = true
	node.add_child(body); body.add_child(shape)

func aisle(angle: float) -> void:
	# Full-width, closed wooden ramp: no gaps at the source cut and no exposed
	# underside. The upper landing meets the actual 6m gallery floor.
	var normal := Vector3(sin(angle), 0, cos(angle))
	var tangent := Vector3(cos(angle), 0, -sin(angle)) * .86
	var entry := normal * 32.0 + Vector3(0, .075, 0)
	var start := normal * 33.1 + Vector3(0, .075, 0)
	var end := normal * 45.5 + Vector3(0, 6.05, 0)
	# The source deck's aisle cut runs about half a metre past the ramp top.
	var landing := normal * 46.8 + Vector3(0, 6.05, 0)
	if tread(43.0, angle).is_empty() and tread(43.0, angle+.06).is_empty() and tread(43.0, angle-.06).is_empty(): return
	var builder := SurfaceTool.new(); builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ends in [[entry,start],[start,end],[end,landing]]:
		var first: Vector3 = ends[0]; var last: Vector3 = ends[1]
		var bottom: Array[Vector3] = []
		for point in [first-tangent,first+tangent,last-tangent,last+tangent]:
			var floor_y := .015
			# A real covered service passage crosses beneath this particular
			# aisle. Its deck stays solid without blocking the ground route.
			if absf(wrapf(angle - 11*TAU/12,-PI,PI)) < .01:
				floor_y = point.y - .14
			bottom.append(Vector3(point.x,floor_y,point.z))
		add_closed_block(builder,bottom,[first.y,first.y,last.y,last.y])
	builder.generate_normals()
	var ramp := mesh_node(builder.commit(), Vector3.ZERO, material("603943"), "GalleryAccessAisle")
	ramp.set_meta("dynamic_set", true)
	ramp.set_meta("gallery_aisle", true)
	add_mesh_collision(ramp)
	for side in [-1,1]:
		rod(start+tangent*side+Vector3(0,.018,0), end+tangent*side+Vector3(0,.018,0), .022, "aa8b57")
	# Invisible balustrades keep visitors on the stairs: the benches beside the
	# aisle are scenery, and dropping into the rows put the camera in the seats.
	var forward := (end - start).normalized()
	var side_axis := tangent.normalized()
	if forward.cross(side_axis).y < 0: side_axis = -side_axis
	var up := forward.cross(side_axis).normalized()
	var guard_body: StaticBody3D = ramp.get_child(0)
	for side in [-1,1]:
		var guard := CollisionShape3D.new(); var bounds := BoxShape3D.new()
		bounds.size = Vector3(.1, 1.2, start.distance_to(end) + .2); guard.shape = bounds
		guard.transform = Transform3D(Basis(side_axis, up, forward), (start + end) * .5 + up * .6 + side_axis * side * .93)
		guard_body.add_child(guard)
