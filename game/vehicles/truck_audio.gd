class_name TruckAudio
extends Node3D

## Sons du camion (enfant « Audio », tache 3.5 « juice minimal ») :
##   - moteur : boucle au regime ; le regime suit la vitesse dans une boite a
##     GEARS rapports (il retombe a chaque passage de vitesse), monte a vide
##     sous le gaz (arret, en l'air) ; plus fort sous la charge ;
##   - crissement : boucle dont le volume suit la glissade laterale du train
##     arriere (derapage, frein a main) quand les roues touchent ; moitie moins
##     fort sur la route mouillee de Cyber City ;
##   - chocs : un coup sourd et metallique a chaque impact (mur, camion,
##     obstacle), d'autant plus fort que le choc est violent.
## Tout est synthetise une fois a l'execution, partage par tous les camions
## (aucun fichier audio tiers, CLAUDE.md §8 ; rien de lourd a l'apparition
## d'un camion, SPIKE A14), sans tirage aleatoire (CLAUDE.md §7). Cote reseau,
## les camions des autres joueurs jouent leurs chocs d'apres les evenements du
## host (NetRace) : memes signaux.
## Rien en headless : le pilote audio factice ne mixe jamais (TruckBoostSound).

const RATE := 22050
## Frequence de la boucle moteur au regime de reference (ENGINE_REF_RPM).
const ENGINE_BASE_HZ := 55.0
const ENGINE_REF_RPM := 1500.0
const IDLE_RPM := 800.0
const MAX_RPM := 2500.0
## Vitesse (km/h) au haut de chaque rapport.
const GEARS: PackedFloat32Array = [22.0, 45.0, 72.0, 104.0, 140.0, 240.0]
## Glissement lateral (m/s) a partir duquel le pneu crie, et a fond.
const SQUEAL_FROM_MS := 2.5
const SQUEAL_FULL_MS := 9.0
## Choc le plus faible qui s'entend (m/s), et le plus fort.
const IMPACT_MIN_MS := 2.0
const IMPACT_FULL_MS := 22.0
## Ecart minimal entre deux sons de choc (s) : un frottement ne mitraille pas.
const IMPACT_GAP_S := 0.12

static var _engine_stream: AudioStreamWAV
static var _squeal_stream: AudioStreamWAV
static var _impact_stream: AudioStreamWAV

var _truck: Truck
var _engine: AudioStreamPlayer3D
var _squeal: AudioStreamPlayer3D
var _impacts: Array[AudioStreamPlayer3D] = []
var _next_impact: int = 0
var _impact_wait: float = 0.0
var rpm: float = IDLE_RPM
var squeal_level: float = 0.0
var _live: bool = false


func _ready() -> void:
	_truck = get_parent() as Truck
	if _truck == null:
		return
	_truck.wall_impact_at.connect(func(v: float, _r: bool, _at: Vector3, _n: Vector3) -> void: impact(v))
	_truck.body_impact.connect(func(v: float, _r: bool, _at: Vector3, _n: Vector3) -> void: impact(v))
	_live = DisplayServer.get_name() != "headless"
	if not _live:
		return
	if _engine_stream == null:
		_engine_stream = _loop(_build_engine())
		_squeal_stream = _loop(_build_squeal())
		_impact_stream = _wav(_build_impact())
	_engine = _player(_engine_stream, 16.0, -8.0)
	_engine.position = TruckSpec.CAB_CENTER
	_engine.play()
	_squeal = _player(_squeal_stream, 12.0, -6.0)
	_squeal.position = Vector3(0.0, 0.4, 1.5)
	for k in 2:
		var p := _player(_impact_stream, 14.0, 0.0)
		_impacts.append(p)


