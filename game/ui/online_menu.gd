class_name OnlineMenu
extends Control

## Menu EN LIGNE (2026-10-22 : « quand on selectionne en ligne, que ce soit
## plus intuitif, que ca ouvre un autre menu dans lequel on peut choisir
## toutes les caracteristiques separees »), page a part de l'accueil, en deux
## etapes :
##   1. hors partie : pseudo, puis deux cartes, HEBERGER (ce PC fait tourner
##      la partie) et REJOINDRE (adresse IP du host) ; l'erreur de connexion
##      s'affiche dessous ;
##   2. dans une partie (salon) : a gauche les REGLES - le host les choisit
##      (circuit au menu deroulant, mode, vitesse, duree ou largages, bots,
##      connexion lente),
##      les autres les voient en direct (NetSession.host_rules) ; a droite
##      les JOUEURS (convoi choisi ou pas), l'adresse a donner, le debit du
##      host ; en bas CHOISIR MON CONVOI, LANCER (host), QUITTER LA PARTIE.
## Les reglages sont ceux du profil en ligne (GameState.Profile.ONLINE), a
## part de ceux de la partie locale. Le contre-la-montre (seul) n'est pas
## propose. Construit dans l'habillage du moment : le menu le reconstruit
## quand le circuit change (ambiance_requested).

signal back_requested
signal convoy_requested
## Circuit des regles change (host qui choisit, client qui recoit) : le menu
## prend son ambiance.
signal ambiance_requested(track: int)

## Modes proposes en ligne (GameStateNode.GameMode), dans l'ordre des boutons.
const MODES: Array[int] = [GameStateNode.GameMode.RACE, GameStateNode.GameMode.ELIMINATION,
	GameStateNode.GameMode.ARENA]
## Adresse tapee la derniere fois (gardee d'une reconstruction a l'autre).
static var last_address: String = ""

var name_edit: LineEdit
var ip_edit: LineEdit
var host_button: Button
var join_button: Button
var status_label: Label
var launch_button: Button
var leave_button: Button
var convoy_button: Button
var slow_check: CheckButton
## Etape 1 (hors partie) et etape 2 (salon).
var connect_box: Control
var lobby_box: Control
## Regles : boutons du host (par regle), resume du client.
var mode_buttons: Array[Button] = []
var track_option: OptionButton
var speed_buttons: Array[Button] = []
var time_buttons: Array[Button] = []
var drop_buttons: Array[Button] = []
var bot_buttons: Array[Button] = []
var level_buttons: Array[Button] = []
var rules_host: Control
var rules_guest: GridContainer
var rules_note: Label
var mode_tip: Label
var time_row: Control
var drops_row: Control
var players_title: Label
var players_box: VBoxContainer
var address_label: Label
var uplink_label: Label
## Ce qu'on attend avant le lancement (convois, host).
var wait_label: Label

