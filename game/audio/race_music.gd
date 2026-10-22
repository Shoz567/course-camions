class_name RaceMusic
extends Node

## Musique de course (2026-10-22 : « une par map [...] la musique change
## uniquement au dernier tour [...] sur la version avec un plus gros BPM ») :
## un morceau par habillage de circuit, et sa version « Climax » (plus
## rapide) pour le dernier tour. Morceaux CC0 de MintoDog (OpenGameArt),
## audio/music/CREDITS.md :
##   Cyber City     Neon sign Circuit, 145 BPM -> Climax 160 ;
##   Playa Del Sol  Sunny City, 120 -> Climax 135 ;
##   Sakura         Blossom Mountain [Remake], 140 -> Climax [Remake] 155.
## L'arene prend celle de son habillage.
##
## play() au GO lance la version normale ; set_final(true) passe en fondu a
## celle du dernier tour, une seule fois (LocalRace decide quand :
## final_due) ; fade_out() a l'arrivee. Deux lecteurs sur le bus Musique
## (SoundMix). Noeud enfant de la course : il disparait avec elle. En
## headless, aucun lecteur ; l'etat (playing, final) suit quand meme.

## [normale, dernier tour] par habillage (TrackTheme.Id).
const TRACKS := {
	TrackTheme.Id.CYBER_CITY: ["res://audio/music/cyber_city.ogg", "res://audio/music/cyber_city_last_lap.ogg"],
	TrackTheme.Id.PLAYA_DEL_SOL: ["res://audio/music/playa_del_sol.mp3", "res://audio/music/playa_del_sol_last_lap.mp3"],
	TrackTheme.Id.SAKURA: ["res://audio/music/sakura.mp3", "res://audio/music/sakura_last_lap.ogg"],
}
const VOLUME_DB := -6.0
## Fondu d'entree au GO, de passage au dernier tour, de sortie a l'arrivee (s).
const FADE_IN_S := 0.4
const SWITCH_S := 1.2
const FADE_S := 1.5
## Arene et elimination (pas de dernier tour) : version rapide pour la
## derniere minute, ou quand il ne reste que FINAL_ALIVE camions.
const FINAL_SECONDS := 60
const FINAL_ALIVE := 2

## Habillage du circuit (TrackTheme.Id), avant play().
var theme_id: int = TrackTheme.Id.CYBER_CITY
## La musique tourne (du GO a l'arrivee) ; la version du dernier tour est
## lancee.
var playing: bool = false
var final: bool = false

var _normal: AudioStreamPlayer
var _last: AudioStreamPlayer


## La version du dernier tour est-elle due ? Course, contre-la-montre,
## elimination : des que le joueur suivi (le plus avance des joueurs de ce
## PC) entame le dernier tour. Arene et elimination : aussi a la derniere
## minute (`seconds_left`, -1 : sans limite), ou quand il ne reste que
## FINAL_ALIVE camions en piste sur `trucks` au depart (une manche a deux
## ne commence pas en version rapide).
static func final_due(mode: int, lap: int, total_laps: int, alive: int, trucks: int, seconds_left: int) -> bool:
	if mode != GameStateNode.GameMode.ARENA and lap >= total_laps:
		return true
	if mode == GameStateNode.GameMode.ARENA or mode == GameStateNode.GameMode.ELIMINATION:
		return (trucks > FINAL_ALIVE and alive <= FINAL_ALIVE) or (seconds_left >= 0 and seconds_left <= FINAL_SECONDS)
	return false


## Flux de l'habillage `id` : version normale, ou du dernier tour.
static func stream_for(id: int, last_lap: bool) -> AudioStream:
	var pair: Array = TRACKS.get(id, TRACKS[TrackTheme.Id.CYBER_CITY])
	return load(String(pair[1 if last_lap else 0])) as AudioStream


## Demarre la version normale (au GO).
func play() -> void:
	if playing:
		return
	playing = true
	if not _audible():
		return
	_normal = _player("Normal", stream_for(theme_id, false))
	_normal.play()
	create_tween().tween_property(_normal, "volume_db", VOLUME_DB, FADE_IN_S)


## Passe a la version du dernier tour (une fois), en fondu croise.
func set_final(on: bool) -> void:
	if not on or final or not playing:
		return
	final = true
	if not _audible():
		return
	_last = _player("LastLap", stream_for(theme_id, true))
	_last.play()
	var tw := create_tween().set_parallel()
	tw.tween_property(_last, "volume_db", VOLUME_DB, SWITCH_S)
	if _normal != null:
		tw.tween_property(_normal, "volume_db", -60.0, SWITCH_S)
		tw.chain().tween_callback(_normal.stop)


## Arrete la musique en fondu (arrivee, partie perdue).
func fade_out() -> void:
	if not playing:
		return
	playing = false
	for p: AudioStreamPlayer in [_normal, _last]:
		if p != null and p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -60.0, FADE_S)
			tw.tween_callback(p.stop)


func is_playing() -> bool:
	return (_normal != null and _normal.playing) or (_last != null and _last.playing)


func _audible() -> bool:
	return DisplayServer.get_name() != "headless"


func _player(player_name: String, s: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = player_name
	p.bus = SoundMix.MUSIC
	p.stream = s
	p.volume_db = -60.0
	add_child(p)
	return p
