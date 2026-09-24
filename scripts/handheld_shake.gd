extends Node3D
class_name HandheldShake

## Realistic handheld camera shake (Camera Shakify-style), for Godot 4.x
##
## HOW TO USE
##   Put this node BETWEEN your rig and your Camera3D:
##     CameraRig
##      \u2514\u2500 HandheldShake  (Node3D, this script)
##          \u2514\u2500 Camera3D
##   Nothing else to change. It offsets only itself, so your look/aim code
##   on the rig keeps working untouched.
##
## WHY IT LOOKS LIKE REAL HANDHELD (and not a bob)
##   A "bob" is a sine wave: same amplitude, same period, perfectly periodic,
##   and the eye reads it as machinery. Real handheld motion is broadband,
##   aperiodic drift: a human arm constantly over- and under-corrects.
##   Blender's Camera Shakify solves this by replaying motion-captured handheld
##   takes (real recorded loc/rot curves) with influence / scale / speed knobs.
##   This script reproduces that *character* procedurally with fractal (fBm)
##   noise: several octaves of Perlin noise summed with decreasing amplitude,
##   so you get a slow wander + medium sway + fine micro-tremor, never repeating,
##   with no periodic beat. Rotation dominates (that is what a wrist does),
##   translation is tiny, roll is the smallest of all.

enum Preset {
	## Locked-off-ish operator, barely holding still. Dialogue / inspection.
	IDLE_BREATH,
	## Slow investigative move, the classic "Shakify INVESTIGATION" feel.
	INVESTIGATION,
	## Loose shoulder-held take with visible wander.
	HANDHELD_LOOSE,
	## Walking with the camera down at hip/chest.
	WALK,
	## Consumer camcorder: heavier body, sloppier wrist, more drift. VHS look.
	CAMCORDER_VHS,
}

@export var preset: Preset = Preset.CAMCORDER_VHS:
	set(v):
		preset = v
		_apply_preset()

## Master blend. 0 = perfectly still, 1 = full preset. Animate/tween this.
@export_range(0.0, 2.0, 0.01) var influence: float = 1.0
## Multiplies amplitude only (how big the shake is).
@export_range(0.0, 4.0, 0.01) var scale: float = 1.0
## Multiplies frequency only (how fast the operator jitters).
@export_range(0.05, 4.0, 0.01) var speed: float = 1.0
@export var random_seed: int = 0
@export var enabled: bool = true

## Seconds to fade shake in on start, so it never pops at frame 0.
@export_range(0.0, 3.0, 0.05) var ease_in_time: float = 0.5

@export_group("Manual overrides")
## Metres. Leave at zero to use the preset.
@export var position_amplitude: Vector3 = Vector3.ZERO
## Degrees, as (pitch, yaw, roll). Leave at zero to use the preset.
@export var rotation_amplitude: Vector3 = Vector3.ZERO
@export var base_frequency: float = 0.0

# --- internals -------------------------------------------------------------

const _PRESETS := {
	Preset.IDLE_BREATH: {
		"pos": Vector3(0.004, 0.005, 0.003),
		"rot": Vector3(0.22, 0.28, 0.08),
		"freq": 0.55, "octaves": 3, "gain": 0.42, "lacunarity": 2.3,
	},
	Preset.INVESTIGATION: {
		"pos": Vector3(0.010, 0.012, 0.008),
		"rot": Vector3(0.55, 0.75, 0.18),
		"freq": 0.85, "octaves": 4, "gain": 0.45, "lacunarity": 2.2,
	},
	Preset.HANDHELD_LOOSE: {
		"pos": Vector3(0.018, 0.022, 0.014),
		"rot": Vector3(0.95, 1.25, 0.32),
		"freq": 1.1, "octaves": 4, "gain": 0.5, "lacunarity": 2.1,
	},
	Preset.WALK: {
		"pos": Vector3(0.028, 0.034, 0.020),
		"rot": Vector3(1.30, 1.70, 0.55),
		"freq": 1.45, "octaves": 5, "gain": 0.52, "lacunarity": 2.0,
	},
	Preset.CAMCORDER_VHS: {
		"pos": Vector3(0.022, 0.026, 0.016),
		"rot": Vector3(1.10, 1.55, 0.45),
		"freq": 0.95, "octaves": 5, "gain": 0.55, "lacunarity": 2.05,
	},
}

