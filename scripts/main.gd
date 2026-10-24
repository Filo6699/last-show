extends Node3D
## Continuous chapter: arena, dressing room, service corridor and clinic.
const DATABASE = preload("res://scripts/story_database.gd")
const INTERACTABLE = preload("res://scripts/interactable.gd")
const SAVE_PATH := "user://chapter_one.json"
const SETTINGS_PATH := "user://settings.json"
const AUDIO_ENABLED := true
const layout = preload("res://scripts/chapter_layout.gd")
const VALID_PHASES := ["intro", "news", "to_dressing", "mirror", "elsa_dressing", "to_hall", "lili", "bruno", "elsa_hall", "to_technical", "technical", "photos", "walter", "contract", "roof_key", "return_arena", "roof_access", "roof", "home", "bathroom", "trapped", "captured", "complete"]
@onready var world: Node3D = $World
@onready var model: Node3D = $World/CircusLayout/Model
@onready var player = $Player
@onready var hud = $HUD
var database := DATABASE.new()
var phase := "intro"
var flags: Dictionary = {}
var sequence_id := ""
var node_id := ""
var line: Dictionary = {}
var dialogue_portrait := ""
var scene_timer: Timer
var mirror_gaze_time := 0.0
var clinic_photo: Node3D
var photo_comparison := ""
var actors: Dictionary = {}
var targets: Dictionary = {}
var target_id := ""
var transitioning := false
var typing_paused := false
var session := 0
var menu_kind := "main"
var save_path := SAVE_PATH
var audio: Node
var autosave_elapsed := 0.0
var actor_tween: Tween
var camera_tween: Tween
var mirror_system: Node3D
var location: Node3D
var full_game: Node3D
var glimpse_node: Node3D
var glimpse_tween: Tween
var elsa_rope: MeshInstance3D
var last_safe_position := Vector3(-3, .05, 3)

func _ready() -> void:
	scene_timer = Timer.new()
	scene_timer.one_shot = true
	scene_timer.timeout.connect(func():
		if not sequence_id.is_empty() and line.get("presentation", "") == "scene":
			advance_dialogue())
	add_child(scene_timer)
	AudioServer.set_bus_mute(0, not AUDIO_ENABLED)
	configure_input()
	if OS.has_feature("mobile"):
		get_window().size_changed.connect(configure_render_budget)
		configure_render_budget()
	var doctor := StaticBody3D.new()
	doctor.name = "Walter"
	doctor.set_script(INTERACTABLE)
	doctor.interaction_id = &"walter"
	doctor.prompt = "Поговорить с Вальтером"
	world.add_child(doctor)
	var doctor_shape := CollisionShape3D.new()
	doctor_shape.name = "CollisionShape3D"
	doctor.add_child(doctor_shape)
	for id in ["mordecai", "bruno", "lili", "elsa", "walter"]:
		var actor: StaticBody3D = world.get_node(id.capitalize())
		actors[id] = actor
		targets[id] = [actor]
		actor.interacted.connect(on_interact)

	stage_existing_props()
	location = Node3D.new()
	location.set_script(preload("res://scripts/location.gd"))
	world.add_child(location)
	location.setup(self)
	for id in actors: location.actor_visual(id, actors[id])
	elsa_rope = actors["elsa"].get_node("Suspension")
	mirror_system = preload("res://scripts/mirrors.gd").new()
	world.add_child(mirror_system)
	mirror_system.setup(self)
	full_game=preload("res://scripts/full_game.gd").new()
	world.add_child(full_game);full_game.setup(self)
	clinic_photo = preload("res://scripts/clinic_photo_reveal.gd").new()
	clinic_photo.setup(self)
	var outline := preload("res://scripts/focus_outline.gd").new()
	add_child(outline);outline.setup(self)
	hud.interaction_requested.connect(player.interact)
	hud.advance_requested.connect(advance_dialogue)
	hud.choice_selected.connect(select_choice)
	hud.menu_action.connect(on_menu_action)
	hud.settings_changed.connect(apply_settings)
	player.focus_changed.connect(hud.set_hint)
	hud.touch.move_changed.connect(func(value: Vector2): player.touch_move = value)
	hud.touch.look_changed.connect(func(value: Vector2): player.look(value * hud.sensitivity))
	audio = preload("res://scripts/chapter_audio.gd").new()
	add_child(audio)
	audio.setup(self)
	load_settings()
	update_staging()
	player.set_locked(true)
	hud.show_menu("main", read_save().size() > 0)

func configure_render_budget() -> void:
	# Limit only 3D pixel work on high-DPI phones; dialogue and touch UI stay native.
	var pixels := Vector2(get_window().size)
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = minf(1.0, minf(1280.0 / maxf(1.0, pixels.x), 720.0 / maxf(1.0, pixels.y)))

