class_name RainFx
extends GPUParticles3D

## Pluie de Cyber City (2026-10-07, realisme) : des gouttes etirees tombent
## autour de la camera `target` (un emetteur par vue), en coordonnees monde -
## la pluie ne suit pas la camera, la camera la traverse. Purement visuel ;
## rien en headless.
## 2026-10-08 (particules) : les gouttes (rain.gdshader) s'etirent le long de
## leur vitesse relative a la camera (a fond, elles foncent sur l'objectif)
## et s'allument dans les phares et sous les lampadaires ; des eclaboussures
## (RainSplash, rain_splash.gdshader) jaillissent de la route devant la
## camera. Chaque vue ne voit que SA pluie (calque VIEW_LAYER + indice de la
## vue) : pas de pluie doublee quand deux camions se suivent. Les anneaux
## dans les flaques restent l'affaire de la chaussee (asphalt.gdshaderinc).

const AMOUNT := 6000
const SPLASHES := 1600
## Boite d'emission autour du point vise, devant la camera (m).
const EXTENTS := Vector3(32.0, 2.0, 32.0)
const AHEAD := 14.0
const HEIGHT := 16.0
const FALL_MS := 19.0
## Eclaboussures : boite au sol devant la camera (m).
const SPLASH_EXTENTS := Vector3(13.0, 0.0, 13.0)
const SPLASH_AHEAD := 9.0
## Premier calque de rendu propre a une vue (vue i : VIEW_LAYER + i).
const VIEW_LAYER := 13
const MAX_VIEWS := 6

const RAIN_SHADER := preload("res://tracks/materials/rain.gdshader")
const SPLASH_SHADER := preload("res://tracks/materials/rain_splash.gdshader")

var target: Node3D
var view: int = 0
var _mat: ShaderMaterial
var _splash: GPUParticles3D
var _last := Vector3.ZERO
var _cam_v := Vector3.ZERO
var _ground := Vector3.ZERO
var _has_ground := false
var _query: PhysicsRayQueryParameters3D


static func make(follow: Node3D, view_index: int = 0) -> RainFx:
	var r := RainFx.new()
	r.name = "Rain"
	r.target = follow
	r.view = clampi(view_index, 0, MAX_VIEWS - 1)
	return r


## Calque de rendu de la vue `i`.
static func view_bit(i: int) -> int:
	return 1 << (VIEW_LAYER - 1 + i)


## Masque d'une camera de la vue `i` : elle ne voit pas les effets des
## autres vues.
static func cull_mask_for(mask: int, i: int) -> int:
	for k in MAX_VIEWS:
		if k != i:
			mask &= ~view_bit(k)
	return mask | view_bit(i)


func _ready() -> void:
	top_level = true
	layers = view_bit(view)
	amount = AMOUNT
	amount_ratio = FxKit.density()
	lifetime = 1.1
	preprocess = 1.1
	local_coords = false
	fixed_fps = 0
	visibility_aabb = AABB(Vector3(-60.0, -40.0, -60.0), Vector3(120.0, 80.0, 120.0))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = EXTENTS
	pm.direction = Vector3(0.08, -1.0, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = FALL_MS * 0.85
	pm.initial_velocity_max = FALL_MS * 1.1
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	process_material = pm
	_mat = ShaderMaterial.new()
	_mat.shader = RAIN_SHADER
	var quad := QuadMesh.new()
	quad.material = _mat
	draw_pass_1 = quad
	emitting = true
	_make_splashes()
	if is_instance_valid(target):
		_last = target.global_position


func _make_splashes() -> void:
	_splash = GPUParticles3D.new()
	_splash.name = "RainSplash"
	_splash.top_level = true
	_splash.layers = view_bit(view)
	_splash.amount = SPLASHES
	_splash.amount_ratio = FxKit.density()
	_splash.lifetime = 0.22
	_splash.local_coords = false
	_splash.fixed_fps = 0
	_splash.visibility_aabb = AABB(Vector3(-20.0, -4.0, -20.0), Vector3(40.0, 8.0, 40.0))
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = SPLASH_EXTENTS
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.anim_offset_max = 1.0
	pm.lifetime_randomness = 0.4
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	pm.scale_curve = FxKit.curve([[0.0, 0.5], [1.0, 1.0]])
	_splash.process_material = pm
	var mat := ShaderMaterial.new()
	mat.shader = SPLASH_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	# base de la couronne au ras du sol
	quad.center_offset = Vector3(0.0, 0.1, 0.0)
	quad.material = mat
	_splash.draw_pass_1 = quad
	_splash.emitting = false
	add_child(_splash)


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var xf := target.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	global_position = xf.origin + fwd * AHEAD + Vector3(0.0, HEIGHT, 0.0)
	# vitesse de la camera, lissee : le biais des gouttes
	if delta > 0.0:
		var v := (xf.origin - _last) / delta
		# une coupure de camera (reapparition) n'est pas une vitesse
		if v.length() < 120.0:
			_cam_v = _cam_v.lerp(v, minf(delta * 8.0, 1.0))
	_last = xf.origin
	_mat.set_shader_parameter(&"cam_velocity", _cam_v)
	if _has_ground:
		_splash.global_position = _ground
	if _splash.emitting != _has_ground:
		_splash.emitting = _has_ground


## Sol devant la camera (rayon vers le bas, depuis la hauteur de la camera :
## sous un pont, la route et pas le tablier) : la ou les gouttes eclatent.
func _physics_process(_delta: float) -> void:
	if not is_instance_valid(target):
		return
	var xf := target.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	var from := xf.origin + fwd.normalized() * SPLASH_AHEAD + Vector3.UP * 0.5
	if _query == null:
		_query = PhysicsRayQueryParameters3D.create(from, from, 1 << (TruckSpec.LAYER_WORLD - 1))
	_query.from = from
	_query.to = from + Vector3.DOWN * 30.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	_has_ground = not hit.is_empty()
	if _has_ground:
		_ground = hit["position"] as Vector3
