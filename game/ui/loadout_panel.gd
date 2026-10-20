class_name LoadoutPanel
extends Control

## Carte d'un joueur sur la page de selection (LoadoutSelect), dessinee a la
## taille de reference DESIGN puis mise a l'echelle de sa case (ecran seul ou
## scinde) :
##   - bandeau a la couleur du joueur : J1, couleur, manette ;
##   - a gauche, son camion en 3D (TruckPreview) avec la remorque choisie ;
##   - a droite, trois rouleaux : 1. REMORQUE, 2. POUVOIR (fleche gauche de la
##     croix), 3. POUVOIR (fleche droite) ;
##   - dessous : nom et description du choix courant, stats de la remorque,
##     aides des commandes ;
##   - PRET : bandeau vert en travers de la carte.
## Ne lit aucune entree : LoadoutSelect la pilote (move, step, accept, cancel).

const DESIGN := Vector2(900, 560)
const COLUMNS := 3
const LocalRace := preload("res://dev/local_race.gd")

signal reel_clicked(column: int, zone: int)

var player: int = 0
var accent: Color = UiKit.PINK
var device_text: String = ""
## Colonne active (0 remorque, 1 pouvoir gauche, 2 pouvoir droite).
var column: int = 0
var validated: Array[bool] = [false, false, false]
var confirmed: bool = false
var trailer: int = 0
var power_left: int = -1
var power_right: int = -1

var reels: Array[LoadoutReel] = []
var preview: TruckPreview
var _info_name: Label
var _info_sub: Label
var _bars: Dictionary = {}
var _ready_banner: Control
var _ready_label: Label
var _frame: Panel
var _t: float = 0.0


func _init(player_index: int = 0, device: String = "") -> void:
	player = player_index
	accent = UiKit.PLAYER_COLORS[player_index % UiKit.PLAYER_COLORS.size()]
	device_text = device
	size = DESIGN
	custom_minimum_size = DESIGN


func _ready() -> void:
	name = "Panel%d" % (player + 1)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_frame = Panel.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.PANEL, 0.93), Color(accent, 0.55), 2, 0.0, 10,
		Color(0, 0, 0, 0.5), 18))
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_build_header()
	_build_body()
	_build_footer()
	_build_ready_banner()
	refresh()


func _build_header() -> void:
	var band := Panel.new()
	band.position = Vector2(0, 0)
	band.size = Vector2(DESIGN.x, 64)
	var sb := UiKit.box(Color(accent, 0.22), Color(0, 0, 0, 0), 0, 0.0, 10)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	band.add_theme_stylebox_override("panel", sb)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	var badge := Panel.new()
	badge.position = Vector2(22, 10)
	badge.size = Vector2(86, 44)
	badge.add_theme_stylebox_override("panel", UiKit.box(accent, Color(1, 1, 1, 0.5), 1, UiKit.SKEW, 3, Color(accent, 0.6), 10))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)
	var jn := UiKit.label("J%d" % (player + 1), 30, UiKit.NIGHT, 900)
	jn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	jn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(jn)
	var col := UiKit.label(LocalRace.COLOR_NAMES[player], 30, UiKit.TEXT, 900)
	col.position = Vector2(128, 11)
	add_child(col)
	var dev := UiKit.label(device_text, 17, UiKit.DIM, 600, false)
	dev.position = Vector2(DESIGN.x - 330, 20)
	dev.size = Vector2(306, 26)
	dev.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(dev)


func _build_body() -> void:
	# vitrine 3D a gauche, fond degrade a la couleur du joueur
	var stage := Panel.new()
	stage.position = Vector2(18, 78)
	stage.size = Vector2(400, 300)
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(accent.darkened(0.55), 0.95))
	g.set_color(1, Color(UiKit.NIGHT, 0.95))
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.75)
	tex.fill_to = Vector2(1.1, 0.0)
	var st := StyleBoxTexture.new()
	st.texture = tex
	stage.add_theme_stylebox_override("panel", st)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	preview = TruckPreview.new(player, accent)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(preview)
	# trois rouleaux a droite
	var titles := ["1  REMORQUE", "2  POUVOIR", "3  POUVOIR"]
	var glyphs := ["", "dpad_left", "dpad_right"]
	for k in COLUMNS:
		var reel := LoadoutReel.new()
		reel.name = "Reel%d" % k
		reel.title = titles[k]
		reel.glyph = glyphs[k]
		reel.accent = accent
		reel.position = Vector2(440 + k * 150, 78)
		reel.size = Vector2(138, 300)
		reel.clicked.connect(func(zone: int) -> void: reel_clicked.emit(k, zone))
		add_child(reel)
		reels.append(reel)


func _build_footer() -> void:
	_info_name = UiKit.label("", 26, UiKit.TEXT, 900)
	_info_name.position = Vector2(24, 392)
	add_child(_info_name)
	_info_sub = UiKit.label("", 17, UiKit.DIM, 600, false)
	_info_sub.position = Vector2(26, 428)
	_info_sub.size = Vector2(DESIGN.x - 52, 24)
	_info_sub.clip_text = true
	add_child(_info_sub)
	# stats de la remorque : barres a segments, repere au milieu (= Conteneur)
	var stats := [["speed", "VITESSE"], ["accel", "ACCÉLÉRATION"], ["grip", "ADHÉRENCE"], ["hp", "PV LARGUÉE"]]
	for k in stats.size():
		var x := 24.0 + k * 218.0
		var l := UiKit.label(stats[k][1], 13, UiKit.DIM, 700, false)
		l.position = Vector2(x, 460)
		add_child(l)
		var bar := StatBar.new()
		bar.position = Vector2(x, 480)
		bar.size = Vector2(196, 14)
		bar.accent = accent
		add_child(bar)
		_bars[stats[k][0]] = bar
	var prompts := HBoxContainer.new()
	prompts.position = Vector2(24, 512)
	prompts.add_theme_constant_override("separation", 22)
	prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompts)
	prompts.add_child(UiKit.prompt("cross", "Valider", 16))
	prompts.add_child(UiKit.prompt("circle", "Retour", 16))
	prompts.add_child(UiKit.prompt("dpad_ud", "Choisir", 16))
	prompts.add_child(UiKit.prompt("dpad_lr", "Colonne", 16))


