extends Node

## Trailer de 30 s (2026-10-23 : « le plus impressionnant possible [...]
## dynamique, de l'action, de la musique, et qu'il presente le jeu [...] finir
## sur l'affichage du nom du jeu avec une image stylee »).
##
## Une seule scene joue tout le film, image par image : a enregistrer avec le
## Movie Maker de Godot (make trailer : 1920 x 1080, 60 i/s, son compris).
## Les vraies courses (LocalRace) tournent dessous, 6 camions aux mains des
## bots ; le realisateur place les camions au debut de chaque plan
## (Truck.reset_to, lances a la vitesse voulue), declenche les actions
## (missile, laser, largage, nitro, explosions), pilote la camera (la Camera3D
## du joueur 1, pour garder pluie et petales autour d'elle) et les ralentis
## (Engine.time_scale). Habillage : TrailerOverlay.
##
## Musique : Neon sign Circuit (Climax), MintoDog, CC0 (audio/music/CREDITS.md),
## 160 BPM : un temps 0,375 s, une mesure 1,5 s. Elle part au GO (3 s : le
## compte a rebours du jeu sert d'ouverture, moteurs et pluie seuls) ; les
## coupes tombent sur les temps. Logo a la mesure 14 (24 s), fondu final.
##
## Options (apres --) : --snaps=t1,t2,... (captures PNG a ces instants, dans
## --snap-dir), --until=T (s'arrete a T secondes : apercus).

const LocalRace := preload("res://dev/local_race.gd")
const MUSIC := "res://audio/music/cyber_city_last_lap.ogg"
const FPS := 60.0
const MUSIC_AT := 3.0
## Premier coup de grosse caisse apres le debut du morceau (mesure le
## 2026-10-23 : 3 images, a 60 i/s).
const KICK := 0.05
const BAR := 1.5
const END := 30.0
## Niveau de la musique (Master) ; bruitages baisses de EFFECTS_DUCK_DB au GO.
const MUSIC_DB := 3.0
const EFFECTS_DUCK_DB := -3.0
const CYBER := 0
const PLAYA := 1
const SAKURA := 2
const MENU := -1

## Pilote d'un camion du trailer : la conduite du bot, puis les ordres du
## realisateur (nitro, frein a main, braquage) ; pouvoirs et largage du bot
## coupes (le realisateur les declenche lui-meme).
class Driver extends InputSource:
	var bot: BotInputSource
	var boost := false
	var handbrake := false
	var steer := NAN
	var coast := false

	func poll(tick: int) -> InputFrame:
		var f := bot.poll(tick)
		frame.copy_from(f)
		frame.tick = tick
		frame.power_left = false
		frame.power_right = false
		frame.cargo = false
		if boost:
			frame.boost = true
		if handbrake:
			frame.handbrake = true
		if not is_nan(steer):
			frame.steer = steer
		if coast:
			frame.throttle = 0.0
		return frame


var overlay: TrailerOverlay
var race: Node3D
var track: TrackBlockout
var cam: Camera3D
var drivers: Array[Driver] = []
var _scene_id := -999
var _frame := 0
var _shots: Array[Dictionary] = []
var _shot := -1
var _shot_t0 := 0.0
var _music: AudioStreamPlayer
var _snaps: Array[float] = []
var _snap_dir := ""
var _until := INF
## Ralenti : [debut, fin, echelle] en temps video.
var _slowmo: Array = []
## Camera : position et visee lissees, secousse.
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_snap := true
## Images de debut de plan ou la camera se recale sans amorti (les camions
## replaces ne le sont qu'au pas physique suivant).
var _snap_frames := 0
## Derniere position de la cible (elle disparait a son explosion).
var _foe_pos := Vector3.ZERO
var _shake := 0.0
## Point fixe du plan courant (camera posee au bord de la route).
var _anchor := Transform3D.IDENTITY
## Evenements du plan : [temps local, Callable], joues une fois.
var _events: Array = []
var _hero := 0
var _foe := 1
var _menu: Node3D
var _orbit := 0.0


