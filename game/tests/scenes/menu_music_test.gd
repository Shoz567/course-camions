extends PhysicsTest

## Son du menu (2026-10-22 : « dans le menu, quand on lance, il y a un bruit
## sourd. Je voudrais que tu le retires. Et qu'a la place, on ait une musique
## dans le menu ») :
##   A. les camions du plateau sont muets : ni moteur (boucle a 55 Hz au
##      ralenti, le bruit sourd), ni klaxon, ni boost ;
##   B. le menu porte sa musique (MenuMusic) ;
##   C. musique rendue : boucle de 16 mesures a 104 BPM, ni muette ni
##      ecretee, la meme a chaque rendu (rendu court a 8 kHz pour le test).

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
	check("B le menu porte sa musique", _menu.get_node_or_null(^"MenuMusic") is MenuMusic)
	var rate := 8000
	var a := MenuMusic.render(rate, 2)
	var b := MenuMusic.render(rate, 2)
	var step := roundi(rate * 60.0 / MenuMusic.BPM / 4.0)
	var n := a.size() / 4
	var peak := 0
	var sum := 0.0
	for i in n:
		var v := a.decode_s16(i * 4)
		peak = maxi(peak, absi(v))
		sum += float(v) * v
	var rms_db := linear_to_db(sqrt(sum / maxf(n, 1.0)) / 32767.0)
	check("C 2 mesures = 32 doubles croches a 104 BPM, stereo 16 bits", n == 2 * 16 * step, "%d / %d" % [n, 2 * 16 * step])
	check("C ni muette ni ecretee (crete sous 90 %, energie au-dessus de -30 dB)",
		peak < roundi(0.9 * 32767) and rms_db > -30.0, "crete %d, %.1f dB" % [peak, rms_db])
	check("C deterministe", a == b)
