extends Node3D
## Continuous chapter: arena, dressing room, service corridor and clinic.
const DATABASE = preload("res://scripts/story_database.gd")
const INTERACTABLE = preload("res://scripts/interactable.gd")
const SAVE_PATH := "user://chapter_one.json"
const SETTINGS_PATH := "user://settings.json"
const VALID_PHASES := ["intro", "news", "to_dressing", "mirror", "elsa_dressing", "to_hall", "lili", "bruno", "elsa_hall", "to_technical", "technical", "photos", "walter", "complete"]
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
var actors: Dictionary = {}
var targets: Dictionary = {}
var target_id := ""
var transitioning := false
var session := 0
var menu_kind := "main"
var save_path := SAVE_PATH
var ambience: AudioStreamPlayer
var autosave_elapsed := 0.0
var actor_tween: Tween
var camera_tween: Tween
var mirror_system: Node3D
var location: Node3D
var glimpse_node: Node3D
var glimpse_tween: Tween
var elsa_rope: MeshInstance3D
var last_safe_position := Vector3(-3, .05, 3)

func _ready() -> void:
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
	ambience = AudioStreamPlayer.new()
	ambience.stream = preload("res://assets/audio/ambience.wav")
	ambience.volume_db = -18
	add_child(ambience)
	ambience.finished.connect(ambience.play)
	ambience.play()
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
	# Relocate the artist's existing mirror and luggage into the story rooms.
	# Its imported collision has baked coordinates, so it receives the same delta.
	var crate: Node3D = model.get_node_or_null("Crate 2_001")
	if crate == null: crate = model.get_node_or_null("Crate 2.001")
	for mesh_name in ["Mirror Frame", "Mirror surface", "Cylinder_009", "Cylinder_008"]:
		bind_imported(mesh_name, "mirror", "Посмотреть на своё отражение")
	# The trunk is physical scenery: Lili reveals herself when Richard enters the hall.
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
		var ceiling: float = 3.59 if actors["elsa"].position.x < -11 else 6.8-2.3*absf(actors["elsa"].position.z)/8.0
		var length: float = maxf(.05,ceiling-actors["elsa"].position.y-.75)
		# Keep the authored cylinder; stretch its instance instead of rebuilding mesh buffers.
		elsa_rope.scale.y = length / elsa_rope.mesh.height
		elsa_rope.position = Vector3(0,.75+length/2,0)
	if not player.locked and not transitioning:
		check_walk_progress()
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
			hud.advance()
			get_viewport().set_input_as_handled()

func new_game() -> void:
	session += 1
	transitioning = false
	stop_effects()
	flags.clear()
	ambience.volume_db = -18
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
	match String(id):
		"mordecai":
			if phase == "news": start_dialogue("mordecai_news")
			elif phase == "bruno": start_dialogue("mordecai_bruno")
			else:
				var replies := {
					"to_dressing": "Твоя гримёрная за афишами. Занавес не заперт.",
					"mirror": "Ты грим так и не смыл. Зеркала в гримёрной.",
					"elsa_dressing": "Кажется, Эльза тебя звала. Она в гримёрной.",
					"to_hall": "Твоя коробка опять стучит. Проверь её, потом поговорим.",
					"lili": "Твоя коробка опять стучит. Проверь её, потом поговорим.",
					"elsa_hall": "Эльза у служебной двери. Спроси её о Вальтере.",
					"to_technical": "Кабинет Вальтера — в конце служебного коридора."}
				hud.show_notice(replies.get(phase, "Мы уже поговорили, Ричард."))
		"bruno":
			start_dialogue("mordecai_bruno" if phase == "bruno" else "bruno_idle")
		"mirror":
			if phase == "mirror": start_dialogue("mirror")
			else: hud.show_notice("Улыбка в зеркале исчезла.")
		"elsa":
			if phase in ["intro", "news", "to_dressing", "mirror"]: return
			if phase == "elsa_dressing": start_dialogue("elsa_dressing")
			elif phase == "elsa_hall": start_dialogue("elsa_hall")
			else: hud.show_notice("Слышишь? В твоей коробке кто-то шуршит. Она посреди манежа." if phase == "to_hall" else "Замок откроется невидимкой. Вальтер в конце коридора.")
		"dressing":
			if phase not in ["intro", "news"]:
				flags["dressing_open"] = true
				location.sync();sound("rigging");save_game()
			else: hud.show_notice("Мордекай окликает меня. Сначала выслушаю его.")
		"hall":
			pass
		"technical":
			if phase == "to_technical" and flags.get("hairpin", false):
				flags["service_open"] = true
				location.sync()
				sound("knock")
				save_game()
			else: hud.show_notice("Замок закрыт. Нужен способ открыть его.")
		"photos":
			if phase == "photos": start_dialogue("photos")

