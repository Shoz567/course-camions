class_name BotInputSource
extends InputSource

## Pilote d'un bot (2026-10-19, hors ligne : solo et ecran partage). Il
## produit des InputFrame comme un joueur ; aucune force n'est appliquee de
## l'exterieur (CLAUDE.md Â§7).
## Refait le 2026-10-20 (Â« meme en dur ils sont faciles a battre, ils prennent
## des trajectoires pas optimales, parfois ils se rentrent dedans Â») :
##   - trajectoire : ligne de course calculee (RacingLine : virages ouverts,
##     corde, sortie large), melangee a la ligne centrale selon le niveau ;
##   - vitesse : profil de la ligne (vitesse de virage et freinage anticipe a
##     l'adherence et au freinage du niveau), lu un peu devant le camion ;
##   - trafic : chaque camion, epave, remorque larguee ou baril est repere le
##     long de la piste (distance, ecart lateral, vitesse). Plus lent devant :
##     depassement du cote le plus libre et proche de la ligne, choix garde
##     jusqu'a l'avoir passe ; pas de place : il se cale derriere a sa
##     vitesse. Un camion a cote : il garde ses distances au lieu de serrer ;
##   - depart : la voie de grille s'efface sur les premiers metres, pour ne
##     pas tous se rabattre ensemble au 1er virage ;
##   - nitro quand rien ne demande de freiner devant (moyen, dur) ;
## Repris le 2026-10-20 (« il ne coupe pas les virages ; il fonce dans les
## barils et les remorques larguees ») : ligne la plus rapide (RacingLine,
## qui contourne aussi les barils) ; profil sans plafond (il garde l'elan
## d'un pad ou de la nitro, ne freine que pour un virage) ; chaque obstacle a
## son gabarit (remorque en travers, zone d'un baril), juge la ou sa ligne
## passera, et il ralentit s'il n'a plus le temps de se decaler ;
##   - pouvoirs : missile ou laser sur un camion devant, bouclier quand ses PV
##     baissent, apres un temps de reaction propre au niveau ;
## Tactique (2026-10-20 : « larguer la remorque au bon moment : juste avant un
## virage, avec un poursuivant colle derriere ; sortir le bouclier quand un
## missile arrive ») :
##   - bouclier quand un missile ou un boomerang qui le vise arrive a moins de
##     SHIELD_WARN_M, ou qu'un laser le touche (moyen, dur ; sans attendre) ;
##   - largage quand un camion le suit dans sa voie, juste derriere sa
##     remorque (moyen) ; en dur, seulement si un virage arrive (il devra
##     freiner, l'autre aussi : il ne l'evitera pas). Jamais en facile.
##   - bloque (moins de 5 km/h pendant STUCK_TICKS en course) : reset.
## Raccourcis (2026-10-21 : « améliore les bots pour qu'ils prennent les short
## cut ») : a SHORTCUT_COMMIT_M de l'entree d'un raccourci, il decide de le
## prendre (part SHORTCUT_TAKE des passages selon le niveau, suite fixe) ;
## il se decale alors vers lui, son plan de freinage saute le virage du
## detour, il vise le long du raccourci, y contourne barils, flaques et
## camions, et reprend sa ligne a la sortie. Remis en piste sur un
## raccourci, il le suit jusqu'au bout.
## Deterministe : aucun tirage, aucun temps reel ; ses ecarts viennent de son
## numero (voie de depart, rythme des pouvoirs).

enum Level { EASY, MEDIUM, HARD }

