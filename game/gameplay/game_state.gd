class_name GameStateNode
extends Node

## Etat global de la partie : joueurs, mapping device -> joueur, camion et
## couleur choisis.
##
## Autoload. Detient le mapping `device_id -> player_slot`, qui persiste
## pendant toute la course (cf. docs/INPUT_SPEC.md §5). Ne reattribue jamais
## un slot en cours de course.
##
## Pour l'instant : le nombre de joueurs choisi dans le menu principal, lu par
## la course locale. Le mapping device -> slot est fixe (joueur i = manette i).

## Nombre de joueurs demande par le menu (1 a 4). 0 = rien de demande : la
## scene de course garde sa propre valeur (tests, lancement direct).
var requested_players: int = 0
