class_name LoadoutSelect
extends Control

## Page de selection du menu (2026-10-16), apres PRET : facon Mario Kart 8,
## une carte par joueur (LoadoutPanel) - ecran seul, ou scinde (2 cote a
## cote, 2 x 2 a 3-4, 3 x 2 a 5-6). Chaque joueur choisit avec SA manette
## (joueur i = manette i ; seul : n'importe laquelle) ou son clavier (J1
## fleches, J2 ZQSD) :
##   1. sa REMORQUE, 2. un POUVOIR (fleche gauche de la croix), 3. un autre
##      POUVOIR (fleche droite). Haut / bas : choix ; gauche / droite :
##      colonne ; Croix (ou Carre) : valide la colonne et passe a la suivante,
##      la derniere valide le joueur (PRET) ; Rond : revient d'une colonne,
##      annule PRET, ou, a la premiere colonne, ramene a l'accueil.
##   Aucun pouvoir n'existe encore : AUCUN se valide comme un autre choix.
## Tout le monde PRET : bandeau, et la course part apres LAUNCH_DELAY_S
## (annule si quelqu'un se ravise). Le choix est ecrit dans GameState
## (trailer_choice, power_left, power_right).

signal launch_requested
signal back_requested
signal trailer_changed(player: int, index: int)

const LAUNCH_DELAY_S := 1.0
const STICK_ON := 0.6
const STICK_OFF := 0.3
## Bandeau du haut et barre d'aide du bas (px, reference 1920 x 1080).
const TOP := 150.0
const BOTTOM := 86.0

var panels: Array[LoadoutPanel] = []
var player_count: int = 1
var launched: bool = false
var _launch_left: float = -1.0
var _stick: Dictionary = {}      # "device:axis" -> -1, 0, 1
var _area: Control
var _summary: Label
var _all_ready: Control
var _built: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_chrome()
	_built = true
	resized.connect(_layout)


## Ouvre la page pour `n` joueurs, choix repris de GameState.
func open(n: int) -> void:
	player_count = clampi(n, 1, 6)
	launched = false
	_launch_left = -1.0
	_stick.clear()
	for p in panels:
		p.queue_free()
	panels.clear()
	for i in player_count:
		var p := LoadoutPanel.new(i, device_text(i, player_count))
		p.trailer = posmod(GameState.trailer_choice[i], TrailerCatalog.count())
		p.power_left = GameState.power_left[i]
		p.power_right = GameState.power_right[i]
		p.reel_clicked.connect(_on_reel_clicked.bind(i))
		_area.add_child(p)
		panels.append(p)
	var c: Dictionary = GameStateNode.SPEED_CLASSES[GameState.speed_class]
	_summary.text = "%s  ·  %s %s  ·  %d joueur%s" % [String(GameStateNode.TRACKS[GameState.selected_track]["name"]).to_upper(),
		c["cc"], String(c["name"]).to_upper(), player_count, "s" if player_count > 1 else ""]
	visible = true
	_layout()
	_update_all_ready()


func close() -> void:
	visible = false
	_launch_left = -1.0


## Manette et touches du joueur `i` (bandeau de sa carte).
static func device_text(i: int, n: int) -> String:
	if GameState.join_devices.size() == n:
		return MainMenu.device_label(GameState.join_devices[i]).capitalize()
	if n == 1:
		return "Manette ou clavier"
	var t := "Manette %d" % (i + 1)
	if i == 0:
		t += "  ·  flèches"
	elif i == 1:
		t += "  ·  ZQSD"
	return t


func all_ready() -> bool:
	if panels.is_empty():
		return false
	for p in panels:
		if not p.confirmed:
			return false
	return true


# --- commandes -------------------------------------------------------------------

## Action `action` du joueur `i` : up, down, left, right, accept, cancel.
func act(i: int, action: StringName) -> void:
	if i < 0 or i >= panels.size() or launched:
		return
	var p := panels[i]
	match action:
		&"up", &"down":
			if p.confirmed:
				return
			var dir := -1 if action == &"up" else 1
			match p.column:
				0:
					p.trailer = posmod(p.trailer + dir, TrailerCatalog.count())
					GameState.trailer_choice[i] = p.trailer
					trailer_changed.emit(i, p.trailer)
				1:
					p.power_left = PowerCatalog.step(p.power_left, dir)
					GameState.power_left[i] = p.power_left
				2:
					p.power_right = PowerCatalog.step(p.power_right, dir)
					GameState.power_right[i] = p.power_right
			MenuSound.play_select()
		&"left", &"right":
			if p.confirmed:
				return
			var col := clampi(p.column + (-1 if action == &"left" else 1), 0, LoadoutPanel.COLUMNS - 1)
			if col == p.column:
				return
			p.column = col
			MenuSound.play_select()
		&"accept":
			if p.confirmed:
				return
			p.validated[p.column] = true
			if p.column < LoadoutPanel.COLUMNS - 1:
				p.column += 1
				MenuSound.play_select()
			else:
				p.confirmed = true
				MenuSound.play_confirm()
		&"cancel":
			if p.confirmed:
				p.confirmed = false
				p.validated[p.column] = false
			elif p.column > 0:
				p.column -= 1
				p.validated[p.column] = false
			else:
				back_requested.emit()
				return
			MenuSound.play_toggle()
	p.refresh()
	# set_index apres refresh : garde le glissement du rouleau
	if action == &"up" or action == &"down":
		p.reels[p.column].set_index(p.reels[p.column].index, -1 if action == &"up" else 1)
	_update_all_ready()


