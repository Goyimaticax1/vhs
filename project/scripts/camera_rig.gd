extends Node3D

# Handheld camcorder operator rig.
#
# Shake comes from CameraShakify (scripts/camera_shakify.gd): real recorded
# handheld takes replayed as curves, blended by locomotion state, exactly like
# the Blender addon. No sine bob, no hand-rolled noise on the shake path.
#
# Layout mirrors the UE5 spring-arm setup: the rig is the arm (position lag 5,
# rotation lag 10, no collision test, length 0), the camera hangs off it and
# does NOT use pawn control rotation of its own -- it only carries shake and
# impulses.
#
# The torch is aimed from the RAW look input with a small predictive lead, so
# the beam moves first and the camera settles into it.
#
# Vertical offsets (crouch, landing dip) are applied in WORLD space on the rig,
# never on the camera's local Y, or they tilt with the view.

const SHAKE_TAKES := ["INVESTIGATION", "WALK_TO_STORE", "RUN_AND_GUN", "CROUCH_CREEP"]

@export_category("Scene references")
@export var player_path: NodePath = NodePath("../Player")
@export var camera_path: NodePath = NodePath("SpringArm3D/CamcorderCamera")
@export var torch_path: NodePath = NodePath("TorchPivot")

@export_category("Operator arm follow (spring arm lag)")
@export var position_lag_speed: float = 5.0
@export var rotation_lag_speed: float = 10.0
@export var position_spring: float = 72.0
@export var position_damping: float = 11.5
@export var rotation_spring: float = 64.0
@export var rotation_damping: float = 11.0

@export_category("State blend")
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
## 4:3 VHS look wants a tighter lens than a modern FPS. 65-70 per the guide.
@export var default_fov: float = 66.0
@export var fov_damping: float = 9.0

@export_category("Camera Shakify")
## Master blend. 0 = locked off, 1 = the take as recorded, >1 = exaggerated.
@export_range(0.0, 3.0, 0.01) var shake_influence: float = 1.0
## Amplitude only.
@export_range(0.0, 4.0, 0.01) var shake_scale: float = 1.35
## Playback rate of the take. 1.0 = as recorded.
@export_range(0.05, 4.0, 0.01) var shake_speed: float = 1.0
@export var shake_pitch_ratio: float = 0.85
@export var shake_roll_ratio: float = 0.60
## Floor on the shake while standing still, so the operator never goes rigid.
@export_range(0.0, 1.0, 0.01) var shake_idle_floor: float = 0.55
@export var move_start_threshold: float = 0.18

@export_category("Footstep impacts (distance based, aperiodic)")
@export var step_length_m: float = 0.80
@export_range(0.0, 0.5, 0.01) var step_length_jitter: float = 0.16
@export var step_kick_deg: float = 0.78
@export var step_drop_m: float = 0.0095
@export var step_lateral_ratio: float = 0.65

@export_category("Breathing / exertion")
@export var breath_position_m: float = 0.0030
@export var breath_roll_deg: float = 0.022
@export var exertion_gain_per_second: float = 0.34
@export var exertion_recovery_per_second: float = 0.20

@export_category("Crouch")
@export var crouch_follow_speed: float = 14.0
@export var crouch_tilt_pitch_deg: float = 1.8
@export var crouch_tilt_roll_deg: float = 1.1

@export_category("Landing dip")
@export var land_spring: float = 150.0
@export var land_damping: float = 9.0

@export_category("Impact / recoil impulse (crisp, unfiltered)")
@export var impulse_spring: float = 140.0
@export var impulse_damping: float = 14.0

@export_category("Torch")
@export var torch_enabled_on_start: bool = true
## Seconds of look-ahead. The torch is aimed where the look input will be this
## far in the future, so it clearly leads the lagging camera.
@export_range(0.0, 0.25, 0.005) var torch_lead_seconds: float = 0.085
@export var torch_lead_max_deg: float = 22.0
@export var torch_rate_smoothing: float = 14.0

@onready var player: VhsPlayer = get_node(player_path) as VhsPlayer
@onready var camera: Camera3D = get_node(camera_path) as Camera3D
@onready var torch_pivot: Node3D = get_node_or_null(torch_path) as Node3D

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
var crouch_current: float = 0.0
var crouch_rate: float = 0.0

var current_fov: float = 66.0
var target_fov: float = 66.0
var fov_velocity: float = 0.0
var fov_spring_effective: float = 40.0

var move_intensity: float = 0.0
var exertion: float = 0.0
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
var breath_noise: FastNoiseLite = FastNoiseLite.new()
var energy_noise: FastNoiseLite = FastNoiseLite.new()

var shake_time: float = 0.0
var breath_time: float = 0.0
var shake_position: Vector3 = Vector3.ZERO
var shake_rotation_deg: Vector3 = Vector3.ZERO

var step_distance: float = 0.0
var next_step_distance: float = 0.8
var step_side: float = 1.0

