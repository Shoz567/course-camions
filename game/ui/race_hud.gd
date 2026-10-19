class_name RaceHud
extends CanvasLayer

## HUD de course (tache 2.7). Lit, ne decide rien (CLAUDE.md §7) : vitesse,
## tour (1/3), temps du tour, meilleur et dernier tour, jauges de boost et de
## cargo, et un message central (compte a rebours, mauvais sens, arrivee) pose
## par la scene.
## Les temps affiches derivent des ticks : 60 ticks = 1 s.

@export var truck: Truck
@export var race: RaceLaps
## Nom affiche (ecran partage) et aide des commandes de CE joueur.
@export var player_label: String = ""
@export_multiline var help_text: String = ""
## Echelle du HUD : 1 en plein ecran, moins dans une vue d'ecran partage.
@export var ui_scale: float = 1.0

var _lap: Label
var _lap_time: Label
var _times: Label
var _speed: Label
var _boost_bar: ProgressBar
var _boost_label: Label
var _cargo_bar: ProgressBar
var _cargo_label: Label
var _cargo: TruckCargo
var _health: TruckHealth
var _hp_label: Label
var _hp_bar: ProgressBar
var _trailer_hp_label: Label
var _trailer_hp_bar: ProgressBar
var _center: Label
## Bandeau du haut, pour un joueur encore en course apres la premiere arrivee
## (« 1er : J2  ·  FIN DANS 28 s ») : rien ne lui cache la route.
var _ticker: Label
var _ticker_card: PanelContainer
var _help: Label
var _standings: Label
var _standings_card: PanelContainer
## Pouvoirs du camion (TruckPowers) : « ◄ BOUCLIER  PRÊT   ► MISSILE  12 s ».
var _powers_label: Label
var _center_card: PanelContainer
var _center_text: String = ""
var _center_color: Color = Color.WHITE


