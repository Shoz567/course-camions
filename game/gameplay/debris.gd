class_name Debris
extends RigidBody3D

## Debris d'un choc ou d'une explosion (2026-10-06 : « que des bouts
## partent ») : une piece arrachee au camion (retro, phare, pare-chocs...) ou
## un eclat de tole. Petit corps physique qui rebondit sur la piste et les
## murs, ne touche jamais un camion (aucune couche : les camions ne le voient
## pas, il ne voit que le decor), puis s'efface au bout de life_ticks.
## Au plus MAX_ALIVE debris dans la partie : au-dela, le plus ancien s'en va.
## Durees en ticks physiques (CLAUDE.md §7).
## Les eclats sont des plaques de tole froissee, pliees et dechiquetees
## (FxKit.shard_mesh), plus des boites (2026-10-08, particules) ; une piece
## soufflee par une explosion peut trainer de la fumee, voire bruler
## (add_trail), pendant TRAIL_TICKS.

const MAX_ALIVE := 90
const FADE_TICKS := 30
const TRAIL_TICKS := 150

static var _alive: Array[Debris] = []

@export var life_ticks: int = 540

var _age: int = 0
var _mesh: Node3D
var _trail: GPUParticles3D
var _flame: GPUParticles3D
var _scale0: Vector3 = Vector3.ONE


## Piece arrachee : copie de `part` (meme maillage, meme materiaux), a sa place
## exacte, lancee a `velocity` (monde) avec une rotation aleatoire.
static func from_part(world: Node, part: MeshInstance3D, velocity: Vector3) -> Debris:
	var aabb := part.get_aabb()
	var xf := part.global_transform
	var scale := xf.basis.get_scale().abs()
	var d := Debris.new()
	var copy := MeshInstance3D.new()
	copy.mesh = part.mesh
	for s in part.get_surface_override_material_count():
		copy.set_surface_override_material(s, part.get_surface_override_material(s))
	copy.material_override = part.material_override
	copy.layers = part.layers
	# le corps a son origine au centre de la piece, sans echelle (Jolt)
	var center := xf * aabb.get_center()
	var body_xf := Transform3D(Basis(xf.basis.get_rotation_quaternion()), center)
	copy.transform = body_xf.affine_inverse() * xf
	d._mesh = copy
	d.add_child(copy)
	var size := (aabb.size * scale).clamp(Vector3.ONE * 0.08, Vector3.ONE * 4.0)
	d._setup(size, clampf(size.x * size.y * size.z * 250.0, 4.0, 120.0))
	d._spawn(world, body_xf, velocity)
	return d


## Eclat de tole (plaque `size`, materiau de la carrosserie touchee).
static func shard(world: Node, at: Vector3, size: Vector3, material: Material, velocity: Vector3) -> Debris:
	var d := Debris.new()
	var mi := MeshInstance3D.new()
	# plaque froissee unitaire : largeur x, profondeur z ; son epaisseur et
	# ses plis suivent la taille de l'eclat
	mi.mesh = FxKit.shard_mesh(roundi(absf(at.x * 7.1 + at.z * 3.3 + at.y * 5.3) * 10.0))
	mi.scale = Vector3(size.x, (size.x + size.z) * 0.5, size.z)
	if material != null:
		mi.material_override = material
	mi.layers |= DamageFx.LAYER_BIT
	d._mesh = mi
	d.add_child(mi)
	d._setup(size, clampf(size.x * size.y * size.z * 7800.0, 2.0, 60.0))
	var h := absf(sin(at.x * 12.9898 + at.z * 78.233)) * TAU
	d._spawn(world, Transform3D(Basis(Vector3(cos(h), 0.4, sin(h)).normalized(), h), at), velocity)
	return d


func _setup(size: Vector3, kg: float) -> void:
	name = "Debris"
	mass = kg
	collision_layer = 0
	collision_mask = 1 << (TruckSpec.LAYER_WORLD - 1)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.25
	physics_material_override = pm
	angular_damp = 0.4
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size.max(Vector3.ONE * 0.06)
	cs.shape = shape
	add_child(cs)


func _spawn(world: Node, xf: Transform3D, velocity: Vector3) -> void:
	world.add_child(self)
	global_transform = xf
	linear_velocity = velocity
	var h := absf(sin(xf.origin.x * 3.1 + xf.origin.z * 5.7))
	angular_velocity = Vector3(h - 0.5, 0.7 - h, h * 0.8 - 0.3) * 14.0
	_alive.append(self)
	while _alive.size() > MAX_ALIVE:
		var old: Debris = _alive.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _ready() -> void:
	if _mesh != null:
		_scale0 = _mesh.scale


## Trainee de fumee sombre derriere la piece (et des flammes si `burning`)
## pendant TRAIL_TICKS. Rien en headless (purement visuel).
func add_trail(burning: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# serree (une bouffee tous les ~25 cm a 15 m/s) et deja large au depart :
	# un ruban continu, pas un pointille
	_trail = FxKit.make_smoke(110, 1.5, 1.1)
	var nk := 1.8 if TruckLights.night else 1.0
	FxKit.set_smoke_look(_trail, Color(0.12 * nk, 0.11 * nk, 0.1 * nk, 0.7), 1.0, 0.7, 1.2)
	var pm := _trail.process_material as ParticleProcessMaterial
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.0
	pm.inherit_velocity_ratio = 0.05
	pm.emission_sphere_radius = 0.15
	pm.scale_curve = FxKit.curve([[0.0, 0.6], [0.4, 0.95], [1.0, 1.5]])
	add_child(_trail)
	if burning:
		_flame = FxKit.make_fire(24, 0.35, 0.7)
		_flame.amount_ratio = FxKit.density()
		_flame.emitting = true
		add_child(_flame)


func _physics_process(_delta: float) -> void:
	_age += 1
	if _age == TRAIL_TICKS and _trail != null:
		_trail.emitting = false
		if _flame != null:
			_flame.emitting = false
	var left := life_ticks - _age
	if left < FADE_TICKS and _mesh != null:
		_mesh.scale = _scale0 * maxf(float(left) / FADE_TICKS, 0.01)
	if left <= 0:
		queue_free()


func _exit_tree() -> void:
	_alive.erase(self)


## Debris encore en jeu (tests).
static func alive_count() -> int:
	var n := 0
	for d in _alive:
		if is_instance_valid(d):
			n += 1
	return n
