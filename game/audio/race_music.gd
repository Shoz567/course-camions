class_name RaceMusic
extends Node

## Musique de course procedurale, esprit arcade des annees 1990-2000 (Daytona
## USA, Ridge Racer, Sega Rally, Mario Kart 64) : boucle de 16 mesures a
## 150 BPM en la mineur, synthetisee en memoire en PCM 16 bits stereo, sans
## aucun fichier (CLAUDE.md §8 : musique demandee explicitement par
## l'utilisateur le 2026-09-30).
##
## Voix : grosse caisse 4 temps, caisse claire, charleston, crash ; basse FM en
## octaves (facon Mega Drive) ; arpege en doubles croches (onde carree 25 %) ;
## nappe de dents de scie desaccordees gauche / droite ; theme au refrain
## (mesures 9 a 16) ; echo ping-pong sur l'arpege et le theme.
##
## Rendu une seule fois, sur un thread de fond (WorkerThreadPool), des le menu
## (`prepare()`), puis garde en cache pour les courses suivantes. Joue sur le
## bus Musique (SoundMix), sous le Master : le volume et la sourdine des
## reglages s'appliquent. Noeud enfant de la course : il disparait avec elle (retour au menu, rejouer).
## Totalement inactive en headless (tests) : ni rendu, ni lecteur.

const RATE := 22050
const BPM := 150.0
const BARS := 16
const STEPS_PER_BAR := 16
const VOLUME_DB := -8.0
const FADE_S := 1.5
const SEED := 1996

## accords, une mesure chacun : [basse (MIDI), notes de l'accord (MIDI)]
const CHORDS := {
	"Am": [45, [57, 60, 64, 69]],
	"F": [41, [53, 57, 60, 65]],
	"C": [48, [55, 60, 64, 67]],
	"G": [43, [55, 59, 62, 67]],
	"E": [40, [52, 56, 59, 64]],
}
const PROGRESSION := ["Am", "F", "C", "G", "Am", "F", "G", "E",
		"F", "G", "Am", "Am", "F", "G", "E", "E"]
## theme du refrain, a partir de LEAD_FIRST_BAR : par mesure, suite de
## [note MIDI, duree en doubles croches] (16 par mesure)
const LEAD_FIRST_BAR := 8
const LEAD := [
	[[72, 2], [69, 2], [72, 2], [77, 4], [76, 2], [72, 2], [74, 2]],
	[[74, 2], [71, 2], [74, 2], [79, 4], [77, 2], [74, 2], [71, 2]],
	[[76, 6], [72, 2], [69, 4], [72, 2], [76, 2]],
	[[81, 8], [79, 4], [76, 4]],
	[[72, 2], [69, 2], [72, 2], [77, 4], [76, 2], [72, 2], [74, 2]],
	[[74, 2], [71, 2], [74, 2], [79, 4], [77, 2], [79, 2], [81, 2]],
	[[80, 4], [76, 4], [83, 4], [80, 4]],
	[[76, 8], [74, 4], [71, 4]],
]
const ARP := [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 1, 2, 3]

static var _stream: AudioStreamWAV
static var _pcm: PackedByteArray
static var _task_id: int = -1

var _player: AudioStreamPlayer
var _want_play: bool = false
var _tween: Tween


## Lance le rendu en fond s'il n'est ni fait ni en cours (sans effet en headless).
static func prepare() -> void:
	if DisplayServer.get_name() == "headless" or _stream != null or _task_id >= 0:
		return
	_task_id = WorkerThreadPool.add_task(_render_default, false, "RaceMusic")


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


## Demarre la boucle (au GO), des que le rendu est pret.
func play() -> void:
	if DisplayServer.get_name() == "headless":
		return
	prepare()
	_want_play = true
	_try_start()


## Arrete la boucle en fondu (arrivee).
func fade_out() -> void:
	_want_play = false
	if _player == null or not _player.playing:
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", -60.0, FADE_S)
	_tween.tween_callback(_player.stop)


func is_playing() -> bool:
	return _player != null and _player.playing


func _process(_delta: float) -> void:
	if _want_play and not is_playing():
		_try_start()


func _try_start() -> void:
	var s := stream()
	if s == null:
		return
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.name = "RaceMusicPlayer"
		_player.bus = SoundMix.MUSIC
		add_child(_player)
	_player.stream = s
	_player.volume_db = VOLUME_DB
	_player.play()


