class_name AmbienceSound
extends Node

## Ambiance sonore du circuit (tache 7.3), sous la musique, du chargement a la
## fin de la course :
##   CYBER_CITY    pluie (souffle aigu, gouttes) et rumeur grave de la ville ;
##   PLAYA_DEL_SOL deux vagues par boucle qui montent, deferlent et
##                 ecument, et le vent.
## Une boucle par theme, synthetisee une fois (aucun asset externe,
## CLAUDE.md §8), sans claquement au raccord : bruit filtre circulairement et
## modulations a un nombre entier de periodes par boucle. Gouttes placees
## par un generateur fixe (CLAUDE.md §7 : aucun tirage). Rien en headless.
## Synthese : 115 ms (ville), 161 ms (plage) sur la machine de reference,
## une fois par theme, au chargement de la course.

const RATE := 22050
## Duree d'une boucle (s) : deux vagues de 4 s sur la plage.
const LOOP_S := 8.0
## Volume de l'ambiance (dB), fondu d'entree.
const VOLUME_DB := -14.0
const FADE_IN_S := 1.5

@export var theme_id: int = TrackTheme.Id.CYBER_CITY

static var _streams: Dictionary = {}
var _player: AudioStreamPlayer
var _fade: float = 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not _streams.has(theme_id):
		var wav := TruckAudio._wav(build(theme_id))
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = roundi(RATE * LOOP_S)
		_streams[theme_id] = wav
	_player = AudioStreamPlayer.new()
	_player.name = "Ambience"
	_player.bus = &"Master"
	_player.stream = _streams[theme_id]
	_player.volume_db = -60.0
	add_child(_player)
	_player.play()


func _process(delta: float) -> void:
	if _player == null or _fade >= 1.0:
		return
	_fade = minf(_fade + delta / FADE_IN_S, 1.0)
	_player.volume_db = VOLUME_DB + linear_to_db(maxf(_fade, 0.001))


## Une boucle de LOOP_S secondes (mono, RATE Hz, crete 0,8).
static func build(id: int) -> PackedFloat32Array:
	return _build_playa() if id == TrackTheme.Id.PLAYA_DEL_SOL else _build_city()


static func _build_city() -> PackedFloat32Array:
	var n := roundi(RATE * LOOP_S)
	var bright := TruckAudio._looped_noise(n, 101, 0.6)
	var dull := TruckAudio._looped_noise(n, 101, 0.15)
	var rumble := TruckAudio._looped_noise(n, 202, 0.004)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		# pluie : bruit passe-bande, respiration lente (2 periodes par boucle)
		var rain := (bright[i] - dull[i]) * (0.85 + 0.15 * sin(TAU * 2.0 * t / LOOP_S))
		# ville : grondement tres grave
		out[i] = rain * 0.9 + rumble[i] * 9.0
	# gouttes sur la tole et les flaques : petits « tic » amortis
	var lcg := 4242
	for k in 260:
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		var start := lcg % n
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		var f := 2200.0 + float(lcg % 2600)
		var amp := 0.15 + 0.25 * float((lcg >> 8) % 100) / 100.0
		for j in roundi(RATE * 0.025):
			var u := float(j) / RATE
			out[(start + j) % n] += sin(TAU * f * u) * exp(-u * 260.0) * amp
	return _normalize(out)


static func _build_playa() -> PackedFloat32Array:
	var n := roundi(RATE * LOOP_S)
	var deep := TruckAudio._looped_noise(n, 303, 0.03)
	var bright := TruckAudio._looped_noise(n, 404, 0.5)
	var dull := TruckAudio._looped_noise(n, 404, 0.08)
	var wind := TruckAudio._looped_noise(n, 505, 0.01)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		# deux vagues par boucle, la seconde un peu plus faible
		var phase := fmod(t, LOOP_S / 2.0) / (LOOP_S / 2.0)
		var which := 1.0 if t < LOOP_S / 2.0 else 0.8
		# la vague monte (grave), deferle, puis l'ecume se retire (aigu)
		var swell := pow(0.5 - 0.5 * cos(TAU * phase), 2.0)
		var foam := pow(0.5 - 0.5 * cos(TAU * fmod(phase + 0.85, 1.0)), 3.0)
		var gust := 0.7 + 0.3 * sin(TAU * 2.0 * t / LOOP_S + 0.8)
		# vent en fond, bien sous la houle (il la masquait a force egale)
		out[i] = (deep[i] * 9.0 * swell + (bright[i] - dull[i]) * 1.1 * foam) * which \
				+ wind[i] * 3.0 * gust
	return _normalize(out)


static func _normalize(out: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	if peak > 0.0:
		var k := 0.8 / peak
		for i in out.size():
			out[i] *= k
	return out
