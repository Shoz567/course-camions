class_name Truck
extends RigidBody3D

## Le camion : un seul RigidBody3D, 4 rayons de suspension (spike V1).
##
## Forces, appliquees a chaque tick dans _physics_process, chacune derriere son
## interrupteur de debug (CLAUDE.md §6) :
##   1.3 suspension : ressort-amortisseur par roue, longueur libre par essieu
##   1.4 moteur, freins, marche arriere, resistance au roulement, trainee
##   1.5 direction reduite avec la vitesse, adherence laterale ponderee par la
##       charge de la roue et la surface
##   1.6 frein a main (derapage, contre-braquage permissif), anti-retournement
##       au sol, controle en l'air (assiette automatique, lacet au stick)
##   1.9 traces DebugDraw : rayons, contacts, forces, centre de masse
##   boost : poussee et vitesse max relevees pendant boost_duration_ticks, puis
##       jauge rechargee en boost_recharge_ticks (declenche a l'appui)
##   plaques : boost de plaque (coup de pouce immediat + vitesse max relevee),
##       saut de plaque (impulsion verticale, assiette renforcee en l'air,
##       reception amortie)
##   remorque articulee : la caisse de la remorque pivote autour de la sellette
##       (VEHICLE_SPEC §5 bis), avec sa propre inertie de lacet. Elle chasse
##       vers l'exterieur en virage et en derapage, s'arrete contre les murs,
##       et balaie les adversaires qu'elle touche.
##   anti-collage : apres wall_unstick_ticks de frottement continu contre un
##       mur, -25 % de vitesse et une impulsion vers l'interieur de la piste
##       (normale du mur) : le camion ne reste jamais aimante a la glissiere.
##   caisse de cargo percutee (cargo_hit) : ralenti et deporte en lacet.
##
## Interface avec le gameplay (gameplay-engineer.md), la seule autorisee :
##   set_input(frame), reset_to(xf), get_speed_kmh(), is_upside_down(),
##   wheels_on_ground(), pad_boost(), jump_pad_launch(), cargo_hit()
## Le camion ne lit jamais Input.* : il recoit une InputFrame.

## Coup de klaxon recu dans l'InputFrame (le son est l'affaire du gameplay).
signal honked
## Un boost commence (jauge du joueur ou plaque de la piste).
signal boosted
## La remorque vient de balayer un adversaire (impulsion en N.s).
signal trailer_shoved(other: Truck, impulse: float)
## Largage de cargo demande dans l'InputFrame (le cargo est l'affaire du
## gameplay : TruckCargo, enfant du camion).
signal cargo_requested
## Decolle du mur apres un frottement continu (normale du mur, horizontale).
signal wall_unstuck(normal: Vector3)
## Vient de percuter une caisse de cargo.
signal cargo_hit_taken

## En dessous de cette vitesse (m/s), le frein devient marche arriere et le gaz
## en marche arriere devient frein.
const STOP_SPEED_MS := 0.5

@export var tuning: VehicleTuning

@export_group("Debug : forces actives")
@export var debug_suspension: bool = true
@export var debug_drive: bool = true
@export var debug_grip: bool = true
@export var debug_steering: bool = true
@export var debug_drag: bool = true
@export var debug_anti_roll: bool = true
@export var debug_handbrake: bool = true
@export var debug_air_control: bool = true
@export var debug_boost: bool = true
@export var debug_wall_unstick: bool = true
## Traces DebugDraw du camion (actifs seulement si DebugDraw.enabled).
@export var debug_draw: bool = true

## Echelle des fleches de force : 1 m pour 10 kN (une roue porte ~12 kN).
const DRAW_FORCE_SCALE := 1.0e-4

## Derniere consigne recue. Copiee, jamais partagee avec la source.
var _input: InputFrame = InputFrame.new()
var _probes: Array[WheelProbe] = []
var _free_length: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _k: float = 0.0
var _c: float = 0.0
var _top_speed_ms: float = 0.0
var _taper_ms: float = 0.0
var _reverse_top_ms: float = 0.0
var _tan_slip: float = 0.0
var _wheelbase: float = TruckSpec.ANCHORS[2].z - TruckSpec.ANCHORS[0].z
var _min_ref_speed: float = 0.0
var _steer_deg: float = 0.0
var _grounded: int = 0
var _active: bool = false
## 0 = adherence pleine, 1 = adherence de frein a main (train arriere).
var _handbrake_blend: float = 0.0
## Boost : ticks restants, jauge 0 .. 1 (1 = pret), appui precedent.
var _boost_ticks: int = 0
var _boost_charge: float = 1.0
var _boost_was_pressed: bool = false
var _tire_force: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
## Plaque de boost : ticks restants, vitesse ajoutee (m/s), coup de pouce a
## donner au prochain tick.
var _pad_boost_ticks: int = 0
var _pad_boost_extra_ms: float = 0.0
var _pad_kick_pending: bool = false
## Saut de plaque : vitesse verticale a atteindre (0 = rien en attente), ticks
## d'aide restants, ticks passes en l'air depuis l'impulsion, amortissement
## renforce apres la reception.
var _launch_up_ms: float = 0.0
var _jump_assist_ticks: int = 0
var _air_ticks: int = 0
var _landing_damp_ticks: int = 0
## Reception d'un saut de plaque : vitesse de chute juste avant l'amorti (m/s).
var last_landing_fall_ms: float = 0.0