## Adherence laterale du camion, mesuree (baseline.json : max_lateral_g), et
## freinage (100 -> 0 en 38,7 m : ~10 m/s2).
const BOT_LATERAL_G := 1.145
const BOT_BRAKE := 9.9
## Par niveau : part de l'adherence en virage, part de la vitesse max, part
## du freinage, part de la ligne de course (le reste : ligne centrale),
## nitro, reaction aux pouvoirs (ticks).
const GRIP := [0.6, 0.75, 0.95]
const SPEED := [0.84, 0.94, 1.0]
const BRAKE := [0.5, 0.65, 0.95]
const LINE := [0.35, 0.75, 1.0]
const BOOST := [false, true, true]
const REACTION_TICKS := [150, 70, 25]
## Bouclier : distance (m) d'un projectile qui le vise a laquelle il le sort
## (0 : jamais).
const SHIELD_WARN_M := [0.0, 25.0, 40.0]
## Largage : poursuivant dans la voie (ecart lateral < DROP_LATERAL_M), son
## nez a moins de DROP_BEHIND_M derriere l'arriere de la remorque ; en dur,
## un virage dans les DROP_CORNER_S secondes (rayon sous DROP_CORNER_RADIUS_M).
const DROP := [false, true, true]
const DROP_BEHIND_M := 18.0
const DROP_LATERAL_M := 3.5
const DROP_CORNER_S := [0.0, 0.0, 2.0]
const DROP_CORNER_RADIUS_M := 150.0
## Lecture du profil de vitesse devant le camion (s de reaction), pas et
## portee du plan de freinage (m).
const SPEED_LEAD_S := 0.25
const PLAN_STEP_M := 4.0
const PLAN_MAX_M := 220.0
## Nitro : rien a freiner sur BOOST_CLEAR_M devant (le profil y reste
## au-dessus de la vitesse actuelle).
const BOOST_CLEAR_M := 70.0
## Gabarit d'un ensemble le long de la piste : nez a +4 m du centre de la
## tete, arriere de remorque a -16 m ; demi-largeur 1,8 m.
const NOSE_M := 4.0
const TAIL_M := 16.0
const HALF_WIDTH_M := 1.8
## Trafic : regarde jusqu'a LOOK_AHEAD_M devant ; ecart lateral voulu entre
## deux ensembles (au passage) ; distance de suivi quand il n'y a pas la
## place de doubler.
const LOOK_AHEAD_M := 70.0
const PASS_GAP_M := 5.5
## Marge laterale entre deux gabarits au passage (m) ; acceleration laterale
## d'un decalage (m/s2) et reaction (s) : il faut sqrt(4 d / a) + reaction pour
## se decaler de d. Portee : au moins LOOK_AHEAD_S secondes devant.
const CLEAR_M := 1.2
const SHIFT_ACCEL := 5.0
const SHIFT_REACT_S := 0.35
const LOOK_AHEAD_S := 3.0
## En deca de NEAR_S secondes, un obstacle dans son couloir actuel compte
## aussi (meme si la ligne s'en ecarte).
const NEAR_S := 0.6
const FOLLOW_GAP_M := 6.0
## Vitesse au pas pour contourner un obstacle arrete.
const CREEP_MS := 4.0
## En travers (cap a plus de ~50 deg de la piste) et lent : il repart en
## braquant, sans plafond du trafic.
const ASTRAY_DOT := 0.65
const ASTRAY_MS := 8.0
## Vitesse de changement d'ecart lateral (m par tick).
const LANE_RATE_M := 0.2
## Voie de grille effacee sur ces premiers metres.
const START_BLEND_M := 250.0
## Ecart (m) vers l'exterieur, direction en butee, qui fait lever le pied.
const SATURATION_DRIFT_M := 1.5
const STUCK_TICKS := 180
## Plafond du profil de vitesse (m/s) : au-dela de toute vitesse atteinte.
const PROFILE_CEILING_MS := 90.0
const SHIELD_HP := 55.0
## Raccourcis : part des passages ou il le prend, par niveau ; distance de
## l'entree ou il decide (m) ; marge aux murs du raccourci et pas des places
## essayees en travers (m).
const SHORTCUT_TAKE := [0.4, 0.75, 1.0]
const SHORTCUT_COMMIT_M := 460.0
const SHORTCUT_EDGE_M := 4.5
const SHORTCUT_STEP_M := 0.5
## Vers et sur le raccourci : vitesse de changement d'ecart (part de
## LANE_RATE_M : un decalage brusque, en virage ou a plus de 40 m/s, le
## jetait contre le mur) ; part de l'adherence gardee a l'approche (il se
## decale en virage) ; cout d'une
## place dans une flaque (m d'ecart equivalents : il l'evite si c'est peu
## couteux, la traverse sinon).
const SHORTCUT_LANE_RATE := 0.5
## Ligne d'approche : longueurs essayees pour quitter la ligne de course (m,
## la moins courbee est gardee, par raccourci) ; elle suit l'axe du raccourci sur les derniers APPROACH_ALIGN_M ;
## demi-pas de la mesure de sa courbure (m).
const APPROACH_BLEND_MIN_M := 60.0
const APPROACH_BLEND_MAX_M := 380.0
const APPROACH_ALIGN_M := 30.0
const APPROACH_CURV_M := 10.0
## Ligne de sortie : longueurs essayees pour regagner la ligne de course (m).
const EXIT_MIN_M := 60.0
const EXIT_MAX_M := 300.0
const SHORTCUT_GRIP := 0.75
## Virages du raccourci lui-meme (courbure exacte de son axe) : marge moindre.
const BRANCH_CURVE_GRIP := 0.75
## Sur le raccourci, il se cale du cote interieur du virage qui vient (lu
## BRANCH_INSIDE_S devant), jusqu'a BRANCH_INSIDE_PART de la place en travers,
## pleinement sous un rayon de BRANCH_INSIDE_R_M : sa remorque, deportee vers
## l'exterieur, garde de la place avant le mur.
const BRANCH_INSIDE_S := 1.0
const BRANCH_INSIDE_PART := 0.6
const BRANCH_INSIDE_R_M := 120.0
## Raccourci (2026-10-21) : il compte sur ce freinage (part du sien) avant ses
## virages (il freine en courbe, la remorque chasse), et ne prend la nitro que
## si rien ne demande de ralentir sur BRANCH_BOOST_CLEAR_M.
const BRANCH_BRAKE := 0.6
## Saut d'un raccourci : il ne le prend que si sa vitesse max depasse d'autant
## la vitesse conseillee (TrackBlockout.branch_jump_min_kmh).
const JUMP_SPEED_MARGIN := 1.1
const BRANCH_BOOST_CLEAR_M := 250.0
const PUDDLE_COST_M := 8.0
## Nombre d'or : passages successifs repartis regulierement dans [0, 1).
const GOLDEN := 0.618034

var track: TrackBlockout
var truck: Truck
var level: int = Level.MEDIUM
## Voie de depart (m, > 0 a droite de la ligne de course).
var lane: float = 0.0
var index: int = -1
var target_speed: float = 0.0
## Ce qui le gene devant (trafic), ou null.
var blocked_by: Node3D = null
var line: RacingLine
var _profile: PackedFloat32Array = []
## Acceleration laterale du niveau (m/s2).
var _grip: float = 0.0
var _cargo: TruckCargo
## Arene (2026-10-20) : il chasse le camion le plus proche au lieu de suivre
## la piste (ses pouvoirs et largages restent).
var arena: bool = false
## Distance au bord de l'arene (m) ou il revient vers le milieu.
const ARENA_EDGE_M := 22.0
## Arene (2026-10-21) : sous ARENA_STUCK_MS pendant ARENA_STUCK_TICKS gaz a
## fond (deux bots nez a nez se poussaient sans fin), il recule
## ARENA_BACK_TICKS en braquant (contre un bord, deja tourne vers le milieu :
## il repart tout droit, reculer le collait au mur), puis laisse cette proie
## ARENA_IGNORE_TICKS.
const ARENA_STUCK_MS := 2.5
const ARENA_STUCK_TICKS := 45
const ARENA_BACK_TICKS := 70
const ARENA_IGNORE_TICKS := 90
var _arena_stuck: int = 0
var _arena_back: int = 0
var _arena_out: bool = false
var _arena_shunned: Truck = null
var _arena_shun_left: int = 0
## Largages faits (tests).
var drops: int = 0
## Faux : il ignore les raccourcis (tests, comparaison).
var shortcuts: bool = true
## Raccourcis pris (tests).
var shortcuts_taken: int = 0
## Raccourci choisi (approche ou dessus), -1 sinon ; distance le long de son
## chemin jusqu'a son entree (m, negative dessus) ; dernier raccourci juge a
## l'approche ; passages juges.
var _branch: int = -1
var _to_entry: float = INF
var _branch_seen: int = -1
var _passes: int = 0
## Ecart de la ligne d'approche au point vise, au tick precedent (INF : aucun).
var _approach_was: float = INF
## Par raccourci : longueur (m) sur laquelle sa ligne d'approche quitte la
## ligne de course.
var _blend_m: PackedFloat32Array = []
## Raccourci qu'il vient de quitter par sa sortie (il regagne sa ligne), -1 ;
## par raccourci, longueur de sa ligne de sortie (m).
var _exit: int = -1
var _exit_m: PackedFloat32Array = []
## Vitesse max du niveau (m/s) : au-dessus, il ne remet pas les gaz.
var _top: float = 0.0
var _lat_now: float = 0.0
var _pass_side: float = 0.0
var _pass_target: Node3D = null
var _driven_m: float = 0.0
var _hints: Dictionary = {}
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
	var lanes := [-4.0, 4.0, 0.0, -8.0, 8.0]
	lane = lanes[number % lanes.size()]
	_phase = number * 37
	_power_wait = int(REACTION_TICKS[level]) + _phase
	line = RacingLine.of(t)
	_top = tr.tuning.top_speed_kmh / 3.6 * float(SPEED[level])
	# profil sans plafond de vitesse : il ne freine que pour un virage (au-dessus
	# de sa vitesse max, apres un pad ou la nitro, il garde son elan)
	_grip = BOT_LATERAL_G * float(GRIP[level]) * TruckSpec.GRAVITY
	_profile = line.speed_profile(_grip,
		BOT_BRAKE * float(BRAKE[level]), PROFILE_CEILING_MS)
	index = t.closest_sample(tr.global_position)
	_lat_now = _lateral_of(tr.global_position, index)
	_blend_m.clear()
	_exit_m.clear()
	for k in t.branch_count():
		_blend_m.append(_best_blend(k))
		_exit_m.append(_best_exit(k))
	_cargo = tr.get_node_or_null(^"Cargo") as TruckCargo


