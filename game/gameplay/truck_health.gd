class_name TruckHealth
extends Node

## Points de vie du camion (enfant « Health » du camion, comme le cargo).
##
##   - 100 PV ; le gameplay inflige les degats par damage(montant, source).
##   - Murs : le camion signale chaque impact contre une glissiere
##     (Truck.wall_impact, vitesse normale a l'impact). REGLE BOUCLIER : seul
##     le tracteur (cabine, chassis) encaisse ; un choc de la remorque contre
##     un mur ne coute rien. Degats de wall_damage_min (frottement leger) a
##     wall_damage_max (choc frontal violent), selon la vitesse normale.
##   - Barils explosifs : BARREL_DAMAGE, inflige par PadEffects.
##   - A 0 PV : explosion, epave immobilisee wreck_ticks (3 s), puis
##     reapparition sur la piste (respawn_provider, RaceLaps.respawn_transform
##     en course) avec tous ses PV.
## Durees en ticks physiques (CLAUDE.md §7).

signal damaged(amount: float, source: StringName)
signal destroyed
signal respawned

const BARREL_DAMAGE := 15.0

@export var max_hp: float = 100.0
@export var wall_damage_min: float = 1.0
@export var wall_damage_max: float = 5.0
## En dessous : frottement leger (wall_damage_min) ; au-dessus : choc frontal
## violent (wall_damage_max). Vitesse normale au mur, m/s.
@export var wall_speed_light_ms: float = 2.0
@export var wall_speed_hard_ms: float = 18.0
@export var wreck_ticks: int = 180

var hp: float = 100.0
## Transformation de reapparition (Truck -> Transform3D). Par defaut : sur
## place, a plat, 1 m au-dessus.
var respawn_provider: Callable

var _truck: Truck
var _dead_pending: bool = false
var _wreck_left: int = 0


## Le noeud de PV d'un camion (null s'il n'en a pas).
static func of(truck: Truck) -> TruckHealth:
	return truck.get_node_or_null(^"Health") as TruckHealth if truck != null else null


## Degats d'un impact contre un mur, a cette vitesse normale (m/s) : entier,
## de wall_damage_min a wall_damage_max.
func wall_damage_for(normal_speed_ms: float) -> float:
	var u := clampf((normal_speed_ms - wall_speed_light_ms) / (wall_speed_hard_ms - wall_speed_light_ms), 0.0, 1.0)
	return roundf(lerpf(wall_damage_min, wall_damage_max, u))


func _ready() -> void:
	hp = max_hp
	_truck = get_parent() as Truck
	if _truck != null:
		_truck.wall_impact.connect(_on_wall_impact)


func _on_wall_impact(normal_speed_ms: float, on_trailer: bool) -> void:
	if on_trailer:
		return   # la remorque sert de bouclier
	damage(wall_damage_for(normal_speed_ms), &"mur")


## Retire `amount` PV (sans effet sur une epave). A 0 : destruction au
## prochain tick physique (le camion n'est jamais modifie pendant un pas).
func damage(amount: float, source: StringName = &"") -> void:
	if amount <= 0.0 or is_wrecked() or _dead_pending:
		return
	hp = maxf(0.0, hp - amount)
	damaged.emit(amount, source)
	if hp <= 0.0:
		_dead_pending = true


func is_wrecked() -> bool:
	return _wreck_left > 0 or _dead_pending


## Secondes avant la reapparition (0 : en course).
func wreck_seconds_left() -> int:
	return ceili(_wreck_left / 60.0)


func _physics_process(_delta: float) -> void:
	if _truck == null:
		return
	if _dead_pending:
		_dead_pending = false
		_wreck_left = wreck_ticks
		_truck.set_wrecked(true)
		ExplosionFx.spawn(_truck.get_parent(), _truck.global_transform * TruckSpec.CENTER_OF_MASS, 8.0)
		destroyed.emit()
		return
	if _wreck_left > 0:
		_wreck_left -= 1
		if _wreck_left == 0:
			_respawn()


func _respawn() -> void:
	var xf: Transform3D
	if respawn_provider.is_valid():
		xf = respawn_provider.call(_truck)
	else:
		var f := -_truck.global_basis.z
		xf = Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.z)), _truck.global_position + Vector3.UP)
	_truck.set_wrecked(false)
	_truck.reset_to(xf)
	hp = max_hp
	respawned.emit()
