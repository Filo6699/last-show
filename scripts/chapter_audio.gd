extends Node
## Supplied chapter sound pack: pooled voices/effects, spatial cues and room crossfades.
const MANIFEST := preload("res://assets/audio/chapter_one/manifest.json")
const FULL_MANIFEST := preload("res://assets/audio/full_game/manifest.json")
const VOICES := {"richard":[2,.05], "mordecai":[2,.12], "bruno":[3,.03], "elsa":[3,.04], "lili":[2,.10], "walter":[2,.01]}
# ---- Loudness map: the only place that decides how loud a sound is. -------------------
# LOUD: measured loudness of each source file (LUFS, or RMS for clips under 0.4 s), by family
# (numeric suffix dropped). Generator: /tmp/ls/sound/measure.py logic, ffmpeg ebur128 + astats.
# TIER_DB: target level for each tier. Final player volume = TIER_DB[tier] - LOUD[family] + trim,
# so every file in a tier lands at the same loudness whatever its source level was.
# Scares sit 12 dB above ordinary SFX; footsteps and room foley sit well under everything else.
const LOUD := {"amb_arena_empty_loop":-31.1, "amb_arena_show_loop":-24.1, "amb_clinic_loop":-38.2, "amb_dressing_loop":-33.1, "amb_drone_loop":-17.4, "amb_home_loop":-41.9, "amb_roof_loop":-24.6, "amb_service_loop":-30.0, "hor_lili_glimpse":-21.0, "hor_mirror_empty":-30.0, "hor_mirror_smile":-18.3, "hor_richard_photo":-22.0, "hor_walter_arrival":-20.0, "mus_menu_loop":-19.9, "mus_show_outro":-15.9, "mus_show_outro_ending":-15.0, "mus_show_outro_loop":-15.9, "mus_tension_loop":-25.9, "sfx_applause":-18.0, "sfx_applause_uneven_tail":-24.0, "sfx_box_bump":-21.2, "sfx_box_rustle":-27.8, "sfx_breath_a":-19.7, "sfx_breath_b":-19.6, "sfx_breath_c":-17.8, "sfx_breath_panic":-18.8, "sfx_canvas_flap":-26.9, "sfx_contract_sign":-24.2, "sfx_corridor_knock_back":-20.0, "sfx_corridor_knock_back_wet":-18.6, "sfx_corridor_knock_front":-20.4, "sfx_corridor_knock_front_wet":-17.0, "sfx_creak_wood":-18.8, "sfx_curtain_open":-24.0, "sfx_door_locked":-22.0, "sfx_elsa_lower":-23.0, "sfx_elsa_rig_creak":-31.8, "sfx_escape_wind":-24.6, "sfx_flashlight_click":-20.8, "sfx_hairpin_receive":-26.0, "sfx_heartbeat":-23.3, "sfx_key_pickup":-26.2, "sfx_knife_pickup":-26.2, "sfx_light_flicker":-34.7, "sfx_lili_jump":-24.0, "sfx_lock_hairpin":-23.8, "sfx_photo_drop":-28.6, "sfx_photo_take":-26.0, "sfx_roof_crack":-27.4, "sfx_roof_crack_wet":-23.7, "sfx_roof_debris":-25.1, "sfx_roof_debris_wet":-22.2, "sfx_roof_jump":-21.4, "sfx_rope_cut":-21.0, "sfx_service_door_open":-26.1, "sfx_step_clinic":-23.1, "sfx_step_mordecai":-25.7, "sfx_step_wood":-24.0, "sfx_whisper":-16.8, "ui_back":-23.9, "ui_confirm":-23.3, "vo_audience_again":-22.0, "vo_bruno_blip":-17.7, "vo_bruno_da":-21.0, "vo_bruno_mgm":-21.0, "vo_elsa_blip":-18.3, "vo_elsa_sigh":-21.0, "vo_lili_blip":-17.5, "vo_lili_giggle":-21.0, "vo_mordecai_blip":-16.2, "vo_mordecai_laugh":-21.0, "vo_mordecai_smile":-21.0, "vo_richard_blip":-21.1, "vo_richard_uh":-21.0, "vo_walter_blip":-16.9, "vo_walter_hm":-21.0}
const TIER_DB := {"scare":-22.0, "sfx":-34.0, "applause":-32.0, "emote":-28.0, "voice":-30.0, "ui":-37.0, "music":-40.0, "amb":-46.0, "drone":-50.0, "foley":-42.0, "step":-52.0, "npc_step":-52.0, "breath":-50.0, "heart":-36.0}
const SCARES := ["hor_lili_glimpse","hor_mirror_smile","hor_walter_arrival","hor_richard_photo","sfx_roof_crack","sfx_roof_crack_wet","sfx_corridor_knock_front","sfx_corridor_knock_back","sfx_box_bump","sfx_lili_jump","sfx_roof_jump","sfx_escape_wind"]
const FOLEY := ["sfx_creak_wood","sfx_canvas_flap","sfx_box_rustle","sfx_elsa_rig_creak","sfx_light_flicker","sfx_curtain_open","sfx_roof_debris","sfx_roof_debris_wet"]
# Tonal chimes would sound like game pickups; they are routed through the softened UI bus.
const SOFT := ["sfx_key_pickup","sfx_knife_pickup","sfx_hairpin_receive","sfx_flashlight_click"]
# Reverb per room: [room_size, wet]. The arena is a big hall, service/dressing are tight corridors.
const ROOM_REVERB := {"arena_show":[.88,.32], "arena_empty":[.92,.38], "dressing":[.4,.2], "service":[.55,.3], "clinic":[.35,.18], "roof":[.2,.06], "home":[.3,.12], "":[.4,.1]}
# Low drone under each room, relative to the drone tier (dB).
const ROOM_DRONE := {"arena_show":-12.0, "arena_empty":0.0, "dressing":-2.0, "service":3.0, "clinic":2.0, "roof":-6.0, "home":-2.0}
var game
var streams := {}
var music: AudioStreamPlayer
var beds: Array[AudioStreamPlayer] = []
var voice_pool: Array[AudioStreamPlayer] = []
var voice_next := 0
var voice := ""
var letters := 0
var zone := ""
var bed_index := 0
var bed_fade: Tween
var music_fade: Tween
var pending: Array[Tween] = []
var effects: Array[Node] = []
var paused := false
var paused_tweens: Array[Tween] = []
var ending := false
var step_distance := 0.0
var previous_position := Vector3.ZERO
var previous_mordecai := Vector3.ZERO
var mordecai_step := 0.0
var random_clock := 8.0
var flicker_clock := 4.0
var rig_clock := 11.0
var box_clock := 1.0
var drone: AudioStreamPlayer
var drone_fade: Tween
var next_step := .95
var recent := {} # Last variation in each family; avoid immediate repeats.