func _ready() -> void:
	var k := ui_scale
	_lap = _label(40, Vector2(24, 16) * k)
	_lap_time = _label(28, Vector2(24, 68) * k)
	_times = _label(20, Vector2(24, 108) * k)
	_center = _label(72, Vector2.ZERO)
	_center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center.grow_vertical = Control.GROW_DIRECTION_BOTH
	_speed = _label(64, Vector2.ZERO)
	_speed.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_speed.offset_left = -330 * k
	_speed.offset_top = -150 * k
	_speed.offset_right = -24 * k
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_boost_bar = ProgressBar.new()
	_boost_bar.min_value = 0.0
	_boost_bar.max_value = 1.0
	_boost_bar.show_percentage = false
	_boost_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_boost_bar.offset_left = -330 * k
	_boost_bar.offset_top = -52 * k
	_boost_bar.offset_right = -24 * k
	_boost_bar.offset_bottom = -30 * k
	var b_bg := StyleBoxFlat.new()
	b_bg.bg_color = Color(0.05, 0.07, 0.11, 0.85)
	b_bg.border_color = Color(0.25, 0.35, 0.45, 0.7)
	b_bg.set_border_width_all(roundi(maxf(1.0, 2.0 * k)))
	b_bg.set_corner_radius_all(roundi(maxf(2.0, 5.0 * k)))
	var b_fill := StyleBoxFlat.new()
	b_fill.bg_color = Color(0.12, 0.88, 1.0)
	b_fill.set_corner_radius_all(roundi(maxf(2.0, 5.0 * k)))
	_boost_bar.add_theme_stylebox_override("background", b_bg)
	_boost_bar.add_theme_stylebox_override("fill", b_fill)
	add_child(_boost_bar)

	_boost_label = _label(18, Vector2.ZERO)
	_boost_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_boost_label.offset_left = -330 * k
	_boost_label.offset_top = -80 * k
	_boost_label.offset_right = -24 * k
	_boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# cargo : a gauche de la jauge de boost, meme hauteur
	_cargo_bar = ProgressBar.new()
	_cargo_bar.min_value = 0.0
	_cargo_bar.max_value = 1.0
	_cargo_bar.show_percentage = false
	_cargo_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_cargo_bar.offset_left = -560 * k
	_cargo_bar.offset_top = -52 * k
	_cargo_bar.offset_right = -350 * k
	_cargo_bar.offset_bottom = -30 * k
	var c_bg := StyleBoxFlat.new()
	c_bg.bg_color = Color(0.06, 0.06, 0.04, 0.85)
	c_bg.border_color = Color(0.55, 0.45, 0.15, 0.7)
	c_bg.set_border_width_all(roundi(maxf(1.0, 2.0 * k)))
	c_bg.set_corner_radius_all(roundi(maxf(2.0, 5.0 * k)))
	var c_fill := StyleBoxFlat.new()
	c_fill.bg_color = Color(1.0, 0.75, 0.1)
	c_fill.set_corner_radius_all(roundi(maxf(2.0, 5.0 * k)))
	_cargo_bar.add_theme_stylebox_override("background", c_bg)
	_cargo_bar.add_theme_stylebox_override("fill", c_fill)
	add_child(_cargo_bar)

	_cargo_label = _label(18, Vector2.ZERO)
	_cargo_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_cargo_label.offset_left = -560 * k
	_cargo_label.offset_top = -80 * k
	_cargo_label.offset_right = -350 * k
	_cargo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if truck != null:
		_cargo = truck.get_node_or_null(^"Cargo") as TruckCargo
	_cargo_bar.visible = _cargo != null
	_cargo_label.visible = _cargo != null
	# PV : discret, sous les temps (les degradations visibles viendront ensuite)
	_hp_label = _label(18, Vector2(24, 138) * k)
	_hp_bar = ProgressBar.new()
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 1.0
	_hp_bar.value = 1.0
	_hp_bar.show_percentage = false
	_hp_bar.position = Vector2(108, 146) * k
	_hp_bar.size = Vector2(130, 9) * k
	var h_bg := StyleBoxFlat.new()
	h_bg.bg_color = Color(0.05, 0.05, 0.06, 0.8)
	h_bg.set_corner_radius_all(roundi(maxf(2.0, 3.0 * k)))
	var h_fill := StyleBoxFlat.new()
	h_fill.bg_color = Color.WHITE
	h_fill.set_corner_radius_all(roundi(maxf(2.0, 3.0 * k)))
	_hp_bar.add_theme_stylebox_override("background", h_bg)
	_hp_bar.add_theme_stylebox_override("fill", h_fill)
	add_child(_hp_bar)
	# PV de la remorque attelee, sous ceux de la tete (deux reserves distinctes)
	_trailer_hp_label = _label(14, Vector2(24, 160) * k)
	_trailer_hp_bar = _hp_bar.duplicate() as ProgressBar
	_trailer_hp_bar.position = Vector2(108, 166) * k
	add_child(_trailer_hp_bar)
	if truck != null:
		_health = TruckHealth.of(truck)
	_hp_label.visible = _health != null
	_hp_bar.visible = _health != null
	_trailer_hp_label.visible = _health != null
	_trailer_hp_bar.visible = _health != null
	_help = _label(14, Vector2.ZERO)
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.offset_left = 24 * k
	_help.offset_top = (-30.0 - 18.0 * help_text.count("\n")) * k
	_help.text = help_text
	_standings = _label(26, Vector2.ZERO)
	_standings.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_standings.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_standings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_standings.offset_top = 150 * k
	_build_cards(k)
	_powers_label = _label(20, Vector2.ZERO)
	_powers_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_powers_label.offset_left = 24 * k
	_powers_label.offset_top = (-70.0 - 18.0 * help_text.count("\n")) * k
	_powers_label.add_theme_color_override("font_color", UiKit.CYAN)


