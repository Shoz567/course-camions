class_name TruckHorn
extends AudioStreamPlayer3D

## Klaxon du camion : trompe a deux tons, generee a l'execution (aucun fichier
## audio tiers, CLAUDE.md §8). Joue a chaque signal `honked` du camion parent,
## donc aussi pour un camion distant en reseau (le klaxon est dans l'InputFrame).

const RATE := 22050
const DURATION_S := 0.55
## Deux notes graves et dissonantes, facon trompe de semi-remorque.
const TONES: Array[float] = [155.6, 185.0]

## Genere une seule fois, partage par tous les camions : ~12 000 echantillons
## calcules en GDScript bloquaient chaque apparition de camion (et le
## rattrapage de pas physiques qui suit faussait la mesure de perf).
static var _shared_stream: AudioStreamWAV


func _ready() -> void:
	if _shared_stream == null:
		_shared_stream = _build_stream()
	stream = _shared_stream
	unit_size = 12.0
	max_db = 3.0
	var truck := get_parent() as Truck
	if truck != null:
		truck.honked.connect(_on_honked)


func _on_honked() -> void:
	play()


static func _build_stream() -> AudioStreamWAV:
	var n := roundi(RATE * DURATION_S)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		# attaque 20 ms, maintien, relache 120 ms
		var env := minf(1.0, t / 0.02) * clampf((DURATION_S - t) / 0.12, 0.0, 1.0)
		var v := 0.0
		for f in TONES:
			# onde en dents de scie adoucie : riche en harmoniques, comme une trompe
			var ph := fposmod(t * f, 1.0)
			v += (2.0 * ph - 1.0) * 0.5 + sin(TAU * f * t) * 0.5
		data.encode_s16(i * 2, clampi(roundi(v * 0.3 * env * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
