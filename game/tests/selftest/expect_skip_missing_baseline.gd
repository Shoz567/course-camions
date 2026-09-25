extends PhysicsTest

## Auto-test du socle — doit donner SKIP.
##
## `top_speed_kmh` vaut null dans baseline.json tant qu'aucun camion n'a ete
## mesure. Un test qui en depend doit se SAUTER, pas inventer une valeur
## (CLAUDE.md §10).
##
## Quand la valeur sera mesuree, ce cas echouera : c'est voulu. Il faudra alors
## le pointer sur une autre cle encore nulle.


func _test_setup() -> void:
	var top_speed: Variant = require_baseline("top_speed_kmh")
	if top_speed == null:
		return
	# Jamais atteint tant que la valeur est null.
	check("ne devrait pas s'executer", false, "top_speed=%s" % top_speed)