var prev_look_yaw: float = 0.0
var prev_look_pitch: float = 0.0
var look_yaw_rate: float = 0.0
var look_pitch_rate: float = 0.0

func _ready() -> void:
    current_position = global_position
    actual_yaw = player.rotation.y
    actual_pitch = player.pitch
    prev_look_yaw = player.rotation.y
    prev_look_pitch = player.pitch
    noise_low.seed = 9137
    noise_mid.seed = 21891
    noise_low.frequency = 0.18
    noise_mid.frequency = 0.55
    noise_low.fractal_octaves = 2
    noise_mid.fractal_octaves = 2
    breath_noise.seed = 33427
    breath_noise.frequency = 1.0
    breath_noise.fractal_octaves = 2
    energy_noise.seed = 77003
    energy_noise.frequency = 1.0
    energy_noise.fractal_octaves = 2
    regrip_timer = randf_range(regrip_min_seconds, regrip_max_seconds)
    next_step_distance = step_length_m
    shake_time = randf() * 37.0
    if torch_pivot != null and torch_pivot.has_method("set_enabled"):
        torch_pivot.call("set_enabled", torch_enabled_on_start)
    if camera != null:
        camera.fov = default_fov
        current_fov = default_fov
        target_fov = default_fov
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

func toggle_torch() -> void:
    if torch_pivot != null and torch_pivot.has_method("toggle"):
        torch_pivot.call("toggle")

func set_torch(value: bool) -> void:
    if torch_pivot != null and torch_pivot.has_method("set_enabled"):
        torch_pivot.call("set_enabled", value)

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

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("toggle_torch"):
        toggle_torch()

func _process(delta: float) -> void:
    elapsed += delta
    _update_state_weights(delta)
    _update_exertion(delta)
    _update_crouch(delta)
    _update_land_spring(delta)
    _update_arm_sway(delta)
    _update_handheld_shake(delta)
    _update_footsteps(delta)
    _update_impulse(delta)
    _update_zoom(delta)
    _compose_camera_transform()
    _update_torch(delta)

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

func _update_exertion(delta: float) -> void:
    if sprinting and is_moving:
        exertion += exertion_gain_per_second * delta
    else:
        exertion -= exertion_recovery_per_second * delta
    exertion = clampf(exertion, 0.0, 1.0)

func _update_crouch(delta: float) -> void:
    var previous: float = crouch_current
    crouch_current = lerp(crouch_current, crouch_offset, 1.0 - exp(-crouch_follow_speed * delta))
    crouch_rate = (crouch_current - previous) / maxf(delta, 0.0001)

    var response: float = 1.0 - exp(-state_blend_speed * delta)
    var tilt_raw: float = clampf(crouch_rate * 1.4, -1.0, 1.0)
    crouch_tilt_pitch = lerp(crouch_tilt_pitch, tilt_raw * crouch_tilt_pitch_deg, response)
    crouch_tilt_roll = lerp(crouch_tilt_roll, tilt_raw * crouch_tilt_roll_deg, response)

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

    breath_time += delta * lerp(0.30, 0.78, exertion)
    var breath: float = breath_noise.get_noise_1d(breath_time) * (1.0 + exertion * 1.7)

    var local_position_offset: Vector3 = low * position_amplitude
    local_position_offset += mid * (position_amplitude * 0.45)
    local_position_offset += Vector3(0.0, breath * breath_position_m, 0.0)
    local_position_offset += acceleration_sway + turn_position + regrip_offset * 0.0015

    var desired_position: Vector3 = player.global_position + Vector3.UP * head_height_m
    desired_position += yaw_basis * local_position_offset

    var rotational_noise: Vector3 = low * 0.45 + mid * 0.20
    var desired_pitch: float = player.pitch + deg_to_rad(rotational_noise.x * rotation_amplitude * 0.75) + turn_rotation.x * 0.20
    var desired_yaw: float = player.rotation.y + deg_to_rad(rotational_noise.y * rotation_amplitude) + turn_rotation.y * 0.20
    var desired_roll: float = deg_to_rad(rotational_noise.z * rotation_amplitude * 0.90) + turn_rotation.z
    desired_roll += deg_to_rad(breath * breath_roll_deg)
    desired_roll += deg_to_rad(regrip_offset.z * rotation_amplitude * 0.60)

    var position_error: Vector3 = desired_position - current_position
    position_velocity += position_error * position_spring * delta
    position_velocity *= exp(-position_damping * delta)
    current_position += position_velocity * delta
    current_position = current_position.lerp(desired_position, 1.0 - exp(-position_lag_speed * delta * 0.18))

    global_position = current_position + Vector3.UP * (crouch_current + land_disp)

    actual_yaw = _spring_angle(actual_yaw, desired_yaw, delta, 0)
    actual_pitch = _spring_angle(actual_pitch, desired_pitch, delta, 1)
    actual_roll = _spring_angle(actual_roll, desired_roll, delta, 2)
    actual_yaw = lerp_angle(actual_yaw, player.rotation.y, 1.0 - exp(-rotation_lag_speed * delta * 0.32))
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

