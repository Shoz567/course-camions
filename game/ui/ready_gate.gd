class_name ReadyGate
extends CanvasLayer

## Sas du depart en ligne (2026-10-22 : « pour etre sur que tout le monde est
## la et qu'il a bien charge la course, une touche a appuyer pour se mettre
## pret. Mais [...] dans le nouveau style graphique, pas du texte jaune ») :
## carte UiKit au centre de l'ecran, une ligne par joueur (pastille a sa
## couleur, nom, etat : CHARGEMENT / EN ATTENTE / PRET), puis l'invite a
## pictos (Croix, Espace) tant que ce PC n'est pas pret. Les bots, prets
## d'office, n'y figurent pas. LocalRace l'affiche pendant le sas (show_gate)
## et la cache au compte a rebours ; elle ne decide rien (CLAUDE.md §7).

enum Status { LOADING, WAITING, READY }

const STATUS_TEXT: Array[String] = ["CHARGEMENT…", "EN ATTENTE", "PRÊT"]

var _card: PanelContainer
var _title: Label
var _hint: Label
var _rows: GridContainer
var _prompt: HBoxContainer
var _waiting: Label
var _count: Label
var _sig: String = ""


func _ready() -> void:
	layer = 5
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -160    # au-dessus du camion
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = UiKit.card(UiKit.CYAN, 760.0)
	_card.name = "Card"
	center.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(col)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var section := UiKit.section("Départ en ligne", 18)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(section)
	_count = UiKit.label("", 20, UiKit.CYAN, 800, false)
	_count.name = "Count"
	head.add_child(_count)
	_title = UiKit.label("PRÊT ?", 54, UiKit.TEXT, 900)
	_title.name = "Title"
	col.add_child(_title)
	_hint = UiKit.label("", 19, UiKit.DIM, 600, false)
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(700, 0)
	col.add_child(_hint)
	_rows = GridContainer.new()
	_rows.name = "Players"
	_rows.columns = 3
	_rows.add_theme_constant_override("h_separation", 14)
	_rows.add_theme_constant_override("v_separation", 8)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_rows)
	col.add_child(UiKit.gap(2))
	_prompt = HBoxContainer.new()
	_prompt.name = "Prompt"
	_prompt.add_theme_constant_override("separation", 26)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_child(UiKit.prompt("cross", "Je suis prêt", 22))
	_prompt.add_child(UiKit.prompt("key:Espace", "Je suis prêt", 22))
	col.add_child(_prompt)
	_waiting = UiKit.label("", 22, UiKit.GOOD, 800, false)
	_waiting.name = "Waiting"
	col.add_child(_waiting)


## Etat du sas : `rows` = [{name, color, status (Status), me}] des joueurs
## (pas des bots) ; `me_ready` : le joueur de ce PC est pret ; `connecting` :
## le host n'a pas encore repondu (client).
func show_gate(rows: Array, me_ready: bool, connecting: bool) -> void:
	visible = true
	var sig := "%s|%s|%s" % [rows, me_ready, connecting]
	if sig == _sig:
		return
	_sig = sig
	var n_ready := 0
	for r: Dictionary in rows:
		n_ready += 1 if int(r["status"]) == Status.READY else 0
	_count.text = "%d / %d PRÊTS" % [n_ready, rows.size()]
	if connecting:
		_title.text = "CONNEXION…"
		_hint.text = "L'hôte prépare encore la course."
	elif me_ready:
		_title.text = "PRÊT !"
		_hint.text = "Le départ sera donné quand tout le monde sera prêt."
	else:
		_title.text = "PRÊT ?"
		_hint.text = "Ta course est chargée : confirme que tu es là. Le départ sera donné quand tout le monde sera prêt."
	_title.add_theme_color_override("font_color", UiKit.GOOD if me_ready else UiKit.TEXT)
	_prompt.visible = not me_ready and not connecting
	_waiting.visible = me_ready
	_waiting.text = "En attente des autres joueurs  ·  %d / %d" % [n_ready, rows.size()]
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for r: Dictionary in rows:
		_add_row(r)


func hide_gate() -> void:
	visible = false
	_sig = ""


## Texte de la ligne `i` (tests) : « nom  ETAT ».
func row_text(i: int) -> String:
	var k := i * 3
	if k + 2 >= _rows.get_child_count():
		return ""
	return "%s  %s" % [(_rows.get_child(k + 1) as Label).text, (_rows.get_child(k + 2) as Label).text]


func _add_row(r: Dictionary) -> void:
	var dot := ColorRect.new()
	dot.color = r["color"]
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_child(dot)
	var me := bool(r.get("me", false))
	var who := UiKit.label(String(r["name"]) + ("  (toi)" if me else ""), 21, UiKit.TEXT, 800 if me else 600, false)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(who)
	var s := int(r["status"])
	var tint: Color = [UiKit.DIM, UiKit.TEXT, UiKit.GOOD][s]
	var st := UiKit.label(STATUS_TEXT[s], 19, tint, 800, false)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	st.custom_minimum_size = Vector2(160, 0)
	_rows.add_child(st)