func setup(owner_game) -> void:
	game = owner_game
	for bus_name in ["Music", "Ambience", "SFX", "Voice", "UI", "Steps"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count-1,bus_name)
	build_bus_effects()
	# A limiter catches overlapping stingers without changing the volume slider.
	if AudioServer.get_bus_effect_count(0) == 0:
		AudioServer.add_bus_effect(0, AudioEffectLimiter.new())
	music = make_player("Music", -60)
	for i in 2: beds.append(make_player("Ambience", -60))
	drone = make_player("Ambience", -60)
	for i in 4: voice_pool.append(make_player("Voice", -30))
	previous_position = game.player.position
	previous_mordecai = game.actors.mordecai.position
	game.hud.character_revealed.connect(on_character)
	game.hud.voice_started.connect(begin_line)
	game.hud.voice_stopped.connect(stop_voice)
	game.hud.ui_sound.connect(ui)
	sync(true)

# Reverb on rooms and softening filters; added once per bus, never stacked.
func build_bus_effects() -> void:
	var setups := {"SFX":[true,0.0], "Ambience":[true,0.0], "Steps":[true,1400.0], "Voice":[false,4200.0], "UI":[false,2300.0]}
	for bus_name in setups:
		var bus := AudioServer.get_bus_index(bus_name)
		if AudioServer.get_bus_effect_count(bus) > 0: continue
		if setups[bus_name][1] > 0.0:
			var low := AudioEffectLowPassFilter.new()
			low.cutoff_hz = setups[bus_name][1]
			AudioServer.add_bus_effect(bus, low)
		if setups[bus_name][0]:
			var reverb := AudioEffectReverb.new()
			reverb.damping = .6; reverb.dry = 1.0; reverb.spread = 1.0
			AudioServer.add_bus_effect(bus, reverb)
		AudioServer.set_bus_volume_db(bus, 0.0)

