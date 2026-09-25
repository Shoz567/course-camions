class_name BoneTuning
extends Resource

## Reglages du PD d'une articulation : celle qui relie `bone` a son parent.
##
## Les gains ne sont PAS stockes en kp / kd bruts, mais en frequence propre et
## taux d'amortissement :
##
##   kp = I * frequency^2
##   kd = 2 * damping_ratio * I * frequency
##
## Deux raisons :
##
## 1. Les gains deviennent proportionnels a l'inertie I du membre, donc a sa
##    masse. C'est la regle de CLAUDE.md §6 : jamais de couple absolu code en
##    dur sur un membre. Un meme reglage de frequence donne le meme
##    comportement sur un avant-bras de 1,8 kg et sur un torse de 19 kg.
##
## 2. damping_ratio = 1 est exactement l'amortissement critique
##    kd = 2 * sqrt(kp * I) recommande par .claude/agents/ragdoll-engineer.md.
##    En dessous, le membre oscille ; au-dessus, il est mou.
##
## Les valeurs livrees dans default_tuning.tres sont des POINTS DE DEPART
## volontairement bas ("commence bas et monte"), pas un reglage. Le tuning se
## fait en tache 1.6, avec les tests d'equilibre.

## Os pilote. Son articulation est celle qui le relie a son parent.
@export var bone: StringName = &""

## Interrupteur de debug : couper le PD de cette seule articulation, pour
## isoler ce qui casse l'equilibre (CLAUDE.md §6).
@export var enabled: bool = true

## ⚠️ Les trois valeurs par defaut ci-dessous valent 0 A DESSEIN, et
## CharacterTuning.validate() refuse 0.
##
## Godot n'ecrit pas dans un .tres une valeur egale au defaut du script. Avec
## des defauts "raisonnables", un os regle exactement sur le defaut n'aurait
## pas sa valeur dans default_tuning.tres — et changer le defaut ici modifierait
## son reglage en silence, sans toucher au .tres. Avec 0, toute valeur reelle
## differe du defaut et figure donc toujours dans le fichier.
##
## Ne remplace pas ces 0 par des valeurs "pratiques".

## Frequence propre du ressort, en rad/s. Plus haut = plus raide.
@export_range(0.0, 60.0, 0.1, "suffix:rad/s") var frequency: float = 0.0

## Taux d'amortissement. 1 = critique (aucune oscillation, retour le plus
## rapide) ; < 1 oscille ; > 1 est mou.
@export_range(0.0, 3.0, 0.01) var damping_ratio: float = 0.0

## Couple maximal, en N.m PAR KILOGRAMME de ce membre. Le couple reel est
## clampe a `max_torque_per_kg * masse` (CLAUDE.md §6).
@export_range(0.0, 200.0, 0.1, "suffix:N.m/kg") var max_torque_per_kg: float = 0.0


## Gain proportionnel, pour une inertie `inertia` (kg.m^2) autour de l'axe
## considere.
func kp(inertia: float) -> float:
	return inertia * frequency * frequency


## Gain derive, pour une inertie `inertia` (kg.m^2).
func kd(inertia: float) -> float:
	return 2.0 * damping_ratio * inertia * frequency


## Couple maximal autorise, en N.m, pour un membre de masse `mass` (kg).
func max_torque(mass: float) -> float:
	return max_torque_per_kg * mass
