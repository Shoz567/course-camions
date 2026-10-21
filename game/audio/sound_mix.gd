class_name SoundMix
extends RefCounted

## Mixage (2026-10-21 : « un grésillement quand on lance le jeu, tous les
## bruitages sont plutôt forts ; la pluie est vachement forte au début ») :
## trois bus sous le Master, qui garde le volume et la sourdine des reglages :
##   Effets    bruitages (moteurs, chocs, pneus, explosions, pouvoirs, klaxon,
##             menus, bips du compte a rebours et du viseur) ;
##   Ambiance  pluie, vagues, brise, foule des tribunes ;
##   Musique   musique de course.
## Un limiteur sur le Master : la somme des sons (quatre moteurs, une
## explosion, la foule, la musique) ne depasse plus le plafond, elle n'ecrete
## plus (l'ecretage s'entend comme un grésillement). Pose une fois par
## GameState au demarrage, avant toute scene.

const EFFECTS := &"Effets"
const AMBIENCE := &"Ambiance"
const MUSIC := &"Musique"
## Volume de chaque bus (dB), sous le Master.
const LEVELS := {EFFECTS: -6.0, AMBIENCE: -6.0, MUSIC: 0.0}
## Plafond du limiteur du Master (dB).
const CEILING_DB := -1.0


## Cree les bus manquants, regle leur volume, pose le limiteur (idempotent).
static func setup() -> void:
	for bus_name: StringName in LEVELS:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
		AudioServer.set_bus_volume_db(idx, float(LEVELS[bus_name]))
	if limiter() == null:
		var fx := AudioEffectHardLimiter.new()
		fx.ceiling_db = CEILING_DB
		AudioServer.add_bus_effect(AudioServer.get_bus_index(&"Master"), fx)


## Le limiteur du Master, ou null.
static func limiter() -> AudioEffectHardLimiter:
	var master := AudioServer.get_bus_index(&"Master")
	for k in AudioServer.get_bus_effect_count(master):
		var fx := AudioServer.get_bus_effect(master, k) as AudioEffectHardLimiter
		if fx != null:
			return fx
	return null
