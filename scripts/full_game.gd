extends Node3D
## Remaining screenplay: Walter's contract, real roof traversal, and four endings.
const PHASES:=["contract","roof_key","return_arena","roof_access","roof","home","bathroom","trapped","captured"]
const ENDINGS:={
	"recovery":["ВНЕ ЦИРКА","Ты проснулся дома. В зеркале отражаешься ты. Лекарства открыты."],
	"host":["ПРЕДСТАВЛЕНИЕ ПРОДОЛЖАЕТСЯ","Ты вернулся домой. Но ведущий остался в отражении."],
	"captured":["НОВЫЙ НОМЕР","Новый ведущий представляет тебя публике."],
	"locker":["БЕЗ ВЫХОДА","Дверь закрылась. Никто не пришёл на помощь."]
}
var set_dressing:Node3D
var late:Node3D
var home_mirror_added:=false
var game
var active_tween:Tween
var apparition:Node3D
var progress_path:="user://last-show-endings.json"
var old_phase:=""
var actual_last_position:=Vector3.ZERO
var home_appearance:=""
var stage_body:Mesh
var home_body:Mesh
var hidden_show_lights:Dictionary={}
var arena_night_env:Environment

func setup(owner_game) -> void:
	game=owner_game;name="FullScenario"
	stage_body=game.mirror_system.avatar.find_child("Body",true,false).mesh
	var ordinary:Node3D=preload("res://assets/characters/models/richard_home.glb").instantiate()
	home_body=ordinary.find_child("Body",true,false).mesh;ordinary.free()
	set_dressing=preload("res://scripts/circus_set.gd").new();add_child(set_dressing);set_dressing.setup(game)
	late=preload("res://scripts/late_locations.gd").new();add_child(late);late.setup(game)
	arena_night_env=game.get_node("World/WorldEnvironment").environment.duplicate()
	arena_night_env.ambient_light_energy=.12;arena_night_env.fog_depth_begin=10;arena_night_env.fog_depth_end=75

func objective(phase:String) -> Array:
	return {
		"contract":["ДОКТОР ВАЛЬТЕР","Прочитать документ на столе"],
		"roof_key":["КЛЮЧ","Взять ключ со стола Вальтера"],
		"return_arena":["ПОСЛЕ ПРЕДСТАВЛЕНИЯ","Вернуться на манеж"],
		"roof_access":["ЗА СЦЕНОЙ","Найти лестницу на крышу за сценой"],
		"roof":["ПОД КУПОЛОМ","Пройти по мосткам к батуту"],
		"home":["ДОМ","Посмотреть в зеркало в ванной"],
		"bathroom":["ОТРАЖЕНИЕ",""],
		"trapped":["ЗАПЕРТО","Открыть шкафчик"],
		"captured":["ПОСЛЕДНИЙ НОМЕР",""],
		"complete":["КОНЕЦ ИГРЫ",""]
	}.get(phase,["LAST SHOW",""])

# World point the objective arrow should lead to in a late phase, or null.
func objective_goal(phase:String):
	var p:Vector3=game.player.global_position
	match phase:
		"contract":return set_dressing.contract_paper.global_position
		"roof_key":return set_dressing.clinic_key.get_meta("target").global_position
		"return_arena","roof_access":return late.roof_door.global_position
		"roof":
			# The catwalk is an L: the long strip passes the rope, then turns east.
			if p.z<-3.9:return Vector3(-10,late.ROOF_FLOOR,-2)
			return late.TRAMPOLINE
		"home":
			# Bedroom first, through the doorway in the north wall.
			if p.z>-3.2:return late.HOME+Vector3(0,0,-4.6)
			return late.HOME_MIRROR
		"trapped":return set_dressing.locker.global_position
	return null

func room_at(position:Vector3) -> String:
	if late.is_roof_position(position):return "roof"
	if position.x>145:return "home"
	return ""

func contains(position:Vector3) -> bool:
	if game.phase in ["roof"]:
		return late.is_roof_position(position)
	if game.phase in ["home","bathroom"] or (game.phase=="complete" and game.flags.get("ending_id","") in ["recovery","host"]):
		return position.x>=150.8 and position.x<=159.2 and position.z>=-11.2 and position.z<=4.2 and position.y>-1
	return false

