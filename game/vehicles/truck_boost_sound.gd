class_name TruckBoostSound
extends AudioStreamPlayer3D

## Souffle du boost (jauge du joueur ou plaque de la piste) : bruit filtre qui
## monte, plus un sifflement de turbo, genere a l'execution (aucun fichier audio
## tiers, CLAUDE.md §8). Joue a chaque signal `boosted` du camion parent.

const RATE := 22050
const DURATION_S := 0.9

## Genere une seule fois, partage par tous les camions (SPIKE A14 : rien de
## lourd a l'apparition d'un camion).
static var _shared_stream: AudioStreamWAV


func _ready() -> void:
	if _shared_stream == null:
		_shared_stream = _build_stream()
	stream = _shared_stream
	unit_size = 14.0
	max_db = 2.0
	var truck := get_parent() as Truck
	if truck != null:
		truck.boosted.connect(_on_boosted)


func _on_boosted() -> void:
	# en headless (tests), le pilote audio factice ne mixe jamais : une lecture
	# ne serait jamais liberee (fuite signalee a la sortie). Rien a entendre.
	if DisplayServer.get_name() != "headless":
		play()


static func _build_stream() -> AudioStreamWAV:
	var n := roundi(RATE * DURATION_S)
	var data := PackedByteArray()
	data.resize(n * 2)
	# bruit pseudo-aleatoire fixe (generateur congruentiel) : son identique a
	# chaque lancement, aucun aleatoire de jeu (CLAUDE.md §7)
	var lcg := 7
	var low := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / DURATION_S
		# attaque 30 ms, puis decroissance lente
		var env := minf(1.0, t / 0.03) * pow(1.0 - u, 1.5)
		# souffle : bruit passe-bas dont la coupure monte (whoosh)
		var cutoff := lerpf(0.04, 0.35, u)
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		var noise := float(lcg) / 1073741824.0 - 1.0
		low += (noise - low) * cutoff
		# turbo : sifflement qui monte de 900 a 2 400 Hz
		phase += lerpf(900.0, 2400.0, u) / RATE
		var whistle := sin(TAU * phase) * 0.25
		var v := (low * 1.6 + whistle) * env
		data.encode_s16(i * 2, clampi(roundi(v * 0.45 * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