func poll(tick: int) -> InputFrame:
	frame.tick = tick
	if track == null or truck == null or not is_instance_valid(truck):
		return frame
	frame.reset = false
	frame.honk = false
	frame.cargo = false
	frame.power_left = false
	frame.power_right = false
	frame.handbrake = false
	if truck.is_wrecked():
		frame.throttle = 0.0
		frame.brake = 0.0
		frame.steer = 0.0
		return frame
	index = _sample_of(truck.global_position, index)
	var v := truck.linear_velocity.length()
	if RaceManager.state == RaceManagerNode.State.RACING:
		_driven_m += v / Engine.physics_ticks_per_second
	if arena:
		_arena_drive(v)
	else:
		_update_branch()
		var traffic := _branch_traffic(v) if _on_branch() else _traffic(v)
		_steer(v, float(traffic["lateral"]))
		_speed(v, float(traffic["cap"]))
		_boost(bool(traffic["clear"]))
	_powers()
	_drop_tactic(v)
	# bloque contre un mur, coince dans une epave : reset (comme un joueur)
	_slow_ticks = _slow_ticks + 1 if v < 1.4 and RaceManager.state == RaceManagerNode.State.RACING else 0
	if _slow_ticks >= STUCK_TICKS:
		frame.reset = true
		_slow_ticks = 0
	return frame


## Echantillon le plus proche de `p`, cherche autour de `hint` ; partout si
## le resultat est loin (remise en piste, premier appel).
func _sample_of(p: Vector3, hint: int) -> int:
	var i := track.closest_sample(p, hint)
	if hint < 0 or track.sample_position(i).distance_to(p) > track.width * 0.75:
		i = track.closest_sample(p)
	return i


## Ecart lateral de la ligne du niveau a l'echantillon `i`.
func _line_at(i: int) -> float:
	var w := float(LINE[level])
	return lerpf(track.line_offset(i), line.offset[posmod(i, line.offset.size())], w)


func _lateral_of(p: Vector3, i: int) -> float:
	return (p - track.sample_position(i)).dot(track.sample_right(i))


## Distance le long de la piste de `a` a `b` (echantillons), dans [-L/2, L/2].
func _s_gap(from_i: int, to_i: int) -> float:
	var d := track.sample_s(to_i) - track.sample_s(from_i)
	var l := track.length()
	if d > l / 2.0:
		d -= l
	elif d < -l / 2.0:
		d += l
	return d


