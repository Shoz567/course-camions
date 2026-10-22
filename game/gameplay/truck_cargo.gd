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
## Limites (2026-10-20 : « limiter le nombre de largages par joueur, le
## choisir au debut d'une course, entre 0 et 5 ; une fois la remorque
## revenue, un delai d'une vingtaine de secondes avant de pouvoir la
## larguer ») : drops_left largages dans la course (GameState.trailer_drops,
## pose par la course ; -1 : illimite), et rearm_ticks apres le retour d'une
## remorque.

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
## Delai apres le retour d'une remorque avant de pouvoir la larguer (20 s).
@export var rearm_ticks: int = 1200

## Largages qui restent dans la course (-1 : illimite).
var drops_left: int = -1
## Arene (2026-10-21 : « on ne peut pas lâcher la remorque ; une fois
## détruite, elle ne réapparaît que quand on perd une vie ») : une remorque
## par vie, pas de nouvelle remorque apres sa destruction (la course met
## aussi drops_left a 0) ; la suivante arrive avec le camion neuf.
var one_per_life: bool = false

var _truck: Truck
var _cooldown: int = 0
var _lock: int = 0
var _waiting: int = 0
var _rearm: int = 0
var last_trailer: DetachedTrailer
## En ligne, chez un client (NetRace) : le host decide du largage et du
## raccrochage ; la recharge affichee arrive du host (net_set_charge).
var net_mirror: bool = false


func _ready() -> void:
	_truck = get_parent() as Truck
	if _truck != null:
		_truck.cargo_requested.connect(_on_cargo_requested)
		var health := TruckHealth.of(_truck)
		if health != null:
			health.respawned.connect(_on_respawned)


## Depart de la course : largage interdit pendant first_seconds_lock_ticks.
func start_race_lock() -> void:
	_lock = first_seconds_lock_ticks


func _physics_process(_delta: float) -> void:
	if _lock > 0:
		_lock -= 1
	if _cooldown > 0:
		_cooldown -= 1
	if _rearm > 0 and _truck != null and not _truck.is_trailer_detached():
		_rearm -= 1
	if net_mirror:
		return
	if _truck == null or not _truck.is_trailer_detached() or _cooldown > 0 or _truck.is_wrecked() or one_per_life:
		return
	# recharge finie : une nouvelle remorque apparait (l'ancienne reste)
	_waiting += 1
	if _truck.reattach_trailer(_waiting >= reattach_timeout_ticks):
		_waiting = 0
		_rearm = rearm_ticks
		reattached.emit()


func is_ready() -> bool:
	return _cooldown == 0 and _lock == 0 and _rearm == 0 and drops_left != 0 and _truck != null \
			and not _truck.is_trailer_detached()


func is_locked() -> bool:
	return _lock > 0


## 1 = pret, 0 = vient d'etre largue (ou verrouille).
func get_charge() -> float:
	if _lock > 0:
		return 1.0 - float(_lock) / maxf(first_seconds_lock_ticks, 1)
	if drops_left == 0 and _truck != null and not _truck.is_trailer_detached():
		return 0.0
	if _rearm > 0 and _truck != null and not _truck.is_trailer_detached():
		return 1.0 - float(_rearm) / maxf(rearm_ticks, 1)
	return 1.0 - float(_cooldown) / maxf(cooldown_ticks, 1)


func seconds_left() -> int:
	return ceili(_cooldown / 60.0)


func lock_seconds_left() -> int:
	return ceili(_lock / 60.0)


## Secondes avant de pouvoir larguer la remorque revenue.
func rearm_seconds_left() -> int:
	return ceili(_rearm / 60.0)


## Etat pour le HUD.
func status_text() -> String:
	if one_per_life:
		return "REMORQUE DÉTRUITE · prochaine vie" if _truck != null and _truck.is_trailer_detached() \
				else "REMORQUE · une par vie"
	if _lock > 0:
		return "VERROU %d s" % lock_seconds_left()
	if _truck != null and _truck.is_trailer_detached():
		return "nouvelle remorque %d s" % maxi(seconds_left(), 1)
	if _cooldown > 0:
		return "remorque %d s" % seconds_left()
	if drops_left == 0:
		return "PLUS DE LARGAGE"
	if _rearm > 0:
		return "largage dans %d s" % rearm_seconds_left()
	if drops_left > 0:
		return "REMORQUE PRÊTE · %d largage%s" % [drops_left, "s" if drops_left > 1 else ""]
	return "REMORQUE PRÊTE"


## Client en ligne : recharge et verrou du depart tels que le host les voit.
func net_set_charge(charge: float, locked: bool) -> void:
	if locked:
		_lock = maxi(roundi((1.0 - charge) * first_seconds_lock_ticks), 1)
		_cooldown = 0
	elif _truck != null and not _truck.is_trailer_detached():
		# remorque sur le camion : la charge est le delai avant le largage
		_lock = 0
		_cooldown = 0
		_rearm = roundi((1.0 - clampf(charge, 0.0, 1.0)) * rearm_ticks)
	else:
		_lock = 0
		_rearm = 0
		_cooldown = roundi((1.0 - clampf(charge, 0.0, 1.0)) * cooldown_ticks)


## Camion reapparu, remorque neuve attelee : le meme delai qu'au retour
## d'une remorque avant de pouvoir la larguer.
func _on_respawned() -> void:
	_cooldown = 0
	_waiting = 0
	_rearm = rearm_ticks


## Client en ligne : largage predit que le host a refuse ; la remorque est
## revenue, le largage n'est pas compte.
func undo_drop() -> void:
	if drops_left >= 0:
		drops_left += 1
	_cooldown = 0
	_waiting = 0


func _on_cargo_requested() -> void:
	if net_mirror:
		return
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
	if drops_left > 0:
		drops_left -= 1
	_waiting = 0
	last_trailer = trailer
	dropped.emit(trailer)
	return trailer


## Remorque detruite sur le camion (TruckHealth, 0 PV de remorque) : elle
## disparait dans l'explosion, sans rien laisser sur la route. Le tracteur
## roule seul, puis une nouvelle remorque arrive apres la recharge, comme
## apres un largage.
func lose_trailer() -> void:
	if _truck == null or _truck.is_trailer_detached():
		return
	_truck.detach_trailer()
	_cooldown = cooldown_ticks
	_waiting = 0
