class_name CountdownSound
extends Node

## Sons proceduraux du compte a rebours de depart (aucun asset externe) :
## 3 bips courts (440 Hz) puis un carillon de depart (880 Hz).
## Totalement silencieux et inactif en headless (tests).

static var _player: AudioStreamPlayer
static var _stream_beep: AudioStreamWAV
static var _stream_go: AudioStreamWAV

const RATE := 22050


static func play_tick() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_ensure_init()
	if _stream_beep == null:
		_stream_beep = _build_beep(440.0, 0.12, 0.45)
	_play(_stream_beep)


static func play_go() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_ensure_init()
	if _stream_go == null:
		_stream_go = _build_beep(880.0, 0.45, 0.55)
	_play(_stream_go)


static func _ensure_init() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = AudioStreamPlayer.new()
	_player.name = "CountdownSoundPlayer"
	_player.bus = &"Master"
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.add_child(_player)


static func _play(s: AudioStreamWAV) -> void:
	if _player != null and is_instance_valid(_player) and _player.is_inside_tree():
		_player.stream = s
		_player.play()


static func _build_beep(freq: float, duration_s: float, vol: float) -> AudioStreamWAV:
	var n := roundi(RATE * duration_s)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var u := float(i) / float(n)
		phase += freq / float(RATE)
		# attaque 5 ms, decroissance exponentielle
		var env := minf(1.0, float(i) / (RATE * 0.005)) * pow(1.0 - u, 1.8)
		var v := sin(TAU * phase) * env * vol
		data.encode_s16(i * 2, clampi(roundi(v * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