func configure_input() -> void:
	var bindings := {"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"interact": [KEY_E], "pause": [KEY_ESCAPE]}
	for action in bindings:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func stage_existing_props() -> void:
	# Bind the source props at their authored positions; never relocate the meshes.
	var crate: Node3D = model.find_child("StoryTrunk",true,false)
	if crate == null: crate = model.find_child("Crate 2.001",true,false)
	if crate:crate.set_meta("dynamic_set",true)
	for mesh_name in ["Mirror Frame", "Mirror surface", "Cylinder_009", "Cylinder_008"]:
		bind_imported(mesh_name, "mirror", "Посмотреть на своё отражение")
	# The trunk stays in the arena centre; approaching it triggers Lili's reveal.
	if not crate:
		push_error("Missing the existing imported magic box")

func bind_imported(mesh_name: String, id: String, prompt: String) -> void:
	for body in model.get_node("GeometryCollisions").get_children():
		if String(body.get_meta("source_mesh", "")) == mesh_name:
			body.set_script(INTERACTABLE)
			body.interaction_id = StringName(id)
			var source := model.find_child(mesh_name, true, false) as MeshInstance3D
			if source:
				body.set_meta("focus_point", body.to_local(source.to_global(source.get_aabb().get_center())))
			body.prompt = prompt
			body.interacted.connect(on_interact)
			if not targets.has(id): targets[id] = []
			targets[id].append(body)

func _process(delta: float) -> void:
	if actors["elsa"].visible:
		var ceiling: float = 8.0 if room_at(actors["elsa"].position)=="dressing" else 20.0
		var length: float = maxf(.05,ceiling-actors["elsa"].position.y-.75)
		# Keep the authored cylinder; stretch its instance instead of rebuilding mesh buffers.
		elsa_rope.scale.y = length / elsa_rope.mesh.height
		elsa_rope.position = Vector3(0,.75+length/2,0)
	if not player.locked and not transitioning:
		check_walk_progress()
		check_mirror_gaze(delta)
	if not player.locked and not sequence_id.is_empty():
		player.set_locked(true)
	autosave_elapsed += delta
	if autosave_elapsed > 8 and not player.locked and not transitioning:
		autosave_elapsed = 0
		save_game()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		on_menu_action("resume" if hud.menu.visible and menu_kind == "pause" else "pause")
		get_viewport().set_input_as_handled()
	elif hud.dialog.visible and not hud.menu.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_E]:
			if hud.line_ready: audio.ui()
			hud.advance()
			get_viewport().set_input_as_handled()

func new_game() -> void:
	session += 1
	transitioning = false
	stop_effects()
	full_game.reset_new_run()
	flags.clear()
	sequence_id = ""
	node_id = ""
	phase = "intro"
	hud.close_dialog()
	hud.hide_menu()
	hud.fade.hide()
	hud.set_story_mode("")
	menu_kind = ""
	place_player(Vector3(0, .36, -5.8), Vector3(0, 1.35, 6.6))
	update_staging()
	start_dialogue("intro")

func place_player(position: Vector3, facing: Vector3) -> void:
	if camera_tween: camera_tween.kill()
	player.camera.position = Vector3(0, 1.55, 0)
	player.position = position
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.look_at(Vector3(facing.x, position.y, facing.z))
	player.camera.look_at(facing)

func on_interact(id: StringName) -> void:
	if player.locked or transitioning or hud.menu.visible: return
	if is_instance_valid(full_game) and full_game.interact(id):return
	match String(id):
		"mordecai":
			if phase == "news": start_dialogue("mordecai_news")
			elif phase == "bruno": start_dialogue("mordecai_bruno")
			else: audio.emote("mordecai_smile")
		"bruno":
			if phase == "bruno": start_dialogue("mordecai_bruno")
			else: audio.emote("bruno_mgm")
		"mirror":
			if phase == "mirror": start_dialogue("mirror")
		"elsa":
			if phase in ["intro", "news", "to_dressing", "mirror"]: return
			if phase == "elsa_dressing": start_dialogue("elsa_dressing")
			elif phase == "elsa_hall": start_dialogue("elsa_hall")
			else: audio.emote("elsa_sigh")
		"dressing":
			if phase not in ["intro", "news"] and not flags.get("dressing_open",false):
				flags["dressing_open"] = true
				location.sync();sound("curtain");save_game()
			elif not flags.get("dressing_open", false): sound("curtain")
		"hall":
			pass
		"technical":
			if phase in ["elsa_hall","to_technical","return_arena","roof_access"] and not flags.get("service_open",false):
				var needs_pick: bool = phase in ["return_arena", "roof_access"]
				if needs_pick and not flags.get("hairpin",false):
					hud.show_notice("Дверь заперта.");return
				flags["service_open"] = true
				location.sync()
				sound("unlock" if needs_pick else "service_open")
				save_game()
			elif not flags.get("service_open",false):
				sound("locked")
				hud.show_notice("Замок закрыт. Нужен способ открыть его.")
		"photos": enter_photo_inspection()
		"photo_bruno", "photo_elsa", "photo_lili": inspect_photo(String(id).trim_prefix("photo_"))
		"photo_child": clinic_photo.interact()

func enter_photo_inspection() -> void:
	if phase != "photos": return
	scene_timer.stop()
	sequence_id = ""; node_id = ""; line = {}
	photo_comparison = ""
	hud.close_dialog()
	player.set_locked(false)

