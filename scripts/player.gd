extends CharacterBody3D
signal focus_changed(text: String)
@export var speed: float = 3.4
@export var mouse_sensitivity: float = 0.0025
@onready var camera: Camera3D = $Camera
@onready var ray: RayCast3D = $Camera/InteractionRay
var locked: bool = false
var touch_move: Vector2 = Vector2.ZERO
var focus: Object
var touch_mode: bool = false

func _ready() -> void:
	touch_mode = DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()
	ray.add_exception(self)
	if not touch_mode and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var movement := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_move.length() > 0.01:
		movement = touch_move
	if locked or (not touch_mode and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED):
		movement = Vector2.ZERO
	var direction := transform.basis * Vector3(movement.x, 0, movement.y)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = 0
	move_and_slide()
	focus = find_focus() if not locked else null
	if is_instance_valid(focus) and focus.has_method("interact"):
		focus_changed.emit(focus.prompt)
	else:
		focus = null
		focus_changed.emit("")

func _unhandled_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseButton and event.pressed and not touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative * mouse_sensitivity)
	if event.is_action_pressed("interact"):
		interact()

func look(amount: Vector2) -> void:
	if locked:
		return
	rotate_y(-amount.x)
	camera.rotation.x = clampf(camera.rotation.x - amount.y, -1.35, 1.35)

func interact() -> void:
	if not locked and is_instance_valid(focus):
		focus.interact()

func set_locked(value: bool) -> void:
	locked = value
	touch_move = Vector2.ZERO
	if not touch_mode and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		touch_move = Vector2.ZERO
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func find_focus() -> Object:
	var direct: Object = ray.get_collider()
	if is_instance_valid(direct) and direct.has_method("interact"): return direct
	# A forgiving cone on phones, with an occlusion ray for every candidate.
	var best: Object = null
	var best_score := .90
	var game := get_parent()
	for group in game.targets.values():
		for body in group:
			if not is_instance_valid(body) or body.collision_layer == 0: continue
			var offset: Vector3 = body.global_position - camera.global_position
			# Imported colliders have baked vertices; their origin is not the mesh center.
			if body.get_parent().name == "GeometryCollisions": continue
			if offset.length() > 3.8 or offset.length() < .1: continue
			var score := -camera.global_basis.z.dot(offset.normalized())
			if score <= best_score: continue
			var query := PhysicsRayQueryParameters3D.create(camera.global_position, body.global_position, 1, [get_rid()])
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if hit.get("collider") == body:
				best = body
				best_score = score
	return best
