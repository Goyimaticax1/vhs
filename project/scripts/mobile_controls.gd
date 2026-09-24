extends Control

@export var joystick_radius_ratio: float = 0.115
@export var sprint_button_width: float = 150.0
@export var sprint_button_height: float = 88.0
@export var crouch_button_width: float = 120.0
@export var crouch_button_height: float = 76.0

var move_vector: Vector2 = Vector2.ZERO
var look_delta: Vector2 = Vector2.ZERO
var sprint_pressed: bool = false
var sprint_touch_id: int = -1
var crouch_pressed: bool = false
var crouch_touch_id: int = -1

var left_touch_id: int = -1
var right_touch_id: int = -1
var left_origin: Vector2 = Vector2.ZERO
var left_knob: Vector2 = Vector2.ZERO
var sprint_rect: Rect2 = Rect2()
var crouch_rect: Rect2 = Rect2()

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_process_input(true)
    _update_layout()

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _update_layout()

func _update_layout() -> void:
    sprint_rect = Rect2(
        size.x - sprint_button_width - 48.0,
        size.y - sprint_button_height - 48.0,
        sprint_button_width,
        sprint_button_height
    )
    crouch_rect = Rect2(
        size.x - crouch_button_width - 48.0,
        sprint_rect.position.y - crouch_button_height - 22.0,
        crouch_button_width,
        crouch_button_height
    )
    queue_redraw()

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        var touch: InputEventScreenTouch = event
        if touch.pressed:
            if sprint_rect.has_point(touch.position) and sprint_touch_id == -1:
                sprint_pressed = true
                sprint_touch_id = touch.index
                queue_redraw()
            elif crouch_rect.has_point(touch.position) and crouch_touch_id == -1:
                crouch_pressed = not crouch_pressed
                crouch_touch_id = touch.index
                queue_redraw()
            elif touch.position.x < size.x * 0.48 and left_touch_id == -1:
                left_touch_id = touch.index
                left_origin = touch.position
                left_knob = touch.position
                queue_redraw()
            elif touch.position.x >= size.x * 0.48 and right_touch_id == -1:
                right_touch_id = touch.index
        else:
            if touch.index == left_touch_id:
                left_touch_id = -1
                move_vector = Vector2.ZERO
                left_knob = left_origin
                queue_redraw()
            if touch.index == right_touch_id:
                right_touch_id = -1
            if touch.index == sprint_touch_id:
                sprint_pressed = false
                sprint_touch_id = -1
                queue_redraw()
            if touch.index == crouch_touch_id:
                crouch_touch_id = -1

    elif event is InputEventScreenDrag:
        var drag: InputEventScreenDrag = event
        if drag.index == left_touch_id:
            var radius: float = minf(size.x, size.y) * joystick_radius_ratio
            var offset: Vector2 = drag.position - left_origin
            if offset.length() > radius:
                offset = offset.normalized() * radius
            left_knob = left_origin + offset
            move_vector = offset / radius
            queue_redraw()
        elif drag.index == right_touch_id:
            look_delta += drag.screen_relative

func _draw() -> void:
    var radius: float = minf(size.x, size.y) * joystick_radius_ratio
    var idle_position: Vector2 = Vector2(size.x * 0.16, size.y * 0.80)
    var base_position: Vector2 = left_origin if left_touch_id != -1 else idle_position
    var knob_position: Vector2 = left_knob if left_touch_id != -1 else idle_position

    draw_circle(base_position, radius, Color(0.80, 0.82, 0.84, 0.055))
    draw_circle(base_position, radius, Color(1.0, 1.0, 1.0, 0.12), false, 2.0)
    draw_circle(knob_position, radius * 0.48, Color(0.92, 0.92, 0.90, 0.11))
    draw_circle(knob_position, radius * 0.48, Color(1.0, 1.0, 1.0, 0.17), false, 2.0)

    var button_fill: Color = Color(0.82, 0.83, 0.82, 0.12 if sprint_pressed else 0.055)
    draw_rect(sprint_rect, button_fill, true)
    draw_rect(sprint_rect, Color(1.0, 1.0, 1.0, 0.15), false, 2.0)
    draw_string(ThemeDB.fallback_font, sprint_rect.position + Vector2(33.0, 55.0), "RUN", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(0.95, 0.95, 0.93, 0.70))

    var crouch_fill: Color = Color(0.82, 0.83, 0.82, 0.12 if crouch_pressed else 0.055)
    draw_rect(crouch_rect, crouch_fill, true)
    draw_rect(crouch_rect, Color(1.0, 1.0, 1.0, 0.15), false, 2.0)
    draw_string(ThemeDB.fallback_font, crouch_rect.position + Vector2(20.0, 48.0), "CROUCH", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(0.95, 0.95, 0.93, 0.70))