func set_room_reverb(room: String) -> void:
	var cfg: Array = ROOM_REVERB.get(room, ROOM_REVERB[""])
	for bus_name in ["SFX", "Ambience", "Steps"]:
		var bus := AudioServer.get_bus_index(bus_name)
		for i in AudioServer.get_bus_effect_count(bus):
			var fx := AudioServer.get_bus_effect(bus, i)
			if fx is AudioEffectReverb:
				fx.room_size = cfg[0]
				fx.wet = cfg[1] * (.55 if bus_name == "Ambience" else (.7 if bus_name == "Steps" else 1.0))

func tier_of(id: String) -> String:
	var key := family(id)
	if id.begins_with("vo_"): return "voice" if "_blip_" in id else "emote"
	if id.begins_with("ui_"): return "ui"
	if id.begins_with("amb_"): return "amb"
	if id.begins_with("mus_"): return "music"
	if key == "sfx_step_mordecai": return "npc_step"
	if key.begins_with("sfx_step_"): return "step"
	if key.begins_with("sfx_breath"): return "breath"
	if key == "sfx_heartbeat": return "heart"
	if key.begins_with("sfx_applause"): return "applause"
	if SCARES.has(key): return "scare"
	if FOLEY.has(key): return "foley"
	return "sfx"

func family(id: String) -> String:
	if LOUD.has(id): return id
	var rx := RegEx.create_from_string("_\\d\\d(_wet)?$")
	var m := rx.search(id)
	if m == null: return id
	return id.substr(0, m.get_start()) + (m.get_string(1))

# Player volume for one sound: tier target minus the file's measured loudness, plus a trim.
func level_db(id: String, trim := 0.0) -> float:
	var key := family(id)
	if id.begins_with("vo_") and "_blip_" in id: key = id.substr(0, id.find("_blip_")) + "_blip"
	return TIER_DB[tier_of(id)] - float(LOUD.get(key, -24.0)) + trim