## Ce qui roule ou traine autour : ecart lateral voulu (absolu, m) et vitesse
## plafond (m/s, INF si rien), et si la voie est libre devant (nitro).
## Chaque obstacle a son gabarit le long de la piste (avant, arriere) et en
## travers (demi-largeur) : une remorque larguee en travers barre 7 m, un baril
## sa zone de declenchement. Passage : decale de nos deux demi-largeurs plus
## CLEAR_M ; il freine s'il n'a plus le temps de se decaler (SHIFT_ACCEL), et
## garde son cote jusqu'a ce que sa remorque ait passe l'obstacle.
func _traffic(v: float) -> Dictionary:
	var me_lat := _lateral_of(truck.global_position, index)
	var start := clampf(1.0 - _driven_m / START_BLEND_M, 0.0, 1.0)
	var lead := track.sample_ahead(index, 10.0 + v * 0.4)
	var want := _line_at(lead) + lane * start
	# vers un raccourci : sa ligne d'approche (au point vise par la direction)
	if _branch >= 0:
		want = _approach_lat(_branch, track.sample_ahead(index, 8.0 + v * 0.38))
	elif _exit >= 0:
		want = _exit_lat(_exit, track.sample_ahead(index, 8.0 + v * 0.38))
	var cap := INF
	var clear := true
	var half := track.width / 2.0 - 4.0
	var my_v := truck.linear_velocity.dot(track.sample_forward(index))
	var look := maxf(LOOK_AHEAD_M, v * LOOK_AHEAD_S)
	var blocker: Node3D = null
	var blocker_room := INF
	var blocker_lat := 0.0
	var blocker_v := 0.0
	var blocker_reach := 0.0
	var blocker_path := 0.0
	var holding := false
	var hold_lat := 0.0
	var hold_reach := 0.0
	var push := 0.0
	for o: Dictionary in _others():
		var node := o["node"] as Node3D
		var at: Vector3 = o["at"]
		# echantillon de chacun, suivi d'un tick a l'autre (recherche locale)
		var oi := _sample_of(at, int(_hints.get(node, -1)))
		_hints[node] = oi
		var gap := _s_gap(index, oi)
		var lat := _lateral_of(at, oi)
		var ov := float(o["v"])
		var front := float(o["front"])
		var back := float(o["back"])
		var reach := float(o["half"]) + HALF_WIDTH_M + CLEAR_M
		# a cote (son gabarit chevauche le mien le long de la piste) : garder
		# ses distances ; l'obstacle qu'on double : garder son cote
		if gap - back < NOSE_M + 1.0 and gap + front > -TAIL_M:
			if node == _pass_target and _pass_side != 0.0:
				holding = true
				hold_lat = lat
				hold_reach = reach
			var dl := me_lat - lat
			if absf(dl) < reach:
				push += signf(dl if absf(dl) > 0.1 else -lat) * (reach - absf(dl))
			continue
		var room := gap - back - NOSE_M
		if room <= -1.0 or room > look:
			continue
		# sur ma route : la ou ma ligne passera a sa hauteur, ou dans mon
		# couloir actuel s'il est tout pres (la ligne s'ecarte d'elle-meme d'un
		# baril encore loin)
		var path_lat := _line_at(oi) + lane * start
		if _branch >= 0:
			path_lat = _approach_lat(_branch, oi)
		elif _exit >= 0:
			path_lat = _exit_lat(_exit, oi)
		var near := room < NEAR_S * v + 5.0
		if absf(lat - path_lat) >= reach and (not near or absf(lat - me_lat) >= reach):
			continue
		if room < 40.0:
			clear = false
		# plus lent que moi (ou arrete) et a portee de rattrapage
		var closing := my_v - ov
		if closing <= 0.5 and room > FOLLOW_GAP_M * 2.0:
			continue
		if room < blocker_room:
			blocker_room = room
			blocker = node
			blocker_lat = lat
			blocker_v = ov
			blocker_reach = reach
			blocker_path = path_lat
	blocked_by = blocker
	if blocker != null:
		if blocker != _pass_target:
			_pass_target = blocker
			_pass_side = _choose_side(blocker_lat, blocker_reach, blocker_path, half)
		if _pass_side != 0.0:
			var side_lat := blocker_lat + _pass_side * (blocker_reach + 0.5)
			if absf(side_lat) <= half:
				# deja de ce cote, plus loin que la ligne : il y reste
				if (want - side_lat) * _pass_side < 0.0:
					want = side_lat
			else:
				_pass_side = 0.0
		# temps pour se decaler (aller-retour du braquage : y = a t^2 / 4) ;
		# s'il arrive trop vite pour l'avoir, il ralentit
		var closing := maxf(my_v - maxf(blocker_v, 0.0), 0.1)
		if _pass_side != 0.0:
			var shift := maxf(0.0, (blocker_lat + _pass_side * blocker_reach - me_lat) * _pass_side)
			var t_need := sqrt(4.0 * shift / SHIFT_ACCEL) + SHIFT_REACT_S
			if blocker_room < closing * t_need:
				var ok := maxf(blocker_v, 0.0) + maxf(blocker_room, 0.0) / t_need
				# un obstacle arrete se contourne au pas, jamais d'arret derriere
				cap = minf(cap, maxf(ok, CREEP_MS))
		elif blocker_room < FOLLOW_GAP_M + closing * 1.5:
			cap = minf(cap, maxf(blocker_v, 0.0) + maxf(0.0, blocker_room - FOLLOW_GAP_M) * 0.35)
	elif holding:
		var keep := hold_lat + _pass_side * (hold_reach + 0.5)
		if (want - keep) * _pass_side < 0.0:
			want = keep
	else:
		_pass_target = null
		_pass_side = 0.0
	want += clampf(push, -PASS_GAP_M, PASS_GAP_M)
	return {"lateral": clampf(want, -half, half), "cap": cap, "clear": clear}


## Cote du depassement : celui qui garde la place dans la chaussee et colle le
## mieux a la ligne visee (-1 gauche, +1 droite, 0 aucun).
func _choose_side(other_lat: float, reach: float, want: float, half: float) -> float:
	var best := 0.0
	var best_cost := INF
	for side: float in [-1.0, 1.0]:
		var lat := other_lat + side * (reach + 0.5)
		if absf(lat) > half:
			continue
		var cost := absf(lat - want)
		if cost < best_cost:
			best_cost = cost
			best = side
	return best


## Camions (pas soi), epaves, remorques larguees, barils : noeud, centre,
## vitesse, gabarit le long de la piste (avant et arriere du centre) et demi-
## largeur en travers (m).
func _others() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tree := truck.get_tree()
	for n in tree.get_nodes_in_group(TruckPowers.TARGETS):
		var t := n as Truck
		# epave : cache, sans collision (sa carcasse est un obstacle a part)
		if t == null or t == truck or not t.is_inside_tree() or t.is_wrecked():
			continue
		var vel := t.linear_velocity.length()
		var tail := NOSE_M if t.is_trailer_detached() else TAIL_M
		out.append({"node": t, "at": t.global_position, "v": vel, "front": NOSE_M, "back": tail, "half": HALF_WIDTH_M})
	for n in tree.get_nodes_in_group(DetachedTrailer.OBSTACLES):
		var d := n as DetachedTrailer
		if d == null or not d.is_inside_tree():
			continue
		# boite orientee projetee sur la piste
		var xf := d.global_transform
		var c := xf * d.box_center
		var i := _sample_of(c, int(_hints.get(d, -1)))
		var f := track.sample_forward(i)
		var r := track.sample_right(i)
		var hx := d.box_size.x / 2.0
		var hz := d.box_size.z / 2.0
		var along := absf(f.dot(xf.basis.x)) * hx + absf(f.dot(xf.basis.z)) * hz
		var across := absf(r.dot(xf.basis.x)) * hx + absf(r.dot(xf.basis.z)) * hz
		out.append({"node": d, "at": c, "v": maxf(0.0, d.linear_velocity.dot(f)), "front": along, "back": along,
			"half": across})
	var barrel_r := ExplosiveBarrel.BARREL_RADIUS + 1.0
	for k in track.barrel_count():
		var barrel := track.barrel_node(k)
		if barrel != null and is_instance_valid(barrel) and barrel.is_inside_tree() and barrel.visible 				and not barrel.exploded_state:
			out.append({"node": barrel, "at": barrel.global_position, "v": 0.0, "front": barrel_r, "back": barrel_r,
				"half": barrel_r})
	return out


func _steer(v: float, want: float) -> void:
	var look := 8.0 + v * 0.38
	if (_branch >= 0 and not _on_branch()) or _exit >= 0:
		# sa ligne d'approche (ou de sortie) glisse sous lui : il la suit, seul
		# son ecart a elle va a la vitesse limitee
		var j := track.sample_ahead(index, look)
		var a := _approach_lat(_branch, j) if _branch >= 0 else _exit_lat(_exit, j)
		if is_finite(_approach_was):
			_lat_now += a - _approach_was
		_approach_was = a
	else:
		_approach_was = INF
	_lat_now = move_toward(_lat_now, want, LANE_RATE_M * (SHORTCUT_LANE_RATE if _branch >= 0 or _exit >= 0 else 1.0))
	var local := truck.global_transform.affine_inverse() * _aim(look)
	var ld2 := maxf(local.x * local.x + local.z * local.z, 1.0)
	var curv := 2.0 * local.x / ld2
	var wheelbase := TruckSpec.ANCHORS[2].z - TruckSpec.ANCHORS[0].z
	var steer_deg := rad_to_deg(atan(curv * wheelbase))
	frame.steer = clampf(steer_deg / maxf(truck.get_max_steer_deg(), 0.5), -1.0, 1.0)


