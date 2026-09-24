extends Node3D

@export_category("Scene references")
@export var player_path: NodePath = NodePath("../Player")
@export var camera_path: NodePath = NodePath("SpringArm3D/CamcorderCamera")

@export_category("Operator arm follow (slow, filtered)")
@export var position_lag_speed: float = 5.0
@export var rotation_lag_speed: float = 10.0
@export var position_spring: float = 72.0
@export var position_damping: float = 11.5
@export var rotation_spring: float = 72.0
@export var rotation_damping: float = 11.0

@export_category("Shakify-style state blend")
@export var state_blend_speed: float = 5.5

@export_category("Handheld arm sway amount per state")
@export var idle_position_m: float = 0.0045
@export var walk_position_m: float = 0.0085
@export var sprint_position_m: float = 0.014
@export var crouch_position_m: float = 0.0035
@export var idle_rotation_deg: float = 0.10
@export var walk_rotation_deg: float = 0.20
@export var sprint_rotation_deg: float = 0.34
@export var crouch_rotation_deg: float = 0.09

@export_category("Operator behavior")
@export var head_height_m: float = 1.52
@export var regrip_min_seconds: float = 1.8
@export var regrip_max_seconds: float = 4.8

@export_category("Zoom")
@export var default_fov: float = 67.0
@export var fov_damping: float = 9.0

@export_category("Footstep bob per state (pitch amp deg, freq, vertical bounce m)")
@export var idle_bob := Vector3(0.05, 1.1, 0.0012)
@export var walk_bob := Vector3(0.95, 7.2, 0.017)
@export var sprint_bob := Vector3(1.55, 10.6, 0.027)
@export var crouch_bob := Vector3(0.50, 4.6, 0.009)
@export var bob_sway_ratio: float = 0.6
@export var move_start_threshold: float = 0.18

@export_category("Landing dip")
@export var land_spring: float = 150.0
@export var land_damping: float = 9.0

@export_category("Impact / recoil impulse (crisp, unfiltered)")
@export var impulse_spring: float = 140.0
@export var impulse_damping: float = 14.0

@onready var player: VhsPlayer = get_node(player_path) as VhsPlayer
@onready var camera: Camera3D = get_node(camera_path) as Camera3D

var sprinting: bool = false
var is_crouching: bool = false

var w_idle: float = 1.0
var w_walk: float = 0.0
var w_sprint: float = 0.0
var w_crouch: float = 0.0
var is_moving: bool = false
var current_horizontal_speed: float = 0.0

var current_position: Vector3 = Vector3.ZERO
var position_velocity: Vector3 = Vector3.ZERO
var actual_yaw: float = 0.0
var actual_pitch: float = 0.0
var actual_roll: float = 0.0
var yaw_velocity: float = 0.0
var pitch_velocity: float = 0.0
var roll_velocity: float = 0.0
var look_velocity: Vector2 = Vector2.ZERO
var last_player_velocity: Vector3 = Vector3.ZERO
var elapsed: float = 0.0
var regrip_timer: float = 2.4
var regrip_offset: Vector3 = Vector3.ZERO
var crouch_offset: float = 0.0
var prev_crouch_offset: float = 0.0

var current_fov: float = 67.0
var target_fov: float = 67.0
var fov_velocity: float = 0.0
var fov_spring_effective: float = 40.0

var bob_phase: float = 0.0
var bob_amp: float = 0.0
var bob_freq: float = 0.0
var bob_bounce: float = 0.0
var bob_intensity: float = 0.0
var crouch_tilt_pitch: float = 0.0
var crouch_tilt_roll: float = 0.0

var land_disp: float = 0.0
var land_vel: float = 0.0

var impulse_pos: Vector3 = Vector3.ZERO
var impulse_pos_vel: Vector3 = Vector3.ZERO
var impulse_rot: Vector3 = Vector3.ZERO
var impulse_rot_vel: Vector3 = Vector3.ZERO

var noise_low: FastNoiseLite = FastNoiseLite.new()
var noise_mid: FastNoiseLite = FastNoiseLite.new()
var hand_noise: FastNoiseLite = FastNoiseLite.new()

var last_stride_index: int = -1
var stride_variance_amp: float = 1.0
var stride_variance_freq: float = 1.0
var stride_variance_bounce: float = 1.0
var stride_variance_amp_target: float = 1.0
var stride_variance_freq_target: float = 1.0
var stride_variance_bounce_target: float = 1.0

