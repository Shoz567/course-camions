class_name SandFx
extends Node3D

## Vent de sable de Playa del Sol (2026-10-08, meteo) : autour du camion
## `target` de chaque vue (un emetteur par joueur), devant lui et a hauteur de
## la route, en coordonnees monde : des grains de sable filent au ras de la
## piste dans le sens du vent, et de grands voiles de poussiere tres pales
## passent plus lentement. Purement visuel ; rien en
## headless (la course ne le cree pas).

const WIND := Vector3(1.0, 0.04, 0.35)
## Boite d'emission autour du point vise, devant le camion (m).
const EXTENTS := Vector3(34.0, 0.9, 34.0)
const AHEAD := 16.0
const GRAINS := 1100
const VEILS := 60

var target: Node3D


static func make(follow: Node3D) -> SandFx:
	var s := SandFx.new()
	s.name = "Sand"
	s.target = follow
	return s


func _ready() -> void:
	top_level = true
	add_child(_grains())
	add_child(_veils())


static func _base(amount: int, lifetime: float, height: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-70.0, -20.0, -70.0), Vector3(140.0, 40.0, 140.0))
	p.position = Vector3(0.0, height, 0.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = EXTENTS
	pm.direction = WIND.normalized()
	pm.gravity = Vector3.ZERO
	p.process_material = pm
	return p


## Grains : traits fins et clairs, rapides, au ras du sol.
func _grains() -> GPUParticles3D:
	var p := _base(GRAINS, 1.6, 0.25)
	p.name = "Grains"
	var pm := p.process_material as ParticleProcessMaterial
	# au ras du sol : une fine couche, pas un nuage
	pm.emission_box_extents = Vector3(EXTENTS.x, 0.25, EXTENTS.z)
	pm.spread = 8.0
	pm.initial_velocity_min = 9.0
	pm.initial_velocity_max = 15.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 6.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.03)
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.95, 0.86, 0.68, 0.38)
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.disable_receive_shadows = true
	quad.material = mat
	p.draw_pass_1 = quad
	return p


## Voiles : grandes nappes de poussiere tres pales, lentes.
func _veils() -> GPUParticles3D:
	var p := _base(VEILS, 5.0, 1.4)
	p.name = "Veils"
	var pm := p.process_material as ParticleProcessMaterial
	pm.spread = 12.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 7.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var quad := QuadMesh.new()
	quad.size = Vector2(12.0, 3.2)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.92, 0.82, 0.64, 0.2)
	mat.albedo_texture = tex
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.roughness = 1.0
	mat.disable_receive_shadows = true
	quad.material = mat
	p.draw_pass_1 = quad
	return p


func _process(_delta: float) -> void:
	if not is_instance_valid(target):
		return
	var xf := target.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	global_position = xf.origin + fwd.normalized() * AHEAD