var _page: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page = UiKit.page("OnlinePage", "EN LIGNE", "JUSQU'À %d JOUEURS  ·  RÉSEAU LOCAL OU INTERNET" % NetSessionNode.MAX_PLAYERS,
		[["cross", "Valider"], ["circle", "Retour"], ["key:Échap", "Retour"]])
	_page.visible = true
	add_child(_page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	UiKit.page_content(_page).add_child(col)
	connect_box = _build_connect()
	col.add_child(connect_box)
	lobby_box = _build_lobby()
	col.add_child(lobby_box)
	for sig: Signal in [NetSession.lobby_changed, NetSession.joined, NetSession.race_launched]:
		sig.connect(refresh)
	NetSession.join_failed.connect(_on_failed)
	NetSession.connection_lost.connect(_on_failed)
	refresh()


func _on_failed(_reason: String) -> void:
	refresh()


## Focus de l'etape affichee : HEBERGER, ou LANCER / CHOISIR MON CONVOI.
func focus_default() -> void:
	if not NetSession.is_online():
		host_button.grab_focus()
	elif NetSession.is_host() and not launch_button.disabled:
		launch_button.grab_focus()
	elif convoy_button.visible:
		convoy_button.grab_focus()
	else:
		leave_button.grab_focus()


# --- etape 1 : heberger ou rejoindre ------------------------------------------

func _build_connect() -> Control:
	var card := UiKit.card(UiKit.CYAN, 1480)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	card.add_child(box)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 16)
	box.add_child(name_row)
	var name_label := UiKit.label("TON PSEUDO", 22, UiKit.TEXT, 800)
	name_label.custom_minimum_size.x = 190
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(name_label)
	name_edit = LineEdit.new()
	name_edit.name = "PlayerName"
	name_edit.text = NetSession.player_name
	name_edit.max_length = NetSessionNode.MAX_NAME
	name_edit.custom_minimum_size = Vector2(520, 56)
	name_edit.add_theme_font_size_override("font_size", 22)
	UiKit.style_field(name_edit)
	name_edit.text_changed.connect(func(t: String) -> void: NetSession.player_name = NetSessionNode.clean_name(t))
	name_row.add_child(name_edit)
	var name_hint := UiKit.label("vu par les autres joueurs", 17, UiKit.DIM, 600, false)
	name_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(name_hint)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 28)
	box.add_child(cards)
	var host_card := _choice_card(UiKit.GOLD)
	cards.add_child(host_card)
	var hb := host_card.get_child(0) as VBoxContainer
	hb.add_child(UiKit.section("Héberger une partie", 24))
	hb.add_child(_wrap("Ce PC fait tourner la partie. Tu choisis le mode, le circuit, la vitesse et les bots, "
		+ "puis tu lances quand tout le monde a choisi son convoi.", 19))
	hb.add_child(_spacer())
	host_button = Button.new()
	host_button.name = "Host"
	host_button.text = "HÉBERGER"
	host_button.custom_minimum_size = Vector2(0, 66)
	UiKit.style_primary(host_button, 26)
	host_button.pressed.connect(host_game)
	hb.add_child(host_button)

	var join_card := _choice_card(UiKit.CYAN)
	cards.add_child(join_card)
	var jb := join_card.get_child(0) as VBoxContainer
	jb.add_child(UiKit.section("Rejoindre une partie", 24))
	jb.add_child(_wrap("Tape l'adresse IP du PC qui héberge : elle s'affiche dans son salon.", 19))
	jb.add_child(_spacer())
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	jb.add_child(join_row)
	ip_edit = LineEdit.new()
	ip_edit.name = "HostAddress"
	ip_edit.placeholder_text = "ex. 192.168.1.20"
	ip_edit.text = last_address
	ip_edit.custom_minimum_size = Vector2(0, 66)
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_edit.add_theme_font_size_override("font_size", 22)
	UiKit.style_field(ip_edit)
	ip_edit.text_changed.connect(func(t: String) -> void: last_address = t)
	ip_edit.text_submitted.connect(func(_t: String) -> void: join_game())
	join_row.add_child(ip_edit)
	join_button = Button.new()
	join_button.name = "Join"
	join_button.text = "REJOINDRE"
	join_button.custom_minimum_size = Vector2(230, 66)
	UiKit.style_choice(join_button, 24)
	join_button.pressed.connect(join_game)
	join_row.add_child(join_button)

	status_label = UiKit.label("", 19, UiKit.TEXT, 700, false)
	status_label.name = "Status"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(0, 28)
	box.add_child(status_label)
	box.add_child(_wrap("Par Internet : celui qui héberge ouvre le port UDP %d de sa box, ou vous passez tous par un VPN "
		% NetSessionNode.DEFAULT_PORT + "(Tailscale, ZeroTier). Sur le même réseau (même box), rien à faire.", 17, UiKit.DIM))
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(bottom)
	var back := Button.new()
	back.name = "Back"
	back.text = "RETOUR"
	back.custom_minimum_size = Vector2(240, 58)
	UiKit.style_choice(back, 22)
	back.pressed.connect(func() -> void: back_requested.emit())
	bottom.add_child(back)
	# croix : du pseudo aux deux cartes, puis RETOUR
	name_edit.focus_neighbor_bottom = name_edit.get_path_to(host_button)
	host_button.focus_neighbor_right = host_button.get_path_to(ip_edit)
	ip_edit.focus_neighbor_left = ip_edit.get_path_to(host_button)
	host_button.focus_neighbor_bottom = host_button.get_path_to(back)
	join_button.focus_neighbor_bottom = join_button.get_path_to(back)
	ip_edit.focus_neighbor_bottom = ip_edit.get_path_to(back)
	return card


