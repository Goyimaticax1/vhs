extends CanvasLayer

# Camcorder OSD. Everything here is faked with plain Labels so the project
# stays font-free: chroma ghosts + hard shadows sell the "burned into tape"
# look, and a dropout glitch occasionally corrupts the readouts.

@onready var vhs_rect: ColorRect = $VHS
@onready var hud: Control = $HUD
@onready var rec_label: Label = $HUD/REC
@onready var timecode_label: Label = $HUD/Timecode
@onready var battery_label: Label = $HUD/Battery
@onready var tape_label: Label = $HUD/TapeMode
@onready var tracking_label: Label = $HUD/Tracking
@onready var date_label: Label = $HUD/DateStamp
@onready var time_label: Label = $HUD/TimeStamp
@onready var focus_label: Label = $HUD/AutoFocus
@onready var status_label: Label = $HUD/Status

@export var dirt_intensity: float = 0.35
@export var autofocus_min_interval: float = 6.0
@export var autofocus_max_interval: float = 16.0
@export var autofocus_hunt_duration: float = 0.9

@export_group("Tape")
@export var tape_fps: int = 30
@export var tape_total_minutes: float = 120.0
@export var tape_start_used_minutes: float = 37.0
@export var battery_life_seconds: float = 1500.0
@export var battery_start_charge: float = 0.86

@export_group("Date stamp")
@export var stamp_year: int = 1998
@export var stamp_month: int = 6
@export var stamp_day: int = 14
@export var stamp_hour: int = 23
@export var stamp_minute: int = 42
@export var stamp_second: int = 8

@export_group("Glitches")
@export var glitch_min_interval: float = 4.5
@export var glitch_max_interval: float = 13.0
@export var glitch_min_duration: float = 0.12
@export var glitch_max_duration: float = 0.42
@export var glitch_hud_jitter_px: float = 5.0
@export var glitch_noise_boost: float = 0.16
@export var glitch_chromatic_boost: float = 0.004

const MONTHS: PackedStringArray = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
const MONTH_DAYS: PackedInt32Array = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

var elapsed: float = 0.0
var vhs_enabled: bool = true
var material: ShaderMaterial
var autofocus_timer: float = 0.0
var autofocus_active: float = 0.0

var ghosts: Dictionary = {}
var hud_base_position: Vector2 = Vector2.ZERO
var glitch_timer: float = 0.0
var glitch_active: float = 0.0
var glitch_duration: float = 0.0
var tracking_phase: float = 0.0
var base_noise_strength: float = 0.024
var base_chromatic: float = 0.0016

func _ready() -> void:
    vhs_rect.visible = true
    material = vhs_rect.material as ShaderMaterial
    if material != null:
        material.set_shader_parameter("dirt_intensity", dirt_intensity)
        var n: Variant = material.get_shader_parameter("noise_strength")
        if n != null:
            base_noise_strength = float(n)
        var c: Variant = material.get_shader_parameter("chromatic")
        if c != null:
            base_chromatic = float(c)

    hud_base_position = hud.position
    for l: Label in [rec_label, timecode_label, battery_label, tape_label, tracking_label, date_label, time_label, focus_label, status_label]:
        _build_ghosts(l)

    _set_label(status_label, "HANDHELD // VHS ON")
    focus_label.visible = false
    autofocus_timer = randf_range(autofocus_min_interval, autofocus_max_interval)
    glitch_timer = randf_range(glitch_min_interval, glitch_max_interval)

func _build_ghosts(l: Label) -> void:
    var red: Label = l.duplicate() as Label
    var blue: Label = l.duplicate() as Label
    var index: int = l.get_index()
    for g: Label in [red, blue]:
        g.name = l.name + "Ghost"
        g.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
        g.add_theme_constant_override("shadow_offset_x", 0)
        g.add_theme_constant_override("shadow_offset_y", 0)
        hud.add_child(g)
        hud.move_child(g, index)
    red.add_theme_color_override("font_color", Color(1.0, 0.18, 0.24, 0.30))
    blue.add_theme_color_override("font_color", Color(0.24, 0.52, 1.0, 0.26))
    red.position += Vector2(-1.5, -0.5)
    blue.position += Vector2(1.5, 0.5)
    ghosts[l] = [red, blue]

func _set_label(l: Label, value: String) -> void:
    if l.text != value:
        l.text = value
    if ghosts.has(l):
        for g: Label in ghosts[l]:
            g.text = value

func _show_label(l: Label, shown: bool) -> void:
    l.visible = shown
    if ghosts.has(l):
        for g: Label in ghosts[l]:
            g.visible = shown

func _process(delta: float) -> void:
    elapsed += delta
    tracking_phase += delta

    _update_rec()
    _update_timecode()
    _update_tape_and_battery()
    _update_stamp()
    _update_tracking(delta)
    _update_autofocus(delta)
    _update_glitch(delta)

    if Input.is_action_just_pressed("toggle_vhs"):
        vhs_enabled = not vhs_enabled
        vhs_rect.visible = vhs_enabled
        _set_label(status_label, "HANDHELD // VHS ON" if vhs_enabled else "HANDHELD // CLEAN CAMERA")

