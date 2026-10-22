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
## Trace par tranche de 100 m (5e argument « trace ») : vitesse, profil, ecart
## a la ligne, braquage, du 1er bot, apres son 1er tour.
var _sect: Dictionary = {}
var _last_blk: Node3D = null
## Par camion : ses 12 derniers etats (un toutes les 30 ticks), affiches avec
## un SLOW.
var _hist: Dictionary = {}


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
		var k := tr.on_branch(t.global_position, 10.0)
		print("CRASH %s tick=%d s=%.0f lat=%.1f v=%.0f zone=%s off=%s up=%.1f y=%.1f branch=%d u=%.2f jump=%s" % [t.name,
			ticks, tr.sample_s(i), d.dot(tr.sample_right(i)), t.linear_velocity.length() * 3.6, ar._zones.get(t, 0),
			ar.is_off_track(t), d.dot(tr.sample_up(i)), t.global_position.y, k,
			tr.branch_u(k, t.global_position) if k >= 0 else -1.0, tr.branch_jump(k) if k >= 0 else Vector2(-1, -1)])
		for line: String in (_hist.get(t, []) as Array).slice(-14):
			print(line))
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
			if _args.size() > 4 and t == trucks[0] and (laps.get(t, []) as Array).size() >= 1:
				var bt: BotInputSource = null
				for p: Object in ps:
					if p.get("truck") == t:
						bt = p.get("input") as BotInputSource
				var tk := scene.get("track") as TrackBlockout
				var bin := int(tk.sample_s(bt.index) / 100.0)
				if _args.size() > 6 and ticks % 15 == 0 and tk.sample_s(bt.index) >= float(_args[5]) and tk.sample_s(bt.index) <= float(_args[6]):
					print("FINE s=%.0f v=%.0f prof=%.0f tgt=%.0f lat=%.1f line=%.1f aim=%.1f steer=%.2f thr=%.2f brk=%.2f k=%.4f" % [tk.sample_s(bt.index),
						t.linear_velocity.length() * 3.6, bt._profile[bt.index] * 3.6, bt.target_speed * 3.6,
						bt._lateral_of(t.global_position, bt.index), bt.line.offset[bt.index], bt._lat_now, bt.frame.steer,
						bt.frame.throttle, bt.frame.brake, bt.line.curvature[bt.index]])
				var acc: Array = _sect.get(bin, [0, 0.0, 0.0, 0.0, 0.0, 0.0])
				acc[0] += 1
				acc[1] += t.linear_velocity.length()
				acc[2] += bt._profile[bt.index]
				acc[3] += absf(bt._lateral_of(t.global_position, bt.index) - bt.line.offset[bt.index])
				acc[4] += absf(bt.frame.steer)
				acc[5] += bt.frame.brake
				_sect[bin] = acc
				if bt.blocked_by != _last_blk:
					_last_blk = bt.blocked_by
					if _last_blk != null:
						print("BLK s=%.0f %s me_lat=%.1f line=%.1f v=%.0f" % [tk.sample_s(bt.index), _last_blk.name,
							bt._lateral_of(t.global_position, bt.index), bt.line.offset[bt.index], t.linear_velocity.length() * 3.6])
			if ticks % 30 == 0:
				var tr2 := scene.get("track") as TrackBlockout
				var j := tr2.closest_sample(t.global_position)
				var bt2: BotInputSource = null
				for p: Object in ps:
					if p.get("truck") == t:
						bt2 = p.get("input") as BotInputSource
				var h: Array = _hist.get(t, [])
				var kb := tr2.on_branch(t.global_position, 1.0)
				h.append("   t=%d s=%.0f lat=%.1f y=%.1f v=%.0f br=%d on=%d u=%.2f steer=%.2f thr=%.2f brk=%.2f fwd=%.2f tgt=%.0f lat_now=%.1f blk=%s" % [
					ticks, tr2.sample_s(j), (t.global_position - tr2.sample_position(j)).dot(tr2.sample_right(j)),
					t.global_position.y, t.linear_velocity.length() * 3.6, bt2._branch, kb,
					tr2.branch_u(kb, t.global_position) if kb >= 0 else -1.0, bt2.frame.steer, bt2.frame.throttle,
					bt2.frame.brake, (-t.global_basis.z).dot(tr2.sample_forward(j)), bt2.target_speed * 3.6, bt2._lat_now,
					bt2.blocked_by.name if bt2.blocked_by != null else "-"])
				if h.size() > 40:
					h.pop_front()
				_hist[t] = h
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
				for line: String in _hist.get(t, []):
					print(line)
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
		var keys := _sect.keys()
		keys.sort()
		for k: int in keys:
			var a: Array = _sect[k]
			var n := float(a[0])
			print("SECT s=%4d v=%3.0f prof=%3.0f laterr=%4.1f steer=%.2f brake=%.2f" % [k * 100, a[1] / n * 3.6, a[2] / n * 3.6, a[3] / n, a[4] / n, a[5] / n])
		get_tree().quit()
