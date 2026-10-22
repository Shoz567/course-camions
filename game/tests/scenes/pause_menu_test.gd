extends PhysicsTest

## Menu pause de la course (2026-10-22 : « quand on appuie sur la touche
## option pour la manette et echappe pour clavier souris, ca ne quitte pas la
## course directement, mais ca ouvre un menu et ca met le jeu en pause. Et
## quand c'est en multijoueur [...] ca met pas le jeu en pause ») : course a
## Cyber City, un joueur, sans bot ; le menu s'ouvre pendant le compte a
## rebours.
##   A. Echap ouvre le menu (« QUITTER LA COURSE ») et fige la course ;
##   B. fige : 200 ticks (plus que les 180 du compte a rebours) plus tard, il
##      n'est pas fini ;
##   C. Options le referme, la course repart ;
##   D. PARAMETRES : le panneau s'ouvre a la place du menu ; Options referme
##      tout ;
##   E. sortie : confirmation (ANNULER par defaut), Echap l'annule, le menu
##      reste ouvert ;
##   F. menu ouvert : la frame du joueur de ce PC est neutre (en ligne, son
##      camion roule a vide) ; refermee, c'est la sienne ;
##   G. le compte a rebours ne compte que les ticks hors pause (GameClock) :
##      le depart tombe apres ses 180 ticks de jeu, pas des la reprise ;
##   H. en ligne (host) : pas de pause, « ARRETER LA COURSE », la sortie
##      confirmee arrete la course pour tous (NetSession.race_stopped) ;
##   I. Options n'est plus reset ni reaffectable (bouton reserve), et sort des
##      profils enregistres.

const PORT := 7798
const FROZEN_TICKS := 200
## LocalRace.State (pas de class_name : la scene de course porte le script)
const COUNTDOWN := 0
const RACING := 1

var _race: Node3D
var _pm: PauseMenu
var _saved: Dictionary = {}
var _saved_players: int = 0
var _seen: Dictionary = {}
var _go: int = -1
## Ticks de jeu (hors pause) jusqu'au depart.
var _running: int = 0


