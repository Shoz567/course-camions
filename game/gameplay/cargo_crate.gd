class_name CargoCrate
extends RigidBody3D

## Caisse de cargo larguee derriere une remorque (TruckCargo) : barriere
## ephemere. Obstacle physique solide (couche 5 `hazard`, VEHICLE_SPEC §7) :
## un camion adverse qui la percute est ralenti et deporte (Truck.cargo_hit),
## une fois par camion. Le camion qui l'a larguee la traverse.
## Regle anti-jeu : elle clignote puis disparait au bout de lifetime_ticks
## (5 s), quoi qu'il arrive. Duree comptee en ticks physiques (CLAUDE.md §7).

## Un camion adverse vient de percuter la caisse.
signal truck_hit(truck: Truck)

const SIZE := Vector3(3.0, 2.4, 3.0)
const HAZARD_LAYER := 5

@export var lifetime_ticks: int = 300
## Clignotement pendant les dernieres secondes, plus rapide a la fin.
@export var blink_from_ticks: int = 180
@export var crate_mass: float = 900.0

## Camion qui a largue la caisse : jamais penalise, ne la heurte pas.
var dropped_by: Truck
var age_ticks: int = 0
var _mesh: MeshInstance3D
var _hit: Dictionary = {}
## Materiau partage par toutes les caisses (compile une fois).
static var _shared_material: ShaderMaterial


func _init() -> void:
	name = "CargoCrate"
	mass = crate_mass
	collision_layer = 1 << (HAZARD_LAYER - 1)
	collision_mask = (1 << (TruckSpec.LAYER_WORLD - 1)) | (1 << (TruckSpec.LAYER_VEHICLE - 1))
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.1
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	cs.shape = box
	add_child(cs)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = SIZE
	bm.material = _material()
	_mesh.mesh = bm
	add_child(_mesh)


func _ready() -> void:
	mass = crate_mass
	if dropped_by != null:
		add_collision_exception_with(dropped_by)
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	age_ticks += 1
	if age_ticks >= lifetime_ticks:
		queue_free()
		return
	if age_ticks >= blink_from_ticks:
		var period := 4 if lifetime_ticks - age_ticks <= 60 else 8
		_mesh.visible = ((age_ticks - blink_from_ticks) / period) % 2 == 0


func is_blinking() -> bool:
	return age_ticks >= blink_from_ticks


func _on_body_entered(body: Node) -> void:
	var truck := body as Truck
	if truck == null or truck == dropped_by or _hit.has(truck):
		return
	_hit[truck] = true
	truck.cargo_hit(global_position)
	truck_hit.emit(truck)


## Caisse de danger : chevrons jaunes et noirs lumineux, aretes en neon
## (lisible de nuit, comme les plaques de la piste).
static func _material() -> ShaderMaterial:
	if _shared_material != null:
		return _shared_material
	var sh := Shader.new()
	sh.code = """shader_type spatial;
// Caisse de danger : chevrons jaunes et noirs lumineux qui pointent vers le
// haut sur chaque face, aretes en neon jaune (Cyber City, visible de nuit).
varying vec3 lp;
varying vec3 ln;
void vertex() { lp = VERTEX; ln = NORMAL; }
void fragment() {
	vec3 a = abs(lp) / vec3(1.5, 1.2, 1.5);
	float across = abs(ln.x) > 0.5 ? lp.z : lp.x;
	if (abs(ln.y) > 0.5) across = lp.x + lp.z;
	float chevron = step(0.5, fract((abs(across) * 0.9 - lp.y * 0.9) * 0.8));
	vec3 yellow = vec3(1.0, 0.8, 0.05);
	float edge = step(1.5, step(0.93, a.x) + step(0.93, a.y) + step(0.93, a.z));
	ALBEDO = mix(vec3(0.02), yellow, chevron);
	EMISSION = yellow * (chevron * 0.9 + edge * 3.5);
	ROUGHNESS = 0.55;
}
"""
	_shared_material = ShaderMaterial.new()
	_shared_material.shader = sh
	return _shared_material
