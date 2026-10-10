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
var focus_query := PhysicsRayQueryParameters3D.new()
var last_focus_prompt := ""

func _ready() -> void:
	touch_mode = DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()
	ray.add_exception(self)
	focus_query.collision_mask = 1
	focus_query.exclude = [get_rid()]
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
	var prompt := ""
	if is_instance_valid(focus) and focus.has_method("interact"):
		prompt = focus.prompt
	else:
		focus = null
	# UI text/shaping only needs notification when the displayed prompt changes.
	if prompt != last_focus_prompt:
		last_focus_prompt = prompt
		focus_changed.emit(prompt)

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
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var space := get_world_3d().direct_space_state
	focus_query.from = eye
	for id in game.targets:
		for body in game.targets[id]:
			if not is_instance_valid(body) or body.collision_layer == 0: continue
			var point: Vector3 = body.to_global(body.get_meta("focus_point", Vector3.ZERO))
			var offset: Vector3 = point - eye
			var distance_squared := offset.length_squared()
			if distance_squared > 14.44 or distance_squared < .01: continue
			var direction := offset / sqrt(distance_squared)
			var score := forward.dot(direction)
			if score <= best_score: continue
			focus_query.to = point + direction * .08
			var hit := space.intersect_ray(focus_query)
			var blocker: Object = hit.get("collider")
			if blocker == body or (is_instance_valid(blocker) and blocker.has_method("interact") and blocker.interaction_id == body.interaction_id):
				best = body
				best_score = score
	return best