func _speed(v: float, cap: float) -> void:
	# vitesse qui laisse freiner a temps pour tout ce qui vient, lue un peu
	# devant (reaction) : sqrt(p(d)^2 + 2 a d). Au-dessus de sa vitesse max
	# (nitro, pad de boost), il garde son elan tant qu'aucun virage ne demande
	# de ralentir (avant : il freinait aussitot et perdait chaque boost)
	var brake := BOT_BRAKE * float(BRAKE[level]) * (BRANCH_BRAKE if _branch >= 0 else 1.0)
	var lead := v * SPEED_LEAD_S
	var reach := minf(v * v / (2.0 * brake) + PLAN_STEP_M, PLAN_MAX_M)
	target_speed = INF
	var d := 0.0
	while d <= reach:
		var p := _profile_at(lead + d)
		target_speed = minf(target_speed, sqrt(p * p + 2.0 * brake * d))
		d += PLAN_STEP_M
	# en travers apres un accrochage : repartir, quoi qu'il y ait devant
	var ahead := _branch_dir(_branch, track.branch_u(_branch, truck.global_position)) if _on_branch() 			else track.sample_forward(index)
	var astray := (-truck.global_basis.z).dot(ahead) < ASTRAY_DOT and v < ASTRAY_MS
	target_speed = minf(target_speed, ASTRAY_MS if astray else cap)
	# garde-fou : direction en butee et le camion s'ecarte de sa ligne vers
	# l'exterieur (il ne tient pas le virage) : il leve le pied
	var drift := (_my_lat() - _lat_now) * signf(frame.steer)
	if absf(frame.steer) > 0.97 and drift < -SATURATION_DRIFT_M:
		target_speed = minf(target_speed, v * 0.92)
	var err := target_speed - v
	frame.throttle = clampf(err / 1.5, 0.0, 1.0)
	frame.brake = clampf(-err / 2.0, 0.0, 1.0)
	# au-dessus de sa vitesse max (niveau) sans virage devant : roue libre
	if float(SPEED[level]) < 1.0 and v > _top and frame.brake == 0.0:
		frame.throttle = 0.0 if not truck.is_boosting() else frame.throttle


func _boost(clear: bool) -> void:
	var press := false
	if BOOST[level] and clear and truck.get_boost_charge() >= 1.0 and not truck.is_boosting():
		# rien a freiner devant : en sortie de virage comme en ligne droite
		var v := truck.linear_velocity.length()
		var ok := true
		var d := 0.0
		while d <= (BRANCH_BOOST_CLEAR_M if _branch >= 0 else BOOST_CLEAR_M):
			if _profile_at(d) < v + 1.0:
				ok = false
				break
			d += 8.0
		press = ok and absf(frame.steer) < 0.25
	# front : appui d'un tick, puis relache
	frame.boost = press and not _boost_was
	_boost_was = frame.boost


# --- raccourcis ----------------------------------------------------------------

## Prend-il le raccourci a ce passage ? Part SHORTCUT_TAKE[niveau] des
## passages, decalee par son numero : deux bots du meme niveau ne font pas les
## memes choix (suite fixe, aucun tirage).
static func takes_shortcut(bot_level: int, phase: int, pass_index: int) -> bool:
	return fposmod(phase * 0.37 + pass_index * GOLDEN, 1.0) < float(SHORTCUT_TAKE[bot_level])


## Le raccourci k n'a pas de saut, ou il va assez vite pour le franchir.
func _can_jump(k: int) -> bool:
	return _top * 3.6 >= track.branch_jump_min_kmh(k) * JUMP_SPEED_MARGIN


## Sur le raccourci choisi (passe son entree).
func _on_branch() -> bool:
	return _branch >= 0 and _to_entry <= 0.0


## Raccourci choisi : adopte s'il roule dessus (hors de la chaussee de la
## piste), quitte a la sortie ou s'il en est sorti, choisi a l'approche ;
## distance a son entree.
func _update_branch() -> void:
	_to_entry = INF
	if not shortcuts or track.branch_count() == 0:
		_branch = -1
		return
	var p := truck.global_position
	if _exit >= 0:
		var past := _s_gap(track.index_at_s(track.branch_span(_exit).y), index)
		if past > _exit_m[_exit] + 10.0 or past < -50.0:
			_exit = -1
	var on := track.on_branch(p, 1.0)
	# l'echantillon suivi est loin : il roule sur un raccourci (remis en piste
	# dessus, ou pousse)
	if on >= 0 and track.sample_position(index).distance_to(p) > track.width / 2.0 + 2.0:
		if _branch != on:
			_branch = on
			_lat_now = track.branch_lateral(on) + track.branch_lateral_of(on, p)
	if _branch >= 0:
		var u := track.branch_u(_branch, p)
		if u > 1.0 or (u > 0.0 and on != _branch):
			# sorti au bout (il regagne sa ligne), ou pousse hors de sa
			# chaussee : la piste reprend
			_exit = _branch if u > 1.0 else -1
			_branch = -1
		else:
			_to_entry = -u * track.branch_length(_branch) if u >= 0.0 \
					else maxf(_s_gap(index, track.index_at_s(track.branch_span(_branch).x)), 0.0)
			return
	for k in track.branch_count():
		var gap := _s_gap(index, track.index_at_s(track.branch_span(k).x))
		if gap <= 0.0 or gap > SHORTCUT_COMMIT_M:
			if _branch_seen == k:
				_branch_seen = -1
			continue
		if _branch_seen == k:
			continue
		_branch_seen = k
		_passes += 1
		if takes_shortcut(level, _phase, _passes) and _can_jump(k):
			_branch = k
			_to_entry = gap
			shortcuts_taken += 1
		return


