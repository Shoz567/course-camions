class_name TruckCargo
extends Node

## Pouvoir cargo (Triangle, ou E / ; au clavier) : enfant du camion. A chaque
## signal `cargo_requested`, si la remorque est prete, elle se detache
## ENTIERE : une DetachedTrailer la remplace sur la route, a sa place exacte
## (articulation comprise), et y reste (2026-10-02 : persistante, 50 PV). Le
## tracteur roule seul, plus rapide et plus vif (bonus dans Truck), pendant la
## recharge (cooldown_ticks, 30 s) ; ensuite une NOUVELLE remorque apparait
## sur le camion (des que sa place est libre, forcee au bout de
## reattach_timeout_ticks), et le joueur peut de nouveau larguer.
## Verrou de depart : pendant first_seconds_lock_ticks (5 s) apres le GO
## (start_race_lock, appele par la course), largage interdit - pas de bouchon
## monstre sur la grille. Comptes en ticks physiques. Prete des le depart.

signal dropped(trailer: DetachedTrailer)
## Une nouvelle remorque vient d'apparaitre sur le camion.
signal reattached

## Recharge apres un largage, puis nouvelle remorque.
@export var cooldown_ticks: int = 1800
## Verrou des premieres secondes de course.
@export var first_seconds_lock_ticks: int = 300
## Au-dela, la nouvelle remorque apparait meme si sa place n'est pas libre
## (caisse sans collision tant que la place est prise : Truck._trailer_ghost).
@export var reattach_timeout_ticks: int = 120

var _truck: Truck
var _cooldown: int = 0
var _lock: int = 0
var _waiting: int = 0
var last_trailer: DetachedTrailer


func _ready() -> void:
	_truck = get_parent() as Truck
	if _truck != null:
		_truck.cargo_requested.connect(_on_cargo_requested)


## Depart de la course : largage interdit pendant first_seconds_lock_ticks.
func start_race_lock() -> void:
	_lock = first_seconds_lock_ticks


func _physics_process(_delta: float) -> void:
	if _lock > 0:
		_lock -= 1
	if _cooldown > 0:
		_cooldown -= 1
	if _truck == null or not _truck.is_trailer_detached() or _cooldown > 0:
		return
	# recharge finie : une nouvelle remorque apparait (l'ancienne reste)
	_waiting += 1
	if _truck.reattach_trailer(_waiting >= reattach_timeout_ticks):
		_waiting = 0
		reattached.emit()


func is_ready() -> bool:
	return _cooldown == 0 and _lock == 0 and _truck != null and not _truck.is_trailer_detached()


func is_locked() -> bool:
	return _lock > 0


## 1 = pret, 0 = vient d'etre largue (ou verrouille).
func get_charge() -> float:
	if _lock > 0:
		return 1.0 - float(_lock) / maxf(first_seconds_lock_ticks, 1)
	return 1.0 - float(_cooldown) / maxf(cooldown_ticks, 1)


func seconds_left() -> int:
	return ceili(_cooldown / 60.0)


func lock_seconds_left() -> int:
	return ceili(_lock / 60.0)


## Etat pour le HUD.
func status_text() -> String:
	if _lock > 0:
		return "VERROU %d s" % lock_seconds_left()
	if _truck != null and _truck.is_trailer_detached():
		return "nouvelle remorque %d s" % maxi(seconds_left(), 1)
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
	# caisse, PV et masse de la remorque choisie (defaut si aucune)
	trailer.configure(_truck.trailer_type)
	var visual := _truck.get_node_or_null(^"Visual") as TruckVisual
	if visual != null:
		trailer.set_visual(visual.make_trailer_copy())
	trailer.transform = _truck.detach_trailer()
	_truck.get_parent().add_child(trailer)
	# elle roule encore un peu, puis tient la place (amortie)
	trailer.linear_velocity = _truck.linear_velocity * 0.5
	_cooldown = cooldown_ticks
	_waiting = 0
	last_trailer = trailer
	dropped.emit(trailer)
	return trailer
