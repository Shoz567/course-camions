class_name NetRace
extends Node

## Course en ligne (phase 6, docs/NETCODE.md) : enfant de LocalRace quand
## NetSession est en ligne. Meme chemin chez tout le monde (meme scene de
## course) : les RPC s'y retrouvent. Objectif : le moins de delai possible.
##
## Host (l'autorite) : simule toute la course. Les joueurs distants pilotent
## par RemoteInputSource. A chaque envoi (NetSession.snapshot_ticks : chaque
## tick par defaut, 60 Hz) : etat de tous les camions (TruckState, 32 o
## chacun) a chaque client, avec la derniere frame de CE client deja prise
## en compte (ack). Etat de la course et tours : `reliable`, a chaque
## changement, et en entier a un client qui vient de charger la scene.
## Paquets pousses tout de suite (flush ENet), sans attendre l'image suivante.
##
## Client :
##   - SON camion est PREDIT (NETCODE.md §5) : simule ici avec ses inputs, il
##     repond sans aucun delai. Chaque snapshot donne l'etat du host apres la
##     frame `ack` ; la difference avec la prediction gardee pour cette frame
##     (historique) est corrigee en douceur (CORRECTION_RATE par tick), ou d'un
##     coup au-dela de SNAP_DISTANCE / SNAP_ANGLE_DEG. Les decisions de jeu
##     (PV, pneus, cargo) restent au host : leurs noeuds sont en miroir ici
##     (net_mirror). Ce que touche SON camion (baril, panneau, plaque) reagit
##     tout de suite ici ; le host confirme.
##   - Les AUTRES camions sont des marionnettes (obstacles cinematiques),
##     rendues un intervalle de snapshots + 1 tick en arriere (2 ticks, ~33 ms
##     a 60 Hz) : le moins de delai possible. Un snapshot en retard (gigue) est
##     couvert par l'extrapolation par les vitesses, quasi exacte sur quelques
##     ticks pour un camion (~4 cm en 3 ticks, a 30 m/s en virage serre) ;
##     EXTRAPOLATE_MAX_TICKS au plus, puis gel.
##   - Inputs : un paquet par tick, la frame du tick et les deux precedentes
##     (un paquet perdu ne perd rien).
## Le client ne valide rien (tours, classement) : il affiche ce que le host a
## valide.

const EXTRAPOLATE_MAX_TICKS := 15
## Ecart au-dela duquel une marionnette saute (reapparition, reset) au lieu
## d'etre interpolee depuis l'ancienne position.
const TELEPORT_DISTANCE := 8.0
## En deca (m, entre centres), un autre camion devient un obstacle physique
## (Truck.set_net_near) : camion + remorque font ~20 m.
const NEAR_DISTANCE := 25.0
## Retard de rendu des marionnettes (ticks) : bornes de l'adaptation.
const MIN_INTERP_TICKS := 1.0
const MAX_INTERP_TICKS := 12.0
## Camion predit : part de l'ecart corrigee a chaque tick (~10 ticks pour
## l'essentiel), et seuils du saut assume (NETCODE.md §5).
const CORRECTION_RATE := 0.2
const SNAP_DISTANCE := 3.0
const SNAP_ANGLE_DEG := 45.0
## Ecart sous lequel on ne corrige rien (bruit de quantification).
const DEAD_ZONE := 0.02
## Historique de la prediction : 2 s de ticks.
const HISTORY := 128
## En-tete du snapshot : tick du host (u32), nombre de camions (u8), ack (u16),
## ack valide (u8).
const SNAPSHOT_HEADER := 8
const BUFFER_SNAPSHOTS := 64
const TICK_S := 1.0 / 60.0
## Pose d'un obstacle dans le snapshot : id (u16), position (3 x f32),
## orientation (u32).
const OBJECT_SIZE := 18
const MAX_OBJECTS := 40
## Un obstacle immobile est quand meme renvoye tous les KEYFRAME_TICKS ticks.
const KEYFRAME_TICKS := 30
## Evenements de jeu (_event), du host vers les clients.
enum Ev { WRECK, RESPAWN, TRAILER_EXPLODED, DROP, OBJECT_HIT, OBJECT_GONE, BARREL, SIGN, IMPACT, LEFT, POWER, PICKUP }

var race_scene: Node
var players: Array = []
var laps: RaceLaps
## Envoi d'un snapshot tous les `snapshot_ticks` ticks (1 = 60 Hz).
var snapshot_ticks: int = 1

