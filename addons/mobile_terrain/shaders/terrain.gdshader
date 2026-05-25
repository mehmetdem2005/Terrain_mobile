shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Per-slot PBR. Each of the 4 splatmap channels controls a texture bundle
// (albedo + normal + roughness + AO) AND its own scale / normal-strength /
// roughness-multiplier / AO-strength (the *_arr[4] uniforms, index = channel).
// Variation, cell size, rotation jitter and triplanar blend stay GLOBAL.

uniform sampler2D splatmap : filter_linear_mipmap, hint_default_black, repeat_disable;

// Albedo (RGB colour, sRGB encoded). hint_default_black means an empty
// slot contributes nothing to the final colour.
uniform sampler2D tex_a_0 : source_color, filter_linear_mipmap_anisotropic, hint_default_black;
uniform sampler2D tex_a_1 : source_color, filter_linear_mipmap_anisotropic, hint_default_black;
uniform sampler2D tex_a_2 : source_color, filter_linear_mipmap_anisotropic, hint_default_black;
uniform sampler2D tex_a_3 : source_color, filter_linear_mipmap_anisotropic, hint_default_black;

// Normal maps (tangent-space). hint_normal defaults empty slots to flat.
uniform sampler2D tex_n_0 : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_n_1 : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_n_2 : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_n_3 : hint_normal, filter_linear_mipmap_anisotropic;

// Roughness (single channel, linear, R = roughness). hint_default_white
// = full roughness when empty.
uniform sampler2D tex_r_0 : filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D tex_r_1 : filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D tex_r_2 : filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D tex_r_3 : filter_linear_mipmap_anisotropic, hint_default_white;

// AO (single channel, linear, R = occlusion factor).
uniform sampler2D tex_ao_0 : filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D tex_ao_1 : filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D tex_ao_2 : filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D tex_ao_3 : filter_linear_mipmap_anisotropic, hint_default_white;

// Per-slot scalars (index = splatmap channel 0..3). Set from GDScript via
// update_shader_textures(); default 1.0 so an un-set array still renders sanely.
uniform float tex_scale_arr[4];
uniform float normal_strength_arr[4];
uniform float roughness_mult_arr[4];
uniform float ao_strength_arr[4];

// Global anti-tiling + slope blend (apply to all slots).
uniform float texture_variation : hint_range(0.0, 1.0) = 0.0;
uniform float texture_cell_size : hint_range(1.0, 50.0) = 10.0;
uniform float rotation_jitter : hint_range(0.0, 1.0) = 0.0;
uniform float triplanar_blend : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

float _mt_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise in [0,1] (bilinear-blended hashed lattice). Used to warp
// UVs CONTINUOUSLY so texture tiling is broken without introducing seams.
float _mt_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = _mt_hash(i);
	float b = _mt_hash(i + vec2(1.0, 0.0));
	float c = _mt_hash(i + vec2(0.0, 1.0));
	float d = _mt_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Continuous (seam-free) domain warp for the "Varyasyon" shift. Displaces the
// sampling UV by a smooth noise field so tiling repetition is broken without any
// hard cell borders. `cell_uv` sets the warp wavelength (one cell).
vec2 _mt_warp_uv(vec2 uv, float cell_uv) {
	if (texture_variation < 0.001) {
		return uv;
	}
	vec2 wp = uv / cell_uv;
	vec2 warp = vec2(
		_mt_vnoise(wp) - 0.5,
		_mt_vnoise(wp + vec2(37.2, 17.9)) - 0.5);
	return uv + warp * cell_uv * texture_variation;
}

vec2 _mt_rotate_uv_around(vec2 uv, vec2 centre, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	vec2 d = uv - centre;
	return centre + vec2(c * d.x - s * d.y, s * d.x + c * d.y);
}

// One texture-bombing tap: sample `s` with `uv` rotated around `cell`'s centre
// by that cell's random angle. The caller bilinearly blends the 2x2 neighbour
// taps so per-cell rotation cross-fades instead of hard-seaming at cell borders.
vec3 _mt_bomb(sampler2D s, vec2 uv, vec2 cell, float cell_uv) {
	float angle = _mt_hash(cell) * 6.28318530718 * rotation_jitter;
	vec2 centre = (cell + 0.5) * cell_uv;
	return texture(s, _mt_rotate_uv_around(uv, centre, angle)).rgb;
}

