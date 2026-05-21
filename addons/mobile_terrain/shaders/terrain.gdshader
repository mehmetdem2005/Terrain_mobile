shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// V21: Full PBR slot system. Each of the 4 splatmap channels controls
// a complete texture bundle: albedo + normal + roughness + AO. All four
// blend by the same splatmap weight so they stay visually coherent.

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

uniform float tex_scale = 1.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_multiplier : hint_range(0.0, 2.0) = 1.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform float texture_variation : hint_range(0.0, 1.0) = 0.0;
uniform float texture_cell_size : hint_range(1.0, 50.0) = 10.0;
uniform float rotation_jitter : hint_range(0.0, 1.0) = 0.0;
uniform float triplanar_blend : hint_range(0.0, 1.0) = 0.0;
// V23 (TKT-002 C6): allow the plugin to force planar-only sampling on
// Forward Mobile / low-end devices. Triplanar takes 3x texture reads per
// albedo+normal slot; with 4 slots that's 24 samples/fragment, blowing
// past mid-tier mobile GPU texture-unit budgets (Adreno 650/Mali-G68).
// The plugin sets mobile_quality=true on Forward Mobile renderers.
uniform bool mobile_quality = false;

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

vec3 _mt_sample_var(sampler2D s, vec2 uv) {
	if (texture_variation < 0.001 && rotation_jitter < 0.001) {
		return texture(s, uv).rgb;
	}
	vec2 world_uv = uv / max(tex_scale, 0.0001);
	vec2 cell = floor(world_uv / max(texture_cell_size, 0.5));
	float h1 = _mt_hash(cell);
	float h_rot = _mt_hash(cell + vec2(17.0, 31.0));

	vec2 sample_uv = uv;
	if (rotation_jitter > 0.001) {
		float angle = h_rot * 6.28318 * rotation_jitter;
		vec2 cell_centre_uv = (cell + 0.5) * texture_cell_size * tex_scale;
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

vec3 _mt_triplanar(sampler2D s, vec3 wpos) {
	vec3 n = normalize(v_world_normal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);

	vec3 xz = _mt_sample_var(s, wpos.xz * tex_scale);
	vec3 xy = _mt_sample_var(s, wpos.xy * tex_scale);
	vec3 yz = _mt_sample_var(s, wpos.zy * tex_scale);
	return xz * w.y + yz * w.x + xy * w.z;
}

vec3 _mt_albedo_sample(sampler2D s, vec3 wpos) {
	vec3 xz = _mt_sample_var(s, wpos.xz * tex_scale);
	// V23 (TKT-002 C6): bypass triplanar on mobile_quality. Saves up to
	// 18 texture reads/fragment with 4 active slots, keeps the plugin
	// runnable on Forward Mobile without breaking desktop visuals.
	if (mobile_quality || triplanar_blend < 0.001) return xz;
	vec3 tri = _mt_triplanar(s, wpos);
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

	vec2 uv = v_world_pos.xz * tex_scale;

	vec3 c0 = _mt_albedo_sample(tex_a_0, v_world_pos);
	vec3 c1 = _mt_albedo_sample(tex_a_1, v_world_pos);
	vec3 c2 = _mt_albedo_sample(tex_a_2, v_world_pos);
	vec3 c3 = _mt_albedo_sample(tex_a_3, v_world_pos);
	ALBEDO = c0 * blend.r + c1 * blend.g + c2 * blend.b + c3 * blend.a;

	vec3 n0 = _mt_albedo_sample(tex_n_0, v_world_pos);
	vec3 n1 = _mt_albedo_sample(tex_n_1, v_world_pos);
	vec3 n2 = _mt_albedo_sample(tex_n_2, v_world_pos);
	vec3 n3 = _mt_albedo_sample(tex_n_3, v_world_pos);
	NORMAL_MAP = n0 * blend.r + n1 * blend.g + n2 * blend.b + n3 * blend.a;
	NORMAL_MAP_DEPTH = normal_strength;

	float r0 = texture(tex_r_0, uv).r;
	float r1 = texture(tex_r_1, uv).r;
	float r2 = texture(tex_r_2, uv).r;
	float r3 = texture(tex_r_3, uv).r;
	ROUGHNESS = clamp((r0 * blend.r + r1 * blend.g + r2 * blend.b + r3 * blend.a) * roughness_multiplier, 0.0, 1.0);

	float ao0 = texture(tex_ao_0, uv).r;
	float ao1 = texture(tex_ao_1, uv).r;
	float ao2 = texture(tex_ao_2, uv).r;
	float ao3 = texture(tex_ao_3, uv).r;
	float ao = ao0 * blend.r + ao1 * blend.g + ao2 * blend.b + ao3 * blend.a;
	AO = mix(1.0, ao, ao_strength);
	AO_LIGHT_AFFECT = 1.0;
}
