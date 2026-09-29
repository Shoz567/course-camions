class_name PadEffects
extends Node

## Effets des plaques de la piste (style Mario Kart). La piste EMET un signal
## quand un camion roule sur une plaque ; c'est ici que le gameplay decide :
##   - plaque de boost : +boost_extra_kmh tout de suite, vitesse max relevee
##     d'autant pendant boost_ticks (le camion joue son son de boost) ;
##   - rampe de saut : vitesse verticale portee a jump_up_speed_ms, assiette
##     automatique renforcee jusqu'a la reception, reception amortie.
## Une meme plaque ne redeclenche pas pour le meme camion avant cooldown_ticks.

@export var track: TrackBlockout
@export var boost_extra_kmh: float = 40.0
@export var boost_ticks: int = 90            # 1,5 s
@export var jump_up_speed_ms: float = 8.0
@export var cooldown_ticks: int = 60

## Dernier declenchement : "b3:<id du camion>" -> tick physique.
var _last: Dictionary = {}


func _ready() -> void:
	if track == null:
		push_error("PadEffects : aucune piste")
		return
	track.boost_pad_entered.connect(_on_boost_pad)
	track.jump_pad_entered.connect(_on_jump_pad)


func _on_boost_pad(body: Node3D, index: int) -> void:
	var truck := body as Truck
	if truck != null and _fresh(truck, "b%d" % index):
		truck.pad_boost(boost_extra_kmh, boost_ticks)


func _on_jump_pad(body: Node3D, index: int) -> void:
	var truck := body as Truck
	if truck != null and _fresh(truck, "j%d" % index):
		truck.jump_pad_launch(jump_up_speed_ms)


func _fresh(truck: Truck, pad: String) -> bool:
	var key := "%s:%d" % [pad, truck.get_instance_id()]
	var now := Engine.get_physics_frames()
	if _last.has(key) and now - int(_last[key]) < cooldown_ticks:
		return false
	_last[key] = now
	return true