func interact(id:StringName) -> bool:
	if set_dressing.arena_details.interact(id):return true
	match String(id):
		"knife":
			if game.flags.get("richard_name_seen",false) and not game.flags.get("knife",false):
				game.flags.knife=true;game.audio.play("sfx_knife_pickup",-9,game.layout.TRUNK)
				game.hud.show_notice("Как он тут оказался?")
				sync();game.save_game()
		"tickets": game.audio.ui()
		"television": game.start_dialogue("television")
		"contract":
			if game.phase=="contract":game.start_dialogue("walter_contract")
		"roof_key":
			if game.flags.get("contract_signed",false) and not game.flags.get("roof_key",false):
				game.flags.roof_key=true;game.phase="return_arena"
				game.audio.play("sfx_key_pickup",-8);game.hud.show_notice("Ключ от крыши")
				game.update_staging();game.save_game()
		"locker":
			if game.phase=="trapped":game.start_dialogue("ending_locker")
			# Before talking to Walter the locker is the other branch of the clinic.
			elif game.phase=="photos" and not game.flags.get("locker_open",false):game.start_dialogue("clinic_locker")
		"roof_door":
			if game.phase not in ["return_arena","roof_access"]:
				game.audio.play("sfx_door_locked", -9, late.roof_door.global_position)
			elif game.flags.get("roof_key",false) or game.flags.get("hairpin",false):
				game.flags.roof_open=true
				game.audio.play("sfx_service_door_open",-8,late.roof_door.global_position)
				transfer(late.ROOF_ENTRY,late.ROPE,"roof")
			else:game.audio.play("sfx_door_locked", -9, late.roof_door.global_position)
		"roof_return":game.start_dialogue("roof_descent")
		"roof_rope":
			if not game.flags.get("rope_cut",false):game.start_dialogue("roof_rope")
		"trampoline":game.start_dialogue("trampoline")
		"home_mirror":
			if game.phase=="home":
				game.phase="bathroom";game.update_staging()
				game.start_dialogue("home_recovery" if game.flags.get("rope_cut",false) else "home_host")
		_ :return false
	return true

func finish_dialogue(id:String) -> bool:
	match id:
		"walter_arrival","walter_greeting":
			game.phase="contract";game.update_staging();game.start_dialogue("walter_contract")
		"walter_contract":
			if game.flags.get("contract_signed",false):game.phase="roof_key"
			elif game.flags.get("hairpin",false):game.phase="return_arena"
			else:game.phase="trapped"
			game.update_staging();game.save_game();game.player.set_locked(false)
		"roof_rope":game.update_staging();game.player.set_locked(false);game.save_game()
		"trampoline","roof_descent":
			var choice:String=game.flags.get("roof_choice","stay")
			if choice=="jump":jump_home()
			elif choice=="back":
				game.phase="captured";game.update_staging();game.start_dialogue("ending_captured")
			else:game.player.set_locked(false);game.save_game()
		"wake_home":game.phase="home";game.update_staging();game.player.set_locked(false);game.save_game()
		"home_recovery":complete("recovery")
		"home_host":complete("host")
		"ending_captured":complete("captured")
		"ending_locker":complete("locker")
		"clinic_locker":
			if game.flags.get("locker_open",false):
				# The corridor door slams behind the scare: the locker ending.
				game.flags.service_open=false;complete("locker")
			else:game.player.set_locked(false);game.save_game()
		"tickets","television":game.player.set_locked(false);game.save_game()
		_:return false
	return true