## Host : index du joueur pilote par chaque peer distant.
var _peer_index: Dictionary = {}
## Host : peers dont la scene de course est chargee (prets a recevoir).
var _ready_peers: Dictionary = {}
## Host : peers prets, en attente de la detection de coupure rapide (posee
## une fois l'ecran de chargement du host leve, cf. _scene_ready).
var _slow_peers: Dictionary = {}
## Client : detection de coupure rapide posee (apres le sas READY).
var _fast_timeout: bool = false
var _last_state_sig: String = ""
## Client : joueur de cette machine, ses dernieres frames, snapshots recus,
## horloge du host.
var _local: int = -1
var _frames: PackedByteArray = PackedByteArray()
var _sent_frames: int = 0
var _snaps: Array[Dictionary] = []
var _offset: float = 0.0
var _offset_known: bool = false
## Dispersion moyenne des arrivees autour du decalage moyen (ticks).
var _dev: float = 0.0
var _interval: float = 1.0
var _interp_ticks: float = MIN_INTERP_TICKS
var _pose: Array[TruckState] = []
var _tmp: TruckState = TruckState.new()
## Prediction : historique par tick (cle : tick % HISTORY).
var _hist_tick := PackedInt32Array()
var _hist_state: Array[TruckState] = []
var _hist_applied: Array[TruckState] = []
## Corrections deja appliquees depuis le depart (cumul), et restant a faire.
var _applied: TruckState = TruckState.new()
var _pending: TruckState = TruckState.new()
var _pending_trailer: float = 0.0
var _has_pending: bool = false
## Dernier snapshot portant un ack, a reconcilier au prochain tick.
var _ack_snap: Dictionary = {}
## Paquets retenus par la latence simulee (NetSession.debug_latency_ms) :
## [echeance ms, inputs ?, peer, octets].
var _delayed: Array = []
## Perte simulee (NetSession.debug_loss_percent) : tirage reproductible.
var _loss_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var packets_lost: int = 0
## Host : chocs releves entre un camion et un autre corps (tests de contact).
var body_impacts: int = 0
var impact_log: Array = []
## Client : le host a repondu (premier etat de course recu) ; avant, on
## renouvelle l'annonce et on n'envoie aucun input (il les perdrait s'il
## charge encore sa scene).
var host_ready: bool = false
var _announce_wait: int = 0
## Mesures (tests, NETCODE.md §9).
var bytes_snapshots_sent: int = 0
var bytes_inputs_sent: int = 0
var snapshots_received: int = 0
## Etats de course envoyes (host) / recus (client).
var states_sent: int = 0
var states_received: int = 0
var corrections: int = 0
var snaps: int = 0
var last_error_m: float = 0.0
var max_error_m: float = 0.0
## Sauts assumes du camion predit : [tick, ecart m, ecart deg] (tests).
var snap_log: Array = []
## Poses de marionnettes extrapolees (aucun snapshot plus recent) / toutes.
var poses_extrapolated: int = 0
var poses_total: int = 0
## A-coups visibles des marionnettes : ecart entre la pose d'un tick et celle
## que leur vitesse annoncait depuis le tick d'avant (m), hors sauts assumes.
var pop_sum: float = 0.0
var pop_count: int = 0
var pop_max: float = 0.0
var _last_pose_pos: Array[Vector3] = []
var _last_pose_vel: Array[Vector3] = []
## Obstacles nes en course (remorques larguees, carcasses), meme id partout :
## id -> noeud ; host : instance_id -> id.
var _objects: Dictionary = {}
var _object_id: Dictionary = {}
var _next_object_id: int = 1
## Barils et panneaux du circuit : meme ordre chez tout le monde (meme scene).
var _barrels: Array[ExplosiveBarrel] = []
var _pickups: Array[TrackPickup] = []
var _signs: Array[RoadsideSign] = []
## Client : derniers flags appliques par camion (klaxon, boost : fronts).
var _last_flags: PackedInt32Array = PackedInt32Array()
var _last_snapshot_local: int = 0
var events_sent: int = 0
var events_received: int = 0
## Client : remorque larguee tout de suite par notre camion (prediction), en
## attente de la confirmation du host (DROP) ; tick du largage.
var _predicted_drop: DetachedTrailer
var _predicted_drop_tick: int = 0
## Sans confirmation au bout de ce delai, le largage predit est annule.
const DROP_CONFIRM_TICKS := 90
var drops_predicted: int = 0
var drops_cancelled: int = 0


func _ready() -> void:
	name = "NetRace"
	_loss_rng.seed = 20261017
	# avant LocalRace a chaque tick : le reseau est lu avant la course (cf.
	# _physics_process)
	process_physics_priority = -100


## `scene` : la LocalRace ; `list` : ses Player (truck, input), dans l'ordre
## des cases du lobby.
func setup(scene: Node, list: Array, lap_counter: RaceLaps) -> void:
	race_scene = scene
	players = list
	laps = lap_counter
	snapshot_ticks = maxi(NetSession.snapshot_ticks, 1)
	for i in players.size():
		_pose.append(TruckState.new())
		_last_pose_pos.append(Vector3.INF)
		_last_pose_vel.append(Vector3.ZERO)
		_last_flags.append(0)
	for n in race_scene.find_children("*", "", true, false):
		if n is ExplosiveBarrel:
			_barrels.append(n as ExplosiveBarrel)
		elif n is RoadsideSign:
			_signs.append(n as RoadsideSign)
		elif n is TrackPickup:
			# bonus : le host decide qui les prend (Ev.PICKUP)
			_pickups.append(n as TrackPickup)
			(n as TrackPickup).net_mirror = not NetSession.is_host()
	if NetSession.is_host():
		_hook_host_events()
		for i in mini(players.size(), NetSession.members.size()):
			var peer := int(NetSession.members[i]["peer"])
			if peer != 1:
				_peer_index[peer] = i
		NetSession.member_left.connect(_on_member_left)
		# a chaque checkpoint, une fois le tour compte (2026-10-22 : envoye a
		# lap_completed, avant que le tour change, le client affichait un tour
		# de retard, et ses checkpoints figes faussaient le classement)
		laps.racer_updated.connect(func(t: Truck) -> void: _send_racer(_index_of(t)))
		return
	_frames.resize(InputFrame.SIZE * RemoteInputSource.BATCH)
	_hist_tick.resize(HISTORY)
	_hist_tick.fill(-1)
	for k in HISTORY:
		_hist_state.append(TruckState.new())
		_hist_applied.append(TruckState.new())
	for i in players.size():
		var truck := _truck(i)
		mirror_gameplay(truck)
		if race_scene.call("is_local", i):
			_local = i
			truck.cargo_requested.connect(_on_local_cargo)
		else:
			truck.set_net_puppet(true, true)