func bar(n: float) -> float:
	return MUSIC_AT + KICK + n * BAR


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--snaps="):
			for s: String in a.substr(8).split(","):
				_snaps.append(float(s))
		elif a.begins_with("--snap-dir="):
			_snap_dir = a.substr(11)
		elif a.begins_with("--until="):
			_until = float(a.substr(8))
	GameState.show_fps = false
	GameState.requested_players = 1
	GameState.bot_count = 5
	GameState.bot_level = BotInputSource.Level.HARD
	GameState.game_mode = GameStateNode.GameMode.RACE
	GameState.speed_class = 3
	GameState.loadout_locked = true
	GameState.trailer_choice = PackedInt32Array([0, 5, 2, 3, 6, 1])
	GameState.power_left = PackedInt32Array([PowerCatalog.Id.MISSILE, PowerCatalog.Id.SAW, PowerCatalog.Id.LASER,
		PowerCatalog.Id.GUN, PowerCatalog.Id.BOOMERANG, PowerCatalog.Id.MISSILE])
	GameState.power_right = PackedInt32Array([PowerCatalog.Id.LASER, PowerCatalog.Id.SHIELD, PowerCatalog.Id.MISSILE,
		PowerCatalog.Id.SAW, PowerCatalog.Id.LASER, PowerCatalog.Id.GUN])
	# la musique de course du jeu se tait : celle du trailer passe sur Master
	AudioServer.set_bus_mute(AudioServer.get_bus_index(SoundMix.MUSIC), true)
	overlay = TrailerOverlay.new()
	add_child(overlay)
	_music = AudioStreamPlayer.new()
	_music.stream = load(MUSIC) as AudioStream
	_music.bus = &"Master"
	_music.volume_db = MUSIC_DB
	add_child(_music)
	_program()
	overlay.count_marks = [0.0, 1.0, 2.0]


# --- le film -------------------------------------------------------------------

func _program() -> void:
	var o := overlay
	o.flash(bar(0), 0.3, 1.0)
	o.text(bar(0) + 0.02, bar(0) + 0.7, "GO !", "", UiKit.GOLD)
	o.text(bar(1) + 0.05, bar(2.4), "COURSE DE CAMIONS", "ARCADE  ·  DÉRAPAGES  ·  CONTACTS  ·  SAUTS")
	o.text(bar(3) + 0.05, bar(4.4), "6 POUVOIRS", "MISSILE  ·  LASER  ·  SCIE  ·  BOUCLIER  ·  MITRAILLEUSE  ·  BOOMERANG")
	o.text(bar(5.5) + 0.05, bar(6.9), "LARGUE TA REMORQUE", "UN MUR EN PLEINE COURSE")
	o.text(bar(8) + 0.05, bar(9.4), "3 CIRCUITS", "CYBER CITY  ·  PLAYA DEL SOL  ·  SAKURA")
	o.text(bar(12) + 0.05, bar(13.0), "JUSQU'À 6 EN ÉCRAN PARTAGÉ", "12 EN LIGNE  ·  BOTS  ·  MODE ARÈNE")
	o.logo_at = bar(14)
	o.set_info("PC  ·  1 À 6 JOUEURS EN LOCAL  ·  EN LIGNE")
	o.black_from = END - 0.7
	o.black_to = END
	for n: float in [1, 2, 3, 4.5, 5.5, 7, 8, 9, 10.5, 12]:
		o.flash(bar(n), 0.16, 0.55)
	for k in 4:
		o.flash(bar(13) + k * BAR / 4.0, 0.1, 0.35)
	o.flash(bar(14), 0.45, 1.0)

	_shots = [
		{"at": 0.0, "scene": CYBER, "setup": _s_grid, "cam": _c_grid},
		{"at": bar(0), "scene": CYBER, "setup": _s_launch, "cam": _c_launch},
		{"at": bar(1), "scene": CYBER, "setup": _s_noop, "cam": _c_chase_low},
		{"at": bar(2), "scene": CYBER, "setup": _s_noop, "cam": _c_side},
		{"at": bar(3), "scene": CYBER, "setup": _s_missile, "cam": _c_missile},
		{"at": bar(4.5), "scene": CYBER, "setup": _s_laser, "cam": _c_laser},
		{"at": bar(5.5), "scene": CYBER, "setup": _s_drop, "cam": _c_drop},
		{"at": bar(7), "scene": CYBER, "setup": _s_duel, "cam": _c_duel},
		{"at": bar(8), "scene": PLAYA, "setup": _s_playa, "cam": _c_drone},
		{"at": bar(9), "scene": PLAYA, "setup": _s_noop, "cam": _c_jump_playa},
		{"at": bar(10.5), "scene": SAKURA, "setup": _s_sakura, "cam": _c_boost},
		{"at": bar(12), "scene": SAKURA, "setup": _s_sakura_corner, "cam": _c_corner},
		{"at": bar(13), "scene": SAKURA, "setup": _s_montage, "cam": _c_montage},
		{"at": bar(14), "scene": MENU, "setup": _s_title, "cam": _c_title},
	]