## Vitesse du profil a `d` m devant, le long de son chemin : sur le raccourci,
## celle de ses virages (2026-10-21 : il n'est plus tout droit) ; apres, le
## profil de la piste a la sortie.
func _profile_at(d: float) -> float:
	if _branch >= 0 and d >= _to_entry:
		var blen := track.branch_length(_branch)
		if d <= _to_entry + blen:
			var c := track.branch_curvature(_branch, (d - _to_entry) / blen)
			return minf(PROFILE_CEILING_MS, sqrt(_grip * BRANCH_CURVE_GRIP / maxf(c, 1e-5)))
		var past := d - _to_entry - blen
		var j := track.index_at_s(track.branch_span(_branch).y + past)
		if past > _exit_m[_branch] + 20.0:
			return _profile[j]
		return minf(_profile[j], _cap(_exit_curv(_branch, j)))
	var i := track.sample_ahead(index, d)
	var p := _profile[i]
	# vers le raccourci, ou en le quittant, il suit sa ligne d'approche ou de
	# sortie, pas la ligne de course
	if _branch >= 0 and d >= _to_entry - _blend_m[_branch] - 20.0:
		p = minf(p, _cap(_approach_curv(_branch, i)))
	elif _exit >= 0 and _s_gap(track.index_at_s(track.branch_span(_exit).y), i) <= _exit_m[_exit] + 20.0:
		p = minf(p, _cap(_exit_curv(_exit, i)))
	return p


## Vitesse de virage (m/s) a cette courbure, avec la marge SHORTCUT_GRIP.
func _cap(curv: float) -> float:
	return sqrt(_grip * SHORTCUT_GRIP / maxf(curv, 1e-5))


## Point vise a `look` m devant, le long de son chemin, a l'ecart _lat_now
## (de la ligne centrale ; sur un raccourci, de son axe plus son decalage).
func _aim(look: float) -> Vector3:
	if _branch >= 0 and look >= _to_entry:
		var blen := track.branch_length(_branch)
		var u := (look - _to_entry) / blen
		if u <= 1.0:
			return track.branch_frame(_branch, u, _lat_now - track.branch_lateral(_branch), 0.0).origin
		var i := track.index_at_s(track.branch_span(_branch).y + (u - 1.0) * blen)
		return track.sample_position(i) + track.sample_right(i) * _lat_now
	var j := track.sample_ahead(index, look)
	return track.sample_position(j) + track.sample_right(j) * _lat_now


## Vers le raccourci k : ecart, a l'echantillon i de la piste, de sa ligne
## d'approche. Loin de l'entree, sa ligne de course (elle prepare deja le
## virage du detour, du cote du raccourci) ; sur _blend_m[k], elle glisse en
## douceur vers l'ecart de l'axe du raccourci (branch_lateral, toujours sur
## la chaussee), atteint APPROACH_ALIGN_M avant l'entree. Une ligne fixe sur
## la piste : pas d'a-coup, et sa courbure se mesure. (L'axe prolonge en
## ligne droite sortait de la route avant un virage ou un S.)
func _approach_lat(k: int, i: int) -> float:
	var to := _s_gap(i, track.index_at_s(track.branch_span(k).x))
	var blend := _blend_m[k]
	var w := clampf((blend - to) / (blend - APPROACH_ALIGN_M), 0.0, 1.0)
	return lerpf(_line_at(i), track.branch_lateral(k), smoothstep(0.0, 1.0, w))


## Courbure (1/m) de sa ligne d'approche a l'echantillon i (trois points,
## APPROACH_CURV_M de part et d'autre, a l'horizontale).
func _approach_curv(k: int, i: int) -> float:
	var s := track.sample_s(i)
	var a := _approach_point(k, track.index_at_s(s - APPROACH_CURV_M))
	var b := _approach_point(k, i)
	var c := _approach_point(k, track.index_at_s(s + APPROACH_CURV_M))
	return _curv3(a, b, c)


