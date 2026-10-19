class_name RemoteInputSource
extends InputSource

## Joueur distant, cote host (docs/NETCODE.md §2, INPUT_SPEC.md §1) : les
## InputFrame arrivent du reseau par paquets de BATCH (push_packet), le
## camion en consomme une par tick (poll).
##
## File d'attente : chaque frame recue sert UNE fois, dans l'ordre. Ainsi un
## front (reset, klaxon, cargo), vrai sur un seul tick, n'est ni perdu ni
## repete. File vide (paquet en retard ou perdu) : la derniere consigne est
## tenue, fronts eteints. File trop longue (horloge du client un peu plus
## rapide, rafale apres un trou) : les plus anciennes sont sautees ; leurs
## fronts ET leurs boutons tenus (boost, frein a main) sont reportes sur la
## suivante : un appui court (READY, boost) n'est jamais perdu, un relacher
## arrive au plus quelques ticks plus tard.
##
## Le host ne fait confiance a rien (NETCODE.md §6) : taille du paquet
## verifiee, valeurs bornees, frames deja vues (meme tick) ignorees.

## Frames par paquet : la frame du tick et les deux precedentes (le client
## envoie un paquet par tick ; un paquet perdu ne perd aucune frame).
const BATCH := 3
## File visee : 2 frames d'avance (~33 ms) absorbent la gigue d'arrivee sans
## que le host saute ou repete un tick du client. Chaque tick saute ou repete
## decale la simulation de SON camion d'un tick par rapport a sa prediction
## (50 cm a 30 m/s) : au-dessus de la cible pendant SLOW_DROP_TICKS, une seule
## frame est sautee (rattrapage doux) ; au-dela de MAX_QUEUE (gros trou puis
## rafale), retour direct a la cible.
const TARGET_QUEUE := 2
const MAX_QUEUE := 12
const SLOW_DROP_TICKS := 30

var _queue: Array[InputFrame] = []
var _pool: Array[InputFrame] = []
## Tick (modulo 65536) de la derniere frame acceptee ; -1 : aucune.
var _last_tick: int = -1
## Frame dont l'effet est dans l'etat du camion au moment ou le host fait son
## snapshot (consommee au tick precedent) : le client y compare sa prediction
## (NETCODE.md §5). Faux si ce tick-la a tenu l'ancienne consigne (file vide) :
## l'etat ne correspond alors a aucune frame du client.
var applied_tick: int = -1
var applied_valid: bool = false
var _current_tick: int = -1
var _current_valid: bool = false
## Paquets refuses (taille), frames ignorees (deja vues), frames sautees.
var rejected_packets: int = 0
var duplicate_frames: int = 0
var dropped_frames: int = 0
## Ticks ou la file etait vide (consigne tenue).
var held_ticks: int = 0
var _above_target: int = 0


## Paquet recu du client : 1 a BATCH frames de InputFrame.SIZE octets, dans
## l'ordre des ticks. Renvoie faux si le paquet est refuse.
func push_packet(bytes: PackedByteArray) -> bool:
	var n := bytes.size() / InputFrame.SIZE
	if bytes.size() % InputFrame.SIZE != 0 or n < 1 or n > BATCH:
		rejected_packets += 1
		return false
	for i in n:
		var f := _take()
		f.read_from(bytes, i * InputFrame.SIZE)
		if _last_tick >= 0 and not _is_newer(f.tick, _last_tick):
			duplicate_frames += 1
			_pool.append(f)
			continue
		_last_tick = f.tick
		f.steer = clampf(f.steer, -1.0, 1.0)
		_queue.append(f)
	if _queue.size() > MAX_QUEUE:
		while _queue.size() > TARGET_QUEUE:
			_drop_oldest()
		_above_target = 0
	return true


## Frames en attente.
func queued() -> int:
	return _queue.size()


func poll(tick: int) -> InputFrame:
	applied_tick = _current_tick
	applied_valid = _current_valid
	# trop d'avance depuis un moment : une frame sautee, pas plus
	_above_target = _above_target + 1 if _queue.size() > TARGET_QUEUE else 0
	if _above_target >= SLOW_DROP_TICKS and _queue.size() > 1:
		_drop_oldest()
		_above_target = 0
	if _queue.is_empty():
		# rien de neuf : la consigne tenue reste, les fronts ne se repetent pas
		frame.reset = false
		frame.honk = false
		frame.cargo = false
		frame.power_left = false
		frame.power_right = false
		_current_valid = false
		held_ticks += 1
	else:
		var f: InputFrame = _queue.pop_front()
		frame.copy_from(f)
		_pool.append(f)
		_current_tick = frame.tick
		_current_valid = true
	frame.tick = tick
	return frame


## Remet la source au neutre (joueur parti, nouvelle course) : la prochaine
## frame recue est acceptee quel que soit son tick.
func clear() -> void:
	while not _queue.is_empty():
		_pool.append(_queue.pop_front())
	frame.clear()
	_last_tick = -1
	_current_valid = false
	applied_valid = false
	_above_target = 0


func _drop_oldest() -> void:
	var old: InputFrame = _queue.pop_front()
	var next: InputFrame = _queue[0]
	next.reset = next.reset or old.reset
	next.honk = next.honk or old.honk
	next.cargo = next.cargo or old.cargo
	next.power_left = next.power_left or old.power_left
	next.power_right = next.power_right or old.power_right
	next.boost = next.boost or old.boost
	next.handbrake = next.handbrake or old.handbrake
	dropped_frames += 1
	_pool.append(old)


func _take() -> InputFrame:
	return _pool.pop_back() if not _pool.is_empty() else InputFrame.new()


## `a` est-il apres `b` (ticks modulo 65536, fenetre d'une demi-boucle) ?
static func _is_newer(a: int, b: int) -> bool:
	var d := posmod(a - b, 65536)
	return d != 0 and d < 32768
