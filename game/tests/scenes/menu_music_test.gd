extends PhysicsTest

## Son du menu (2026-10-22 : « dans le menu, quand on lance, il y a un bruit
## sourd. Je voudrais que tu le retires. Et qu'a la place, on ait une musique
## dans le menu ») :
##   A. les camions du plateau sont muets : ni moteur (boucle a 55 Hz au
##      ralenti, le bruit sourd), ni klaxon, ni boost ;
##   B. le menu porte sa musique (MenuMusic) : Racing Game Title de MintoDog
##      (CC0), en boucle ; aucun lecteur en headless.

var _menu: MainMenu


func _test_setup() -> void:
	duration_ticks = 3
	GameState.requested_players = 0
	_menu = (load("res://ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	_menu.auto_change_scene = false
	add_child(_menu)


func _test_finish() -> void:
	var sounds := []
	for t in _menu.trucks:
		for n: String in MainMenu.SHOWROOM_MUTED:
			if t.get_node_or_null(n) != null:
				sounds.append("%s/%s" % [t.name, n])
	check("A camions du plateau muets (moteur, klaxon, boost)", sounds.is_empty() and _menu.trucks.size() == 6
		and MainMenu.SHOWROOM_MUTED.has("Audio"), str(sounds))
	var music := _menu.get_node_or_null(^"MenuMusic") as MenuMusic
	var s := load(MenuMusic.STREAM) as AudioStream
	check("B le menu porte sa musique, en boucle (> 30 s), sans lecteur en headless",
		music != null and s != null and bool(s.get("loop")) and s.get_length() > 30.0 and not music.is_playing()
		and music.get_child_count() == 0, "%s" % [s.get_length() if s != null else "absente"])