## Remorque : angle par rapport au tracteur (rad, > 0 = arriere vers la droite
## du tracteur) et vitesse de lacet DANS LE MONDE (rad/s) : elle a sa propre
## inertie, le tracteur tourne sans l'entrainer instantanement.
var _trailer_angle: float = 0.0
var _trailer_yaw_rate: float = 0.0
var _trailer_rel_rate: float = 0.0
var _trailer_applied: float = 0.0
## Acceleration laterale mesuree (m/s2, > 0 vers la gauche du tracteur),
## filtree : vitesse du tick precedent pour la deriver.
var _lat_accel: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
var _accel_ready: bool = false
## Cap de la vitesse au tick precedent (rotation de la trajectoire).
var _prev_heading_v: float = 0.0
var _heading_ready: bool = false
## Dernier coup de remorque donne a chaque adversaire (id -> tick).
var _shove_ticks: Dictionary = {}
var _trailer_shape: CollisionShape3D
var _trailer_query: PhysicsShapeQueryParameters3D

## Mur touche au dernier pas physique (lu dans _integrate_forces) : normale
## moyenne, horizontale, tournee vers le camion. ZERO = aucun mur.
var _wall_normal: Vector3 = Vector3.ZERO
## Ticks de frottement continu contre un mur, ticks sans contact depuis.
var _wall_ticks: int = 0
var _wall_gap: int = 0
## Caisse de cargo percutee : position de la caisse, choc a appliquer.
var _cargo_hit_pending: bool = false
var _cargo_hit_from: Vector3 = Vector3.ZERO

var _reset_pending: bool = false
## Teleportation faite au dernier pas : l'interpolation du rendu doit repartir
## de la nouvelle position, sinon le camion "glisse" a l'ecran jusqu'a elle.
var _reset_applied: bool = false
var _reset_xf: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	for n in TruckSpec.PROBE_NAMES:
		_probes.append(get_node(NodePath(n)) as WheelProbe)
	_trailer_shape = get_node_or_null(^"Trailer") as CollisionShape3D
	if _trailer_shape != null:
		_trailer_query = PhysicsShapeQueryParameters3D.new()
		_trailer_query.shape = _trailer_shape.shape
		_trailer_query.exclude = [get_rid()]
	if tuning == null:
		push_error("Truck '%s' : aucun VehicleTuning" % name)
		return
	var errors := tuning.validate()
	if not errors.is_empty():
		push_error("Truck '%s' : VehicleTuning invalide :\n  %s" % [name, "\n  ".join(errors)])
		return
	apply_tuning()
	_active = true


## Derive les constantes de simulation du reglage. A rappeler apres avoir
## modifie `tuning` en cours de partie.
func apply_tuning() -> void:
	# Raideur reglee en frequence sur m_roue = M/4 ; longueur libre deduite de
	# la charge de CHAQUE essieu (VEHICLE_SPEC §4), pour que la hauteur de caisse
	# ne depende pas de la raideur.
	var m_wheel := mass / 4.0
	var w := TAU * tuning.suspension_frequency_hz
	_k = m_wheel * w * w
	_c = 2.0 * tuning.suspension_damping_ratio * m_wheel * w
	for i in 4:
		_free_length[i] = TruckSpec.spring_free_length(i, _k)
	_top_speed_ms = tuning.top_speed_kmh / 3.6
	_taper_ms = tuning.engine_taper_kmh / 3.6
	_reverse_top_ms = tuning.reverse_top_speed_kmh / 3.6
	_tan_slip = tan(deg_to_rad(tuning.grip_slip_angle_deg))
	# Sous cette vitesse, l'adherence se regle en glissement (m/s) et non plus en
	# angle : les deux lois se raccordent exactement a cette vitesse.
	_min_ref_speed = tuning.grip_saturation_speed_ms / _tan_slip
	# inertie imposee (axes locaux X tangage, Y lacet, Z roulis) : independante
	# des formes de collision, donc de la remorque
	inertia = Vector3(tuning.inertia_pitch_kgm2, tuning.inertia_yaw_kgm2, tuning.inertia_roll_kgm2)
	var mat := PhysicsMaterial.new()
	mat.friction = tuning.chassis_friction
	mat.bounce = 0.0
	physics_material_override = mat


# --- interface gameplay --------------------------------------------------------

## Consigne du tick courant. Appelee a chaque tick, avant la physique.
func set_input(frame: InputFrame) -> void:
	_input.copy_from(frame)


func get_input() -> InputFrame:
	return _input


## Remet le camion a `xf`, vitesses nulles, au prochain pas physique.
## Passe par state.transform (CLAUDE.md §6) : jamais global_position.
func reset_to(xf: Transform3D) -> void:
	_reset_xf = xf
	_reset_pending = true


## Vitesse le long de l'axe avant (-Z), pas la norme du vecteur (METRICS.md).
func get_speed_kmh() -> float:
	return linear_velocity.dot(-global_transform.basis.z) * 3.6


func is_upside_down() -> bool:
	return global_transform.basis.y.y < 0.0