func is_host() -> bool:
	return NetSession.is_host()


func _truck(i: int) -> Truck:
	return (players[i] as Object).get("truck") as Truck


func _index_of(truck: Truck) -> int:
	for i in players.size():
		if _truck(i) == truck:
			return i
	return -1


## Client : PV, pneus et cargo du camion ne decident plus rien sur cette
## machine (le host fait foi) ; leurs effets (fumee, eclatement, jantes)
## suivent ce que le host envoie.
static func mirror_gameplay(truck: Truck) -> void:
	for path: NodePath in [^"Health", ^"Tires", ^"Cargo"]:
		var n := truck.get_node_or_null(path)
		if n != null:
			n.set("net_mirror", true)


## Paquet d'inputs (vers le host) ou snapshot (vers un client), retenu le
## temps de la latence simulee s'il y en a une.
func _send(inputs: bool, peer: int, bytes: PackedByteArray) -> void:
	if NetSession.debug_loss_percent > 0.0 and _loss_rng.randf() * 100.0 < NetSession.debug_loss_percent:
		packets_lost += 1
		return
	if NetSession.debug_latency_ms > 0:
		_delayed.append([Time.get_ticks_msec() + NetSession.debug_latency_ms, inputs, peer, bytes])
	elif inputs:
		_inputs.rpc_id(peer, bytes)
	else:
		_snapshot.rpc_id(peer, bytes)


## Au debut de chaque tick, avant la course : lecture du reseau. Godot ne la
## fait qu'une fois par image, APRES les ticks physiques ; sur une image lente
## (plusieurs ticks d'affilee), le host jouerait ces ticks sans les inputs deja
## arrives (file vide, puis rafale), et le client lirait ses snapshots une
## image plus tard.
func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.poll()
	if _delayed.is_empty():
		return
	var now := Time.get_ticks_msec()
	var sent := false
	while not _delayed.is_empty() and int(_delayed[0][0]) <= now:
		var d: Array = _delayed.pop_front()
		var to := int(d[2])
		if to != 1 and not multiplayer.get_peers().has(to):
			continue   # parti pendant que le paquet attendait
		if d[1]:
			_inputs.rpc_id(int(d[2]), d[3])
		else:
			_snapshot.rpc_id(int(d[2]), d[3])
		sent = true
	if sent:
		_flush()


## Pousse tout de suite les paquets en attente (sinon ENet attend le poll de
## l'image suivante : jusqu'a ~16 ms de plus).
func _flush() -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer != null and peer.host != null:
		peer.host.flush()


# --- host ---------------------------------------------------------------------------

## Client : annonce au host que sa scene est chargee (apres son _ready, pour
## que les RPC du host trouvent ce noeud).
func _announce_ready() -> void:
	_scene_ready.rpc_id(1)


## Client -> host : sa scene de course est chargee. Le host lui envoie tout
## l'etat courant, puis le compte parmi les destinataires.
@rpc("any_peer", "call_remote", "reliable")
func _scene_ready() -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _peer_index.has(id):
		return
	_ready_peers[id] = true
	# scene chargee des deux cotes : coupure detectee vite, mais seulement une
	# fois l'ecran de chargement du host leve et le sas READY passe
	# (2026-10-19 : le host encore en preparation se figeait jusqu'a 16 s et
	# coupait le client qui venait d'arriver)
	_slow_peers[id] = true
	_race_state.rpc_id(id, race_scene.call("net_state"))
	for i in players.size():
		_racer.rpc_id(id, i, _racer_data(i))


## Client -> host : la frame du tick et les precedentes. Un peer ne pilote que
## SON camion : son id vient de l'ENet, jamais du message (NETCODE.md §6).
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _inputs(bytes: PackedByteArray) -> void:
	if not is_host():
		return
	var i: int = _peer_index.get(multiplayer.get_remote_sender_id(), -1)
	if i < 0:
		return
	var src := (players[i] as Object).get("input") as RemoteInputSource
	if src != null:
		src.push_packet(bytes)


## A la fin de chaque tick de la course, cote host.
func host_tick(tick: int) -> void:
	var loaded := not LoadingScreen.covering() and RaceManager.state != RaceManagerNode.State.LOBBY
	if not _slow_peers.is_empty() and loaded:
		for id: int in _slow_peers:
			NetSession.set_fast_timeout(id, true)
		_slow_peers.clear()
	var state: Array = race_scene.call("net_state")
	var sig := str(state)
	if sig != _last_state_sig:
		_last_state_sig = sig
		for id: int in _ready_peers:
			_race_state.rpc_id(id, state)
			states_sent += 1
	if tick % snapshot_ticks != 0 or _ready_peers.is_empty():
		return
	var buf := encode_snapshot(tick)
	for id: int in _ready_peers:
		# ack propre a chaque client : la frame de SON camion deja prise en compte
		var src := (players[_peer_index[id]] as Object).get("input") as RemoteInputSource
		var ok := src != null and src.applied_valid
		buf.encode_u16(5, posmod(src.applied_tick, 65536) if ok else 0)
		buf.encode_u8(7, 1 if ok else 0)
		_send(false, id, buf.duplicate())
		bytes_snapshots_sent += buf.size()
	_flush()


