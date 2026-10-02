class_name ExplosionFx
extends Node3D

## Explosion ponctuelle (camion detruit, remorque larguee detruite) : boule de
## feu qui gonfle et s'efface, eclair de lumiere, et le son d'explosion
## procedural des barils (aucun fichier audio). Se libere seule apres
## life_ticks (ticks physiques). Purement visuelle et sonore ; silencieuse en
## headless (le serveur audio factice ne libere jamais ses lectures).

@export var radius: float = 6.0
@export var life_ticks: int = 40

var _ticks: int = 0
var _ball: MeshInstance3D
var _mat: StandardMaterial3D
var _light: OmniLight3D


## Pose une explosion a `at` (monde) sous `parent`.
static func spawn(parent: Node, at: Vector3, size: float = 6.0) -> ExplosionFx:
	var fx := ExplosionFx.new()
	fx.radius = size
	parent.add_child(fx)
	fx.global_position = at
	return fx


func _ready() -> void:
	name = "Explosion"
	_ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 20
	sphere.rings = 10
	_ball.mesh = sphere
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(1.0, 0.55, 0.12, 0.9)
	_ball.material_override = _mat
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ball.scale = Vector3.ONE * radius * 0.2
	add_child(_ball)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.22)
	_light.light_energy = 8.0
	_light.omni_range = radius * 4.0
	add_child(_light)
	if DisplayServer.get_name() != "headless":
		var sound := AudioStreamPlayer3D.new()
		sound.stream = ExplosiveBarrel._build_explosion_stream()
		sound.unit_size = 30.0
		sound.max_distance = 220.0
		add_child(sound)
		sound.play()


func _physics_process(_delta: float) -> void:
	_ticks += 1
	var u := clampf(float(_ticks) / (life_ticks * 0.6), 0.0, 1.0)
	_ball.scale = Vector3.ONE * radius * lerpf(0.2, 1.0, sqrt(u))
	_mat.albedo_color = Color(1.0, lerpf(0.6, 0.25, u), 0.1, (1.0 - u) * 0.9)
	_light.light_energy = lerpf(8.0, 0.0, u)
	if _ticks >= life_ticks:
		queue_free()