func wheels_on_ground() -> int:
	return _grounded


func get_probe(i: int) -> WheelProbe:
	return _probes[i]


## Angle de braquage courant des roues avant (deg, > 0 a droite).
func get_steer_deg() -> float:
	return _steer_deg


## Engagement du frein a main, 0 .. 1 (rampes d'engagement et de relacher).
func get_handbrake_blend() -> float:
	return _handbrake_blend


## Jauge de boost : 1 = pret, 0 = vide (pendant le boost et au debut de la
## recharge).
func get_boost_charge() -> float:
	return _boost_charge


func is_boosting() -> bool:
	return _boost_ticks > 0 or _pad_boost_ticks > 0


## Plaque de boost : +extra_kmh tout de suite (sans depasser la vitesse max
## + extra_kmh), puis vitesse max relevee d'autant pendant `ticks`. La jauge du
## joueur n'est pas touchee.
func pad_boost(extra_kmh: float, ticks: int) -> void:
	_pad_boost_extra_ms = extra_kmh / 3.6
	_pad_boost_ticks = ticks
	_pad_kick_pending = true
	boosted.emit()


## Plaque de saut : vitesse verticale portee a `up_speed_ms` (jamais reduite),
## assiette automatique renforcee jusqu'a la reception, reception amortie.
func jump_pad_launch(up_speed_ms: float) -> void:
	_launch_up_ms = up_speed_ms
	_jump_assist_ticks = roundi(tuning.jump_assist_max_ticks)


func is_jump_assisted() -> bool:
	return _jump_assist_ticks > 0


## Caisse de cargo percutee (CargoCrate) : au prochain tick, vitesse reduite
## a cargo_hit_speed_factor et coup de lacet du cote de la caisse.
func cargo_hit(crate_position: Vector3) -> void:
	_cargo_hit_pending = true
	_cargo_hit_from = crate_position


## Ticks de frottement continu contre un mur (0 = libre).
func get_wall_contact_ticks() -> int:
	return _wall_ticks


## Angle de la remorque par rapport au tracteur (rad), > 0 : arriere de la
## remorque vers la droite du tracteur.
func get_trailer_angle() -> float:
	return _trailer_angle


func get_trailer_angle_deg() -> float:
	return rad_to_deg(_trailer_angle)


## Pose de la caisse de remorque dans le repere du camion, pour un angle donne :
## rotation en lacet autour de la sellette.
static func trailer_local_transform(angle: float) -> Transform3D:
	var b := Basis(Vector3.UP, angle)
	return Transform3D(b, TruckSpec.KINGPIN + b * (TruckSpec.TRAILER_CENTER - TruckSpec.KINGPIN))


# --- simulation ------------------------------------------------------------------

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# contacts avec un mur : corps statique, normale presque horizontale (le
	# sol et les rampes ont une normale verticale)
	var n_sum := Vector3.ZERO
	for i in state.get_contact_count():
		if not (state.get_contact_collider_object(i) is StaticBody3D):
			continue
		var n := state.get_contact_local_normal(i)
		if absf(n.y) > 0.6:
			continue
		n.y = 0.0
		if n.dot(state.transform.origin - state.get_contact_local_position(i)) < 0.0:
			n = -n
		n_sum += n.normalized()
	_wall_normal = n_sum.normalized() if n_sum.length_squared() > 1e-6 else Vector3.ZERO
	if not _reset_pending:
		return
	_reset_pending = false
	state.transform = _reset_xf
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
	_reset_applied = true