func inspect_photo(id: String) -> void:
	if phase != "photos" or transitioning: return
	photo_comparison = id
	player.set_locked(true)
	hud.show_line("", "", null, [])
	hud.show_photo_pair(database.get_photo(id, true))
	flags["photo_seen_" + id] = true
	save_game()

func check_walk_progress() -> void:
	var p: Vector3 = player.position
	if is_instance_valid(full_game):full_game.check_walk_progress()
	# Physical walls do the blocking. This recovers corrupted/old saves and falls.
	if not is_inside_location(p) or p.y < -2:
		place_player(last_safe_position, last_safe_position + Vector3(0, 1.5, -1))
		return
	if player.is_on_floor(): last_safe_position = p
	if phase == "to_dressing" and Vector2(p.x+48.1356,p.z-40.1154).length()<9.0:
		phase = "mirror"
		update_staging()
		save_game()
	elif phase == "to_hall" and Vector2(p.x-layout.TRUNK.x,p.z-layout.TRUNK.z).length()<4.0:
		begin_lili_reveal()
	elif phase in ["elsa_hall","to_technical"] and flags.get("service_open",false) and p.z > layout.SERVICE_START+.5 and room_at(p)=="service":
		phase = "technical"
		update_staging()
	if phase == "technical":
		if p.z > layout.SERVICE_START+2 and not flags.get("knock_front",false):
			flags["knock_front"] = true
			sound("knock_front")
		if p.z > layout.SERVICE_START+4.5 and not flags.get("knock_behind",false):
			flags["knock_behind"] = true
			sound("knock_back")
		if p.z > layout.CLINIC_START+.4:
			phase = "photos"
			update_staging()
			if not flags.get("corridor_scare", false):
				flags["corridor_scare"] = true
				show_lili_glimpse()
				sound("lili_glimpse")
			save_game()

func is_inside_location(p: Vector3) -> bool:
	if is_instance_valid(full_game) and full_game.contains(p):return true
	return layout.contains(p)

func room_at(p: Vector3) -> String:
	if is_instance_valid(full_game):
		var late_room:String=full_game.room_at(p)
		if not late_room.is_empty():return late_room
	return layout.room_at(p)

func check_mirror_gaze(delta: float) -> void:
	# The screenplay starts the reflection when the player actually looks into
	# the glass. A short dwell allows looking around without a forced cut.
	if phase != "mirror" or player.locked or transitioning or hud.menu.visible:
		mirror_gaze_time = 0
		return
	var eye: Vector3 = player.camera.global_position
	var forward: Vector3 = -player.camera.global_basis.z
	var looking := false
	for mirror in mirror_system.mirrors:
		var offset: Vector3 = mirror.center - eye
		if offset.length_squared() > 4.6 * 4.6 or offset.length_squared() < .01: continue
		if forward.dot(offset.normalized()) < .965: continue
		if not mirror_system.surface_visible(mirror, player.camera, 4.6): continue
		# Use the real interaction's occlusion test; no scene through a wall.
		if is_instance_valid(player.focus) and player.focus.interaction_id == &"mirror":
			looking = true
			break
	mirror_gaze_time = mirror_gaze_time + delta if looking else 0.0
	if mirror_gaze_time >= .8:
		mirror_gaze_time = 0
		start_dialogue("mirror")

func start_dialogue(id: String) -> void:
	if id == "photos":
		enter_photo_inspection()
		return
	scene_timer.stop()
	sequence_id = id
	node_id = database.get_sequence(id)["start"]
	dialogue_portrait = ""
	hud.clear_portrait()
	player.set_locked(true)
	display_line()

func display_line() -> void:
	if sequence_id == "photos":
		var old_photo := node_id.trim_suffix("_photo")
		enter_photo_inspection()
		if old_photo in ["bruno", "elsa", "lili"]: inspect_photo(old_photo)
		return
	scene_timer.stop()
	var nodes: Dictionary = database.get_sequence(sequence_id)["nodes"]
	if node_id == "end":
		finish_dialogue()
		return
	line = nodes[node_id].duplicate(true)
	for choice in line.get("choices",[]):
		for flag in choice.get("requires",{}):
			if flags.get(flag,false)!=choice.requires[flag]:choice["disabled"]=true
	if sequence_id == "mirror": mirror_system.begin_scene()
	var who: String = line.get("speaker", "narrator")
	var background := who in ["richard", "narrator"] and not line.has("portrait")
	if not background:
		var portrait_id: String = line.get("portrait", who)
		dialogue_portrait = portrait_id if database.get_portrait(portrait_id) != null else ""
	var scene: bool = line.get("presentation", "") == "scene"
	if scene:
		hud.close_dialog()
		hud.touch.hide()
		hud.crosshair.hide()
	else:
		hud.set_voice(who)
		hud.show_line(database.speaker_name(who, flags.get("richard_name_seen", false)), line.get("text", ""), database.get_portrait(dialogue_portrait), line.get("choices", []), float(line.get("pause", 0)), "background" if background else "speaker")
	if sequence_id == "photos" and node_id.ends_with("_photo"):
		var id := node_id.trim_suffix("_photo")
		hud.show_photo_pair(database.get_photo(id,true))
	if sequence_id == "photos" and node_id == "2": sound("photo_take")
	var emotes := {"mordecai_news:0":"mordecai_smile", "mordecai_news:3":"mordecai_laugh", "lili:0":"lili_giggle", "elsa_dressing:0":"elsa_sigh", "mordecai_bruno:0":"bruno_da", "mordecai_bruno:2":"bruno_mgm", "mordecai_bruno:4":"richard_uh", "walter_arrival:1":"walter_hm"}
	var emote_key := sequence_id+":"+node_id
	if is_instance_valid(audio) and emotes.has(emote_key): audio.emote(emotes[emote_key])
	run_event(line.get("event", ""))
	if scene:
		scene_timer.start(maxf(.1, float(line.get("duration", 1.2))))
	save_game()