func check_walk_progress() -> void:
	var p: Vector3 = player.position
	# Physical walls do the blocking. This recovers corrupted/old saves and falls.
	if not is_inside_location(p) or p.y < -2:
		place_player(last_safe_position, last_safe_position + Vector3(0, 1.5, -1))
		return
	if player.is_on_floor(): last_safe_position = p
	if phase == "to_dressing" and p.x < -11.3:
		phase = "mirror"
		hud.show_notice("Смою грим… Постой. Где моё отражение?")
		update_staging()
	elif phase == "to_hall" and p.x > -7.6:
		begin_lili_reveal()
	elif phase == "to_technical" and flags.get("service_open",false) and p.x > 8.5:
		phase = "technical"
		update_staging()
	if phase == "technical":
		if p.x > 10 and not flags.get("knock_front",false):
			flags["knock_front"] = true
			sound("knock", -.8)
		if p.x > 12.5 and not flags.get("knock_behind",false):
			flags["knock_behind"] = true
			sound("knock", .8)
		if p.x > 16.4:
			phase = "photos"
			update_staging()
			if not flags.get("corridor_scare", false):
				flags["corridor_scare"] = true
				show_lili_glimpse()
				sound("sting")
			save_game()

func is_inside_location(p: Vector3) -> bool:
	return (p.x >= -8 and p.x <= 8 and p.z >= -8 and p.z <= 8) or (p.x >= -18 and p.x <= -11 and p.z >= -2 and p.z <= 6) or (p.x >= -11 and p.x <= 16 and p.z >= 1 and p.z <= 3.8) or (p.x >= 16 and p.x <= 22 and p.z >= -1 and p.z <= 6)

func start_dialogue(id: String) -> void:
	sequence_id = id
	node_id = database.get_sequence(id)["start"]
	player.set_locked(true)
	display_line()

func display_line() -> void:
	var nodes: Dictionary = database.get_sequence(sequence_id)["nodes"]
	if node_id == "end":
		finish_dialogue()
		return
	line = nodes[node_id]
	if sequence_id == "mirror": mirror_system.begin_scene()
	var who: String = line.get("speaker", "narrator")
	var portrait_id: String = line.get("portrait", who)
	hud.set_voice(who)
	hud.show_line(database.SPEAKERS.get(who, ""), line.get("text", ""), database.get_portrait(portrait_id), line.get("choices", []), float(line.get("pause", 0)))
	if sequence_id == "photos" and node_id.ends_with("_photo"):
		var id := node_id.trim_suffix("_photo")
		hud.show_photo_pair(database.get_photo(id,true), database.get_photo(id,false))
	run_event(line.get("event", ""))
	save_game()

func advance_dialogue() -> void:
	if sequence_id.is_empty() or hud.menu.visible or transitioning or not line.get("choices", []).is_empty(): return
	node_id = line.get("next", "end")
	display_line()

func select_choice(index: int) -> void:
	if sequence_id.is_empty() or hud.menu.visible or transitioning: return
	var options: Array = line.get("choices", [])
	if index < 0 or index >= options.size(): return
	var option: Dictionary = options[index]
	flags.merge(option.get("set", {}), true)
	node_id = option["next"]
	display_line()