# Blend the four Shakify takes by locomotion weight and play them on a single
# advancing cursor, so a state change crossfades takes instead of restarting
# one.
func _update_handheld_shake(delta: float) -> void:
    var speed_ref: float = maxf(player.walk_speed, 0.01) * (w_idle + w_walk) + sprint_speed_reference() * w_sprint + maxf(player.crouch_speed, 0.01) * w_crouch
    var response: float = 1.0 - exp(-state_blend_speed * delta)
    var intensity_target: float = clampf(current_horizontal_speed / maxf(speed_ref, 0.01), 0.0, 1.25) if is_moving else 0.0
    move_intensity = lerp(move_intensity, intensity_target, response)

    shake_time += delta * shake_speed * lerp(0.9, 1.18, clampf(move_intensity, 0.0, 1.0))

    var weights: Array[float] = [w_idle, w_walk, w_sprint, w_crouch]
    var loc: Vector3 = Vector3.ZERO
    var rot_deg: Vector3 = Vector3.ZERO
    for i in 4:
        var w: float = weights[i]
        if w <= 0.001:
            continue
        var s: Dictionary = CameraShakify.sample(SHAKE_TAKES[i], shake_time)
        loc += (s["loc"] as Vector3) * w
        rot_deg += (s["rot_deg"] as Vector3) * w

    var energy: float = 1.0 + energy_noise.get_noise_1d(elapsed * 0.23) * 0.22
    var gate: float = lerp(shake_idle_floor, 1.0, clampf(move_intensity, 0.0, 1.0))
    var k: float = shake_influence * shake_scale * energy * gate * (1.0 + exertion * 0.35)

    shake_position = loc * k
    shake_rotation_deg = Vector3(
        rot_deg.x * shake_pitch_ratio,
        rot_deg.y,
        rot_deg.z * shake_roll_ratio
    ) * k

func _update_footsteps(delta: float) -> void:
    if not is_moving:
        step_distance = maxf(step_distance - delta * 0.5, 0.0)
        return

    step_distance += current_horizontal_speed * delta
    if step_distance < next_step_distance:
        return

    step_distance = 0.0
    var stride: float = step_length_m * lerp(1.0, 1.25, w_sprint) * lerp(1.0, 0.72, w_crouch)
    next_step_distance = stride * randf_range(1.0 - step_length_jitter, 1.0 + step_length_jitter)
    step_side = -step_side

    var strength: float = clampf(current_horizontal_speed / sprint_speed_reference(), 0.30, 1.15)
    strength *= lerp(1.0, 0.45, w_crouch)

    impulse_rot_vel += Vector3(
        deg_to_rad(step_kick_deg * strength * randf_range(0.75, 1.25)),
        deg_to_rad(step_side * step_kick_deg * 0.45 * strength * randf_range(0.6, 1.3)),
        deg_to_rad(-step_side * step_kick_deg * 0.70 * strength * randf_range(0.7, 1.2))
    )
    impulse_pos_vel += Vector3(
        step_side * step_drop_m * step_lateral_ratio,
        -step_drop_m,
        0.0
    ) * strength

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
    camera.position = shake_position + impulse_pos
    camera.rotation = Vector3(
        deg_to_rad(shake_rotation_deg.x + crouch_tilt_pitch) + impulse_rot.x,
        deg_to_rad(shake_rotation_deg.y) + impulse_rot.y,
        deg_to_rad(shake_rotation_deg.z + crouch_tilt_roll) + impulse_rot.z
    )

# The torch is aimed in WORLD space from the raw, unlagged look input plus a
# short predictive lead, so during a turn the beam is already on the new
# heading while the spring-filtered camera is still swinging onto it.
func _update_torch(delta: float) -> void:
    if torch_pivot == null:
        return

    var raw_yaw: float = player.rotation.y
    var raw_pitch: float = player.pitch

    var yaw_delta: float = wrapf(raw_yaw - prev_look_yaw + PI, 0.0, TAU) - PI
    var pitch_delta: float = raw_pitch - prev_look_pitch
    prev_look_yaw = raw_yaw
    prev_look_pitch = raw_pitch

    var smoothing: float = 1.0 - exp(-torch_rate_smoothing * delta)
    look_yaw_rate = lerp(look_yaw_rate, yaw_delta / maxf(delta, 0.0001), smoothing)
    look_pitch_rate = lerp(look_pitch_rate, pitch_delta / maxf(delta, 0.0001), smoothing)

    var lead_cap: float = deg_to_rad(torch_lead_max_deg)
    var yaw_lead: float = clampf(look_yaw_rate * torch_lead_seconds, -lead_cap, lead_cap)
    var pitch_lead: float = clampf(look_pitch_rate * torch_lead_seconds, -lead_cap, lead_cap)

    torch_pivot.global_rotation = Vector3(
        clampf(raw_pitch + pitch_lead, -1.45, 1.45),
        raw_yaw + yaw_lead,
        0.0
    )