## Carte d'un choix de l'etape 1 (HEBERGER, REJOINDRE) : meme hauteur.
func _choice_card(edge: Color) -> PanelContainer:
	var c := UiKit.card(edge)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size.y = 290
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	c.add_child(v)
	return c


func host_game() -> void:
	NetSession.player_name = NetSessionNode.clean_name(name_edit.text)
	NetSession.last_error = ""
	if NetSession.host() == OK:
		MenuSound.play_confirm()
	refresh()
	focus_default()


## Rejoint l'adresse du champ (ou `address`, qui le remplit).
func join_game(address: String = "") -> void:
	if address != "":
		ip_edit.text = address
		last_address = address
	NetSession.player_name = NetSessionNode.clean_name(name_edit.text)
	NetSession.last_error = ""
	if ip_edit.text.strip_edges() == "":
		NetSession.last_error = "Tape d'abord l'adresse IP du PC qui héberge."
		ip_edit.grab_focus()
	elif NetSession.join(ip_edit.text.strip_edges()) == OK:
		MenuSound.play_confirm()
	refresh()


func leave_game() -> void:
	NetSession.leave()
	NetSession.last_error = ""
	MenuSound.play_toggle()
	refresh()
	focus_default()


## Host : la course de la partie, avec les regles du salon.
func launch_online() -> void:
	if not NetSession.is_host() or not NetSession.all_ready():
		return
	MenuSound.play_confirm()
	NetSession.launch_race()


# --- etape 2 : salon ------------------------------------------------------------

func _build_lobby() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 28)
	col.add_child(cards)

	var rules_card := UiKit.card(UiKit.GOLD, 820)
	rules_card.size_flags_vertical = Control.SIZE_FILL
	cards.add_child(rules_card)
	var rb := VBoxContainer.new()
	rb.add_theme_constant_override("separation", 10)
	rules_card.add_child(rb)
	rb.add_child(UiKit.section("Règles de la partie", 22))
	rules_note = UiKit.label("", 17, UiKit.DIM, 600, false)
	rb.add_child(rules_note)
	rules_host = _build_rules_host()
	rb.add_child(rules_host)
	rules_guest = GridContainer.new()
	rules_guest.name = "RulesGuest"
	rules_guest.columns = 2
	rules_guest.add_theme_constant_override("h_separation", 28)
	rules_guest.add_theme_constant_override("v_separation", 12)
	rb.add_child(rules_guest)

	var players_card := UiKit.card(UiKit.CYAN, 760)
	cards.add_child(players_card)
	var pb := VBoxContainer.new()
	pb.add_theme_constant_override("separation", 8)
	players_card.add_child(pb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	pb.add_child(head)
	head.add_child(UiKit.section("Joueurs", 22))
	players_title = UiKit.label("", 22, UiKit.TEXT, 800)
	head.add_child(players_title)
	address_label = UiKit.label("", 20, UiKit.GOLD, 800, false)
	address_label.name = "Address"
	address_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pb.add_child(address_label)
	players_box = VBoxContainer.new()
	players_box.name = "Lobby"
	players_box.add_theme_constant_override("separation", 4)
	players_box.custom_minimum_size = Vector2(0, 380)
	pb.add_child(players_box)
	uplink_label = UiKit.label("", 16, UiKit.DIM, 600, false)
	uplink_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pb.add_child(uplink_label)
	wait_label = UiKit.label("", 18, UiKit.GOLD, 700, false)
	wait_label.name = "Waiting"
	wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(wait_label)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 18)
	col.add_child(bottom)
	convoy_button = Button.new()
	convoy_button.name = "Convoy"
	convoy_button.text = "CHOISIR MON CONVOI"
	convoy_button.tooltip_text = "Remorque et pouvoirs de ton camion, comme en local."
	convoy_button.custom_minimum_size = Vector2(340, 64)
	UiKit.style_choice(convoy_button, 22)
	convoy_button.pressed.connect(func() -> void: convoy_requested.emit())
	bottom.add_child(convoy_button)
	launch_button = Button.new()
	launch_button.name = "Launch"
	launch_button.text = "LANCER LA PARTIE"
	launch_button.custom_minimum_size = Vector2(380, 64)
	UiKit.style_primary(launch_button, 26)
	launch_button.pressed.connect(launch_online)
	bottom.add_child(launch_button)
	leave_button = Button.new()
	leave_button.name = "Leave"
	leave_button.text = "QUITTER LA PARTIE"
	leave_button.custom_minimum_size = Vector2(320, 64)
	UiKit.style_choice(leave_button, 22)
	leave_button.pressed.connect(leave_game)
	bottom.add_child(leave_button)
	return col