func _player(stream: AudioStream, unit: float, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = unit
	p.volume_db = db
	p.max_db = 3.0
	add_child(p)
	return p


## Regime du moteur pour cette vitesse (km/h) et ce gaz (0 .. 1) : dans le
## rapport courant, du ralenti au regime de passage ; a l'arret ou en l'air, le
## gaz fait monter le regime a vide.
static func rpm_for(speed_kmh: float, throttle: float, grounded: bool) -> float:
	var v := absf(speed_kmh)
	var lo := 0.0
	for hi in GEARS:
		if v <= hi:
			var u := (v - lo) / maxf(hi - lo, 1.0)
			var r := lerpf(1100.0 if lo > 0.0 else IDLE_RPM, MAX_RPM, u)
			if not grounded or v < 3.0:
				r = maxf(r, lerpf(IDLE_RPM, MAX_RPM * 0.9, throttle))
			return r
		lo = hi
	return MAX_RPM


## Crissement (0 .. 1) pour ce glissement lateral (m/s), ce frein a main.
static func squeal_for(slide_ms: float, handbrake: float, grounded: bool) -> float:
	if not grounded:
		return 0.0
	var s := clampf((slide_ms - SQUEAL_FROM_MS) / (SQUEAL_FULL_MS - SQUEAL_FROM_MS), 0.0, 1.0)
	return clampf(maxf(s, handbrake * clampf(slide_ms / SQUEAL_FULL_MS, 0.0, 1.0)), 0.0, 1.0)


## Volume d'un choc (0 .. 1) a cette vitesse d'impact (m/s).
static func impact_level(speed_ms: float) -> float:
	return clampf((speed_ms - IMPACT_MIN_MS) / (IMPACT_FULL_MS - IMPACT_MIN_MS), 0.0, 1.0)


func impact(speed_ms: float) -> void:
	var level := impact_level(speed_ms)
	if not _live or level <= 0.0 or _impact_wait > 0.0 or _impacts.is_empty():
		return
	_impact_wait = IMPACT_GAP_S
	var p := _impacts[_next_impact]
	_next_impact = (_next_impact + 1) % _impacts.size()
	p.volume_db = linear_to_db(lerpf(0.25, 1.0, level))
	# chocs violents plus graves, legers plus secs ; aucun tirage
	p.pitch_scale = lerpf(1.25, 0.8, level)
	p.play()


func _process(delta: float) -> void:
	if _truck == null:
		return
	var grounded := _truck.wheels_on_ground() >= 2
	var throttle := _truck.get_input().throttle
	var speed := _truck.get_speed_kmh()
	# regime lisse : l'aiguille ne saute pas d'une image a l'autre, sauf au
	# passage de vitesse (chute franche)
	var target := rpm_for(speed, throttle, grounded) if not _truck.is_wrecked() else 0.0
	rpm = lerpf(rpm, target, 1.0 - exp(-(14.0 if target < rpm - 300.0 else 6.0) * delta))
	var v := _truck.linear_velocity
	var slide := absf(v.dot(_truck.global_basis.x))
	squeal_level = lerpf(squeal_level, squeal_for(slide, _truck.get_handbrake_blend(), grounded),
		1.0 - exp(-10.0 * delta))
	_impact_wait = maxf(_impact_wait - delta, 0.0)
	if not _live:
		return
	if _truck.is_wrecked() or not _truck.is_visible_in_tree():
		if _engine.playing:
			_engine.stop()
		_squeal.stop()
		return
	if not _engine.playing:
		_engine.play()
	_engine.pitch_scale = clampf(rpm / ENGINE_REF_RPM, 0.4, 2.0)
	_engine.volume_db = linear_to_db(lerpf(0.35, 0.8, throttle) * lerpf(0.8, 1.0, rpm / MAX_RPM))
	var wet := 0.5 if TruckWheelFx.spray == TruckWheelFx.Spray.WATER else 1.0
	var sq := squeal_level * wet
	if sq > 0.03:
		_squeal.volume_db = linear_to_db(sq * 0.7)
		_squeal.pitch_scale = lerpf(0.9, 1.15, squeal_level)
		if not _squeal.playing:
			_squeal.play()
	elif _squeal.playing:
		_squeal.stop()


# --- synthese ----------------------------------------------------------------

static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(roundi(samples[i] * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


static func _loop(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := _wav(samples)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples.size()
	return wav


## Bruit fixe (generateur congruentiel), filtre passe-bas CIRCULAIREMENT : il
## boucle sans claquement (deux tours, le second en regime etabli).
static func _looped_noise(n: int, seed_value: int, cutoff: float) -> PackedFloat32Array:
	var raw := PackedFloat32Array()
	raw.resize(n)
	var lcg := seed_value
	for i in n:
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		raw[i] = float(lcg) / 1073741824.0 - 1.0
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for _pass in 2:
		for i in n:
			low += (raw[i] - low) * cutoff
			out[i] = low
	return out


## Moteur diesel : 1 s, fondamentale ENGINE_BASE_HZ (un nombre entier de
## periodes : la boucle est continue), harmoniques decroissants et bruit de
## combustion module au rythme des explosions (3 par periode).
static func _build_engine() -> PackedFloat32Array:
	var n := RATE
	var noise := _looped_noise(n, 31, 0.08)
	var out := PackedFloat32Array()
	out.resize(n)
	var amps: PackedFloat32Array = [1.0, 0.7, 0.55, 0.3, 0.22, 0.15, 0.1, 0.06]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for k in amps.size():
			s += amps[k] * sin(TAU * ENGINE_BASE_HZ * (k + 1) * t + k * 0.7)
		var firing := 0.55 + 0.45 * cos(TAU * ENGINE_BASE_HZ * 3.0 * t)
		out[i] = (s * 0.16 + noise[i] * 1.4 * firing) * 0.6
	return out


## Crissement : 0,5 s, trois partiels aigus (entiers de periodes) modules, plus
## un souffle passe-bande.
static func _build_squeal() -> PackedFloat32Array:
	var n := RATE / 2
	var noise := _looped_noise(n, 77, 0.45)
	var low := _looped_noise(n, 77, 0.12)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var am := 0.75 + 0.25 * sin(TAU * 14.0 * t)
		var tone := sin(TAU * 1800.0 * t) * 0.5 + sin(TAU * 2350.0 * t) * 0.3 + sin(TAU * 2900.0 * t) * 0.2
		out[i] = (tone * 0.35 * am + (noise[i] - low[i]) * 0.9) * 0.55
	return out


## Choc : 0,6 s, coup sourd qui descend de 90 a 40 Hz, tole (partiels
## inharmoniques qui s'eteignent vite), souffle bref.
static func _build_impact() -> PackedFloat32Array:
	var n := roundi(RATE * 0.6)
	var noise := _looped_noise(n, 5, 0.3)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / 0.6
		phase += lerpf(90.0, 40.0, u) / RATE
		var thump := sin(TAU * phase) * exp(-t * 9.0)
		var clang := (sin(TAU * 523.0 * t) * 0.5 + sin(TAU * 1310.0 * t) * 0.35 + sin(TAU * 2470.0 * t) * 0.2) \
				* exp(-t * 14.0)
		var burst := noise[i] * exp(-t * 30.0)
		var attack := minf(1.0, t / 0.002)
		out[i] = (thump * 0.9 + clang * 0.45 + burst * 1.2) * attack * 0.7
	return out
