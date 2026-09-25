extends PhysicsTest

## Auto-test du socle — doit donner FAIL.
##
## Un test qui arrive au bout sans avoir pose une seule verification. Le socle
## doit le refuser : un test qui ne mesure rien n'est pas un test.


func _test_setup() -> void:
	duration_ticks = 10
