extends Node3D
## Scripted first chapter with the corrected supplied layout and Blender props.
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
var spotlight: OmniLight3D
var autosave_elapsed := 0.0
var magic_box_label: Label3D
var actor_tween: Tween
var camera_tween: Tween

func _ready() -> void:
	configure_input()
	for id in ["mordecai", "bruno", "lili", "elsa"]:
		var actor: StaticBody3D = world.get_node(id.capitalize())
		actors[id] = actor
		targets[id] = [actor]
		actor.interacted.connect(on_interact)
		add_label(actor, database.SPEAKERS[id], Vector3(0, 1.65, 0))
	stage_existing_props()
	add_hotspot("dressing", "В гримёрную", Vector3(-39.6, 1.5, 44.1))
	add_hotspot("hall", "В главный шатёр", Vector3(-44, 1.5, 41))
	add_hotspot("technical", "Только для персонала", Vector3(-12, 1.5, 25))
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
	spotlight = OmniLight3D.new()
	spotlight.omni_range = 18
	spotlight.light_color = Color("cfc2a5")
	spotlight.light_energy = 1.4
	world.add_child(spotlight)
	load_settings()
	update_staging()
	player.set_locked(true)
	hud.show_menu("main", read_save().size() > 0)

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
	move_imported_group("Mirror Frame", Vector3(-48, 0.578197, 36.5))
	move_imported_group("Crate 2_001", Vector3(-22, 0.750519, 25))
	# Godot normalizes punctuation in imported names. Resolve by source position
	# if an exporter version uses a different name.
	var crate: Node3D = model.get_node_or_null("Crate 2_001")
	if crate == null:
		crate = model.get_node_or_null("Crate 2.001")
		if crate: move_imported_group(String(crate.name), Vector3(-22, 0.750519, 25))
	for mesh_name in ["Mirror Frame", "Mirror surface", "Cylinder_009", "Cylinder_008"]:
		bind_imported(mesh_name, "mirror", "Посмотреть в зеркало")
	if crate:
		bind_imported(String(crate.name), "box", "Открыть коробку для фокусов")
		magic_box_label = add_label(crate, "Коробка для фокусов", Vector3(0, 1.35, 0))
	else:
		push_error("Missing the existing imported magic box")

func move_imported_group(mesh_name: String, destination: Vector3) -> void:
	var mesh: Node3D = model.get_node_or_null(NodePath(mesh_name))
	if mesh == null: return
	var delta := destination - mesh.position
	var names: Array[String] = [String(mesh.name)]
	for child in mesh.find_children("*", "MeshInstance3D"):
		names.append(String(child.name))
	mesh.position += delta
	for body in model.get_node("GeometryCollisions").get_children():
		if String(body.get_meta("source_mesh", "")) in names:
			body.position += delta

func bind_imported(mesh_name: String, id: String, prompt: String) -> void:
	for body in model.get_node("GeometryCollisions").get_children():
		if String(body.get_meta("source_mesh", "")) == mesh_name:
			body.set_script(INTERACTABLE)
			body.interaction_id = StringName(id)
			body.prompt = prompt
			body.interacted.connect(on_interact)
			if not targets.has(id): targets[id] = []
			targets[id].append(body)

func add_label(parent: Node3D, text: String, offset: Vector3) -> Label3D:
	var label := Label3D.new()
	label.name = "StoryLabel"
	label.text = text
	label.position = offset
	label.font = preload("res://assets/fonts/DejaVuSerif.ttf")
	label.font_size = 40
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = Color("e2c799")
	parent.add_child(label)
	label.add_to_group("story_world_labels")
	return label

