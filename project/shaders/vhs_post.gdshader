shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float fisheye_strength : hint_range(0.0, 1.0) = 0.35;
uniform float distortion : hint_range(0.0, 0.08) = 0.011;
uniform float chromatic : hint_range(0.0, 0.01) = 0.0016;
uniform float grain : hint_range(0.0, 0.2) = 0.052;
uniform float scanline_strength : hint_range(0.0, 0.3) = 0.045;
uniform float noise_strength : hint_range(0.0, 0.2) = 0.024;
uniform float vignette : hint_range(0.0, 0.6) = 0.14;
uniform float sharpness : hint_range(0.0, 0.5) = 0.11;
uniform float bloom_bleed : hint_range(0.0, 0.2) = 0.035;
uniform float dirt_intensity : hint_range(0.0, 1.0) = 0.35;
uniform float blur_pulse : hint_range(0.0, 1.0) = 0.0;

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

float dirt_blob(vec2 uv, vec2 cell_scale, vec2 seed_offset) {
    vec2 p = uv * cell_scale + seed_offset;
    vec2 id = floor(p);
    float n = hash21(id);
    vec2 f = fract(p) - 0.5;
    float radius = 0.14 + 0.26 * hash21(id + 11.3);
    float d = length(f) - radius;
    float blob = smoothstep(0.05, -0.03, d);
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
    float line_id = floor(uv.y * 270.0);
    float tape_gate = step(0.968, hash21(vec2(floor(TIME * 7.0), line_id)));
    float line_jitter = (hash21(vec2(line_id, floor(TIME * 11.0))) - 0.5) * 0.0045 * tape_gate;
    vec2 warped = warp_uv(uv) + vec2(line_jitter, 0.0);
    vec2 edge_clamp = vec2(0.001);
    vec2 edge_max = vec2(0.999);

    vec2 chroma_vec = vec2(chromatic + 0.0008 * abs(warped.y - 0.5), 0.0);
    float r = texture(screen_texture, clamp(warped - chroma_vec, edge_clamp, edge_max)).r;
    float g = texture(screen_texture, clamp(warped, edge_clamp, edge_max)).g;
    float b = texture(screen_texture, clamp(warped + chroma_vec, edge_clamp, edge_max)).b;
    vec3 c = vec3(r, g, b);

    vec2 edge_dist = min(warped, 1.0 - warped);
    float frame_mask = smoothstep(-0.012, 0.014, min(edge_dist.x, edge_dist.y));

    vec2 d = SCREEN_PIXEL_SIZE * (1.25 + blur_pulse * 5.0);
    vec3 soft = c;
    soft += texture(screen_texture, clamp(warped + vec2(d.x, 0.0), edge_clamp, edge_max)).rgb;
    soft += texture(screen_texture, clamp(warped - vec2(d.x, 0.0), edge_clamp, edge_max)).rgb;
    soft += texture(screen_texture, clamp(warped + vec2(0.0, d.y), edge_clamp, edge_max)).rgb;
    soft += texture(screen_texture, clamp(warped - vec2(0.0, d.y), edge_clamp, edge_max)).rgb;
    soft *= 0.2;
    float sharpen_blend = clamp(1.0 + sharpness - blur_pulse * 1.6, 0.0, 1.0 + sharpness);
    c = mix(soft, c, sharpen_blend);

    float n = hash21(floor(uv * vec2(960.0, 540.0)) + floor(TIME * 24.0));
    float scan = sin(uv.y * 960.0) * 0.5 + 0.5;
    float line_noise = hash21(vec2(floor(TIME * 13.0), floor(uv.y * 170.0))) - 0.5;
    c += (n - 0.5) * grain;
    c += line_noise * noise_strength * (0.55 + 0.45 * scan);
    c *= 1.0 - scan * scanline_strength;

    float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
    float bloom_gate = max(luma - 0.68, 0.0);
    c += bloom_gate * bloom_bleed;

    if (dirt_intensity > 0.001) {
        float dirt = dirt_mask(uv);
        c += dirt * bloom_gate * dirt_intensity * 1.6;
        c *= 1.0 - dirt * 0.06;
    }

    vec2 centered = uv * 2.0 - 1.0;
    float edge = smoothstep(0.38, 1.02, length(centered));
    c *= 1.0 - edge * vignette;

    float exposure_drift = sin(TIME * 0.37) * 0.006 + sin(TIME * 0.11 + 2.0) * 0.004;
    c += exposure_drift;
    c *= frame_mask;
    COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
