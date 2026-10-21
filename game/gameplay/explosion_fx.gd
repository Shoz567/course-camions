class_name ExplosionFx
extends Node3D

## Explosion ponctuelle (camion detruit, remorque larguee detruite, baril) :
##   - boule de feu : langues de flamme projetees en tous sens, freinees,
##     qui passent du blanc-jaune au rouge sombre (FxKit, additif HDR) ;
##   - fumee noire qui monte et s'etale, rougeoyante au debut ;
##   - braises : etincelles qui retombent et rebondissent sur la route ;
##   - souffle : anneau de poussiere qui court au ras du sol ;
##   - eclair de lumiere qui vacille et s'eteint ;
##   - le son d'explosion procedural des barils (aucun fichier audio).
## (2026-10-08, particules : remplace la sphere orange qui gonflait.)
## Se libere seule apres life_ticks (ticks physiques). Purement visuelle et
## sonore ; silencieuse en headless (le serveur audio factice ne libere
## jamais ses lectures).

@export var radius: float = 6.0
@export var life_ticks: int = 270
@export var with_sound: bool = true

var _ticks: int = 0
var _light: OmniLight3D
var _fire: GPUParticles3D
var _smoke: GPUParticles3D
var _embers: GPUParticles3D
var _dust: GPUParticles3D


## Pose une explosion a `at` (monde) sous `parent`.
static func spawn(parent: Node, at: Vector3, size: float = 6.0, sound: bool = true) -> ExplosionFx:
	var fx := ExplosionFx.new()
	fx.radius = size
	fx.with_sound = sound
	# pose avant l'entree dans l'arbre (ses emetteurs partent des _ready)
	var base := parent as Node3D
	fx.position = base.global_transform.affine_inverse() * at if base != null and base.is_inside_tree() else at
	parent.add_child(fx)
	# le souffle secoue les cameras proches (plus fort pour une grosse explosion)
	ChaseCamera.shake_near(parent.get_tree(), at, clampf(size / 10.0, 0.2, 1.0), size * 9.0)
	return fx


