class_name NetSessionNode
extends Node

## Session reseau (autoload NetSession, phase 6, docs/NETCODE.md) : un PC
## heberge (host, peer 1, l'autorite), les autres le rejoignent par son
## adresse IP (reseau local, ou Internet avec le port UDP ouvert / un VPN).
##
##   host(port)        ouvre la partie ; le host est le joueur de la case 0
##   join(ip, port)    rejoint ; le host attribue une case (0 a 5) et diffuse
##                     le lobby a tous (members)
##   set_loadout(...)  remorque et pouvoirs de ce PC (page de selection du
##                     menu) : envoyes au host, diffuses avec le lobby, le
##                     joueur est alors PRET (ready)
##   launch_race()     host : circuit et categorie du host, puis la scene de
##                     course chez tout le monde (LocalRace lit la session)
##   stop_race()       host : arrete la course, chacun revient au salon
##                     (menu pause, 2026-10-22)
##   leave()           quitte, ferme la partie si on est le host
##
## Messages (NETCODE.md §7) : lobby, refus et depart de course en `reliable` ;
## les inputs et les snapshots de la course passent par NetRace en
## `unreliable_ordered`. Host qui part : la partie se termine (§8, pas de
## migration d'hote).
##
## Utilise le MultiplayerAPI de son chemin (`multiplayer`) : un test peut donc
## faire tourner un host et un client dans le meme processus.

signal lobby_changed
## Client : le host l'a accepte (case attribuee).
signal joined
signal join_failed(reason: String)
## Partie perdue (host parti, refus, coupure) ; deja revenu hors ligne.
signal connection_lost(reason: String)
## Host : un joueur est parti (case liberee).
signal member_left(slot: int, peer_id: int)
signal race_launched
## Le host a arrete la course (menu pause) : retour au salon.
signal race_stopped

enum Mode { OFFLINE, HOST, CLIENT }

const DEFAULT_PORT := 7777
## 12 joueurs (2026-10-22 ; 6 avant).
const MAX_PLAYERS := 12
## Versions de protocole differentes : le host refuse le client.
## 4 (2026-10-21) : mode de jeu au lancement, eliminations et vies dans l'etat
## de course.
## 5 (2026-10-21) : duree de l'arene au lancement.
## 6 (2026-10-22) : nombre et niveau des bots du host au lancement.
## 7 (2026-10-22) : 12 joueurs (cases 6 a 11 : une version a 6 couleurs
## plantait sur ces cases).
## 8 (2026-10-22) : regles du host dans le lobby (menu en ligne : chacun voit
## mode, circuit, vitesse et bots avant le lancement).
const PROTOCOL := 10
## Menu principal : retour au salon quand le host arrete la course.
const MENU_SCENE := "res://ui/main_menu.tscn"
const MAX_NAME := 16
## En-tetes par datagramme (UDP + IP + ENet, NETCODE.md §3).
const PACKET_OVERHEAD := 48
## Coupure detectee (ENet, ENetPacketPeer.set_timeout) : en course, 3 s au
## moins, 8 s au plus ; pendant les chargements (scene, carrosseries : la
## machine ne repond plus pendant quelques secondes), 15 a 60 s : une machine
## lente se fige ~5 s d'un bloc en chargeant la course, un host surcharge
## jusqu'a 16 s (mesures 2026-10-19, deux instances sur un PC) ; au reglage
## d'ENet (5 a 30 s), le client etait coupe une fois sur deux.
const TIMEOUT_MIN_MS := 3000
const TIMEOUT_MAX_MS := 8000
const LOADING_TIMEOUT_MIN_MS := 15000
const LOADING_TIMEOUT_MAX_MS := 60000
## Cadence des snapshots pour une connexion qui envoie peu : 20 Hz.
const SNAPSHOT_TICKS_LOW_BANDWIDTH := 3

