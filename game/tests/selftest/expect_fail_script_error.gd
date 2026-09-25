extends PhysicsTest

## Auto-test du socle — doit donner FAIL.
##
## Une verification passe, PUIS une erreur d'execution survient. GDScript
## interrompt la fonction mais la scene conclut quand meme, avec 1 verification
## reussie : "RESULT PASS". Le runner doit detecter l'erreur et refuser.


func _test_setup() -> void:
	duration_ticks = 10


func _test_finish() -> void:
	check("verification posee avant l'erreur", true, "valeur=ok")
	var missing: Node = get_node_or_null("NoeudQuiNExistePas")
	# Erreur d'execution volontaire : appel de methode sur null.
	print(missing.name)
	check("jamais atteint", true)