func _on_reel_clicked(column: int, zone: int, i: int) -> void:
	var p := panels[i]
	if p.confirmed:
		return
	if column != p.column:
		p.column = column
		p.refresh()
	if zone == 0:
		act(i, &"accept")
	else:
		act(i, &"up" if zone < 0 else &"down")


func _update_all_ready() -> void:
	var all := all_ready()
	_all_ready.visible = all
	if all and _launch_left < 0.0:
		_launch_left = LAUNCH_DELAY_S
	elif not all:
		_launch_left = -1.0


func _process(delta: float) -> void:
	if not visible or launched or _launch_left < 0.0:
		return
	_launch_left -= delta
	if _launch_left <= 0.0:
		launched = true
		launch_requested.emit()


func _input(event: InputEvent) -> void:
	if not visible or launched:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.physical_keycode == KEY_ESCAPE and not key.echo:
		back_requested.emit()
		get_viewport().set_input_as_handled()
		return
	var routed := route(event)
	if routed.is_empty():
		return
	act(routed[0], routed[1])
	get_viewport().set_input_as_handled()


## Joueur et action d'une entree, ou [] : manette i -> joueur i (seul : toutes),
## fleches + Entree / Retour arriere -> J1, ZQSD + Espace / E -> J2 (seul : J1).
## Venus de la salle d'attente (GameState.join_devices) : chaque appareil pilote
## le joueur qu'il a inscrit, et un appareil non inscrit personne.
func route(event: InputEvent) -> Array:
	var n := player_count
	var joined := GameState.join_devices.size() == n
	var key := event as InputEventKey
	if key != null:
		if not key.pressed:
			return []
		var nav := {KEY_UP: &"up", KEY_DOWN: &"down", KEY_LEFT: &"left", KEY_RIGHT: &"right"}
		var zqsd := {KEY_W: &"up", KEY_S: &"down", KEY_A: &"left", KEY_D: &"right"}
		var code := key.physical_keycode
		var first := GameState.join_devices.find(GameStateNode.JOIN_ARROWS) if joined else 0
		var second := (GameState.join_devices.find(GameStateNode.JOIN_ZQSD) if joined else (1 if n > 1 else 0))
		if nav.has(code) and first < 0 or zqsd.has(code) and second < 0:
			return []
		if nav.has(code):
			return [first, nav[code]]
		if zqsd.has(code):
			return [second, zqsd[code]]
		if key.echo:
			return []
		match code:
			KEY_ENTER, KEY_KP_ENTER:
				return [first, &"accept"] if first >= 0 else []
			KEY_BACKSPACE:
				return [first, &"cancel"] if first >= 0 else []
			KEY_SPACE:
				return [second, &"accept"] if second >= 0 else []
			KEY_E:
				return [second, &"cancel"] if second >= 0 else []
		return []
	var pad := event as InputEventJoypadButton
	if pad != null:
		if not pad.pressed:
			return []
		var who := GameState.join_devices.find(pad.device) if joined else (0 if n == 1 else pad.device)
		if who < 0 or who >= n:
			return []
		match pad.button_index:
			JOY_BUTTON_DPAD_UP: return [who, &"up"]
			JOY_BUTTON_DPAD_DOWN: return [who, &"down"]
			JOY_BUTTON_DPAD_LEFT: return [who, &"left"]
			JOY_BUTTON_DPAD_RIGHT: return [who, &"right"]
			JOY_BUTTON_A, JOY_BUTTON_X: return [who, &"accept"]
			JOY_BUTTON_B: return [who, &"cancel"]
		return []
	var motion := event as InputEventJoypadMotion
	if motion != null and (motion.axis == JOY_AXIS_LEFT_X or motion.axis == JOY_AXIS_LEFT_Y):
		var who := GameState.join_devices.find(motion.device) if joined else (0 if n == 1 else motion.device)
		if who < 0 or who >= n:
			return []
		var k := "%d:%d" % [motion.device, motion.axis]
		var was: int = _stick.get(k, 0)
		var v := motion.axis_value
		var now := was
		if absf(v) < STICK_OFF:
			now = 0
		elif absf(v) > STICK_ON:
			now = 1 if v > 0.0 else -1
		_stick[k] = now
		if now == 0 or now == was:
			return []
		if motion.axis == JOY_AXIS_LEFT_X:
			return [who, &"right" if now > 0 else &"left"]
		return [who, &"down" if now > 0 else &"up"]
	return []


# --- mise en page ----------------------------------------------------------------

