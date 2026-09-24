extends CanvasLayer

@onready var vhs_rect: ColorRect = $VHS
@onready var rec_label: Label = $HUD/REC
@onready var status_label: Label = $HUD/Status

@export var dirt_intensity: float = 0.35
@export var autofocus_min_interval: float = 6.0
@export var autofocus_max_interval: float = 16.0
@export var autofocus_hunt_duration: float = 0.9

var elapsed: float = 0.0
var vhs_enabled: bool = true
var material: ShaderMaterial
var autofocus_timer: float = 0.0
var autofocus_active: float = 0.0

func _ready() -> void:
    vhs_rect.visible = true
    status_label.text = "HANDHELD // VHS ON"
    material = vhs_rect.material as ShaderMaterial
    if material != null:
        material.set_shader_parameter("dirt_intensity", dirt_intensity)
    autofocus_timer = randf_range(autofocus_min_interval, autofocus_max_interval)

func _process(delta: float) -> void:
    elapsed += delta
    var total: int = int(elapsed)
    rec_label.text = "● REC  %02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
    if Input.is_action_just_pressed("toggle_vhs"):
        vhs_enabled = not vhs_enabled
        vhs_rect.visible = vhs_enabled
        status_label.text = "HANDHELD // VHS ON" if vhs_enabled else "HANDHELD // CLEAN CAMERA"

    autofocus_timer -= delta
    if autofocus_timer <= 0.0:
        autofocus_active = autofocus_hunt_duration
        autofocus_timer = randf_range(autofocus_min_interval, autofocus_max_interval)

    var pulse: float = 0.0
    if autofocus_active > 0.0:
        autofocus_active -= delta
        var t: float = 1.0 - clampf(autofocus_active / autofocus_hunt_duration, 0.0, 1.0)
        pulse = sin(clampf(t, 0.0, 1.0) * PI)

    if material != null:
        material.set_shader_parameter("blur_pulse", pulse)

func trigger_autofocus_hunt() -> void:
    autofocus_active = autofocus_hunt_duration

func set_dirt_intensity(value: float) -> void:
    dirt_intensity = value
    if material != null:
        material.set_shader_parameter("dirt_intensity", value)
