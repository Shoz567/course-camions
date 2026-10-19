class_name SakuraPetals
extends GPUParticles3D

## Petales de cerisier qui volent autour de la camera `target` (Sakura,
## 2026-10-19) : un nuage autour du point vise, devant la camera, en
## coordonnees monde (la camera le traverse) ; les petales tombent lentement,
## portes par le vent, tourbillonnent (turbulence) et tournoient sur
## eux-memes (sakura_petal.gdshader). Chaque vue ne voit que les siens
## (calques de RainFx). Purement visuel ; rien en headless.

const AMOUNT := 1000
## Boite d'emission autour du point vise, devant la camera (m).
const EXTENTS := Vector3(38.0, 9.0, 38.0)
const AHEAD := 16.0
const HEIGHT := 6.0
## Vent (m/s) : le nuage derive a travers la piste.
const WIND := Vector3(2.4, -0.9, 0.8)

const PETAL_SHADER := preload("res://tracks/materials/sakura_petal.gdshader")

var target: Node3D
var view: int = 0


static func make(follow: Node3D, view_index: int = 0) -> SakuraPetals:
	var p := SakuraPetals.new()
	p.name = "Petals"
	p.target = follow
	p.view = clampi(view_index, 0, RainFx.MAX_VIEWS - 1)
	return p


func _ready() -> void:
	top_level = true
	layers = RainFx.view_bit(view)
	amount = AMOUNT
	amount_ratio = FxKit.density()
	lifetime = 7.0
	preprocess = 7.0
	local_coords = false
	visibility_aabb = AABB(Vector3(-70.0, -40.0, -70.0), Vector3(140.0, 80.0, 140.0))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = EXTENTS
	pm.direction = WIND.normalized()
	pm.spread = 25.0
	pm.initial_velocity_min = WIND.length() * 0.6
	pm.initial_velocity_max = WIND.length() * 1.2
	pm.gravity = Vector3(0.0, -0.35, 0.0)
	pm.damping_min = 0.2
	pm.damping_max = 0.5
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.6
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_noise_speed = Vector3(0.3, 0.1, 0.2)
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.12
	pm.particle_flag_rotate_y = true
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -160.0
	pm.angular_velocity_max = 160.0
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	process_material = pm
	var mat := ShaderMaterial.new()
	mat.shader = PETAL_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.14)
	quad.material = mat
	draw_pass_1 = quad
	emitting = true
	_follow()


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	if not is_instance_valid(target):
		return
	var xf := target.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 1e-6:
		fwd = fwd.normalized()
	global_position = xf.origin + fwd * AHEAD + Vector3(0.0, HEIGHT, 0.0)