func add_hotspot(id: String, text: String, position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = id.capitalize() + "Transition"
	body.set_script(INTERACTABLE)
	body.interaction_id = StringName(id)
	body.prompt = text
	body.position = position
	world.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.8
	collision.shape = shape
	body.add_child(collision)
	add_label(body, text + "  ›", Vector3.ZERO)
	body.interacted.connect(on_interact)
	targets[id] = [body]

func _process(delta: float) -> void:
	for label in get_tree().get_nodes_in_group("story_world_labels"):
		label.visible = not hud.dialog.visible and not hud.menu.visible
	if is_instance_valid(spotlight):
		spotlight.position = player.position + Vector3(0, 4, 0)
	if phase in ["mirror", "elsa_dressing", "to_hall", "elsa_hall", "to_technical"]:
		# Elsa's feet stay above the floor at every point in the story.
		actors["elsa"].position.y = 4.0 + sin(Time.get_ticks_msec() / 1400.0) * 0.12
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
	place_player(Vector3(0, 0.05, 12), Vector3(0, 1.5, 0))
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
			else: hud.show_notice("Мордекай больше ничего не говорит.")
		"bruno":
			if phase == "bruno": start_dialogue("mordecai_bruno")
		"mirror":
			if phase == "mirror": start_dialogue("mirror")
			else: hud.show_notice("Улыбка в зеркале исчезла.")
		"elsa":
			if phase == "elsa_dressing": start_dialogue("elsa_dressing")
			elif phase == "elsa_hall": start_dialogue("elsa_hall")
			else: hud.show_notice("Эльза молча смотрит сверху.")
		"dressing":
			if phase == "to_dressing": change_area("mirror", Vector3(-48, 0.05, 40.5), Vector3(-48, 1.5, 36.5))
		"hall":
			if phase == "to_hall": change_area("lili", Vector3(-22, 0.05, 29), Vector3(-22, 1.5, 25))
		"box":
			if phase == "lili": start_dialogue("lili")
			else: hud.show_notice("RICHARD. Коробка пуста.")
		"technical":
			if phase == "to_technical": enter_technical()

func change_area(next_phase: String, position: Vector3, facing: Vector3) -> void:
	transitioning = true
	player.set_locked(true)
	var current_session := session
	await hud.transition_out()
	if session != current_session: return
	phase = next_phase
	place_player(position, facing)
	update_staging()
	save_game()
	await hud.transition_in()
	if session != current_session: return
	transitioning = false
	player.set_locked(hud.menu.visible)

func enter_technical() -> void:
	transitioning = true
	player.set_locked(true)
	var current_session := session
	await hud.transition_out()
	if current_session != session: return
	phase = "technical"
	update_staging()
	hud.set_story_mode("technical")
	await hud.transition_in()
	if current_session != session: return
	transitioning = false
	start_dialogue("technical")

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
	var who: String = line.get("speaker", "narrator")
	var portrait_id: String = line.get("portrait", who)
	hud.show_line(database.SPEAKERS.get(who, ""), line.get("text", ""), database.get_portrait(portrait_id), line.get("choices", []), float(line.get("pause", 0)))
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
			change_area("news", Vector3(-31.2, 0.08, 36.6), Vector3(-29.8, 1.5, 37.0))
			return
		"mordecai_news": phase = "to_dressing"
		"mirror": phase = "elsa_dressing"
		"elsa_dressing": phase = "to_hall"
		"lili": phase = "bruno"
		"mordecai_bruno": phase = "elsa_hall"
		"elsa_hall": phase = "to_technical"
		"technical":
			phase = "photos"
			hud.set_story_mode("photos")
			update_staging()
			start_dialogue("photos")
			return
		"photos":
			phase = "walter"
			start_dialogue("walter_arrival")
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
		var show_actor: bool = (id == "mordecai" and phase in ["news", "to_dressing", "bruno"]) or (id == "bruno" and phase == "bruno") or (id == "elsa" and phase in ["mirror", "elsa_dressing", "to_hall", "elsa_hall", "to_technical"]) or (id == "lili" and phase == "lili" and flags.get("lili_visible", false))
		actors[id].visible = show_actor
		actors[id].collision_layer = 1 if show_actor else 0
	if phase in ["bruno", "elsa_hall", "to_technical"]: actors["mordecai"].position = Vector3(-18, 1.2, 24)
	else: actors["mordecai"].position = Vector3(-29.8, 1.2, 37.0)
	actors["elsa"].position = Vector3(-14, 4, 26) if phase in ["elsa_hall", "to_technical"] else Vector3(-46, 4, 40)
	for id in ["dressing", "hall", "technical"]:
		var body: StaticBody3D = targets[id][0]
		var active: bool = (id == "dressing" and phase == "to_dressing") or (id == "hall" and phase == "to_hall") or (id == "technical" and phase == "to_technical")
		body.visible = active
		body.collision_layer = 1 if active else 0
	if magic_box_label:
		magic_box_label.text = "RICHARD" if flags.get("richard_name_seen", false) else "Коробка для фокусов"
	var objectives := {
		"intro": ["ПОСЛЕДНЕЕ ПРЕДСТАВЛЕНИЕ", "Закончите выступление."],
		"news": ["ЗА КУЛИСАМИ", "Поговорите с Мордекаем."],
		"to_dressing": ["ЗА КУЛИСАМИ", "Пройдите к метке «В гримёрную»."],
		"mirror": ["ГРИМЁРНАЯ", "Осмотрите зеркало перед вами."],
		"elsa_dressing": ["ГРИМЁРНАЯ", "Поговорите с Эльзой. Поднимите взгляд."],
		"to_hall": ["ГРИМЁРНАЯ", "Нужны ключ и доступ к крыше. Вернитесь в главный шатёр: метка у Эльзы."],
		"lili": ["ГЛАВНЫЙ ШАТЁР", "Откройте коробку для фокусов."],
		"bruno": ["ГЛАВНЫЙ ШАТЁР", "Расспросите Мордекая и Бруно о крыше."],
		"elsa_hall": ["ГЛАВНЫЙ ШАТЁР", "Спросите Эльзу о Вальтере. Она в воздухе, возле служебного прохода."],
		"to_technical": ["ГЛАВНЫЙ ШАТЁР", "Пройдите через служебный проход у Эльзы."],
		"technical": ["ТЕХНИЧЕСКИЙ ТУННЕЛЬ", "Доберитесь до доктора Вальтера."],
		"photos": ["КАБИНЕТ ВАЛЬТЕРА", "Осмотрите фотографии артистов."],
		"walter": ["КАБИНЕТ ВАЛЬТЕРА", "За спиной кто-то стоит."],
		"complete": ["КОНЕЦ ГЛАВЫ", "Ричард добрался до Вальтера."]}
	var info: Array = objectives[phase]
	hud.set_objective(info[0], info[1], flags.get("hairpin", false))

func run_event(event: String) -> void:
	match event:
		"applause": sound("applause")
		"roof_crack":
			sound("crack")
			shake_camera(0.05)
		"audience": ambience.volume_db = -26
		"mirror_empty": sound("whisper")
		"mirror_scare":
			hud.scare()
			sound("sting")
			shake_camera(0.09)
		"lili_appears":
			flags["lili_visible"] = true
			actors["lili"].position = Vector3(-22, 0.8, 25)
			update_staging()
			if actor_tween: actor_tween.kill()
			actor_tween = create_tween()
			actor_tween.tween_property(actors["lili"], "position", Vector3(-21, 2.8, 25), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			actor_tween.tween_property(actors["lili"], "position", Vector3(-20, 0.9, 25), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			sound("knock")
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
			hud.show_silhouette(database.get_portrait("lili"))
			sound("sting")
		"richard_photo": hud.show_caption("РЕБЁНОК")
		"photo_falls": sound("knock")
		"walter_appears":
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
			player.set_locked(true)
			hud.show_menu("pause")
			save_game()
		"resume":
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
		"position": [player.position.x, player.position.y, player.position.z], "yaw": player.rotation.y, "pitch": player.camera.rotation.x}
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
	hud.hide_menu()
	hud.close_dialog()
	hud.fade.hide()
	hud.set_story_mode("technical" if phase == "technical" else ("photos" if phase in ["photos", "walter", "complete"] else ""))
	menu_kind = ""
	update_staging()
	if phase == "complete":
		menu_kind = "end"
		hud.show_menu("end")
	elif not sequence_id.is_empty(): display_line()
	player.set_locked(hud.menu.visible or not sequence_id.is_empty())

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