# One noise object per channel so axes are fully decorrelated. If they shared
# a noise field the motion would look like it is sliding along a diagonal.
var _noise: Array[FastNoiseLite] = []
var _cfg: Dictionary = {}
var _t: float = 0.0
var _fade: float = 0.0
var _rest_position: Vector3
var _rest_rotation: Vector3
var _impulse: Vector3 = Vector3.ZERO      # extra rotational kick, degrees
var _impulse_decay: float = 7.0

func _ready() -> void:
	_rest_position = position
	_rest_rotation = rotation
	_build_noise()
	_apply_preset()
	if ease_in_time <= 0.0:
		_fade = 1.0

func _build_noise() -> void:
	_noise.clear()
	for i in 6:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.seed = random_seed + i * 7919
		n.frequency = 1.0        # we drive frequency via the sample position
		_noise.append(n)

func _apply_preset() -> void:
	_cfg = _PRESETS[preset].duplicate()
	for n in _noise:
		n.fractal_octaves = _cfg["octaves"]
		n.fractal_gain = _cfg["gain"]
		n.fractal_lacunarity = _cfg["lacunarity"]

func _process(delta: float) -> void:
	if not enabled or _cfg.is_empty():
		return

	if ease_in_time > 0.0:
		_fade = min(1.0, _fade + delta / ease_in_time)
	else:
		_fade = 1.0

	var freq: float = base_frequency if base_frequency > 0.0 else float(_cfg["freq"])
	_t += delta * freq * speed

	var amp_pos: Vector3 = position_amplitude if position_amplitude != Vector3.ZERO else _cfg["pos"]
	var amp_rot: Vector3 = rotation_amplitude if rotation_amplitude != Vector3.ZERO else _cfg["rot"]
	var k: float = influence * scale * _fade

	# Each channel is sampled on its own noise field along a 1D path.
	# fBm gives slow wander + sway + tremor in one curve: aperiodic, no bob.
	var offset_pos := Vector3(
		_sample(0, _t) * amp_pos.x,
		_sample(1, _t) * amp_pos.y,
		_sample(2, _t) * amp_pos.z
	) * k

	# Rotation runs a touch slower than translation: a wrist drifts before it
	# jitters, and that lag is most of the "human" read.
	var tr := _t * 0.85
	var offset_rot := Vector3(
		_sample(3, tr) * amp_rot.x + _impulse.x,
		_sample(4, tr) * amp_rot.y + _impulse.y,
		_sample(5, tr) * amp_rot.z * 0.9 + _impulse.z
	) * k

	_impulse = _impulse.lerp(Vector3.ZERO, clamp(delta * _impulse_decay, 0.0, 1.0))

	position = _rest_position + offset_pos
	rotation = _rest_rotation + Vector3(
		deg_to_rad(offset_rot.x),
		deg_to_rad(offset_rot.y),
		deg_to_rad(offset_rot.z)
	)

# fBm Perlin in [-1, 1], remapped so peaks are reached rarely rather than
# constantly -> the "mostly steady, occasionally corrects" handheld rhythm.
func _sample(channel: int, t: float) -> float:
	var v := _noise[channel].get_noise_2d(t, float(channel) * 137.0)
	return sign(v) * pow(abs(v), 1.35) * 1.6

## Optional one-off kick: landings, hits, doors, reload, camera being bumped.
## Degrees, as (pitch, yaw, roll).
func kick(degrees: Vector3, decay: float = 7.0) -> void:
	_impulse += degrees
	_impulse_decay = decay

## Re-read the rest pose if you move this node in code.
func rebase() -> void:
	_rest_position = position
	_rest_rotation = rotation