func _physics_process(_delta: float) -> void:
	if _reset_applied:
		_reset_applied = false
		reset_physics_interpolation()
		# remis en piste : remorque dans l'axe, plus d'aide ni de boost de plaque
		_trailer_yaw_rate = 0.0
		_lat_accel = 0.0
		_accel_ready = false
		_set_trailer_angle(0.0)
		_jump_assist_ticks = 0
		_launch_up_ms = 0.0
		_pad_boost_ticks = 0
		_pad_kick_pending = false
	_grounded = 0
	for p in _probes:
		p.probe()
		if p.in_contact:
			_grounded += 1
	if not _active:
		return

	var xf := global_transform
	var origin := xf.origin
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var com := xf * center_of_mass
	var v_fwd := linear_velocity.dot(fwd)
	var t := tuning

	# 1.5 direction : l'angle max diminue avec la vitesse, borne par l'angle
	# qui fait tourner a la limite d'adherence (tout le stick reste utile), et
	# les roues tournent a vitesse bornee (pas de coup de volant instantane).
	var target_deg := 0.0
	var steer_in := clampf(_input.steer, -1.0, 1.0)
	if debug_steering:
		var max_deg := _grip_steer_deg(v_fwd)
		# 1.6 contre-braquage permissif : du cote ou glisse le camion, la limite
		# s'elargit de l'angle de derive. Les roues avant peuvent toujours
		# s'aligner sur la trajectoire, et un derapage se rattrape au stick.
		var v_right := linear_velocity.dot(xf.basis.x)
		var slip_deg := 0.0   # > 0 : la vitesse part a droite du cap
		if v_fwd > STOP_SPEED_MS:
			slip_deg = rad_to_deg(atan2(v_right, v_fwd))
		if steer_in * slip_deg > 0.0:
			max_deg += absf(slip_deg)
		target_deg = steer_in * minf(t.max_steer_deg, max_deg)
		# contre-braquage automatique, stick au neutre : relance propre
		target_deg += (1.0 - absf(steer_in)) * t.auto_countersteer_ratio * slip_deg
		target_deg = clampf(target_deg, -t.max_steer_deg, t.max_steer_deg)
	_steer_deg = move_toward(_steer_deg, target_deg, t.steer_rate_deg_per_tick)
	var steer_rad := deg_to_rad(_steer_deg)

	# 1.6 frein a main : engagement rapide, relacher plus lent (relance propre).
	var hb_target := 1.0 if (_input.handbrake and debug_handbrake) else 0.0
	var hb_step := 1.0 / (t.handbrake_engage_ticks if hb_target > _handbrake_blend else t.handbrake_release_ticks)
	_handbrake_blend = move_toward(_handbrake_blend, hb_target, hb_step)
	var rear_grip := lerpf(1.0, t.handbrake_rear_grip_factor, _handbrake_blend)

	# 1.4 consigne longitudinale, en m/s2 pour tout le camion.
	var drive := 0.0     # > 0 vers l'avant
	var braking := 0.0   # 0 .. 1
	var thr := clampf(_input.throttle, 0.0, 1.0)
	var brk := clampf(_input.brake, 0.0, 1.0)
	var resist := t.aero_drag_per_m * v_fwd * v_fwd \
			+ t.rolling_resistance_ms2 * clampf(absf(v_fwd) / t.grip_saturation_speed_ms, 0.0, 1.0)
	if thr > 0.0:
		if v_fwd < -STOP_SPEED_MS:
			braking = thr
		else:
			# poussee nette constante, puis decroissance lineaire sur la bande
			# sous la vitesse max ; les resistances sont compensees jusqu'a la
			# vitesse max, pas au-dela : apres un boost, le camion y redescend.
			var taper := clampf((_top_speed_ms - v_fwd) / _taper_ms, 0.0, 1.0)
			drive = thr * (t.engine_accel_ms2 * taper + (resist if v_fwd <= _top_speed_ms else 0.0))
	if brk > 0.0:
		if v_fwd > STOP_SPEED_MS:
			braking = maxf(braking, brk)
		elif thr <= 0.0:
			var taper_r := clampf((_reverse_top_ms + v_fwd) / _taper_ms, 0.0, 1.0)
			drive = -brk * (t.reverse_accel_ms2 * taper_r + resist)
	# boost : declenche a l'appui si la jauge est pleine ; poussee ajoutee meme
	# sans gaz, vitesse max relevee, resistances compensees.
	# plaque de boost : meme mecanique, vitesse ajoutee par la plaque, et un
	# coup de pouce immediat a l'entree sur la plaque.
	_update_boost(t)
	var boost_extra := 0.0
	var boost_push := 0.0
	if _boost_ticks > 0:
		boost_extra = t.boost_top_speed_kmh / 3.6
		boost_push = t.boost_accel_ms2
	if _pad_boost_ticks > 0:
		_pad_boost_ticks -= 1
		boost_extra = maxf(boost_extra, _pad_boost_extra_ms)
		boost_push = maxf(boost_push, t.pad_boost_accel_ms2)
	if _pad_kick_pending:
		_pad_kick_pending = false
		if debug_boost:
			var kick := clampf(_top_speed_ms + _pad_boost_extra_ms - v_fwd, 0.0, _pad_boost_extra_ms)
			apply_central_impulse(fwd * kick * mass)
	if boost_push > 0.0 and debug_boost and v_fwd > -STOP_SPEED_MS:
		var top_b := _top_speed_ms + boost_extra
		var taper_b := clampf((top_b - v_fwd) / _taper_ms, 0.0, 1.0)
		drive = (thr * t.engine_accel_ms2 + boost_push) * taper_b + (resist if v_fwd <= top_b else 0.0)
		braking = 0.0 if brk <= 0.0 else braking
	elif v_fwd > _top_speed_ms:
		# frein moteur au-dessus de la vitesse max (rampe sur 2 m/s : pas de
		# pompage autour de la vitesse max)
		drive -= t.overspeed_decel_ms2 * clampf((v_fwd - _top_speed_ms) / 2.0, 0.0, 1.0)
	if not debug_drive:
		drive = 0.0
		braking = 0.0
	if _input.honk:
		honked.emit()
	if _input.cargo:
		cargo_requested.emit()
	_update_wall_unstick(t)
	if _cargo_hit_pending:
		_cargo_hit_pending = false
		_apply_cargo_hit(t, up)

	# saut de plaque : impulsion verticale ; a la reception (apres un vrai vol),
	# chute ramenee a jump_landing_max_down_ms et suspension plus amortie.
	if _launch_up_ms > 0.0:
		if linear_velocity.y < _launch_up_ms:
			apply_central_impulse(Vector3.UP * (_launch_up_ms - linear_velocity.y) * mass)
		_launch_up_ms = 0.0
		_air_ticks = 0
	var damp := _c
	if _landing_damp_ticks > 0:
		_landing_damp_ticks -= 1
		damp *= t.jump_landing_damping_factor
	if _jump_assist_ticks > 0:
		_jump_assist_ticks -= 1
		if _grounded == 0:
			_air_ticks += 1
		elif _air_ticks >= 8:   # un vrai vol, pas un rebond sur le bord de la rampe
			_jump_assist_ticks = 0
			_landing_damp_ticks = roundi(t.jump_landing_damping_ticks)
			var fall := -linear_velocity.y
			last_landing_fall_ms = fall
			if fall > t.jump_landing_max_down_ms:
				apply_central_impulse(Vector3.UP * (fall - t.jump_landing_max_down_ms) * mass)

	var m_wheel := mass / 4.0
	for i in 4:
		var p := _probes[i]
		_tire_force[i] = Vector3.ZERO
		if not p.in_contact:
			continue
		var anchor := p.global_position

		# 1.3 suspension : intensite mesuree le long du ressort, force appliquee
		# a l'ancrage le long de la NORMALE DE CONTACT. Le long de l'axe de la
		# caisse, elle aurait une composante horizontale des que le camion
		# cabre : 0,10 m/s2 de frein fantome mesure a l'acceleration (0,6 deg).
		# Hors de la verticale, ce choix cree aussi un leger couple de
		# redressement (ancrage au-dessus du contact).
		var n := p.contact_normal
		var fs := 0.0
		if debug_suspension:
			var v_up := _point_velocity(anchor, com).dot(up)
			fs = maxf(_k * (_free_length[i] - p.hub_distance) - damp * v_up, 0.0)
			apply_force(n * fs, anchor - origin)
		p.load_n = fs

		# Repere du pneu, dans le plan du sol ; roues avant braquees.
		var wheel_fwd := fwd
		if i < 2 and steer_rad != 0.0:
			wheel_fwd = fwd.rotated(up, -steer_rad)
		var f_dir := (wheel_fwd - n * wheel_fwd.dot(n)).normalized()
		var s_dir := n.cross(f_dir)   # vers la gauche de la roue
		var vc := _point_velocity(p.contact_point, com)
		var v_long := vc.dot(f_dir)
		var v_lat := vc.dot(s_dir)
		p.long_speed = v_long

		# 1.5 adherence laterale : lineaire en angle de glissement jusqu'a
		# grip_slip_angle_deg, puis plafonnee a mu * charge de la roue * surface.
		# A basse vitesse, la loi passe en glissement (m/s) pour tenir l'arret.
		# Sans charge, pas d'adherence : le camion ne s'accroche pas en l'air.
		var f_lat := 0.0
		var rear := i >= 2
		if debug_grip:
			var v_ref := maxf(absf(v_long), _min_ref_speed) * _tan_slip
			var mu := t.lateral_grip_g * p.surface_grip * (rear_grip if rear else 1.0)
			f_lat = -mu * fs * clampf(v_lat / v_ref, -1.0, 1.0)

		# 1.4 longitudinal : 4 roues motrices, forces proportionnelles a la masse.
		var f_long := drive * m_wheel
		if debug_drive:
			var decel := braking * t.brake_decel_ms2 + t.rolling_resistance_ms2
			if rear:
				decel += _handbrake_blend * t.handbrake_decel_ms2
			var sat := clampf(v_long / t.grip_saturation_speed_ms, -1.0, 1.0)
			f_long -= decel * m_wheel * sat

		_tire_force[i] = s_dir * f_lat + f_dir * f_long
		apply_force(_tire_force[i], p.contact_point - origin)

	# 1.4 trainee aerodynamique, explicite (linear_damp = 0, SPIKE A10).
	if debug_drag:
		apply_central_force(-linear_velocity * linear_velocity.length() * t.aero_drag_per_m * mass)

	# derapage maitrise : cible de derive au frein a main, jamais de tete-a-queue
	if debug_handbrake:
		_apply_drift_assist(t, up, fwd, steer_in, v_fwd)

	# 1.6 au sol : anti-retournement (prioritaire : les camions se percutent
	# souvent). En l'air : assiette automatique et lacet au stick.
	if _grounded > 0:
		if debug_anti_roll:
			_apply_anti_roll(up, fwd)
	elif debug_air_control:
		_apply_air_control(up, steer_in)

	# remorque articulee : angle de la caisse, murs, adversaires balayes
	if _trailer_shape != null:
		_update_trailer(up, com, v_fwd, xf.basis.x)

	# 1.9 traces de debug
	if debug_draw and DebugDraw.enabled:
		_draw_debug(up, com)


