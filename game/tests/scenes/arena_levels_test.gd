extends PhysicsTest

## Niveaux des bots en arene (2026-10-21 : « les faciles ne vont pas chercher
## de heal et utilisent leurs capacites pas tres souvent ; les moyens vont
## chercher du heal, mais pas obligatoirement, et attaquent regulierement ; en
## hard, il aggro le plus possible, boost pour percuter ; le hard vraiment
## hard, le facile facile »). dev/arena.tscn, trois manches de 45 s a la
## suite : un bot moyen de reference contre 4 bots faciles, puis moyens, puis
## durs (joueur gele hors du jeu, 99 vies) :
##   A. les faciles ne partent jamais chercher une reparation ; les durs oui ;
##   B. decision de reparation (suite fixe, 40 passages sous le seuil, 5
##      bots) : jamais en facile, de 30 a 70 % en moyen, toujours en dur ;
##   C. pouvoirs : un facile au plus 1 toutes les 20 s ; les moyens plus que
##      les faciles, les durs au moins autant que les moyens ;
##   D. les durs chargent a la nitro (au moins 2 fois), jamais les autres ;
##   E. (2026-10-22) la reference est marquee joueur humain :
##      E1. degats infliges a tous par les faciles < 0,8 x ceux des moyens ;
##      E2. les durs la visent plus souvent que les moyens (part des
##          bots-ticks ou elle est leur proie) ;
##      E3. rarement plus de 2 durs sur elle (moins de 15 % des ticks).
##      Avant : PV perdus par la reference, moyens > 1,5 x faciles, durs > 1,3 x
##      moyens. Banc de 6 manches (reference et nombre de bots varies) : de 1 a
##      113 PV en facile, de 52 a 299 en dur selon la manche ; une seule manche
##      ne classe pas les niveaux, ce critere basculait au moindre changement ;
##   F. aucun ne reste coince (2,5 s sous 1,5 m/s).

const ROUND_TICKS := 2700
const START := 300

var _scene: Node3D
var _saved: Array = []
var _round := -1
var _round_t0 := 0
## Par manche : PV perdus par la reference, pouvoirs des 4 adversaires,
## departs vers une reparation, charges a la nitro.
var _taken: Array[float] = [0.0, 0.0, 0.0]
## Par manche : degats subis par tous les bots ; bots-ticks ou la reference
## est la proie, ticks ou 3 bots ou plus la visent.
var _all: Array[float] = [0.0, 0.0, 0.0]
var _aimed: Array[int] = [0, 0, 0]
var _crowd: Array[int] = [0, 0, 0]
var _ticks: Array[int] = [0, 0, 0]
var _powers: Array[int] = [0, 0, 0]
var _trips: Array[int] = [0, 0, 0]
var _rams: Array[int] = [0, 0, 0]
var _slow: Array[int] = [0, 0, 0, 0, 0]
var _stuck: Array = []


func _test_setup() -> void:
	duration_ticks = 3 * (START + ROUND_TICKS) + 10
	_saved = [GameState.requested_players, GameState.bot_count, GameState.game_mode, GameState.arena_minutes,
		GameState.bot_level]
	_next_round()