func _ready() -> void:
    current_position = global_position
    actual_yaw = player.rotation.y
    actual_pitch = player.pitch
    noise_low.seed = 9137
    noise_mid.seed = 21891
    noise_low.frequency = 0.18
    noise_mid.frequency = 0.55
    noise_low.fractal_octaves = 2
    noise_mid.fractal_octaves = 2
    hand_noise.seed = 51173
    hand_noise.frequency = 1.35
    hand_noise.fractal_octaves = 2
    regrip_timer = randf_range(regrip_min_seconds, regrip_max_seconds)
    if camera != null:
        current_fov = camera.fov
        target_fov = camera.fov
    else:
        current_fov = default_fov
        target_fov = default_fov

func feed_look_velocity(value: Vector2) -> void:
    look_velocity = look_velocity.lerp(value, 0.35)

func zoom_to(fov: float, duration: float = 0.6) -> void:
    target_fov = fov
    fov_spring_effective = clampf(7.0 / maxf(duration, 0.05), 6.0, 260.0)

func zoom_reset(duration: float = 0.6) -> void:
    zoom_to(default_fov, duration)

func recoil(strength: float = 1.0) -> void:
    impulse_rot_vel += Vector3(
        deg_to_rad(strength * 5.5),
        deg_to_rad(randf_range(-1.0, 1.0) * strength * 2.5),
        deg_to_rad(randf_range(-1.0, 1.0) * strength * 2.0)
    )
    impulse_pos_vel += Vector3(0.0, -strength * 0.05, strength * 0.03)

func snap_shake(strength: float = 1.0) -> void:
    impulse_rot_vel += Vector3(
        randf_range(-1.0, 1.0),
        randf_range(-1.0, 1.0),
        randf_range(-1.0, 1.0)
    ) * deg_to_rad(strength * 6.0)
    impulse_pos_vel += Vector3(
        randf_range(-1.0, 1.0),
        -absf(randf_range(0.4, 1.0)),
        randf_range(-1.0, 1.0)
    ) * strength * 0.045

func land_dip(impulse: float) -> void:
    land_vel -= impulse

func set_crouch_offset(value: float) -> void:
    crouch_offset = value

func _process(delta: float) -> void:
    elapsed += delta
    _update_state_weights(delta)
    _update_arm_sway(delta)
    _update_bob(delta)
    _update_land_spring(delta)
    _update_impulse(delta)
    _update_zoom(delta)
    _compose_camera_transform()

func _update_state_weights(delta: float) -> void:
    current_horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
    is_moving = current_horizontal_speed > move_start_threshold and player.is_on_floor()

    var target_idle: float = 0.0
    var target_walk: float = 0.0
    var target_sprint: float = 0.0
    var target_crouch: float = 0.0
    if is_crouching:
        target_crouch = 1.0
    elif not is_moving:
        target_idle = 1.0
    elif sprinting:
        target_sprint = 1.0
    else:
        target_walk = 1.0

    var response: float = 1.0 - exp(-state_blend_speed * delta)
    w_idle = lerp(w_idle, target_idle, response)
    w_walk = lerp(w_walk, target_walk, response)
    w_sprint = lerp(w_sprint, target_sprint, response)
    w_crouch = lerp(w_crouch, target_crouch, response)

    var total: float = w_idle + w_walk + w_sprint + w_crouch
    if total > 0.0001:
        w_idle /= total
        w_walk /= total
        w_sprint /= total
        w_crouch /= total