## Anti-collage : le frottement continu contre un mur (quelques ticks sans
## contact toleres) declenche, au-dela de wall_unstick_ticks, une perte de
## vitesse et une impulsion vers l'interieur de la piste. La vitesse qui
## rentre dans le mur est annulee, le nez est ramene parallele au mur.
func _update_wall_unstick(t: VehicleTuning) -> void:
	if _wall_normal != Vector3.ZERO:
		_wall_ticks += 1
		_wall_gap = 0
	else:
		_wall_gap += 1
		if _wall_gap > roundi(t.wall_contact_grace_ticks):
			_wall_ticks = 0
	if not debug_wall_unstick or _wall_ticks < roundi(t.wall_unstick_ticks) or _wall_normal == Vector3.ZERO:
		return
	var n := _wall_normal
	var v := linear_velocity
	var target := v * t.wall_unstick_speed_factor
	var into := target.dot(n)
	if into < 0.0:
		target -= n * into   # plus rien vers le mur
	target += n * t.wall_bump_speed_ms
	apply_central_impulse((target - v) * mass)
	# nez vers le mur : ramene parallele au mur (vers l'interieur de la piste)
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if fwd.dot(n) < -0.05:
		var along := (fwd - n * fwd.dot(n)).normalized()
		var turn := signf(fwd.cross(along).y) * minf(fwd.angle_to(along) * 3.0, t.wall_bump_align_rad_s)
		var w_up := angular_velocity.y
		apply_torque_impulse(Vector3.UP * (turn - w_up) * t.inertia_yaw_kgm2)
	_wall_ticks = 0
	wall_unstuck.emit(n)


