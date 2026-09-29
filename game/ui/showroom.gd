class_name Showroom
extends Node3D

## Decor du menu principal : un showroom sur le toit d'une tour de Cyber City.
## Plateau tournant (les camions choisis y sont exposes, alignes), anneaux
## neon, projecteurs (cle blanche, contres magenta et cyan), faisceaux qui
## montent du toit et balaient le ciel, et la ville illuminee en contrebas
## jusqu'a l'horizon. Purement visuel, sauf le dessus du plateau (couche 1
## `world`) : les rayons de suspension des camions s'y posent.

const PLATE_RADIUS := 20.0
const PLATE_TOP := 0.5
## Ecart lateral entre deux camions exposes.
const SLOT_SPACING := 7.2
## Centre de l'ensemble semi-remorque (le tracteur est a l'avant, en -Z).
const RIG_CENTER_Z := 5.3

@export var turn_speed: float = 0.12        # rad/s
@export var city_seed: int = 11

## Tourne avec les camions (les camions en sont enfants).
var turntable: Node3D
## Point vise par la camera.
var focus: Vector3 = Vector3(0.0, 3.0, 0.0)
var _beams: Array[Node3D] = []
var _time: float = 0.0


func _ready() -> void:
	_build_roof()
	_build_turntable()
	_build_lights()
	_build_beams()
	if DisplayServer.get_name() != "headless" or CityBackdrop.generate_in_headless:
		var cb := CityBuilder.new(city_seed)
		cb.add_ring(Vector3(0.0, -140.0, 0.0), 110.0, 950.0, 260, 60.0, 250.0)
		add_child(cb.build())


func _process(delta: float) -> void:
	_time += delta
	turntable.rotate_y(turn_speed * delta)
	# faisceaux : balayage lent, dephase
	for k in _beams.size():
		var b := _beams[k]
		b.rotation = Vector3(deg_to_rad(14.0 + 8.0 * sin(_time * 0.35 + k)), b.rotation.y,
			deg_to_rad(10.0 * sin(_time * 0.27 + k * 1.7)))


## Pose du camion `i` quand `n` camions sont exposes : alignes cote a cote,
## centres sur le plateau (repere du plateau tournant).
static func slot(i: int, n: int) -> Transform3D:
	var x := (i - (n - 1) / 2.0) * SLOT_SPACING
	return Transform3D(Basis.IDENTITY, Vector3(x, PLATE_TOP, -RIG_CENTER_Z))


func _build_roof() -> void:
	# toit de la tour : grande dalle, bord lumineux, facades qui plongent
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = preload("res://ui/showroom_floor.gdshader")
	var roof := _box(self, Vector3(150.0, 2.0, 150.0), Vector3(0.0, -1.0, 0.0), floor_mat)
	roof.name = "Roof"
	var tower_mat := StandardMaterial3D.new()
	tower_mat.albedo_color = Color(0.03, 0.035, 0.05)
	tower_mat.metallic = 0.5
	tower_mat.roughness = 0.4
	_box(self, Vector3(146.0, 140.0, 146.0), Vector3(0.0, -72.0, 0.0), tower_mat)
	var edge := preload("res://tracks/materials/neon_cyan.tres")
	for k in 4:
		var along := Vector3(150.0, 0.25, 0.25) if k < 2 else Vector3(0.25, 0.25, 150.0)
		var pos := Vector3(0.0, 0.1, 75.0 * (1 if k == 0 else -1)) if k < 2 \
				else Vector3(75.0 * (1 if k == 2 else -1), 0.1, 0.0)
		_box(self, along, pos, edge)
	# sol de la ville, loin en contrebas
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000.0, 4000.0)
	ground.mesh = pm
	ground.material_override = preload("res://tracks/materials/grass.tres")
	ground.position = Vector3(0.0, -140.0, 0.0)
	add_child(ground)


func _build_turntable() -> void:
	turntable = Node3D.new()
	turntable.name = "Turntable"
	# tourne dans _process : pas d'interpolation physique (ni pour les camions)
	turntable.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(turntable)
	var plate := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = PLATE_RADIUS
	cyl.bottom_radius = PLATE_RADIUS
	cyl.height = PLATE_TOP
	cyl.radial_segments = 96
	plate.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.045, 0.06)
	mat.metallic = 0.85
	mat.roughness = 0.18
	plate.material_override = mat
	plate.position = Vector3(0.0, PLATE_TOP / 2.0, 0.0)
	turntable.add_child(plate)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = PLATE_RADIUS - 0.25
	torus.outer_radius = PLATE_RADIUS + 0.25
	torus.rings = 96
	ring.mesh = torus
	ring.material_override = preload("res://tracks/materials/neon_magenta.tres")
	ring.position = Vector3(0.0, PLATE_TOP, 0.0)
	turntable.add_child(ring)
	# dessus du plateau : fixe (un disque qui tourne sur son axe ne change pas
	# de forme), sur la couche 1 pour les rayons de suspension
	var body := StaticBody3D.new()
	body.name = "PlateCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = PLATE_RADIUS
	shape.height = PLATE_TOP
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(0.0, PLATE_TOP / 2.0, 0.0)
	add_child(body)


func _build_lights() -> void:
	_spot("KeyLight", Vector3(6.0, 32.0, 30.0), Color(0.85, 0.9, 1.0), 7.0, true)
	_spot("RimMagenta", Vector3(-32.0, 16.0, -24.0), Color(1.0, 0.2, 0.8), 6.0, false)
	_spot("RimCyan", Vector3(32.0, 16.0, -24.0), Color(0.1, 0.9, 1.0), 6.0, false)


func _spot(light_name: String, pos: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var l := SpotLight3D.new()
	l.name = light_name
	l.light_color = color
	l.light_energy = energy
	l.spot_range = 90.0
	l.spot_angle = 34.0
	l.shadow_enabled = shadows
	add_child(l)
	l.look_at_from_position(pos, focus, Vector3.UP)


## Projecteurs au sol autour du plateau, et leurs faisceaux vers le ciel.
func _build_beams() -> void:
	var colors := [Color(0.1, 0.9, 1.0), Color(1.0, 0.15, 0.8), Color(0.55, 0.3, 1.0)]
	for k in 6:
		var a := TAU * k / 6.0 + 0.3
		var base := Vector3(cos(a), 0.0, sin(a)) * 32.0
		var col: Color = colors[k % 3]
		var lamp := StandardMaterial3D.new()
		lamp.albedo_color = col
		lamp.emission_enabled = true
		lamp.emission = col
		lamp.emission_energy_multiplier = 5.0
		_box(self, Vector3(1.6, 0.7, 1.6), base + Vector3(0.0, 0.35, 0.0), lamp)
		var pivot := Node3D.new()
		pivot.position = base + Vector3(0.0, 0.7, 0.0)
		pivot.rotation.y = -a + PI / 2.0
		add_child(pivot)
		var beam := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 5.0
		cone.bottom_radius = 0.5
		cone.height = 70.0
		cone.cap_top = false
		cone.cap_bottom = false
		cone.radial_segments = 24
		beam.mesh = cone
		var bm := ShaderMaterial.new()
		bm.shader = preload("res://ui/light_beam.gdshader")
		bm.set_shader_parameter("color", col)
		beam.material_override = bm
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3(0.0, 35.0, 0.0)
		pivot.add_child(beam)
		_beams.append(pivot)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