func _process(_delta: float) -> void:
	var t := _frame / FPS
	if t >= minf(END, _until):
		get_tree().quit()
		return
	# plan suivant
	while _shot + 1 < _shots.size() and t >= float(_shots[_shot + 1]["at"]):
		_shot += 1
		var s: Dictionary = _shots[_shot]
		_shot_t0 = float(s["at"])
		_events.clear()
		_cam_snap = true
		_snap_frames = 3
		if int(s["scene"]) != _scene_id:
			_load_scene(int(s["scene"]))
		(s["setup"] as Callable).call()
	var lt := t - _shot_t0
	for e: Array in _events:
		if not bool(e[2]) and lt >= float(e[0]):
			e[2] = true
			(e[1] as Callable).call()
	if t >= MUSIC_AT and not _music.playing and t < MUSIC_AT + 0.5:
		_music.play()
		for bus: StringName in [SoundMix.EFFECTS, SoundMix.AMBIENCE]:
			var k := AudioServer.get_bus_index(bus)
			AudioServer.set_bus_volume_db(k, AudioServer.get_bus_volume_db(k) + EFFECTS_DUCK_DB)
	if t > END - 1.6:
		_music.volume_db = lerpf(MUSIC_DB, -40.0, clampf((t - (END - 1.6)) / 1.6, 0.0, 1.0))
	# ralentis
	var scale := 1.0
	for m: Array in _slowmo:
		if t >= float(m[0]) and t < float(m[1]):
			var into := clampf((t - float(m[0])) / 0.08, 0.0, 1.0)
			var out := clampf((float(m[1]) - t) / 0.25, 0.0, 1.0)
			scale = minf(scale, lerpf(1.0, float(m[2]), minf(into, out)))
	Engine.time_scale = scale
	if _shot >= 0 and cam != null:
		if _snap_frames > 0:
			_snap_frames -= 1
			_cam_snap = true
		(_shots[_shot]["cam"] as Callable).call(lt)
	overlay.update(t)
	if _snaps.size() > 0 and _snap_dir != "":
		for s: float in _snaps:
			if absf(s - t) < 0.5 / FPS:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/snap_%05.2f.png" % [_snap_dir, s])
	_frame += 1


func _event(at: float, f: Callable) -> void:
	_events.append([at, f, false])


func _slow(from: float, duration: float, scale: float) -> void:
	_slowmo.append([from, from + duration, scale])


# --- scenes ---------------------------------------------------------------------

func _load_scene(id: int) -> void:
	_scene_id = id
	Engine.time_scale = 1.0
	if race != null:
		remove_child(race)
		race.free()
		race = null
		track = null
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null
	drivers.clear()
	if id == MENU:
		GameState.selected_track = 0
		GameState.requested_players = 6
		_menu = (load("res://ui/main_menu.tscn") as PackedScene).instantiate() as Node3D
		_menu.set("auto_change_scene", false)
		add_child(_menu)
		var ui := _menu.get_node_or_null(^"UI") as CanvasLayer
		if ui != null:
			ui.visible = false
		var mm := _menu.get_node_or_null(^"MenuMusic")
		if mm != null:
			mm.queue_free()
		cam = _menu.get("camera") as Camera3D
		cam.h_offset = 0.0
		_menu.set("orbit_speed", 0.0)
		_menu.set_process(false)
		return
	GameState.requested_players = 1
	GameState.selected_track = id
	race = (load(GameStateNode.track_scene(id)) as PackedScene).instantiate() as Node3D
	add_child(race)
	track = race.get("track") as TrackBlockout
	var players: Array = race.get("players")
	for i in players.size():
		var p: Object = players[i]
		var t := p.get("truck") as Truck
		var bot := p.get("input") as BotInputSource
		if bot == null:
			bot = BotInputSource.new()
			bot.name = "TrailerBot%d" % i
			bot.setup(track, t, BotInputSource.Level.HARD, 7 + i)
			race.add_child(bot)
		var d := Driver.new()
		d.name = "TrailerDriver%d" % i
		d.bot = bot
		race.add_child(d)
		p.set("input", d)
		drivers.append(d)
		var hud := p.get("hud") as Node
		if hud != null:
			hud.set("visible", false)
	var chase := (players[0] as Object).get("camera") as ChaseCamera
	chase.process_mode = Node.PROCESS_MODE_DISABLED
	cam = chase.get_camera()
	cam.top_level = true
	cam.current = true
	if id != CYBER:
		# deja lancee : plus de compte a rebours (les camions sont replaces)
		race.set("_state_tick", GameClock.now() - LocalRace.COUNTDOWN_TICKS - 1)