func event(id:String) -> bool:
	match id:
		"show_contract":game.frame_player_at(set_dressing.contract_paper.global_position,.4)
		"contract_signed":
			game.audio.play("sfx_contract_sign",-8);game.flags.service_open=true;game.location.sync()
		"contract_refused":
			game.flags.service_open=false;game.location.sync();game.sound("locked")
		"cut_rope":
			game.audio.play("sfx_rope_cut",-8,late.ROPE)
			late.rope_piece.hide()
			active_tween=create_tween()
			active_tween.tween_property(late.medicine_bag,"position:y",-15.0,1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			active_tween.tween_callback(late.medicine_bag.hide)
		"roof_audience":
			game.flags.roof_audience=true;game.location.stage_show.sync_damage()
			game.location.stage_show.start_applause()
			game.audio.play("sfx_applause",-15);game.audio.play("mus_show_outro",-19,Vector3.INF,"Music")
			var start:Vector3=game.player.camera.global_position
			active_tween=create_tween()
			active_tween.tween_method(func(amount:float):
				game.player.camera.global_position=start.lerp(late.AUDIENCE_VIEW,amount)
				game.player.camera.look_at(late.AUDIENCE_LOOK)
			,0.0,1.0,.7).set_trans(Tween.TRANS_SINE)
		"home_reflection":home_appearance="recovery";dress_reflection(false)
		"host_reflection":home_appearance="host";dress_reflection(true);game.sound("mirror_smile")
		"ending_surrounded":
			game.place_player(Vector3(0,.05,3),Vector3(0,1.8,0));game.player.camera.environment=null
			for index in 5:
				var actor:Node3D=game.actors[["mordecai","bruno","elsa","lili","walter"][index]]
				actor.show();actor.collision_layer=0
				var angle:float=(index-2)*.55
				actor.position=Vector3(sin(angle)*2.8,2.1 if index==2 else [1.25,1.55,2.1,1.2,.95][index],3-cos(angle)*2.8)
				actor.look_at(Vector3(0,actor.position.y,3),Vector3.UP,true)
		"ending_operation":
			for actor in game.actors.values():actor.hide();actor.collision_layer=0
			game.actors.walter.show();game.actors.walter.position=set_dressing.clinic_chair+Vector3(0,.95,-1.7)
			game.place_player(set_dressing.clinic_chair+Vector3(0,.9,0),game.actors.walter.position+Vector3(0,.6,0))
			game.actors.walter.look_at(Vector3(set_dressing.clinic_chair.x,game.actors.walter.position.y,set_dressing.clinic_chair.z),Vector3.UP,true)
			game.player.camera.position.y=.35
			game.player.camera.look_at(game.actors.walter.position+Vector3(0,.6,0))
			game.sound("walter")
		"ending_replacement":
			for actor in game.actors.values():actor.hide();actor.collision_layer=0
			game.place_player(Vector3(-1.4,.05,-8.7),Vector3(0,1.7,-6.5))
			if not is_instance_valid(apparition):
				apparition=load("res://assets/characters/models/richard.glb").instantiate();add_child(apparition)
			apparition.position=Vector3(0,.32,-6.5)
			apparition.rotation.y=0
			for node in apparition.find_children("Uncanny*","MeshInstance3D",true,false):node.hide()
			game.audio.play("sfx_applause",-12)
		"locker_rattle":
			var hinge: Node3D = set_dressing.locker.get_meta("hinge")
			var scrape: Node = game.audio.play("sfx_service_door_open", -20, set_dressing.locker.global_position)
			scrape.pitch_scale = .55
			if active_tween and active_tween.is_valid(): active_tween.kill()
			active_tween = create_tween()
			for angle in [.025, -.02, .018, 0.0]:
				active_tween.tween_property(hinge, "rotation:y", angle, .12)
		"locker_scare":
			game.flags.locker_open = true
			if is_instance_valid(apparition):apparition.queue_free()
			apparition=load("res://assets/characters/models/lili.glb").instantiate();add_child(apparition)
			apparition.position=set_dressing.locker.position+Vector3(0,-1.1,-.8)
			apparition.look_at(Vector3(game.player.position.x,apparition.position.y,game.player.position.z),Vector3.UP,true)
			set_dressing.locker.collision_layer=0
			game.audio.play("sfx_service_door_open", -5, set_dressing.locker.global_position)
			if active_tween and active_tween.is_valid(): active_tween.kill()
			active_tween = create_tween()
			active_tween.tween_property(set_dressing.locker.get_meta("hinge"), "rotation:y", 1.45, .16)
			game.frame_player_at(apparition.position+Vector3(0,1.25,0),.15)
			game.sound("lili_glimpse");game.hud.scare()
		_:return false
	return true

func transfer(destination:Vector3,facing:Vector3,phase:String) -> void:
	if game.transitioning:return
	game.transitioning=true;game.player.set_locked(true)
	var token:int=game.session
	await game.hud.transition_out()
	if token!=game.session:return
	game.phase=phase;game.place_player(destination,facing);game.last_safe_position=destination
	game.update_staging()
	for i in 3:await get_tree().physics_frame
	await game.hud.transition_in()
	if token!=game.session:return
	game.transitioning=false;game.player.set_locked(false);game.save_game()

func jump_home() -> void:
	if active_tween and active_tween.is_valid():active_tween.kill()
	game.transitioning=true;game.player.set_locked(true)
	var token:int=game.session
	# Richard steps onto the trampoline, bounces once and is thrown up through
	# the torn canvas. In flight he looks back down at the circus while the
	# picture slowly fades to black under the wind.
	var camera:Camera3D=game.player.camera
	var eye_height:float=camera.position.y
	var breach:Vector3=game.location.stage_show.ROOF_BREACH_CENTER
	var bed:=Vector3(late.TRAMPOLINE.x,late.ROOF_FLOOR+.68,late.TRAMPOLINE.z)
	game.player.set_physics_process(false)
	active_tween=create_tween()
	active_tween.tween_property(game.player,"global_position",bed,.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	active_tween.parallel().tween_property(camera,"rotation:x",.35,.9)
	active_tween.tween_property(camera,"position:y",eye_height-.4,.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	active_tween.tween_callback(func():game.audio.play("sfx_roof_jump",-8))
	active_tween.tween_property(camera,"position:y",eye_height,.12)
	await active_tween.finished
	if token!=game.session:return
	var wind:=AudioStreamPlayer.new();wind.stream=load("res://assets/audio/full_game/sfx_escape_wind.wav")
	wind.volume_db=-10;add_child(wind);wind.play()
	active_tween=create_tween()
	active_tween.tween_property(game.player,"global_position",Vector3(breach.x,breach.y+16.0,breach.z),3.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Look back and down into the tent through the tear.
	active_tween.parallel().tween_property(camera,"rotation:x",-1.25,1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	active_tween.parallel().tween_property(game.player,"rotation:y",game.player.rotation.y+PI,1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var fade:ColorRect=game.hud.fade
	fade.modulate.a=0;fade.show()
	active_tween.parallel().tween_property(fade,"modulate:a",1.0,2.6).set_delay(1.4)
	await active_tween.finished
	if token!=game.session:return
	var hush:=create_tween();hush.tween_property(wind,"volume_db",-40.0,1.2);hush.tween_callback(wind.queue_free)
	game.player.set_physics_process(true)
	camera.position.y=eye_height;camera.rotation.x=0
	game.phase="home";game.place_player(late.HOME+Vector3(0,0,1.8),late.HOME+Vector3(-2.4,1.3,.3))
	game.last_safe_position=game.player.position;game.update_staging()
	await game.hud.transition_in()
	if token!=game.session:return
	game.transitioning=false;game.start_dialogue("wake_home")

func dress_reflection(host:bool) -> void:
	var avatar:Node3D=game.mirror_system.avatar
	avatar.find_child("Body",true,false).mesh=stage_body if host else home_body
	for mesh in avatar.find_children("*","MeshInstance3D",true,false):
		var name:=String(mesh.name)
		if name.begins_with("Coat") or name.contains("Tail") or name.contains("Hat") or name.contains("Waistcoat"):
			mesh.visible=host
		if name.begins_with("Uncanny"):mesh.visible=host
		if name.begins_with("NeutralMouth"):mesh.visible=not host

func unlocked() -> Array:
	if not FileAccess.file_exists(progress_path):return []
	var data=JSON.parse_string(FileAccess.get_file_as_string(progress_path))
	return data if data is Array else []

func complete(id:String) -> void:
	game.flags.ending_id=id;game.phase="complete";game.sequence_id="";game.node_id=""
	var found:=unlocked()
	if not found.has(id):found.append(id)
	var file=FileAccess.open(progress_path,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(found));file.close()
	game.hud.ending_title=ENDINGS[id][0];game.hud.ending_description=ENDINGS[id][1]
	game.menu_kind="end";game.player.set_locked(true);game.hud.close_dialog();game.hud.show_menu("end")
	game.save_game()

func sync() -> void:
	set_dressing.sync();late.sync()
	var open_locker: bool = game.flags.get("locker_open", false)
	set_dressing.locker.get_meta("hinge").rotation.y = 1.45 if open_locker else 0.0
	set_dressing.locker.collision_layer = 0 if open_locker else 1
	var extended:bool=game.phase in PHASES
	var late_arena:bool=game.phase in ["return_arena","roof_access","roof","home","bathroom","trapped","captured"]
	if extended:
		for id in game.actors:
			var show:bool=id=="walter" and game.phase in ["contract","roof_key"]
			game.actors[id].visible=show;game.actors[id].collision_layer=1 if show else 0
		if game.phase=="contract":
			var at:Vector3=game.actors.walter.position
			if Vector2(at.x-game.player.position.x,at.z-game.player.position.z).length()>.1:
				game.actors.walter.look_at(Vector3(game.player.position.x,at.y,game.player.position.z),Vector3.UP,true)
		if game.phase=="roof_key":
			game.actors.walter.position=game.layout.CLINIC_CENTER+Vector3(1.8,.95,1)
			game.actors.walter.collision_layer=0
	var home_active:bool=game.phase in ["home","bathroom"] or (game.phase=="complete" and game.flags.get("ending_id","") in ["recovery","host"])
	if home_active:
		game.player.camera.environment=late.home_env
		if not home_mirror_added:
			game.mirror_system.add_surface(late.bathroom_glass);home_mirror_added=true
		dress_reflection(not game.flags.get("rope_cut",false))
	elif game.phase=="roof":game.player.camera.environment=late.roof_env
	elif game.phase in ["return_arena","roof_access"]:game.player.camera.environment=arena_night_env
	else:game.player.camera.environment=null
	if old_phase!=game.phase:
		old_phase=game.phase
		if late_arena:
			for light in set_dressing.find_children("*","Light3D",true,false):
				if Vector2(light.global_position.x,light.global_position.z).length()>50 or light.position.y>15:continue
				if not hidden_show_lights.has(light):hidden_show_lights[light]=light.light_energy
				light.light_energy=0
		elif not hidden_show_lights.is_empty():
			for light in hidden_show_lights:
				if is_instance_valid(light):light.light_energy=hidden_show_lights[light]
			hidden_show_lights.clear()
	game.hud.item.text=" · ".join(inventory())

func inventory() -> PackedStringArray:
	var result:=PackedStringArray()
	for entry in [["knife","Нож"],["hairpin","Невидимка"],["roof_key","Ключ от крыши"]]:
		if game.flags.get(entry[0],false):result.append(entry[1])
	return result

func check_walk_progress() -> void:
	if game.phase=="return_arena" and game.room_at(game.player.position)=="arena":
		game.phase="roof_access";game.update_staging();game.save_game()
		game.audio.emote("mordecai_smile")
		game.hud.show_notice("Ричард… Не опоздай.")
	if game.phase=="roof" and game.player.position.y<late.ROOF_FLOOR-1:
		game.place_player(late.ROOF_ENTRY,late.ROPE)

func reset_motion() -> void:
	if is_instance_valid(set_dressing):set_dressing.arena_details.reset_motion()
	if active_tween and active_tween.is_valid():active_tween.kill()
	if is_instance_valid(apparition):apparition.queue_free()
	apparition=null
	if is_instance_valid(late):late.medicine_bag.position=Vector3.ZERO

func reset_new_run() -> void:
	old_phase="";game.hud.ending_title="";game.hud.ending_description=""
	game.location.lighting.show_mode=-1
	set_dressing.locker.show();set_dressing.locker.collision_layer=1
	set_dressing.locker.get_meta("hinge").rotation.y = 0
	game.mirror_system.avatar.find_child("Body",true,false).mesh=stage_body
	for node in game.mirror_system.avatar.find_children("*","MeshInstance3D",true,false):
		if not String(node.name).begins_with("Uncanny"):node.show()
		else:node.hide()

func restore_ending(id:String) -> void:
	if id=="captured":event("ending_replacement")
	elif id=="locker":event("locker_scare")
	elif id in ["host","recovery"]:dress_reflection(id=="host")

func pause_motion(value:bool) -> void:
	set_dressing.arena_details.pause_motion(value)
	if active_tween and active_tween.is_valid():
		if value:active_tween.pause()
		else:active_tween.play()

func restore_dialogue_view() -> void:
	if not String(game.line.get("event","")).is_empty():return
	if game.sequence_id=="ending_captured":
		if game.node_id=="0":event("ending_surrounded")
		elif game.node_id in ["1","2"]:event("ending_operation")
		elif game.node_id=="3":event("ending_replacement")
	elif game.sequence_id in ["ending_locker","clinic_locker"] and game.node_id in ["1","2"]:event("locker_scare")
	elif game.sequence_id=="trampoline" and game.node_id in ["1","2","3"]:
		game.player.camera.global_position=late.AUDIENCE_VIEW
		game.player.camera.look_at(late.AUDIENCE_LOOK)