func advance_dialogue() -> void:
	if not photo_comparison.is_empty() and not hud.menu.visible:
		photo_comparison = ""
		hud.close_dialog()
		player.set_locked(false)
		return
	if sequence_id.is_empty() or hud.menu.visible or transitioning or not line.get("choices", []).is_empty(): return
	node_id = line.get("next", "end")
	display_line()

func select_choice(index: int) -> void:
	if sequence_id.is_empty() or hud.menu.visible or transitioning: return
	var options: Array = line.get("choices", [])
	if index < 0 or index >= options.size(): return
	var option: Dictionary = options[index]
	if option.get("disabled",false):
		hud.show_notice("Нужен нож из коробки в манеже.");return
	flags.merge(option.get("set", {}), true)
	node_id = option["next"]
	display_line()

func finish_dialogue() -> void:
	scene_timer.stop()
	var finished := sequence_id
	sequence_id = ""
	node_id = ""
	line = {}
	dialogue_portrait = ""
	hud.close_dialog()
	if is_instance_valid(full_game) and full_game.finish_dialogue(finished):return
	match finished:
		"intro":
			location.stage_show.finish_opening()
			phase = "news"
			begin_backstage_exploration()
			return
		"mordecai_news":
			phase = "to_dressing"
			hud.show_notice("Грим стянул кожу. Смыть бы.")
		"mirror":
			mirror_system.end_scene()
			phase = "elsa_dressing"
			sound("rigging")
		"elsa_dressing": phase = "to_hall"
		"lili":
			phase = "bruno"
		"mordecai_bruno": phase = "elsa_hall"
		"elsa_hall": phase = "to_technical"
		"technical":
			phase = "photos"
			hud.set_story_mode("")
			update_staging()
			enter_photo_inspection()
			return
		"photos":
			enter_photo_inspection()
			return
	update_staging()
	save_game()
	player.set_locked(hud.menu.visible)

func begin_backstage_exploration() -> void:
	# The screenplay cuts from the performance to backstage. Start free roam
	# within sight and earshot of the cast, with room to investigate the props.
	# All furnishings and NPC anchors keep their existing authored positions.
	transitioning = true
	flags["opening_exit_pending"] = true
	player.set_locked(true)
	var token := session
	save_game()
	await hud.transition_out()
	if token != session: return
	place_player(Vector3(-8, .05, 18), Vector3(-8, 1.6, 30))
	last_safe_position = player.position
	update_staging()
	await hud.transition_in()
	if token != session: return
	flags.erase("opening_exit_pending")
	transitioning = false
	player.set_locked(false)
	save_game()