## Rend `bars` mesures de la boucle (16 au plus) en PCM 16 bits stereo
## entrelace : `bars * 16` doubles croches de rate / 10 echantillons (150 BPM).
## Les queues de notes qui depassent la fin sont repliees au debut : la boucle
## se raccorde sans clic. Deterministe (bruit a graine fixe). Pur calcul, sans
## arbre de scene : appele sur un thread de fond.
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

	for bar in bars:
		var chord: Array = CHORDS[PROGRESSION[bar]]
		var root: int = chord[0]
		var tones: Array = chord[1]
		var at := bar * STEPS_PER_BAR * step
		var chorus := bar >= LEAD_FIRST_BAR
		var fill := bar % 8 == 7
		# batterie
		if bar % 8 == 0:
			_crash(l, r, noise, at, rate, 0.22)
		for s in STEPS_PER_BAR:
			var p := at + s * step
			if s % 4 == 0:
				_kick(l, r, p, rate, 0.95)
			if s == 4 or s == 12:
				_snare(l, r, noise, p, rate, 0.55)
			elif fill and s >= 13:
				_snare(l, r, noise, p, rate, 0.25 + 0.1 * (s - 13))
			elif s % 4 == 2:
				_hat(l, r, noise, p, rate, 0.2, 0.07)
			elif chorus or s % 2 == 1:
				_hat(l, r, noise, p, rate, 0.09, 0.025)
		# basse FM en octaves, croches
		for e in 8:
			var note := root + (12 if e % 2 == 1 else 0)
			if fill and e == 7:
				note = root + 7
			_bass(l, r, at + e * 2 * step, _hz(note), roundi(step * 1.8), rate, 0.42)
		# arpege, doubles croches, une octave au-dessus de l'accord
		for s in STEPS_PER_BAR:
			var tone: int = tones[ARP[s]] + 12
			var pan := 0.35 if s % 2 == 0 else 0.65
			_arp(l, r, send, at + s * step, _hz(tone), step, rate, 0.13 if chorus else 0.17, pan)
		# nappe
		_pad(l, r, at, tones, STEPS_PER_BAR * step, rate, 0.045)
		# theme du refrain
		if chorus and bar - LEAD_FIRST_BAR < LEAD.size():
			var s16 := 0
			for nd: Array in LEAD[bar - LEAD_FIRST_BAR]:
				_lead(l, r, send, at + s16 * step, _hz(nd[0]), int(nd[1]) * step, rate, 0.2)
				s16 += int(nd[1])

	# echo ping-pong (3 et 6 doubles croches) sur l'arpege et le theme
	var d := 3 * step
	for i in n:
		l[i] += send[i - d + (n if i < d else 0)] * 0.32
		var j := i - 2 * d
		while j < 0:
			j += n
		r[i] += send[j] * 0.24

	# normalisation, saturation douce, 16 bits entrelace
	var peak := 0.0
	for i in n:
		peak = maxf(peak, maxf(absf(l[i]), absf(r[i])))
	var g := 1.4 / maxf(peak, 1e-6)
	var norm := 0.9 / tanh(1.4)
	var out := PackedByteArray()
	out.resize(n * 4)
	for i in n:
		out.encode_s16(i * 4, roundi(tanh(l[i] * g) * norm * 32767.0))
		out.encode_s16(i * 4 + 2, roundi(tanh(r[i] * g) * norm * 32767.0))
	return out


static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## Grosse caisse : sinus qui plonge de 155 a 45 Hz.
static func _kick(l: PackedFloat32Array, r: PackedFloat32Array, at: int, rate: int, gain: float) -> void:
	var n := l.size()
	var dur := roundi(rate * 0.28)
	var ph := 0.0
	var env := gain
	var fall := exp(-11.0 / rate)
	for i in dur:
		var t := float(i) / rate
		ph += (45.0 + 110.0 * exp(-t * 32.0)) / rate
		var v := sin(TAU * ph) * env
		env *= fall
		var k := (at + i) % n
		l[k] += v
		r[k] += v


## Caisse claire : bruit + ton a 185 Hz.
static func _snare(l: PackedFloat32Array, r: PackedFloat32Array, noise: PackedFloat32Array,
		at: int, rate: int, gain: float) -> void:
	var n := l.size()
	var dur := roundi(rate * 0.2)
	var env := gain
	var fall := exp(-19.0 / rate)
	var ph := 0.0
	var prev := 0.0
	for i in dur:
		var w := noise[(at + i * 3) & 8191]
		var v := ((w + prev) * 0.45 + sin(TAU * ph) * 0.5 * exp(-float(i) / rate * 40.0)) * env
		prev = w
		ph += 185.0 / rate
		env *= fall
		var k := (at + i) % n
		l[k] += v
		r[k] += v


## Charleston : bruit derive (aigus), un peu a droite.
static func _hat(l: PackedFloat32Array, r: PackedFloat32Array, noise: PackedFloat32Array,
		at: int, rate: int, gain: float, decay_s: float) -> void:
	var n := l.size()
	var dur := roundi(rate * decay_s * 4.0)
	var env := gain
	var fall := exp(-1.0 / (rate * decay_s))
	var prev := 0.0
	for i in dur:
		var w := noise[(at * 7 + i) & 8191]
		var v := (w - prev) * env
		prev = w
		env *= fall
		var k := (at + i) % n
		l[k] += v * 0.75
		r[k] += v