## Charte arcade neon (UiKit, 2026-10-17) : classement et message central dans
## des cartes inclinees, empilees au centre de la vue (elles ne se chevauchent
## plus a l'arrivee) ; barres inclinees comme les boutons des menus.
func _build_cards(k: float) -> void:
	var stack := VBoxContainer.new()
	stack.name = "Cards"
	stack.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	stack.grow_vertical = Control.GROW_DIRECTION_BOTH
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", roundi(12 * k))
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	_standings_card = _card(UiKit.CYAN, k)
	_center_card = _card(UiKit.PINK, k)
	for pair: Array in [[_standings_card, _standings], [_center_card, _center]]:
		var card := pair[0] as PanelContainer
		var l := pair[1] as Label
		stack.add_child(card)
		remove_child(l)
		l.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		l.position = Vector2.ZERO
		card.add_child(l)
		card.visible = false
	_ticker_card = _card(UiKit.GOLD, k)
	_ticker_card.name = "Ticker"
	_ticker_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_ticker_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ticker_card.offset_top = 18 * k
	_ticker_card.visible = false
	add_child(_ticker_card)
	_ticker = _label(22, Vector2.ZERO)
	remove_child(_ticker)
	_ticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ticker.add_theme_color_override("font_color", UiKit.GOLD)
	_ticker_card.add_child(_ticker)
	_center.add_theme_font_override("font", UiKit.font(900))
	_center.add_theme_font_size_override("font_size", maxi(10, roundi(54 * ui_scale)))
	for bar: ProgressBar in [_boost_bar, _cargo_bar, _hp_bar, _trailer_hp_bar]:
		for s: String in ["background", "fill"]:
			var sb := bar.get_theme_stylebox(s) as StyleBoxFlat
			if sb != null:
				sb = sb.duplicate() as StyleBoxFlat
				sb.skew = Vector2(UiKit.SKEW, 0.0)
				sb.anti_aliasing = true
				bar.add_theme_stylebox_override(s, sb)