func update_staging() -> void:
	for id in actors:
		var show_actor: bool = (id == "mordecai" and phase not in ["technical", "photos", "walter", "complete"]) or (id == "bruno" and phase not in ["technical", "photos", "walter", "complete"]) or (id == "elsa" and phase not in ["technical", "photos", "walter", "complete"]) or (id == "lili" and phase == "lili" and flags.get("lili_visible", false)) or (id == "walter" and phase in ["technical", "photos", "walter","complete"])
		actors[id].visible = show_actor
		var can_interact: bool = show_actor and not (id == "elsa" and phase in ["intro", "news", "to_dressing", "mirror"])
		actors[id].collision_layer = 1 if can_interact else 0
	location.move_actor("mordecai", layout.HALL_MORDECAI if phase not in ["intro", "news"] else layout.ARENA_MORDECAI, 6.0)
	actors["mordecai"].prompt = "Обсудить крышу с Мордекаем" if phase == "bruno" else "Поговорить с Мордекаем"
	actors["bruno"].prompt = "Обсудить крышу с Бруно" if phase == "bruno" else "Поговорить с Бруно"
	actors["bruno"].position = layout.BRUNO
	location.move_actor("elsa", layout.ELSA_HALL if phase in ["lili", "bruno", "elsa_hall", "to_technical"] else layout.ELSA_DRESSING + Vector3(0,0 if phase in ["elsa_dressing", "to_hall"] else 2.2,0), 2.0)
	var doctor_position: Array = flags.get("walter_position", [layout.WALTER_WAIT.x, layout.WALTER_WAIT.y, layout.WALTER_WAIT.z])
	actors["walter"].position = Vector3(doctor_position[0], doctor_position[1], doctor_position[2])
	actors["mordecai"].rotation.y = PI if phase in ["intro","news"] else -.35
	actors["bruno"].rotation.y = PI-.5
	actors["lili"].rotation.y = 0
	if phase == "lili" and flags.get("lili_visible", false) and not flags.get("lili_reveal_pending", false):
		actors["lili"].position = layout.LILI
		actors["lili"].look_at(Vector3(player.position.x, actors["lili"].position.y, player.position.z), Vector3.UP, true)
	actors["elsa"].rotation.y = 1.8 if phase in ["lili","bruno","elsa_hall","to_technical"] else PI
	actors["walter"].rotation.y = float(flags.get("walter_yaw", PI))
	if is_instance_valid(location): location.sync()
	if is_instance_valid(clinic_photo): clinic_photo.sync()
	var notes := {
		"intro": ["ПОСЛЕДНЕЕ ПРЕДСТАВЛЕНИЕ", ""],
		"news": ["ЗА КУЛИСАМИ", ""],
		"to_dressing": ["ЗА КУЛИСАМИ", "Вернуться в гримёрную."],
		"mirror": ["ГРИМЁРНАЯ", ""],
		"elsa_dressing": ["ГРИМЁРНАЯ", ""],
		"to_hall": ["ГРИМЁРНАЯ", "Найти ключ от двери на крышу."],
		"lili": ["МАНЕЖ", ""],
		"bruno": ["МАНЕЖ", ""],
		"elsa_hall": ["МАНЕЖ", "Найти доктора Вальтера."],
		"to_technical": ["МАНЕЖ", "Найти доктора Вальтера."],
		"technical": ["СЛУЖЕБНЫЙ КОРИДОР", "Найти доктора Вальтера."],
		"photos": ["КАБИНЕТ", ""],
		"walter": ["КАБИНЕТ", ""],
		"complete": ["КОНЕЦ ГЛАВЫ", ""]}
	var info: Array = notes.get(phase,full_game.objective(phase) if is_instance_valid(full_game) else ["LAST SHOW",""])
	hud.set_objective(info[0], info[1], flags.get("hairpin", false))
	if is_instance_valid(full_game):full_game.sync()

func run_event(event: String) -> void:
	if is_instance_valid(full_game) and full_game.event(event):return
	match event:
		"applause":
			sound("applause")
			location.opening_action(flags.get("opening_action", "bow"))
		"roof_crack":
			sound("crack")
			location.roof_crack()
			shake_camera(0.05)
		"audience": sound("audience")
		"mirror_empty":
			flags["reflection_restored"] = false
			sound("mirror_empty")
		"mirror_scare":
			flags["reflection_restored"] = true
			hud.scare()
			sound("mirror_smile")
			shake_camera(0.09)
		"lili_appears":
			# Legacy saves can still enter node 0 directly; never replay the jump under UI.
			flags["lili_visible"] = true
			update_staging()
		"lili_leaves":
			flags["richard_name_seen"] = true
			flags["lili_visible"] = false
			update_staging()
			var lili: Node3D = actors["lili"]
			lili.position = layout.LILI
			lili.show()
			lili.collision_layer = 0
			var away := layout.LILI + Vector3(-4.5, 0, -3)
			lili.look_at(Vector3(away.x, lili.position.y, away.z), Vector3.UP, true)
			if actor_tween: actor_tween.kill()
			actor_tween = create_tween()
			actor_tween.tween_property(lili, "position", away, 1.1)
			actor_tween.tween_callback(lili.hide)
			var nameplate: MeshInstance3D = model.find_child("Trunk name", true, false)
			if nameplate:
				frame_player_at(nameplate.to_global(nameplate.get_aabb().get_center()), .5)
		"hairpin_received":
			flags["hairpin"] = true
			sound("hairpin")
			update_staging()
		"technical_begin": audio.flicker()
		"knock_front": sound("knock_front")
		"knock_behind": sound("knock_back")
		"lili_silhouette":
			show_lili_glimpse()
			sound("lili_glimpse")
		"photo_take": sound("photo_take")
		"show_photos": frame_player_at(layout.PHOTOS, .35)
		"richard_photo":
			clinic_photo.reveal_child()
			frame_player_at(clinic_photo.photo_card.global_position, .4)
			sound("richard_photo")
		"photo_falls":
			clinic_photo.drop_photo()
			frame_player_at(clinic_photo.landing_position(), .5)
			sound("photo_drop")
		"walter_turn":
			var initial: Quaternion = player.camera.quaternion
			player.camera.look_at(actors["walter"].global_position+Vector3(0,.65,0))
			var target: Quaternion = player.camera.quaternion
			player.camera.quaternion = initial
			if camera_tween: camera_tween.kill()
			camera_tween = create_tween()
			camera_tween.tween_property(player.camera,"quaternion",target,.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		"walter_appears":
			update_staging()
			hud.show_caption("")


func shake_camera(strength: float) -> void:
	var initial: Vector3 = player.camera.position
	if camera_tween: camera_tween.kill()
	camera_tween = create_tween()
	for offset in [Vector3(strength, 0, 0), Vector3(-strength, strength, 0), Vector3.ZERO]:
		camera_tween.tween_property(player.camera, "position", initial + offset, 0.09)

func sound(id: String) -> void:
	if is_instance_valid(audio): audio.cue(id)

func on_menu_action(action: String) -> void:
	match action:
		"new_game": new_game()
		"continue": load_game()
		"pause":
			if (transitioning and not flags.get("photo_reveal_pending", false)) or hud.menu.visible: return
			menu_kind = "pause"
			location.pause_motion(true)
			full_game.pause_motion(true)
			if is_instance_valid(clinic_photo.transition) and clinic_photo.transition.is_valid(): clinic_photo.transition.pause()
			audio.set_paused(true)
			typing_paused = hud.text_tween != null and hud.text_tween.is_valid() and hud.text_tween.is_running()
			if typing_paused: hud.text_tween.pause()
			hud.pause_portrait(true)
			hud.pause_timer.paused=true
			scene_timer.paused = true
			player.set_locked(true)
			hud.show_menu("pause")
			save_game()
		"resume":
			location.pause_motion(false)
			full_game.pause_motion(false)
			if is_instance_valid(clinic_photo.transition) and clinic_photo.transition.is_valid(): clinic_photo.transition.play()
			audio.set_paused(false)
			if typing_paused and hud.text_tween and hud.text_tween.is_valid(): hud.text_tween.play()
			typing_paused=false
			hud.pause_portrait(false)
			hud.pause_timer.paused=false
			scene_timer.paused = false
			hud.hide_menu()
			if line.get("presentation", "") == "scene" or transitioning:
				hud.touch.hide()
				hud.crosshair.hide()
			menu_kind = ""
			player.set_locked(not sequence_id.is_empty() or transitioning or not photo_comparison.is_empty())
		"main_menu":
			save_game()
			stop_effects()
			session += 1
			transitioning = false
			hud.fade.hide()
			menu_kind = "main"
			player.set_locked(true)
			hud.show_menu("main", not read_save().is_empty())
		"settings_back": hud.show_menu(menu_kind, menu_kind == "main" and not read_save().is_empty())
		"endings":hud.show_endings(full_game.unlocked(),full_game.ENDINGS)
		"quit":
			if menu_kind != "main": save_game()
			get_tree().quit()

func save_game() -> void:
	if phase == "walter" and transitioning:
		var at: Vector3 = actors["walter"].position
		flags["walter_position"] = [at.x, at.y, at.z]
		flags["walter_yaw"] = actors["walter"].rotation.y
	var data := {"version": 1, "layout": layout.ID, "phase": phase, "flags": flags, "sequence": sequence_id, "node": node_id,
		"dialogue_portrait": dialogue_portrait,
		"position": [player.position.x, player.position.y, player.position.z], "yaw": player.rotation.y, "pitch": mirror_system.saved_rotation.get_euler().x if mirror_system.cinematic else (location.stage_show.neutral_pitch if location.stage_show.view_active else player.camera.rotation.x)}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(data))