func finish_dialogue() -> void:
	var finished := sequence_id
	sequence_id = ""
	node_id = ""
	line = {}
	hud.close_dialog()
	match finished:
		"intro":
			location.stage_show.finish_opening()
			phase = "news"
		"mordecai_news": phase = "to_dressing"
		"mirror":
			mirror_system.end_scene()
			phase = "elsa_dressing"
			hud.show_notice("Ричард… здесь, у занавеса.")
			sound("rigging")
		"elsa_dressing": phase = "to_hall"
		"lili": phase = "bruno"
		"mordecai_bruno": phase = "elsa_hall"
		"elsa_hall": phase = "to_technical"
		"technical":
			phase = "photos"
			hud.set_story_mode("")
			update_staging()
			start_dialogue("photos")
			return
		"photos":
			begin_walter_arrival()
			return
		"walter_arrival":
			phase = "complete"
			menu_kind = "end"
			hud.show_menu("end")
	update_staging()
	save_game()
	player.set_locked(hud.menu.visible)

func update_staging() -> void:
	for id in actors:
		var show_actor: bool = (id == "mordecai" and phase not in ["technical", "photos", "walter", "complete"]) or (id == "bruno" and phase not in ["technical", "photos", "walter", "complete"]) or (id == "elsa" and phase not in ["technical", "photos", "walter", "complete"]) or (id == "lili" and phase == "lili" and flags.get("lili_visible", false)) or (id == "walter" and phase in ["walter","complete"])
		actors[id].visible = show_actor
		var can_interact: bool = show_actor and not (id == "elsa" and phase in ["intro", "news", "to_dressing", "mirror"])
		actors[id].collision_layer = 1 if can_interact else 0
	location.move_actor("mordecai", Vector3(2.2,1.25,-3) if phase not in ["intro", "news"] else Vector3(-5.3,1.25,1), 6.0)
	actors["mordecai"].prompt = "Обсудить крышу с Мордекаем" if phase == "bruno" else "Поговорить с Мордекаем"
	actors["bruno"].prompt = "Обсудить крышу с Бруно" if phase == "bruno" else "Поговорить с Бруно"
	actors["bruno"].position = Vector3(4.5,1.55,-3.7)
	location.move_actor("elsa", Vector3(5.7,2.6,1.4) if phase in ["lili", "bruno", "elsa_hall", "to_technical"] else Vector3(-13.2,2.1 if phase in ["elsa_dressing", "to_hall"] else 4.8,.5), 2.0)
	var doctor_position: Array = flags.get("walter_position", [18, .95, 3.8])
	actors["walter"].position = Vector3(doctor_position[0], doctor_position[1], doctor_position[2])
	actors["mordecai"].rotation.y = -.35
	actors["bruno"].rotation.y = -.5
	actors["lili"].rotation.y = 0
	if phase == "lili" and flags.get("lili_visible", false) and not flags.get("lili_reveal_pending", false):
		actors["lili"].position = Vector3(-4.4, 1.2, .3)
		actors["lili"].look_at(Vector3(player.position.x, actors["lili"].position.y, player.position.z), Vector3.UP, true)
	actors["elsa"].rotation.y = .25
	actors["walter"].rotation.y = float(flags.get("walter_yaw", PI))
	if is_instance_valid(location): location.sync()
	var notes := {
		"intro": ["ПОСЛЕДНЕЕ ПРЕДСТАВЛЕНИЕ", "Номер окончен. Мордекай ждёт за кулисами."],
		"news": ["ЗА КУЛИСАМИ", "Мордекай хотел что-то сказать."],
		"to_dressing": ["ЗА КУЛИСАМИ", "Хочу смыть грим. Моя комната за коротким проходом с афишами."],
		"mirror": ["ГРИМЁРНАЯ", "В зеркалах нет моего отражения. Нужно подойти и присмотреться."],
		"elsa_dressing": ["ГРИМЁРНАЯ", "Эльза зовёт меня из-под потолка."],
		"to_hall": ["ГРИМЁРНАЯ", "Эльза сказала про крышу. У коробки в манеже кто-то шуршит."],
		"lili": ["МАНЕЖ", "Моя коробка для фокусов. Кажется, внутри кто-то есть."],
		"bruno": ["МАНЕЖ", "Мордекай позвал меня к снарядам, где стоит Бруно. Поговорю с ними."],
		"elsa_hall": ["МАНЕЖ", "Эльза ждёт у служебной двери."],
		"to_technical": ["МАНЕЖ", "Невидимкой можно открыть служебный замок."],
		"technical": ["СЛУЖЕБНЫЙ КОРИДОР", "Вальтер — в комнате в конце коридора."],
		"photos": ["КАБИНЕТ", "На дальней стене висят фотографии артистов."],
		"walter": ["КАБИНЕТ", "Вальтер стоит передо мной."],
		"complete": ["КОНЕЦ ГЛАВЫ", "Ричард добрался до Вальтера."]}
	var info: Array = notes[phase]
	hud.set_objective(info[0], info[1], flags.get("hairpin", false))