## Courbure (1/m) du cercle par trois points, a l'horizontale.
static func _curv3(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var bc := Vector2(c.x - b.x, c.z - b.z)
	var ac := Vector2(c.x - a.x, c.z - a.z)
	var den := ab.length() * bc.length() * ac.length()
	return 2.0 * absf(ab.cross(ac)) / den if den > 1e-3 else 0.0


## Longueur de glissement (pas de 20 m) dont la ligne d'approche du raccourci
## k a la plus faible courbure maximale (une fois, a la mise en place).
func _best_blend(k: int) -> float:
	var s0 := track.branch_span(k).x
	var best := APPROACH_BLEND_MIN_M
	var best_curv := INF
	var blend := APPROACH_BLEND_MIN_M
	while blend <= APPROACH_BLEND_MAX_M:
		_blend_m.resize(k + 1)
		_blend_m[k] = blend
		var worst := 0.0
		var d := 0.0
		while d <= blend + 20.0:
			worst = maxf(worst, _approach_curv(k, track.index_at_s(s0 - d)))
			d += 4.0
		if worst < best_curv:
			best_curv = worst
			best = blend
		blend += 20.0
	return best


## Apres le raccourci k : ecart, a l'echantillon i de la piste, de sa ligne de
## sortie. Elle part de l'ecart de l'axe du raccourci et rejoint en douceur sa
## ligne de course sur _exit_m[k] (la piste peut tourner aussitot apres la
## sortie : il ne doit pas y rester du cote interieur).
func _exit_lat(k: int, i: int) -> float:
	var d := _s_gap(track.index_at_s(track.branch_span(k).y), i)
	var w := clampf(d / _exit_m[k], 0.0, 1.0)
	return lerpf(track.branch_lateral(k), _line_at(i), smoothstep(0.0, 1.0, w))


## Courbure (1/m) de sa ligne de sortie a l'echantillon i.
func _exit_curv(k: int, i: int) -> float:
	var s := track.sample_s(i)
	var a := _exit_point(k, track.index_at_s(s - APPROACH_CURV_M))
	var b := _exit_point(k, i)
	var c := _exit_point(k, track.index_at_s(s + APPROACH_CURV_M))
	return _curv3(a, b, c)


func _exit_point(k: int, i: int) -> Vector3:
	return track.sample_position(i) + track.sample_right(i) * _exit_lat(k, i)


## Longueur de sortie (pas de 20 m) la moins courbee, qui ne passe pas sur le
## bord d'un tremplin (il l'aborderait de biais, par son flanc).
func _best_exit(k: int) -> float:
	var s1 := track.branch_span(k).y
	var best := EXIT_MIN_M
	var best_cost := INF
	var length := EXIT_MIN_M
	while length <= EXIT_MAX_M:
		_exit_m.resize(k + 1)
		_exit_m[k] = length
		var worst := 0.0
		var d := 0.0
		while d <= length + 20.0:
			worst = maxf(worst, _exit_curv(k, track.index_at_s(s1 + d)))
			d += 4.0
		for j in track.jump_pad_count():
			var xf := track.jump_pad_transform(j)
			var ji := track.closest_sample(xf.origin)
			var ahead := _s_gap(track.index_at_s(s1), ji)
			if ahead < -track.jump_length or ahead > length + 20.0:
				continue
			# le long de la rampe, l'ensemble ne doit chevaucher aucun bord
			var jl := _lateral_of(xf.origin, ji)
			var u := -track.jump_length
			while u <= track.jump_length:
				var y := _exit_lat(k, track.index_at_s(track.sample_s(ji) + u))
				if absf(absf(y - jl) - track.jump_width / 2.0) < HALF_WIDTH_M + 1.0:
					worst += 1.0
					break
				u += 2.0
		if worst < best_cost:
			best_cost = worst
			best = length
		length += 20.0
	return best


func _approach_point(k: int, i: int) -> Vector3:
	return track.sample_position(i) + track.sample_right(i) * _approach_lat(k, i)


## Sens de course du raccourci k a sa part u.
func _branch_dir(k: int, u: float) -> Vector3:
	return -track.branch_frame(k, clampf(u, 0.0, 1.0), 0.0, 0.0).basis.z


## Son ecart, comme _lat_now (sur un raccourci : axe plus decalage).
func _my_lat() -> float:
	if _on_branch():
		return track.branch_lateral(_branch) + track.branch_lateral_of(_branch, truck.global_position)
	return _lateral_of(truck.global_position, index)


## Sur le raccourci : la place en travers (pas SHORTCUT_STEP_M) la plus proche
## de sa voie, et du milieu, qui evite les barils et les camions devant lui,
## et les flaques si ce n'est pas trop couteux ; sans place, il se cale derriere le plus proche qui roule.
## Memes champs que _traffic.
func _branch_traffic(v: float) -> Dictionary:
	var k := _branch
	var p := truck.global_position
	var blen := track.branch_length(k)
	var u_me := track.branch_u(k, p)
	var bl := track.branch_lateral(k)
	var half := track.branch_width_of(k) / 2.0 - SHORTCUT_EDGE_M
	var look := maxf(LOOK_AHEAD_M, v * LOOK_AHEAD_S)
	var dir := _branch_dir(k, u_me)
	var my_v := truck.linear_velocity.dot(dir)
	# obstacles : [devant mon nez (m), ecart a l'axe, portee en travers,
	# vitesse, camion qui roule]
	var obs: Array[Array] = []
	# flaques : [devant (m), ecart, portee] ; un cout, pas un mur
	var puddles: Array[Array] = []
	for pd: Array in track.branch_puddles(k):
		var ahead := (float(pd[0]) - u_me) * blen - float(pd[2]) - NOSE_M
		if ahead > -2.0:
			puddles.append([ahead, float(pd[1]), float(pd[2]) + HALF_WIDTH_M])
	var barrel_r := ExplosiveBarrel.BARREL_RADIUS + 1.0
	for b in track.branch_barrels(k):
		if b == null or not is_instance_valid(b) or not b.is_inside_tree() or not b.visible or b.exploded_state:
			continue
		# sa zone compte jusqu'a ce que la remorque l'ait passee
		var ahead := (track.branch_u(k, b.global_position) - u_me) * blen - barrel_r - NOSE_M
		if ahead > -TAIL_M - 2.0 * barrel_r:
			obs.append([ahead, track.branch_lateral_of(k, b.global_position), barrel_r + HALF_WIDTH_M + CLEAR_M, 0.0, false])
	for n in truck.get_tree().get_nodes_in_group(TruckPowers.TARGETS):
		var t := n as Truck
		if t == null or t == truck or not t.is_inside_tree() or t.is_wrecked() or track.on_branch(t.global_position, 2.0) != k:
			continue
		var tail := NOSE_M if t.is_trailer_detached() else TAIL_M
		var ahead := (track.branch_u(k, t.global_position) - u_me) * blen - tail - NOSE_M
		var tv := t.linear_velocity.dot(dir)
		# a cote, ou devant et plus lent
		if ahead > -TAIL_M - tail - NOSE_M and (ahead < 1.0 or my_v - tv > 0.5):
			obs.append([ahead, track.branch_lateral_of(k, t.global_position), 2.0 * HALF_WIDTH_M + CLEAR_M, tv, true])
	var cur := _lat_now - bl
	var turn := track.branch_turn(k, u_me + v * BRANCH_INSIDE_S / blen)
	var inside := -clampf(turn * BRANCH_INSIDE_R_M, -1.0, 1.0) * half * BRANCH_INSIDE_PART
	var best := INF
	var best_x := cur
	var x := -half
	while x <= half + 0.001:
		var free := true
		for o in obs:
			if float(o[0]) <= look and absf(x - float(o[1])) < float(o[2]):
				free = false
				break
		if free:
			var cost := 0.5 * absf(x - cur) + absf(x - inside)
			for pd in puddles:
				if float(pd[0]) <= look and absf(x - float(pd[1])) < float(pd[2]):
					cost += PUDDLE_COST_M
			if cost < best:
				best = cost
				best_x = x
		x += SHORTCUT_STEP_M
	var cap := INF
	var clear := true
	blocked_by = null
	for o in obs:
		var ahead := float(o[0])
		if ahead < 0.0 or ahead > look or absf(best_x - float(o[1])) >= float(o[2]):
			continue
		if ahead < 40.0:
			clear = false
		# pas de place pour passer un camion : il se cale derriere
		if bool(o[4]):
			cap = minf(cap, maxf(float(o[3]), 0.0) + maxf(0.0, ahead - FOLLOW_GAP_M) * 0.35)
	return {"lateral": bl + clampf(best_x, -half, half), "cap": cap, "clear": clear}


## Arene : fonce sur le camion vivant le plus proche (vise un peu devant lui),
## plein gaz ; trop pres d'un mur et en s'y dirigeant, il revient vers le
## milieu de l'anneau. Nitro en ligne droite sur sa proie.
func _arena_drive(v: float) -> void:
	_arena_shun_left = maxi(_arena_shun_left - 1, 0)
	if _arena_back > 0:
		# recule en braquant un peu, pour se degager de biais (a fond, la
		# remorque se met en portefeuille et bloque)
		_arena_back -= 1
		frame.boost = false
		if _arena_out:
			frame.throttle = 1.0
			frame.brake = 0.0
			frame.steer = 0.0
			return
		frame.throttle = 0.0
		frame.brake = 1.0
		frame.steer = 0.35 if _phase % 2 == 0 else -0.35
		return
	var prey: Truck = null
	var best := INF
	for n in truck.get_tree().get_nodes_in_group(TruckPowers.TARGETS):
		var t := n as Truck
		if t == null or t == truck or t.is_wrecked():
			continue
		if t == _arena_shunned and _arena_shun_left > 0:
			continue
		var d := t.global_position.distance_to(truck.global_position)
		if d < best:
			best = d
			prey = t
	var fwd := -truck.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var want := fwd
	if prey != null:
		want = prey.global_position + prey.linear_velocity * 0.6 - truck.global_position
		want.y = 0.0
		want = want.normalized() if want.length_squared() > 1.0 else fwd
	# bord de l'anneau : vers le milieu de la chaussee
	var lat := _lateral_of(truck.global_position, index)
	var edge := track.width / 2.0 - ARENA_EDGE_M
	if absf(lat) > edge and truck.linear_velocity.dot(track.sample_right(index)) * signf(lat) > 0.0:
		want = (track.sample_position(index) - truck.global_position).normalized()
		want.y = 0.0
	var angle := atan2(fwd.cross(want).y, fwd.dot(want))
	frame.steer = clampf(-angle * 2.0, -1.0, 1.0)
	frame.throttle = 1.0 if absf(angle) < 1.8 else 0.6
	frame.brake = 0.0
	frame.boost = prey != null and absf(angle) < 0.15 and best > 40.0 and bool(BOOST[level])
	# gaz a fond sans avancer : il pousse quelqu'un ou un mur, il recule
	_arena_stuck = _arena_stuck + 1 if v < ARENA_STUCK_MS and RaceManager.state == RaceManagerNode.State.RACING else 0
	if _arena_stuck >= ARENA_STUCK_TICKS:
		_arena_stuck = 0
		_arena_back = ARENA_BACK_TICKS
		_arena_out = absf(lat) > edge and fwd.dot(track.sample_right(index)) * signf(lat) < 0.0
		if prey != null and best < 15.0:
			_arena_shunned = prey
			_arena_shun_left = ARENA_IGNORE_TICKS


## Un missile ou un boomerang qui le vise arrive (a moins de SHIELD_WARN_M),
## ou un laser le touche.
func _threatened() -> bool:
	var warn := float(SHIELD_WARN_M[level])
	if warn <= 0.0:
		return false
	var tree := truck.get_tree()
	for n in tree.get_nodes_in_group(PowerMissile.PROJECTILES):
		var aim: Variant = n.get("target")
		if aim != truck:
			continue
		if n is PowerBoomerang and (n as PowerBoomerang).returning:
			continue
		if (n as Node3D).global_position.distance_to(truck.global_position) < warn:
			return true
	for n in tree.get_nodes_in_group(TruckPowers.TARGETS):
		var t := n as Truck
		if t == null or t == truck:
			continue
		var p := TruckPowers.of(t)
		if p != null and p.laser_ticks > 0 and p.laser_hit == truck:
			return true
	return false


## Largage tactique (voir l'en-tete) : un front d'un tick.
func _drop_tactic(v: float) -> void:
	if not bool(DROP[level]) or _cargo == null or not _cargo.is_ready() or truck.is_trailer_detached():
		return
	if _pursuer() == null:
		return
	var corner_s := float(DROP_CORNER_S[level])
	if corner_s > 0.0 and not _corner_within(v, corner_s):
		return
	frame.cargo = true
	drops += 1


## Camion qui le suit dans sa voie, juste derriere sa remorque, ou null.
func _pursuer() -> Truck:
	for n in truck.get_tree().get_nodes_in_group(TruckPowers.TARGETS):
		var t := n as Truck
		if t == null or t == truck or t.is_wrecked() or not t.is_inside_tree():
			continue
		var i := _sample_of(t.global_position, int(_hints.get(t, index)))
		_hints[t] = i
		# son nez par rapport a l'arriere de notre remorque (negatif : derriere)
		var gap := _s_gap(index, i) + NOSE_M + TAIL_M
		if gap > 0.0 or gap < -DROP_BEHIND_M:
			continue
		if absf(_lateral_of(t.global_position, i) - _lateral_of(truck.global_position, index)) < DROP_LATERAL_M:
			return t
	return null


## Un virage arrive dans `seconds` s : la piste y tourne plus serre que
## DROP_CORNER_RADIUS_M.
func _corner_within(v: float, seconds: float) -> bool:
	var reach := maxf(v * seconds, 20.0)
	var d := 0.0
	while d <= reach:
		if absf(track.curvature(track.sample_ahead(index, d))) > 1.0 / DROP_CORNER_RADIUS_M:
			return true
		d += PLAN_STEP_M
	return false


## Un camion juste a cote de la cabine (a portee des scies), ou null.
func _beside() -> Truck:
	var inv := truck.global_transform.affine_inverse()
	for n in truck.get_tree().get_nodes_in_group(TruckPowers.TARGETS):
		var t := n as Truck
		if t == null or t == truck:
			continue
		var local := inv * t.global_position
		local.x -= signf(local.x) * TruckSpec.CHASSIS_SIZE.x / 2.0
		if TruckPowers.saw_side(local) != 0.0:
			return t
	return null


func _powers() -> void:
	var powers := TruckPowers.of(truck)
	if powers == null:
		return
	var health := TruckHealth.of(truck)
	# un projectile arrive : le bouclier tout de suite, sans temps de reaction
	for k in 2:
		if powers.slots[k] == PowerCatalog.Id.SHIELD and powers.cooldown[k] == 0 and _threatened():
			if k == 0:
				frame.power_left = true
			else:
				frame.power_right = true
			_power_wait = int(REACTION_TICKS[level])
			return
	if _power_wait > 0:
		_power_wait -= 1
		return
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
				use = t != null and truck.global_position.distance_to(t.global_position) < PowerCatalog.BOOMERANG_RANGE_M * 0.8
			PowerCatalog.Id.SAW:
				use = _beside() != null
		if use:
			if k == 0:
				frame.power_left = true
			else:
				frame.power_right = true
			_power_wait = int(REACTION_TICKS[level])
			return