func _truck(i: int) -> Truck:
	return ((race.get("players") as Array)[i] as Object).get("truck") as Truck


func _xf(i: int) -> Transform3D:
	return _truck(i).get_global_transform_interpolated()


## Pose le camion `i` sur la piste a l'abscisse `s`, decale de `lateral`,
## lance a `speed` m/s dans le sens de course.
func _place(i: int, s: float, lateral: float, speed: float) -> void:
	var k := track.index_at_s(fposmod(s, track.length()))
	var xf := track.frame_at(k, lateral, 0.35)
	var t := _truck(i)
	var h := TruckHealth.of(t)
	if h != null:
		if h.is_wrecked():
			# epave d'un plan precedent (explosion voisine) : camion neuf tout
			# de suite, minuteur de l'epave arrete
			h.set("_wreck_left", 0)
			h.call("_respawn")
		h.repair(h.max_hp, 999.0)
	if t.is_trailer_detached():
		t.reattach_trailer(true)
	t.reset_to(xf, -xf.basis.z * speed)


func _road(s: float, lateral: float, lift: float) -> Transform3D:
	return track.frame_at(track.index_at_s(fposmod(s, track.length())), lateral, lift)


func _fire(i: int, power: int) -> void:
	var tp := TruckPowers.of(_truck(i))
	if tp == null:
		return
	tp.slots[0] = power
	tp.cooldown[0] = 0
	tp.use(0)


func _boom(i: int) -> void:
	var h := TruckHealth.of(_truck(i))
	if h != null:
		h.damage(9999.0, &"trailer")
	_shake = 1.0


## A 0 PV, le camion `i` explose au prochain coup ; ralenti a son explosion.
func _fragile(i: int, slow_s: float, scale: float) -> void:
	var h := TruckHealth.of(_truck(i))
	if h == null:
		return
	h.hp = 1.0
	h.trailer_hp = 1.0
	h.destroyed.connect(func() -> void:
		var t := _frame / FPS
		_slow(t, slow_s, scale)
		overlay.flash(t, 0.2, 0.6)
		_shake = 1.0, CONNECT_ONE_SHOT)


# --- plans ----------------------------------------------------------------------

func _s_noop() -> void:
	pass


func _s_grid() -> void:
	_anchor = track.get_start_transform(0)


func _s_launch() -> void:
	_anchor = track.get_start_transform(0)


## Coups de missile : un tireur, une cible 32 m devant, ligne droite de Cyber
## City (s 650-950, tremplin a 772) ; la cible explose au ralenti.
func _s_missile() -> void:
	_hero = 0
	_foe = 1
	_place(0, 655.0, -2.8, 46.0)
	_place(1, 700.0, 2.6, 44.0)
	_place(2, 600.0, 2.8, 47.0)
	_place(3, 580.0, -2.8, 47.0)
	_place(4, 555.0, 0.0, 47.0)
	_place(5, 530.0, 2.0, 47.0)
	_fragile(1, 1.0, 0.22)
	_event(0.35, func() -> void: _fire(0, PowerCatalog.Id.MISSILE))


