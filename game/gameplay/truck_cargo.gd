class_name TruckCargo
extends Node

## Largage de cargo (ZL, ou E / ; au clavier) : enfant du camion. A chaque
## signal `cargo_requested`, si la recharge est finie, pose une CargoCrate au
## sol juste derriere la remorque (dans son axe, articulation comprise), a
## l'arret, dans la scene du camion. Recharge : cooldown_ticks (30 s), comptee
## en ticks physiques. Prete des le depart.

signal dropped(crate: CargoCrate)

@export var cooldown_ticks: int = 1800
## Ecart entre l'arriere de la remorque et la caisse.
@export var gap: float = 1.0

var _truck: Truck
var _cooldown: int = 0
var last_crate: CargoCrate


func _ready() -> void:
	_truck = get_parent() as Truck
	if _truck != null:
		_truck.cargo_requested.connect(_on_cargo_requested)


func _physics_process(_delta: float) -> void:
	if _cooldown > 0:
		_cooldown -= 1


func is_ready() -> bool:
	return _cooldown == 0


## 1 = pret, 0 = vient d'etre largue.
func get_charge() -> float:
	return 1.0 - float(_cooldown) / maxf(cooldown_ticks, 1)


func seconds_left() -> int:
	return ceili(_cooldown / 60.0)


func _on_cargo_requested() -> void:
	if _cooldown > 0 or _truck.is_upside_down():
		return
	drop()


## Pose la caisse derriere la remorque et lance la recharge.
func drop() -> CargoCrate:
	var angle := _truck.get_trailer_angle()
	var yaw := Basis(Vector3.UP, angle)
	var back := TruckSpec.TRAILER_CENTER.z + TruckSpec.TRAILER_SIZE.z / 2.0 - TruckSpec.KINGPIN.z \
			+ gap + CargoCrate.SIZE.z / 2.0
	var local := TruckSpec.KINGPIN + yaw * Vector3(0.0, 0.0, back)
	local.y = CargoCrate.SIZE.y / 2.0 + 0.05
	var crate := CargoCrate.new()
	crate.dropped_by = _truck
	crate.transform = _truck.global_transform * Transform3D(yaw, local)
	_truck.get_parent().add_child(crate)
	_cooldown = cooldown_ticks
	last_crate = crate
	dropped.emit(crate)
	return crate
