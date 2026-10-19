class_name BotInputSource
extends InputSource

## Pilote d'un bot (2026-10-19, hors ligne : solo et ecran partage). Il
## produit des InputFrame comme un joueur ; aucune force n'est appliquee de
## l'exterieur (CLAUDE.md §7). Meme methode que TrackAutopilot (tests) :
##   - direction : poursuite pure d'un point vise devant, sur la ligne de
##     course decalee de sa voie (`lane`) ;
##   - vitesse : vitesse de virage sqrt(a * R) en chaque point a venir, avec a
##     = BOT_LATERAL_G x la part du niveau ; freinage anticipe ;
## et, en plus :
##   - evitement : un camion ou une epave devant, dans sa voie, le fait changer
##     de voie du cote le plus libre ;
##   - nitro sur une longue ligne droite (moyen, dur) ;
##   - pouvoirs : missile ou laser sur un camion devant, bouclier quand ses PV
##     baissent, apres un temps de reaction propre au niveau ;
##   - bloque (moins de 5 km/h pendant STUCK_TICKS en course) : reset.
## Deterministe : aucun tirage, aucun temps reel ; ses ecarts viennent de son
## numero (voie de depart, rythme des pouvoirs).

enum Level { EASY, MEDIUM, HARD }

## Adherence laterale du camion, mesuree (baseline.json : max_lateral_g).
const BOT_LATERAL_G := 1.145
## Par niveau : part de l'adherence en virage, part de la vitesse max,
## nitro, reaction aux pouvoirs (ticks).
const GRIP := [0.6, 0.72, 0.84]
const SPEED := [0.82, 0.93, 1.0]
const BOOST := [false, true, true]
const REACTION_TICKS := [150, 70, 25]
const PLAN_DECEL := 6.0
const PLAN_DISTANCE := 160.0
const PLAN_STEP := 4.0
## Ligne droite devant (m) pour lancer la nitro.
const BOOST_STRAIGHT_M := 140.0
## Obstacle dans sa voie a moins de AVOID_AHEAD_M devant, a moins de
## AVOID_SIDE_M en travers : changement de voie de AVOID_SHIFT_M.
const AVOID_AHEAD_M := 35.0
const AVOID_SIDE_M := 3.5
const AVOID_SHIFT_M := 6.0
const LANE_RATE_M := 0.15
const STUCK_TICKS := 180
const SHIELD_HP := 55.0

var track: TrackBlockout
var truck: Truck
var level: int = Level.MEDIUM
## Voie preferee (m, > 0 a droite de la ligne de course).
var lane: float = 0.0
var index: int = -1
var target_speed: float = 0.0
var _lane_now: float = 0.0
var _lateral_accel: float = 0.0
var _slow_ticks: int = 0
var _boost_was: bool = false
## Ticks avant que le bot puisse reagir a nouveau avec un pouvoir.
var _power_wait: int = 0
var _phase: int = 0


## `number` : son rang parmi les bots (voie et rythme propres).
func setup(t: TrackBlockout, tr: Truck, bot_level: int, number: int) -> void:
	track = t
	truck = tr
	level = clampi(bot_level, Level.EASY, Level.HARD)
	_lateral_accel = BOT_LATERAL_G * float(GRIP[level]) * TruckSpec.GRAVITY
	var lanes := [-4.0, 4.0, 0.0, -8.0, 8.0]
	lane = lanes[number % lanes.size()]
	_lane_now = lane
	_phase = number * 37
	_power_wait = int(REACTION_TICKS[level]) + _phase


func poll(tick: int) -> InputFrame:
	frame.tick = tick
	if track == null or truck == null or not is_instance_valid(truck):
		return frame
	frame.reset = false
	frame.honk = false
	frame.cargo = false
	frame.power_left = false
	frame.power_right = false
	if truck.is_wrecked():
		frame.throttle = 0.0
		frame.brake = 0.0
		frame.steer = 0.0
		return frame
	index = track.closest_sample(truck.global_position, index)
	var v := truck.linear_velocity.length()
	_steer(v)
	_speed(v)
	_boost()
	_powers()
	# bloque contre un mur, coince dans une epave : reset (comme un joueur)
	_slow_ticks = _slow_ticks + 1 if v < 1.4 and RaceManager.state == RaceManagerNode.State.RACING else 0
	if _slow_ticks >= STUCK_TICKS:
		frame.reset = true
		_slow_ticks = 0
	return frame


func _steer(v: float) -> void:
	var want := lane + _avoid_shift()
	var half := track.width / 2.0 - 5.0
	want = clampf(want, -half, half)
	_lane_now = move_toward(_lane_now, want, LANE_RATE_M)
	var look := 10.0 + v * 0.45
	var j := track.sample_ahead(index, look)
	var aim := track.sample_position(j) + track.sample_right(j) * (track.line_offset(j) + _lane_now)
	var local := truck.global_transform.affine_inverse() * aim
	var ld2 := maxf(local.x * local.x + local.z * local.z, 1.0)
	var curvature := 2.0 * local.x / ld2
	var wheelbase := TruckSpec.ANCHORS[2].z - TruckSpec.ANCHORS[0].z
	var steer_deg := rad_to_deg(atan(curvature * wheelbase))
	frame.steer = clampf(steer_deg / maxf(truck.get_max_steer_deg(), 0.5), -1.0, 1.0)