## Regles du host : une rangee de boutons par regle.
func _build_rules_host() -> Control:
	var box := VBoxContainer.new()
	box.name = "RulesHost"
	box.add_theme_constant_override("separation", 10)
	var track_row := _rule_row("CIRCUIT")
	track_option = MainMenu.track_dropdown(19, 46)
	track_option.item_selected.connect(set_track)
	track_row.add_child(track_option)
	box.add_child(track_row)

	var mode_row := _rule_row("MODE")
	var group := ButtonGroup.new()
	for k in MODES.size():
		var b := _rule_button("Mode%d" % k, GameStateNode.MODE_NAMES[MODES[k]], group, 17)
		b.tooltip_text = MainMenu.MODE_TIPS[MODES[k]]
		b.pressed.connect(set_mode.bind(MODES[k]))
		mode_row.add_child(b)
		mode_buttons.append(b)
	box.add_child(mode_row)
	mode_tip = UiKit.label("", 16, UiKit.DIM, 600, false)
	var tip_row := _rule_row("")
	tip_row.add_child(mode_tip)
	box.add_child(tip_row)

	var speed_row := _rule_row("VITESSE")
	group = ButtonGroup.new()
	for k in GameStateNode.SPEED_CLASSES.size():
		var c: Dictionary = GameStateNode.SPEED_CLASSES[k]
		var b := _rule_button("Speed%d" % k, "%s\n%s" % [c["cc"], String(c["name"]).to_upper()], group, 15)
		b.custom_minimum_size.y = 52
		b.tooltip_text = "%s : %d km/h" % [c["name"], int(c["top_kmh"])]
		b.pressed.connect(set_speed.bind(k))
		speed_row.add_child(b)
		speed_buttons.append(b)
	box.add_child(speed_row)

	time_row = _rule_row("DURÉE")
	group = ButtonGroup.new()
	for minutes in GameStateNode.ARENA_MINUTES:
		var b := _rule_button("Time%d" % minutes, "%d MIN" % minutes if minutes > 0 else "∞", group, 16)
		b.tooltip_text = "Manche de %d minutes" % minutes if minutes > 0 else "Sans limite : le dernier debout gagne"
		b.pressed.connect(set_arena_time.bind(minutes))
		time_row.add_child(b)
		time_buttons.append(b)
	box.add_child(time_row)
	drops_row = _rule_row("LARGAGES")
	group = ButtonGroup.new()
	for k in GameStateNode.MAX_TRAILER_DROPS + 1:
		var b := _rule_button("Drops%d" % k, str(k), group, 18)
		b.tooltip_text = "%d largage%s de remorque par joueur" % [k, "s" if k > 1 else ""]
		b.pressed.connect(set_drops.bind(k))
		drops_row.add_child(b)
		drop_buttons.append(b)
	box.add_child(drops_row)

	var bots_row := _rule_row("BOTS")
	bots_row.add_theme_constant_override("separation", 5)
	group = ButtonGroup.new()
	for k in NetSessionNode.MAX_PLAYERS:
		var b := _rule_button("Bots%d" % k, str(k), group, 17)
		b.pressed.connect(set_bots.bind(k))
		bots_row.add_child(b)
		bot_buttons.append(b)
	box.add_child(bots_row)
	var level_row := _rule_row("NIVEAU")
	group = ButtonGroup.new()
	for k in MainMenu.BOT_LEVELS.size():
		var b := _rule_button("BotLevel%d" % k, MainMenu.BOT_LEVELS[k], group, 17)
		b.pressed.connect(set_bot_level.bind(k))
		level_row.add_child(b)
		level_buttons.append(b)
	box.add_child(level_row)

	slow_check = CheckButton.new()
	slow_check.name = "SlowUpload"
	slow_check.text = "Connexion lente : 20 envois par seconde au lieu de 60 (un peu plus de délai)"
	slow_check.tooltip_text = "Pour une connexion Internet qui envoie peu (ADSL) : le débit de ce PC est divisé par 3."
	UiKit.style_toggle(slow_check, 17)
	slow_check.toggled.connect(set_slow)
	box.add_child(slow_check)
	return box


