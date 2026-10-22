extends Node

## Essai de bout en bout en ligne : deux instances du jeu sur ce PC (host et
## client, ENet sur 127.0.0.1), chacune pilotee par un bot dur.
##   godot --headless --path game res://dev/net_e2e.tscn -- --role=host --mode=3 --port=7781 --secs=120
## Le client passe --role=client et le meme port (modes : GameState.GameMode) ;
## --bots=N : bots durs du host ; --players=N : le host lance quand N joueurs
## sont la (2 par defaut) ; --track=N : circuit (GameState.TRACKS) ;
## --quality=N : qualite graphique (GraphicsSettings.Quality, 3 = extreme) ;
## --offscreen : fenetre hors de l'ecran (GameState.go_offscreen), --mute :
## sans le son ;
## --audio-stats : niveau des bus Effets, Ambiance, Musique (ligne E2E).
## Toutes les 10 s, une ligne SAMPLE (tour affiche, place, vies, PV de chaque
## camion) a comparer entre les deux ; a 50 s, le host detruit le camion du
## client (vitesse de reapparition : launch_kmh). A la fin : une ligne E2E par
## instance (etat de course, et pour chaque camion : tour, checkpoint,
## arrivee, PV, vies, elimine, destructions vues, pouvoirs vus, position).
## 2026-10-22 : a trouve le tour de retard affiche chez le client.

class Driver extends InputSource:
	var bot: BotInputSource

	func poll(tick: int) -> InputFrame:
		var f := bot.poll(tick)
		frame.copy_from(f)
		frame.tick = tick
		# sas READY : Carre (boost) = pret
		if RaceManager.state == RaceManagerNode.State.LOBBY:
			frame.boost = (tick / 10) % 2 == 0
		return frame


var role := "host"
var mode := 0
var port := 7781
var secs := 120
var bots := 0
var expected := 2
var snap := ""
var track := 0
var _wall0 := 0
var _phys_sum := 0.0
var _phys_n := 0
var _phys_max := 0.0
var trace := ""
var _trace: FileAccess
var _launched := false
var _loadout_sent := false
var _race: Node
var _go := -1
var _wrecks: Array[int] = []
var _was_wrecked: Array[bool] = []
var _powers: Array[int] = []
## Recharges du tick d'avant (un tir : la recharge remonte).
var _cool: Array = []
var _back: Array[int] = []
var _launch_kmh: Array = []
var _max_gap := 0
var _done := false
## --audio-stats : niveau de chaque bus (Effets, Ambiance, Musique) pendant la
## course, lu a chaque image : energie moyenne et crete (dB). Le Master peut
## etre muet (--offscreen) : les bus en dessous mixent quand meme.
var audio_stats := false
var _audio_sum: PackedFloat64Array = [0.0, 0.0, 0.0]
var _audio_peak: PackedFloat64Array = [0.0, 0.0, 0.0]
var _audio_n := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var v := a.get_slice("=", 1)
		if a.begins_with("--role="):
			role = v
		elif a.begins_with("--mode="):
			mode = v.to_int()
		elif a.begins_with("--port="):
			port = v.to_int()
		elif a.begins_with("--secs="):
			secs = v.to_int()
		elif a.begins_with("--bots="):
			bots = v.to_int()
		elif a.begins_with("--players="):
			expected = v.to_int()
		elif a.begins_with("--snap="):
			snap = v
		elif a.begins_with("--trace="):
			trace = v
		elif a == "--audio-stats":
			audio_stats = true
		elif a.begins_with("--track="):
			track = v.to_int()
		elif a.begins_with("--quality="):
			GameState.graphics_quality = v.to_int()
	NetSession.player_name = role
	GameState.game_mode = mode
	GameState.selected_track = track
	GameState.trailer_drops = 3
	GameState.arena_minutes = 2
	# bots du host (le client recoit les siens au lancement)
	GameState.bot_count = bots if role == "host" else 0
	GameState.bot_level = BotInputSource.Level.HARD
	if role == "host":
		NetSession.host(port)
	else:
		NetSession.join("127.0.0.1", port)


