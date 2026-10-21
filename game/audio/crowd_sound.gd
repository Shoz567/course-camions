class_name CrowdSound
extends AudioStreamPlayer3D

## Rumeur d'une tribune (tache 7.3) : son 3D au centre des gradins, qu'on
## entend monter en passant devant et s'eteindre en s'eloignant. Une boucle de
## LOOP_S s synthetisee une fois et partagee par toutes les tribunes (aucun
## asset externe, CLAUDE.md §8) :
##   - brouhaha : bruit filtre dans la bande des voix (environ 250 Hz a
##     2,5 kHz), dont le volume ondule lentement ;
##   - deux clameurs par boucle, qui enflent puis retombent ;
##   - quelques sifflets aigus, places par un generateur fixe (CLAUDE.md §7).
## Raccord sans claquement : bruit filtre circulairement, modulations a un
## nombre entier de periodes par boucle. Rien en headless.

const RATE := 22050
const LOOP_S := 6.0
## Portee : pleine voix a UNIT_M m, inaudible au-dela de MAX_M m.
const UNIT_M := 22.0
const MAX_M := 160.0

static var _stream: AudioStreamWAV


func _ready() -> void:
	unit_size = UNIT_M
	max_distance = MAX_M
	volume_db = -4.0
	bus = SoundMix.AMBIENCE
	if DisplayServer.get_name() == "headless":
		return
	if _stream == null:
		var wav := TruckAudio._wav(build())
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = roundi(RATE * LOOP_S)
		_stream = wav
	stream = _stream
	play()


## Une boucle (mono, RATE Hz, crete 0,8).
static func build() -> PackedFloat32Array:
	var n := roundi(RATE * LOOP_S)
	# bande des voix : passe-haut (bruit - passe-bas grave) puis passe-bas
	var voice := TruckAudio._looped_noise(n, 707, 0.5)
	var below := TruckAudio._looped_noise(n, 707, 0.07)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var u := t / LOOP_S
		# ondulation lente du brouhaha (3 et 5 periodes par boucle)
		var swell := 0.75 + 0.15 * sin(TAU * 3.0 * u) + 0.1 * sin(TAU * 5.0 * u + 1.1)
		# deux clameurs par boucle : bosses lissees centrees a 1/4 et 3/4
		var cheer := pow(0.5 - 0.5 * cos(TAU * 2.0 * u), 6.0)
		out[i] = (voice[i] - below[i]) * (swell + 0.9 * cheer)
	# sifflets : glissandos aigus courts
	var lcg := 9001
	for k in 7:
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		var start := lcg % n
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		var f0 := 1700.0 + float(lcg % 900)
		var dur := 0.35
		var phase := 0.0
		for j in roundi(RATE * dur):
			var v := float(j) / RATE
			phase += (f0 + 600.0 * v / dur) / RATE
			var env := sin(PI * v / dur)
			out[(start + j) % n] += sin(TAU * phase) * env * 0.12
	return AmbienceSound._normalize(out)
