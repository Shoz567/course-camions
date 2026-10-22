extends PhysicsTest

## Menu range en pages (2026-10-22 : « ameliorer tout ce qui est menu [...]
## quand on selectionne en ligne, que ca ouvre un autre menu [...] le mode en
## ligne et local, pas tres bien separe ») :
##   A. accueil d'abord : quatre tuiles, focus sur JOUER EN LOCAL ; Echap
##      ramene de la partie locale et du menu en ligne a l'accueil ;
##   B. reglages separes : circuit et bots choisis en local et en ligne ne se
##      melangent pas, dans les deux sens, et settings.cfg garde les deux
##      ([race], [online]) ;
##   C. heberger : le salon remplace HEBERGER / REJOINDRE ; regles du host
##      sans contre-la-montre, LANCER grise tant que le convoi n'est pas
##      choisi, ce qu'on attend est ecrit ; les regles partent au lobby
##      (NetSession.rules) ;
##   D. partie ouverte : a l'accueil, JOUER EN LOCAL grisee, JOUER EN LIGNE
##      ramene au salon ; QUITTER LA PARTIE rouvre tout.

const PORT := 7797
const CFG := "user://menu_pages_test.cfg"

var _menu: MainMenu
var _seen: Dictionary = {}
var _saved: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 90
	get_window().size = Vector2i(1920, 1080)
	GameState.use_profile(GameStateNode.Profile.LOCAL)
	_saved = GameState.rules()
	GameState.apply_rules({"track": 0, "bots": 0, "mode": GameStateNode.GameMode.RACE})
	GameState.requested_players = 0
	_menu = (load("res://ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	_menu.auto_change_scene = false
	add_child(_menu)


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		Input.flush_buffered_events()


func _test_tick(t: int) -> void:
	match t:
		3:
			_seen["title"] = [_menu.title_page.visible, _menu.local_page.visible, _menu.online.visible,
				_menu.local_tile.has_focus(), _menu.quit_tile != null and _menu.settings_tile != null]
			_menu.open_local()
			_menu.select_track(1)
			_menu.select_bots(2)
		8:
			_seen["local"] = [_menu.local_page.visible, GameState.profile, GameState.selected_track, GameState.bot_count]
			_key(KEY_ESCAPE)
		10:
			_seen["esc_local"] = [_menu.title_page.visible, _menu.local_page.visible, _menu.local_tile.has_focus()]
			_menu.open_online()
		14:
			_seen["online_first"] = [_menu.online.visible, _menu.online.connect_box.visible, GameState.profile]
			# en ligne : autre circuit, autres bots
			_menu.online.set_track(2)
			_menu.online.set_bots(4)
		20:
			_key(KEY_ESCAPE)
		22:
			_seen["esc_online"] = [_menu.title_page.visible, _menu.online.visible, _menu.online_tile.has_focus()]
			_menu.open_local()
		28:
			_seen["back_local"] = [GameState.profile, GameState.selected_track, GameState.bot_count,
				_menu.track_option.selected == 1, _menu.bot_buttons[2].button_pressed, UiKit.skin]
			_menu.back_to_title()
			_menu.open_online()
		34:
			_seen["back_online"] = [GameState.profile, GameState.selected_track, GameState.bot_count, UiKit.skin]
			GameState.write_settings(CFG)
			var cfg := ConfigFile.new()
			cfg.load(CFG)
			_seen["cfg"] = [int(cfg.get_value("race", "track", -1)), int(cfg.get_value("race", "bots", -1)),
				int(cfg.get_value("online", "track", -1)), int(cfg.get_value("online", "bots", -1))]
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
			NetSession.player_name = "Hote"
			_menu.online.host_game()
		40:
			var o := _menu.online
			var names: Array[String] = []
			for b in o.mode_buttons:
				names.append(b.text)
			_seen["lobby"] = [o.connect_box.visible, o.lobby_box.visible, o.rules_host.visible, o.rules_guest.visible,
				names, o.launch_button.visible, o.launch_button.disabled, o.wait_label.text.contains("convoi")]
			o.set_mode(GameStateNode.GameMode.TIME_TRIAL)
			o.set_bots(5)
		42:
			var r := NetSession.rules()
			_seen["rules"] = [GameState.game_mode, int(r["mode"]), int(r["bots"]), int(r["track"])]
			_menu.back_to_title()
		46:
			_seen["title_online"] = [_menu.local_tile.disabled, (_menu.online_tile.find_child("Sub", true, false) as Label).text]
			_menu.open_local()
		48:
			_seen["local_blocked"] = [_menu.local_page.visible, _menu.title_page.visible]
			_menu.open_online()
		52:
			_seen["lobby_again"] = [_menu.online.visible, _menu.online.lobby_box.visible]
			_menu.online.leave_game()
		56:
			_seen["left"] = [NetSession.is_online(), _menu.online.connect_box.visible, _menu.local_tile.disabled]
			duration_ticks = mini(duration_ticks, t + 1)


func _test_finish() -> void:
	check("A accueil d'abord : tuiles, focus sur JOUER EN LOCAL", _seen.get("title", []) == [true, false, false, true, true],
		str(_seen.get("title")))
	check("A partie locale : profil local, choix pris", _seen.get("local", []) == [true, GameStateNode.Profile.LOCAL, 1, 2],
		str(_seen.get("local")))
	check("A Echap : de la partie locale a l'accueil", _seen.get("esc_local", []) == [true, false, true], str(_seen.get("esc_local")))
	check("A en ligne : menu a part, HEBERGER / REJOINDRE, profil en ligne",
		_seen.get("online_first", []) == [true, true, GameStateNode.Profile.ONLINE], str(_seen.get("online_first")))
	check("A Echap : du menu en ligne a l'accueil, focus sur JOUER EN LIGNE", _seen.get("esc_online", []) == [true, false, true],
		str(_seen.get("esc_online")))
	check("B retour en local : ses reglages (Playa, 2 bots), ambiance Playa",
		_seen.get("back_local", []) == [GameStateNode.Profile.LOCAL, 1, 2, true, true, UiKit.Look.PLAYA], str(_seen.get("back_local")))
	check("B retour en ligne : les siens (Sakura, 4 bots), ambiance Sakura",
		_seen.get("back_online", []) == [GameStateNode.Profile.ONLINE, 2, 4, UiKit.Look.SAKURA], str(_seen.get("back_online")))
	check("B settings.cfg : [race] Playa 2 bots, [online] Sakura 4 bots", _seen.get("cfg", []) == [1, 2, 2, 4], str(_seen.get("cfg")))
	check("C heberger : salon, regles du host, 3 modes (sans contre-la-montre), LANCER grise, convoi attendu",
		_seen.get("lobby", []) == [false, true, true, false, ["COURSE", "ÉLIMINATION", "ARÈNE"], true, true, true],
		str(_seen.get("lobby")))
	check("C regles au lobby : contre-la-montre refuse (course), 5 bots, Sakura",
		_seen.get("rules", []) == [GameStateNode.GameMode.RACE, GameStateNode.GameMode.RACE, 5, 2], str(_seen.get("rules")))
	var t: Array = _seen.get("title_online", [false, ""])
	check("D partie ouverte : JOUER EN LOCAL grisee, JOUER EN LIGNE ramene au salon",
		bool(t[0]) and String(t[1]).contains("salon"), str(t))
	check("D partie ouverte : la partie locale ne s'ouvre pas", _seen.get("local_blocked", []) == [false, true],
		str(_seen.get("local_blocked")))
	check("D JOUER EN LIGNE : retour au salon", _seen.get("lobby_again", []) == [true, true], str(_seen.get("lobby_again")))
	check("D QUITTER LA PARTIE : hors ligne, HEBERGER / REJOINDRE, local rouvert",
		_seen.get("left", []) == [false, true, false], str(_seen.get("left")))
	NetSession.leave()
	NetSession.last_error = ""
	GameState.use_profile(GameStateNode.Profile.LOCAL)
	GameState.apply_rules(_saved)