func _build_chrome() -> void:
	# voile sur le showroom : lisible, la ville reste devinee
	var dim := TextureRect.new()
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(UiKit.NIGHT, 0.94))
	g.set_color(1, Color(UiKit.NIGHT.lightened(0.04), 0.78))
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 1)
	dim.texture = tex
	dim.stretch_mode = TextureRect.STRETCH_SCALE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	# bandeau : titre, etapes, resume de la course
	var title := UiKit.label("CHOIX DU CONVOI", 58, UiKit.TEXT, 900)
	title.position = Vector2(64, 30)
	add_child(title)
	var steps := HBoxContainer.new()
	steps.position = Vector2(68, 104)
	steps.add_theme_constant_override("separation", 26)
	steps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(steps)
	for s: Array in [["1", "REMORQUE", ""], ["2", "POUVOIR", "dpad_left"], ["3", "POUVOIR", "dpad_right"]]:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 8)
		chip.add_child(UiKit.label(s[0], 20, UiKit.PINK, 900))
		chip.add_child(UiKit.label(s[1], 20, UiKit.DIM, 800))
		if s[2] != "":
			var gl := PadGlyph.new()
			gl.kind = s[2]
			gl.custom_minimum_size = Vector2(24, 24)
			gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			chip.add_child(gl)
		steps.add_child(chip)
	_summary = UiKit.label("", 22, UiKit.CYAN, 800)
	_summary.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_summary.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_summary.offset_top = 52
	_summary.offset_right = -64
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_summary)
	var rule := ColorRect.new()
	rule.color = Color(UiKit.PINK, 0.8)
	rule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rule.offset_top = TOP - 12
	rule.offset_bottom = TOP - 10
	rule.offset_left = 64
	rule.offset_right = -64
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)
	_area = Control.new()
	_area.name = "Cards"
	_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_area.offset_top = TOP
	_area.offset_bottom = -BOTTOM
	_area.offset_left = 40
	_area.offset_right = -40
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.resized.connect(_layout)
	add_child(_area)
	# barre d'aide
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -BOTTOM + 14
	var sb := UiKit.box(Color(UiKit.NIGHT, 0.9), Color(0, 0, 0, 0), 0, 0.0, 0)
	sb.content_margin_left = 64
	bar.add_theme_stylebox_override("panel", sb)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var help := HBoxContainer.new()
	help.add_theme_constant_override("separation", 34)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(help)
	help.add_child(UiKit.prompt("dpad_ud", "Choisir"))
	help.add_child(UiKit.prompt("dpad_lr", "Colonne"))
	help.add_child(UiKit.prompt("cross", "Valider"))
	help.add_child(UiKit.prompt("circle", "Retour"))
	help.add_child(UiKit.prompt("key:Échap", "Accueil"))
	help.add_child(UiKit.prompt("key:J1", "flèches · Entrée · Retour arrière"))
	help.add_child(UiKit.prompt("key:J2", "ZQSD · Espace · E"))
	# tout le monde pret
	_all_ready = Panel.new()
	_all_ready.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_all_ready.custom_minimum_size = Vector2(980, 120)
	_all_ready.offset_left = -490
	_all_ready.offset_right = 490
	_all_ready.offset_top = -60
	_all_ready.offset_bottom = 60
	_all_ready.add_theme_stylebox_override("panel", UiKit.box(UiKit.GOLD, Color(1, 1, 1, 0.8), 3, UiKit.SKEW, 4,
		Color(UiKit.GOLD, 0.55), 30, true))
	_all_ready.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_all_ready)
	var go := UiKit.label("TOUS PRÊTS !  EN PISTE", 58, UiKit.NIGHT, 900)
	go.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_all_ready.add_child(go)
	_all_ready.visible = false


## Grille de l'ecran (seul ou scinde) : chaque carte a l'echelle de sa case,
## centree.
func _layout() -> void:
	if _area == null or panels.is_empty():
		return
	var n := panels.size()
	var cols := 1 if n == 1 else (2 if n <= 4 else 3)
	var rows := 1 if n <= 2 else 2
	var gap := 22.0
	var area := _area.size
	var cell := Vector2((area.x - gap * (cols - 1)) / cols, (area.y - gap * (rows - 1)) / rows)
	var k := minf(cell.x / LoadoutPanel.DESIGN.x, cell.y / LoadoutPanel.DESIGN.y)
	k = minf(k, 1.45)
	# la grille en bloc, centree (cartes serrees, pas une par case)
	var card := LoadoutPanel.DESIGN * k
	var block := Vector2(cols * card.x + gap * (cols - 1), rows * card.y + gap * (rows - 1))
	var corner := (area - block) / 2.0
	for i in n:
		var c := i % cols
		var r := floori(float(i) / cols)
		# derniere rangee incomplete (3 ou 5 joueurs) : centree elle aussi
		var in_row := mini(cols, n - r * cols)
		var shift := (cols - in_row) * (card.x + gap) / 2.0
		var p := panels[i]
		p.scale = Vector2(k, k)
		p.position = corner + Vector2(shift + c * (card.x + gap), r * (card.y + gap))