func _rule_row(title: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	var l := UiKit.label(title, 18, UiKit.TEXT, 800)
	l.custom_minimum_size.x = 118
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r.add_child(l)
	return r


func _rule_button(button_name: String, text: String, group: ButtonGroup, font_size: int) -> Button:
	var b := Button.new()
	b.name = button_name
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 42)
	UiKit.style_choice(b, font_size)
	return b


# --- regles du host ----------------------------------------------------------

func set_mode(mode: int) -> void:
	GameState.game_mode = NetSessionNode.online_mode(mode)
	_rules_changed()


func set_track(k: int) -> void:
	var prev := GameState.selected_track
	GameState.selected_track = clampi(k, 0, GameStateNode.TRACKS.size() - 1)
	_rules_changed()
	if GameState.selected_track != prev:
		ambiance_requested.emit(GameState.selected_track)


func set_speed(k: int) -> void:
	GameState.speed_class = clampi(k, 0, GameStateNode.SPEED_CLASSES.size() - 1)
	_rules_changed()


func set_arena_time(minutes: int) -> void:
	GameState.arena_minutes = minutes if GameStateNode.ARENA_MINUTES.has(minutes) else 4
	_rules_changed()


func set_drops(n: int) -> void:
	GameState.trailer_drops = clampi(n, 0, GameStateNode.MAX_TRAILER_DROPS)
	_rules_changed()


## Bots du host : bornes aux places libres (12 camions en tout).
func set_bots(n: int) -> void:
	GameState.bot_count = clampi(n, 0, NetSessionNode.MAX_PLAYERS - maxi(NetSession.members.size(), 1))
	_rules_changed()


func set_bot_level(k: int) -> void:
	GameState.bot_level = clampi(k, 0, MainMenu.BOT_LEVELS.size() - 1)
	_rules_changed()


func set_slow(on: bool) -> void:
	NetSession.snapshot_ticks = NetSessionNode.SNAPSHOT_TICKS_LOW_BANDWIDTH if on else 1
	_rules_changed()


func _rules_changed() -> void:
	if is_node_ready():
		MenuSound.play_select()
	GameState.save_settings()
	NetSession.push_rules()
	refresh()


# --- affichage ----------------------------------------------------------------

