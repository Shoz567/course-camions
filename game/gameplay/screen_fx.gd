class_name ScreenFx
extends CompositorEffect

## Post-traitement d'une vue (2026-10-08, graphismes) : effet du compositeur
## pose sur la camera de chaque joueur (ChaseCamera), donc calcule vue par vue
## en ecran partage. Apres les transparents (la pluie et les particules sont
## dedans), avant le tonemapping :
##   - flou radial de vitesse : l'image file vers les bords depuis le point de
##     fuite, de plus en plus fort au-dela de BLUR_FROM_KMH, plus encore au
##     boost ; le centre (le camion) reste net ;
##   - aberration chromatique legere sur les bords, qui augmente avec le flou ;
##   - vignettage.
##   - brume de chaleur (`haze`, circuit de jour) : l'air ondule au-dessus de
##     la route juste sous l'horizon (temps reel : purement visuel).
## Deux passes de calcul : copie de l'image, puis effet qui lit la copie.
## Purement visuel ; jamais cree en headless (aucun RenderingDevice).

## Flou : nul sous BLUR_FROM_KMH, plein a BLUR_FULL_KMH ; part du boost.
const BLUR_FROM_KMH := 60.0
const BLUR_FULL_KMH := 170.0
const BLUR_SPEED := 0.75
const BLUR_BOOST := 0.35
## Aberration au repos, et ce que le flou y ajoute.
const ABERRATION := 0.0005
const ABERRATION_BLUR := 0.003
const VIGNETTE := 0.32
## Hauteur du point de fuite a l'ecran (camera de poursuite inclinee de
## 13 deg vers le bas : l'horizon est au-dessus du centre).
const VANISH_Y := 0.4

const _COPY := """#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D src;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D dst;
void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(src);
	if (px.x >= size.x || px.y >= size.y) return;
	imageStore(dst, px, imageLoad(src, px));
}
"""

const _EFFECT := """#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D src;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D dst;
layout(set = 0, binding = 2) uniform sampler2D depth;
layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 center;
	float blur;
	float aberration;
	float vignette;
	float haze;
	float time;
	float znear;
	float zfar;
	float pad;
} p;
const int TAPS = 10;
void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(p.size.x) || px.y >= int(p.size.y)) return;
	vec2 uv = (vec2(px) + 0.5) / p.size;
	// brume de chaleur : l'air ondule au-dessus de la route, juste sous l'horizon
	if (p.haze > 0.0) {
		// seulement au loin (profondeur inversee : 1 au plan proche, 0 au fond)
		float dz = textureLod(depth, uv, 0.0).r;
		float z = p.znear * p.zfar / (dz * (p.zfar - p.znear) + p.znear);
		float band = p.haze * smoothstep(45.0, 90.0, z)
				* (1.0 - smoothstep(0.0, 0.07, abs(uv.y - p.center.y - 0.035)));
		float wave = sin(uv.y * 820.0 + p.time * 5.0) + 0.6 * sin(uv.y * 350.0 - p.time * 3.1 + uv.x * 23.0);
		uv.x += wave * 0.0007 * band;
		uv.y += sin(uv.x * 140.0 + p.time * 2.3) * 0.0004 * band;
	}
	vec2 d = uv - p.center;
	float aspect = p.size.x / p.size.y;
	float r = length(d * vec2(aspect, 1.0));
	// le flou file depuis le point de fuite (center) et epargne le camion,
	// sous le centre de l'image : ellipse haute autour de (0.5, 0.62)
	vec2 k = (uv - vec2(0.5, 0.62)) * vec2(aspect, 0.75);
	float keep = smoothstep(0.2, 0.75, length(k));
	float m = p.blur * keep * 0.09;
	vec2 ca = d * p.aberration * keep * (0.5 + r);
	// decalage de depart par pixel (bruit entrelace) : pas de copies en escalier
	float jit = fract(52.9829189 * fract(dot(vec2(px), vec2(0.06711056, 0.00583715))));
	int taps = m > 0.0005 ? TAPS : 1;
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < taps; i++) {
		float t = taps > 1 ? (float(i) + jit) / float(taps) : 0.0;
		vec2 s = uv - d * m * t;
		float w = 1.0 - 0.6 * t;
		acc.r += textureLod(src, s + ca, 0.0).r * w;
		acc.g += textureLod(src, s, 0.0).g * w;
		acc.b += textureLod(src, s - ca, 0.0).b * w;
		wsum += w;
	}
	vec3 col = acc / wsum;
	float rv = length((uv - 0.5) * vec2(aspect, 1.0));
	col *= 1.0 - p.vignette * smoothstep(0.35, 1.05, rv);
	imageStore(dst, px, vec4(col, textureLod(src, uv, 0.0).a));
}
"""