func encode_snapshot(tick: int) -> PackedByteArray:
	var moving: Array[int] = []
	for id: int in _objects:
		var o := _objects[id] as RigidBody3D
		if not is_instance_valid(o) or moving.size() >= MAX_OBJECTS:
			continue
		if o.linear_velocity.length_squared() > 0.0025 or o.angular_velocity.length_squared() > 0.0025 \
				or (tick + id) % KEYFRAME_TICKS == 0:
			moving.append(id)
	var trucks_end := SNAPSHOT_HEADER + TruckState.SIZE * players.size()
	var buf := PackedByteArray()
	buf.resize(trucks_end + 1 + OBJECT_SIZE * moving.size())
	buf.encode_u32(0, tick)
	buf.encode_u8(4, players.size())
	for i in players.size():
		_tmp.capture(_truck(i))
		_tmp.write_to(buf, SNAPSHOT_HEADER + i * TruckState.SIZE)
	buf.encode_u8(trucks_end, moving.size())
	for k in moving.size():
		var o := _objects[moving[k]] as Node3D
		var at := trucks_end + 1 + k * OBJECT_SIZE
		var xf := o.global_transform
		buf.encode_u16(at, moving[k])
		buf.encode_float(at + 2, xf.origin.x)
		buf.encode_float(at + 6, xf.origin.y)
		buf.encode_float(at + 10, xf.origin.z)
		buf.encode_u32(at + 14, TruckState.encode_quaternion(xf.basis.get_rotation_quaternion()))
	return buf


func _racer_data(i: int) -> Array:
	return racer_data(laps.racer(_truck(i)))


## Etat d'un concurrent envoye aux clients (_racer, RaceLaps.apply_remote).
static func racer_data(r: RaceLaps.Racer) -> Array:
	if r == null:
		return []
	return [r.lap, r.next_cp, r.last_cp, r.lap_start_tick, r.last_lap, r.best_lap, r.finished, r.finish_ticks]


func _send_racer(i: int) -> void:
	if i < 0:
		return
	var data := _racer_data(i)
	for id: int in _ready_peers:
		_racer.rpc_id(id, i, data)


## Un joueur est parti : son camion roule au neutre, classe « abandon ».
func _on_member_left(_slot: int, peer_id: int) -> void:
	var i: int = _peer_index.get(peer_id, -1)
	_peer_index.erase(peer_id)
	_ready_peers.erase(peer_id)
	_slow_peers.erase(peer_id)
	if i < 0:
		return
	var src := (players[i] as Object).get("input") as RemoteInputSource
	if src != null:
		src.clear()
	race_scene.call("mark_abandoned", i)
	_send_event(Ev.LEFT, [i])


# --- host : evenements de jeu ---------------------------------------------------

## Signaux du jeu chez le host -> evenements pour les clients.
func _hook_host_events() -> void:
	for i in players.size():
		var truck := _truck(i)
		var health := TruckHealth.of(truck)
		if health != null:
			health.wreck_left.connect(func(w: TruckWreck, t: DetachedTrailer) -> void:
				_send_event(Ev.WRECK, [i, _register(w), _register(t) if t != null else -1]))
			health.respawned.connect(func() -> void: _send_event(Ev.RESPAWN, [i]))
			health.trailer_destroyed.connect(func(at: Vector3) -> void: _send_event(Ev.TRAILER_EXPLODED, [i, at]))
		# pouvoirs : emplacement et cible du missile, rejoues chez les clients
		var powers := TruckPowers.of(truck)
		if powers != null:
			powers.fired.connect(func(slot: int, _p: int) -> void:
				_send_event(Ev.POWER, [i, slot, _index_of(powers.last_target)]))
		var cargo := truck.get_node_or_null(^"Cargo") as TruckCargo
		if cargo != null:
			cargo.dropped.connect(func(t: DetachedTrailer) -> void: _send_event(Ev.DROP, [i, _register(t)]))
		# chocs : les autres machines ne simulent pas ce camion, elles en
		# rejouent les effets (creux, etincelles, pieces) ; la sienne les a deja
		# (un bot est simule ici, chez le host)
		var owner := int(NetSession.members[i]["peer"]) if i < NetSession.members.size() else 1
		truck.wall_impact_at.connect(func(v: float, rear: bool, at: Vector3, n: Vector3) -> void:
			_send_event(Ev.IMPACT, [i, true, v, rear, at, n], owner))
		truck.body_impact.connect(func(v: float, rear: bool, at: Vector3, n: Vector3) -> void:
			body_impacts += 1
			if impact_log.size() < 20:
				impact_log.append([Engine.get_physics_frames(), i, snappedf(v, 0.1)])
			_send_event(Ev.IMPACT, [i, false, v, rear, at, n], owner))
	for k in _barrels.size():
		_barrels[k].exploded.connect(func(_t: Truck) -> void: _send_event(Ev.BARREL, [k]))
	for k in _signs.size():
		_signs[k].hit.connect(func(t: Truck) -> void: _send_event(Ev.SIGN, [k, t.linear_velocity]))
	for k in _pickups.size():
		_pickups[k].taken.connect(func(t: Truck, _p: TrackPickup) -> void: _send_event(Ev.PICKUP, [k, _index_of(t)]))


## Obstacle ne en course (remorque larguee, carcasse) : son id, partage par
## tout le monde ; ses chocs et sa destruction deviennent des evenements.
func _register(obj: DetachedTrailer) -> int:
	var id := _next_object_id
	_next_object_id += 1
	_objects[id] = obj
	_object_id[obj.get_instance_id()] = id
	obj.struck.connect(func(at: Vector3, n: Vector3, amount: float, v: float) -> void:
		_send_event(Ev.OBJECT_HIT, [id, at, n, amount, v, obj.hp]))
	obj.destroyed.connect(func() -> void: _send_event(Ev.OBJECT_GONE, [id]))
	obj.tree_exited.connect(func() -> void:
		_objects.erase(id)
		_object_id.erase(obj.get_instance_id()))
	return id