## Laser : seconde ligne droite (s 2842-3002), le rayon de 2 sur 4.
func _s_laser() -> void:
	_hero = 2
	_foe = 4
	_place(2, 2850.0, -1.2, 45.0)
	_place(4, 2876.0, 1.0, 43.0)
	_place(3, 2830.0, 2.4, 46.0)
	_place(5, 2815.0, -2.4, 46.0)
	var h := TruckHealth.of(_truck(4))
	if h != null:
		h.hp = 22.0
		h.trailer_hp = 22.0
	_event(0.1, func() -> void: _fire(2, PowerCatalog.Id.LASER))


## Largage : 3 lache sa remorque devant 5, qui la percute et explose.
func _s_drop() -> void:
	_hero = 5
	_foe = 3
	_place(3, 70.0, 0.4, 38.0)
	_place(5, 46.0, 0.6, 50.0)
	_place(0, 20.0, -2.6, 46.0)
	_place(1, 10.0, 2.6, 46.0)
	_fragile(5, 1.1, 0.2)
	_event(0.05, func() -> void:
		var cargo := _truck(3).get_node_or_null(^"Cargo") as TruckCargo
		if cargo != null:
			cargo.drop())


## Duel cote a cote (ligne droite s 2842-3002) : scies sorties de 1 contre
## 3, qui riposte a la mitrailleuse.
func _s_duel() -> void:
	_hero = 1
	_foe = 3
	_place(1, 2860.0, -1.9, 42.0)
	_place(3, 2862.0, 1.9, 42.0)
	_place(0, 2835.0, 0.0, 42.0)
	_event(0.05, func() -> void: _fire(1, PowerCatalog.Id.SAW))
	_event(0.35, func() -> void: _fire(3, PowerCatalog.Id.GUN))


## Playa : peloton sur la grande ligne droite (s 1856-2206), vers le tremplin
## geant de s 2006.
func _s_playa() -> void:
	_hero = 0
	var j := track.jump_pad_transform(0)
	var s := track.sample_s(track.closest_sample(j.origin))
	var lat := (j.origin - _road(s, 0.0, 0.0).origin).dot(_road(s, 0.0, 0.0).basis.x)
	_anchor = j
	_place(0, s - 120.0, lat, 48.0)
	_place(1, s - 132.0, lat - 2.6, 48.0)
	_place(2, s - 140.0, lat + 2.6, 48.0)
	_place(3, s - 150.0, lat, 48.0)
	_place(4, s - 162.0, lat - 2.0, 48.0)
	_place(5, s - 175.0, lat + 2.0, 48.0)
	_event(BAR + 0.85, func() -> void: _slow(_frame / FPS, 0.9, 0.3))


## Sakura : ligne droite (s 1728-2580), nitro du camion 0.
func _s_sakura() -> void:
	_hero = 0
	_place(0, 1760.0, 0.0, 44.0)
	_place(1, 1785.0, -2.4, 46.0)
	_place(2, 1800.0, 2.4, 46.0)
	_place(3, 1740.0, 2.0, 44.0)
	_place(4, 1725.0, -2.0, 44.0)
	_place(5, 1705.0, 0.0, 44.0)
	_event(0.4, func() -> void: drivers[0].boost = true)
	_event(1.6, func() -> void: _fire(0, PowerCatalog.Id.MISSILE))


## Virage de Sakura (s 3043) en derapage.
func _s_sakura_corner() -> void:
	drivers[0].boost = false
	_hero = 0
	_place(0, 2990.0, 1.5, 31.0)
	_place(1, 2968.0, -1.5, 32.0)
	_place(2, 2950.0, 2.0, 32.0)
	_anchor = _road(3043.0, 0.0, 0.0)


## Montage sur les temps : explosions en cascade, coupe a chaque temps.
func _s_montage() -> void:
	_hero = 1
	_place(1, 2080.0, 0.0, 44.0)
	_place(3, 2100.0, -2.4, 44.0)
	_place(4, 2112.0, 2.4, 44.0)
	_place(5, 2062.0, 2.0, 44.0)
	_place(2, 2050.0, -2.0, 44.0)
	_event(0.05, func() -> void: _boom(3))
	_event(BAR / 4.0 + 0.05, func() -> void: _fire(1, PowerCatalog.Id.LASER))
	_event(BAR / 2.0 + 0.05, func() -> void: _boom(4))
	_event(BAR * 0.75 + 0.05, func() -> void: _boom(5))


func _s_title() -> void:
	overlay.bars_on = 0.0
	_orbit = 0.0


