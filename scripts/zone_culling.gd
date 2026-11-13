extends Node
## Portal culling across the main tent wall.
## The canvas is an opaque cylinder (radius 50, height 20) pierced only at the
## bottom, where the service corridor and the dressing passage go through. From
## the ring the dressing tent, clinic block and house were all drawn behind the
## canvas (a third of the opening's draw calls), and Godot's occlusion buffer is
## too coarse to reject them at 50 m. Here static geometry on the far side of the
## wall is drawn only when its bounds fall inside the view cone through an
## opening. The cone depends on the eye position alone, so the work reruns only
## after the camera moves. Geometry is collected once after start-up and again
## on each story phase change, when scenes add or remove their props.
##
## Visibility is switched on the rendering server instance, never on the node:
## story code keeps full control of `visible`, and an instance is only ever
## re-shown while its node is visible in the tree.
var game
const RADIUS := 50.0
const HEIGHT := 20.0
# Openings measured from the canvas mesh, padded: degrees from +X towards +Z.
const OPENINGS := [Vector2(112.5, 114.5), Vector2(126.5, 130.5)]
const OPENING_TOP := 3.6
# Near an opening the cone degenerates; there everything stays drawn.
const OPENING_CLEARANCE := 3.0
# Static geometry is grouped into cells; one bounds test per cell.
const CELL := 6.0
const MOVE_EPSILON := .05
# The gallery and story props are built over the first frames.
const FIRST_COLLECT := 1.0

var portals: Array = []  # [corners: Array[Vector3], centre: Vector3]
# side 0: inside the tent, side 1: outside it. Each cluster: [aabb, [nodes], hidden]
var clusters := [[], []]
var last_eye := Vector3.INF
var start_clock := 0.0
var collected := false
var last_phase := ""
var enabled := true

func setup(owner_game) -> void:
	game = owner_game
	for opening in OPENINGS:
		var a := deg_to_rad(opening.x); var b := deg_to_rad(opening.y)
		var left := Vector3(cos(a), 0, sin(a)) * RADIUS
		var right := Vector3(cos(b), 0, sin(b)) * RADIUS
		var corners := [left, right, right + Vector3.UP * OPENING_TOP, left + Vector3.UP * OPENING_TOP]
		portals.append([corners, (left + right) * .5 + Vector3.UP * OPENING_TOP * .5])

func side_of(box: AABB) -> int:
	# -1: spans the wall, sits above it, or is near an opening; never culled.
	if box.end.y > HEIGHT: return -1
	var nearest := Vector2(clampf(0, box.position.x, box.end.x), clampf(0, box.position.z, box.end.z)).length()
	var farthest := 0.0
	for x in [box.position.x, box.end.x]:
		for z in [box.position.z, box.end.z]:
			farthest = maxf(farthest, Vector2(x, z).length())
	for portal in portals:
		var centre: Vector3 = portal[1]
		if box.grow(OPENING_CLEARANCE).has_point(centre): return -1
	if farthest < RADIUS - .05: return 0
	if nearest > RADIUS + .05: return 1
	return -1

func dynamic(node: Node) -> bool:
	var ancestor := node
	while ancestor != null and ancestor != game:
		if ancestor.get_meta("dynamic_set", false) or ancestor is CharacterBody3D or ancestor is AnimatableBody3D: return true
		if ancestor is Skeleton3D or ancestor is AnimationMixer: return true
		ancestor = ancestor.get_parent()
	for id in game.actors:
		if game.actors[id].is_ancestor_of(node): return true
	return false

func collect() -> void:
	show_all()
	var cells := [{}, {}]
	for node in game.world.find_children("*", "GeometryInstance3D", true, false):
		var item := node as GeometryInstance3D
		if item is MeshInstance3D and item.skeleton != NodePath(""): continue
		if item is GPUParticles3D or item is CPUParticles3D: continue
		if is_instance_valid(game.mirror_system) and game.mirror_system.is_ancestor_of(item): continue
		if dynamic(item): continue
		var box := item.global_transform * item.get_aabb()
		var side := side_of(box)
		if side < 0: continue
		var centre := box.get_center()
		var key := Vector3i(floori(centre.x / CELL), floori(centre.y / CELL), floori(centre.z / CELL))
		if not cells[side].has(key): cells[side][key] = [box, [], false]
		var cluster: Array = cells[side][key]
		cluster[0] = cluster[0].merge(box)
		cluster[1].append(item)
	clusters = [cells[0].values(), cells[1].values()]
	last_eye = Vector3.INF

func show_all() -> void:
	for side in clusters:
		for cluster in side: set_cluster(cluster, false)

func set_cluster(cluster: Array, hidden: bool) -> void:
	if cluster[2] == hidden: return
	cluster[2] = hidden
	for item in cluster[1]:
		if not is_instance_valid(item): continue
		RenderingServer.instance_set_visible(item.get_instance(), not hidden and item.is_visible_in_tree())

# Planes through the eye and each opening edge, normals pointing into the cone.
func cone(eye: Vector3, portal: Array) -> Array:
	var corners: Array = portal[0]
	var centre: Vector3 = portal[1]
	var planes := []
	for index in 4:
		var plane := Plane(eye, corners[index], corners[(index + 1) % 4])
		if plane.distance_to(centre) < 0: plane = -plane
		planes.append(plane)
	return planes

func box_in_cone(box: AABB, planes: Array) -> bool:
	for plane in planes:
		var outside := true
		for index in 8:
			if plane.distance_to(box.get_endpoint(index)) >= 0: outside = false; break
		if outside: return false
	return true

func eye_side(eye: Vector3) -> int:
	if eye.y > HEIGHT: return -1
	for portal in portals:
		if eye.distance_to(portal[1]) < OPENING_CLEARANCE: return -1
	var r := Vector2(eye.x, eye.z).length()
	if r < RADIUS - .3: return 0
	if r > RADIUS + .3: return 1
	return -1

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not enabled: return
	if not collected:
		start_clock += delta
		if start_clock < FIRST_COLLECT: return
	if not collected or game.phase != last_phase:
		collected = true; last_phase = game.phase
		collect()
	var eye: Vector3 = game.player.camera.global_position
	if eye.distance_to(last_eye) < MOVE_EPSILON: return
	last_eye = eye
	var side := eye_side(eye)
	if side < 0:
		show_all(); return
	# Geometry on the eye's own side is always drawn.
	for cluster in clusters[side]: set_cluster(cluster, false)
	var cones := []
	for portal in portals: cones.append(cone(eye, portal))
	for cluster in clusters[1 - side]:
		var seen := false
		for planes in cones:
			if box_in_cone(cluster[0], planes): seen = true; break
		set_cluster(cluster, not seen)