func run_event(event: String) -> void:
	match event:
		"applause":
			sound("applause")
			location.opening_action(flags.get("opening_action", "bow"))
		"roof_crack":
			sound("crack")
			location.roof_crack()
			shake_camera(0.05)
		"audience": ambience.volume_db = -26
		"mirror_empty":
			flags["reflection_restored"] = false
			sound("whisper")
		"mirror_scare":
			flags["reflection_restored"] = true
			hud.scare()
			sound("sting")
			shake_camera(0.09)
		"lili_appears":
			# Legacy saves can still enter node 0 directly; never replay the jump under UI.
			flags["lili_visible"] = true
			update_staging()
		"lili_leaves":
			flags["richard_name_seen"] = true
			flags["lili_visible"] = false
			update_staging()
		"hairpin_received":
			flags["hairpin"] = true
			hud.show_notice("Получена невидимка")
			update_staging()
		"technical_begin": sound("whisper")
		"knock_front": sound("knock", -0.8)
		"knock_behind": sound("knock", 0.8)
		"lili_silhouette":
			show_lili_glimpse()
			sound("sting")
		"richard_photo": hud.show_caption("РЕБЁНОК")
		"photo_falls": sound("knock")
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
			sound("whisper")

func shake_camera(strength: float) -> void:
	var initial: Vector3 = player.camera.position
	if camera_tween: camera_tween.kill()
	camera_tween = create_tween()
	for offset in [Vector3(strength, 0, 0), Vector3(-strength, strength, 0), Vector3.ZERO]:
		camera_tween.tween_property(player.camera, "position", initial + offset, 0.09)

func sound(id: String, pan: float = 0) -> void:
	var stream: AudioStream = load("res://assets/audio/" + id + ".wav")
	var playback := AudioStreamPlayer.new()
	playback.stream = stream
	playback.volume_db = -5
	# Use a dedicated effects bus to position the tunnel knocks in stereo.
	if pan != 0:
		var bus := AudioServer.get_bus_index("StoryPan")
		if bus == -1:
			AudioServer.add_bus()
			bus = AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus, "StoryPan")
			var panner := AudioEffectPanner.new()
			AudioServer.add_bus_effect(bus, panner)
		var effect: AudioEffectPanner = AudioServer.get_bus_effect(bus, 0)
		effect.pan = pan
		playback.bus = "StoryPan"
	add_child(playback)
	playback.finished.connect(playback.queue_free)
	playback.play()

func on_menu_action(action: String) -> void:
	match action:
		"new_game": new_game()
		"continue": load_game()
		"pause":
			if transitioning or hud.menu.visible: return
			menu_kind = "pause"
			location.pause_motion(true)
			player.set_locked(true)
			hud.show_menu("pause")
			save_game()
		"resume":
			location.pause_motion(false)
			hud.hide_menu()
			menu_kind = ""
			player.set_locked(not sequence_id.is_empty() or transitioning)
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
		"quit":
			if menu_kind != "main": save_game()
			get_tree().quit()

