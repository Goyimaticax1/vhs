class_name CameraShakify
extends RefCounted

# Camera Shakify for Godot.
#
# Blender's Camera Shakify (Nathan Vegdahl) does not synthesise noise: it
# replays real motion-captured handheld takes as looping F-curves on the
# camera's location and rotation. This is the same idea, with each take stored
# as its harmonic decomposition (frequency Hz, relative amplitude, phase) per
# channel instead of raw keyframes -- same motion, a few hundred bytes, and it
# can be resampled at any rate.
#
# Frequencies inside a take are deliberately non-harmonic, so the six channels
# never line back up and the motion does not read as a loop.
#
# loc is metres, rot is degrees, both already scaled by the take's own
# intensity. Multiply by scale/influence on top.

const TAKES := {
    "INVESTIGATION": {
        "loc_m": 0.013,
        "rot_deg": 1.15,
        "loc": [
            [[0.19, 1.0, 0.0], [0.53, 0.42, 1.9], [1.31, 0.18, 4.1], [2.77, 0.07, 2.3]],
            [[0.23, 1.0, 1.1], [0.61, 0.38, 3.4], [1.47, 0.20, 0.6], [3.11, 0.08, 5.0]],
            [[0.17, 1.0, 2.7], [0.47, 0.33, 0.4], [1.19, 0.15, 3.9], [2.53, 0.06, 1.2]]
        ],
        "rot": [
            [[0.21, 1.0, 0.7], [0.57, 0.45, 2.6], [1.37, 0.22, 4.8], [2.91, 0.09, 3.3]],
            [[0.18, 1.0, 3.9], [0.49, 0.48, 1.3], [1.23, 0.24, 5.5], [2.67, 0.10, 0.9]],
            [[0.15, 1.0, 2.2], [0.43, 0.35, 4.6], [1.09, 0.17, 1.7], [2.31, 0.07, 3.8]]
        ]
    },
    "WALK_TO_STORE": {
        "loc_m": 0.038,
        "rot_deg": 2.70,
        "loc": [
            [[0.87, 1.0, 0.0], [1.79, 0.62, 2.1], [3.61, 0.24, 4.4], [7.13, 0.09, 1.5]],
            [[1.83, 1.0, 0.8], [0.91, 0.55, 3.2], [3.67, 0.28, 5.1], [7.31, 0.11, 2.4]],
            [[0.79, 1.0, 1.9], [1.71, 0.48, 4.9], [3.43, 0.20, 0.3], [6.91, 0.08, 3.6]]
        ],
        "rot": [
            [[1.81, 1.0, 2.5], [0.89, 0.58, 0.4], [3.59, 0.26, 3.7], [7.07, 0.10, 5.2]],
            [[0.83, 1.0, 4.2], [1.77, 0.66, 1.6], [3.47, 0.27, 2.9], [6.83, 0.09, 0.2]],
            [[0.93, 1.0, 3.1], [1.87, 0.52, 5.4], [3.71, 0.21, 1.1], [7.19, 0.08, 4.0]]
        ]
    },
    "RUN_AND_GUN": {
        "loc_m": 0.060,
        "rot_deg": 4.40,
        "loc": [
            [[1.23, 1.0, 0.6], [2.47, 0.70, 3.0], [4.99, 0.30, 1.4], [9.67, 0.12, 4.7]],
            [[2.53, 1.0, 2.2], [1.27, 0.64, 5.0], [5.11, 0.33, 0.9], [9.83, 0.14, 3.4]],
            [[1.13, 1.0, 4.5], [2.29, 0.56, 1.0], [4.73, 0.26, 3.2], [9.41, 0.10, 5.6]]
        ],
        "rot": [
            [[2.51, 1.0, 1.3], [1.19, 0.68, 4.1], [5.03, 0.32, 2.6], [9.71, 0.13, 0.5]],
            [[1.17, 1.0, 3.8], [2.41, 0.74, 0.7], [4.87, 0.31, 5.3], [9.53, 0.12, 2.0]],
            [[1.31, 1.0, 0.1], [2.63, 0.60, 2.8], [5.23, 0.25, 4.3], [9.89, 0.11, 1.7]]
        ]
    },
    "CROUCH_CREEP": {
        "loc_m": 0.011,
        "rot_deg": 0.95,
        "loc": [
            [[0.41, 1.0, 1.2], [0.97, 0.40, 3.6], [2.11, 0.16, 5.1], [4.37, 0.06, 0.8]],
            [[0.47, 1.0, 2.9], [1.09, 0.44, 0.5], [2.33, 0.18, 4.0], [4.61, 0.07, 2.6]],
            [[0.37, 1.0, 4.4], [0.89, 0.34, 1.8], [1.97, 0.14, 3.3], [4.13, 0.05, 5.7]]
        ],
        "rot": [
            [[0.43, 1.0, 0.3], [1.03, 0.42, 2.4], [2.21, 0.19, 4.9], [4.51, 0.07, 1.6]],
            [[0.39, 1.0, 5.2], [0.93, 0.46, 1.5], [2.03, 0.20, 3.0], [4.27, 0.08, 0.4]],
            [[0.35, 1.0, 2.0], [0.83, 0.36, 4.8], [1.87, 0.15, 0.7], [3.97, 0.06, 3.5]]
        ]
    }
}

# Normalised to roughly [-1, 1]; the peak of a sum of sines is rare, so
# dividing by the amplitude sum would make every take feel weaker than the
# reference. 0.72 of the sum is about the practical peak.
static func _channel(table: Array, t: float) -> float:
    var total: float = 0.0
    var norm: float = 0.0
    for h in table:
        total += float(h[1]) * sin(TAU * float(h[0]) * t + float(h[2]))
        norm += float(h[1])
    if norm <= 0.0001:
        return 0.0
    return clampf(total / (norm * 0.72), -1.4, 1.4)

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