# --- cameras ---------------------------------------------------------------------

## Pose la camera en `pos`, visant `look`, champ `fov` ; `smooth` > 0 : amortie.
func _put(pos: Vector3, look: Vector3, fov: float, smooth: float = 0.0) -> void:
	if _cam_snap or smooth <= 0.0:
		_cam_pos = pos
		_cam_look = look
		_cam_snap = false
	else:
		var k := 1.0 - exp(-smooth / FPS)
		_cam_pos = _cam_pos.lerp(pos, k)
		_cam_look = _cam_look.lerp(look, k)
	var p := _cam_pos
	if _shake > 0.0:
		p += Vector3(sin(_frame * 1.7), cos(_frame * 2.3), sin(_frame * 1.1)) * _shake * 0.35
		_shake = maxf(0.0, _shake - 1.6 / FPS)
	cam.fov = fov
	if p.distance_to(_cam_look) > 0.01:
		cam.global_transform = Transform3D(Basis.IDENTITY, p).looking_at(_cam_look, Vector3.UP)


## Grille de nuit : travelling lent au ras du sol, face aux calandres.
func _c_grid(lt: float) -> void:
	var a := _anchor
	var fwd := -a.basis.z
	var side := a.basis.x
	var pos := a.origin + fwd * (11.0 - lt * 0.9) + side * (-7.0 + lt * 3.2) + Vector3.UP * 0.7
	var look := a.origin + side * (lt * 1.2 - 1.0) + Vector3.UP * 1.6 - fwd * 4.0
	_put(pos, look, 52.0 - lt * 2.0)


## GO : camera posee au ras de la route devant la grille, les camions foncent.
func _c_launch(lt: float) -> void:
	var a := _anchor
	var fwd := -a.basis.z
	var pos := a.origin + fwd * 17.0 + a.basis.x * 4.8 + Vector3.UP * 0.5
	var look := _xf(0).origin + Vector3.UP * 1.5
	_put(pos, look, 70.0 + lt * 6.0, 18.0)


## Camera de face devant le camion de tete, qui la rattrape ; le peloton
## derriere lui.
func _c_chase_low(lt: float) -> void:
	var lead := _leader()
	var xf := _xf(lead)
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var pos := xf.origin + fwd * (15.0 - lt * 5.0) + side * 3.2 + Vector3.UP * 1.3
	var look := xf.origin - fwd * 6.0 + Vector3.UP * 1.8
	_put(pos, look, 66.0, 14.0)


## Travelling lateral a hauteur de roue.
func _c_side(lt: float) -> void:
	var lead := _leader()
	var xf := _xf(lead)
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var pos := xf.origin + side * 10.0 + fwd * (3.0 - lt * 4.0) + Vector3.UP * 1.4
	var look := xf.origin - fwd * (3.0 + lt * 2.0) + Vector3.UP * 1.8
	_put(pos, look, 58.0, 14.0)


## Missile : de cote et en hauteur, le tireur et sa cible dans l'image.
func _c_missile(lt: float) -> void:
	var xf := _xf(_hero)
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	if not _truck(_foe).is_wrecked():
		_foe_pos = _xf(_foe).origin
	var mid := xf.origin.lerp(_foe_pos, 0.55)
	var pos := mid - side * (19.0 - lt * 2.0) - fwd * 6.0 + Vector3.UP * (5.0 - lt * 0.8)
	_put(pos, mid + Vector3.UP * 1.5, 62.0, 8.0)


## Laser : camera basse devant, de trois quarts, le rayon vient vers nous.
func _c_laser(lt: float) -> void:
	var xf := _xf(_hero)
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var pos := xf.origin + fwd * (14.0 - lt * 2.0) - side * 5.5 + Vector3.UP * 1.0
	var look := xf.origin.lerp(_xf(_foe).origin, 0.45) + Vector3.UP * 1.5
	_put(pos, look, 58.0, 10.0)


## Largage : derriere celui qui va percuter la remorque.
func _c_drop(lt: float) -> void:
	var xf := _xf(_hero)
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var pos := xf.origin - fwd * 7.0 + side * 6.0 + Vector3.UP * 3.2
	var look := xf.origin + fwd * 18.0 + Vector3.UP * 1.0
	if lt > 0.9:
		# apres l'impact : on tourne autour de l'epave
		var a := (lt - 0.9) * 0.9
		pos = xf.origin + (side * cos(a) - fwd * sin(a) * -1.0) * 9.0 + Vector3.UP * 2.6
		look = xf.origin + Vector3.UP * 1.2
	_put(pos, look, 64.0, 8.0)


