class_name MenuSound
extends Node

## Sons proceduraux du menu (aucun asset externe, CLAUDE.md §8) :
## bips de navigation, validation arcade, et ouverture / fermeture.
## Totalement silencieux et inactif en headless (tests).

static var _player: AudioStreamPlayer
static var _stream_select: AudioStreamWAV
static var _stream_confirm: AudioStreamWAV
static var _stream_toggle: AudioStreamWAV

const RATE := 22050


static func play_select() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_ensure_init()
	if _stream_select == null:
		_stream_select = _build_tone(580.0, 880.0, 0.055, 0.35)
	_play(_stream_select)


static func play_confirm() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_ensure_init()
	if _stream_confirm == null:
		_stream_confirm = _build_triad(523.25, 659.25, 783.99, 0.16, 0.4)
	_play(_stream_confirm)


static func play_toggle() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_ensure_init()
	if _stream_toggle == null:
		_stream_toggle = _build_tone(440.0, 330.0, 0.045, 0.3)
	_play(_stream_toggle)


static func _ensure_init() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = AudioStreamPlayer.new()
	_player.name = "MenuSoundPlayer"
	_player.bus = SoundMix.EFFECTS
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		# differe : au _ready du menu, la racine est occupee a ajouter la scene
		# (add_child direct refuse, et plus aucun son ne sortait ensuite)
		tree.root.add_child.call_deferred(_player)


static func _play(s: AudioStreamWAV) -> void:
	if _player != null and is_instance_valid(_player) and _player.is_inside_tree():
		_player.stream = s
		_player.play()


## Bip glisse de `f1` a `f2` Hz (HUD de course : touche, cible).
static func build_tone(f1: float, f2: float, duration_s: float, vol: float) -> AudioStreamWAV:
	return _build_tone(f1, f2, duration_s, vol)


static func _build_tone(f1: float, f2: float, duration_s: float, vol: float) -> AudioStreamWAV:
	var n := roundi(RATE * duration_s)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var u := float(i) / float(n)
		var freq := lerpf(f1, f2, u)
		phase += freq / float(RATE)
		var env := sin(u * PI) * (1.0 - u * 0.4)
		var v := sin(TAU * phase) * env * vol
		data.encode_s16(i * 2, clampi(roundi(v * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


static func _build_triad(f1: float, f2: float, f3: float, duration_s: float, vol: float) -> AudioStreamWAV:
	var n := roundi(RATE * duration_s)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph1 := 0.0
	var ph2 := 0.0
	var ph3 := 0.0
	for i in n:
		var u := float(i) / float(n)
		ph1 += f1 / float(RATE)
		ph2 += f2 / float(RATE)
		ph3 += f3 / float(RATE)
		var env := (1.0 - pow(u, 0.7)) * minf(1.0, float(i) / (RATE * 0.015))
		var v := (sin(TAU * ph1) * 0.45 + sin(TAU * ph2) * 0.35 + sin(TAU * ph3) * 0.2) * env * vol
		data.encode_s16(i * 2, clampi(roundi(v * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
