extends Node

## Banc des bots (outil, hors make test) : une course hors ligne, 1 joueur
## immobile et N bots, jusqu'a ce que chaque bot ait boucle `laps` tours.
## Affiche une ligne BENCH : temps au tour (s) par bot, chutes, remises en
## piste, contacts camion-camion (cabines a moins de 3,5 m, front montant),
## part du temps a la vitesse max et sous boost, vitesse max atteinte. En
## cours de route : CRASH (chute : ou, zone, geometrie), SLOW (plus de 3 s
## sous 20 km/h : ou, consignes, ce qui le gene). S'arrete a la fin de la
## course ou quand chaque bot a fait `tours` tours.
##   godot --headless --fixed-fps 60 --path game res://dev/bot_bench.tscn -- <circuit> <niveau> <bots> <tours>

var scene: Node3D
var laps_target := 3
var ticks := 0
var laps: Dictionary = {}
var crashes := 0
var resets := 0
var contacts := 0
var _close: Dictionary = {}
var _args: PackedStringArray
var _race_ticks := 0
var _started := false
var _slow: Dictionary = {}
var _top_ticks := 0
var _boost_ticks := 0
var _vmax := 0.0


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	while _args.size() < 4:
		_args.append(["0", "2", "1", "3"][_args.size()])
	GameState.persist = false
	GameState.requested_players = 0
	laps_target = int(_args[3])
	scene = (load(GameStateNode.track_scene(int(_args[0]))) as PackedScene).instantiate() as Node3D
	scene.set("ready_gate", false)
	scene.set("player_count", 1)
	scene.set("bot_count", int(_args[2]))
	scene.set("bot_level", int(_args[1]))
	var t0 := Time.get_ticks_msec()
	add_child(scene)
	print("LOAD %d ms" % (Time.get_ticks_msec() - t0))
	var ar := scene.get("auto_reset") as AutoReset
	ar.truck_crashed.connect(func(t: Truck) -> void:
		crashes += 1
		var tr := scene.get("track") as TrackBlockout
		var i := tr.closest_sample(t.global_position)
		var d := t.global_position - tr.sample_position(i)
		print("CRASH %s tick=%d s=%.0f lat=%.1f v=%.0f zone=%s off=%s up=%.1f y=%.1f" % [t.name, ticks, tr.sample_s(i),
			d.dot(tr.sample_right(i)), t.linear_velocity.length() * 3.6, ar._zones.get(t, 0), ar.is_off_track(t),
			d.dot(tr.sample_up(i)), t.global_position.y]))
	(scene.get("race") as RaceLaps).lap_completed.connect(_on_lap)


func _on_lap(truck: Truck, _lap: int, lap_ticks: int) -> void:
	if not laps.has(truck):
		laps[truck] = []
	laps[truck].append(snappedf(lap_ticks / 60.0, 0.01))


func _physics_process(_d: float) -> void:
	ticks += 1
	var ps: Array = scene.get("players")
	var trucks: Array[Truck] = []
	for p: Object in ps.slice(1):
		trucks.append(p.get("truck") as Truck)
	for a in trucks.size():
		for b in range(a + 1, trucks.size()):
			var key := a * 10 + b
			var close := trucks[a].global_position.distance_to(trucks[b].global_position) < 3.5
			if close and not _close.get(key, false):
				contacts += 1
			_close[key] = close
	if RaceManager.state == RaceManagerNode.State.RACING:
		for t in trucks:
			_race_ticks += 1
			if t.linear_velocity.length() * 3.6 >= t.tuning.top_speed_kmh * 0.97:
				_top_ticks += 1
			if t.is_boosting():
				_boost_ticks += 1
			_vmax = maxf(_vmax, t.linear_velocity.length() * 3.6)
			# lent (< 20 km/h) plus de 3 s : ou et pourquoi
			var slow := t.linear_velocity.length() * 3.6 < 20.0 and not t.is_wrecked()
			_slow[t] = int(_slow.get(t, 0)) + 1 if slow else 0
			if int(_slow[t]) == 180:
				var tr := scene.get("track") as TrackBlockout
				var i := tr.closest_sample(t.global_position)
				var bot: BotInputSource = null
				for p: Object in ps:
					if p.get("truck") == t:
						bot = p.get("input") as BotInputSource
				print("SLOW %s s=%.0f lat=%.1f tgt=%.0f thr=%.1f brk=%.1f steer=%.2f fwd_dot=%.2f" % [t.name, tr.sample_s(i),
					(t.global_position - tr.sample_position(i)).dot(tr.sample_right(i)), bot.target_speed * 3.6, bot.frame.throttle,
					bot.frame.brake, bot.frame.steer, (-t.global_basis.z).dot(tr.sample_forward(i))])
				if bot.blocked_by != null:
					var b := bot.blocked_by
					var bi := tr.closest_sample(b.global_position)
					print("   blocked by %s s=%.0f lat=%.1f dist=%.1f dy=%.1f" % [b.name, tr.sample_s(bi),
						(b.global_position - tr.sample_position(bi)).dot(tr.sample_right(bi)), b.global_position.distance_to(t.global_position),
						b.global_position.y - t.global_position.y])
	var done := true
	for t in trucks:
		done = done and (laps.get(t, []) as Array).size() >= laps_target
	if RaceManager.state == RaceManagerNode.State.RACING:
		_started = true
	elif _started:
		done = true
	if done or ticks > 60 * 60 * 8:
		var out := []
		for t in trucks:
			out.append(laps.get(t, []))
		print("BENCH track=%s level=%s bots=%s laps=%s crashes=%d resets=%d contacts=%d top=%d%% boost=%d%% vmax=%.0f" % [_args[0],
			_args[1], _args[2], str(out), crashes, resets, contacts, 100 * _top_ticks / maxi(_race_ticks, 1),
			100 * _boost_ticks / maxi(_race_ticks, 1), _vmax])
		get_tree().quit()
