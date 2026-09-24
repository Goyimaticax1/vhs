shader_type canvas_item;
render_mode unshaded;

// Low-band VHS chain:
//   lens warp -> low-res luma raster -> heavily subsampled chroma ->
//   threshold bloom + halation -> bloom-gated lens dirt -> tape noise -> vignette
//
// The old version faked "VHS" by striping the image with a 960 Hz scanline
// sine, which is why it read as LINES instead of a bad tape. This one actually
// resamples the picture to a tape-grade raster (~296x224 luma, ~48 chroma
// samples per line, which is roughly real VHS chroma bandwidth), so the image
// is genuinely low quality: soft, smeared colour, blocky edges. Scanlines are
// now locked to the raster and almost invisible.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float luma_samples : hint_range(120.0, 640.0) = 296.0;
uniform float tape_lines : hint_range(120.0, 480.0) = 224.0;
uniform float chroma_samples : hint_range(12.0, 240.0) = 48.0;
uniform float chroma_lines : hint_range(60.0, 480.0) = 148.0;
uniform float softness : hint_range(0.0, 4.0) = 1.35;

uniform float fisheye_strength : hint_range(0.0, 1.0) = 0.30;
uniform float distortion : hint_range(0.0, 0.08) = 0.010;
uniform float chromatic : hint_range(0.0, 0.02) = 0.0022;
uniform float vignette : hint_range(0.0, 0.8) = 0.18;

// Proper bloom: energy above a threshold, gathered in two rings, then pushed
// toward red (halation) the way a real lens + tape does around a hot source.
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float bloom_intensity : hint_range(0.0, 3.0) = 1.15;
uniform float bloom_radius : hint_range(0.5, 14.0) = 4.5;
uniform float halation : hint_range(0.0, 1.0) = 0.45;

uniform float tape_grain : hint_range(0.0, 0.3) = 0.038;
uniform float scanlines : hint_range(0.0, 0.3) = 0.012;
uniform float noise_strength : hint_range(0.0, 0.2) = 0.020;

// Dirt is multiplied by how much bloom energy is actually landing on the
// glass, so it is invisible in the dark and only flares up when you point the
// camera at something bright.
uniform float dirt_intensity : hint_range(0.0, 3.0) = 0.35;
uniform float dirt_threshold : hint_range(0.0, 2.0) = 0.16;
uniform float dirt_softness : hint_range(0.01, 2.0) = 0.42;

uniform float blur_pulse : hint_range(0.0, 1.0) = 0.0;

const float TAU_F = 6.28318530718;

const vec2 RING[8] = vec2[8](
    vec2(1.0, 0.0), vec2(0.70711, 0.70711), vec2(0.0, 1.0), vec2(-0.70711, 0.70711),
    vec2(-1.0, 0.0), vec2(-0.70711, -0.70711), vec2(0.0, -1.0), vec2(0.70711, -0.70711)
);

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec2 warp_uv(vec2 uv) {
    vec2 p = uv * 2.0 - 1.0;
    float r2 = dot(p, p);
    float fish_k = fisheye_strength * 0.32;
    p *= 1.0 + fish_k * r2 + fish_k * 0.6 * r2 * r2;
    p *= 1.0 + distortion * r2;
    p.x += sin(p.y * 18.0 + TIME * 0.22) * 0.0010;
    p.y += sin(p.x * 12.0 - TIME * 0.17) * 0.0007;
    return p * 0.5 + 0.5;
}

vec3 tap(vec2 uv) {
    return texture(screen_texture, clamp(uv, vec2(0.0015), vec2(0.9985))).rgb;
}

