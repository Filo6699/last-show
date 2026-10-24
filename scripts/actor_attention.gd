extends Node
## Small in-world invitation for Mordecai during the first free-roam beat.
## The imported root idle remains untouched; this only adds a short real arm
## pose to the additional sleeve/forearm/hand bones in his attention rig.
var game: Node3D
var actor: Node3D
var skeleton: Skeleton3D
var animator: AnimationPlayer
var paused := false
var engaged := false
var elapsed := 0.0
var gesture_wait := 0.0
var gesture_age := -1.0
var first_invite_pending := true
var voice_played := false
var bone_ids := {}
var base_poses := {}
const WAIT_BEFORE_INVITE := 2.5
const INVITE_INTERVAL := 5.8
const INVITE_LENGTH := 1.5

func setup(owner_game: Node3D, owner_actor: Node3D, owner_skeleton: Skeleton3D, model: Node3D) -> void:
	game = owner_game
	actor = owner_actor
	skeleton = owner_skeleton
	process_priority = 100
	for candidate in model.find_children("*", "AnimationPlayer", true, false):
		animator = candidate
		break
	for bone_name in ["beckon_upper", "beckon_forearm", "beckon_hand"]:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			bone_ids[bone_name] = index
			base_poses[bone_name] = skeleton.get_bone_pose_rotation(index)
	if animator:
		# The supplied authored idle is the first imported clip and keeps running.
		for clip in animator.get_animation_list():
			if clip == "RESET":
				continue
			animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			animator.play(clip)
			break

func _process(delta: float) -> void:
	_tick(delta)

func _tick(delta: float) -> void:
	if paused or not is_instance_valid(game) or not is_instance_valid(actor) or not is_instance_valid(skeleton):
		return
	var eligible: bool = game.phase == "news" and game.sequence_id.is_empty() and not game.transitioning and not game.hud.menu.visible and actor.visible
	if not eligible:
		if engaged:
			engaged = false
			elapsed = 0.0
			gesture_wait = 0.0
			gesture_age = -1.0
			_restore_arm_pose()
		return
	if not engaged:
		engaged = true
		elapsed = 0.0
		gesture_wait = 0.0
		gesture_age = -1.0
		first_invite_pending = true
	elapsed += delta
	_face_player(delta)
	if gesture_age >= 0.0:
		gesture_age += delta
		if gesture_age >= INVITE_LENGTH:
			gesture_age = -1.0
			gesture_wait = 0.0
	else:
		gesture_wait += delta
		if elapsed >= WAIT_BEFORE_INVITE and (first_invite_pending or gesture_wait >= INVITE_INTERVAL):
			gesture_age = 0.0
			first_invite_pending = false
			_play_first_invitation_voice()
	_apply_invitation()

func _play_first_invitation_voice() -> void:
	if voice_played:
		return
	voice_played = true
	if not is_instance_valid(game) or not is_instance_valid(actor) or not is_instance_valid(game.audio):
		return
	var voice: Node = game.audio.play("vo_mordecai_smile", -13.0, actor.global_position, "Voice")
	if voice is AudioStreamPlayer3D:
		voice.max_distance = 60.0
		voice.unit_size = 12.0

func _face_player(delta: float) -> void:
	var direction: Vector3 = game.player.global_position - actor.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return
	# The imported stage models face local +Z; update_staging uses PI to face
	# away from the arena approach, so target the same local forward convention.
	var target_yaw := atan2(direction.x, direction.z)
	actor.rotation.y = lerp_angle(actor.rotation.y, target_yaw, 1.0 - exp(-2.2 * delta))

func _apply_invitation() -> void:
	if gesture_age < 0.0:
		_restore_arm_pose()
		return
	var raise_in := smoothstep(0.0, 0.42, gesture_age)
	var settle := 1.0 - smoothstep(1.05, INVITE_LENGTH, gesture_age)
	var amount := raise_in * settle
	# Lift the forearm with a restrained elbow bend, then turn the palm twice.
	_set_bone_delta("beckon_upper", Vector3.BACK, 0.10 * amount)
	_set_bone_delta("beckon_forearm", Vector3.BACK, 1.12 * amount)
	var wave := sin(maxf(0.0, gesture_age - 0.35) * TAU * 1.45) * 0.34 * amount
	_set_bone_delta("beckon_hand", Vector3.UP, wave)

func _set_bone_delta(bone_name: String, world_axis: Vector3, angle: float) -> void:
	if not bone_ids.has(bone_name):
		return
	var index: int = bone_ids[bone_name]
	var rest_basis := skeleton.get_bone_global_rest(index).basis.orthonormalized()
	var local_axis := (rest_basis.inverse() * world_axis).normalized()
	var base: Quaternion = base_poses[bone_name]
	skeleton.set_bone_pose_rotation(index, base * Quaternion(local_axis, angle))

func _restore_arm_pose() -> void:
	for bone_name in bone_ids:
		skeleton.set_bone_pose_rotation(bone_ids[bone_name], base_poses[bone_name])

func set_paused(value: bool) -> void:
	paused = value
	if animator:
		animator.speed_scale = 0.0 if value else 1.0

func reset_attention() -> void:
	engaged = false
	elapsed = 0.0
	gesture_wait = 0.0
	gesture_age = -1.0
	first_invite_pending = true
	voice_played = false
	_restore_arm_pose()
	if is_instance_valid(actor):
		actor.rotation.y = PI
	if animator:
		animator.speed_scale = 0.0 if paused else 1.0