func _apply_cargo_hit(t: VehicleTuning, up: Vector3) -> void:
	var v := linear_velocity
	var flat := v - up * v.dot(up)
	apply_central_impulse(-flat * (1.0 - t.cargo_hit_speed_factor) * mass)
	# coup de lacet du cote de la caisse (la caisse retient ce cote)
	var side := signf((_cargo_hit_from - global_position).dot(global_basis.x))
	if side == 0.0:
		side = 1.0
	apply_torque_impulse(up * (-side * t.cargo_hit_yaw_kick_rad_s) * t.inertia_yaw_kgm2)
	cargo_hit_taken.emit()


## Derapage maitrise (demande du playtest : plus de tetes-a-queue). La derive
## (angle entre le cap et la vitesse, > 0 : vitesse a droite du cap) varie
## comme lacet - rotation de la trajectoire ; on pilote donc le lacet :
##   - au frein a main, vers une derive cible proportionnelle au braquage
##     (drift_target_slip_deg au plein stick) : le drift tient, previsible ;
##   - a tout moment, jamais au-dela de drift_max_slip_deg : retour vers la
##     limite, meme sans frein a main (apres un choc, par exemple).
## Acceleration angulaire bornee (drift_assist_accel) : une aide, pas un rail.
func _apply_drift_assist(t: VehicleTuning, up: Vector3, fwd: Vector3, steer_in: float, v_fwd: float) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	var flat := linear_velocity - up * linear_velocity.dot(up)
	var speed := flat.length()
	var heading_v := atan2(-flat.x, -flat.z)
	var path_rate := 0.0
	if _heading_ready and speed > 2.0:
		path_rate = wrapf(heading_v - _prev_heading_v, -PI, PI) / dt
	_prev_heading_v = heading_v
	_heading_ready = speed > 2.0
	if _grounded < 2 or speed < t.drift_min_speed_ms or v_fwd <= 0.0:
		return
	var slip := atan2(flat.dot(fwd.cross(up)), flat.dot(fwd))
	var max_slip := deg_to_rad(t.drift_max_slip_deg)
	var w := angular_velocity.dot(up)
	var target := 0.0
	var gain := 0.0
	var limit := t.drift_assist_accel
	if _handbrake_blend > 0.2:
		target = clampf(-steer_in * deg_to_rad(t.drift_target_slip_deg), -max_slip, max_slip)
		gain = _handbrake_blend
	# garde anti tete-a-queue : derive PREVUE a 0,3 s (un choc lance la rotation
	# trop vite pour attendre la limite), autorite plus forte
	var predicted := slip + (w - path_rate) * 0.3
	if absf(predicted) > max_slip:
		target = signf(predicted) * max_slip
		gain = 1.0
		limit = t.spin_guard_accel
	if gain <= 0.0:
		return
	var desired_w := path_rate + t.drift_assist_gain * (target - slip)
	var alpha := clampf((desired_w - w) * 8.0, -limit, limit) * gain
	apply_torque(up * alpha * t.inertia_yaw_kgm2)


func _update_boost(t: VehicleTuning) -> void:
	var pressed := _input.boost
	if _boost_ticks > 0:
		_boost_ticks -= 1
	elif _boost_charge < 1.0:
		_boost_charge = minf(1.0, _boost_charge + 1.0 / t.boost_recharge_ticks)
	if pressed and not _boost_was_pressed and _boost_charge >= 1.0 and _boost_ticks == 0:
		_boost_ticks = roundi(t.boost_duration_ticks)
		_boost_charge = 0.0
		boosted.emit()
	_boost_was_pressed = pressed


# --- remorque articulee --------------------------------------------------------

