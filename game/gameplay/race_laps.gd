class_name RaceLaps
extends Node

## Tours, chrono et mauvais sens (taches 2.3, 2.5), pour les camions suivis.
##
## Regle : un checkpoint ne compte que s'il est CELUI ATTENDU (ordre strict).
## Un raccourci, une marche arriere ou un checkpoint repasse sont ignores : le
## tour n'est valide qu'au passage de la ligne apres TOUS les checkpoints.
## La grille est derriere la ligne : le premier passage ouvre le tour 1, dont le
## temps part du depart (start()). Tout est derive des ticks (CLAUDE.md §7).
##
## Mauvais sens : vitesse le long de la ligne de course (gameplay-engineer.md),
## pas les checkpoints. Reapparition : jamais au-dela du prochain checkpoint
## attendu (respawn_transform), sinon un saut de mur puis un reset tricherait.

signal lap_completed(truck: Truck, lap: int, lap_ticks: int)
signal race_finished(truck: Truck, total_ticks: int)
signal wrong_way_changed(truck: Truck, wrong: bool)
## L'etat d'un concurrent vient de changer (checkpoint, tour, arrivee), une
## fois tout mis a jour : le host le recopie aux clients (NetRace).
signal racer_updated(truck: Truck)

@export var track: TrackBlockout
## Tours d'une course (2026-10-20 : 3, circuits rallonges a 4,6-4,8 km).
const DEFAULT_LAPS := 3
@export var total_laps: int = DEFAULT_LAPS
## Detection du mauvais sens (faux en arene : pas de sens de course).
@export var wrong_way_enabled: bool = true
## Mauvais sens : vitesse a contre-sens (m/s) tenue pendant ce nombre de ticks.
@export var wrong_way_speed_ms: float = 2.0
@export var wrong_way_ticks: int = 45
## Marge avant le prochain checkpoint pour une reapparition bridee (m).
@export var respawn_margin: float = 15.0


class Racer:
	var truck: Truck
	var next_cp: int = 0
	var last_cp: int = 0
	var lap: int = 0              # 0 : ligne pas encore franchie
	var lap_start_tick: int = -1
	var last_lap: int = -1
	var best_lap: int = -1
	var lap_times: PackedInt32Array = []
	var finished: bool = false
	var finish_ticks: int = -1
	var wrong_way: bool = false
	var wrong_count: int = 0
	var idx: int = -1


var start_tick: int = -1
## Course en ligne, cote client (phase 6, docs/NETCODE.md §2) : aucun tour ne
## se valide ici, ils sont recopies du host (apply_remote). Le mauvais sens
## reste calcule sur place : il ne sert qu'a l'affichage.
var mirror: bool = false
var _racers: Dictionary = {}      # Truck -> Racer


func _ready() -> void:
	if track != null:
		track.checkpoint_passed.connect(_on_checkpoint)


func watch(truck: Truck) -> void:
	if _racers.has(truck):
		return
	var r := Racer.new()
	r.truck = truck
	r.last_cp = track.checkpoint_count - 1
	_racers[truck] = r


## Signal de depart : le chrono de tous les camions part de ce tick.
func start() -> void:
	start_tick = GameClock.now()


func is_started() -> bool:
	return start_tick >= 0


func racer(truck: Truck) -> Racer:
	return _racers.get(truck)


## Tour affiche : 1 .. total_laps (le tour 1 avant meme la ligne).
func display_lap(truck: Truck) -> int:
	var r := racer(truck)
	return clampi(maxi(r.lap, 1), 1, total_laps)


## Ticks du tour en cours (ou -1 avant le depart / apres l'arrivee).
func current_lap_ticks(truck: Truck) -> int:
	var r := racer(truck)
	if start_tick < 0 or r.finished:
		return -1
	var from := r.lap_start_tick if r.lap > 0 else start_tick
	return GameClock.now() - from


func _on_checkpoint(body: Node3D, index: int) -> void:
	if mirror:
		return
	var r: Racer = _racers.get(body)
	if r == null or start_tick < 0 or r.finished or index != r.next_cp:
		return
	var now := GameClock.now()
	if index == 0:
		if r.lap == 0:
			r.lap = 1
			r.lap_start_tick = start_tick
		else:
			var lt := now - r.lap_start_tick
			r.last_lap = lt
			r.lap_times.append(lt)
			if r.best_lap < 0 or lt < r.best_lap:
				r.best_lap = lt
			lap_completed.emit(r.truck, r.lap, lt)
			if r.lap >= total_laps:
				r.finished = true
				r.finish_ticks = now - start_tick
				race_finished.emit(r.truck, r.finish_ticks)
			else:
				r.lap += 1
				r.lap_start_tick = now
	r.last_cp = index
	r.next_cp = (index + 1) % track.checkpoint_count
	racer_updated.emit(r.truck)