func _physics_process(_delta: float) -> void:
	if _done:
		return
	if not _loadout_sent and NetSession.members.size() >= 1 and (role == "host" or NetSession.local_slot() >= 0):
		_loadout_sent = true
		NetSession.set_loadout(1 if role == "host" else 4, 0, 2)
	if role == "host" and not _launched and NetSession.members.size() == expected and NetSession.all_ready():
		_launched = true
		NetSession.launch_race()
	var scene := get_tree().current_scene
	if _race == null and scene != null and scene.get("players") != null and (scene.get("players") as Array).size() > 0:
		_hook(scene)
	if _race == null:
		return
	var players: Array = _race.get("players")
	for i in players.size():
		var t := (players[i] as Object).get("truck") as Truck
		var w := t.is_wrecked() or (t.get_node_or_null(^"Health") != null and TruckHealth.of(t).is_wrecked())
		if w and not _was_wrecked[i]:
			_wrecks[i] += 1
		if not w and _was_wrecked[i]:
			_back[i] = Engine.get_physics_frames()
		if Engine.get_physics_frames() - int(_back[i]) == 8:
			_launch_kmh.append([i, roundi(-t.linear_velocity.dot(t.global_basis.z) * 3.6)])
		_was_wrecked[i] = w
		var pw := TruckPowers.of(t)
		if pw != null:
			for s in 2:
				if pw.cooldown[s] > int(_cool[i][s]):
					_powers[i] += 1
				_cool[i][s] = pw.cooldown[s]
	# le host detruit le camion du client a 50 s : il doit reapparaitre lance
	if role == "host" and _go >= 0 and Engine.get_physics_frames() - _go == 3000:
		TruckHealth.of((players[1] as Object).get("truck") as Truck).crash(&"essai")
	# captures du rendu (fenetre seulement) : --snap=prefixe, au depart, toutes les 10 s et a la fin
	if snap != "" and DisplayServer.get_name() != "headless" and _go >= 0:
		var k := Engine.get_physics_frames() - _go
		if k == 1 or k % 600 == 0 or k == secs * 60 - 2:
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [snap, k / 60])
	if _go >= 0 and (Engine.get_physics_frames() - _go) % 600 == 0:
		var race := _race.get("race") as RaceLaps
		var lives: Array = _race.get("lives")
		var rows := []
		for i in players.size():
			var t := (players[i] as Object).get("truck") as Truck
			var h := TruckHealth.of(t)
			rows.append([race.display_lap(t), race.position(t), lives[i] if i < lives.size() else -1,
				roundi(h.hp) if h else -1])
		print("SAMPLE %s t=%d %s" % [role, (Engine.get_physics_frames() - _go) / 60, rows])
	if _go >= 0:
		# cout de la physique de cette machine (ms par tick)
		var ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_phys_sum += ms
		_phys_n += 1
		_phys_max = maxf(_phys_max, ms)
	if RaceManager.state == RaceManagerNode.State.RACING and _go < 0:
		_go = Engine.get_physics_frames()
		_wall0 = Time.get_ticks_usec()
		if trace != "":
			_trace = FileAccess.open(trace, FileAccess.WRITE)
	if _trace != null:
		var frame := Engine.get_physics_frames() % 65536
		if role == "host" and players.size() > 1:
			var src := (players[1] as Object).get("input") as RemoteInputSource
			frame = src.applied_tick if src != null else -1
		var line := "%.1f;%d" % [Time.get_unix_time_from_system() * 1000.0, frame]
		for i in players.size():
			var t := (players[i] as Object).get("truck") as Truck
			var p := t.global_position
			line += ";%.3f,%.3f,%.3f,%d" % [p.x, p.y, p.z, 1 if t.is_net_puppet() else 0]
		_trace.store_line(line)
	var net: Variant = _race.get("net")
	if net != null and role == "client" and _go >= 0 and Engine.get_physics_frames() - _go == 1:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--present="):
				(net as Object).set("present_part", a.get_slice("=", 1).to_float())
	if net != null and role == "client" and _go >= 0:
		_max_gap = maxi(_max_gap, int((net as Object).call("ticks_since_snapshot")))
	var over := RaceManager.state == RaceManagerNode.State.FINISHED
	if (_go >= 0 and Engine.get_physics_frames() - _go >= secs * 60) or over:
		_report(over)