## Evenement a tous les clients prets, sauf `except_peer`.
func _send_event(kind: int, data: Array, except_peer: int = 0) -> void:
	for id: int in _ready_peers:
		if id != except_peer:
			_event.rpc_id(id, kind, data)
			events_sent += 1

# --- client -------------------------------------------------------------------------

## A chaque tick, cote client, AVANT la physique du tick : la frame du joueur
## local vient d'etre appliquee a son camion (LocalRace).
func client_tick(tick: int, local_frame: InputFrame) -> void:
	if not host_ready:
		_announce_wait -= 1
		# pret seulement une fois l'ecran de chargement leve : la preparation
		# des camions dessous fige encore la machine par moments (~5 s d'un
		# bloc sur un PC lent, 2026-10-19), et le host passe a la detection de
		# coupure rapide des qu'on s'annonce
		if _announce_wait <= 0 and not LoadingScreen.covering():
			_announce_wait = 30
			_announce_ready()
		return
	if _local >= 0:
		_record(tick - 1)
		_reconcile()
		_correct_step()
	_send_frame(local_frame)
	apply_poses(tick)
	_apply_objects(float(tick) + _offset - _interp_ticks)


## Les deux frames precedentes decalees, celle du tick a la fin : un paquet
## par tick, 3 frames.
func _send_frame(f: InputFrame) -> void:
	var n := InputFrame.SIZE
	for k in RemoteInputSource.BATCH - 1:
		for b in n:
			_frames[k * n + b] = _frames[(k + 1) * n + b]
	f.write_to(_frames, (RemoteInputSource.BATCH - 1) * n)
	_sent_frames += 1
	var count := mini(_sent_frames, RemoteInputSource.BATCH)
	var pkt := _frames if count == RemoteInputSource.BATCH else _frames.slice((RemoteInputSource.BATCH - count) * n)
	_send(true, 1, pkt.duplicate())
	bytes_inputs_sent += pkt.size()
	_flush()


## Etat du camion predit au debut du tick `t + 1`, c'est-a-dire apres la frame
## `t`, et le cumul des corrections deja faites a ce moment-la.
func _record(t: int) -> void:
	var k := posmod(t, HISTORY)
	_hist_tick[k] = posmod(t, 65536)
	_hist_state[k].capture(_truck(_local))
	_hist_applied[k].copy_from(_applied)


## Dernier snapshot avec ack : ecart entre l'etat du host apres la frame `ack`
## et notre prediction pour cette frame (corrigee depuis de ce qu'on a deja
## applique). Petit : corrige en douceur ; grand : saut assume.
func _reconcile() -> void:
	if _ack_snap.is_empty():
		return
	var snap := _ack_snap
	_ack_snap = {}
	var truck := _truck(_local)
	var host: TruckState = (snap["states"] as Array)[_local]
	# epave, ou remorque larguee / raccrochee par le host : on suit le host
	_follow_host_flags(truck, host)
	if truck.is_net_puppet():
		_has_pending = false
		return
	var ack := int(snap["ack"])
	var k := posmod(ack, HISTORY)
	if _hist_tick[k] != ack:
		return   # trop vieux, ou pas encore enregistre
	var mine := _hist_state[k]
	var then := _hist_applied[k]
	# prediction de la frame `ack`, avec les corrections faites depuis
	var p := mine.position + (_applied.position - then.position)
	var dpos := host.position - p
	var drot := _rotvec(host.rotation * mine.rotation.inverse()) - (_applied.angular_velocity - then.angular_velocity)
	var dvel := host.linear_velocity - (mine.linear_velocity + (_applied.linear_velocity - then.linear_velocity))
	var dang := host.angular_velocity - mine.angular_velocity
	var dtrl := deg_to_rad(host.trailer_angle_deg - mine.trailer_angle_deg) - (_applied.trailer_angle_deg - then.trailer_angle_deg)
	last_error_m = dpos.length()
	max_error_m = maxf(max_error_m, last_error_m)
	if dpos.length() > SNAP_DISTANCE or rad_to_deg(drot.length()) > SNAP_ANGLE_DEG:
		truck.net_correct(dpos, drot, dvel, dang, dtrl, true)
		_accumulate(dpos, drot, dvel, dtrl)
		_has_pending = false
		snaps += 1
		if snap_log.size() < 20:
			snap_log.append([Engine.get_physics_frames(), snappedf(dpos.length(), 0.01), snappedf(rad_to_deg(drot.length()), 0.1)])
		return
	if dpos.length() < DEAD_ZONE and dvel.length() < DEAD_ZONE * 10.0:
		_has_pending = false
		return
	_pending.position = dpos
	_pending.angular_velocity = drot   # rotation restante, en vecteur
	_pending.linear_velocity = dvel
	_pending_trailer = dtrl
	_has_pending = true
	corrections += 1


## Une part de la correction en attente, a chaque tick : jamais de saut visible.
func _correct_step() -> void:
	if not _has_pending:
		return
	var dp := _pending.position * CORRECTION_RATE
	var dr := _pending.angular_velocity * CORRECTION_RATE
	var dv := _pending.linear_velocity * CORRECTION_RATE
	var dt := _pending_trailer * CORRECTION_RATE
	_pending.position -= dp
	_pending.angular_velocity -= dr
	_pending.linear_velocity -= dv
	_pending_trailer -= dt
	_truck(_local).net_correct(dp, dr, dv, Vector3.ZERO, dt)
	_accumulate(dp, dr, dv, dt)
	if _pending.position.length() < 1e-3 and _pending.linear_velocity.length() < 1e-2:
		_has_pending = false


