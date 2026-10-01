@tool
class_name CityBackdrop
extends Node3D

## Ville de decor autour de la piste parente (CityBuilder.around_track).
## Purement visuelle : en headless (tests), elle n'est pas generee, sauf si un
## test le force ; rien dans la simulation n'en depend.

@export var city_seed: int = 7

## Un test peut forcer la generation en headless.
static var generate_in_headless: bool = false


func _ready() -> void:
	if DisplayServer.get_name() == "headless" and not generate_in_headless:
		return
	var track := get_parent() as TrackBlockout
	if track == null:
		return
	# la piste parente se construit dans SON _ready, apres le notre : on
	# attend qu'elle soit prete (sinon elle ne pourrait pas ajouter ses noeuds)
	if track.is_node_ready():
		_generate(track)
	else:
		track.ready.connect(_generate.bind(track), CONNECT_ONE_SHOT)


func _generate(track: TrackBlockout) -> void:
	add_child(CityBuilder.around_track(track, city_seed))
