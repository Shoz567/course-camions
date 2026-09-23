class_name GameStateNode
extends Node

## Etat global de la partie : slots joueurs, mapping device -> slot, couleurs.
##
## Autoload. Detient le mapping `device_id -> player_slot`, qui persiste
## pendant tout le match (cf. docs/INPUT_SPEC.md §5). Ne reattribue jamais
## un slot en cours de partie.
##
## Phase 0 : volontairement vide. Rempli en phase 4.

func _ready() -> void:
	pass