## Cumul des corrections : position, vitesse, rotation (vecteur, rangee dans
## angular_velocity) et angle de remorque (rad, range dans trailer_angle_deg).
func _accumulate(dp: Vector3, dr: Vector3, dv: Vector3, dt: float) -> void:
	_applied.position += dp
	_applied.angular_velocity += dr
	_applied.linear_velocity += dv
	_applied.trailer_angle_deg += dt


static func _rotvec(q: Quaternion) -> Vector3:
	q = q.normalized()
	if q.w < 0.0:
		q = -q
	var a := q.get_angle()
	if a < 1e-7:
		return Vector3.ZERO
	return q.get_axis() * a


## Decisions du host sur le camion predit : epave (il devient marionnette le
## temps de la reapparition), remorque larguee ou raccrochee.
func _follow_host_flags(truck: Truck, host: TruckState) -> void:
	var wrecked := host.flags & TruckState.FLAG_WRECKED != 0
	if wrecked and not truck.is_net_puppet():
		truck.set_net_puppet(true, true)
	elif not wrecked and truck.is_net_puppet():
		truck.set_net_puppet(false)
		var xf := Transform3D(Basis(host.rotation), host.position)
		truck.reset_to(xf, host.linear_velocity)
	_check_predicted_drop(truck)
	if is_instance_valid(_predicted_drop):
		return   # largage predit : le host ne l'a pas encore vu
	var detached := host.flags & TruckState.FLAG_TRAILER_DETACHED != 0
	if detached and not truck.is_trailer_detached():
		truck.detach_trailer()
	elif not detached and truck.is_trailer_detached():
		truck.reattach_trailer(true)


## Ce que le host decide pour chaque camion, applique des qu'un snapshot plus
## recent arrive : PV, cargo, pneus ; klaxon et boost (fronts) des camions
## qu'on ne simule pas.
func _apply_truck_states(states: Array[TruckState]) -> void:
	for i in mini(states.size(), players.size()):
		var s := states[i]
		var truck := _truck(i)
		var health := TruckHealth.of(truck)
		if health != null:
			health.net_apply_hp(s.hp, s.trailer_hp)
		var cargo := truck.get_node_or_null(^"Cargo") as TruckCargo
		if cargo != null:
			cargo.net_set_charge(s.cargo_charge, s.cargo_locked)
		var tires := s.tires()
		for w in TruckState.TIRE_COUNT:
			if tires & (1 << w) and not truck.is_tire_burst(w):
				truck.burst_tire(w)
		if tires == 0 and truck.burst_tire_count() + truck.trailer_burst_count() > 0:
			truck.repair_tires()
		if i != _local:
			var rising := s.flags & ~_last_flags[i]
			if rising & TruckState.FLAG_HONK:
				truck.honked.emit()
			if rising & TruckState.FLAG_BOOSTING:
				truck.boosted.emit()
		_last_flags[i] = s.flags


