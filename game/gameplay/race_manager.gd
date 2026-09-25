class_name RaceManagerNode
extends Node

## Machine a etats de la course : LOBBY -> GRID -> COUNTDOWN -> RACING ->
## FINISHED -> RESULTS. Transitions par signaux, jamais par booleens eparpilles
## (cf. .claude/agents/gameplay-engineer.md).
##
## Detient aussi le RandomNumberGenerator seede : tout aleatoire du jeu passe
## par lui (cf. CLAUDE.md §7), pour que la phase online reste possible.
##
## Volontairement vide pour l'instant. Rempli en phase 3 (boucle de course).

func _ready() -> void:
	pass
