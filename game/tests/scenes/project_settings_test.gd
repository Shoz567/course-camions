extends PhysicsTest

## Reglages non negociables de CLAUDE.md §2 et §6, lus sur leur valeur
## EFFECTIVE. L'editeur Godot retire de project.godot les lignes egales au
## defaut (60 ticks/s, Forward+) : le texte du fichier ne prouve rien, la
## valeur chargee si.


func _test_setup() -> void:
	duration_ticks = 1


func _test_finish() -> void:
	check("tick physique = 60 Hz", Engine.physics_ticks_per_second == 60,
		"ticks=%d" % Engine.physics_ticks_per_second)
	var engine: String = ProjectSettings.get_setting("physics/3d/physics_engine", "")
	check("moteur physique = Jolt", engine == "Jolt Physics", "moteur=%s" % engine)
	var renderer: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
	check("renderer = Forward+", renderer == "forward_plus", "renderer=%s" % renderer)