func make_player(bus: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus; p.volume_db = db; add_child(p)
	return p

func stream(id: String) -> AudioStream:
	if not streams.has(id):
		var path: String = MANIFEST.data.get(id, FULL_MANIFEST.data.get(id,""))
		assert(not path.is_empty(), "Unknown chapter audio: " + id)
		streams[id] = load(path)
	return streams[id]

func loop_stream(id: String) -> AudioStream:
	var value: AudioStream = stream(id).duplicate()
	if value is AudioStreamWAV:
		value.loop_mode = AudioStreamWAV.LOOP_FORWARD
		value.loop_begin = 0
		value.loop_end = int(value.get_length()*value.mix_rate)
	elif value is AudioStreamOggVorbis: value.loop=true
	return value

func variation(prefix: String, count: int) -> String:
	var index := randi_range(1,count)
	if count > 1 and index == recent.get(prefix,0): index = index % count + 1
	recent[prefix] = index
	return "%s_%02d" % [prefix,index]

# `db` is a legacy argument and is ignored: levels come from level_db(). Use `trim` to
# make one particular call quieter or louder than its tier (dB).
func play(id: String, db: float = 0.0, at: Vector3 = Vector3.INF, bus: String = "SFX", trim := 0.0) -> Node:
	if SOFT.has(family(id)) and bus == "SFX": bus = "UI"
	var p: Node
	if at == Vector3.INF:
		p = AudioStreamPlayer.new()
	else:
		p = AudioStreamPlayer3D.new()
		p.max_distance = 35
		p.unit_size = 7
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.stream = stream(id); p.bus = bus; p.volume_db = level_db(id, trim)
	p.set_meta("cue",id)
	add_child(p)
	if p is Node3D: p.global_position = at
	effects.append(p)
	p.finished.connect(func(): effects.erase(p); p.queue_free())
	p.play()
	return p

func later(seconds: float, action: Callable) -> void:
	var tween := create_tween()
	pending.append(tween)
	tween.tween_interval(seconds)
	tween.tween_callback(action)

func set_music(id: String, immediate := false) -> void:
	if music.get_meta("cue", "") == id: return
	if music_fade: music_fade.kill()
	music.set_meta("cue", id)
	if immediate:
		music.stop()
		if not id.is_empty(): music.stream=loop_stream(id); music.volume_db=level_db(id); music.play()
		return
	music_fade=create_tween()
	music_fade.tween_property(music,"volume_db",-60, .5)
	music_fade.tween_callback(func():
		music.stop()
		if not id.is_empty(): music.stream=loop_stream(id); music.play())
	music_fade.tween_property(music,"volume_db",level_db(id) if not id.is_empty() else -40.0, .8)

func desired_zone() -> String:
	if game.menu_kind in ["main","end"]: return ""
	if game.phase == "intro": return "arena_show"
	var room: String = game.room_at(game.player.position)
	return {"arena":"arena_empty", "dressing":"dressing", "service":"service", "clinic":"clinic", "roof":"roof", "home":"home"}.get(room,"arena_empty")

func sync(immediate := false) -> void:
	var next := desired_zone()
	if zone != next:
		zone = next
		if bed_fade: bed_fade.kill()
		var old := beds[bed_index]
		bed_index = 1-bed_index
		var current := beds[bed_index]
		current.stop(); current.volume_db = -60
		var bed_db := -60.0
		if not next.is_empty():
			current.stream=loop_stream("amb_"+next+"_loop"); current.play()
			bed_db = level_db("amb_"+next+"_loop")
		set_room_reverb(next)
		set_drone(next, immediate)
		if immediate:
			old.stop();current.volume_db=bed_db
		else:
			bed_fade=create_tween().set_parallel(true)
			bed_fade.tween_property(old,"volume_db",-60,1.2)
			bed_fade.tween_property(current,"volume_db",bed_db,1.2)
			bed_fade.chain().tween_callback(old.stop)
	if game.phase != "intro": ending=false
	var cue := ""
	if game.menu_kind in ["main","end"]: cue="mus_menu_loop"
	elif game.phase == "intro" and not ending: cue="mus_show_outro_loop"
	elif game.phase in ["technical","photos","walter","contract","trapped","captured"]: cue="mus_tension_loop"
	elif game.phase in ["home","bathroom"]:cue="mus_menu_loop"
	if not ending: set_music(cue,immediate)

# Constant low rumble under every room so silence never feels empty.
func set_drone(room: String, immediate := false) -> void:
	if drone_fade: drone_fade.kill()
	if room.is_empty() or not ROOM_DRONE.has(room):
		drone_fade = create_tween()
		drone_fade.tween_property(drone, "volume_db", -60, 1.0)
		drone_fade.tween_callback(drone.stop)
		return
	var target := level_db("amb_drone_loop", ROOM_DRONE[room])
	if not drone.playing:
		drone.stream = loop_stream("amb_drone_loop")
		drone.volume_db = -60
		drone.play()
	if immediate: drone.volume_db = target
	else:
		drone_fade = create_tween()
		drone_fade.tween_property(drone, "volume_db", target, 2.5)

func cue(id: String) -> void:
	match id:
		"applause":
			if ending: return
			ending=true
			if music_fade: music_fade.kill()
			var delay := 1.071 - fmod(music.get_playback_position(),1.071)
			later(delay,func(): music.stop(); music.set_meta("cue",""); play("mus_show_outro_ending",-16,Vector3.INF,"Music"))
			later(delay+3.21,func(): play("sfx_applause",-10); game.location.stage_show.start_applause())
			later(delay+11.51,func(): play("sfx_applause_uneven_tail",-12))
		"crack":
			# Canvas rips first (flap sped up), then the dome cracks and debris falls.
			var rip:=play(variation("sfx_canvas_flap",3),-3);rip.pitch_scale=1.5
			later(.35,func(): play("sfx_roof_crack_wet",-6))
			later(1.5,func(): play(variation("sfx_roof_debris",3)+"_wet",-10))
		"curtain": play(variation("sfx_curtain_open",2),-8,game.location.gates.dressing.global_position)
		"rigging": play("sfx_elsa_lower",-9,game.actors.elsa.global_position)
		"mirror_empty": play("hor_mirror_empty",-9)
		"mirror_smile": play("hor_mirror_smile",-6)
		"hairpin": play("sfx_hairpin_receive",-7)
		"service_open": play("sfx_service_door_open",-8,game.location.gates.technical.global_position)
		"unlock":
			play("sfx_lock_hairpin",-6,game.location.gates.technical.global_position)
			later(1.0,func(): play("sfx_service_door_open",-8,game.location.gates.technical.global_position))
		"locked": play("sfx_door_locked",-9,game.location.gates.technical.global_position)
		"knock_front": play("sfx_corridor_knock_front",-5,game.player.global_position-game.player.global_basis.z*4+Vector3.UP)
		"knock_back": play("sfx_corridor_knock_back",-5,game.player.global_position+game.player.global_basis.z*3+Vector3.UP)
		"box_first": play("sfx_box_bump_01",-7,game.layout.TRUNK)
		"box_second":
			play("sfx_box_bump_02",-7,game.layout.TRUNK)
			later(.2,func(): play("sfx_lili_jump",-8,game.layout.TRUNK))
		"lili_glimpse": play("hor_lili_glimpse",-6); flicker()
		"photo_take": play("sfx_photo_take",-7)
		"richard_photo": play("hor_richard_photo",-7)
		"photo_drop": play("sfx_photo_drop",-7)
		"walter": play("hor_walter_arrival",-7)
		"audience": play("vo_audience_again",-7,Vector3.INF,"Voice")

func flicker() -> void:
	var light: OmniLight3D = game.location.lamps[7+randi_range(0,1)]
	play(variation("sfx_light_flicker",3),-18,light.global_position)
	light.light_energy=.08
	later(.12,func(): light.light_energy=float(light.get_meta("rest_energy",1.35)))

func begin_line(id: String) -> void:
	stop_voice(); voice=id; letters=0

func stop_voice() -> void:
	voice=""
	for p in voice_pool: p.stop()
	for p in effects.duplicate():
		if is_instance_valid(p) and p.bus=="Voice":
			p.stop();effects.erase(p);p.queue_free()

func on_character(letter: String) -> void:
	if paused or not VOICES.has(voice) or letter.strip_edges().is_empty() or ".,!?…—-:;«»\"()".contains(letter): return
	for effect in effects:
		if is_instance_valid(effect) and effect.bus=="Voice" and effect.playing: return
	var cfg: Array=VOICES[voice]
	letters+=1
	if (letters-1)%int(cfg[0])!=0: return
	var id := variation("vo_"+voice+"_blip",12)
	var p := voice_pool[voice_next];voice_next=(voice_next+1)%voice_pool.size()
	p.stream=stream(id);p.volume_db=level_db(id);p.pitch_scale=randf_range(1-cfg[1],1+cfg[1]);p.play()

func emote(id: String) -> void:
	play("vo_"+id,-9,Vector3.INF,"Voice")

func ui(back := false) -> void:
	play("ui_back" if back else variation("ui_confirm",3),0,Vector3.INF,"UI")

func set_paused(value: bool) -> void:
	if paused==value: return
	paused=value
	for p in effects:
		if is_instance_valid(p) and p.bus != "UI": p.stream_paused=value
	for p in beds: p.stream_paused=value
	drone.stream_paused=value
	music.stream_paused=value
	if value:
		paused_tweens.clear()
		for tween in pending+([bed_fade] if bed_fade else [])+([music_fade] if music_fade else []):
			if tween and tween.is_valid() and tween.is_running():
				tween.pause();paused_tweens.append(tween)
	else:
		for tween in paused_tweens:
			if tween and tween.is_valid(): tween.play()
		paused_tweens.clear()
	for p in voice_pool: p.stream_paused=value

func reset() -> void:
	for tween in pending:
		if tween and tween.is_valid():tween.kill()
	pending.clear()
	for p in effects:
		if is_instance_valid(p): p.stop();p.queue_free()
	effects.clear();stop_voice();ending=false
	music.stop();music.set_meta("cue", "")
	if music_fade: music_fade.kill()
	if bed_fade: bed_fade.kill()
	for p in beds: p.stop()
	zone="reset"
	set_paused(false)
	for light in game.location.lamps: light.light_energy=float(light.get_meta("rest_energy",1.35))
	random_clock=randf_range(6,20);rig_clock=randf_range(12,24);flicker_clock=randf_range(3,8);box_clock=1
	step_distance=0;mordecai_step=0;next_step=.95
	if drone_fade: drone_fade.kill()
	drone.stop()
	previous_position=game.player.position;previous_mordecai=game.actors.mordecai.position

func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	for i in range(pending.size()-1,-1,-1):
		if not pending[i].is_valid(): pending.remove_at(i)
	sync()
	var position: Vector3=game.player.global_position
	var walked := Vector2(position.x-previous_position.x,position.z-previous_position.z).length()
	previous_position=position
	var mordecai: Node3D=game.actors.mordecai
	var npc_walked := mordecai.position.distance_to(previous_mordecai)
	previous_mordecai=mordecai.position
	if paused or game.hud.menu.visible:return
	if not game.player.locked and game.player.is_on_floor() and walked<1 and walked>.002:
		step_distance+=walked
		if step_distance>next_step:
			step_distance=0
			next_step=randf_range(.78,1.18) # uneven stride: no machine-gun rhythm
			if randf()>.08: # now and then a step is missed or too soft to hear
				var step: Node = play(variation("sfx_step_clinic" if game.room_at(position) in ["clinic","home"] else "sfx_step_wood",8),0,Vector3.INF,"Steps",randf_range(-4.5,1.0))
				step.pitch_scale = randf_range(.82,1.02)
	else:step_distance=0
	if mordecai.visible and npc_walked>.001 and npc_walked<1:
		mordecai_step+=npc_walked
		if mordecai_step>.8:
			mordecai_step=0;var m_step: Node = play(variation("sfx_step_mordecai",4),0,mordecai.global_position,"Steps",randf_range(-3.0,1.0)); m_step.pitch_scale=randf_range(.85,1.0)
	random_clock-=delta;flicker_clock-=delta;rig_clock-=delta;box_clock-=delta
	if random_clock<=0:
		random_clock=randf_range(6,20)
		if zone in ["arena_empty","service"]:
			play(variation("sfx_canvas_flap",3) if zone=="arena_empty" and randf()<.35 else variation("sfx_creak_wood",5),-21,position+Vector3(randf_range(-5,5),3,randf_range(-5,5)))
	if zone=="service" and flicker_clock<=0:flicker_clock=randf_range(9,24);flicker()
	if rig_clock<=0:
		rig_clock=randf_range(12,24)
		if game.actors.elsa.visible:play(variation("sfx_elsa_rig_creak",3),-24,game.actors.elsa.global_position)
	if game.phase=="to_hall" and box_clock<=0:
		box_clock=randf_range(2,4);play(variation("sfx_box_rustle",3),-10,game.layout.TRUNK)

func shutdown() -> void:
	for tween in pending+([bed_fade] if bed_fade else [])+([music_fade] if music_fade else [])+([drone_fade] if drone_fade else []):
		if tween and tween.is_valid(): tween.kill()
	pending.clear();paused_tweens.clear();bed_fade=null;music_fade=null;drone_fade=null
	for p in get_children():
		if p is AudioStreamPlayer or p is AudioStreamPlayer3D:
			p.stop();p.stream=null
	streams.clear()
