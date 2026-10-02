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
##     de vitesse sur le camion.
## Une meme plaque ne redeclenche pas pour le meme camion avant cooldown_ticks.

@export var track: TrackBlockout
@export var boost_extra_kmh: float = 40.0
@export var boost_ticks: int = 90            # 1,5 s
@export var jump_up_speed_ms: float = 8.0
@export var cooldown_ticks: int = 60
@export var puddle_slip_ticks: int = 60
@export var puddle_speed_factor: float = 1.0
@export var puddle_ticks: int = 0
@export var puddle_decel_ms2: float = 0.0
@export var sign_speed_factor: float = 1.0
@export var sign_ticks: int = 0
@export var sign_decel_ms2: float = 0.0

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


func _fresh(truck: Truck, pad: String) -> bool:
	var key := "%s:%d" % [pad, truck.get_instance_id()]
	var now := Engine.get_physics_frames()
	if _last.has(key) and now - int(_last[key]) < cooldown_ticks:
		return false
	_last[key] = now
	return true
