extends "res://tests/scenes/track_01_lap_test.gd"

## Circuit n°2, Playa Del Sol : les memes regles dures que le circuit n°1
## (track_01_lap_test) - un tour complet au pilote automatique en 90 a 130 s,
## jamais retourne ni hors de la chaussee, tremplin de la plage franchi, tour
## compte par les vraies Area3D, camera jamais masquee ni tremblante - sur le
## pont de la baie, la jetee en bois et la corniche.


func _track_scene() -> String:
	return "res://tracks/track_02_playa.tscn"
