# Handheld camera shake

`scripts/handheld_shake.gd` adds real handheld-operator camera motion, in the
spirit of Blender's **Camera Shakify** addon (Nathan Vegdahl / Ian Hubert),
which plays back motion-captured handheld takes with influence / scale / speed
controls. This is the same *character*, generated procedurally so it never
loops or repeats.

**It is not head bob.** No sine waves anywhere. Motion comes from fractal (fBm)
Perlin noise: a slow wander, a medium sway and a fine tremor summed together,
all aperiodic, with rotation dominant, translation tiny and roll smallest.

## Install

1. Copy `scripts/handheld_shake.gd` into the project's `scripts/` folder
   (inside `VHS_Camcorder_Godot48_Nodes/`).
2. In your camera scene, insert a plain `Node3D` between the rig and the
   `Camera3D`, attach the script, and reparent the camera under it:

```
CameraRig            <- your existing rig script, unchanged
 └─ HandheldShake    <- Node3D + handheld_shake.gd
     └─ Camera3D
```

Because the node only offsets itself relative to its own rest pose, your
existing look/aim/follow code keeps working and never fights the shake.

## Controls (inspector)

| Property | Meaning |
| --- | --- |
| `preset` | `IDLE_BREATH`, `INVESTIGATION`, `HANDHELD_LOOSE`, `WALK`, `CAMCORDER_VHS` |
| `influence` | Master blend, 0–1. Tween it to fade shake in/out per shot. |
| `scale` | Amplitude only — bigger/smaller shake at the same speed. |
| `speed` | Frequency only — jitterier/calmer operator at the same size. |
| `random_seed` | Different take, same style. |
| `ease_in_time` | Fade-in so it never pops on frame 0. |
| `position_amplitude` / `rotation_amplitude` / `base_frequency` | Manual overrides; leave at zero to use the preset. |

## Tuning notes

- Start with `CAMCORDER_VHS`, then adjust `scale` first, `speed` second.
- If it reads as floaty, lower `scale` and raise `speed` slightly.
- If it reads as mechanical, raise `scale` and lower `speed` — the slow octaves
  are what sell "a person is holding this".
- Keep translation small; audiences read rotation as handheld, translation as
  the camera being physically shoved.

## Code hooks

```gdscript
$CameraRig/HandheldShake.influence = 0.3          # calm down for a cutscene
create_tween().tween_property($CameraRig/HandheldShake, "influence", 1.0, 0.8)
$CameraRig/HandheldShake.kick(Vector3(1.8, -0.9, 0.4))   # landing / impact
```
