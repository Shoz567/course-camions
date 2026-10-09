shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Langue de feu (2026-10-08, particules) : billboard dresse (l'axe Y du
// monde reste vertical, la flamme monte), forme en goutte rongee par un
// bruit qui defile vers le haut, coeur presque blanc. Couleur HDR des
// particules (rampe : jaune -> orange -> rouge), fondue contre le decor.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float soft_m = 0.6;
// etirement vertical (1 : boule de feu ronde)
uniform float tall = 1.35;

varying float v_seed;
varying float v_age;

void vertex() {
	vec3 y = vec3(0.0, 1.0, 0.0);
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
	vec3 x = cross(y, to_cam);
	x = length(x) > 1e-5 ? normalize(x) : vec3(1.0, 0.0, 0.0);
	vec3 z = cross(x, y);
	float sc = length(MODEL_MATRIX[0].xyz);
	float tilt = (INSTANCE_CUSTOM.z - 0.5) * 0.5;
	vec3 xx = (x * cos(tilt) - y * sin(tilt)) * sc;
	vec3 yy = (x * sin(tilt) + y * cos(tilt)) * sc * tall;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(xx, 0.0), vec4(yy, 0.0), vec4(z * sc, 0.0), MODEL_MATRIX[3]);
	v_seed = INSTANCE_CUSTOM.z;
	v_age = INSTANCE_CUSTOM.y / max(INSTANCE_CUSTOM.w, 0.001);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	// goutte : large en bas (UV.y = 1), effilee en haut
	float taper = mix(1.9, 1.0, UV.y);
	float r = length(vec2(uv.x * taper, uv.y * 0.85 + 0.1));
	vec2 o = vec2(v_seed * 13.7, v_seed * 7.1);
	float n1 = texture(noise_tex, vec2(UV.x * 0.6, UV.y * 0.5 + TIME * 0.9) + o).r;
	float n2 = texture(noise_tex, vec2(UV.x * 1.4, UV.y * 1.2 + TIME * 1.7) + o * 2.0).r;
	float shape = 1.0 - smoothstep(0.15, 0.85, r + (n1 - 0.5) * 0.9 + (n2 - 0.5) * 0.35);
	float core = smoothstep(0.5, 0.95, shape) * (1.0 - v_age);
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vp.xyz /= vp.w;
	float soft = clamp((VERTEX.z - vp.z) / soft_m, 0.0, 1.0) * smoothstep(0.3, 1.5, -VERTEX.z);
	ALBEDO = (COLOR.rgb * shape + vec3(1.0, 0.85, 0.6) * core * 1.5) * COLOR.a * soft;
}