var mode: Mode = Mode.OFFLINE
## Lobby, trie par case : [{"peer": int, "name": String, "slot": int,
## "trailer": int, "power_left": int, "power_right": int, "ready": bool}]
## (choix de la page de selection, PowerCatalog : -1 = aucun).
var members: Array[Dictionary] = []
## Regles de la partie (rules()), recues du host avec le lobby ; vide hors
## ligne. Le host lit les siennes dans GameState.
var host_rules: Dictionary = {}
var player_name: String = ""
## Faux pour les tests : launch_race ne change pas de scene.
var auto_change_scene: bool = true
## Raison du dernier echec ou de la derniere deconnexion (affichee au menu).
var last_error: String = ""
## Version annoncee au host (PROTOCOL ; un test en change pour etre refuse).
var protocol: int = PROTOCOL
## Snapshots du host : tous les snapshot_ticks ticks. 1 = 60 Hz, le moins de
## delai (~270 kbps montants a 4 joueurs) ; 3 = 20 Hz pour une connexion qui
## envoie peu (~90 kbps). Choisi par le host, transmis au lancement.
var snapshot_ticks: int = 1
## Tests seulement (NETCODE.md §9) : delai (ms) ajoute a chaque paquet
## d'inputs ou de snapshot que CETTE machine envoie. 50 des deux cotes : 100 ms
## d'aller-retour. Ligne de commande : -- --net-latency=50.
var debug_latency_ms: int = 0
## Tests seulement : part (%) des paquets d'inputs et de snapshots que CETTE
## machine jette au lieu de les envoyer (les messages reliable ne sont jamais
## perdus : ENet les renvoie). Ligne de commande : -- --net-loss=2.
var debug_loss_percent: float = 0.0
## Tests seulement : gigue (ms), de 0 a cette valeur en plus de la latence,
## tiree pour chaque paquet (l'ordre d'envoi est garde). -- --net-jitter=15.
var debug_jitter_ms: int = 0

var _peer: ENetMultiplayerPeer
var _api: MultiplayerAPI


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if player_name == "":
		player_name = default_name()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net-latency="):
			debug_latency_ms = maxi(a.get_slice("=", 1).to_int(), 0)
		elif a.begins_with("--net-loss="):
			debug_loss_percent = clampf(a.get_slice("=", 1).to_float(), 0.0, 100.0)
		elif a.begins_with("--net-jitter="):
			debug_jitter_ms = maxi(a.get_slice("=", 1).to_int(), 0)


static func default_name() -> String:
	var n := OS.get_environment("USERNAME")
	if n == "":
		n = OS.get_environment("USER")
	return clean_name(n if n != "" else "Joueur")


static func clean_name(n: String) -> String:
	n = n.strip_edges().strip_escapes()
	return (n if n != "" else "Joueur").left(MAX_NAME)


func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


## Case de ce PC dans la course (-1 hors ligne ou pas encore accepte).
func local_slot() -> int:
	return slot_of_peer(_my_id())


func slot_of_peer(peer_id: int) -> int:
	for m in members:
		if int(m["peer"]) == peer_id:
			return int(m["slot"])
	return -1


func peer_of_slot(slot: int) -> int:
	for m in members:
		if int(m["slot"]) == slot:
			return int(m["peer"])
	return 0


func name_of_slot(slot: int) -> String:
	for m in members:
		if int(m["slot"]) == slot:
			return String(m["name"])
	return ""


## Adresses IPv4 de ce PC a donner aux autres joueurs (reseau local d'abord).
static func local_addresses() -> PackedStringArray:
	var lan := PackedStringArray()
	var other := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or _is_172_private(a):
			lan.append(a)
		else:
			other.append(a)
	lan.append_array(other)
	return lan


static func _is_172_private(a: String) -> bool:
	if not a.begins_with("172."):
		return false
	var b := a.get_slice(".", 1).to_int()
	return b >= 16 and b <= 31


## Debit montant du host (kbps, en-tetes compris) : un snapshot de `trucks`
## camions a chacun des `players - 1` autres joueurs, tous les `ticks` ticks.
## 12 joueurs a 60 Hz : ~2,6 Mbit/s ; a 20 Hz : ~0,9.
static func host_uplink_kbps(players: int, trucks: int, ticks: int) -> float:
	var size := NetRace.SNAPSHOT_HEADER + trucks * TruckState.SIZE + 1 + PACKET_OVERHEAD
	return size * 60.0 / maxf(ticks, 1.0) * maxi(players - 1, 0) * 8.0 / 1000.0


# --- ouverture et fermeture ---------------------------------------------------