func _next_round() -> void:
	if _scene != null:
		_tally()
		remove_child(_scene)
		_scene.free()
	_round += 1
	_round_t0 = Engine.get_physics_frames()
	_slow.fill(0)
	GameState.requested_players = 1
	GameState.bot_count = 5
	GameState.bot_level = _round
	GameState.game_mode = GameStateNode.GameMode.ARENA
	GameState.arena_minutes = 0
	_scene = (load("res://dev/arena.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	_scene.set("arena_lives", 99)
	add_child(_scene)
	var players: Array = _scene.get("players")
	# le joueur hors du jeu : ni cible ni obstacle
	var p0 := (players[0] as Object).get("truck") as Truck
	p0.remove_from_group(TruckPowers.TARGETS)
	p0.freeze = true
	p0.global_position += Vector3(0, -50, 0)
	# la reference : le premier bot, toujours moyen, vu comme un joueur humain
	((players[1] as Object).get("input") as BotInputSource).level = BotInputSource.Level.MEDIUM
	((players[1] as Object).get("truck") as Truck).set_meta(BotInputSource.HUMAN_META, true)
	var k := _round
	TruckHealth.of((players[1] as Object).get("truck") as Truck).damaged.connect(func(a: float, _s: StringName) -> void:
		_taken[k] += a)
	for i in range(1, players.size()):
		TruckHealth.of((players[i] as Object).get("truck") as Truck).damaged.connect(func(a: float, _s: StringName) -> void:
			if a < 500.0:
				_all[k] += a)


## Fin de manche : ce que les adversaires ont fait.
func _tally() -> void:
	var players: Array = _scene.get("players")
	for i in range(2, players.size()):
		var b := (players[i] as Object).get("input") as BotInputSource
		_trips[_round] += b.repair_trips
		_rams[_round] += b.rams


func _test_tick(_t: int) -> void:
	var k := Engine.get_physics_frames() - _round_t0
	if k >= START + ROUND_TICKS:
		if _round < 2:
			_next_round()
		return
	if k < START:
		return
	var players: Array = _scene.get("players")
	var ref := (players[1] as Object).get("truck") as Truck
	var on_ref := 0
	for i in range(2, players.size()):
		if ((players[i] as Object).get("input") as BotInputSource).arena_prey == ref:
			on_ref += 1
	_aimed[_round] += on_ref
	_crowd[_round] += 1 if on_ref >= 3 else 0
	_ticks[_round] += 1
	for i in range(1, players.size()):
		var b := (players[i] as Object).get("input") as BotInputSource
		var tr := (players[i] as Object).get("truck") as Truck
		if i >= 2 and (b.frame.power_left or b.frame.power_right):
			_powers[_round] += 1
		if not tr.is_wrecked():
			_slow[i - 1] = _slow[i - 1] + 1 if tr.linear_velocity.length() < 1.5 else 0
			if _slow[i - 1] == 150:
				_stuck.append([_round, i, k, tr.global_position.round()])


func _test_finish() -> void:
	if _round == 2 and _scene != null:
		_tally()
	GameState.requested_players = _saved[0]
	GameState.bot_count = _saved[1]
	GameState.game_mode = _saved[2]
	GameState.arena_minutes = _saved[3]
	GameState.bot_level = _saved[4]
	check("A reparation : jamais en facile, oui en dur", _trips[0] == 0 and _trips[2] > 0, str(_trips))
	var seek := [0, 0, 0]
	for lv in 3:
		for times in 40:
			for phase in [0, 37, 74, 111, 148]:
				if BotInputSource.seeks_repair(lv, phase, times):
					seek[lv] += 1
	check("B decision de reparation : 0 %% / 30-70 %% / 100 %% (sur 200)",
		seek[0] == 0 and seek[1] >= 60 and seek[1] <= 140 and seek[2] == 200, str(seek))
	var easy_max := 4 * (ROUND_TICKS / 1200 + 1)
	check("C pouvoirs (4 bots) : facile rare, moyen regulier, dur au moins autant",
		_powers[0] <= easy_max and _powers[1] > _powers[0] and _powers[2] >= _powers[1], str(_powers))
	check("D les durs chargent a la nitro, eux seuls", _rams[0] == 0 and _rams[1] == 0 and _rams[2] >= 2, str(_rams))
	check("E1 degats infliges : facile < 0,8 x moyen", _all[0] < _all[1] * 0.8, "%s (PV perdus par la reference %s)" % [_all, _taken])
	var share := [0.0, 0.0, 0.0]
	for r in 3:
		share[r] = float(_aimed[r]) / maxf(_ticks[r] * 4.0, 1.0)
	check("E2 les durs visent le joueur plus que les moyens", share[2] > share[1], str(share))
	var crowd := float(_crowd[2]) / maxf(_ticks[2], 1.0)
	check("E3 rarement plus de 2 durs sur lui", crowd < 0.15, "%.2f" % crowd)
	check("F aucun bot coince", _stuck.is_empty(), str(_stuck))
