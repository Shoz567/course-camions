extends PhysicsTest

## Ambiance du circuit au menu (2026-10-19) :
##   - Cyber City par defaut : habillage neon, toit de la tour, ciel de nuit ;
##   - clic sur PLAYA DEL SOL : habillage plage (tuiles de bois flotte,
##     choix turquoise), ile au soleil (decor, ciel playa_sun, soleil) ;
##     l'interface est reconstruite (une seule), les choix (joueurs, vitesse)
##     sont gardes ;
##   - touche T : Sakura, habillage Japon (bois de miel, laque, police
##     Mincho), jardin japonais, ciel sakura_day ;
##   - un panneau ouvert (parametres) le reste quand le circuit change ;
##   - chaque circuit a son image d'ecran de chargement (1920 x 1080) ;
##   - les decors n'ajoutent aucun corps physique (le plateau seul).

var _menu: MainMenu
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 60
	get_window().size = Vector2i(1920, 1080)
	GameState.selected_track = 0
	GameState.requested_players = 0
	UiKit.apply_skin(UiKit.Look.NEON)
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


func _click(c: Control) -> void:
	var m := InputEventMouseMotion.new()
	m.position = c.get_global_rect().get_center()
	m.global_position = m.position
	Input.parse_input_event(m)
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = m.position
		e.global_position = m.position
		e.pressed = pressed
		Input.parse_input_event(e)
	Input.flush_buffered_events()


func _env() -> Environment:
	return (_menu.get_node("WorldEnvironment") as WorldEnvironment).environment


func _sets() -> Array:
	var out := []
	for id in 3:
		var n := _menu.showroom.set_node(id)
		out.append(n != null and n.visible)
	return out


func _ui_count() -> int:
	var n := 0
	for c in _menu.get_children():
		if c.name.begins_with("UI") and c is CanvasLayer:
			n += 1
	return n


func _test_tick(t: int) -> void:
	match t:
		3:
			_seen["neon"] = [UiKit.skin, _sets(), _env().resource_path.ends_with("cyber_night.tres"),
				_menu.player_buttons[0].get_theme_stylebox("normal") is StyleBoxFlat]
			_menu.select_players(3)
			_menu.select_speed(2)
		6: _click(_menu.track_buttons[1])
		12:
			var moon := _menu.get_node("Moon") as DirectionalLight3D
			_seen["playa"] = [UiKit.skin, _sets(), _env().resource_path.ends_with("playa_sun.tres"), moon.light_energy > 0.8,
				_menu.player_buttons[0].get_theme_stylebox("normal") is StyleBoxTexture,
				(_menu.start_button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.is_equal_approx(UiKit.PRIMARY_FILL)]
			_seen["kept"] = [_ui_count(), _menu.track_buttons[1].button_pressed, _menu.player_buttons[2].button_pressed,
				_menu.speed_buttons[2].button_pressed, _menu.selected_players, GameState.speed_class]
		14: _key(KEY_T)
		20:
			_seen["sakura"] = [UiKit.skin, _sets(), _env().resource_path.ends_with("sakura_day.tres"),
				UiKit.FONT_NAMES.has("Yu Mincho"), _menu.track_buttons[2].button_pressed,
				_menu.player_buttons[0].get_theme_stylebox("normal") is StyleBoxTexture]
			_menu.toggle_settings()
		22: _menu.select_track(0)
		28:
			_seen["panel"] = [UiKit.skin, _menu.settings.visible, _menu.home.visible, _ui_count()]


func _test_finish() -> void:
	check("Cyber City par defaut : neon, toit, nuit, tuiles a plat", _seen.get("neon", []) == [UiKit.Look.NEON,
		[true, false, false], true, true], str(_seen.get("neon")))
	check("clic sur Playa : habillage plage, ile au soleil, bois flotte, PRET soleil",
		_seen.get("playa", []) == [UiKit.Look.PLAYA, [false, true, false], true, true, true, true], str(_seen.get("playa")))
	check("interface reconstruite une fois, choix gardes (circuit, 3 joueurs, 150cc)",
		_seen.get("kept", []) == [1, true, true, true, 3, 2], str(_seen.get("kept")))
	check("touche T : Sakura, jardin japonais, Mincho, bois de miel",
		_seen.get("sakura", []) == [UiKit.Look.SAKURA, [false, false, true], true, true, true, true], str(_seen.get("sakura")))
	check("panneau des parametres garde ouvert au changement de circuit",
		_seen.get("panel", []) == [UiKit.Look.NEON, true, false, 1], str(_seen.get("panel")))
	var images := true
	for k in GameStateNode.TRACKS.size():
		var img := LoadingScreen.track_image(k)
		images = images and img != null and img.get_width() == 1920 and img.get_height() == 1080
	check("une image d'ecran de chargement par circuit (1920 x 1080)", images)
	# les camions exposes mis a part
	var bodies := _menu.showroom.find_children("*", "CollisionObject3D", true, false).filter(
		func(b: Node) -> bool: return not b is Truck)
	check("decors sans corps physique (le plateau seul)", bodies.size() == 1 and bodies[0].name == "PlateCollision",
		"%d corps" % bodies.size())
