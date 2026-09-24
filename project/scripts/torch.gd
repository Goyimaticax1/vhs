extends Node3D

# Operator torch. The rig drives this node's global rotation directly from the
# raw look input -- no lag -- while the camera is spring-filtered behind it, so
# the beam leads the frame on every turn and the view catches up. That lead is
# the whole read: it looks like a hand pointing a light, not a light welded to
# a camera.

@export var light_path: NodePath = NodePath("SpotLight3D")
@export var enabled: bool = true
@export var base_energy: float = 4.2
@export var warmup_speed: float = 6.0

@export_category("Bulb behaviour")
## Cheap filament flicker. Old torch, weak contacts.
@export_range(0.0, 1.0, 0.01) var flicker_amount: float = 0.13
@export var flicker_speed: float = 7.5
## Chance per second of a brief brownout dip.
@export var brownout_chance: float = 0.05

@export_category("Hand sway")
## Independent wrist wobble on top of the aim, in degrees.
@export var sway_deg: float = 0.55
@export var sway_speed: float = 1.4

@onready var light: SpotLight3D = get_node_or_null(light_path) as SpotLight3D

var energy_blend: float = 0.0
var brownout: float = 0.0
var time: float = 0.0
var flicker_noise: FastNoiseLite = FastNoiseLite.new()
var sway_noise: FastNoiseLite = FastNoiseLite.new()

func _ready() -> void:
    flicker_noise.seed = 60611
    flicker_noise.frequency = 1.0
    flicker_noise.fractal_octaves = 3
    sway_noise.seed = 12289
    sway_noise.frequency = 1.0
    sway_noise.fractal_octaves = 2
    energy_blend = 1.0 if enabled else 0.0

func set_enabled(value: bool) -> void:
    enabled = value

func toggle() -> void:
    enabled = not enabled

func is_enabled() -> bool:
    return enabled

func _process(delta: float) -> void:
    time += delta
    energy_blend = lerp(energy_blend, 1.0 if enabled else 0.0, 1.0 - exp(-warmup_speed * delta))

    if enabled and randf() < brownout_chance * delta * 60.0 * 0.016:
        brownout = randf_range(0.25, 0.6)
    brownout = maxf(brownout - delta * 2.4, 0.0)

    if light != null:
        var flicker: float = flicker_noise.get_noise_1d(time * flicker_speed) * flicker_amount
        var e: float = base_energy * energy_blend * (1.0 + flicker) * (1.0 - brownout)
        light.light_energy = maxf(e, 0.0)
        light.visible = energy_blend > 0.01

        # Wrist wobble, local to the aim the rig already set.
        light.rotation = Vector3(
            deg_to_rad(sway_noise.get_noise_1d(time * sway_speed) * sway_deg),
            deg_to_rad(sway_noise.get_noise_1d(time * sway_speed + 41.0) * sway_deg),
            deg_to_rad(sway_noise.get_noise_1d(time * sway_speed * 0.7 + 87.0) * sway_deg * 0.6)
        )
