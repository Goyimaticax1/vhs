# VHS Camcorder Operator Camera - Godot 4.8 Mobile

This revision is deliberately scene/node based. The Player, CamcorderRig, SpringArm3D, Camera3D, MobileControls and VHSOverlay are all real nodes visible in the Godot editor. Runtime scripts handle only behavior and animation.

## Scene tree

VHSWorld
- WorldEnvironment
- Level
  - House (all walls/floor/furniture, hand-placed — see Map below)
    - Lighting
- Player
  - CollisionShape3D
- CamcorderRig
  - SpringArm3D
    - CamcorderCamera
- UI
  - MobileControls
- VHSOverlay
  - VHS
  - HUD

## Camera handling

The rig is split into two layers. `CamcorderRig` itself does the slow, heavily-damped operator arm/hand follow (low/mid-frequency body drift, acceleration catch-up, turn counter-sway, regrip) — this is deliberately filtered so it feels like a heavy camcorder being carried. The `CamcorderCamera` leaf gets a second, unfiltered layer applied directly each frame: footstep bob, landing dip, recoil/impact shake, and a constant low-amplitude hand tremor. Footstep bob previously got routed through the same damped spring as the arm sway and was filtered out almost entirely — it's now crisp and clearly visible.

The SpringArm3D is kept in the hierarchy as the camera mount/collision component.

## Mobile

- Left touch: analog movement
- Right touch: free look
- Hold RUN: sprint
- Tap CROUCH: toggle crouch
- Multitouch is supported
- Touch look uses `screen_relative`, which is preferred by Godot for resolution-independent aiming.

## Desktop

- WASD move
- Mouse look
- Shift sprint
- Hold C to crouch (overrides sprint, blocks jump, lowers capsule + camera)
- Space jump
- V toggles VHS
- Escape releases mouse capture
- Losing window focus auto-releases mouse capture

## Camera animation API (CamcorderRig)

- `zoom_to(fov, duration)` / `zoom_reset(duration)` — spring-driven FOV push-in/out
- `recoil(strength)` — kicks the existing pitch/yaw/roll springs, settles naturally
- `snap_shake(strength)` — short decaying impulse layered into the high-frequency noise; auto-fires on hard landings
- `set_crouch_offset(value)` — driven by the player script, lowers the rig height while crouched

## Map