## Brume de chaleur du circuit en cours (LocalRace : Playa del Sol), 0 .. 1.
static var haze: float = 0.0

## Reglages courants (ecrits par la camera, lus au rendu).
var blur: float = 0.0
var aberration: float = ABERRATION
var vignette: float = VIGNETTE

var _rd: RenderingDevice
var _copy_shader: RID
var _copy_pipeline: RID
var _fx_shader: RID
var _fx_pipeline: RID
var _sampler: RID
var _nearest: RID


## Flou pour cette vitesse (km/h, avant) et ce boost : 0 .. 1.
static func blur_for(speed_kmh: float, boosting: bool) -> float:
	var s := clampf((speed_kmh - BLUR_FROM_KMH) / (BLUR_FULL_KMH - BLUR_FROM_KMH), 0.0, 1.0)
	return clampf(s * s * BLUR_SPEED + (BLUR_BOOST if boosting else 0.0), 0.0, 1.0)


## Met a jour l'effet pour la vitesse et le boost du camion suivi.
func drive(speed_kmh: float, boosting: bool) -> void:
	blur = blur_for(speed_kmh, boosting)
	aberration = ABERRATION + ABERRATION_BLUR * blur


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		enabled = false
		return
	RenderingServer.call_on_render_thread(_build)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		for rid: RID in [_copy_shader, _fx_shader, _sampler, _nearest]:
			if rid.is_valid():
				_rd.free_rid(rid)


func _compile(code: String) -> RID:
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = code
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_warning("ScreenFx : %s" % spirv.compile_error_compute)
		return RID()
	return _rd.shader_create_from_spirv(spirv)


func _build() -> void:
	_copy_shader = _compile(_COPY)
	_fx_shader = _compile(_EFFECT)
	if not _copy_shader.is_valid() or not _fx_shader.is_valid():
		return
	_copy_pipeline = _rd.compute_pipeline_create(_copy_shader)
	_fx_pipeline = _rd.compute_pipeline_create(_fx_shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(ss)
	var sn := RDSamplerState.new()
	sn.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sn.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_nearest = _rd.sampler_create(sn)


func _image(binding: int, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(tex)
	return u


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or _rd == null \
			or not _fx_pipeline.is_valid():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	if not buffers.has_texture(&"screen_fx", &"copy"):
		buffers.create_texture(&"screen_fx", &"copy",
			RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
			RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT,
			RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, true, false)
	var proj := render_data.get_render_scene_data().get_cam_projection()
	var groups := Vector3i(ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	var push := PackedFloat32Array([size.x, size.y, 0.5, VANISH_Y, blur, aberration, vignette,
		haze, fmod(Time.get_ticks_msec() * 0.001, 600.0), proj.get_z_near(), proj.get_z_far(), 0.0])
	var push_bytes := push.to_byte_array()
	for view in buffers.get_view_count():
		var color := buffers.get_color_layer(view)
		var copy := buffers.get_texture_slice(&"screen_fx", &"copy", view, 0, 1, 1)
		var copy_set := UniformSetCacheRD.get_cache(_copy_shader, 0, [_image(0, color), _image(1, copy)])
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _copy_pipeline)
		_rd.compute_list_bind_uniform_set(list, copy_set, 0)
		_rd.compute_list_dispatch(list, groups.x, groups.y, groups.z)
		_rd.compute_list_end()
		var sampled := RDUniform.new()
		sampled.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		sampled.binding = 0
		sampled.add_id(_sampler)
		sampled.add_id(copy)
		var depth := RDUniform.new()
		depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		depth.binding = 2
		depth.add_id(_nearest)
		depth.add_id(buffers.get_depth_layer(view))
		var fx_set := UniformSetCacheRD.get_cache(_fx_shader, 0, [sampled, _image(1, color), depth])
		list = _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _fx_pipeline)
		_rd.compute_list_bind_uniform_set(list, fx_set, 0)
		_rd.compute_list_set_push_constant(list, push_bytes, push_bytes.size())
		_rd.compute_list_dispatch(list, groups.x, groups.y, groups.z)
		_rd.compute_list_end()
