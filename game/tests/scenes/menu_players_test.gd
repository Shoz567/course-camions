extends PhysicsTest

## Accueil du menu, nombre de joueurs et bots (2026-10-19) :
##   A. 3 joueurs : boutons 1, 2, 3 a la couleur de leur pastille (bleu,
##      rouge, jaune), 4 a 6 en tuile sombre ; texte sombre sur le jaune ;
##   B. bots : 5 demandes a 3 joueurs -> 3 (6 au plus en tout), 4 et 5
##      grises ; 6 joueurs -> plus de bot, niveau grise.

var _menu: MainMenu
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 10
	GameState.bot_count = 0
	_menu = (load("res://ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	_menu.auto_change_scene = false
	add_child(_menu)


func _fill(b: Button) -> Color:
	return (b.get_theme_stylebox("normal") as StyleBoxFlat).bg_color


func _test_tick(t: int) -> void:
	if t != 3:
		return
	_menu.select_players(3)
	var fills: Array = []
	for b in _menu.player_buttons:
		fills.append(_fill(b))
	_seen["fills"] = fills
	_seen["ink3"] = _menu.player_buttons[2].get_theme_color("font_color")
	_menu.select_bots(5)
	_seen["bots3"] = GameState.bot_count
	_seen["dis3"] = [_menu.bot_buttons[3].disabled, _menu.bot_buttons[4].disabled, _menu.bot_buttons[5].disabled]
	_menu.select_players(6)
	_seen["bots6"] = GameState.bot_count
	_seen["level6"] = _menu.bot_level_buttons[0].disabled


func _test_finish() -> void:
	var f: Array = _seen.get("fills", [])
	var ok := f.size() == 6
	for i in f.size():
		var c := f[i] as Color
		if i < 3:
			ok = ok and Color(c, 1.0).is_equal_approx(UiKit.PLAYER_COLORS[i])
		else:
			ok = ok and c.is_equal_approx(UiKit.TILE)
	check("3 joueurs : 1 a 3 a la couleur de leur pastille, 4 a 6 sombres", ok, str(f))
	check("texte sombre sur le jaune", (_seen.get("ink3", Color.WHITE) as Color).is_equal_approx(UiKit.NIGHT))
	check("bots : 5 demandes a 3 joueurs -> 3, 4 et 5 grises", int(_seen.get("bots3", -1)) == 3
		and _seen.get("dis3", []) == [false, true, true], "%s %s" % [_seen.get("bots3"), _seen.get("dis3")])
	check("6 joueurs : plus de bot, niveau grise", int(_seen.get("bots6", -1)) == 0 and bool(_seen.get("level6", false)))
	GameState.bot_count = 0
