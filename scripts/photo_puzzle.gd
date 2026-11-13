extends CanvasLayer
## Torn, worn photographs on the clinic wall and the optional reassembly puzzle.
## Wall pieces and board pieces share one wear shader; wear 1 -> 0 restores the print.
signal closed(id: String, solved: bool)
const SHADER := preload("res://assets/shaders/photo_wear.gdshader")
const UI_SHADER := preload("res://assets/shaders/photo_wear_ui.gdshader")
const GRIDS := {"bruno": Vector2i(3, 3), "elsa": Vector2i(3, 3), "lili": Vector2i(3, 3), "child": Vector2i(3, 4)}
const LINES := {
	"bruno": "Теперь видно лицо.",
	"elsa": "Эльза. Теперь видно её целиком.",
	"lili": "Лили. Целая, как раньше.",
	"child": "Это я. Совсем маленький.",
}
const SNAP := 0.4
var game: Node3D
var walls := {}
var glass_off := {}
var active := ""
var busy := false
var pieces: Array = []
var board_rect := Rect2()
var cell := Vector2.ONE
var texture: Texture2D
var root: Control
var board: Control
var caption: Label
var full_photo: TextureRect
var drag := -1
var drag_source := ""
var grab := Vector2.ZERO
var touch_index := -1

static func photo_texture(id: String) -> Texture2D:
	if id == "child": return load("res://assets/story/photos/richard_child_portrait.png")
	var path := "res://assets/story/photos/" + id + "_before.webp"
	return load(path) if ResourceLoader.exists(path) else null

static func flag_name(id: String) -> String:
	return "puzzle_" + id + "_done"

func is_done(id: String) -> bool:
	return game != null and bool(game.flags.get(flag_name(id), false))