float luma_of(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

// Snap to the tape raster, then blur across one raster cell. That combination
// is what gives the soft, mushy, low-resolution look instead of a clean
// pixelation.
vec3 resample(vec2 uv, vec2 res, float soft) {
    vec2 snapped = (floor(uv * res) + 0.5) / res;
    vec2 px = soft / res;
    vec3 c = tap(snapped) * 0.36;
    c += tap(snapped + vec2(px.x, 0.0)) * 0.16;
    c += tap(snapped - vec2(px.x, 0.0)) * 0.16;
    c += tap(snapped + vec2(0.0, px.y)) * 0.16;
    c += tap(snapped - vec2(0.0, px.y)) * 0.16;
    return c;
}

vec3 bloom_gather(vec2 uv, float radius) {
    vec3 acc = vec3(0.0);
    vec2 px = SCREEN_PIXEL_SIZE * radius;
    for (int i = 0; i < 8; i++) {
        vec3 a = tap(uv + RING[i] * px);
        vec3 b = tap(uv + RING[i] * px * 2.7);
        acc += max(a - vec3(bloom_threshold), vec3(0.0)) * 0.6;
        acc += max(b - vec3(bloom_threshold), vec3(0.0)) * 0.4;
    }
    return acc * 0.125;
}

float dirt_blob(vec2 uv, vec2 cell_scale, vec2 seed_offset) {
    vec2 p = uv * cell_scale + seed_offset;
    vec2 id = floor(p);
    float n = hash21(id);
    vec2 f = fract(p) - 0.5;
    float radius = 0.14 + 0.26 * hash21(id + 11.3);
    float d = length(f) - radius;
    float blob = smoothstep(0.06, -0.04, d);
    return blob * step(0.6, n);
}

float dirt_mask(vec2 uv) {
    float d = 0.0;
    d += dirt_blob(uv, vec2(7.0, 6.0), vec2(3.17, 1.71));
    d += dirt_blob(uv, vec2(13.0, 11.0), vec2(9.44, 0.31)) * 0.7;
    d += dirt_blob(uv, vec2(23.0, 19.0), vec2(1.02, 8.66)) * 0.4;
    return clamp(d, 0.0, 1.0);
}

void fragment() {
    vec2 uv = SCREEN_UV;

    float line_id = floor(uv.y * tape_lines);
    float tape_gate = step(0.972, hash21(vec2(floor(TIME * 6.0), line_id)));
    float line_jitter = (hash21(vec2(line_id, floor(TIME * 9.0))) - 0.5) * 0.006 * tape_gate;
    vec2 warped = warp_uv(uv) + vec2(line_jitter, 0.0);

    float soft = softness + blur_pulse * 2.6;
    vec2 chroma_vec = vec2(chromatic + 0.0009 * abs(warped.y - 0.5), 0.0);

    vec3 luma_src = resample(warped, vec2(luma_samples, tape_lines), soft);
    vec3 chroma_hi = resample(warped + chroma_vec, vec2(chroma_samples, chroma_lines), soft * 1.6);
    vec3 chroma_lo = resample(warped - chroma_vec, vec2(chroma_samples, chroma_lines), soft * 1.6);
    vec3 chroma_src = vec3(chroma_lo.r, mix(chroma_hi.g, chroma_lo.g, 0.5), chroma_hi.b);

    float y = luma_of(luma_src);
    vec3 c = clamp(vec3(y) + (chroma_src - vec3(luma_of(chroma_src))) * 1.05, 0.0, 2.0);

    vec3 bloom = bloom_gather(warped, bloom_radius + blur_pulse * 6.0);
    vec3 hal = vec3(bloom.r, bloom.g * 0.45, bloom.b * 0.22);
    bloom = mix(bloom, hal, halation);
    c += bloom * bloom_intensity;

    float bloom_energy = luma_of(bloom) * bloom_intensity;
    float dirt_gate = smoothstep(dirt_threshold, dirt_threshold + dirt_softness, bloom_energy);
    if (dirt_intensity > 0.001 && dirt_gate > 0.001) {
        float dirt = dirt_mask(uv);
        c += dirt * dirt_gate * dirt_intensity * 3.0 * mix(vec3(1.0), vec3(1.0, 0.9, 0.78), halation);
    }

    float n = hash21(floor(uv * vec2(luma_samples, tape_lines)) + floor(TIME * 20.0));
    c += (n - 0.5) * tape_grain;
    float line_noise = hash21(vec2(floor(TIME * 11.0), line_id)) - 0.5;
    c += line_noise * noise_strength;

    float scan = 0.5 + 0.5 * cos(warped.y * tape_lines * TAU_F);
    c *= 1.0 - scan * scanlines;

    vec2 centered = uv * 2.0 - 1.0;
    float edge = smoothstep(0.42, 1.05, length(centered));
    c *= 1.0 - edge * vignette;

    c += sin(TIME * 0.37) * 0.005 + sin(TIME * 0.11 + 2.0) * 0.0035;

    vec2 edge_dist = min(warped, 1.0 - warped);
    float frame_mask = smoothstep(-0.012, 0.014, min(edge_dist.x, edge_dist.y));
    c *= frame_mask;

    COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