func _update_arm_sway(delta: float) -> void:
    var player_velocity: Vector3 = player.velocity

    var low: Vector3 = Vector3(
        noise_low.get_noise_1d(elapsed * 0.86),
        noise_low.get_noise_1d(elapsed * 0.73 + 47.0),
        noise_low.get_noise_1d(elapsed * 0.63 + 93.0)
    )
    var mid: Vector3 = Vector3(
        noise_mid.get_noise_1d(elapsed * 1.03 + 11.0),
        noise_mid.get_noise_1d(elapsed * 0.91 + 73.0),
        noise_mid.get_noise_1d(elapsed * 0.79 + 191.0)
    )

    var position_amplitude: float = idle_position_m * w_idle + walk_position_m * w_walk + sprint_position_m * w_sprint + crouch_position_m * w_crouch
    var rotation_amplitude: float = idle_rotation_deg * w_idle + walk_rotation_deg * w_walk + sprint_rotation_deg * w_sprint + crouch_rotation_deg * w_crouch

    var acceleration_vector: Vector3 = (player_velocity - last_player_velocity) / maxf(delta, 0.0001)
    last_player_velocity = player_velocity
    var yaw_basis: Basis = Basis(Vector3.UP, player.rotation.y)
    var acceleration_local: Vector3 = yaw_basis.inverse() * acceleration_vector
    var acceleration_sway: Vector3 = Vector3(
        -acceleration_local.x * 0.0022,
        acceleration_local.y * 0.0010,
        acceleration_local.z * 0.0014
    )

    var turn_normalized: Vector2 = Vector2(
        clampf(look_velocity.x / 900.0, -1.0, 1.0),
        clampf(look_velocity.y / 900.0, -1.0, 1.0)
    )
    var turn_position: Vector3 = Vector3(-turn_normalized.x * 0.010, turn_normalized.y * 0.006, 0.0)
    var turn_rotation: Vector3 = Vector3(
        -turn_normalized.y * 0.035,
        -turn_normalized.x * 0.055,
        -turn_normalized.x * 0.045
    )
    look_velocity = look_velocity.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))

    regrip_timer -= delta
    if regrip_timer <= 0.0:
        regrip_offset = Vector3(
            randf_range(-1.0, 1.0),
            randf_range(-0.75, 0.75),
            randf_range(-0.55, 0.55)
        )
        regrip_timer = randf_range(regrip_min_seconds, regrip_max_seconds)
    regrip_offset = regrip_offset.lerp(Vector3.ZERO, 1.0 - exp(-7.5 * delta))

    var local_position_offset: Vector3 = low * position_amplitude
    local_position_offset += mid * (position_amplitude * 0.45)
    local_position_offset += Vector3(0.0, sin(elapsed * 1.47) * 0.0022, 0.0)
    local_position_offset += acceleration_sway + turn_position + regrip_offset * 0.0015

    var desired_position: Vector3 = player.global_position + Vector3.UP * head_height_m
    desired_position += yaw_basis * local_position_offset

    var rotational_noise: Vector3 = low * 0.45 + mid * 0.20
    var desired_pitch: float = player.pitch + deg_to_rad(rotational_noise.x * rotation_amplitude * 0.75) + turn_rotation.x * 0.20
    var desired_yaw: float = player.rotation.y + deg_to_rad(rotational_noise.y * rotation_amplitude) + turn_rotation.y * 0.20
    var desired_roll: float = deg_to_rad(rotational_noise.z * rotation_amplitude * 0.90) + turn_rotation.z
    desired_roll += deg_to_rad(sin(elapsed * 1.47) * 0.014)
    desired_roll += deg_to_rad(regrip_offset.z * rotation_amplitude * 0.60)

    var position_error: Vector3 = desired_position - current_position
    position_velocity += position_error * position_spring * delta
    position_velocity *= exp(-position_damping * delta)
    current_position += position_velocity * delta
    current_position = current_position.lerp(desired_position, 1.0 - exp(-position_lag_speed * delta * 0.18))
    global_position = current_position

    actual_yaw = _spring_angle(actual_yaw, desired_yaw, delta, 0)
    actual_pitch = _spring_angle(actual_pitch, desired_pitch, delta, 1)
    actual_roll = _spring_angle(actual_roll, desired_roll, delta, 2)
    actual_yaw = lerp_angle(actual_yaw, player.rotation.y, 1.0 - exp(-rotation_lag_speed * delta * 0.45))
    rotation = Vector3(actual_pitch, actual_yaw, actual_roll)

func sprint_speed_reference() -> float:
    return maxf(player.sprint_speed, 0.01)

func _spring_angle(current: float, target: float, delta: float, channel: int) -> float:
    var error: float = wrapf(target - current + PI, 0.0, TAU) - PI
    var velocity: float = yaw_velocity if channel == 0 else (pitch_velocity if channel == 1 else roll_velocity)
    velocity += error * rotation_spring * delta
    velocity *= exp(-rotation_damping * delta)
    if channel == 0:
        yaw_velocity = velocity
    elif channel == 1:
        pitch_velocity = velocity
    else:
        roll_velocity = velocity
    return current + velocity * delta