## Angle de consigne : la remorque chasse vers l'exterieur du virage
## (acceleration laterale du tracteur) et plus encore en derapage (angle de
## derive). Elle le suit comme un ressort amorti avec sa propre inertie de
## lacet : un coup de volant sec la laisse d'abord en arriere, puis elle
## balaie vers l'exterieur et depasse sa consigne (effet de balancier). Angle
## borne a +/- trailer_max_angle_deg. Un mur l'arrete ; un adversaire touche
## en plein balayage recoit un choc (_shove).
func _update_trailer(up: Vector3, com: Vector3, v_fwd: float, right: Vector3) -> void:
	var t := tuning
	var dt := 1.0 / Engine.physics_ticks_per_second
	var w := angular_velocity.dot(up)          # lacet du tracteur, > 0 a gauche
	var max_a := deg_to_rad(t.trailer_max_angle_deg)
	# acceleration laterale REELLE (variation de vitesse), pas v x lacet : en
	# rattrapage de derapage, le camion tourne sur lui-meme sans que sa
	# trajectoire tourne autant. Filtree (~0,1 s) : un choc ne fouette pas.
	if _accel_ready:
		var accel := (linear_velocity - _prev_velocity) / dt
		_lat_accel = lerpf(_lat_accel, -accel.dot(right), 1.0 - exp(-dt / 0.1))
	_prev_velocity = linear_velocity
	_accel_ready = true
	var target := 0.0
	if _grounded > 0 and v_fwd > t.trailer_min_speed_ms:
		# virage a gauche : acceleration vers la gauche, l'exterieur est a
		# droite, angle > 0
		var slip := atan2(linear_velocity.dot(right), v_fwd)   # > 0 : vitesse a droite du cap
		target = deg_to_rad(t.trailer_sweep_deg_per_g) * _lat_accel / TruckSpec.GRAVITY 				+ t.trailer_drift_sweep_ratio * slip
		target = clampf(target, -max_a, max_a)
	var wn := TAU * t.trailer_frequency_hz
	var rel := _trailer_yaw_rate - w
	_trailer_yaw_rate += (-wn * wn * (_trailer_angle - target) - 2.0 * t.trailer_damping_ratio * wn * rel) * dt
	rel = _trailer_yaw_rate - w
	var angle := _trailer_angle + rel * dt
	if absf(angle) > max_a:
		angle = signf(angle) * max_a
		rel = 0.0
	# un mur arrete le balayage ; deja contre un mur, la remorque se replie
	if absf(angle - _trailer_angle) > 1e-5 and _trailer_hits(angle, 1 << (TruckSpec.LAYER_WORLD - 1)):
		if _trailer_hits(_trailer_angle, 1 << (TruckSpec.LAYER_WORLD - 1)):
			angle = move_toward(_trailer_angle, 0.0, deg_to_rad(t.trailer_wall_fold_deg_per_tick))
		else:
			angle = _trailer_angle
		rel = 0.0
	if absf(rel) > 0.3:
		rel = _shove(angle, rel, up, com)
	_trailer_yaw_rate = w + rel
	_trailer_rel_rate = rel
	_set_trailer_angle(angle)


## Remorque balayant un adversaire : la caisse ne connait pas de vitesse propre
## pour le solveur (elle pivote dans le corps), on donne donc le choc a la main,
## le long du balayage, au centre de masse de l'adversaire (pas de couple : il
## glisse, il ne se couche pas). Retourne la vitesse de balayage restante.
func _shove(angle: float, rel: float, up: Vector3, com: Vector3) -> float:
	var t := tuning
	_trailer_query.transform = global_transform * trailer_local_transform(angle)
	_trailer_query.collision_mask = 1 << (TruckSpec.LAYER_VEHICLE - 1)
	var hits := get_world_3d().direct_space_state.intersect_shape(_trailer_query, 4)
	if hits.is_empty():
		return rel
	var now := Engine.get_physics_frames()
	var tb := global_basis * Basis(Vector3.UP, angle)
	var kingpin := global_transform * TruckSpec.KINGPIN
	var reach := TruckSpec.TRAILER_CENTER.z + TruckSpec.TRAILER_SIZE.z / 2.0 - TruckSpec.KINGPIN.z
	for h: Dictionary in hits:
		var other := h["collider"] as Truck
		if other == null or other == self:
			continue
		# un choc par adversaire et par balayage, pas une rafale
		var last: int = _shove_ticks.get(other.get_instance_id(), -100000)
		if now - last < roundi(t.trailer_shove_cooldown_ticks):
			continue
		var along := clampf((other.global_position - kingpin).dot(tb.z), 0.0, reach)
		var point := kingpin + tb.z * along
		var dir := tb.x * signf(rel)
		dir = (dir - up * dir.dot(up)).normalized()
		if (other.global_position - point).dot(dir) <= 0.0:
			continue   # l'adversaire n'est pas du cote balaye
		var v_sweep := absf(rel) * along
		var v_sep := (other.linear_velocity - _point_velocity(point, com)).dot(dir)
		if v_sweep - v_sep <= 1.5:
			continue   # frottement cote a cote : le solveur s'en charge
		var m_red := mass * other.mass / (mass + other.mass)
		var j := minf(m_red * (v_sweep - v_sep) * (1.0 + t.trailer_shove_restitution),
				other.mass * t.trailer_shove_max_dv_ms)
		_shove_ticks[other.get_instance_id()] = now
		other.apply_central_impulse(dir * j)
		apply_central_impulse(-dir * j * t.trailer_shove_reaction)
		trailer_shoved.emit(other, j)
		rel *= 0.3   # la remorque est freinee par le choc
	return rel