func _card(border: Color, k: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := UiKit.box(Color(UiKit.NIGHT, 0.8), Color(border, 0.85), maxi(1, roundi(2 * k)), UiKit.SKEW, 4,
		Color(border, 0.3), roundi(14 * k))
	sb.content_margin_left = 34 * k
	sb.content_margin_right = 34 * k
	sb.content_margin_top = 10 * k
	sb.content_margin_bottom = 10 * k
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## Classement (liste multiligne, vide pour l'effacer), en haut au centre.
func set_standings(text: String) -> void:
	_standings.text = text
	if _standings_card != null:
		_standings_card.visible = text != ""


## Bandeau du haut (une ligne, vide pour l'effacer).
func set_ticker(text: String) -> void:
	if _ticker == null:
		return
	_ticker.text = text
	_ticker_card.visible = text != ""


func ticker_text() -> String:
	return _ticker.text if _ticker != null and _ticker_card.visible else ""


func standings_visible() -> bool:
	return _standings_card != null and _standings_card.visible


## Message central (vide pour l'effacer).
func set_center_message(text: String, color: Color = Color.WHITE) -> void:
	_center_text = text
	_center_color = color


func _process(_delta: float) -> void:
	if truck == null or race == null:
		return
	var r := race.racer(truck)
	if r == null:
		return
	var head := "TOUR %d/%d" % [race.display_lap(truck), race.total_laps]
	if race.racer_count() > 1:
		head = "%s   POS %d/%d   %s" % [player_label, race.position(truck), race.racer_count(), head]
	_lap.text = head
	_lap_time.text = "Tour  %s" % chrono(race.current_lap_ticks(truck))
	_times.text = "Meilleur  %s     Dernier  %s" % [chrono(r.best_lap), chrono(r.last_lap)]
	var spd := roundi(absf(truck.get_speed_kmh()))
	_speed.text = "%d km/h" % spd
	if truck.is_boosting():
		_speed.modulate = Color(1.0, 0.65, 0.15)
	elif spd >= 140:
		_speed.modulate = Color(0.15, 0.95, 1.0)
	else:
		_speed.modulate = Color(0.95, 0.96, 0.98)
	var charge := truck.get_boost_charge()
	_boost_bar.value = charge
	if truck.is_boosting():
		_boost_label.text = "BOOST !"
		_boost_bar.modulate = Color(1.0, 0.55, 0.1)
	elif charge >= 1.0:
		_boost_label.text = "BOOST PRET"
		_boost_bar.modulate = Color(0.3, 1.0, 0.4)
	else:
		# recharge (6 s) : secondes restantes, derivees de la jauge
		var left := ceili((1.0 - charge) * truck.tuning.boost_recharge_ticks / 60.0)
		_boost_label.text = "recharge %d s" % maxi(left, 1)
		_boost_bar.modulate = Color(0.6, 0.6, 0.6)
	if _cargo != null:
		# remorque : prete, larguee (compte a rebours du raccrochage), recharge
		_cargo_bar.value = _cargo.get_charge()
		_cargo_label.text = _cargo.status_text()
		if _cargo.is_ready():
			_cargo_bar.modulate = Color(1.0, 0.6, 0.1)
		elif truck.is_trailer_detached():
			_cargo_bar.modulate = Color(0.2, 0.9, 1.0)
		else:
			_cargo_bar.modulate = Color(0.6, 0.6, 0.6)
	if _health != null:
		var ratio := _health.hp / maxf(_health.max_hp, 1.0)
		_hp_label.text = "%d HP" % ceili(_health.hp)
		_hp_bar.value = ratio
		var tint := Color(0.35, 1.0, 0.45) if ratio > 0.6 else (Color(1.0, 0.8, 0.2) if ratio > 0.3 else Color(1.0, 0.3, 0.2))
		_hp_label.modulate = tint
		_hp_bar.modulate = tint
		var has_trailer := not truck.is_trailer_detached()
		var t_ratio := _health.trailer_hp / maxf(_health.trailer_max_hp, 1.0) if has_trailer else 0.0
		_trailer_hp_label.text = "REM %d" % ceili(_health.trailer_hp) if has_trailer else "REM --"
		_trailer_hp_bar.value = t_ratio
		var t_tint := Color(0.4, 0.8, 1.0) if t_ratio > 0.6 else (Color(1.0, 0.8, 0.2) if t_ratio > 0.3 else Color(1.0, 0.3, 0.2))
		_trailer_hp_label.modulate = t_tint
		_trailer_hp_bar.modulate = t_tint
	var powers := TruckPowers.of(truck)
	_powers_label.visible = powers != null
	if powers != null:
		_powers_label.text = powers_text(powers)
	var text := _center_text
	var color := _center_color
	# epave : prioritaire sur le GO et le compte a rebours de la scene
	if _health != null and _health.is_wrecked():
		text = "DÉTRUIT !\nretour dans %d s" % maxi(_health.wreck_seconds_left(), 1)
		color = Color(1.0, 0.4, 0.15)
	if text == "" and r.wrong_way:
		text = "«« MAUVAIS SENS »»"
		color = Color(1.0, 0.25, 0.15)
	_center.text = text
	_center.add_theme_color_override("font_color", color)
	_center_card.visible = text != ""
	(_center_card.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color(color, 0.85)
	(_center_card.get_theme_stylebox("panel") as StyleBoxFlat).shadow_color = Color(color, 0.3)


## Etat des deux emplacements de pouvoir (vide : rien).
static func powers_text(p: TruckPowers) -> String:
	var parts := PackedStringArray()
	for k in 2:
		var left := p.seconds_left(k)
		if left < 0:
			continue
		var state := "ACTIF" if p.active(k) else ("PRÊT" if left == 0 else "%d s" % left)
		parts.append("%s %s  %s" % ["◄" if k == 0 else "►", PowerCatalog.display_name(p.slots[k]), state])
	return "     ".join(parts)


## Temps affiche, derive des ticks.
@warning_ignore("integer_division")
static func chrono(ticks: int) -> String:
	if ticks < 0:
		return "--:--.--"
	var cs := ticks * 100 / 60
	return "%d:%02d.%02d" % [cs / 6000, (cs / 100) % 60, cs % 100]


func _label(size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	size = maxi(10, roundi(size * ui_scale))
	l.add_theme_font_override("font", UiKit.font(800))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, roundi(size / 6.0)))
	add_child(l)
	return l