## Etape et contenu selon NetSession (partie, regles, joueurs).
func refresh() -> void:
	if connect_box == null:
		return
	var online := NetSession.is_online() and (NetSession.is_host() or NetSession.local_slot() >= 0)
	connect_box.visible = not online
	lobby_box.visible = online
	var connecting := NetSession.is_client() and NetSession.local_slot() < 0
	host_button.disabled = connecting
	join_button.disabled = connecting
	name_edit.editable = not connecting
	ip_edit.editable = not connecting
	if connecting:
		status_label.text = "Connexion à %s…" % ip_edit.text.strip_edges()
		status_label.add_theme_color_override("font_color", UiKit.CYAN)
	elif NetSession.last_error != "":
		status_label.text = NetSession.last_error
		status_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45))
	else:
		status_label.text = ""
	if not online:
		return
	_refresh_rules()
	_refresh_players()
	var host := NetSession.is_host()
	launch_button.visible = host
	launch_button.disabled = not NetSession.all_ready()
	convoy_button.visible = NetSession.local_slot() >= 0
	var missing := 0
	for m in NetSession.members:
		missing += 0 if bool(m.get("ready", false)) else 1
	var mine := bool(NetSession.member_of_slot(NetSession.local_slot()).get("ready", false))
	if not mine:
		wait_label.text = "Choisis ton convoi (remorque et pouvoirs) : CHOISIR MON CONVOI."
	elif missing > 0:
		wait_label.text = ("En attente de %d joueurs qui choisissent leur convoi." % missing) if missing > 1 \
			else "En attente d'un joueur qui choisit son convoi."
	elif host:
		wait_label.text = "Tout le monde est prêt : LANCER LA PARTIE."
	else:
		wait_label.text = "Tout le monde est prêt : celui qui héberge va lancer la partie."


func _refresh_rules() -> void:
	var host := NetSession.is_host()
	var r := NetSession.rules()
	rules_host.visible = host
	rules_guest.visible = not host
	rules_note.text = "Tu héberges : tu choisis, les autres voient tes choix en direct." if host \
		else "Choisies par celui qui héberge."
	var mode := int(r.get("mode", 0))
	var arena := mode == GameStateNode.GameMode.ARENA
	if host:
		for k in mode_buttons.size():
			mode_buttons[k].set_pressed_no_signal(MODES[k] == mode)
		mode_tip.text = MainMenu.MODE_TIPS[mode]
		track_option.select(int(r["track"]))
		for k in speed_buttons.size():
			speed_buttons[k].set_pressed_no_signal(k == int(r["speed_class"]))
		time_row.visible = arena
		drops_row.visible = not arena
		for k in time_buttons.size():
			time_buttons[k].set_pressed_no_signal(GameStateNode.ARENA_MINUTES[k] == int(r["arena_minutes"]))
		for k in drop_buttons.size():
			drop_buttons[k].set_pressed_no_signal(k == int(r["trailer_drops"]))
		var room := NetSessionNode.MAX_PLAYERS - maxi(NetSession.members.size(), 1)
		for k in bot_buttons.size():
			bot_buttons[k].set_pressed_no_signal(k == int(r["bots"]))
			bot_buttons[k].disabled = k > room
		for k in level_buttons.size():
			level_buttons[k].set_pressed_no_signal(k == int(r["bot_level"]))
			level_buttons[k].disabled = int(r["bots"]) == 0
		slow_check.set_pressed_no_signal(NetSession.snapshot_ticks > 1)
		return
	for c in rules_guest.get_children():
		rules_guest.remove_child(c)
		c.queue_free()
	if r.is_empty():
		_guest_line("", "En attente des règles…")
		return
	var c: Dictionary = GameStateNode.SPEED_CLASSES[int(r["speed_class"])]
	_guest_line("CIRCUIT", String(GameStateNode.TRACKS[int(r["track"])]["name"]).to_upper())
	_guest_line("MODE", "%s  ·  %s" % [GameStateNode.MODE_NAMES[mode], MainMenu.MODE_TIPS[mode]])
	_guest_line("VITESSE", "%s  %s" % [c["cc"], String(c["name"]).to_upper()])
	if arena:
		var minutes := int(r["arena_minutes"])
		_guest_line("DURÉE", "%d MIN" % minutes if minutes > 0 else "SANS LIMITE")
	else:
		_guest_line("LARGAGES", str(int(r["trailer_drops"])))
	var bots := int(r["bots"])
	_guest_line("BOTS", "%d  (%s)" % [bots, MainMenu.BOT_LEVELS[int(r["bot_level"])]] if bots > 0 else "AUCUN")
	_guest_line("CONNEXION", "lente (20 envois/s)" if int(r["send_ticks"]) > 1 else "normale (60 envois/s)")