func _ready() -> void:
	name = "Explosion"
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.22)
	_light.light_energy = 0.0
	_light.omni_range = radius * 4.0
	add_child(_light)
	if DisplayServer.get_name() == "headless":
		return
	var r := radius
	var d := FxKit.density()
	# boule de feu
	_fire = FxKit.make_fire(roundi(60 * d), 1.2, 1.0)
	_fire.name = "Fireball"
	(_fire.draw_pass_1 as QuadMesh).material = FxKit.flame_material(1.0)
	var pm := _fire.process_material as ParticleProcessMaterial
	pm.emission_sphere_radius = r * 0.15
	pm.spread = 180.0
	pm.direction = Vector3.UP
	pm.initial_velocity_min = r * 0.6
	pm.initial_velocity_max = r * 1.4
	pm.inherit_velocity_ratio = 0.0
	pm.damping_min = r * 0.9
	pm.damping_max = r * 1.4
	pm.gravity = Vector3(0.0, 3.0, 0.0)
	pm.scale_min = r * 0.5
	pm.scale_max = r * 0.8
	pm.scale_curve = FxKit.curve([[0.0, 0.4], [0.15, 1.0], [1.0, 1.3]])
	pm.color_ramp = FxKit.ramp([[0.0, Color(7.0, 5.5, 3.2, 1.0)], [0.18, Color(5.0, 2.2, 0.5, 1.0)],
		[0.5, Color(1.6, 0.35, 0.06, 0.7)], [1.0, Color(0, 0, 0, 0)]], true)
	_fire.one_shot = true
	_fire.explosiveness = 0.92
	add_child(_fire)
	# fumee noire : part avec la boule, monte et s'etale
	_smoke = FxKit.make_smoke(roundi(30 * d), 4.0, 1.0, FxKit.smoke_material(Color(1.4, 0.5, 0.12), 0.18))
	_smoke.name = "Smoke"
	pm = _smoke.process_material as ParticleProcessMaterial
	pm.emission_sphere_radius = r * 0.2
	pm.spread = 180.0
	pm.initial_velocity_min = r * 0.4
	pm.initial_velocity_max = r * 0.9
	pm.inherit_velocity_ratio = 0.0
	pm.damping_min = r * 0.5
	pm.damping_max = r * 0.8
	pm.gravity = Vector3(0.0, 2.2, 0.0)
	pm.color = Color(0.09, 0.085, 0.08, 0.9)
	pm.scale_min = r * 0.45
	pm.scale_max = r * 0.75
	pm.scale_curve = FxKit.curve([[0.0, 0.4], [0.3, 0.9], [1.0, 1.6]])
	pm.color_ramp = FxKit.ramp([[0.0, Color(1, 1, 1, 0)], [0.06, Color(1, 1, 1, 1)],
		[0.45, Color(1, 1, 1, 0.75)], [1.0, Color(1, 1, 1, 0)]])
	_smoke.one_shot = true
	_smoke.explosiveness = 0.75
	add_child(_smoke)
	# braises
	_embers = FxKit.make_sparks(roundi(90 * d), 2.0, {
		"direction": Vector3.UP, "spread": 1.35, "speed_min": r * 0.8, "speed_max": r * 2.6,
		"inherit": 0.0, "box_extents": Vector3.ONE * r * 0.1, "gravity": 13.0, "drag": 0.35,
		"bounce": 0.3, "floor_below": 1.2, "life_min": 0.3, "stretch": 0.025, "max_len": 0.9,
		"width": 0.035, "streak_follow": 0.0, "heat": 7.0})
	_embers.name = "Embers"
	_embers.one_shot = true
	_embers.explosiveness = 0.95
	add_child(_embers)
	# souffle au ras du sol
	_dust = FxKit.make_smoke(roundi(28 * d), 1.8, 1.0)
	_dust.name = "Blast"
	pm = _dust.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = r * 0.25
	pm.emission_ring_inner_radius = r * 0.2
	pm.emission_ring_height = 0.2
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.radial_velocity_min = r * 2.2
	pm.radial_velocity_max = r * 3.2
	pm.damping_min = r * 2.5
	pm.damping_max = r * 3.5
	pm.gravity = Vector3(0.0, 0.6, 0.0)
	pm.inherit_velocity_ratio = 0.0
	pm.color = Color(0.5, 0.47, 0.42, 0.5)
	pm.scale_min = r * 0.3
	pm.scale_max = r * 0.45
	_dust.one_shot = true
	_dust.explosiveness = 1.0
	_dust.visible = false
	add_child(_dust)
	_fire.emitting = true
	_smoke.emitting = true
	_embers.emitting = true
	# le sol sous l'explosion : apres le pas physique (on peut naitre d'un
	# choc, pendant que l'espace physique est verrouille)
	_find_ground.call_deferred()
	if with_sound:
		var sound := AudioStreamPlayer3D.new()
		sound.stream = ExplosiveBarrel._build_explosion_stream()
		sound.unit_size = 30.0
		sound.max_distance = 220.0
		sound.bus = SoundMix.EFFECTS
		add_child(sound)
		sound.play()


## Sol sous l'explosion : les braises y rebondissent, le souffle y court.
func _find_ground() -> void:
	if not is_inside_tree():
		return
	var from := global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0, 1 << (TruckSpec.LAYER_WORLD - 1))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var below := 1.2
	if not hit.is_empty():
		below = maxf(global_position.y - (hit["position"] as Vector3).y, 0.0)
	FxKit.spark_param(_embers, &"floor_below", below)
	if below < radius * 0.8:
		_dust.position = Vector3(0.0, -below + 0.3, 0.0)
		_dust.visible = true
		_dust.emitting = true


func _physics_process(_delta: float) -> void:
	_ticks += 1
	# eclair : plein en 2 ticks, puis s'eteint en vacillant
	var u := float(_ticks) / 50.0
	var flash := minf(float(_ticks) / 2.0, 1.0) * maxf(1.0 - u, 0.0)
	_light.light_energy = 12.0 * flash * flash * (0.85 + 0.15 * sin(float(_ticks) * 1.7))
	if _ticks >= life_ticks:
		queue_free()