// Single varied sample of map `s`. `uv` is the slot's tiled UV (wpos*scale),
// `scale` converts UV<->world. Applies, both SEAM-FREE: (1) a continuous domain
// warp for the "Varyasyon" shift, then (2) "Rotasyon Jitter" as a 2x2 cell
// texture-bombing blend. Per-cell TONE is albedo-only (see _mt_tone()).
vec3 _mt_sample_var(sampler2D s, vec2 uv, float scale) {
	if (texture_variation < 0.001 && rotation_jitter < 0.001) {
		return texture(s, uv).rgb;
	}
	float cell_uv = max(texture_cell_size * scale, 0.0001);

	// (1) Variation shift: continuous warp (no seams).
	vec2 warped = _mt_warp_uv(uv, cell_uv);

	if (rotation_jitter < 0.001) {
		return texture(s, warped).rgb;
	}

	// (2) Rotation jitter: bilinear blend of the 4 cells whose centres surround
	// this point (centre-aligned via cs - 0.5). Each contributes its own rotated
	// sample, so rotations cross-fade -> no hard seams.
	vec2 cs = warped / cell_uv - 0.5;
	vec2 cell = floor(cs);
	vec2 f = fract(cs);
	vec2 w = f * f * (3.0 - 2.0 * f);
	vec3 c00 = _mt_bomb(s, warped, cell + vec2(0.0, 0.0), cell_uv);
	vec3 c10 = _mt_bomb(s, warped, cell + vec2(1.0, 0.0), cell_uv);
	vec3 c01 = _mt_bomb(s, warped, cell + vec2(0.0, 1.0), cell_uv);
	vec3 c11 = _mt_bomb(s, warped, cell + vec2(1.0, 1.0), cell_uv);
	return mix(mix(c00, c10, w.x), mix(c01, c11, w.x), w.y);
}

// Triplanar-axis sample: warp only. Rotation bombing is intentionally SKIPPED on
// the triplanar (slope) path — triplanar already mixes three projections so tiling
// seams read minimally there, and skipping the 4-tap bomb per axis keeps mobile
// cost bounded when triplanar_blend and rotation_jitter are both enabled.
vec3 _mt_sample_tri(sampler2D s, vec2 uv, float scale) {
	if (texture_variation < 0.001) {
		return texture(s, uv).rgb;
	}
	return texture(s, _mt_warp_uv(uv, max(texture_cell_size * scale, 0.0001))).rgb;
}

// Per-cell albedo TONE (brightness + slight tint) — the visible "blocks" of the
// "Varyasyon" knob. Applied to FINAL albedo only so normal/roughness/AO stay
// physically correct. Cell is world-space (scale-independent) -> blocks line up
// across slots. Returns a multiplier (1.0 = no change when variation is 0).
vec3 _mt_tone(vec2 world_xz) {
	if (texture_variation < 0.001) {
		return vec3(1.0);
	}
	vec2 cell = floor(world_xz / max(texture_cell_size, 0.5));
	float hb = _mt_hash(cell + vec2(23.0, 7.0));
	float ht = _mt_hash(cell + vec2(5.0, 41.0));
	float bright = mix(1.0, 0.78 + hb * 0.44, texture_variation);
	float t = (ht - 0.5) * 0.18 * texture_variation;
	return vec3(bright) * vec3(1.0 + t, 1.0, 1.0 - t);
}

vec3 _mt_triplanar(sampler2D s, vec3 wpos, float scale) {
	vec3 n = normalize(v_world_normal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);

	vec3 xz = _mt_sample_tri(s, wpos.xz * scale, scale);
	vec3 xy = _mt_sample_tri(s, wpos.xy * scale, scale);
	vec3 yz = _mt_sample_tri(s, wpos.zy * scale, scale);
	return xz * w.y + yz * w.x + xy * w.z;
}

