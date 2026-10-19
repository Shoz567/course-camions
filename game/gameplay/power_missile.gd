class_name PowerMissile
extends Node3D

## Missile du pouvoir MISSILE (tache 4.5.8) : part du toit du tireur a
## MISSILE_SPEED_MS, tourne vers sa cible d'au plus MISSILE_TURN_DEG par tick,
## et avance par segments testes contre le monde et les camions (jamais de
## traversee, meme a 70 m/s). Au contact d'un camion : MISSILE_DAMAGE PV,
## secousse (vitesse ajoutee proportionnelle a la masse) et explosion ; contre
## un mur : explosion seule ; au bout de MISSILE_LIFE_TICKS : explosion en
## l'air. Aucun tirage aleatoire.

## Camion touche (tests) ; null tant que rien ou contre un mur.
signal exploded(at: Vector3, victim: Truck)

var shooter: Truck
var target: Truck
var direction: Vector3 = Vector3.FORWARD
## Client en ligne : copie du missile du host, explosion sans degat ni
## poussee (le host les applique, les PV arrivent par le snapshot).
var mirror: bool = false
var _life: int = 0


## Tire depuis le toit de `from` vers `aim` (null : tout droit).
static func launch(from: Truck, aim: Truck, as_mirror: bool = false) -> PowerMissile:
	var m := PowerMissile.new()
	m.name = "Missile"
	m.mirror = as_mirror
	m.shooter = from
	m.target = aim
	m.direction = -from.global_basis.z
	var world := from.get_parent()
	world.add_child(m)
	m.global_position = from.global_transform * TruckPowers.MUZZLE
	return m


func _ready() -> void:
	_life = PowerCatalog.MISSILE_LIFE_TICKS
	if DisplayServer.get_name() == "headless":
		return
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.18
	cap.height = 1.2
	body.mesh = cap
	body.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	body.material_override = TruckPowers._glow(UiKit.GOLD, 3.0, 1.0)
	add_child(body)
	var flame := FxKit.make_fire(14, 0.25, 0.5)
	flame.position = Vector3(0.0, 0.0, 0.7)
	flame.emitting = true
	add_child(flame)


func _physics_process(delta: float) -> void:
	_life -= 1
	if target != null and is_instance_valid(target) and not target.is_wrecked():
		var want := (target.global_position + Vector3.UP * 1.5 - global_position).normalized()
		var angle := direction.angle_to(want)
		var turn := deg_to_rad(PowerCatalog.MISSILE_TURN_DEG)
		if angle > 1e-4:
			var axis := direction.cross(want).normalized()
			if axis.length_squared() > 0.5:
				direction = direction.rotated(axis, minf(angle, turn)).normalized()
	var step := direction * PowerCatalog.MISSILE_SPEED_MS * delta
	var exclude: Array[RID] = []
	if shooter != null and is_instance_valid(shooter):
		exclude.append(shooter.get_rid())
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step,
		(1 << (TruckSpec.LAYER_WORLD - 1)) | (1 << (TruckSpec.LAYER_VEHICLE - 1)), exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_explode(hit["position"], hit["collider"] as Truck)
		return
	global_position += step
	if direction.length_squared() > 0.5:
		look_at(global_position + direction, Vector3.UP)
	if _life <= 0:
		_explode(global_position, null)


func _explode(at: Vector3, victim: Truck) -> void:
	if victim != null and not mirror:
		var h := TruckHealth.of(victim)
		if h != null:
			h.damage(PowerCatalog.MISSILE_DAMAGE, &"missile")
		var flat := Vector3(direction.x, 0.0, direction.z).normalized()
		victim.apply_central_impulse((Vector3.UP * PowerCatalog.MISSILE_KICK_UP_MS
			+ flat * PowerCatalog.MISSILE_KICK_MS) * victim.mass)
	ExplosionFx.spawn(get_parent(), at, 4.0, true)
	exploded.emit(at, victim)
	queue_free()
