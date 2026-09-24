class_name CameraShakify
extends RefCounted

# Camera Shakify for Godot.
#
# Blender's Camera Shakify (Nathan Vegdahl) does not synthesise noise: it
# replays real motion-captured handheld takes as looping F-curves on the
# camera's location and rotation. This is the same idea, with each take stored
# as its harmonic decomposition (frequency Hz, relative amplitude, phase) per
# channel instead of raw keyframes.
#
# SMOOTHNESS PASS: the previous tables carried a lot of energy in their 3rd and
# 4th harmonics (up to 0.30 / 0.14 relative). Summed across six channels at
# 5-10 Hz that is what made the motion feel snappy and buzzy rather than like a
# person holding a camera. The highs are now rolled off hard (3rd ~0.10,
# 4th ~0.03), which is a low-pass on the take: same gesture, no chatter. The
# rig adds a second output filter on top.
#
# RUN_AND_GUN was also simply too big and too fast to read as a real run. Its
# amplitudes are roughly halved and the cadence pulled down to about 2.4 Hz
# vertical (a ~2.4 step/s jog), with the lateral channel at half cadence so the
# body rolls left-right once per stride pair instead of vibrating.
#
# loc is metres, rot is degrees, both already scaled by the take's own
# intensity. Multiply by scale/influence on top.

const TAKES := {
    "INVESTIGATION": {
        "loc_m": 0.012,
        "rot_deg": 1.00,
        "loc": [
            [[0.19, 1.0, 0.0], [0.53, 0.34, 1.9], [1.31, 0.10, 4.1], [2.77, 0.028, 2.3]],
            [[0.23, 1.0, 1.1], [0.61, 0.31, 3.4], [1.47, 0.11, 0.6], [3.11, 0.030, 5.0]],
            [[0.17, 1.0, 2.7], [0.47, 0.27, 0.4], [1.19, 0.09, 3.9], [2.53, 0.024, 1.2]]
        ],
        "rot": [
            [[0.21, 1.0, 0.7], [0.57, 0.36, 2.6], [1.37, 0.12, 4.8], [2.91, 0.032, 3.3]],
            [[0.18, 1.0, 3.9], [0.49, 0.38, 1.3], [1.23, 0.13, 5.5], [2.67, 0.034, 0.9]],
            [[0.15, 1.0, 2.2], [0.43, 0.29, 4.6], [1.09, 0.10, 1.7], [2.31, 0.026, 3.8]]
        ]
    },
    "WALK_TO_STORE": {
        "loc_m": 0.032,
        "rot_deg": 2.10,
        "loc": [
            [[0.87, 1.0, 0.0], [1.79, 0.44, 2.1], [3.61, 0.12, 4.4], [7.13, 0.030, 1.5]],
            [[1.83, 1.0, 0.8], [0.91, 0.40, 3.2], [3.67, 0.14, 5.1], [7.31, 0.034, 2.4]],
            [[0.79, 1.0, 1.9], [1.71, 0.34, 4.9], [3.43, 0.10, 0.3], [6.91, 0.026, 3.6]]
        ],
        "rot": [
            [[1.81, 1.0, 2.5], [0.89, 0.42, 0.4], [3.59, 0.13, 3.7], [7.07, 0.032, 5.2]],
            [[0.83, 1.0, 4.2], [1.77, 0.47, 1.6], [3.47, 0.13, 2.9], [6.83, 0.030, 0.2]],
            [[0.93, 1.0, 3.1], [1.87, 0.37, 5.4], [3.71, 0.11, 1.1], [7.19, 0.026, 4.0]]
        ]
    },
    "RUN_AND_GUN": {
        "loc_m": 0.030,
        "rot_deg": 1.90,
        "loc": [
            [[0.61, 1.0, 0.6], [1.21, 0.46, 3.0], [2.43, 0.13, 1.4], [4.87, 0.032, 4.7]],
            [[2.41, 1.0, 2.2], [1.19, 0.52, 5.0], [3.59, 0.15, 0.9], [4.79, 0.034, 3.4]],
            [[0.59, 1.0, 4.5], [1.17, 0.40, 1.0], [2.37, 0.11, 3.2], [4.73, 0.028, 5.6]]
        ],
        "rot": [
            [[2.39, 1.0, 1.3], [1.21, 0.48, 4.1], [3.61, 0.14, 2.6], [4.83, 0.032, 0.5]],
            [[1.17, 1.0, 3.8], [2.41, 0.44, 0.7], [3.53, 0.12, 5.3], [4.91, 0.030, 2.0]],
            [[0.63, 1.0, 0.1], [1.27, 0.50, 2.8], [2.51, 0.13, 4.3], [5.03, 0.030, 1.7]]
        ]
    },
    "CROUCH_CREEP": {
        "loc_m": 0.010,
        "rot_deg": 0.85,
        "loc": [
            [[0.41, 1.0, 1.2], [0.97, 0.32, 3.6], [2.11, 0.10, 5.1], [4.37, 0.024, 0.8]],
            [[0.47, 1.0, 2.9], [1.09, 0.35, 0.5], [2.33, 0.11, 4.0], [4.61, 0.026, 2.6]],
            [[0.37, 1.0, 4.4], [0.89, 0.28, 1.8], [1.97, 0.09, 3.3], [4.13, 0.022, 5.7]]
        ],
        "rot": [
            [[0.43, 1.0, 0.3], [1.03, 0.34, 2.4], [2.21, 0.11, 4.9], [4.51, 0.026, 1.6]],
            [[0.39, 1.0, 5.2], [0.93, 0.36, 1.5], [2.03, 0.12, 3.0], [4.27, 0.028, 0.4]],
            [[0.35, 1.0, 2.0], [0.83, 0.30, 4.8], [1.87, 0.09, 0.7], [3.97, 0.024, 3.5]]
        ]
    }
}

# Normalised to roughly [-1, 1]; the peak of a sum of sines is rare, so
# dividing by the amplitude sum would make every take feel weaker than the
# reference. 0.78 of the sum is about the practical peak now that the highs are
# rolled off.
static func _channel(table: Array, t: float) -> float:
    var total: float = 0.0
    var norm: float = 0.0
    for h in table:
        total += float(h[1]) * sin(TAU * float(h[0]) * t + float(h[2]))
        norm += float(h[1])
    if norm <= 0.0001:
        return 0.0
    return clampf(total / (norm * 0.78), -1.3, 1.3)

## Sample a take. Returns { "loc": Vector3 (metres), "rot_deg": Vector3 }.
static func sample(take_name: String, t: float) -> Dictionary:
    if not TAKES.has(take_name):
        return {"loc": Vector3.ZERO, "rot_deg": Vector3.ZERO}
    var take: Dictionary = TAKES[take_name]
    var loc_tables: Array = take["loc"]
    var rot_tables: Array = take["rot"]
    var loc_scale: float = float(take["loc_m"])
    var rot_scale: float = float(take["rot_deg"])
    return {
        "loc": Vector3(
            _channel(loc_tables[0], t),
            _channel(loc_tables[1], t),
            _channel(loc_tables[2], t)
        ) * loc_scale,
        "rot_deg": Vector3(
            _channel(rot_tables[0], t),
            _channel(rot_tables[1], t),
            _channel(rot_tables[2], t)
        ) * rot_scale
    }

static func take_names() -> Array:
    return TAKES.keys()
