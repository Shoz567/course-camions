class_name RaceHud
extends CanvasLayer

## HUD de course (tache 2.7, refait le 2026-10-19). Lit, ne decide rien
## (CLAUDE.md §7) : en haut a gauche une carte (position, nom, tour, temps,
## PV) ; en bas a droite un cadran facon arcade (HudDial : vitesse, nitro,
## cargo, recharge des pouvoirs) ; un message central (compte a rebours,
## mauvais sens, arrivee) et un bandeau poses par la scene.
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
## Carte du haut a gauche (2026-10-19) : position en grand, nom a la couleur
## du joueur, tour, temps, PV de la tete et de la remorque.
var _pos: Label
var _name: Label
var _info_card: PanelContainer
## Cadran du bas a droite : vitesse, nitro, cargo, pouvoirs (HudDial).
var _dial: HudDial
var _cargo: TruckCargo
var _health: TruckHealth
var _hp_label: Label
var _hp_bar: ProgressBar
var _trailer_hp_label: Label
var _trailer_hp_bar: ProgressBar
var _cargo_label: Label
var _center: Label
## Bandeau du haut, pour un joueur encore en course apres la premiere arrivee
## (« 1er : J2  ·  FIN DANS 28 s ») : rien ne lui cache la route.
var _ticker: Label
var _ticker_card: PanelContainer
var _help: Label
var _standings: Label
var _standings_card: PanelContainer
var _center_card: PanelContainer
var _center_text: String = ""
var _center_color: Color = Color.WHITE
var _slots: Array[Dictionary] = [{}, {}]

## Couleur du joueur (bordure de la carte, nom).
@export var accent: Color = UiKit.CYAN


func _ready() -> void:
	var k := ui_scale
	_center = _label(72, Vector2.ZERO)
	_center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center.grow_vertical = Control.GROW_DIRECTION_BOTH
	if truck != null:
		_cargo = truck.get_node_or_null(^"Cargo") as TruckCargo
		_health = TruckHealth.of(truck)
	_build_info(k)
	# cadran en bas a droite ; l'etat du largage juste au-dessus
	_dial = HudDial.new()
	_dial.name = "Dial"
	_dial.ui_scale = k
	add_child(_dial)
	_dial.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_dial.offset_left = -_dial.custom_minimum_size.x - 20 * k
	_dial.offset_top = -_dial.custom_minimum_size.y - 16 * k
	_dial.offset_right = -20 * k
	_dial.offset_bottom = -16 * k
	_cargo_label = _label(16, Vector2.ZERO)
	_cargo_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_cargo_label.offset_left = -360 * k
	_cargo_label.offset_right = -24 * k
	_cargo_label.offset_top = (-HudDial.SIZE - 46.0) * k
	_cargo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cargo_label.add_theme_color_override("font_color", UiKit.GOLD)
	_cargo_label.visible = _cargo != null
	_help = _label(13, Vector2.ZERO)
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.offset_left = 24 * k
	_help.offset_top = (-28.0 - 16.0 * help_text.count("\n")) * k
	_help.text = help_text
	_help.modulate = Color(1, 1, 1, 0.75)
	_standings = _label(26, Vector2.ZERO)
	_standings.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_standings.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_standings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_standings.offset_top = 150 * k
	_build_cards(k)