func _update_rec() -> void:
    # Real camcorders blink the dot, not the word.
    var on: bool = fmod(elapsed, 1.0) < 0.72
    _set_label(rec_label, "\u25cf REC" if on else "   REC")

func _update_timecode() -> void:
    var total_frames: int = int(elapsed * float(tape_fps))
    var frames: int = total_frames % tape_fps
    var secs: int = total_frames / tape_fps
    _set_label(timecode_label, "%02d:%02d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60, frames])

func _update_tape_and_battery() -> void:
    var used: float = tape_start_used_minutes + elapsed / 60.0
    var remaining: int = int(maxf(tape_total_minutes - used, 0.0))
    _set_label(tape_label, "SP  T-120  4:3  REM %dM" % remaining)

    var charge: float = clampf(battery_start_charge - elapsed / maxf(battery_life_seconds, 1.0), 0.0, 1.0)
    var bars: int = int(ceil(charge * 5.0))
    var low: bool = charge < 0.18
    if low and fmod(elapsed, 0.8) > 0.4:
        _set_label(battery_label, "")
    else:
        var text: String = ""
        for i: int in range(5):
            text += "\u25ae" if i < bars else "\u25af"
        if low:
            text += "  E"
        _set_label(battery_label, text)

func _update_stamp() -> void:
    var total: int = stamp_second + stamp_minute * 60 + stamp_hour * 3600 + int(elapsed)
    var day_offset: int = total / 86400
    var t: int = total % 86400
    var hour24: int = t / 3600
    var minute: int = (t / 60) % 60
    var second: int = t % 60

    var month: int = clampi(stamp_month, 1, 12)
    var day: int = stamp_day + day_offset
    while day > MONTH_DAYS[month - 1]:
        day -= MONTH_DAYS[month - 1]
        month += 1
        if month > 12:
            month = 1
    _set_label(date_label, "%s %d %d" % [MONTHS[month - 1], day, stamp_year])

    var suffix: String = "AM" if hour24 < 12 else "PM"
    var hour12: int = hour24 % 12
    if hour12 == 0:
        hour12 = 12
    _set_label(time_label, "%s %d:%02d:%02d" % [suffix, hour12, minute, second])

func _update_tracking(_delta: float) -> void:
    # Slowly wandering tracking marker, plus a hard offset while glitching.
    var drift: int = int(round(sin(tracking_phase * 0.23) * 2.0))
    if glitch_active > 0.0:
        drift = randi_range(-2, 2)
    var bar: String = ""
    for i: int in range(5):
        bar += "\u253c" if i == clampi(2 + drift, 0, 4) else "\u2500"
    _set_label(tracking_label, "TRACKING " + bar)

func _update_autofocus(delta: float) -> void:
    autofocus_timer -= delta
    if autofocus_timer <= 0.0:
        autofocus_active = autofocus_hunt_duration
        autofocus_timer = randf_range(autofocus_min_interval, autofocus_max_interval)

    var pulse: float = 0.0
    if autofocus_active > 0.0:
        autofocus_active -= delta
        var t: float = 1.0 - clampf(autofocus_active / autofocus_hunt_duration, 0.0, 1.0)
        pulse = sin(clampf(t, 0.0, 1.0) * PI)
        _show_label(focus_label, fmod(elapsed, 0.3) < 0.18)
    else:
        _show_label(focus_label, false)

    if material != null:
        material.set_shader_parameter("blur_pulse", pulse)

func _update_glitch(delta: float) -> void:
    if glitch_active > 0.0:
        glitch_active -= delta
        var k: float = clampf(glitch_active / maxf(glitch_duration, 0.001), 0.0, 1.0)
        hud.position = hud_base_position + Vector2(
            randf_range(-glitch_hud_jitter_px, glitch_hud_jitter_px) * k,
            randf_range(-glitch_hud_jitter_px * 0.6, glitch_hud_jitter_px * 0.6) * k
        )
        if material != null:
            material.set_shader_parameter("noise_strength", base_noise_strength + glitch_noise_boost * k)
            material.set_shader_parameter("chromatic", base_chromatic + glitch_chromatic_boost * k)
        if glitch_active <= 0.0:
            hud.position = hud_base_position
            if material != null:
                material.set_shader_parameter("noise_strength", base_noise_strength)
                material.set_shader_parameter("chromatic", base_chromatic)
        return

    glitch_timer -= delta
    if glitch_timer <= 0.0:
        trigger_dropout()
        glitch_timer = randf_range(glitch_min_interval, glitch_max_interval)

func trigger_dropout() -> void:
    glitch_duration = randf_range(glitch_min_duration, glitch_max_duration)
    glitch_active = glitch_duration

func trigger_autofocus_hunt() -> void:
    autofocus_active = autofocus_hunt_duration

func set_dirt_intensity(value: float) -> void:
    dirt_intensity = value
    if material != null:
        material.set_shader_parameter("dirt_intensity", value)
