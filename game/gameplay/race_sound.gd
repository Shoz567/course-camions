class_name RaceSound
extends RefCounted

## Bruitages de course des joueurs de cet ecran (tache 7.3), synthetises
## (aucun asset externe, CLAUDE.md §8), sans tirage aleatoire :
##   - tour boucle : deux notes montantes (mi, si) ;
##   - dernier tour : arpege do-mi-sol-do, plus long ;
##   - arrivee : fanfare, accord de do majeur tenu apres l'arpege.
## Non spatialises : c'est un signal de course, pas un son du monde. Rien en
## headless (pilote audio factice) ; cue_for, lui, se teste.

enum Cue { NONE, LAP, FINAL_LAP, FINISH }

const RATE := 22050
## Notes (Hz) : do5, mi5, sol5, si5, do6.
const C5 := 523.25
const E5 := 659.25
const G5 := 783.99
const B5 := 987.77
const C6 := 1046.5

static var _player: AudioStreamPlayer
static var _streams: Dictionary = {}


## Son a jouer quand un camion vient de boucler son tour `lap` (1 = premier)
## sur `total_laps` : le dernier tour s'annonce en bouclant l'avant-dernier ;
## le tour final, c'est l'arrivee.
static func cue_for(lap: int, total_laps: int) -> Cue:
	if lap <= 0:
		return Cue.NONE
	if lap >= total_laps:
		return Cue.FINISH
	if lap == total_laps - 1:
		return Cue.FINAL_LAP
	return Cue.LAP


static func play(cue: Cue) -> void:
	if cue == Cue.NONE or DisplayServer.get_name() == "headless":
		return
	if _player == null or not is_instance_valid(_player):
		_player = AudioStreamPlayer.new()
		_player.name = "RaceSoundPlayer"
		_player.bus = &"Master"
		_player.volume_db = -4.0
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null or tree.root == null:
			return
		tree.root.add_child(_player)
	if not _streams.has(cue):
		_streams[cue] = TruckAudio._wav(build(cue))
	_player.stream = _streams[cue]
	_player.play()


## Echantillons du son (mono, RATE Hz, dans -1 .. 1).
static func build(cue: Cue) -> PackedFloat32Array:
	match cue:
		Cue.LAP:
			return _notes([[E5, 0.0, 0.16], [B5, 0.11, 0.35]], 0.5)
		Cue.FINAL_LAP:
			return _notes([[C5, 0.0, 0.16], [E5, 0.12, 0.16], [G5, 0.24, 0.16], [C6, 0.36, 0.55]], 0.95)
		Cue.FINISH:
			return _notes([[C5, 0.0, 0.18], [E5, 0.14, 0.18], [G5, 0.28, 0.18],
				[C5, 0.44, 1.1], [E5, 0.44, 1.1], [G5, 0.44, 1.1], [C6, 0.44, 1.2]], 1.7)
	return PackedFloat32Array()


## Notes [frequence, debut (s), duree (s)] : timbre de cloche douce (fondamentale
## + octave + quinte de l'octave, qui s'eteignent plus vite), attaque 4 ms,
## decroissance exponentielle ; normalise sous 0,8.
static func _notes(notes: Array, length_s: float) -> PackedFloat32Array:
	var n := roundi(RATE * length_s)
	var out := PackedFloat32Array()
	out.resize(n)
	for note: Array in notes:
		var f := float(note[0])
		var start := roundi(RATE * float(note[1]))
		var dur := float(note[2])
		var m := mini(roundi(RATE * dur), n - start)
		for i in m:
			var t := float(i) / RATE
			var env := minf(1.0, t / 0.004) * exp(-t * 4.5 / dur)
			var s := sin(TAU * f * t) + 0.35 * sin(TAU * 2.0 * f * t) * exp(-t * 6.0) \
					+ 0.15 * sin(TAU * 3.0 * f * t) * exp(-t * 10.0)
			out[start + i] += s * env
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	if peak > 0.0:
		var k := 0.8 / peak
		for i in n:
			out[i] *= k
	# fin a zero : aucun claquement a la coupure
	var fade := mini(roundi(RATE * 0.01), n)
	for i in fade:
		out[n - 1 - i] *= float(i) / fade
	return out
