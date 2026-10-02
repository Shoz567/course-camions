class_name TruckCargo
extends Node

## Pouvoir cargo (Triangle, ou E / ; au clavier) : enfant du camion. A chaque
## signal `cargo_requested`, si la recharge est finie, la remorque ENTIERE se
## detache : une DetachedTrailer la remplace sur la route, a sa place exacte
## (articulation comprise), et fait barrage pendant detach_ticks (60 s). Le
## tracteur roule seul, plus rapide et plus vif (bonus dans Truck). Au bout du
## temps, la remorque larguee disparait et la remorque se raccroche au
## tracteur (des que sa place est libre). Recharge globale : cooldown_ticks
## (30 s) depuis le largage. Comptee en ticks physiques. Prete des le depart.

signal dropped(trailer: DetachedTrailer)
signal reattached

@export var cooldown_ticks: int = 1800
## Duree du barrage : 60 s depuis le 2026-10-02 (10 s avant, demande de
## l'utilisateur). Plus longue que la recharge : on relargue des le
## raccrochage.
@export var detach_ticks: int = 3600
## Au-dela, la remorque se raccroche meme si sa place n'est pas libre.
@export var reattach_timeout_ticks: int = 120

var _truck: Truck
var _cooldown: int = 0
var _detached_left: int = 0
var _waiting: int = 0
var last_trailer: DetachedTrailer


func _ready() -> void:
	_truck = get_parent() as Truck
	if _truck != null:
		_truck.cargo_requested.connect(_on_cargo_requested)


func _physics_process(_delta: float) -> void:
	if _cooldown > 0:
		_cooldown -= 1
	if _truck == null or not _truck.is_trailer_detached():
		return
	if _detached_left > 0:
		_detached_left -= 1
		return
	# temps ecoule : la remorque larguee disparait, la remorque se raccroche
	if last_trailer != null and is_instance_valid(last_trailer) and not last_trailer.is_queued_for_deletion():
		last_trailer.queue_free()
	_waiting += 1
	if _truck.reattach_trailer(_waiting >= reattach_timeout_ticks):
		_waiting = 0
		reattached.emit()


func is_ready() -> bool:
	return _cooldown == 0 and _truck != null and not _truck.is_trailer_detached()


## 1 = pret, 0 = vient d'etre largue.
func get_charge() -> float:
	return 1.0 - float(_cooldown) / maxf(cooldown_ticks, 1)


func seconds_left() -> int:
	return ceili(_cooldown / 60.0)


## Secondes avant que la remorque se raccroche (0 = attachee).
func detached_seconds_left() -> int:
	return ceili(_detached_left / 60.0) if _truck != null and _truck.is_trailer_detached() else 0


## Etat pour le HUD.
func status_text() -> String:
	if _truck != null and _truck.is_trailer_detached():
		return "remorque larguee %d s" % maxi(detached_seconds_left(), 1)
	if _cooldown > 0:
		return "remorque %d s" % seconds_left()
	return "REMORQUE PRETE"


func _on_cargo_requested() -> void:
	if not is_ready() or _truck.is_upside_down():
		return
	drop()


## Detache la remorque, la pose sur la route et lance la recharge.
func drop() -> DetachedTrailer:
	var trailer := DetachedTrailer.new()
	trailer.dropped_by = _truck
	trailer.lifetime_ticks = detach_ticks
	var visual := _truck.get_node_or_null(^"Visual") as TruckVisual
	if visual != null:
		trailer.set_visual(visual.make_trailer_copy())
	trailer.transform = _truck.detach_trailer()
	_truck.get_parent().add_child(trailer)
	# elle roule encore un peu, puis tient la place (amortie)
	trailer.linear_velocity = _truck.linear_velocity * 0.5
	_cooldown = cooldown_ticks
	_detached_left = detach_ticks
	_waiting = 0
	last_trailer = trailer
	dropped.emit(trailer)
	return trailer