func _hook(scene: Node) -> void:
	_race = scene
	var players: Array = scene.get("players")
	_wrecks.resize(players.size())
	_wrecks.fill(0)
	_was_wrecked.resize(players.size())
	_was_wrecked.fill(false)
	_powers.resize(players.size())
	_powers.fill(0)
	_back.resize(players.size())
	_back.fill(-100)
	for i in players.size():
		var p := players[i] as Object
		var t := p.get("truck") as Truck
		var pw := t.get_node_or_null(^"Powers") as TruckPowers
		var k := i
		_cool.append([0, 0])
		if bool(scene.call("is_local", i)):
			var d := Driver.new()
			d.bot = BotInputSource.new()
			d.bot.setup(scene.get("track") as TrackBlockout, t, BotInputSource.Level.HARD, 3 + maxi(NetSession.local_slot(), 0))
			add_child(d.bot)
			add_child(d)
			p.set("input", d)


const AUDIO_BUSES: Array[StringName] = [SoundMix.EFFECTS, SoundMix.AMBIENCE, SoundMix.MUSIC]


func _process(_delta: float) -> void:
	if not audio_stats or _go < 0 or _done:
		return
	_audio_n += 1
	for b in 3:
		var idx := AudioServer.get_bus_index(AUDIO_BUSES[b])
		var lin := db_to_linear(maxf(AudioServer.get_bus_peak_volume_left_db(idx, 0),
			AudioServer.get_bus_peak_volume_right_db(idx, 0)))
		_audio_sum[b] += lin * lin
		_audio_peak[b] = maxf(_audio_peak[b], lin)


func _report(over: bool) -> void:
	if snap != "" and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("%s_fin.png" % snap)
	_done = true
	var players: Array = _race.get("players")
	var race := _race.get("race") as RaceLaps
	var lives: Array = _race.get("lives")
	var elim: Array = _race.get("eliminated")
	var rows := []
	for i in players.size():
		var t := (players[i] as Object).get("truck") as Truck
		var r := race.racer(t)
		var h := TruckHealth.of(t)
		rows.append([i, r.lap if r else -1, r.next_cp if r else -1, r.finished if r else false,
			roundi(h.hp) if h else -1, lives[i] if i < lives.size() else -1, elim.has(i), _wrecks[i], _powers[i],
			t.global_position.round(), String(_race.call("player_name", i)), int(_race.call("slot_of", i))])
	var net: Variant = _race.get("net")
	var extra := ""
	if _trace != null:
		_trace.close()
	if net != null and role == "client":
		var o := net as Object
		extra = " states=%d max_gap=%d interp=%.1f pop_avg=%.3f pop_max=%.2f snaps=%d corr=%d err_max=%.2f" % [
			int(o.get("states_received")), _max_gap, float(o.call("interp_ticks")),
			float(o.get("pop_sum")) / maxf(float(o.get("pop_count")), 1.0), float(o.get("pop_max")),
			int(o.get("snaps")), int(o.get("corrections")), float(o.get("max_error_m"))]
	if audio_stats:
		for b in 3:
			extra += " %s_db=%.1f %s_peak_db=%.1f" % [AUDIO_BUSES[b], linear_to_db(sqrt(_audio_sum[b] / maxf(_audio_n, 1.0))),
				AUDIO_BUSES[b], linear_to_db(_audio_peak[b])]
	extra += " phys_ms=%.2f phys_max=%.2f wall_ms_tick=%.2f" % [_phys_sum / maxf(_phys_n, 1.0), _phys_max,
		(Time.get_ticks_usec() - _wall0) / 1000.0 / maxf(Engine.get_physics_frames() - _go, 1.0)]
	print("E2E role=%s mode=%d over=%s state=%d ticks=%d%s launch_kmh=%s rows=%s" % [role, mode, over, RaceManager.state,
		Engine.get_physics_frames() - _go if _go >= 0 else -1, extra, _launch_kmh, rows])
	# le client part le premier : le host ne voit pas de coupure avant sa fin
	if role == "client":
		get_tree().quit()
	else:
		(func() -> void:
			await get_tree().create_timer(2.0).timeout
			get_tree().quit()).call()
