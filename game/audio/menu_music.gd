class_name MenuMusic
extends Node

## Musique du menu (2026-10-22 : « a la place [du bruit sourd], on ait une
## musique dans le menu »), procedurale comme la musique de course
## (RaceMusic, CLAUDE.md §8) mais posee : facon ecran-titre d'un jeu de
## course arcade (city pop, jazz-funk), 104 BPM, en fa majeur, boucle de 16
## mesures (~37 s).
##
## Voix : piano electrique FM (accords plaques sur le temps et en
## contretemps), basse FM syncopee, nappe douce ; batterie legere -
## grosse caisse, rimshot sur 2 et 4, charleston en croches balancees ; theme
## au son de cloche FM sur la seconde moitie ; echo sur le piano et le theme.
## Grosse caisse, charleston, basse et nappe : les voix de RaceMusic.
##
## Rendu une fois sur un thread de fond (prepare), garde en cache ; joue sur
## le bus Musique (SoundMix), entree en fondu. Noeud enfant du menu : il
## disparait avec lui (depart d'une course). Inactive en headless.

const RATE := 22050
const BPM := 104.0
const BARS := 16
const STEPS_PER_BAR := 16
const VOLUME_DB := -9.0
const FADE_IN_S := 2.5
const SEED := 2026

## accords, une mesure chacun : [basse (MIDI), notes du piano (MIDI)]
const CHORDS := {
	"Fmaj7": [41, [57, 60, 64, 65]],
	"Em7": [40, [55, 59, 62, 64]],
	"Dm7": [38, [57, 60, 62, 65]],
	"Cmaj7": [36, [55, 59, 60, 64]],
	"Bbmaj7": [46, [57, 58, 62, 65]],
	"Am7": [45, [55, 57, 60, 64]],
	"Gm7": [43, [53, 55, 58, 62]],
	"C7sus": [36, [55, 58, 60, 65]],
}
const PROGRESSION := ["Fmaj7", "Em7", "Dm7", "Cmaj7", "Bbmaj7", "Am7", "Gm7", "C7sus",
	"Fmaj7", "Em7", "Dm7", "Cmaj7", "Bbmaj7", "Am7", "Gm7", "C7sus"]
## Piano : doubles croches ou l'accord est plaque, et sa duree (doubles croches).
const COMP := [[0, 3], [6, 2], [10, 4]]
## Basse : [double croche, intervalle (demi-tons), duree].
const BASS := [[0, 0, 5], [6, 12, 2], [8, 0, 3], [11, 7, 2], [14, 12, 2]]
## Theme, a partir de THEME_FIRST_BAR : par mesure, [note MIDI, duree en
## doubles croches] (16 par mesure ; note < 0 : silence).
const THEME_FIRST_BAR := 8
const THEME := [
	[[69, 2], [72, 2], [76, 4], [74, 2], [72, 6]],
	[[71, 4], [74, 4], [76, 8]],
	[[77, 2], [76, 2], [74, 4], [72, 4], [69, 4]],
	[[71, 6], [67, 2], [72, 8]],
	[[74, 2], [77, 2], [81, 4], [79, 2], [77, 6]],
	[[76, 4], [72, 4], [79, 8]],
	[[77, 2], [74, 2], [70, 4], [74, 4], [77, 4]],
	[[76, 8], [79, 4], [-1, 4]],
]

static var _stream: AudioStreamWAV
static var _pcm: PackedByteArray
static var _task_id: int = -1

var _player: AudioStreamPlayer
var _want_play: bool = false


## Lance le rendu en fond s'il n'est ni fait ni en cours (sans effet en headless).
static func prepare() -> void:
	if DisplayServer.get_name() == "headless" or _stream != null or _task_id >= 0:
		return
	_task_id = WorkerThreadPool.add_task(_render_default, false, "MenuMusic")


static func _render_default() -> void:
	_pcm = render(RATE, BARS)


## Flux pret a jouer, ou null tant que le rendu de fond n'est pas fini.
static func stream() -> AudioStreamWAV:
	if _stream == null and _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id):
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = RATE
		wav.stereo = true
		wav.data = _pcm
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = _pcm.size() / 4
		_stream = wav
		_pcm = PackedByteArray()
	return _stream


## Demarre la boucle des que le rendu est pret.
func play() -> void:
	if DisplayServer.get_name() == "headless":
		return
	prepare()
	_want_play = true


func is_playing() -> bool:
	return _player != null and _player.playing


func _process(_delta: float) -> void:
	if not _want_play or is_playing():
		return
	var s := stream()
	if s == null:
		return
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.name = "MenuMusicPlayer"
		_player.bus = SoundMix.MUSIC
		add_child(_player)
	_player.stream = s
	_player.volume_db = -50.0
	_player.play()
	create_tween().tween_property(_player, "volume_db", VOLUME_DB, FADE_IN_S)