func _guest_line(key: String, value: String) -> void:
	var k := UiKit.label(key, 18, UiKit.TEXT, 800)
	k.custom_minimum_size.x = 118
	rules_guest.add_child(k)
	var v := UiKit.label(value, 20, UiKit.CYAN if key != "" else UiKit.DIM, 700, false)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.custom_minimum_size.x = 600
	rules_guest.add_child(v)


func _refresh_players() -> void:
	var n := NetSession.members.size()
	var r := NetSession.rules()
	var bots := int(r.get("bots", 0))
	players_title.text = "%d / %d" % [n, NetSessionNode.MAX_PLAYERS]
	if NetSession.is_host():
		var ips := NetSessionNode.local_addresses()
		address_label.text = "Adresse à donner aux autres : %s" % (" ou ".join(ips) if not ips.is_empty() else "l'adresse IP de ce PC")
		# debit d'envoi de ce PC : il croit avec le carre du nombre de joueurs
		var mbps := NetSessionNode.host_uplink_kbps(n, n + bots, NetSession.snapshot_ticks) / 1000.0
		uplink_label.text = "" if n < 2 else "Envoi de ce PC : %.1f Mbit/s pour %d joueurs%s" % [mbps, n,
			"  ·  trop pour une ADSL : coche « Connexion lente »" if mbps > 1.0 and NetSession.snapshot_ticks == 1 else ""]
	else:
		address_label.text = ""
		uplink_label.text = ""
	address_label.visible = address_label.text != ""
	for c in players_box.get_children():
		players_box.remove_child(c)
		c.queue_free()
	for m in NetSession.members:
		players_box.add_child(_player_row(m))
	if bots > 0:
		var l := UiKit.label("+ %d bot%s (%s), simulé%s par celui qui héberge" % [bots, "s" if bots > 1 else "",
			MainMenu.BOT_LEVELS[int(r.get("bot_level", 1))], "s" if bots > 1 else ""], 17, UiKit.DIM, 600, false)
		players_box.add_child(l)


## Ligne d'un joueur : pastille a sa couleur (J1..J12), nom, host / toi,
## convoi choisi ou pas.
func _player_row(m: Dictionary) -> Control:
	var slot := int(m["slot"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var tag := PanelContainer.new()
	var sb := UiKit.box(UiKit.PLAYER_COLORS[slot], Color(1, 1, 1, 0.3), 1, UiKit.SKEW, 3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	tag.add_theme_stylebox_override("panel", sb)
	tag.custom_minimum_size = Vector2(58, 0)
	var tl := UiKit.label("J%d" % (slot + 1), 18, UiKit.NIGHT if UiKit.PLAYER_COLORS[slot].get_luminance() > 0.55 else UiKit.TEXT, 900)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_child(tl)
	row.add_child(tag)
	var who := String(m["name"])
	if int(m["peer"]) == 1:
		who += "  · hôte"
	if slot == NetSession.local_slot():
		who += "  · toi"
	var name_l := UiKit.label(who, 20, UiKit.TEXT, 800, false)
	name_l.custom_minimum_size.x = 300
	name_l.clip_text = true
	row.add_child(name_l)
	var ready := bool(m.get("ready", false))
	var state := UiKit.label(lobby_convoy(m), 17, UiKit.GOOD if ready else UiKit.DIM, 700, false)
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state.clip_text = true
	row.add_child(state)
	return row


## Convoi d'un membre du salon : « PRÊT · CITERNE · MISSILE + LASER », ou
## « choisit son convoi… ».
static func lobby_convoy(m: Dictionary) -> String:
	if not bool(m.get("ready", false)):
		return "choisit son convoi…"
	return "PRÊT  ·  %s  ·  %s + %s" % [TrailerCatalog.at(int(m["trailer"])).display_name.to_upper(),
		PowerCatalog.display_name(int(m["power_left"])), PowerCatalog.display_name(int(m["power_right"]))]


func _wrap(text: String, size: int, color: Color = Color(-1, -1, -1)) -> Label:
	var l := UiKit.label(text, size, color, 600, false)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200
	return l


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
