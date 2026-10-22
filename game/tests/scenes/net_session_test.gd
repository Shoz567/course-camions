extends PhysicsTest

## Session reseau en vrai (ENet sur 127.0.0.1), host et clients dans le meme
## processus, chacun avec son propre MultiplayerAPI (phase 6, tache 6.1) :
##   - un client rejoint : case 1, le lobby (noms, cases) est le meme des deux
##     cotes ;
##   - un client d'une autre version est refuse, avec la raison ;
##   - les regles du host (menu en ligne, 2026-10-22) arrivent au client avec
##     le lobby, avant le lancement : circuit, categorie, mode, duree, bots ;
##   - le host lance la course : circuit, categorie et mode du host chez le
##     client (2026-10-21 : arene ; le contre-la-montre devient une course),
##     avec la duree de l'arene du host et ses bots (nombre, niveau ; 2026-10-22) ;
##   - un client qui part libere sa case (member_left) ;
##   - le host qui part termine la partie chez le client (connection_lost).

const PORT := 17777
const TIMEOUT := 240

var host: NetSessionNode
var guest: NetSessionNode
var stranger: NetSessionNode
var _stage: int = 0
var _stage_tick: int = 0
var _launched: int = 0
var _bots_saved: Array = []
var _left: Array = []
var _lost_reason: String = ""
var _refused_reason: String = ""


func _session(owner_name: String, player: String) -> NetSessionNode:
	var holder := Node.new()
	holder.name = owner_name
	add_child(holder)
	get_tree().set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var s := NetSessionNode.new()
	s.name = "Session"
	s.player_name = player
	s.auto_change_scene = false
	holder.add_child(s)
	return s


func _test_setup() -> void:
	duration_ticks = TIMEOUT * 5
	host = _session("Host", "Hote")
	guest = _session("Guest", "Invite")
	stranger = _session("Stranger", "Ancien")
	stranger.protocol = NetSessionNode.PROTOCOL + 1
	guest.race_launched.connect(func() -> void: _launched += 1)
	host.member_left.connect(func(slot: int, _peer: int) -> void: _left.append(slot))
	guest.connection_lost.connect(func(reason: String) -> void: _lost_reason = reason)
	stranger.connection_lost.connect(func(reason: String) -> void: _refused_reason = reason)
	check("host ouvert sur le port %d" % PORT, host.host(PORT) == OK, host.last_error)
	check("client : connexion demandee", guest.join("127.0.0.1", PORT) == OK, guest.last_error)


func _next(t: int) -> void:
	_stage += 1
	_stage_tick = t


func _test_tick(t: int) -> void:
	if t - _stage_tick > TIMEOUT:
		abort("etape %d : rien apres %d ticks" % [_stage, TIMEOUT])
		return
	match _stage:
		0:
			if guest.local_slot() == 1 and host.members.size() == 2:
				check("client accepte en case 1, host en case 0", host.local_slot() == 0 and guest.local_slot() == 1)
				check("meme lobby des deux cotes",
					str(host.members) == str(guest.members) and guest.name_of_slot(0) == "Hote"
					and host.name_of_slot(1) == "Invite", str(guest.members))
				check("client vu comme client, host comme host", guest.is_client() and host.is_host())
				stranger.join("127.0.0.1", PORT)
				_next(t)
		1:
			if _refused_reason != "":
				check("autre version : refusee, avec la raison", _refused_reason.contains("Version")
					and not stranger.is_online() and host.members.size() == 2, _refused_reason)
				GameState.selected_track = 1
				GameState.speed_class = 2
				GameState.game_mode = GameStateNode.GameMode.ARENA
				GameState.arena_minutes = 8
				_bots_saved = [GameState.bot_count, GameState.bot_level]
				GameState.bot_count = 3
				GameState.bot_level = BotInputSource.Level.HARD
				# regles au salon, puis lancement (messages fiables, dans l'ordre)
				host.push_rules()
				host.launch_race()
				# meme processus : on efface ce que le host vient de poser, le client
				# doit le reecrire en recevant le lancement
				GameState.game_mode = GameStateNode.GameMode.RACE
				GameState.arena_minutes = 2
				GameState.bot_count = 0
				GameState.bot_level = BotInputSource.Level.EASY
				_next(t)
		2:
			if _launched > 0:
				check("course lancee chez le client : circuit, categorie et mode du host",
					GameState.selected_track == 1 and GameState.speed_class == 2 and guest.members.size() == 2
					and GameState.game_mode == GameStateNode.GameMode.ARENA, str(GameState.game_mode))
				check("duree de l'arene du host chez le client", GameState.arena_minutes == 8, str(GameState.arena_minutes))
				var r := guest.host_rules
				check("regles du host recues au salon, avant le lancement", not r.is_empty() and int(r["track"]) == 1
					and int(r["speed_class"]) == 2 and int(r["mode"]) == GameStateNode.GameMode.ARENA
					and int(r["arena_minutes"]) == 8 and int(r["bots"]) == 3 and int(r["bot_level"]) == BotInputSource.Level.HARD
					and int(r["send_ticks"]) == 1 and str(guest.rules()) == str(r), str(r))
				check("bots du host chez le client (nombre, niveau)", GameState.bot_count == 3
					and GameState.bot_level == BotInputSource.Level.HARD, "%d %d" % [GameState.bot_count, GameState.bot_level])
				check("en ligne : le contre-la-montre devient une course, les autres modes restent",
					NetSessionNode.online_mode(GameStateNode.GameMode.TIME_TRIAL) == GameStateNode.GameMode.RACE
					and NetSessionNode.online_mode(GameStateNode.GameMode.ELIMINATION) == GameStateNode.GameMode.ELIMINATION)
				guest.leave()
				_next(t)
		3:
			if not _left.is_empty():
				check("client parti : sa case liberee chez le host", _left == [1] and host.members.size() == 1,
					"%s %s" % [_left, host.members])
				check("client parti : hors ligne", not guest.is_online())
				guest.join("127.0.0.1", PORT)
				_next(t)
		4:
			if guest.local_slot() == 1:
				host.leave()
				_next(t)
		5:
			if _lost_reason != "":
				check("host parti : partie terminee chez le client", not guest.is_online(), _lost_reason)
				_next(t)
				duration_ticks = t + 1


func _test_finish() -> void:
	check("toutes les etapes", _stage == 6, "etape %d" % _stage)
	GameState.selected_track = 0
	GameState.speed_class = GameStateNode.SpeedClass.NORMAL
	GameState.game_mode = GameStateNode.GameMode.RACE
	GameState.arena_minutes = 4
	if not _bots_saved.is_empty():
		GameState.bot_count = _bots_saved[0]
		GameState.bot_level = _bots_saved[1]
	for s in [host, guest, stranger]:
		(s as NetSessionNode).leave()
