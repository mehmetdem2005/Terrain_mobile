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

vec2 _mt_rotate_uv_around(vec2 uv, vec2 centre, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	vec2 d = uv - centre;
	return centre + vec2(c * d.x - s * d.y, s * d.x + c * d.y);
}

vec3 _mt_sample_var(sampler2D s, vec2 uv, float scale) {
	if (texture_variation < 0.001 && rotation_jitter < 0.001) {
		return texture(s, uv).rgb;
	}
	vec2 world_uv = uv / max(scale, 0.0001);
	vec2 cell = floor(world_uv / max(texture_cell_size, 0.5));
	float h1 = _mt_hash(cell);
	float h_rot = _mt_hash(cell + vec2(17.0, 31.0));

	vec2 sample_uv = uv;
	if (rotation_jitter > 0.001) {
		float angle = h_rot * 6.28318 * rotation_jitter;
		vec2 cell_centre_uv = (cell + 0.5) * texture_cell_size * scale;
		sample_uv = _mt_rotate_uv_around(sample_uv, cell_centre_uv, angle);
	}

	vec3 base = texture(s, sample_uv).rgb;
	if (texture_variation < 0.001) return base;

	vec2 offset = vec2(h1 * 17.3, fract(h1 * 31.7) * 23.1);
	vec3 alt = texture(s, sample_uv + offset).rgb;
	float h2 = _mt_hash(floor(world_uv / max(texture_cell_size * 1.7, 0.5)));
	float blend = smoothstep(0.3, 0.7, h2) * texture_variation;
	return mix(base, alt, blend);
}

vec3 _mt_triplanar(sampler2D s, vec3 wpos, float scale) {
	vec3 n = normalize(v_world_normal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);

	vec3 xz = _mt_sample_var(s, wpos.xz * scale, scale);
	vec3 xy = _mt_sample_var(s, wpos.xy * scale, scale);
	vec3 yz = _mt_sample_var(s, wpos.zy * scale, scale);
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
	ALBEDO = c0 * blend.r + c1 * blend.g + c2 * blend.b + c3 * blend.a;

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
	AO_LIGHT_AFFECT = 1.0;
}
