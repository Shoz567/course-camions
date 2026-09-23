class_name MatchManagerNode
extends Node

## Machine a etats de la manche : LOBBY -> COUNTDOWN -> PLAYING -> ROUND_END
## -> (PLAYING | MATCH_END). Transitions par signaux, jamais par booleens
## eparpilles (cf. .claude/agents/gameplay-engineer.md).
##
## Detient aussi le RandomNumberGenerator seede : tout aleatoire du jeu passe
## par lui (cf. CLAUDE.md §7).
##
## Phase 0 : volontairement vide. Rempli en phase 3.

func _ready() -> void:
	pass