A fully enclosed, hand-placed house (`main.tscn`, under `Level/House`) — every wall, floor, and piece of furniture is an explicit node with an authored `position`/`scale`, not runtime-generated. Footprint is 18m x 14m with 3.6m ceilings (bumped up from an initial 16x12/3.0m pass that felt cramped against the player's 1.72m capsule). Layout: a central hallway (front door at the south wall) splits into four rooms — Living Room and Kitchen on the west side, Bedroom and Study/storage on the east side — each connected to the hallway and to its neighbor through door gaps left in the dividing walls. All structural pieces and furniture reuse one shared unit BoxMesh/BoxShape3D scaled per node, so it's a single mesh resource driving ~36 nodes (cheap on the Y27). Lighting is deliberately sparse — hall, living room, and bedroom have a dim warm bulb; kitchen and study are left dark for that unlit-corner horror-house feel; `WorldEnvironment` ambient is set very low with fog off (small enclosed rooms don't need distance fog).

Player spawns just inside the front door at (0, 1, 6) facing into the hallway.

## Camera feel

Rearchitected the whole handheld system around a **Shakify-style continuous state blend**, the same idea Blender's Camera Shakify addon uses: four motion profiles (idle/walk/run/crouch), each with its own position-sway amplitude, rotation-sway amplitude, and bob amplitude/frequency/bounce — and instead of switching which profile drives the camera, four weights (`w_idle`, `w_walk`, `w_sprint`, `w_crouch`) are continuously lerped toward a one-hot target every frame and normalized to sum to 1. Every amplitude used anywhere in the rig is a weighted sum across all four profiles, so there is never a discrete "jump" to a new target — transitioning between states is a smooth cross-fade of motion characteristics, not a redirect-then-chase. Crouch now has its own arm-sway character too (previously it only affected footstep bob, so the slow "held low" sway during crouch was missing).

- Bob is now genuinely visible: the old rig routed footstep bob through the same heavily-damped spring used for slow hand/arm follow, which filtered a 7-10Hz signal down to nothing. Footstep bob, landing dip, and recoil/impact shake live on the camera leaf directly (crisp, unfiltered) while the rig root keeps only the slow ambient sway.
- A persistent low-amplitude hand tremor (always on, not tied to movement) plus smoothly-blended per-stride amplitude/frequency/bounce variance so steps aren't perfectly identical — reads more like real hands holding a camera, not a metronome.
- Two earlier snapping bugs, now fixed: (1) discrete impulse kicks were fired on every stride and every movement start/stop, stacking on top of the bob itself — removed. (2) the footstep vertical bounce used `abs(sin())`, which has a hard kink at every zero-crossing — swapped for `sin()²`, same twice-per-stride bounce shape, continuous derivative, no cusp.
- Crouch transition is slow and deliberate (`crouch_blend_speed = 1.7`, ~1.5-2s), and movement speed blends with the crouch pose instead of snapping.
- Root cause of the "sudden bounce": the crouch height offset (a ~0.76m step) was being fed into the same underdamped root-follow spring used for tiny ambient sways — a step that big makes a tuned-for-millimeters spring overshoot before settling, and that overshoot was also swamping the crouch pose itself. Crouch height now applies directly to the camera leaf (same unfiltered layer as bob/land-dip) — moves cleanly over its own blend, no spring overshoot.
- REC/status text and the viewfinder reticle now render *before* the VHS shader pass (moved earlier in draw order within the CanvasLayer) so they get captured into `screen_texture` and warped along with everything else — barrel distortion, chromatic aberration, grain, all of it. Burned into the "recorded" image now, not a clean UI overlay on top of it.
- Added bending viewfinder corner brackets (small L-shaped tick marks near all four corners) — render pre-shader like the REC text, so they warp with the fisheye too instead of sitting static.
- Fisheye corners: the barrel-warp pushes UVs outside [0,1]; previously the shader clamped them to the edge pixel, smearing it outward. Now out-of-bounds UVs render black with a soft falloff (`frame_mask`), giving proper rounded CRT/TV-style corners instead of a stretching artifact.
- Mobile touch controls no longer get warped: the VHS post-process CanvasLayer was drawing *above* the touch UI (layer 100 vs UI's 90), so the joystick/buttons were being captured into the shader's screen read. VHS overlay now sits at layer 10, below the UI's 90 — game world gets the full VHS treatment, touch controls stay clean on top (drawn after, never enters the shader's screen read).

## VHS overlay (post shader)

- Procedural dirt/dust lens mask (no external texture, matches UE5 Step 4's "only visible on bright bloom" behavior) — `dirt_intensity` uniform, `set_dirt_intensity()` on VHSOverlay
- Autofocus-hunt blur pulses fire on a random timer (UE5 Step 2's blur widget, reimagined as a camcorder behavior) via `blur_pulse` uniform; call `trigger_autofocus_hunt()` on VHSOverlay to fire one on demand
- `fisheye_strength` uniform (default 0.35) — real barrel distortion, separate from the subtle tape-warp wobble
- Sharpen (Step 5), chromatic aberration (Step 7), lens warp/distortion (Step 8), scanlines/grain, and vignette unchanged

## Rendering

- Godot 4.8-dev6 target
- Mobile renderer
- 1280x960 4:3 base frame
- 0.85 3D scale for mobile headroom
- One fullscreen canvas-item shader for VHS treatment

Godot's current 4.8 documentation marks the `latest` docs as unstable; this project intentionally uses conservative 4.x APIs. 4.8-dev6 is the current 4.8 development snapshot dated September 15, 2026.