func host(port: int = DEFAULT_PORT) -> Error:
	leave()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		last_error = "Impossible d'ouvrir le port %d (déjà utilisé ?)" % port
		return err
	_attach(p)
	mode = Mode.HOST
	members = [_member(1, player_name, 0)]
	last_error = ""
	lobby_changed.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	address = address.strip_edges()
	if address == "":
		last_error = "Adresse du host vide"
		return ERR_INVALID_PARAMETER
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(address, port)
	if err != OK:
		last_error = "Adresse invalide : %s" % address
		return err
	_attach(p)
	mode = Mode.CLIENT
	members = []
	last_error = ""
	return OK


## Quitte la partie (le host la ferme pour tous). Sans effet hors ligne.
func leave() -> void:
	if _api != null:
		for pair: Array in _signal_pairs():
			var sig: Signal = pair[0]
			if sig.is_connected(pair[1]):
				sig.disconnect(pair[1])
		_api.multiplayer_peer = null
	if _peer != null:
		_peer.close()
	_peer = null
	_api = null
	mode = Mode.OFFLINE
	members = []
	host_rules = {}
	lobby_changed.emit()


func _attach(p: ENetMultiplayerPeer) -> void:
	_peer = p
	_api = multiplayer
	_api.multiplayer_peer = p
	for pair: Array in _signal_pairs():
		(pair[0] as Signal).connect(pair[1])


func _signal_pairs() -> Array:
	return [
		[_api.peer_connected, _on_peer_connected],
		[_api.peer_disconnected, _on_peer_disconnected],
		[_api.connected_to_server, _on_connected],
		[_api.connection_failed, _on_connection_failed],
		[_api.server_disconnected, _on_server_disconnected],
	]


func _my_id() -> int:
	if _api == null or _api.multiplayer_peer == null:
		return 0
	return _api.get_unique_id()


# --- lobby ------------------------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	pass   # le client se presente ensuite (_hello)


## Detection de coupure rapide (en course) ou tolerante (chargement) pour le
## peer id.
func set_fast_timeout(id: int, fast: bool) -> void:
	var p := _peer.get_peer(id) if _peer != null else null
	if p != null:
		p.set_timeout(32, TIMEOUT_MIN_MS if fast else LOADING_TIMEOUT_MIN_MS,
			TIMEOUT_MAX_MS if fast else LOADING_TIMEOUT_MAX_MS)


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	var slot := slot_of_peer(id)
	if slot < 0:
		return
	var kept: Array[Dictionary] = []
	kept.assign(members.filter(func(m: Dictionary) -> bool: return int(m["peer"]) != id))
	members = kept
	_broadcast_lobby()
	member_left.emit(slot, id)


func _on_connected() -> void:
	_hello.rpc_id(1, player_name, protocol)


func _on_connection_failed() -> void:
	var reason := "Aucun host ne répond à cette adresse"
	leave()
	last_error = reason
	join_failed.emit(reason)


func _on_server_disconnected() -> void:
	var reason := last_error if last_error != "" else "Le host a quitté la partie"
	leave()
	last_error = reason
	connection_lost.emit(reason)


## Client -> host : presentation. Le host attribue la premiere case libre.
@rpc("any_peer", "call_remote", "reliable")
func _hello(name_in: String, protocol: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if slot_of_peer(id) >= 0:
		return
	var refuse := ""
	if protocol != PROTOCOL:
		refuse = "Version du jeu différente de celle du host"
	elif members.size() >= MAX_PLAYERS:
		refuse = "Partie complète (%d joueurs)" % MAX_PLAYERS
	if refuse != "":
		_refused.rpc_id(id, refuse)
		# apres l'envoi du refus (disconnect_peer le perdrait)
		_peer.get_peer(id).peer_disconnect_later()
		return
	var used: Array[int] = []
	for m in members:
		used.append(int(m["slot"]))
	var slot := 0
	while used.has(slot):
		slot += 1
	members.append(_member(id, clean_name(name_in), slot))
	members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["slot"]) < int(b["slot"]))
	_broadcast_lobby()


static func _member(peer: int, member_name: String, slot: int, trailer: int = 0, left: int = -1,
		right: int = -1, ready: bool = false) -> Dictionary:
	return {"peer": peer, "name": member_name, "slot": slot, "trailer": trailer,
		"power_left": left, "power_right": right, "ready": ready}


## Remorque et pouvoirs du joueur de ce PC, choisis sur la page de selection :
## le joueur devient PRET. Host : applique et diffuse ; client : au host.
func set_loadout(trailer: int, left: int, right: int) -> void:
	if is_host():
		_apply_loadout(1, trailer, left, right)
	elif is_client():
		_loadout.rpc_id(1, trailer, left, right)