func read_save() -> Dictionary:
	if not FileAccess.file_exists(save_path): return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary or data.get("version") != 1 or not data.get("phase", "") in VALID_PHASES or not data.get("flags", {}) is Dictionary: return {}
	var seq: String = data.get("sequence", "")
	if not seq.is_empty():
		if not database.sequences.has(seq) or not database.get_sequence(seq)["nodes"].has(data.get("node", "")): return {}
	return data

func load_game() -> void:
	var data := read_save()
	if data.is_empty():
		new_game()
		return
	stop_effects()
	photo_comparison = ""
	session += 1
	transitioning = false
	player.camera.position = Vector3(0, 1.55, 0)
	phase = data["phase"]
	flags = data["flags"]
	sequence_id = data.get("sequence", "")
	node_id = data.get("node", "")
	dialogue_portrait = str(data.get("dialogue_portrait", database.preceding_portrait(sequence_id, node_id)))
	if not database.portraits.has(dialogue_portrait): dialogue_portrait = ""
	# Lili's name reveal is already behind all of these phases, including old
	# saves in the current layout which did not yet persist the reveal flag.
	if phase in ["bruno", "elsa_hall", "to_technical", "technical", "photos", "walter", "contract", "roof_key", "return_arena", "roof_access", "roof", "home", "bathroom", "trapped", "captured", "complete"]:
		flags["richard_name_seen"] = true
	# Earlier builds ended at Walter's first greeting. Continue those saves at
	# the contract rather than treating the former chapter stop as an ending.
	if phase=="complete" and not flags.has("ending_id"):
		phase="contract";sequence_id="walter_contract";node_id="0"
		flags["richard_name_seen"]=true
	var position: Array = data.get("position", [-34, 0.05, 38.7])
	if position.size() != 3: position = [-34, 0.05, 38.7]
	player.position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	player.rotation = Vector3(0, float(data.get("yaw", 0)), 0)
	player.camera.rotation = Vector3(clampf(float(data.get("pitch", 0)), -1.35, 1.35), 0, 0)
	player.velocity = Vector3.ZERO
	if data.get("layout", "") != layout.ID or not is_inside_location(player.position):
		if phase in ["bruno","elsa_hall","to_technical","technical","photos","walter","contract","roof_key","return_arena","roof_access"]:flags["richard_name_seen"]=true
		flags.erase("walter_position")
		flags.erase("walter_yaw")
		var at := layout.safe_position(phase)
		if phase in ["technical","photos","walter","contract","roof_key","complete"]: flags["service_open"] = true
		place_player(at, at+Vector3(0,1.5,-1))
	player.position=full_game.set_dressing.arena_details.safe_saved_position(player.position)
	last_safe_position = player.position
	hud.hide_menu()
	hud.close_dialog()
	hud.fade.hide()
	hud.set_story_mode("")
	menu_kind = ""
	update_staging()
	if phase == "complete":
		var ending:String=flags.get("ending_id","")
		if full_game.ENDINGS.has(ending):
			hud.ending_title=full_game.ENDINGS[ending][0];hud.ending_description=full_game.ENDINGS[ending][1]
			full_game.restore_ending(ending)
		menu_kind = "end"
		hud.show_menu("end")
	elif phase == "lili" and sequence_id.is_empty():
		begin_lili_reveal()
	elif phase == "walter" and sequence_id.is_empty():
		begin_walter_arrival()
	elif phase == "news" and sequence_id.is_empty() and flags.get("opening_exit_pending", false):
		begin_backstage_exploration()
	elif phase == "photos" and flags.get("richard_photo_fallen", false):
		flags.erase("photo_reveal_pending")
		begin_walter_arrival()
	elif phase == "photos" and flags.get("photo_reveal_pending", false):
		clinic_photo.interact()
	elif not sequence_id.is_empty():
		display_line()
		full_game.restore_dialogue_view()
	player.set_locked(hud.menu.visible or not sequence_id.is_empty() or transitioning)

