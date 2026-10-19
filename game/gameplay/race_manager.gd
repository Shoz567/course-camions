class_name RaceManagerNode
extends Node

## Machine a etats de la course (autoload RaceManager, tache 3.1) :
##
##   LOBBY      grille de depart : camions poses, sas READY (choix de la
##              remorque), personne ne roule
##   COUNTDOWN  3, 2, 1 (COUNTDOWN_TICKS), camions immobilises
##   RACING     course ; a la premiere arrivee, les autres ont encore
##              FINISH_TIMEOUT_TICKS pour finir
##   FINISHED   resultats : tout le monde est arrive (ou parti, en ligne), ou
##              le temps limite est ecoule (les autres : « non classe »)
##
## Transitions par enter() et le signal state_changed, jamais par booleens
## eparpilles (gameplay-engineer.md). Les valeurs de State sont celles que lisent
## les tests et le reseau (NetRace) : ne pas les renumeroter.
##
## La course (LocalRace) decide QUAND passer d'un etat a l'autre (sas READY,
## fin du compte a rebours, arrivees) et ce qui l'accompagne (sons, musique,
## verrou du cargo). En ligne, seul le host fait avancer cette machine ; les
## clients recopient son etat (LocalRace.apply_net_state).
##
## Detient aussi le RandomNumberGenerator seede de la course : tout aleatoire
## de logique de jeu passe par lui (CLAUDE.md §7).
## Durees en ticks physiques (CLAUDE.md §7).

signal state_changed(state: int, previous: int)
## Un camion vient d'arriver, a la place `rank` (1 = premier).
signal truck_finished(truck: Truck, rank: int)
## Premiere arrivee : le temps limite des autres commence.
signal finish_deadline_started(deadline_tick: int)

enum State { COUNTDOWN, RACING, FINISHED, LOBBY }

const COUNTDOWN_TICKS := 180
## Apres la premiere arrivee, 30 s pour les autres : une course se termine
## toujours, meme si un camion ne finit pas (critere de sortie de la phase 3).
const FINISH_TIMEOUT_TICKS := 1800

var state: State = State.LOBBY
## Tick d'entree dans l'etat courant.
var state_tick: int = 0
## Ordre d'arrivee.
var finish_order: Array[Truck] = []
## Tick de la premiere arrivee (-1 : personne).
var first_finish_tick: int = -1
## Vrai si la course s'est terminee au temps limite (des camions non classes).
var ended_by_timeout: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Temps limite apres la premiere arrivee (FINISH_TIMEOUT_TICKS ; un test le
## raccourcit).
var finish_timeout_ticks: int = FINISH_TIMEOUT_TICKS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Nouvelle course : grille (sas READY) ou compte a rebours direct.
func begin(with_lobby: bool, tick: int, seed_value: int = 0) -> void:
	finish_order.clear()
	first_finish_tick = -1
	ended_by_timeout = false
	rng.seed = seed_value if seed_value != 0 else 0x5EED
	state = State.LOBBY if with_lobby else State.COUNTDOWN
	state_tick = tick


func enter(next: State, tick: int) -> void:
	if next == state:
		return
	var previous := state
	state = next
	state_tick = tick
	state_changed.emit(next, previous)


func ticks_in_state(tick: int) -> int:
	return tick - state_tick


## Compte a rebours fini (tick courant) ?
func countdown_done(tick: int) -> bool:
	return state == State.COUNTDOWN and ticks_in_state(tick) >= COUNTDOWN_TICKS


## Secondes affichees pendant le compte a rebours (3, 2, 1).
func countdown_seconds(tick: int) -> int:
	return maxi(3 - floori(float(ticks_in_state(tick)) / 60.0), 1)


## Arrivee d'un camion ; renvoie sa place.
func record_finish(truck: Truck, tick: int) -> int:
	if finish_order.has(truck):
		return finish_order.find(truck) + 1
	finish_order.append(truck)
	if first_finish_tick < 0:
		first_finish_tick = tick
		finish_deadline_started.emit(tick + finish_timeout_ticks)
	var rank := finish_order.size()
	truck_finished.emit(truck, rank)
	return rank


## Ticks restants avant la fin au temps limite (-1 : pas de limite en cours).
func deadline_left(tick: int) -> int:
	if state != State.RACING or first_finish_tick < 0:
		return -1
	return maxi(first_finish_tick + finish_timeout_ticks - tick, 0)


## La course doit-elle se terminer ? `racers` : camions engages, `gone` : ceux
## qui ne comptent plus (joueurs partis, en ligne).
func should_finish(tick: int, racers: int, gone: int) -> bool:
	if state != State.RACING:
		return false
	if finish_order.size() + gone >= racers:
		return true
	return deadline_left(tick) == 0


## Fin de course (resultats). `timeout` : au temps limite.
func finish(tick: int, timeout: bool = false) -> void:
	ended_by_timeout = timeout
	enter(State.FINISHED, tick)