// TKT-018: per-slot scale threaded in. The SINGLE sampling path for every map
// of a slot (albedo, normal, roughness, AO) — they share the slot's scale +
// the global variation/jitter/triplanar so a slot's maps stay coherent.
vec3 _mt_slot_sample(sampler2D s, vec3 wpos, float scale) {
	vec3 xz = _mt_sample_var(s, wpos.xz * scale, scale);
	if (triplanar_blend < 0.001) return xz;
	vec3 tri = _mt_triplanar(s, wpos, scale);
	return mix(xz, tri, triplanar_blend);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec4 blend = texture(splatmap, UV);
	float total_blend = blend.r + blend.g + blend.b + blend.a;
	if (total_blend > 0.0001) {
		blend /= total_blend;
	} else {
		blend = vec4(1.0, 0.0, 0.0, 0.0);
	}

	vec3 c0 = _mt_slot_sample(tex_a_0, v_world_pos, tex_scale_arr[0]);
	vec3 c1 = _mt_slot_sample(tex_a_1, v_world_pos, tex_scale_arr[1]);
	vec3 c2 = _mt_slot_sample(tex_a_2, v_world_pos, tex_scale_arr[2]);
	vec3 c3 = _mt_slot_sample(tex_a_3, v_world_pos, tex_scale_arr[3]);
	ALBEDO = (c0 * blend.r + c1 * blend.g + c2 * blend.b + c3 * blend.a) * _mt_tone(v_world_pos.xz);

	vec3 n0 = _mt_slot_sample(tex_n_0, v_world_pos, tex_scale_arr[0]);
	vec3 n1 = _mt_slot_sample(tex_n_1, v_world_pos, tex_scale_arr[1]);
	vec3 n2 = _mt_slot_sample(tex_n_2, v_world_pos, tex_scale_arr[2]);
	vec3 n3 = _mt_slot_sample(tex_n_3, v_world_pos, tex_scale_arr[3]);
	NORMAL_MAP = n0 * blend.r + n1 * blend.g + n2 * blend.b + n3 * blend.a;
	NORMAL_MAP_DEPTH = normal_strength_arr[0] * blend.r + normal_strength_arr[1] * blend.g + normal_strength_arr[2] * blend.b + normal_strength_arr[3] * blend.a;

	float r0 = _mt_slot_sample(tex_r_0, v_world_pos, tex_scale_arr[0]).r;
	float r1 = _mt_slot_sample(tex_r_1, v_world_pos, tex_scale_arr[1]).r;
	float r2 = _mt_slot_sample(tex_r_2, v_world_pos, tex_scale_arr[2]).r;
	float r3 = _mt_slot_sample(tex_r_3, v_world_pos, tex_scale_arr[3]).r;
	ROUGHNESS = clamp(r0 * roughness_mult_arr[0] * blend.r + r1 * roughness_mult_arr[1] * blend.g + r2 * roughness_mult_arr[2] * blend.b + r3 * roughness_mult_arr[3] * blend.a, 0.0, 1.0);

	float ao0 = _mt_slot_sample(tex_ao_0, v_world_pos, tex_scale_arr[0]).r;
	float ao1 = _mt_slot_sample(tex_ao_1, v_world_pos, tex_scale_arr[1]).r;
	float ao2 = _mt_slot_sample(tex_ao_2, v_world_pos, tex_scale_arr[2]).r;
	float ao3 = _mt_slot_sample(tex_ao_3, v_world_pos, tex_scale_arr[3]).r;
	float ao = ao0 * blend.r + ao1 * blend.g + ao2 * blend.b + ao3 * blend.a;
	float ao_str = ao_strength_arr[0] * blend.r + ao_strength_arr[1] * blend.g + ao_strength_arr[2] * blend.b + ao_strength_arr[3] * blend.a;
	AO = mix(1.0, ao, ao_str);
	// AO is an ambient/indirect occlusion term; letting it darken DIRECT light
	// double-shadows the terrain and reads as "muddy". 0.0 = Godot default
	// (AO affects ambient/GI only), which is the physically correct behaviour.
	AO_LIGHT_AFFECT = 0.0;
}