## Crash : bruit derive, longue decroissance.
static func _crash(l: PackedFloat32Array, r: PackedFloat32Array, noise: PackedFloat32Array,
		at: int, rate: int, gain: float) -> void:
	var n := l.size()
	var dur := roundi(rate * 1.6)
	var env := gain
	var fall := exp(-2.6 / rate)
	var prev := 0.0
	for i in dur:
		var w := noise[(i * 5 + 11) & 8191]
		var v := (w - prev) * env
		prev = w
		env *= fall
		var k := (at + i) % n
		l[k] += v
		r[k] += v * 0.85


## Basse FM (modulateur au rapport 1, indice qui decroit : attaque brillante).
static func _bass(l: PackedFloat32Array, r: PackedFloat32Array, at: int, hz: float, dur: int,
		rate: int, gain: float) -> void:
	var n := l.size()
	var ph := 0.0
	var inc := hz / rate
	var release := roundi(rate * 0.012)
	for i in dur:
		var t := float(i) / rate
		var idx := 0.9 + 2.2 * exp(-t * 16.0)
		var env := minf(1.0, float(i) / (rate * 0.003)) * (0.6 + 0.4 * exp(-t * 10.0))
		if i > dur - release:
			env *= float(dur - i) / release
		var v := sin(TAU * ph + idx * sin(TAU * ph)) * env * gain
		ph += inc
		var k := (at + i) % n
		l[k] += v
		r[k] += v


## Arpege : onde carree 25 % filtree (passe-bas a un pole), attaque seche.
static func _arp(l: PackedFloat32Array, r: PackedFloat32Array, send: PackedFloat32Array, at: int,
		hz: float, dur: int, rate: int, gain: float, pan: float) -> void:
	var n := l.size()
	var ph := 0.0
	var inc := hz / rate
	var a := 1.0 - exp(-TAU * 2400.0 / rate)
	var y := 0.0
	var env := gain
	var fall := exp(-9.0 / rate)
	var release := roundi(rate * 0.01)
	for i in dur:
		ph += inc
		var x := 1.0 if fmod(ph, 1.0) < 0.25 else -1.0
		y += a * (x - y)
		var v := y * env
		if i > dur - release:
			v *= float(dur - i) / release
		env *= fall
		var k := (at + i) % n
		l[k] += v * (1.0 - pan)
		r[k] += v * pan
		send[k] += v * 0.5


## Nappe : 3 notes de l'accord, dents de scie desaccordees (+/- 8 cents)
## a gauche et a droite, filtrees ; fondu d'entree et de sortie.
static func _pad(l: PackedFloat32Array, r: PackedFloat32Array, at: int, tones: Array, dur: int,
		rate: int, gain: float) -> void:
	var n := l.size()
	var up := pow(2.0, 8.0 / 1200.0)
	var incs_l: Array[float] = []
	var incs_r: Array[float] = []
	for k in 3:
		var hz := _hz(float(tones[k]))
		incs_l.append(hz * up / rate)
		incs_r.append(hz / up / rate)
	var ph := [0.0, 0.3, 0.6, 0.15, 0.45, 0.75]
	var a := 1.0 - exp(-TAU * 900.0 / rate)
	var yl := 0.0
	var yr := 0.0
	var fade := roundi(rate * 0.08)
	for i in dur:
		var sl := 0.0
		var sr := 0.0
		for k in 3:
			ph[k] = fmod(ph[k] + incs_l[k], 1.0)
			ph[k + 3] = fmod(ph[k + 3] + incs_r[k], 1.0)
			sl += 2.0 * ph[k] - 1.0
			sr += 2.0 * ph[k + 3] - 1.0
		yl += a * (sl - yl)
		yr += a * (sr - yr)
		var env := gain * minf(1.0, minf(float(i) / fade, float(dur - i) / fade))
		var k2 := (at + i) % n
		l[k2] += yl * env
		r[k2] += yr * env


## Theme : deux carres desaccordes, vibrato apres 150 ms, relache de 40 ms.
static func _lead(l: PackedFloat32Array, r: PackedFloat32Array, send: PackedFloat32Array, at: int,
		hz: float, dur: int, rate: int, gain: float) -> void:
	var n := l.size()
	var ph1 := 0.0
	var ph2 := 0.5
	var a := 1.0 - exp(-TAU * 3200.0 / rate)
	var y := 0.0
	var total := dur + roundi(rate * 0.04)
	for i in total:
		var t := float(i) / rate
		var vib := 1.0 + (0.007 * sin(TAU * 5.5 * t) if t > 0.15 else 0.0)
		ph1 += hz * vib / rate
		ph2 += hz * vib * 1.004 / rate
		var x := (1.0 if fmod(ph1, 1.0) < 0.5 else -1.0) + (1.0 if fmod(ph2, 1.0) < 0.5 else -1.0)
		y += a * (x * 0.5 - y)
		var env := minf(1.0, float(i) / (rate * 0.006)) * (0.8 + 0.2 * exp(-t * 8.0))
		if i >= dur:
			env *= 1.0 - float(i - dur) / (total - dur)
		var v := y * env * gain
		var k := (at + i) % n
		l[k] += v
		r[k] += v
		send[k] += v * 0.6
