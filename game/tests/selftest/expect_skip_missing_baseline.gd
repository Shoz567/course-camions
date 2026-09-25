extends PhysicsTest

## Auto-test du socle — doit donner SKIP.
##
## `impulse_stagger_ns` vaut null dans baseline.json tant que la phase 1 n'a pas
## calibre les impulsions (spike S4). Un test qui en depend doit se SAUTER, pas
## inventer une valeur (CLAUDE.md §10).
##
## Quand la valeur sera mesuree, ce cas echouera : c'est voulu. Il faudra alors
## le pointer sur une autre cle encore nulle.


func _test_setup() -> void:
	var impulse: Variant = require_baseline("impulse_stagger_ns")
	if impulse == null:
		return
	# Jamais atteint tant que la valeur est null.
	check("ne devrait pas s'executer", false, "impulse=%s" % impulse)