## Carte du haut a gauche, inclinee comme les menus : « 2e/4 » en grand a
## gauche ; a droite le nom du joueur (sa couleur) et le tour ; en dessous les
## temps et les PV de la tete et de la remorque.
func _build_info(k: float) -> void:
	_info_card = PanelContainer.new()
	_info_card.name = "Info"
	_info_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiKit.box(Color(UiKit.NIGHT, 0.72), Color(accent, 0.8), maxi(1, roundi(2 * k)), UiKit.SKEW, 4,
		Color(accent, 0.25), roundi(12 * k))
	sb.content_margin_left = 26 * k
	sb.content_margin_right = 30 * k
	sb.content_margin_top = 8 * k
	sb.content_margin_bottom = 10 * k
	_info_card.add_theme_stylebox_override("panel", sb)
	_info_card.position = Vector2(20, 14) * k
	add_child(_info_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", roundi(2 * k))
	_info_card.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", roundi(16 * k))
	col.add_child(top)
	_pos = _boxed(top, 60)
	_pos.add_theme_font_override("font", UiKit.font(900))
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(right)
	_name = _boxed(right, 20)
	_name.add_theme_color_override("font_color", accent.lightened(0.25))
	_lap = _boxed(right, 28)
	_lap_time = _boxed(col, 22)
	_times = _boxed(col, 16)
	_times.modulate = Color(1, 1, 1, 0.8)
	var hp_row := _row(col, k)
	_hp_label = _boxed(hp_row, 16)
	_hp_label.custom_minimum_size.x = 92 * k
	_hp_bar = _bar(hp_row, k, 150)
	var trl_row := _row(col, k)
	_trailer_hp_label = _boxed(trl_row, 13)
	_trailer_hp_label.custom_minimum_size.x = 92 * k
	_trailer_hp_bar = _bar(trl_row, k, 150)
	for c: Control in [_hp_label, _hp_bar, _trailer_hp_label, _trailer_hp_bar]:
		c.visible = _health != null


func _row(parent: Control, k: float) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", roundi(8 * k))
	parent.add_child(r)
	return r


func _boxed(parent: Control, font_size: int) -> Label:
	var l := _label(font_size, Vector2.ZERO)
	remove_child(l)
	parent.add_child(l)
	return l


func _bar(parent: Control, k: float, width: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 1.0
	b.value = 1.0
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, 10) * k
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# sa hauteur minimale suit la police du theme : une barre fine
	b.add_theme_font_size_override("font_size", 1)
	for pair: Array in [["background", UiKit.box(Color(0.05, 0.05, 0.08, 0.85), Color(1, 1, 1, 0.08), 1)],
			["fill", UiKit.box(Color.WHITE)]]:
		var sb := pair[1] as StyleBoxFlat
		sb.set_content_margin_all(0)
		b.add_theme_stylebox_override(pair[0], sb)
	parent.add_child(b)
	return b


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
	var n := race.racer_count()
	_pos.visible = n > 1
	_name.visible = player_label != ""
	if n > 1:
		var place := race.position(truck)
		_pos.text = "%d%s/%d" % [place, "er" if place == 1 else "e", n]
	_name.text = player_label
	_lap.text = "TOUR %d/%d" % [race.display_lap(truck), race.total_laps]
	_lap_time.text = "Tour  %s" % chrono(race.current_lap_ticks(truck))
	_times.text = "Meilleur  %s     Dernier  %s" % [chrono(r.best_lap), chrono(r.last_lap)]
	var charge := truck.get_boost_charge()
	var boost_label := "BOOST PRÊT" if charge >= 1.0 else ("nitro %d s" % maxi(ceili(
		(1.0 - charge) * truck.tuning.boost_recharge_ticks / 60.0), 1))
	if truck.is_boosting():
		boost_label = "BOOST !"
	var cargo := -1.0
	if _cargo != null:
		# remorque : prete, larguee (compte a rebours du raccrochage), recharge
		cargo = _cargo.get_charge()
		_cargo_label.text = _cargo.status_text()
	var powers := TruckPowers.of(truck)
	for k in 2:
		var d := _slots[k]
		d.clear()
		if powers == null or powers.slots[k] < 0:
			continue
		var p := powers.slots[k]
		d["name"] = PowerCatalog.short_name(p)
		d["ready"] = 1.0 - float(powers.cooldown[k]) / maxf(float(PowerCatalog.cooldown_ticks(p)), 1.0)
		d["left"] = powers.seconds_left(k)
		d["active"] = powers.active(k)
	_dial.set_state(roundi(absf(truck.get_speed_kmh())), charge, truck.is_boosting(), boost_label, cargo, _slots)
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
