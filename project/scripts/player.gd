class_name VhsPlayer
extends CharacterBody3D

@export_category("Movement")
@export var walk_speed: float = 2.70
@export var sprint_speed: float = 4.60
@export var crouch_speed: float = 1.55
@export var acceleration: float = 9.0
@export var deceleration: float = 12.0
@export var gravity: float = 15.0
@export var jump_velocity: float = 4.2

@export_category("Crouch")
@export var crouch_height_scale: float = 0.56
@export var crouch_blend_speed: float = 1.7

@export_category("Look")
@export var mouse_sensitivity: float = 0.0024
@export var touch_sensitivity: float = 0.0020
@export var pitch_limit_degrees: float = 84.0

@export_category("Scene references")
@export var camera_rig_path: NodePath = NodePath("../CamcorderRig")
@export var mobile_controls_path: NodePath = NodePath("../UI/MobileControls")

@onready var camera_rig: Node3D = get_node(camera_rig_path) as Node3D
@onready var mobile_controls: Control = get_node(mobile_controls_path) as Control
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var capsule_shape: CapsuleShape3D = collision_shape.shape as CapsuleShape3D

var yaw: float = 0.0
var pitch: float = -0.04
var mobile_look: Vector2 = Vector2.ZERO
var standing_height: float = 1.72
var standing_shape_y: float = -0.14
var crouch_blend: float = 0.0
var was_on_floor: bool = true
var vertical_velocity_before_step: float = 0.0

func _ready() -> void:
    rotation.y = yaw
    if not OS.has_feature("mobile"):
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    if capsule_shape != null:
        standing_height = capsule_shape.height
    standing_shape_y = collision_shape.position.y

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        var mouse_event: InputEventMouseMotion = event
        if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
            _apply_look(mouse_event.screen_relative, mouse_sensitivity)
    elif event is InputEventMouseButton:
        var mouse_button: InputEventMouseButton = event
        if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    elif event is InputEventKey:
        var key_event: InputEventKey = event
        if key_event.keycode == KEY_ESCAPE and key_event.pressed:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
    mobile_look = mobile_controls.look_delta
    mobile_controls.look_delta = Vector2.ZERO
    if mobile_look.length_squared() > 0.0:
        _apply_look(mobile_look, touch_sensitivity)

    var keyboard_move: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var input_vector: Vector2 = keyboard_move
    if mobile_controls.move_vector.length_squared() > keyboard_move.length_squared():
        input_vector = mobile_controls.move_vector

    var direction: Vector3 = Vector3.ZERO
    if input_vector.length_squared() > 0.001:
        direction = Vector3(input_vector.x, 0.0, input_vector.y).rotated(Vector3.UP, yaw).normalized()

    var crouch_held: bool = Input.is_key_pressed(KEY_C) or mobile_controls.crouch_pressed
    var crouch_target: float = 1.0 if crouch_held else 0.0
    crouch_blend = lerp(crouch_blend, crouch_target, 1.0 - exp(-crouch_blend_speed * delta))

    var sprinting: bool = (Input.is_action_pressed("sprint") or mobile_controls.sprint_pressed) and not crouch_held
    var upright_speed: float = lerp(walk_speed, sprint_speed, 1.0 if sprinting else 0.0)
    var target_speed: float = lerp(upright_speed, crouch_speed, crouch_blend)

    var target_velocity: Vector3 = direction * target_speed
    var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
    var response: float = acceleration if direction.length_squared() > 0.0 else deceleration
    horizontal_velocity = horizontal_velocity.lerp(target_velocity, 1.0 - exp(-response * delta))
    velocity.x = horizontal_velocity.x
    velocity.z = horizontal_velocity.z

    vertical_velocity_before_step = velocity.y

    if is_on_floor():
        if not was_on_floor:
            var fall_speed: float = -vertical_velocity_before_step
            camera_rig.call("land_dip", clampf(fall_speed * 0.010, 0.0, 0.06))
            if fall_speed > 4.0:
                camera_rig.call("snap_shake", clampf(fall_speed / 9.0, 0.2, 1.6))
        if Input.is_action_just_pressed("jump") and not crouch_held:
            velocity.y = jump_velocity
        else:
            velocity.y = -0.15
    else:
        velocity.y -= gravity * delta

    move_and_slide()
    was_on_floor = is_on_floor()
    rotation.y = yaw
    camera_rig.set("sprinting", sprinting)
    camera_rig.set("is_crouching", crouch_held)

    if capsule_shape != null:
        var crouched_height: float = standing_height * crouch_height_scale
        capsule_shape.height = lerp(standing_height, crouched_height, crouch_blend)
        collision_shape.position.y = standing_shape_y - (standing_height - capsule_shape.height) * 0.5
    camera_rig.call("set_crouch_offset", -crouch_blend * standing_height * (1.0 - crouch_height_scale))

func _apply_look(raw_delta: Vector2, sensitivity: float) -> void:
    var look_change: Vector2 = raw_delta * sensitivity
    yaw -= look_change.x
    pitch -= look_change.y
    pitch = clampf(pitch, deg_to_rad(-pitch_limit_degrees), deg_to_rad(pitch_limit_degrees))
    camera_rig.call("feed_look_velocity", raw_delta)