func _speed(v: float) -> void:
	target_speed = truck.tuning.top_speed_kmh / 3.6 * float(SPEED[level])
	var d := 0.0
	while d <= PLAN_DISTANCE:
		var k := track.sample_ahead(index, d)
		var c := absf(track.curvature(k))
		if c > 1e-4:
			var v_corner := sqrt(_lateral_accel / c)
			target_speed = minf(target_speed, sqrt(v_corner * v_corner + 2.0 * PLAN_DECEL * d))
		d += PLAN_STEP
	var err := target_speed - v
	frame.throttle = clampf(err / 3.0, 0.0, 1.0)
	frame.brake = clampf(-err / 3.0, 0.0, 1.0)
	frame.handbrake = false


## Decalage de voie pour eviter le plus proche obstacle devant dans sa voie
## (autre camion, epave, remorque larguee) : du cote ou il y a le plus de place.
func _avoid_shift() -> float:
	var me := truck.global_position
	var fwd := -truck.global_basis.z
	var right := truck.global_basis.x
	var best := INF
	var side := 0.0
	var near := truck.get_tree().get_nodes_in_group(TruckPowers.TARGETS)
	near.append_array(truck.get_tree().get_nodes_in_group(DetachedTrailer.OBSTACLES))
	for n in near:
		var other := n as Node3D
		if other == truck:
			continue
		var d := other.global_position - me
		var ahead := d.dot(fwd)
		var across := d.dot(right)
		if ahead > 2.0 and ahead < AVOID_AHEAD_M and absf(across - (_lane_now - lane)) < AVOID_SIDE_M and ahead < best:
			best = ahead
			side = -1.0 if across > 0.0 else 1.0
	if best == INF:
		return 0.0
	# vers le centre si on est deja pres d'un bord
	var lateral := (me - track.sample_position(index)).dot(track.sample_right(index))
	if absf(lateral) > track.width / 2.0 - 10.0:
		side = -signf(lateral)
	return side * AVOID_SHIFT_M


## Un camion juste a cote de la cabine (a portee des scies), ou null.
func _beside() -> Truck:
	var inv := truck.global_transform.affine_inverse()
	for n in truck.get_tree().get_nodes_in_group(TruckPowers.TARGETS):
		var t := n as Truck
		if t == null or t == truck:
			continue
		var local := inv * t.global_position
		if absf(local.z) < PowerCatalog.SAW_HALF_LENGTH_M and absf(local.x) < TruckSpec.CAB_SIZE.x + PowerCatalog.SAW_REACH_M:
			return t
	return null


func _boost() -> void:
	var press := false
	if BOOST[level] and truck.get_boost_charge() >= 1.0 and not truck.is_boosting():
		var straight := true
		var d := 0.0
		while d <= BOOST_STRAIGHT_M:
			if absf(track.curvature(track.sample_ahead(index, d))) > 1.0 / 400.0:
				straight = false
				break
			d += 10.0
		press = straight and absf(frame.steer) < 0.2
	# front : appui d'un tick, puis relache
	frame.boost = press and not _boost_was
	_boost_was = frame.boost


func _powers() -> void:
	var powers := TruckPowers.of(truck)
	if powers == null:
		return
	if _power_wait > 0:
		_power_wait -= 1
		return
	var health := TruckHealth.of(truck)
	for k in 2:
		if powers.slots[k] < 0 or powers.cooldown[k] > 0:
			continue
		var use := false
		match powers.slots[k]:
			PowerCatalog.Id.SHIELD:
				use = health != null and health.hp < SHIELD_HP
			PowerCatalog.Id.MISSILE:
				use = powers.target_ahead() != null
			PowerCatalog.Id.LASER:
				var t := powers.target_ahead()
				use = t != null and truck.global_position.distance_to(t.global_position) < PowerCatalog.LASER_RANGE_M * 0.6
			PowerCatalog.Id.GUN:
				var t := powers.target_ahead()
				use = t != null and truck.global_position.distance_to(t.global_position) < PowerCatalog.GUN_RANGE_M * 0.6
			PowerCatalog.Id.BOOMERANG:
				var t := powers.target_ahead()
				use = t != null and truck.global_position.distance_to(t.global_position) < 40.0
			PowerCatalog.Id.SAW:
				use = _beside() != null
		if use:
			if k == 0:
				frame.power_left = true
			else:
				frame.power_right = true
			_power_wait = int(REACTION_TICKS[level])
			return