func _update_bob(delta: float) -> void:
    bob_amp = idle_bob.x * w_idle + walk_bob.x * w_walk + sprint_bob.x * w_sprint + crouch_bob.x * w_crouch
    bob_freq = idle_bob.y * w_idle + walk_bob.y * w_walk + sprint_bob.y * w_sprint + crouch_bob.y * w_crouch
    bob_bounce = idle_bob.z * w_idle + walk_bob.z * w_walk + sprint_bob.z * w_sprint + crouch_bob.z * w_crouch

    var speed_ref: float = maxf(player.walk_speed, 0.01) * (w_idle + w_walk) + sprint_speed_reference() * w_sprint + maxf(player.crouch_speed, 0.01) * w_crouch
    var response: float = 1.0 - exp(-state_blend_speed * delta)
    var intensity_target: float = clampf(current_horizontal_speed / maxf(speed_ref, 0.01), 0.0, 1.3) if is_moving else 1.0
    bob_intensity = lerp(bob_intensity, intensity_target, response)

    bob_phase += bob_freq * delta

    var stride_index: int = int(floor(bob_phase / TAU))
    if stride_index != last_stride_index:
        last_stride_index = stride_index
        stride_variance_amp_target = randf_range(0.90, 1.10)
        stride_variance_freq_target = randf_range(0.95, 1.05)
        stride_variance_bounce_target = randf_range(0.88, 1.12)
    var variance_response: float = 1.0 - exp(-3.0 * delta)
    stride_variance_amp = lerp(stride_variance_amp, stride_variance_amp_target, variance_response)
    stride_variance_freq = lerp(stride_variance_freq, stride_variance_freq_target, variance_response)
    stride_variance_bounce = lerp(stride_variance_bounce, stride_variance_bounce_target, variance_response)

    var crouch_transition_speed: float = (crouch_offset - prev_crouch_offset) / maxf(delta, 0.0001)
    prev_crouch_offset = crouch_offset
    var tilt_raw: float = clampf(crouch_transition_speed * 0.9, -1.0, 1.0)
    crouch_tilt_pitch = lerp(crouch_tilt_pitch, tilt_raw * -2.2, response)
    crouch_tilt_roll = lerp(crouch_tilt_roll, tilt_raw * 1.6, response)

func _update_land_spring(delta: float) -> void:
    var force: float = -land_spring * land_disp - land_damping * land_vel
    land_vel += force * delta
    land_disp += land_vel * delta
    land_disp = clampf(land_disp, -0.06, 0.025)

func _update_impulse(delta: float) -> void:
    var rot_force: Vector3 = -impulse_spring * impulse_rot - impulse_damping * impulse_rot_vel
    impulse_rot_vel += rot_force * delta
    impulse_rot += impulse_rot_vel * delta

    var pos_force: Vector3 = -impulse_spring * impulse_pos - impulse_damping * impulse_pos_vel
    impulse_pos_vel += pos_force * delta
    impulse_pos += impulse_pos_vel * delta

func _update_zoom(delta: float) -> void:
    if camera == null:
        return
    var fov_error: float = target_fov - current_fov
    fov_velocity += fov_error * fov_spring_effective * delta
    fov_velocity *= exp(-fov_damping * delta)
    current_fov += fov_velocity * delta
    camera.fov = current_fov

func _compose_camera_transform() -> void:
    if camera == null:
        return
    var amp: float = bob_amp * stride_variance_amp
    var bounce: float = bob_bounce * stride_variance_bounce
    var phase: float = bob_phase * stride_variance_freq
    var pitch_bob: float = sin(phase) * amp * bob_intensity
    var yaw_bob: float = sin(phase * 0.5 + 0.6) * amp * bob_sway_ratio * 0.6 * bob_intensity
    var roll_bob: float = sin(phase * 0.5) * amp * bob_sway_ratio * bob_intensity
    var vertical_bounce: float = pow(sin(phase), 2.0) * bounce * bob_intensity
    var lateral_bounce: float = sin(phase * 0.5) * bounce * 0.5 * bob_intensity

    var tremor_pitch: float = hand_noise.get_noise_1d(elapsed * 2.1) * 0.055
    var tremor_yaw: float = hand_noise.get_noise_1d(elapsed * 1.8 + 41.0) * 0.045
    var tremor_roll: float = hand_noise.get_noise_1d(elapsed * 1.6 + 83.0) * 0.040
    var tremor_pos_x: float = hand_noise.get_noise_1d(elapsed * 2.3 + 19.0) * 0.00045
    var tremor_pos_y: float = hand_noise.get_noise_1d(elapsed * 2.0 + 57.0) * 0.00035

    camera.position = Vector3(lateral_bounce + tremor_pos_x, vertical_bounce + land_disp + crouch_offset + tremor_pos_y, 0.0) + impulse_pos
    camera.rotation = Vector3(
        deg_to_rad(pitch_bob + crouch_tilt_pitch + tremor_pitch) + impulse_rot.x,
        deg_to_rad(yaw_bob + tremor_yaw) + impulse_rot.y,
        deg_to_rad(roll_bob + crouch_tilt_roll + tremor_roll) + impulse_rot.z
    )