func _build_ready_banner() -> void:
	_ready_banner = Panel.new()
	_ready_banner.position = Vector2(-10, 190)
	_ready_banner.size = Vector2(DESIGN.x + 20, 110)
	_ready_banner.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.GOOD, 0.92), Color(1, 1, 1, 0.7), 2,
		UiKit.SKEW, 4, Color(UiKit.GOOD, 0.5), 22))
	_ready_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_banner.pivot_offset = _ready_banner.size / 2.0
	add_child(_ready_banner)
	_ready_label = UiKit.label("PRÊT !", 64, UiKit.NIGHT, 900)
	_ready_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ready_banner.add_child(_ready_label)
	var hint := UiKit.prompt("circle", "Annuler", 15)
	hint.position = Vector2(DESIGN.x - 150, 76)
	_ready_banner.add_child(hint)
	_ready_banner.visible = false


func _process(delta: float) -> void:
	_t += delta
	if _ready_banner.visible:
		var s := 1.0 + 0.02 * sin(_t * 5.0)
		_ready_banner.scale = Vector2(s, s)


## Met les rouleaux, la vitrine, le texte et les stats a jour.
func refresh() -> void:
	if reels.is_empty():
		return
	var trailer_items: Array[Dictionary] = []
	for k in TrailerCatalog.count():
		var t := TrailerCatalog.at(k)
		trailer_items.append({"name": t.display_name, "sub": "%d / %d" % [k + 1, TrailerCatalog.count()]})
	reels[0].items = trailer_items
	reels[0].index = trailer
	var power_items: Array[Dictionary] = [{"name": "AUCUN", "sub": "emplacement libre"}]
	for k in PowerCatalog.count():
		power_items.append({"name": PowerCatalog.display_name(k), "sub": ""})
	reels[1].items = power_items
	reels[1].index = power_left + 1
	reels[2].items = power_items.duplicate()
	reels[2].index = power_right + 1
	for k in COLUMNS:
		reels[k].active = k == column and not confirmed
		reels[k].validated = validated[k]
		reels[k].queue_redraw()
	var type := TrailerCatalog.at(trailer)
	if preview != null:
		preview.set_trailer(type)
	if column == 0 or confirmed:
		_info_name.text = type.display_name
		var sub := type.tagline
		_info_sub.text = sub.left(1).to_upper() + sub.substr(1)
	else:
		var p := power_left if column == 1 else power_right
		_info_name.text = "%s  ·  %s" % [PowerCatalog.display_name(p), "flèche gauche" if column == 1 else "flèche droite"]
		var sub := PowerCatalog.tagline(p)
		_info_sub.text = (sub.left(1).to_upper() + sub.substr(1)) + "  —  Croix pour passer"
	(_bars["speed"] as StatBar).value = StatBar.from_mult(type.top_speed_mult)
	(_bars["accel"] as StatBar).value = StatBar.from_mult(type.accel_mult)
	(_bars["grip"] as StatBar).value = StatBar.from_mult(type.grip_mult)
	(_bars["hp"] as StatBar).value = clampf(type.dropped_hp / 80.0, 0.0, 1.0)
	_ready_banner.visible = confirmed
	_frame.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.PANEL, 0.93),
		Color(UiKit.GOOD if confirmed else accent, 0.9 if confirmed else 0.55), 3 if confirmed else 2, 0.0, 10, Color(0, 0, 0, 0.5), 18))


## Barre de stat a segments : `value` 0..1, le repere du milieu = reference.
class StatBar:
	extends Control
	const SEGMENTS := 10
	var accent: Color = UiKit.PINK
	var value: float = 0.5:
		set(v):
			value = v
			queue_redraw()

	## Multiplicateur de reglage (0,85 .. 1,15) vers 0..1 : 1 = la moitie.
	static func from_mult(m: float) -> float:
		return clampf((m - 0.85) / 0.3, 0.0, 1.0)

	func _draw() -> void:
		var gap := 3.0
		var w := (size.x - gap * (SEGMENTS - 1)) / SEGMENTS
		var lit := roundi(value * SEGMENTS)
		for k in SEGMENTS:
			var r := Rect2(k * (w + gap), 0, w, size.y)
			var on := k < lit
			var col := accent.lerp(UiKit.TEXT, float(k) / SEGMENTS * 0.35) if on else Color(1, 1, 1, 0.1)
			# segments penches en neon seulement, droits ailleurs
			var sb := UiKit.box(col, Color(0, 0, 0, 0), 0, 0.35 if UiKit.SKEW > 0.0 else 0.0, mini(UiKit.RADIUS, 3))
			sb.set_content_margin_all(0)
			draw_style_box(sb, r)
		var mid := size.x / 2.0
		draw_line(Vector2(mid, -3), Vector2(mid, size.y + 3), Color(1, 1, 1, 0.55), 1.0)