func load_settings() -> void:
	var values = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH)) if FileAccess.file_exists(SETTINGS_PATH) else {}
	if not values is Dictionary: values = {}
	hud.volume = clampf(float(values.get("volume", 0.65)), 0, 1)
	hud.sensitivity = clampf(float(values.get("sensitivity", 1)), 0.4, 2.5)
	apply_settings(hud.volume, hud.sensitivity)

func apply_settings(volume: float, sensitivity: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	player.mouse_sensitivity = 0.0025 * sensitivity
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"volume": volume, "sensitivity": sensitivity}))

func stop_effects() -> void:
	photo_comparison = ""
	scene_timer.stop()
	scene_timer.paused = false
	mirror_gaze_time = 0
	if is_instance_valid(clinic_photo) and is_instance_valid(clinic_photo.transition): clinic_photo.transition.kill()
	typing_paused=false
	if glimpse_tween: glimpse_tween.kill()
	if is_instance_valid(glimpse_node): glimpse_node.queue_free()
	glimpse_node = null
	if is_instance_valid(location): location.reset_motion()
	if is_instance_valid(full_game):full_game.reset_motion()
	if is_instance_valid(mirror_system): mirror_system.end_scene()
	if actor_tween: actor_tween.kill()
	if camera_tween: camera_tween.kill()
	if is_instance_valid(audio): audio.reset()
	hud.pause_timer.paused=false
	hud.reset_effects()

func _exit_tree() -> void:
	if is_instance_valid(audio): audio.shutdown()
	for child in get_children():
		if child is AudioStreamPlayer: child.stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		if menu_kind != "main" and not transitioning: save_game()
		on_menu_action("pause")

func frame_player_at(point: Vector3, duration: float) -> void:
	var direction: Vector3 = point - player.camera.global_position
	var yaw := atan2(-direction.x, -direction.z)
	yaw = player.rotation.y + wrapf(yaw - player.rotation.y, -PI, PI)
	var pitch := atan2(direction.y, Vector2(direction.x, direction.z).length())
	if camera_tween: camera_tween.kill()
	camera_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	camera_tween.tween_property(player, "rotation:y", yaw, duration)
	camera_tween.tween_property(player.camera, "rotation", Vector3(pitch, 0, 0), duration)

