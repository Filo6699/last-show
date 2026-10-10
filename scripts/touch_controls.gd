extends Control
## Separate touch indices let walking and looking work at the same time.
signal move_changed(value: Vector2)
signal look_changed(value: Vector2)
signal target_tapped
var target_rect := Rect2()
var tap_origin := Vector2.ZERO
var tap_time := 0
var tap_moved := false
const JOYSTICK_RADIUS := 99.0
const JOYSTICK_TRAVEL := 96.0
const KNOB_RADIUS := 36.0
var move_index: int = -1
var look_index: int = -1
var origin: Vector2
var knob: Vector2

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			# Only pause owns a fixed corner; interaction belongs to the outlined object.
			if event.position.x > size.x-100 and event.position.y < 85:
				return
			if not target_rect.has_point(event.position) and event.position.x < size.x * 0.45 and event.position.y > size.y * .35 and move_index == -1:
				move_index = event.index
				origin = event.position
				knob = origin
			elif look_index == -1:
				look_index = event.index
				tap_origin = event.position
				tap_time = Time.get_ticks_msec()
				tap_moved = false
		else:
			if event.index == move_index:
				move_index = -1
				move_changed.emit(Vector2.ZERO)
			if event.index == look_index:
				look_index = -1
				if not tap_moved and Time.get_ticks_msec()-tap_time < 350 and target_rect.has_point(tap_origin) and target_rect.has_point(event.position): target_tapped.emit()
		queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == move_index:
			var offset: Vector2 = (event.position - origin).limit_length(JOYSTICK_TRAVEL)
			knob = origin + offset
			move_changed.emit(offset / JOYSTICK_TRAVEL)
			queue_redraw()
		elif event.index == look_index:
			if event.position.distance_to(tap_origin) > 18: tap_moved = true
			look_changed.emit(event.relative * 0.004)

func reset() -> void:
	move_index = -1
	look_index = -1
	move_changed.emit(Vector2.ZERO)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset()

func _draw() -> void:
	var center := origin if move_index >= 0 else Vector2(135, size.y - 135)
	draw_circle(center, JOYSTICK_RADIUS, Color(0.9, 0.85, 0.7, 0.12))
	draw_arc(center, JOYSTICK_RADIUS, 0, TAU, 64, Color(0.9, 0.85, 0.7, 0.4), 3.0, true)
	draw_circle(knob if move_index >= 0 else center, KNOB_RADIUS, Color(0.9, 0.85, 0.7, 0.35))
