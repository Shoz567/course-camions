class_name MenuMusic
extends Node

## Musique du menu (2026-10-22 : « qu'a la place [du bruit sourd], on ait une
## musique dans le menu », puis des morceaux choisis par l'utilisateur) :
## Racing Game Title de MintoDog (CC0, OpenGameArt, audio/music/CREDITS.md),
## en boucle, entree en fondu. Bus Musique (SoundMix). Noeud enfant du menu :
## il disparait avec lui (depart d'une course). Aucun lecteur en headless.

const STREAM := "res://audio/music/menu.mp3"
const VOLUME_DB := -8.0
const FADE_IN_S := 2.0

var _player: AudioStreamPlayer


## Demarre la boucle, en fondu.
func play() -> void:
	if DisplayServer.get_name() == "headless" or is_playing():
		return
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.name = "MenuMusicPlayer"
		_player.bus = SoundMix.MUSIC
		_player.stream = load(STREAM) as AudioStream
		add_child(_player)
	_player.volume_db = -50.0
	_player.play()
	create_tween().tween_property(_player, "volume_db", VOLUME_DB, FADE_IN_S)


func is_playing() -> bool:
	return _player != null and _player.playing
