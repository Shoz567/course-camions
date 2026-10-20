class_name PowerBoomerang
extends Node3D

## Boomerang aimante (pouvoir, 2026-10-19) : part du toit du tireur a
## BOOMERANG_SPEED_MS tout droit pendant BOOMERANG_OUT_TICKS, fait demi-tour
## vers lui, puis le suit en tournant d'au plus BOOMERANG_TURN_DEG par tick ; il disparait
## en le rejoignant, ou au bout de BOOMERANG_LIFE_TICKS. Chaque camion a moins
## de BOOMERANG_RADIUS_M de lui (tete ou caisse de la remorque) est touche une
## fois a l'aller et une fois au retour : BOOMERANG_DAMAGE PV a la partie
## touchee, tole marquee (TruckPowers.strike) et un coup de cote. Il traverse les camions
## et passe au-dessus des murs (il vole). En miroir (client en ligne) : rien
## que l'image. Aucun tirage aleatoire.

signal struck(victim: Truck)

var shooter: Truck
var direction: Vector3 = Vector3.FORWARD
var mirror: bool = false
var returning: bool = false
var _age: int = 0
var _hit_out: Dictionary = {}
var _hit_back: Dictionary = {}
var _spin: Node3D


static func launch(from: Truck, as_mirror: bool = false) -> PowerBoomerang:
	var b := PowerBoomerang.new()
	b.name = "Boomerang"
	b.shooter = from
	b.mirror = as_mirror
	b.direction = -from.global_basis.z
	from.get_parent().add_child(b)
	b.global_position = from.global_transform * TruckPowers.MUZZLE
	return b


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_spin = Node3D.new()
	add_child(_spin)
	var model := TruckPowers._weapon(PowerCatalog.model(PowerCatalog.Id.BOOMERANG))
	if model != null:
		_spin.add_child(model)
	else:
		var blade := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.8, 0.12, 0.4)
		blade.mesh = box
		blade.material_override = TruckPowers._glow(UiKit.CYAN, 3.0, 1.0)
		_spin.add_child(blade)


func _physics_process(delta: float) -> void:
	_age += 1
	if _age >= PowerCatalog.BOOMERANG_LIFE_TICKS or shooter == null or not is_instance_valid(shooter):
		queue_free()
		return
	if _age >= PowerCatalog.BOOMERANG_OUT_TICKS and not returning:
		# demi-tour net vers le tireur : le retour repasse sur l'aller
		returning = true
		direction = (shooter.global_position + Vector3.UP * 2.5 - global_position).normalized()
	if returning:
		var home := shooter.global_position + Vector3.UP * 2.5 - global_position
		if home.length() < 2.5:
			queue_free()
			return
		var want := home.normalized()
		var angle := direction.angle_to(want)
		if angle > 1e-4:
			var axis := direction.cross(want).normalized()
			if axis.length_squared() > 0.5:
				direction = direction.rotated(axis, minf(angle, deg_to_rad(PowerCatalog.BOOMERANG_TURN_DEG))).normalized()
	global_position += direction * PowerCatalog.BOOMERANG_SPEED_MS * delta
	if _spin != null:
		_spin.rotate_y(0.5)
	_strike()


func _strike() -> void:
	var seen := _hit_back if returning else _hit_out
	for n in get_tree().get_nodes_in_group(TruckPowers.TARGETS):
		var t := n as Truck
		if t == null or t == shooter or t.is_wrecked() or seen.has(t):
			continue
		# la tete (autour du tracteur) ou la caisse de la remorque
		var reach := PowerCatalog.BOOMERANG_RADIUS_M
		var near_cab := (t.global_position + Vector3.UP * 1.5).distance_to(global_position) <= reach + 1.5
		if not near_cab and TruckPowers.trailer_distance(t, global_position) > reach:
			continue
		seen[t] = true
		struck.emit(t)
		var at := global_position
		if near_cab:
			at = t.global_position + Vector3.UP * 1.5
			at += (global_position - at).limit_length(TruckSpec.CHASSIS_SIZE.x / 2.0)
		TruckPowers.strike(t, at, direction, PowerCatalog.BOOMERANG_DAMAGE, &"boomerang",
			PowerCatalog.BOOMERANG_HIT_MS, mirror)
		if mirror:
			continue
		var side := direction.cross(Vector3.UP).normalized()
		t.apply_central_impulse(side * PowerCatalog.BOOMERANG_KICK_MS * t.mass)
