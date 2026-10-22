class_name SoundMix
extends RefCounted

## Mixage (2026-10-21 : « un grésillement quand on lance le jeu, tous les
## bruitages sont plutôt forts ; la pluie est vachement forte au début ») :
## trois bus sous le Master, qui garde le volume et la sourdine des reglages :
##   Effets    bruitages (moteurs, chocs, pneus, explosions, pouvoirs, klaxon,
##             menus, bips du compte a rebours et du viseur) ;
##   Ambiance  pluie, vagues, brise ;
##   Musique   musique de course et du menu.
## Un limiteur sur le Master : la somme des sons (quatre moteurs, une
## explosion, la foule, la musique) ne depasse plus le plafond, elle n'ecrete
## plus (l'ecretage s'entend comme un grésillement). Pose une fois par
## GameState au demarrage, avant toute scene.

const EFFECTS := &"Effets"
const AMBIENCE := &"Ambiance"
const MUSIC := &"Musique"
## Volume de chaque bus (dB), sous le Master, jauge a 100 % ; les jauges
## partent de DEFAULT_MUSIC et DEFAULT_EFFECTS. Historique du 2026-10-22 :
## « les bruitages sont trop forts par rapport a la musique » (bruitages -6 ->
## -12, musique +3), puis « je trouve les bruitages faibles, meme a 100 % » :
## 100 % ne faisait que rendre ce -12. Maintenant 100 % = 0 dB, le defaut
## (50 %) = -6 dB, le niveau d'origine, et la musique a pris 5 dB depuis.
const LEVELS := {EFFECTS: 0.0, AMBIENCE: 0.0, MUSIC: 5.0}
## Jauges au premier lancement (%) : musique +3 dB, bruitages et ambiance -6.
const DEFAULT_MUSIC := 80.0
const DEFAULT_EFFECTS := 50.0
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


## Jauges des parametres (2026-10-22 : « une jauge pour la musique et une
## jauge pour les bruitages. Et une jauge generale ») : musique et bruitages
## de 0 a 100 %, par-dessus le niveau de leur bus (LEVELS) ; la jauge des
## bruitages regle aussi l'ambiance (pluie, vagues, foule). La jauge generale
## est le volume du Master. 0 % : bus muet.
static func apply_user_volumes(music_percent: float, effects_percent: float) -> void:
	_set_gain(MUSIC, music_percent)
	_set_gain(EFFECTS, effects_percent)
	_set_gain(AMBIENCE, effects_percent)


static func _set_gain(bus_name: StringName, percent: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, float(LEVELS[bus_name]) + linear_to_db(maxf(percent, 0.1) / 100.0))
	AudioServer.set_bus_mute(idx, percent <= 0.0)


## Le limiteur du Master, ou null.
static func limiter() -> AudioEffectHardLimiter:
	var master := AudioServer.get_bus_index(&"Master")
	for k in AudioServer.get_bus_effect_count(master):
		var fx := AudioServer.get_bus_effect(master, k) as AudioEffectHardLimiter
		if fx != null:
			return fx
	return null