## Obstacles nes en course (cinematiques ici) poses a l'instant `at` : entre les
## deux snapshots qui les citent, sinon a la derniere pose connue.
func _apply_objects(at: float) -> void:
	if _objects.is_empty():
		return
	for id: int in _objects:
		var o := _objects[id] as Node3D
		if not is_instance_valid(o):
			continue
		var older: Variant = null
		var t0 := 0.0
		var newer: Variant = null
		var t1 := 0.0
		for s: Dictionary in _snaps:
			var objs: Dictionary = s["objs"]
			if not objs.has(id):
				continue
			if float(s["tick"]) <= at:
				older = objs[id]
				t0 = float(s["tick"])
			else:
				newer = objs[id]
				t1 = float(s["tick"])
				break
		var xf: Transform3D
		if older != null and newer != null:
			xf = (older as Transform3D).interpolate_with(newer as Transform3D, clampf((at - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0))
		elif older != null:
			xf = older as Transform3D
		elif newer != null:
			xf = newer as Transform3D
		else:
			continue
		o.global_transform = xf


## Evenement de jeu du host (Ev), rejoue ici par le meme code que chez lui.
@rpc("authority", "call_remote", "reliable")
func _event(kind: int, data: Array) -> void:
	events_received += 1
	match kind:
		Ev.WRECK:
			var health := TruckHealth.of(_truck_at(data, 0))
			if health == null:
				return
			var left := health.net_wreck()
			if left.size() == 2:
				_adopt(int(data[1]), left[0])
				_adopt(int(data[2]), left[1])
		Ev.RESPAWN:
			var health := TruckHealth.of(_truck_at(data, 0))
			if health != null:
				health.net_respawn()
		Ev.TRAILER_EXPLODED:
			var health := TruckHealth.of(_truck_at(data, 0))
			if health != null and data.size() == 2:
				health.net_trailer_exploded(data[1])
		Ev.DROP:
			var truck := _truck_at(data, 0)
			var cargo := truck.get_node_or_null(^"Cargo") as TruckCargo if truck != null else null
			if cargo == null or data.size() != 2:
				return
			if int(data[0]) == _local and is_instance_valid(_predicted_drop):
				# deja larguee ici (prediction) : c'est la meme
				_adopt(int(data[1]), _predicted_drop)
				_predicted_drop = null
			else:
				_adopt(int(data[1]), cargo.drop())
		Ev.OBJECT_HIT:
			var o := _objects.get(int(data[0])) as DetachedTrailer if data.size() == 6 else null
			if is_instance_valid(o):
				o.net_hit(data[1], data[2], float(data[3]), float(data[4]), float(data[5]))
		Ev.OBJECT_GONE:
			var o := _objects.get(int(data[0])) as DetachedTrailer if data.size() == 1 else null
			if is_instance_valid(o):
				o.net_destroy()
			_objects.erase(int(data[0]) if data.size() == 1 else -1)
		Ev.BARREL:
			var k := int(data[0]) if data.size() == 1 else -1
			if k >= 0 and k < _barrels.size():
				_barrels[k].net_explode()
		Ev.SIGN:
			var k := int(data[0]) if data.size() == 2 else -1
			if k >= 0 and k < _signs.size():
				_signs[k].net_knock(data[1])
		Ev.PICKUP:
			var k := int(data[0]) if data.size() == 2 else -1
			if k >= 0 and k < _pickups.size():
				_pickups[k].net_take(_truck_at(data, 1))
		Ev.LEFT:
			var k := int(data[0]) if data.size() == 1 else -1
			if k >= 0 and k < players.size():
				race_scene.call("mark_abandoned", k)
		Ev.POWER:
			var powers := TruckPowers.of(_truck_at(data, 0))
			if powers != null and data.size() == 3:
				powers.net_fire(int(data[1]), _truck_at(data, 2))
		Ev.IMPACT:
			var truck := _truck_at(data, 0)
			if truck == null or data.size() != 6 or not truck.is_net_puppet():
				return
			if bool(data[1]):
				truck.wall_impact_at.emit(float(data[2]), bool(data[3]), data[4], data[5])
			else:
				truck.body_impact.emit(float(data[2]), bool(data[3]), data[4], data[5])


func _truck_at(data: Array, k: int) -> Truck:
	if data.size() <= k:
		return null
	var i := int(data[k])
	return _truck(i) if i >= 0 and i < players.size() else null


## Obstacle cree ici par le meme code que chez le host : meme id, en miroir.
func _adopt(id: int, obj: Variant) -> void:
	var o := obj as DetachedTrailer
	if id < 0 or o == null:
		return
	o.net_mirror = true
	_objects[id] = o
	o.tree_exited.connect(func() -> void: _objects.erase(id))

## Notre joueur largue sa remorque : tout de suite ici, comme le ferait le
## host (memes regles : recharge, verrou du depart, camion a l'endroit). Le
## host recoit l'input et decide ; sa confirmation (DROP) relie cette remorque
## a la sienne.
func _on_local_cargo() -> void:
	var truck := _truck(_local)
	var cargo := truck.get_node_or_null(^"Cargo") as TruckCargo
	if cargo == null or is_instance_valid(_predicted_drop) or not cargo.is_ready() or truck.is_upside_down() \
			or truck.is_net_puppet():
		return
	_predicted_drop = cargo.drop()
	_predicted_drop_tick = Engine.get_physics_frames()
	drops_predicted += 1


## Largage predit que le host n'a pas confirme a temps (refuse chez lui :
## recharge, verrou, camion retourne) : la remorque predite disparait, la
## notre revient.
func _check_predicted_drop(truck: Truck) -> void:
	if not is_instance_valid(_predicted_drop):
		_predicted_drop = null
		return
	if Engine.get_physics_frames() - _predicted_drop_tick < DROP_CONFIRM_TICKS:
		return
	_predicted_drop.queue_free()
	_predicted_drop = null
	truck.reattach_trailer(true)
	var cargo := truck.get_node_or_null(^"Cargo") as TruckCargo
	if cargo != null:
		cargo.undo_drop()
	drops_cancelled += 1

## Pose les marionnettes a l'instant (tick local + decalage du host - retard).
func apply_poses(tick: int) -> void:
	if _snaps.is_empty():
		return
	var at := float(tick) + _offset - _interp_ticks
	var mine: Truck = _truck(_local) if _local >= 0 and not _truck(_local).is_net_puppet() else null
	for i in players.size():
		var truck := _truck(i)
		if truck == null or not truck.is_net_puppet() or not sample(i, at, _pose[i]):
			continue
		var s := _pose[i]
		var xf := Transform3D(Basis(s.rotation), s.position)
		var jump := truck.global_position.distance_to(s.position) > TELEPORT_DISTANCE
		# obstacle physique pres de notre camion (contact possible), exact loin
		truck.set_net_near(mine != null and mine.global_position.distance_to(s.position) < NEAR_DISTANCE)
		if not jump and _last_pose_pos[i].is_finite():
			var pop := s.position.distance_to(_last_pose_pos[i] + _last_pose_vel[i] * TICK_S)
			pop_sum += pop
			pop_count += 1
			pop_max = maxf(pop_max, pop)
		_last_pose_pos[i] = s.position
		_last_pose_vel[i] = s.linear_velocity
		truck.set_net_pose(xf, s.steer_deg, s.trailer_angle_deg, s.flags & TruckState.FLAG_BOOSTING != 0,
			s.flags & TruckState.FLAG_HANDBRAKE != 0, s.flags & TruckState.FLAG_TRAILER_DETACHED != 0, jump,
			s.linear_velocity, s.angular_velocity)


## Etat du camion `i` a l'instant `at` (ticks du host) : interpole entre les
## deux snapshots qui l'encadrent, ou extrapole du dernier (borne). Faux si
## aucun snapshot ne le connait.
func sample(i: int, at: float, out: TruckState) -> bool:
	var newer: Dictionary = {}
	var older: Dictionary = {}
	for s: Dictionary in _snaps:
		var st: Array = s["states"]
		if i >= st.size():
			continue
		if float(s["tick"]) <= at:
			older = s
		elif newer.is_empty():
			newer = s
			break
	if not older.is_empty() and not newer.is_empty():
		poses_total += 1
		var t0 := float(older["tick"])
		var t1 := float(newer["tick"])
		out.interpolate(older["states"][i], newer["states"][i], clampf((at - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0))
		return true
	poses_total += 1
	if not older.is_empty():
		poses_extrapolated += 1
		var ahead := minf(at - float(older["tick"]), EXTRAPOLATE_MAX_TICKS)
		out.extrapolate(older["states"][i], ahead, TICK_S)
		return true
	if not newer.is_empty():
		out.copy_from(newer["states"][i])
		return true
	return false


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _snapshot(bytes: PackedByteArray) -> void:
	receive_snapshot(bytes, Engine.get_physics_frames())


## Snapshot recu au tick local `local_tick`. Paquet mal forme : ignore.
func receive_snapshot(bytes: PackedByteArray, local_tick: int) -> void:
	if bytes.size() < SNAPSHOT_HEADER:
		return
	var tick := bytes.decode_u32(0)
	var count := bytes.decode_u8(4)
	var trucks_end := SNAPSHOT_HEADER + count * TruckState.SIZE
	if bytes.size() < trucks_end + 1:
		return
	var n_obj := bytes.decode_u8(trucks_end)
	if bytes.size() != trucks_end + 1 + n_obj * OBJECT_SIZE:
		return
	if not _snaps.is_empty() and tick <= int(_snaps[-1]["tick"]):
		return   # en retard sur un plus recent : inutile
	var states: Array[TruckState] = []
	for k in count:
		var s := TruckState.new()
		s.read_from(bytes, SNAPSHOT_HEADER + k * TruckState.SIZE)
		states.append(s)
	var objs := {}
	for k in n_obj:
		var at := trucks_end + 1 + k * OBJECT_SIZE
		objs[bytes.decode_u16(at)] = Transform3D(Basis(TruckState.decode_quaternion(bytes.decode_u32(at + 14))),
			Vector3(bytes.decode_float(at + 2), bytes.decode_float(at + 6), bytes.decode_float(at + 10)))
	var snap := {"tick": tick, "states": states, "objs": objs}
	_apply_truck_states(states)
	if not _snaps.is_empty():
		_interval = lerpf(_interval, float(tick - int(_snaps[-1]["tick"])), 0.1)
	_snaps.append(snap)
	while _snaps.size() > BUFFER_SNAPSHOTS:
		_snaps.pop_front()
	snapshots_received += 1
	_last_snapshot_local = local_tick
	if bytes.decode_u8(7) != 0 and _local >= 0 and _local < count:
		snap["ack"] = bytes.decode_u16(5)
		_ack_snap = snap
	_track_clock(float(tick) - float(local_tick))


## Decalage horloge du host - horloge locale, mesure a chaque snapshot (tick
## du host - tick local a l'arrivee, latence comprise) : moyenne glissante,
## qui suit aussi une derive des horloges ; gros saut (pause, chargement) : on
## repart de la mesure. La dispersion des arrivees (gigue) est mesuree pour
## les tests ; le rendu ne l'attend pas (extrapolation).
func _track_clock(sample_offset: float) -> void:
	if not _offset_known or absf(sample_offset - _offset) > 60.0:
		_offset = sample_offset
		_offset_known = true
		_dev = 0.0
	else:
		_offset = lerpf(_offset, sample_offset, 0.05)
		_dev = lerpf(_dev, absf(sample_offset - _offset), 0.05)
	# intervalle des snapshots, plus la gigue mesuree (ecart moyen) : une
	# liaison reguliere affiche les autres camions au plus pres (2026-10-19)
	# (20 Hz : un tick de marge en plus, un snapshot en retard y coute cher)
	_interp_ticks = clampf(ceilf(_interval + _dev) + (1.0 if _interval > 1.5 else 0.0), MIN_INTERP_TICKS, MAX_INTERP_TICKS)


## Gigue des arrivees de snapshots (ticks).
func jitter_ticks() -> float:
	return _dev

## Tick du host -> tick local (horloges des tours, du depart).
func to_local_tick(host_tick: int) -> int:
	return host_tick - roundi(_offset)


func host_offset() -> float:
	return _offset


## Client : ticks depuis le dernier snapshot recu (liaison instable).
func ticks_since_snapshot() -> int:
	return Engine.get_physics_frames() - _last_snapshot_local


## Retard de rendu des autres camions (ticks).
func interp_ticks() -> float:
	return _interp_ticks


@rpc("authority", "call_remote", "reliable")
func _race_state(state: Array) -> void:
	# coupure detectee vite seulement apres le sas READY : le host peut encore
	# se figer en preparant sa course (16 s d'un bloc mesurees sur un PC lent)
	if not _fast_timeout and state.size() > 0 and int(state[0]) != RaceManagerNode.State.LOBBY:
		_fast_timeout = true
		NetSession.set_fast_timeout(1, true)
	host_ready = true
	states_received += 1
	race_scene.call("apply_net_state", state)


@rpc("authority", "call_remote", "reliable")
func _racer(i: int, data: Array) -> void:
	if i < 0 or i >= players.size() or data.size() != 8:
		return
	var truck := _truck(i)
	var start := int(data[3])
	laps.apply_remote(truck, int(data[0]), int(data[1]), int(data[2]),
		to_local_tick(start) if start >= 0 else -1, int(data[4]), int(data[5]), bool(data[6]), int(data[7]))
