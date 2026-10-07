class_name RainFx
extends GPUParticles3D

## Pluie de Cyber City (2026-10-07, realisme) : des gouttes etirees tombent
## autour de la camera `target` (un emetteur par vue), en coordonnees monde -
## la pluie ne suit pas la camera, la camera la traverse. Les impacts au sol
## sont l'affaire de la chaussee (anneaux dans les flaques, asphalt.
## gdshaderinc). Purement visuel ; rien en headless.

const AMOUNT := 6000
## Boite d'emission autour du point vise, devant la camera (m).
const EXTENTS := Vector3(32.0, 2.0, 32.0)
const AHEAD := 14.0
const HEIGHT := 16.0
const FALL_MS := 19.0

var target: Node3D


static func make(follow: Node3D) -> RainFx:
	var r := RainFx.new()
	r.name = "Rain"
	r.target = follow
	return r


func _ready() -> void:
	top_level = true
	amount = AMOUNT
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
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.55)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.62, 0.66, 0.78, 0.2)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	quad.material = mat
	draw_pass_1 = quad
	emitting = true


func _process(_delta: float) -> void:
	if not is_instance_valid(target):
		return
	var xf := target.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	global_position = xf.origin + fwd.normalized() * AHEAD + Vector3(0.0, HEIGHT, 0.0)