func _physics_process(_delta: float) -> void:
	for r: Racer in _racers.values():
		var t := r.truck
		r.idx = track.closest_sample(t.global_position, r.idx)
		var along := t.linear_velocity.dot(track.sample_forward(r.idx))
		if along < -wrong_way_speed_ms:
			r.wrong_count += 1
		elif along > wrong_way_speed_ms:
			r.wrong_count = 0
		var wrong := wrong_way_enabled and r.wrong_count >= wrong_way_ticks
		if wrong != r.wrong_way:
			r.wrong_way = wrong
			wrong_way_changed.emit(t, wrong)


## Client en ligne : etat d'un concurrent tel que le host l'a valide (ticks
## deja ramenes a l'horloge de cette machine). Emet lap_completed et
## race_finished comme une validation locale : la course et le HUD n'y voient
## pas de difference.
func apply_remote(truck: Truck, lap: int, next_cp: int, last_cp: int, lap_start_tick: int,
		last_lap: int, best_lap: int, finished: bool, finish_ticks: int) -> void:
	var r: Racer = _racers.get(truck)
	if r == null:
		return
	var lap_done := lap > r.lap and r.lap > 0
	# arrivee sur la ligne : son dernier tour vient d'etre chronometre ;
	# arrivee decidee par le mode (finish_now) : aucun tour de plus
	var line_finish := finished and not r.finished and last_lap != r.last_lap
	r.next_cp = next_cp
	r.last_cp = last_cp
	r.lap_start_tick = lap_start_tick
	r.last_lap = last_lap
	r.best_lap = best_lap
	if lap_done or line_finish:
		if last_lap >= 0:
			r.lap_times.append(last_lap)
		lap_completed.emit(truck, r.lap, last_lap)
	r.lap = lap
	if finished and not r.finished:
		r.finished = true
		r.finish_ticks = finish_ticks
		race_finished.emit(truck, finish_ticks)


## Arrivee decidee par le mode de jeu (vainqueur d'une elimination) : le
## camion finit maintenant.
func finish_now(truck: Truck) -> void:
	var r := racer(truck)
	if r == null or r.finished:
		return
	r.finished = true
	r.finish_ticks = GameClock.now() - start_tick
	race_finished.emit(truck, r.finish_ticks)
	racer_updated.emit(truck)


func racer_count() -> int:
	return _racers.size()


## Progression (m) depuis la ligne : tours faits x longueur + position dans le
## tour. Negative sur la grille (derriere la ligne). Un camion arrive passe
## devant tous ceux qui roulent, par ordre d'arrivee.
func progress(truck: Truck) -> float:
	var r := racer(truck)
	var length := track.length()
	if r.finished:
		return total_laps * length + 1.0e6 - r.finish_ticks
	var idx := r.idx if r.idx >= 0 else track.closest_sample(truck.global_position)
	var s := track.sample_s(idx)
	if r.lap == 0:
		return s - length
	# a la ligne, le tour change quand l'AVANT du camion touche sa zone, alors
	# que la position se lit au centre (2026-10-17, race_flow_test : 6 ticks de
	# classement faux a chaque passage) : tour deja compte, centre encore
	# avant la ligne, ou centre passe, tour pas encore compte
	if r.last_cp == 0 and s > length * 0.5:
		s -= length
	elif r.next_cp == 0 and s < length * 0.5:
		s += length
	return (r.lap - 1) * length + s


## Position (1 = en tete) parmi les camions suivis.
func position(truck: Truck) -> int:
	var mine := progress(truck)
	var pos := 1
	for other: Truck in _racers.keys():
		if other != truck and progress(other) > mine:
			pos += 1
	return pos


## Reapparition au plus pres, mais jamais au-dela du prochain checkpoint
## attendu : on ne gagne pas de terrain en sautant un mur.
func respawn_transform(truck: Truck) -> Transform3D:
	var r := racer(truck)
	var xf := track.get_respawn_transform(truck.global_position)
	if r == null:
		return xf
	var length := track.length()
	var s_last := track.checkpoint_s(r.last_cp)
	var s_next := track.checkpoint_s(r.next_cp)
	var s_here := track.sample_s(track.closest_sample(xf.origin))
	var ahead := fposmod(s_here - s_last, length)
	var allowed := fposmod(s_next - s_last, length) - respawn_margin
	if ahead > allowed:
		return track.frame_at(track.index_at_s(s_next - respawn_margin), 0.0, 1.0)
	return xf
