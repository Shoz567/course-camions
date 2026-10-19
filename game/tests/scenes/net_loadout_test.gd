extends PhysicsTest

## Page de selection en ligne (2026-10-19 : « mettre les ecrans de selection de
## remorque et pouvoir du solo en multijoueur ») :
##   A. un client choisit son convoi : le host le recoit (remorque, pouvoirs,
##      PRET) et le rediffuse, le lobby est le meme des deux cotes ; un
##      pouvoir inconnu devient AUCUN ;
##   B. PRET pour tous seulement quand le host a aussi choisi ;
##   C. en course (host seul, autoload NetSession), le camion porte la
##      remorque et les pouvoirs envoyes au lobby, pas ceux du GameState.

const PORT := 17781
const TIMEOUT := 240

var host: NetSessionNode
var guest: NetSessionNode
var _stage: int = 0
var _stage_tick: int = 0
var _race: Node3D


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
	duration_ticks = TIMEOUT * 4
	host = _session("Host", "Hote")
	guest = _session("Guest", "Invite")
	check("host ouvert", host.host(PORT) == OK, host.last_error)
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
				check("personne n'est PRET a l'arrivee", not host.all_ready()
					and not bool(host.member_of_slot(1)["ready"]))
				guest.set_loadout(3, PowerCatalog.Id.MISSILE, 99)
				_next(t)
		1:
			var m := host.member_of_slot(1)
			if bool(m.get("ready", false)) and bool(guest.member_of_slot(1).get("ready", false)):
				check("host : convoi du client recu (remorque 3, MISSILE, inconnu -> AUCUN)",
					int(m["trailer"]) == 3 and int(m["power_left"]) == PowerCatalog.Id.MISSILE
					and int(m["power_right"]) == -1, str(m))
				check("meme lobby des deux cotes", str(host.members) == str(guest.members), str(guest.members))
				check("pas encore PRET pour tous : le host n'a pas choisi", not host.all_ready() and not guest.all_ready())
				host.set_loadout(1, PowerCatalog.Id.SHIELD, PowerCatalog.Id.LASER)
				_next(t)
		2:
			if guest.all_ready():
				check("tous PRETS, des deux cotes", host.all_ready())
				host.leave()
				guest.leave()
				# C : course en ligne, host seul (autoload)
				check("autoload : partie ouverte", NetSession.host(PORT + 1) == OK, NetSession.last_error)
				GameState.trailer_choice[0] = 0
				GameState.power_left[0] = -1
				GameState.power_right[0] = -1
				NetSession.set_loadout(2, PowerCatalog.Id.LASER, PowerCatalog.Id.MISSILE)
				_race = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
				add_child(_race)
				_next(t)
		3:
			if t - _stage_tick >= 5:
				var players: Array = _race.get("players")
				var p: Object = players[0]
				var tp := TruckPowers.of(p.get("truck") as Truck)
				check("course : remorque du lobby", int(p.get("trailer")) == 2, str(p.get("trailer")))
				check("course : pouvoirs du lobby sur le camion", tp != null
					and tp.slots == PackedInt32Array([PowerCatalog.Id.LASER, PowerCatalog.Id.MISSILE]),
					str(tp.slots if tp != null else null))
				_next(t)
				duration_ticks = t + 1


func _test_finish() -> void:
	check("toutes les etapes", _stage == 4, "etape %d" % _stage)
	for s in [host, guest]:
		(s as NetSessionNode).leave()
	NetSession.leave()