## Duel : camera basse devant les deux cabines, qui recule avec elles.
func _c_duel(lt: float) -> void:
	var a := _xf(_hero).origin
	var b := _xf(_foe).origin
	var mid := a.lerp(b, 0.5)
	var xf := _xf(_hero)
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var pos := mid + fwd * (11.0 - lt * 1.5) + side * (2.5 - lt * 3.0) + Vector3.UP * 1.0
	_put(pos, mid + Vector3.UP * 1.6 - fwd * 2.0, 70.0, 12.0)


## Playa : drone qui plonge sur le peloton, la mer derriere.
func _c_drone(lt: float) -> void:
	var xf := _xf(_hero)
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var pos := xf.origin - fwd * (26.0 - lt * 6.0) + side * (14.0 - lt * 4.0) + Vector3.UP * (30.0 - lt * 14.0)
	var look := xf.origin + fwd * 12.0
	_put(pos, look, 60.0, 6.0)


## Playa : au pied du tremplin geant, on regarde le peloton s'envoler.
func _c_jump_playa(lt: float) -> void:
	var a := _anchor
	var fwd := -a.basis.z
	var pos := a.origin + fwd * 28.0 - a.basis.x * 11.0 + Vector3.UP * 1.2
	var look := _xf(_hero).origin + Vector3.UP * 2.0
	_put(pos, look, 64.0, 14.0)


## Sakura : nitro de pres, camera basse derriere qui recule.
func _c_boost(lt: float) -> void:
	var xf := _xf(_hero)
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var lead := 16.0 - clampf(lt - 0.4, 0.0, 1.8) * 7.0
	var pos := xf.origin + fwd * lead + side * 3.4 + Vector3.UP * 1.0
	var look := xf.origin - fwd * 4.0 + Vector3.UP * 1.6
	_put(pos, look, 64.0 + clampf(lt - 0.4, 0.0, 1.0) * 12.0, 10.0)


## Virage de Sakura : la camera, au ras de la route, se laisse depasser par le
## camion de tete.
func _c_corner(lt: float) -> void:
	var xf := _xf(_hero)
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var pos := xf.origin + fwd * (9.0 - lt * 11.0) + side * 5.5 + Vector3.UP * 1.1
	_put(pos, xf.origin + Vector3.UP * 1.8 + fwd * 2.0, 66.0, 14.0)


## Montage : un angle different a chaque temps.
func _c_montage(lt: float) -> void:
	var k := clampi(int(lt / (BAR / 4.0)), 0, 3)
	var xf := _xf(_hero)
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var offsets := [Vector3(-11.0, 1.6, 10.0), Vector3(-3.0, 8.0, -30.0), Vector3(13.0, 1.4, -4.0), Vector3(0.0, 20.0, -12.0)]
	var o: Vector3 = offsets[k]
	var pos := xf.origin + side * o.x + Vector3.UP * o.y + fwd * o.z
	if k != int((lt - 1.0 / FPS) / (BAR / 4.0)):
		_cam_snap = true
	_put(pos, xf.origin + fwd * 8.0 + Vector3.UP * 1.2, 64.0, 0.0)


## Titre : plateau du menu, la camera monte et recule lentement.
func _c_title(lt: float) -> void:
	var center: Vector3 = _menu.get("_orbit_center")
	var a := 0.5 + PI + lt * 0.07
	var r := 34.0 - lt * 1.2
	var pos := center + Vector3(sin(a), 0.0, cos(a)) * r + Vector3.UP * (3.6 + lt * 0.4)
	_put(pos, center + Vector3.UP * 2.5, 58.0)


func _leader() -> int:
	var best := 0
	var best_s := -INF
	for i in drivers.size():
		var s := track.sample_s(track.closest_sample(_xf(i).origin))
		# la grille est juste avant la ligne : au depart, s proche de la fin
		if s > track.length() * 0.6:
			s -= track.length()
		if s > best_s:
			best_s = s
			best = i
	return best