## Vrai si la caisse de remorque, a cet angle, touche un corps de `mask`.
func _trailer_hits(angle: float, mask: int) -> bool:
	_trailer_query.transform = global_transform * trailer_local_transform(angle)
	_trailer_query.collision_mask = mask
	return not get_world_3d().direct_space_state.intersect_shape(_trailer_query, 1).is_empty()


## Pose la caisse de collision a l'angle donne. Jolt reconstruit la forme du
## corps a chaque changement : on ne le fait qu'au-dela d'un centieme de degre.
func _set_trailer_angle(angle: float) -> void:
	_trailer_angle = angle
	if _trailer_shape != null and absf(angle - _trailer_applied) > 1.7e-4:
		_trailer_applied = angle
		_trailer_shape.transform = trailer_local_transform(angle)


## En l'air : ressort angulaire amorti critiquement vers l'horizontale (sans
## seuil, plus doux que l'anti-retournement), et lacet pilote au stick vers une
## vitesse de consigne, a acceleration bornee. Le camion retombe a plat, dans
## la direction choisie.
func _apply_air_control(up: Vector3, steer_in: float) -> void:
	var t := tuning
	var alpha := Vector3.ZERO
	var body_up := up.normalized()
	var axis := body_up.cross(Vector3.UP)
	var tilt := body_up.angle_to(Vector3.UP)
	if axis.length_squared() > 1e-8:
		axis = axis.normalized()
		var k := t.air_level_strength
		if _jump_assist_ticks > 0:
			k *= t.jump_air_level_factor
		alpha += axis * (k * tilt - 2.0 * sqrt(k) * angular_velocity.dot(axis))
	# lacet : stick a droite = rotation horaire vue de dessus = -Y
	var target_yaw := -steer_in * deg_to_rad(t.air_yaw_rate_deg_s)
	var dt := 1.0 / Engine.physics_ticks_per_second
	alpha.y += clampf((target_yaw - angular_velocity.y) / dt, -t.air_control_accel, t.air_control_accel)
	var inertia := get_inverse_inertia_tensor().inverse()
	apply_torque(inertia * alpha)


## Rayons de suspension (vert au sol, gris en l'air), contacts, charge de
## chaque roue, force de pneu, centre de masse. Aucune allocation.
func _draw_debug(up: Vector3, com: Vector3) -> void:
	for i in 4:
		var p := _probes[i]
		var anchor := p.global_position
		var hub := anchor - up * p.hub_distance
		if p.in_contact:
			DebugDraw.line(anchor, hub, Color.GREEN, DebugDraw.CH_SUSPENSION)
			DebugDraw.point(p.contact_point, 0.3, Color.WHITE, DebugDraw.CH_SUSPENSION)
			DebugDraw.arrow(p.contact_point, p.contact_normal * p.load_n * DRAW_FORCE_SCALE,
				Color.CYAN, DebugDraw.CH_SUSPENSION)
			DebugDraw.arrow(p.contact_point, _tire_force[i] * DRAW_FORCE_SCALE,
				Color.RED, DebugDraw.CH_FORCES)
		else:
			DebugDraw.line(anchor, hub, Color.GRAY, DebugDraw.CH_SUSPENSION)
	DebugDraw.point(com, 0.6, Color.YELLOW, DebugDraw.CH_COM)


## Au sol : ramene l'inclinaison sous le seuil par un ressort angulaire amorti
## critiquement. La reference est le sol sous les roues quand 3 roues touchent,
## sinon la verticale. Couple = inertie * acceleration angulaire : l'aide ne
## depend pas de la masse du camion.
func _apply_anti_roll(up: Vector3, fwd: Vector3) -> void:
	var t := tuning
	var ref := Vector3.UP
	if _grounded >= 3:
		var n_sum := Vector3.ZERO
		for p in _probes:
			if p.in_contact:
				n_sum += p.contact_normal
		ref = n_sum.normalized()
	var body_up := up.normalized()
	var excess := body_up.angle_to(ref) - deg_to_rad(t.anti_roll_threshold_deg)
	if excess <= 0.0:
		return
	var axis := body_up.cross(ref)
	if axis.length_squared() < 1e-8:
		axis = fwd   # completement retourne : n'importe quel axe horizontal convient
	axis = axis.normalized()
	var w_righting := angular_velocity.dot(axis)
	var alpha := t.anti_roll_strength * excess - 2.0 * sqrt(t.anti_roll_strength) * w_righting
	var inertia := get_inverse_inertia_tensor().inverse()
	apply_torque(inertia * (axis * alpha))


func _point_velocity(p: Vector3, com: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(p - com)


## Angle de braquage qui fait tourner a la limite d'adherence a la vitesse
## v_fwd, multiplie par steer_grip_ratio (tache 1.5).
func _grip_steer_deg(v_fwd: float) -> float:
	var v2 := maxf(v_fwd * v_fwd, 1.0)
	var t := tuning
	return rad_to_deg(atan(_wheelbase * t.lateral_grip_g * TruckSpec.GRAVITY / v2)) * t.steer_grip_ratio


## Braquage max au plein stick a la vitesse actuelle, hors derive (deg).
## Lecture seule : sert a un pilote (IA, test) a doser son stick.
func get_max_steer_deg() -> float:
	return minf(tuning.max_steer_deg, _grip_steer_deg(get_speed_kmh() / 3.6))