func begin_lili_reveal() -> void:
	if transitioning: return
	phase = "lili"
	sequence_id = ""
	node_id = ""
	flags["lili_reveal_pending"] = true
	flags["lili_visible"] = false
	transitioning = true
	player.set_locked(true)
	hud.close_dialog()
	hud.touch.hide()
	hud.hint.hide()
	hud.crosshair.hide()
	update_staging()
	save_game()
	sound("box_first")
	frame_player_at(layout.TRUNK+Vector3(-.8,.6,.65), .45)
	var reveal_session := session
	if actor_tween: actor_tween.kill()
	actor_tween = create_tween()
	actor_tween.tween_interval(.5)
	actor_tween.tween_callback(func():
		if session != reveal_session: return
		flags["lili_visible"] = true
		var actor: Node3D = actors["lili"]
		actor.position = layout.TRUNK+Vector3(-.7,-.2,.8)
		actor.visible = true
		actor.collision_layer = 0
		actor.look_at(Vector3(player.position.x, actor.position.y, player.position.z), Vector3.UP, true)
		sound("box_second"))
	actor_tween.tween_property(actors["lili"], "position", layout.TRUNK+Vector3(-.7,1.65,.8), .35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	actor_tween.tween_property(actors["lili"], "position", layout.LILI, .4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	actor_tween.tween_interval(.45)
	actor_tween.tween_callback(func():
		if session != reveal_session: return
		flags["lili_reveal_pending"] = false
		transitioning = false
		update_staging()
		start_dialogue("lili"))

func find_clear_appearance_position(distance: float, height: float, radius: float, feet_y: float) -> Vector3:
	var eye: Vector3 = player.camera.global_position
	var forward: Vector3 = -player.camera.global_basis.z
	forward.y = 0
	if forward.length_squared() < .01: forward = -player.global_basis.z
	forward = forward.normalized()
	var excluded: Array[RID] = [player.get_rid(), actors["walter"].get_rid()]
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	# Ignore the thin sole/floor contact band while checking the full body footprint.
	capsule.height = height - .10
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = excluded
	query.margin = .025
	var ray := PhysicsRayQueryParameters3D.new()
	ray.from = eye
	ray.collision_mask = 1
	ray.exclude = excluded
	var space := get_world_3d().direct_space_state
	for reach in [distance, 1.05, 2.2, 2.8]:
		for angle in [0.0, PI/4, -PI/4, PI/2, -PI/2, 3*PI/4, -3*PI/4, PI]:
			var position: Vector3 = player.position + forward.rotated(Vector3.UP, angle) * reach
			position.y = feet_y
			query.transform = Transform3D(Basis.IDENTITY, position + Vector3(0, height/2, 0))
			if not space.intersect_shape(query, 1).is_empty(): continue
			ray.to = position + Vector3(0, height * .88, 0)
			if space.intersect_ray(ray).is_empty(): return position
	# The clinic has open floor; this last fallback is only for corrupted/outside saves.
	return Vector3(layout.CLINIC_CENTER.x, feet_y, layout.CLINIC_CENTER.z)

func begin_walter_arrival() -> void:
	phase = "walter"
	sequence_id = ""
	node_id = ""
	transitioning = true
	player.set_locked(true)
	hud.close_dialog()
	hud.touch.hide()
	hud.hint.hide()
	hud.crosshair.hide()
	var doctor: Node3D = actors["walter"]
	var start: Vector3 = doctor.position
	flags["walter_position"] = [start.x, start.y, start.z]
	update_staging()
	save_game()
	var entrance_session := session
	if actor_tween: actor_tween.kill()
	actor_tween = create_tween()
	# He has been standing in the clinic throughout inspection. Walk the open
	# central aisle from that existing position instead of spawning near the camera.
	var destination := Vector3(-21.0, .95, 56.4)
	if Vector2(destination.x-player.position.x,destination.z-player.position.z).length() < 1.1:
		destination = Vector3(-20.5,.95,55.6)
	var duration := maxf(.8, start.distance_to(destination) / .8)
	doctor.look_at(Vector3(destination.x, start.y, destination.z), Vector3.UP, true)
	actor_tween.tween_property(doctor, "position", destination, duration)
	actor_tween.tween_callback(func():
		if session != entrance_session: return
		flags["walter_position"] = [doctor.position.x, doctor.position.y, doctor.position.z]
		var toward_player: Vector3 = player.position - doctor.position
		flags["walter_yaw"] = atan2(toward_player.x, toward_player.z)
		doctor.rotation.y = flags["walter_yaw"]
		frame_player_at(doctor.global_position + Vector3(0, .72, 0), .55)
		sound("walter")
		transitioning = false
		start_dialogue("walter_arrival"))

func show_lili_glimpse() -> void:
	if glimpse_tween: glimpse_tween.kill()
	if is_instance_valid(glimpse_node): glimpse_node.queue_free()
	glimpse_node = load("res://assets/characters/models/lili.glb").instantiate()
	glimpse_node.name = "LiliGlimpse"
	world.add_child(glimpse_node)
	# If a wall blocks the viewing axis, choose the nearest clear angle inside the room.
	# Keep the head at eye level and frame it instead of spawning through that wall.
	glimpse_node.position = find_clear_appearance_position(1.35, 1.42, .25, maxf(.025, player.camera.global_position.y - 1.25))
	glimpse_node.look_at(Vector3(player.position.x, glimpse_node.position.y, player.position.z), Vector3.UP, true)
	frame_player_at(glimpse_node.position + Vector3(0, 1.25, 0), .20)
	for animator in glimpse_node.find_children("*", "AnimationPlayer", true, false):
		for clip in animator.get_animation_list():
			if clip != "RESET":
				animator.play(clip)
				break
	var glimpse_session := session
	var was_transitioning := transitioning
	transitioning = true
	player.set_locked(true)
	hud.touch.hide()
	glimpse_tween = create_tween()
	glimpse_tween.tween_interval(.85)
	glimpse_tween.tween_callback(func():
		if session != glimpse_session: return
		if is_instance_valid(glimpse_node): glimpse_node.queue_free()
		glimpse_node = null
		transitioning = was_transitioning
		player.set_locked(hud.menu.visible or not sequence_id.is_empty() or transitioning)
		hud.touch.visible = hud.touch_enabled and not hud.menu.visible and not hud.dialog.visible)