func save_game() -> void:
	var data := {"version": 1, "phase": phase, "flags": flags, "sequence": sequence_id, "node": node_id,
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
	session += 1
	transitioning = false
	player.camera.position = Vector3(0, 1.55, 0)
	phase = data["phase"]
	flags = data["flags"]
	sequence_id = data.get("sequence", "")
	node_id = data.get("node", "")
	var position: Array = data.get("position", [-34, 0.05, 38.7])
	if position.size() != 3: position = [-34, 0.05, 38.7]
	player.position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	player.rotation = Vector3(0, float(data.get("yaw", 0)), 0)
	player.camera.rotation = Vector3(clampf(float(data.get("pitch", 0)), -1.35, 1.35), 0, 0)
	player.velocity = Vector3.ZERO
	if not is_inside_location(player.position):
		var at := Vector3(-3,.05,3)
		if phase in ["mirror","elsa_dressing","to_hall"]: at = Vector3(-14,.05,2)
		elif phase in ["technical","photos","walter","complete"]:
			at = Vector3(17,.05,2.4)
			flags["service_open"] = true
		place_player(at, at+Vector3(0,1.5,-1))
	last_safe_position = player.position
	hud.hide_menu()
	hud.close_dialog()
	hud.fade.hide()
	hud.set_story_mode("")
	menu_kind = ""
	update_staging()
	if phase == "complete":
		menu_kind = "end"
		hud.show_menu("end")
	elif phase == "lili" and sequence_id.is_empty():
		begin_lili_reveal()
	elif phase == "walter" and sequence_id.is_empty():
		begin_walter_arrival()
	elif not sequence_id.is_empty(): display_line()
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
	if glimpse_tween: glimpse_tween.kill()
	if is_instance_valid(glimpse_node): glimpse_node.queue_free()
	glimpse_node = null
	if is_instance_valid(location): location.reset_motion()
	if is_instance_valid(mirror_system): mirror_system.end_scene()
	if actor_tween: actor_tween.kill()
	if camera_tween: camera_tween.kill()
	for child in get_children():
		if child is AudioStreamPlayer and child != ambience:
			child.stop()
			child.queue_free()
	hud.reset_effects()

func _exit_tree() -> void:
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
	sound("knock")
	frame_player_at(Vector3(-3.8, 1.45, -.65), .45)
	var reveal_session := session
	if actor_tween: actor_tween.kill()
	actor_tween = create_tween()
	actor_tween.tween_interval(.5)
	actor_tween.tween_callback(func():
		if session != reveal_session: return
		flags["lili_visible"] = true
		var actor: Node3D = actors["lili"]
		actor.position = Vector3(-3, .65, -1.2)
		actor.visible = true
		actor.collision_layer = 0
		actor.look_at(Vector3(player.position.x, actor.position.y, player.position.z), Vector3.UP, true)
		sound("knock"))
	actor_tween.tween_property(actors["lili"], "position", Vector3(-3.6, 2.5, -.7), .35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	actor_tween.tween_property(actors["lili"], "position", Vector3(-4.4, 1.2, .3), .4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
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
	return Vector3(19, feet_y, 2.4)

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
	if not flags.has("walter_position"):
		var feet := find_clear_appearance_position(1.65, 1.86, .30, .025)
		var position := feet + Vector3(0, .925, 0)
		var toward_player: Vector3 = player.position - position
		flags["walter_position"] = [position.x, position.y, position.z]
		flags["walter_yaw"] = atan2(toward_player.x, toward_player.z)
	update_staging()
	frame_player_at(actors["walter"].global_position + Vector3(0, .72, 0), .3)
	sound("whisper")
	save_game()
	var entrance_session := session
	if actor_tween: actor_tween.kill()
	actor_tween = create_tween()
	actor_tween.tween_interval(.95)
	actor_tween.tween_callback(func():
		if session != entrance_session: return
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
