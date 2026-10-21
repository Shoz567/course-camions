class_name PadEffects
extends Node

## Effets des plaques de la piste (style Mario Kart). La piste EMET un signal
## quand un camion roule sur une plaque ; c'est ici que le gameplay decide :
##   - plaque de boost : +boost_extra_kmh tout de suite, vitesse max relevee
##     d'autant pendant boost_ticks (le camion joue son son de boost) ;
##   - rampe de saut : vitesse verticale portee a jump_up_speed_ms, assiette
##     automatique renforcee jusqu'a la reception, reception amortie ;
##   - flaque d'eau : perte d'adherence laterale (savonnette) pendant
##     puddle_slip_ticks, sans freinage longitudinal ;
##   - panneau percute : le panneau s'envole (RoadsideSign), sans penalite
##     de vitesse sur le camion ;
##   - baril explosif : le baril saute (ExplosiveBarrel) et le camion qui l'a
##     fait detoner perd barrel_damage PV (TruckHealth) ;
##   - bonus (TrackPickup, 2026-10-20) : reparation (+repair_cab_hp a la tete,
##     +repair_trailer_hp a la remorque, pneus neufs) ou recharge (le pouvoir
##     qui avait le plus de recharge redevient pret).
## Une meme plaque ne redeclenche pas pour le meme camion avant cooldown_ticks.

@export var track: TrackBlockout
@export var boost_extra_kmh: float = 40.0
@export var boost_ticks: int = 90            # 1,5 s
@export var jump_up_speed_ms: float = 9.5
@export var cooldown_ticks: int = 60
@export var puddle_slip_ticks: int = 60
@export var puddle_speed_factor: float = 1.0
@export var puddle_ticks: int = 0
@export var puddle_decel_ms2: float = 0.0
@export var sign_speed_factor: float = 1.0
@export var sign_ticks: int = 0
@export var sign_decel_ms2: float = 0.0
@export var barrel_damage: float = TruckHealth.BARREL_DAMAGE
@export var repair_cab_hp: float = 40.0
@export var repair_trailer_hp: float = 30.0

## Dernier declenchement : "b3:<id du camion>" -> tick physique.
var _last: Dictionary = {}


func _ready() -> void:
	if track == null:
		push_error("PadEffects : aucune piste")
		return
	track.boost_pad_entered.connect(_on_boost_pad)
	track.jump_pad_entered.connect(_on_jump_pad)
	track.puddle_entered.connect(_on_puddle)
	track.sign_hit.connect(_on_sign)
	track.barrel_hit.connect(_on_barrel)
	track.pickup_taken.connect(_on_pickup)


func _on_pickup(truck: Truck, kind: int, _index: int) -> void:
	if kind == TrackPickup.Kind.REPAIR:
		var h := TruckHealth.of(truck)
		if h != null:
			h.repair(repair_cab_hp, repair_trailer_hp)
		var tires := truck.get_node_or_null(^"Tires") as TruckTires
		if tires != null and not tires.net_mirror:
			tires.repair()
	else:
		var p := TruckPowers.of(truck)
		if p != null and not p.mirror:
			p.refill_one()


func _on_boost_pad(body: Node3D, index: int) -> void:
	var truck := body as Truck
	if truck != null and _fresh(truck, "b%d" % index):
		truck.pad_boost(boost_extra_kmh, boost_ticks)


func _on_jump_pad(body: Node3D, index: int) -> void:
	var truck := body as Truck
	if truck != null and _fresh(truck, "j%d" % index):
		truck.jump_pad_launch(jump_up_speed_ms)


func _on_puddle(body: Node3D, index: int) -> void:
	var truck := body as Truck
	if truck != null and _fresh(truck, "p%d" % index):
		truck.apply_puddle_slip(puddle_slip_ticks)
		if puddle_speed_factor < 1.0 or puddle_decel_ms2 > 0.0:
			truck.apply_slowdown(puddle_speed_factor, puddle_ticks, puddle_decel_ms2)


func _on_sign(body: Node3D, index: int) -> void:
	var truck := body as Truck
	if truck != null and _fresh(truck, "s%d" % index):
		if sign_speed_factor < 1.0 or sign_decel_ms2 > 0.0:
			truck.apply_slowdown(sign_speed_factor, sign_ticks, sign_decel_ms2)


func _on_barrel(truck: Truck, _index: int) -> void:
	var health := TruckHealth.of(truck)
	if health != null:
		health.damage(barrel_damage, &"baril")


func _fresh(truck: Truck, pad: String) -> bool:
	var key := "%s:%d" % [pad, truck.get_instance_id()]
	var now := Engine.get_physics_frames()
	if _last.has(key) and now - int(_last[key]) < cooldown_ticks:
		return false
	_last[key] = now
	return true