@rpc("any_peer", "call_remote", "reliable")
func _loadout(trailer: int, left: int, right: int) -> void:
	if is_host():
		_apply_loadout(multiplayer.get_remote_sender_id(), trailer, left, right)


func _apply_loadout(peer: int, trailer: int, left: int, right: int) -> void:
	for m in members:
		if int(m["peer"]) == peer:
			m["trailer"] = posmod(trailer, TrailerCatalog.count())
			m["power_left"] = _power(left)
			m["power_right"] = _power(right)
			m["ready"] = true
			_broadcast_lobby()
			return


static func _power(p: int) -> int:
	return p if p >= 0 and p < PowerCatalog.count() else -1


## Choix du joueur de la case `slot` (membre du lobby), {} si personne.
func member_of_slot(slot: int) -> Dictionary:
	for m in members:
		if int(m["slot"]) == slot:
			return m
	return {}


## Tous les joueurs de la partie ont choisi leur convoi (PRET).
func all_ready() -> bool:
	if members.is_empty():
		return false
	for m in members:
		if not bool(m["ready"]):
			return false
	return true


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	last_error = reason


## Lobby et regles a tous les joueurs acceptes (pas a un peer refuse, encore
## en train de se deconnecter).
func _broadcast_lobby() -> void:
	lobby_changed.emit()
	if _api == null or _api.multiplayer_peer == null:
		return
	var data := _pack(members)
	var r := _pack_rules(rules())
	for id in _guest_peers():
		_lobby.rpc_id(id, data, r)


## Host : regles changees au menu, envoyees a tous.
func push_rules() -> void:
	if is_host():
		_broadcast_lobby()


## Regles de la partie : celles du menu du host (GameState) chez le host,
## celles recues chez un client. Le contre-la-montre devient une course, les
## bots sont bornes aux places libres, "send_ticks" : cadence des snapshots.
func rules() -> Dictionary:
	if is_client():
		return host_rules
	var r := GameState.rules()
	r["mode"] = online_mode(int(r["mode"]))
	r["bots"] = clampi(int(r["bots"]), 0, MAX_PLAYERS - maxi(members.size(), 1))
	r["send_ticks"] = snapshot_ticks
	return r


const RULES_ORDER: PackedStringArray = ["track", "speed_class", "mode", "arena_minutes", "trailer_drops", "bots",
	"bot_level", "send_ticks"]


static func _pack_rules(r: Dictionary) -> Array:
	var out := []
	for k: String in RULES_ORDER:
		out.append(int(r.get(k, 0)))
	return out


static func _unpack_rules(a: Array) -> Dictionary:
	if a.size() != RULES_ORDER.size():
		return {}
	var r := {}
	for i in RULES_ORDER.size():
		r[RULES_ORDER[i]] = int(a[i])
	r["track"] = clampi(int(r["track"]), 0, GameStateNode.TRACKS.size() - 1)
	r["speed_class"] = clampi(int(r["speed_class"]), 0, GameStateNode.SPEED_CLASSES.size() - 1)
	r["mode"] = online_mode(int(r["mode"]))
	r["trailer_drops"] = clampi(int(r["trailer_drops"]), 0, GameStateNode.MAX_TRAILER_DROPS)
	r["bots"] = clampi(int(r["bots"]), 0, MAX_PLAYERS - 1)
	r["bot_level"] = clampi(int(r["bot_level"]), 0, 2)
	r["send_ticks"] = clampi(int(r["send_ticks"]), 1, SNAPSHOT_TICKS_LOW_BANDWIDTH)
	if not GameStateNode.ARENA_MINUTES.has(int(r["arena_minutes"])):
		r["arena_minutes"] = 4
	return r


func _guest_peers() -> Array[int]:
	var ids: Array[int] = []
	for m in members:
		if int(m["peer"]) != 1:
			ids.append(int(m["peer"]))
	return ids


@rpc("authority", "call_remote", "reliable")
func _lobby(data: Array, rules_data: Array) -> void:
	var was_in := local_slot() >= 0
	members = _unpack(data)
	host_rules = _unpack_rules(rules_data)
	lobby_changed.emit()
	if not was_in and local_slot() >= 0:
		joined.emit()