# Deterministic derangement per id: piece i sits in cell result[i] (never its own).
# Prefers layouts where no two originally adjacent pieces stay adjacent.
static func shuffled_slots(id: String, grid: Vector2i) -> Array:
	var n := grid.x * grid.y
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("shuffle_" + id)
	var best: Array = []
	var best_score := 1 << 30
	for attempt in 400:
		var perm: Array = range(n)
		for i in range(n - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = perm[i]; perm[i] = perm[j]; perm[j] = t
		var fixed := false
		for i in n:
			if perm[i] == i: fixed = true
		if fixed: continue
		var score := 0
		for i in n:
			if i % grid.x < grid.x - 1 and perm[i + 1] == perm[i] + 1 and perm[i] % grid.x < grid.x - 1: score += 1
			if i + grid.x < n and perm[i + grid.x] == perm[i] + grid.x: score += 1
		if score < best_score:
			best_score = score; best = perm
		if score == 0: break
	if best.is_empty():
		for i in n: best.append((i + 1) % n)
	return best

# Builds the torn pieces (and the glass over them) as children of parent, centred on at.
func build_wall(id: String, parent: Node3D, at: Vector3, size: Vector2, tint: Color) -> void:
	var tex := photo_texture(id)
	var grid: Vector2i = GRIDS[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var perm := shuffled_slots(id, grid)
	var group := Node3D.new()
	group.name = "TornPhoto_" + id
	group.position = at
	parent.add_child(group)
	var cw := size.x / grid.x
	var ch := size.y / grid.y
	var list: Array = []
	for index in grid.x * grid.y:
		var col := index % grid.x
		var row := index / grid.x
		var piece := MeshInstance3D.new()
		piece.name = "Piece%d_%d" % [col, row]
		var quad := QuadMesh.new()
		quad.size = Vector2(cw, ch)
		piece.mesh = quad
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("photo", tex)
		material.set_shader_parameter("region", Vector4(float(col) / grid.x, float(row) / grid.y, 1.0 / grid.x, 1.0 / grid.y))
		material.set_shader_parameter("seed", float(index) * 1.37 + rng.randf() * 5.0)
		material.set_shader_parameter("aspect", Vector2(cw, ch) / ch)
		material.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		material.set_shader_parameter("wear", 1.0)
		piece.material_override = material
		var center := Vector3((col + .5 - grid.x * .5) * cw, (grid.y * .5 - row - .5) * ch, 0)
		piece.set_meta("flat", Transform3D(Basis.IDENTITY.scaled(Vector3(1.012, 1.012, 1)), center + Vector3(0, 0, 0.0001 * index)))
		var target: int = perm[index]
		var tcell := Vector2i(target % grid.x, target / grid.x)
		var tcenter := Vector3((tcell.x + .5 - grid.x * .5) * cw, (grid.y * .5 - tcell.y - .5) * ch, 0)
		var angle := rng.randf_range(.14, .26) * (1.0 if rng.randf() < .5 else -1.0)
		var torn := Basis(Vector3.BACK, angle).scaled(Vector3(.9, .9, 1))
		piece.set_meta("torn", Transform3D(torn, tcenter + Vector3(rng.randf_range(-.02, .02) * cw / .24, rng.randf_range(-.02, .02) * ch / .24, 0.0004 * (1 + index % 5))))
		piece.set_meta("home", Vector2i(col, row))
		piece.set_meta("slot", tcell)
		group.add_child(piece)
		list.append(piece)
	var glass := MeshInstance3D.new()
	glass.name = "Glass_" + id
	var plate := QuadMesh.new()
	plate.size = size + Vector2(.04, .04)
	glass.mesh = plate
	var glass_material := StandardMaterial3D.new()
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.albedo_color = Color(.82, .9, .95, .13)
	glass_material.roughness = .04
	glass_material.metallic_specular = 1.0
	glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.material_override = glass_material
	glass.position = at + Vector3(0, 0, .014)
	parent.add_child(glass)
	walls[id] = {"group": group, "pieces": list, "glass": glass, "glass_at": glass.position}
	_blend_wall(0.0 if is_done(id) else 1.0, id)

func wall_meshes(id: String) -> Array:
	return walls[id]["pieces"] if walls.has(id) else []

func set_wear(id: String, value: float) -> void:
	for piece in wall_meshes(id):
		piece.material_override.set_shader_parameter("wear", value)

func _blend_wall(value: float, id: String) -> void:
	# value 1 = torn scraps, 0 = merged clean print.
	for piece in wall_meshes(id):
		piece.transform = (piece.get_meta("flat") as Transform3D).interpolate_with(piece.get_meta("torn"), value)
	set_wear(id, value)

# Applies the saved state to every wall photo (called from staging/sync).
func sync() -> void:
	for id in walls:
		var done := is_done(id)
		if done: glass_off.erase(id)
		_blend_wall(0.0 if done else 1.0, id)
		var glass: MeshInstance3D = walls[id]["glass"]
		glass.visible = not done and not glass_off.has(id)
		glass.position = walls[id]["glass_at"]
		(glass.material_override as StandardMaterial3D).albedo_color.a = .13

func remove_glass(id: String) -> void:
	glass_off[id] = true
	var glass: MeshInstance3D = walls[id]["glass"]
	if not glass.visible: return
	var material := glass.material_override as StandardMaterial3D
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(glass, "position:y", walls[id]["glass_at"].y + .5, .6)
	tween.tween_property(glass, "position:z", walls[id]["glass_at"].z + .25, .6)
	tween.tween_property(material, "albedo_color:a", 0.0, .6)
	tween.chain().tween_callback(func(): glass.visible = false)

func restore_wall(id: String) -> void:
	if not walls.has(id): return
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_blend_wall.bind(id), 1.0, 0.0, .8)

# Opens the board. Glass must already be gone (see remove_glass).
func open(id: String) -> void:
	if active != "" or not GRIDS.has(id): return
	active = id
	busy = false
	texture = photo_texture(id)
	var grid: Vector2i = GRIDS[id]
	layer = 0
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(.03, .02, .03, .86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var title := Label.new()
	title.name = "Title"
	title.text = "Сложи фотографию"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 14
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("e4d6bf"))
	root.add_child(title)
	board = Control.new()
	board.name = "Board"
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.draw.connect(_draw_board)
	root.add_child(board)
	full_photo = TextureRect.new()
	full_photo.texture = texture
	full_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	full_photo.stretch_mode = TextureRect.STRETCH_SCALE
	full_photo.modulate.a = 0
	full_photo.visible = false
	full_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(full_photo)
	pieces.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for index in grid.x * grid.y:
		var rect := ColorRect.new()
		rect.name = "Piece%d" % index
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = UI_SHADER
		material.set_shader_parameter("photo", texture)
		material.set_shader_parameter("region", Vector4(float(index % grid.x) / grid.x, float(index / grid.x) / grid.y, 1.0 / grid.x, 1.0 / grid.y))
		material.set_shader_parameter("seed", float(index) * 1.37 + rng.randf() * 5.0)
		material.set_shader_parameter("wear", 1.0)
		rect.material = material
		root.add_child(rect)
		pieces.append({"node": rect, "slot": Vector2i(index % grid.x, index / grid.x), "locked": false})
	caption = Label.new()
	caption.name = "Caption"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -120
	caption.offset_bottom = -76
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_color", Color("f1e4c8"))
	caption.modulate.a = 0
	root.add_child(caption)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "Отложить"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(220, 54)
	back.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	back.offset_left = -110
	back.offset_right = 110
	back.offset_top = -70
	back.offset_bottom = -16
	back.pressed.connect(close.bind(false))
	root.add_child(back)
	get_viewport().size_changed.connect(layout)
	layout()
	_scatter(rng)
	root.modulate.a = 0
	create_tween().tween_property(root, "modulate:a", 1.0, .25)

func layout() -> void:
	if active == "": return
	var grid: Vector2i = GRIDS[active]
	var vp := get_viewport().get_visible_rect().size
	var aspect := 1.0 if active != "child" else 0.72 / 0.89
	var bw: float
	var bh: float
	if vp.x >= vp.y * 1.1:
		bh = minf(vp.y * .66, vp.x * .44 / aspect)
		bw = bh * aspect
		board_rect = Rect2(Vector2(vp.x * .06 + (vp.x * .44 - bw) * .5, (vp.y - bh) * .5), Vector2(bw, bh))
	else:
		bw = minf(vp.x * .8, vp.y * .32 * aspect)
		bh = bw / aspect
		board_rect = Rect2(Vector2((vp.x - bw) * .5, vp.y * .1), Vector2(bw, bh))
	cell = board_rect.size / Vector2(grid)
	board.position = Vector2.ZERO
	board.size = vp
	board.queue_redraw()
	full_photo.position = board_rect.position
	full_photo.size = board_rect.size
	for entry in pieces:
		var rect: ColorRect = entry["node"]
		rect.size = cell
		(rect.material as ShaderMaterial).set_shader_parameter("aspect", cell / cell.y)
		if entry["locked"]: rect.position = slot_center(entry["slot"]) - cell * .5

func _scatter(rng: RandomNumberGenerator) -> void:
	var vp := get_viewport().get_visible_rect().size
	var tray: Rect2
	if vp.x >= vp.y * 1.1: tray = Rect2(vp.x * .54, vp.y * .12, vp.x * .42, vp.y * .74)
	else: tray = Rect2(vp.x * .05, board_rect.end.y + 14, vp.x * .9, vp.y - board_rect.end.y - 96)
	var open_pieces: Array = []
	for entry in pieces:
		if not entry["locked"]: open_pieces.append(entry)
	var count := open_pieces.size()
	var tcols := 3
	var trows := ceili(float(count) / tcols)
	var spare := Vector2(maxf(tray.size.x - cell.x, 0), maxf(tray.size.y - cell.y, 0))
	var slots: Array = range(count)
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = slots[i]; slots[i] = slots[j]; slots[j] = t
	for i in count:
		var s: int = slots[i]
		var at := tray.position + Vector2(spare.x * (s % tcols) / maxf(tcols - 1, 1), spare.y * (s / tcols) / maxf(trows - 1, 1))
		at += Vector2(rng.randf_range(-.12, .12), rng.randf_range(-.12, .12)) * cell
		open_pieces[i]["node"].position = at.clamp(Vector2.ZERO, vp - cell)

func slot_center(slot: Vector2i) -> Vector2:
	return board_rect.position + (Vector2(slot) + Vector2(.5, .5)) * cell

func _draw_board() -> void:
	board.draw_rect(board_rect.grow(10), Color("392c27"))
	board.draw_rect(board_rect, Color(.1, .08, .07))
	var grid: Vector2i = GRIDS[active]
	var line := Color(.9, .82, .65, .22)
	for x in range(1, grid.x): board.draw_line(board_rect.position + Vector2(cell.x * x, 0), board_rect.position + Vector2(cell.x * x, board_rect.size.y), line, 1.0)
	for y in range(1, grid.y): board.draw_line(board_rect.position + Vector2(0, cell.y * y), board_rect.position + Vector2(board_rect.size.x, cell.y * y), line, 1.0)
	board.draw_rect(board_rect, Color(.9, .82, .65, .5), false, 2.0)

func _input(event: InputEvent) -> void:
	if active == "" or busy or (game and game.hud.menu.visible): return
	var pos := Vector2.ZERO
	var kind := ""
	var source := ""
	if event is InputEventScreenTouch:
		pos = event.position; kind = "down" if event.pressed else "up"; source = "touch"
		if event.pressed and touch_index == -1: touch_index = event.index
		elif event.index != touch_index: return
		elif not event.pressed: touch_index = -1
	elif event is InputEventScreenDrag:
		if event.index != touch_index: return
		pos = event.position; kind = "move"; source = "touch"
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position; kind = "down" if event.pressed else "up"; source = "mouse"
	elif event is InputEventMouseMotion:
		pos = event.position; kind = "move"; source = "mouse"
	else: return
	if drag >= 0 and source != drag_source: return
	match kind:
		"down":
			if drag >= 0: return
			var hit := pick(pos)
			if hit < 0: return
			drag = hit; drag_source = source
			var node: ColorRect = pieces[hit]["node"]
			grab = pos - node.position
			root.move_child(node, root.get_child_count() - 3)
			get_viewport().set_input_as_handled()
		"move":
			if drag < 0: return
			var node: ColorRect = pieces[drag]["node"]
			node.position = pos - grab
			get_viewport().set_input_as_handled()
		"up":
			if drag < 0: return
			var held := drag
			drag = -1; drag_source = ""
			drop_piece(held, pos - grab + cell * .5)
			get_viewport().set_input_as_handled()

func pick(pos: Vector2) -> int:
	for i in range(pieces.size() - 1, -1, -1):
		var entry: Dictionary = pieces[i]
		if entry["locked"]: continue
		if Rect2(entry["node"].position, cell).has_point(pos): return i
	# Overlapping pieces: the last child drawn is on top.
	return -1

# Drops piece i with its centre at `center`. Snaps and locks it near its slot.
func drop_piece(i: int, center: Vector2) -> bool:
	var entry: Dictionary = pieces[i]
	var node: ColorRect = entry["node"]
	if entry["locked"]: return false
	node.position = center - cell * .5
	if center.distance_to(slot_center(entry["slot"])) > SNAP * maxf(cell.x, cell.y):
		return false
	entry["locked"] = true
	node.position = slot_center(entry["slot"]) - cell * .5
	root.move_child(node, 4)
	if is_complete(): _finish()
	return true

func placed_count() -> int:
	var n := 0
	for entry in pieces:
		if entry["locked"]: n += 1
	return n

func is_complete() -> bool:
	return not pieces.is_empty() and placed_count() == pieces.size()

func _finish() -> void:
	busy = true
	var id := active
	root.move_child(full_photo, root.get_child_count() - 3)
	full_photo.visible = true
	if game:
		game.flags[flag_name(id)] = true
		game.save_game()
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for entry in pieces:
		tween.parallel().tween_property(entry["node"].material, "shader_parameter/wear", 0.0, 1.0)
	tween.tween_property(full_photo, "modulate:a", 1.0, .5)
	tween.tween_callback(func():
		caption.text = LINES.get(id, "")
		create_tween().tween_property(caption, "modulate:a", 1.0, .4))
	tween.tween_interval(2.0)
	tween.tween_callback(close.bind(true))

func close(solved: bool) -> void:
	if active == "": return
	var id := active
	var was_solved := solved or is_done(id)
	if get_viewport().size_changed.is_connected(layout): get_viewport().size_changed.disconnect(layout)
	if is_instance_valid(root): root.queue_free()
	root = null
	pieces.clear()
	active = ""
	busy = false
	drag = -1
	touch_index = -1
	if was_solved:
		sync()
		# sync() snaps the wall to clean; replay the merge from the torn state.
		restore_wall(id)
	closed.emit(id, was_solved)