## Rend `bars` mesures (16 au plus) en PCM 16 bits stereo entrelace. Les
## queues qui depassent la fin sont repliees au debut : la boucle se raccorde
## sans clic. Deterministe. Pur calcul : appele sur un thread de fond.
static func render(rate: int, bars: int) -> PackedByteArray:
	var step := roundi(rate * 60.0 / BPM / 4.0)
	var n := bars * STEPS_PER_BAR * step
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	var send := PackedFloat32Array()
	l.resize(n)
	r.resize(n)
	send.resize(n)
	var noise := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in 8192:
		noise.append(rng.randf_range(-1.0, 1.0))
	# croches balancees : la seconde croche de chaque temps un tiers plus tard
	var swing := roundi(step / 3.0)

	for bar in bars:
		var chord: Array = CHORDS[PROGRESSION[bar]]
		var root: int = chord[0]
		var tones: Array = chord[1]
		var at := bar * STEPS_PER_BAR * step
		var theme := bar >= THEME_FIRST_BAR
		# batterie legere
		for s in STEPS_PER_BAR:
			var p := at + s * step + (swing if s % 4 == 2 else 0)
			if s == 0 or s == 10:
				RaceMusic._kick(l, r, p, rate, 0.55)
			if s == 4 or s == 12:
				_rim(l, r, noise, p, rate, 0.22)
			if s % 2 == 0:
				RaceMusic._hat(l, r, noise, p, rate, 0.07 if s % 4 == 0 else 0.05, 0.03)
		# basse syncopee
		for b: Array in BASS:
			RaceMusic._bass(l, r, at + int(b[0]) * step, RaceMusic._hz(root + int(b[1])), int(b[2]) * step, rate, 0.3)
		# piano electrique
		for c: Array in COMP:
			for k in tones.size():
				var pan := 0.3 + 0.4 * k / maxf(tones.size() - 1, 1.0)
				_epiano(l, r, send, at + int(c[0]) * step + k * 40, RaceMusic._hz(tones[k]), int(c[1]) * step, rate,
					0.075, pan)
		# nappe
		RaceMusic._pad(l, r, at, tones, STEPS_PER_BAR * step, rate, 0.03)
		# theme
		if theme and bar - THEME_FIRST_BAR < THEME.size():
			var s16 := 0
			for nd: Array in THEME[bar - THEME_FIRST_BAR]:
				if int(nd[0]) >= 0:
					_bell(l, r, send, at + s16 * step, RaceMusic._hz(nd[0]), int(nd[1]) * step, rate, 0.16)
				s16 += int(nd[1])

	# echo (3 doubles croches a gauche, 6 a droite) sur le piano et le theme
	var d := 3 * step
	for i in n:
		l[i] += send[i - d + (n if i < d else 0)] * 0.28
		var j := i - 2 * d
		while j < 0:
			j += n
		r[i] += send[j] * 0.2

	# normalisation, saturation douce, 16 bits entrelace
	var peak := 0.0
	for i in n:
		peak = maxf(peak, maxf(absf(l[i]), absf(r[i])))
	var g := 1.2 / maxf(peak, 1e-6)
	var norm := 0.85 / tanh(1.2)
	var out := PackedByteArray()
	out.resize(n * 4)
	for i in n:
		out.encode_s16(i * 4, roundi(tanh(l[i] * g) * norm * 32767.0))
		out.encode_s16(i * 4 + 2, roundi(tanh(r[i] * g) * norm * 32767.0))
	return out


## Rimshot : clic de bois a 1,7 kHz et un souffle de bruit, tres court.
static func _rim(l: PackedFloat32Array, r: PackedFloat32Array, noise: PackedFloat32Array,
		at: int, rate: int, gain: float) -> void:
	var n := l.size()
	var dur := roundi(rate * 0.06)
	var ph := 0.0
	for i in dur:
		var t := float(i) / rate
		var v := (sin(TAU * ph) * 0.7 + noise[(at + i * 5) & 8191] * 0.3) * gain * exp(-t * 70.0)
		ph += 1700.0 / rate
		var k := (at + i) % n
		l[k] += v * 0.9
		r[k] += v


## Piano electrique : FM au rapport 1 (le corps) et 14 (la lame qui tinte a
## l'attaque), decroissance lente, relache de 60 ms.
static func _epiano(l: PackedFloat32Array, r: PackedFloat32Array, send: PackedFloat32Array, at: int,
		hz: float, dur: int, rate: int, gain: float, pan: float) -> void:
	var n := l.size()
	var ph := 0.0
	var inc := hz / rate
	var total := dur + roundi(rate * 0.06)
	for i in total:
		var t := float(i) / rate
		var body := 1.1 * exp(-t * 3.0)
		var tine := 0.6 * exp(-t * 28.0)
		var env := minf(1.0, float(i) / (rate * 0.002)) * exp(-t * 1.6)
		if i >= dur:
			env *= 1.0 - float(i - dur) / (total - dur)
		var v := sin(TAU * ph + body * sin(TAU * ph) + tine * sin(TAU * ph * 14.0)) * env * gain
		ph += inc
		var k := (at + i) % n
		l[k] += v * (1.0 - pan)
		r[k] += v * pan
		send[k] += v * 0.35


## Theme : cloche FM (rapport 3,5, indice qui decroit), legere modulation.
static func _bell(l: PackedFloat32Array, r: PackedFloat32Array, send: PackedFloat32Array, at: int,
		hz: float, dur: int, rate: int, gain: float) -> void:
	var n := l.size()
	var ph := 0.0
	var inc := hz / rate
	var total := dur + roundi(rate * 0.25)
	for i in total:
		var t := float(i) / rate
		var idx := 0.4 + 1.6 * exp(-t * 9.0)
		var env := minf(1.0, float(i) / (rate * 0.004)) * exp(-t * 2.2)
		if i >= dur:
			env *= 1.0 - float(i - dur) / (total - dur)
		var vib := 1.0 + (0.004 * sin(TAU * 5.0 * t) if t > 0.2 else 0.0)
		var v := sin(TAU * ph + idx * sin(TAU * ph * 3.5)) * env * gain
		ph += inc * vib
		var k := (at + i) % n
		l[k] += v
		r[k] += v
		send[k] += v * 0.5