static func _pack(list: Array[Dictionary]) -> Array:
	var out := []
	for m in list:
		out.append([int(m["peer"]), String(m["name"]), int(m["slot"]), int(m["trailer"]),
			int(m["power_left"]), int(m["power_right"]), bool(m["ready"])])
	return out


static func _unpack(data: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Variant in data:
		var a := e as Array
		if a == null or a.size() != 7:
			continue
		out.append(_member(int(a[0]), clean_name(str(a[1])), clampi(int(a[2]), 0, MAX_PLAYERS - 1),
			posmod(int(a[3]), TrailerCatalog.count()), _power(int(a[4])), _power(int(a[5])), bool(a[6])))
	return out


# --- course ------------------------------------------------------------------------

## Mode de jeu d'une partie en ligne (2026-10-21 : « tous les modes en ligne,
## à part le contre-la-montre ») : celui du host, ou une course normale s'il a
## choisi le contre-la-montre (seul contre son fantome).
static func online_mode(mode: int) -> int:
	if mode == GameStateNode.GameMode.TIME_TRIAL:
		return GameStateNode.GameMode.RACE
	return clampi(mode, 0, GameStateNode.MODE_NAMES.size() - 1)


## Host : lance la course pour tous, sur le circuit, la categorie, le mode,
## la duree de l'arene et les bots (nombre, niveau) choisis au menu du host.
func launch_race() -> void:
	if not is_host():
		return
	var data := _pack(members)
	var mode := online_mode(GameState.game_mode)
	for id in _guest_peers():
		_launch.rpc_id(id, GameState.selected_track, GameState.speed_class, snapshot_ticks, data, GameState.trailer_drops, mode,
			GameState.arena_minutes, GameState.bot_count, GameState.bot_level)
	_launch(GameState.selected_track, GameState.speed_class, snapshot_ticks, data, GameState.trailer_drops, mode,
		GameState.arena_minutes, GameState.bot_count, GameState.bot_level)


## Host : arrete la course en cours pour tous (menu pause, « ARRETER LA
## COURSE ») ; la partie reste ouverte, chacun revient au salon du menu.
func stop_race() -> void:
	if not is_host():
		return
	for id in _guest_peers():
		_stop.rpc_id(id)
	_stop()


@rpc("authority", "call_remote", "reliable")
func _stop() -> void:
	# le menu se charge : chacun peut se figer un moment (comme au depart)
	for m in members:
		var id := int(m["peer"])
		if is_host() and id != 1:
			set_fast_timeout(id, false)
		elif is_client() and id == 1:
			set_fast_timeout(1, false)
	race_stopped.emit()
	if auto_change_scene:
		get_tree().change_scene_to_file(MENU_SCENE)


@rpc("authority", "call_remote", "reliable")
func _launch(track: int, speed_class: int, send_ticks: int, data: Array, drops: int = 3, mode: int = 0,
		arena_minutes: int = 4, bots: int = 0, bot_level: int = 1) -> void:
	# chargement de la course : chacun peut se figer quelques secondes
	for m in members:
		var id := int(m["peer"])
		if is_host() and id != 1:
			set_fast_timeout(id, false)
		elif is_client() and id == 1:
			set_fast_timeout(1, false)
	snapshot_ticks = clampi(send_ticks, 1, SNAPSHOT_TICKS_LOW_BANDWIDTH)
	GameState.selected_track = clampi(track, 0, GameStateNode.TRACKS.size() - 1)
	GameState.speed_class = clampi(speed_class, 0, GameStateNode.SPEED_CLASSES.size() - 1)
	GameState.trailer_drops = clampi(drops, 0, GameStateNode.MAX_TRAILER_DROPS)
	# avant le choix de la scene : l'arene remplace le circuit (track_scene)
	GameState.game_mode = online_mode(mode)
	# le compte a rebours de l'arene est le meme chez tous
	GameState.arena_minutes = arena_minutes if GameStateNode.ARENA_MINUTES.has(arena_minutes) else 4
	# les bots du host : il les simule, chacun les voit (LocalRace)
	GameState.bot_count = clampi(bots, 0, MAX_PLAYERS - 1)
	GameState.bot_level = clampi(bot_level, 0, 2)
	members = _unpack(data)
	race_launched.emit()
	if auto_change_scene:
		LoadingScreen.go(get_tree(), GameStateNode.track_scene(GameState.selected_track))