func _test_setup() -> void:
	duration_ticks = 900
	# le test compte ses ticks pendant la pause ; la course, elle, se fige
	process_mode = Node.PROCESS_MODE_ALWAYS
	_saved = GameState.rules()
	_saved_players = GameState.requested_players
	GameState.requested_players = 1
	GameState.apply_rules({"track": 0, "mode": GameStateNode.GameMode.RACE, "bots": 0}, 0)
	_race = (load(GameStateNode.track_scene(0)) as PackedScene).instantiate() as Node3D
	_race.set("ready_gate", false)
	_race.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_race)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _pad(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _race_state() -> int:
	return int(_race.get("state"))


func _test_tick(t: int) -> void:
	if _pm == null:
		_pm = _race.get("pause_menu") as PauseMenu
	var paused := get_tree().paused
	if not paused and _go < 0:
		_running += 1
	match t:
		10: _key(KEY_ESCAPE, true)
		11: _key(KEY_ESCAPE, false)
		13:
			_seen["A"] = [_pm.visible, paused, _pm.quit_button.text, _pm.resume_button.has_focus(),
				_race_state() == COUNTDOWN]
		_ when t == 13 + FROZEN_TICKS:
			_seen["B"] = [_race_state() == COUNTDOWN, paused]
			_pad(JOY_BUTTON_START, true)
		_ when t == 14 + FROZEN_TICKS:
			_pad(JOY_BUTTON_START, false)
		_ when t == 16 + FROZEN_TICKS:
			_seen["C"] = [_pm.visible, paused]
			_pad(JOY_BUTTON_START, true)
		_ when t == 17 + FROZEN_TICKS:
			_pad(JOY_BUTTON_START, false)
		_ when t == 19 + FROZEN_TICKS:
			_pm.open_settings()
			_seen["D1"] = [_pm.visible, _pm.settings.visible, _pm.page.visible, paused]
			_pad(JOY_BUTTON_START, true)
		_ when t == 20 + FROZEN_TICKS:
			_pad(JOY_BUTTON_START, false)
		_ when t == 22 + FROZEN_TICKS:
			_seen["D2"] = [_pm.visible, _pm.settings.visible, paused]
			_key(KEY_ESCAPE, true)
		_ when t == 23 + FROZEN_TICKS:
			_key(KEY_ESCAPE, false)
		_ when t == 25 + FROZEN_TICKS:
			_pm.ask_quit()
			_seen["E1"] = [_pm.confirm.visible, _pm.cancel_button.has_focus(), _pm.confirm_button.text]
			_key(KEY_ESCAPE, true)
		_ when t == 26 + FROZEN_TICKS:
			_key(KEY_ESCAPE, false)
		_ when t == 28 + FROZEN_TICKS:
			_seen["E2"] = [_pm.confirm.visible, _pm.visible, paused, _pm.quit_button.has_focus()]
			var f := InputFrame.new()
			f.throttle = 1.0
			f.boost = true
			var g := _race.call("_menu_frame", 0, f, t) as InputFrame
			_seen["F1"] = g != f and g.throttle == 0.0 and not g.boost
			_pm.close()
			_seen["F2"] = (_race.call("_menu_frame", 0, f, t) as InputFrame) == f
			_seen["unpaused"] = not get_tree().paused
		_ when t == 40 + FROZEN_TICKS:
			_online_check()
	if t > 40 + FROZEN_TICKS and _go < 0 and _race_state() == RACING:
		_go = t
		duration_ticks = mini(duration_ticks, t + 1)


## H : menu seul, ce PC hebergeant une partie (un tick, puis la partie se
## ferme).
func _online_check() -> void:
	var pm := PauseMenu.new()
	add_child(pm)
	var opened := NetSession.host(PORT) == OK
	var stopped := [0]
	var auto := NetSession.auto_change_scene
	NetSession.auto_change_scene = false
	NetSession.race_stopped.connect(func() -> void: stopped[0] += 1)
	pm.quit_confirmed.connect(NetSession.stop_race)
	pm.open()
	_seen["H1"] = [opened, pm.visible, get_tree().paused, pm.quit_button.text, pm._title.text]
	pm.ask_quit()
	pm.confirm_quit()
	_seen["H2"] = [stopped[0], pm.visible, get_tree().paused]
	NetSession.leave()
	NetSession.auto_change_scene = auto
	pm.queue_free()


func _test_finish() -> void:
	get_tree().paused = false
	check("A Echap : menu ouvert, course figee, QUITTER LA COURSE, focus REPRENDRE",
		_seen.get("A", []) == [true, true, "QUITTER LA COURSE", true, true], str(_seen.get("A")))
	check("B figee : compte a rebours pas fini %d ticks plus tard" % FROZEN_TICKS,
		_seen.get("B", []) == [true, true], str(_seen.get("B")))
	check("C Options referme le menu, la course repart", _seen.get("C", []) == [false, false], str(_seen.get("C")))
	check("D PARAMETRES a la place du menu, toujours en pause",
		_seen.get("D1", []) == [true, true, false, true], str(_seen.get("D1")))
	check("D Options referme tout (parametres compris)", _seen.get("D2", []) == [false, false, false],
		str(_seen.get("D2")))
	check("E sortie : confirmation, ANNULER par defaut",
		_seen.get("E1", []) == [true, true, "QUITTER LA COURSE"], str(_seen.get("E1")))
	check("E Echap annule la confirmation, le menu reste ouvert",
		_seen.get("E2", []) == [false, true, true, true], str(_seen.get("E2")))
	check("F menu ouvert : frame neutre pour le joueur de ce PC", _seen.get("F1", false))
	check("F menu ferme : sa frame", _seen.get("F2", false) and _seen.get("unpaused", false))
	check("G depart apres les %d ticks de jeu du compte a rebours (pauses non comptees)" % RaceManagerNode.COUNTDOWN_TICKS,
		_go > 0 and absi(_running - RaceManagerNode.COUNTDOWN_TICKS) <= 3,
		"GO au tick %d, %d ticks hors pause" % [_go, _running])
	check("H en ligne (host) : pas de pause, ARRETER LA COURSE, MENU",
		_seen.get("H1", []) == [true, true, false, "ARRÊTER LA COURSE", "MENU"], str(_seen.get("H1")))
	check("H sortie confirmee : course arretee pour tous", _seen.get("H2", []) == [1, false, false],
		str(_seen.get("H2")))
	check("H client : QUITTER LA PARTIE", PauseMenu.exit_label(PauseMenu.Exit.CLIENT) == "QUITTER LA PARTIE")
	# I
	var d := PadBindings.defaults()
	var options_free := true
	for a: String in PadBindings.ACTIONS:
		options_free = options_free and not (d[a] as PackedInt32Array).has(JOY_BUTTON_START)
	check("I Options : dans aucune action par defaut", options_free)
	check("I Options : refuse a la reaffectation",
		str(PadBindings.assign(d, "boost", JOY_BUTTON_START)) == str(d))
	var old := PadBindings.sanitized({"reset": PackedInt32Array([JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_TOUCHPAD])})
	check("I profil enregistre : Options retire du reset",
		old["reset"] == PackedInt32Array([JOY_BUTTON_BACK, JOY_BUTTON_TOUCHPAD]), str(old["reset"]))
	GameState.apply_rules(_saved, 0)
	GameState.requested_players = _saved_players
