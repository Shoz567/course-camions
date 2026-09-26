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
##
## Interface avec le gameplay (gameplay-engineer.md), la seule autorisee :
##   set_input(frame), reset_to(xf), get_speed_kmh(), is_upside_down(),
##   wheels_on_ground()
## Le camion ne lit jamais Input.* : il recoit une InputFrame.

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

## Derniere consigne recue. Copiee, jamais partagee avec la source.
var _input: InputFrame = InputFrame.new()
var _probes: Array[WheelProbe] = []
var _wheel_visuals: Array[Node3D] = []
var _wheel_bases: Array[Basis] = []
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

var _reset_pending: bool = false
var _reset_xf: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	for n in TruckSpec.PROBE_NAMES:
		_probes.append(get_node(NodePath(n)) as WheelProbe)
	for n in TruckSpec.WHEEL_NAMES:
		var v := get_node_or_null(NodePath("Visual/%s" % n)) as Node3D
		_wheel_visuals.append(v)
		_wheel_bases.append(v.transform.basis if v != null else Basis.IDENTITY)
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


# --- simulation ------------------------------------------------------------------

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _reset_pending:
		return
	_reset_pending = false
	state.transform = _reset_xf
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO


func _physics_process(_delta: float) -> void:
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
	if debug_steering:
		var v2 := maxf(v_fwd * v_fwd, 1.0)
		var grip_deg := rad_to_deg(atan(_wheelbase * t.lateral_grip_g * TruckSpec.GRAVITY / v2))
		var max_deg := minf(t.max_steer_deg, grip_deg * t.steer_grip_ratio)
		target_deg = clampf(_input.steer, -1.0, 1.0) * max_deg
	_steer_deg = move_toward(_steer_deg, target_deg, t.steer_rate_deg_per_tick)
	var steer_rad := deg_to_rad(_steer_deg)

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
			# sous la vitesse max ; les resistances sont compensees.
			var taper := clampf((_top_speed_ms - v_fwd) / _taper_ms, 0.0, 1.0)
			drive = thr * (t.engine_accel_ms2 * taper + resist)
	if brk > 0.0:
		if v_fwd > STOP_SPEED_MS:
			braking = maxf(braking, brk)
		elif thr <= 0.0:
			var taper_r := clampf((_reverse_top_ms + v_fwd) / _taper_ms, 0.0, 1.0)
			drive = -brk * (t.reverse_accel_ms2 * taper_r + resist)
	if not debug_drive:
		drive = 0.0
		braking = 0.0

	var m_wheel := mass / 4.0
	for i in 4:
		var p := _probes[i]
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
			fs = maxf(_k * (_free_length[i] - p.hub_distance) - _c * v_up, 0.0)
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
		if debug_grip:
			var v_ref := maxf(absf(v_long), _min_ref_speed) * _tan_slip
			f_lat = -t.lateral_grip_g * p.surface_grip * fs * clampf(v_lat / v_ref, -1.0, 1.0)

		# 1.4 longitudinal : 4 roues motrices, forces proportionnelles a la masse.
		var f_long := drive * m_wheel
		if debug_drive:
			var sat := clampf(v_long / t.grip_saturation_speed_ms, -1.0, 1.0)
			f_long -= (braking * t.brake_decel_ms2 + t.rolling_resistance_ms2) * m_wheel * sat

		apply_force(s_dir * f_lat + f_dir * f_long, p.contact_point - origin)

	# 1.4 trainee aerodynamique, explicite (linear_damp = 0, SPIKE A10).
	if debug_drag:
		apply_central_force(-linear_velocity * linear_velocity.length() * t.aero_drag_per_m * mass)

	# 1.6 anti-retournement (prioritaire : les camions se percutent souvent).
	if debug_anti_roll:
		_apply_anti_roll(up, fwd)


## Ramene l'inclinaison sous le seuil par un ressort angulaire amorti
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


# --- visuel ------------------------------------------------------------------------

## Les roues suivent les rayons : debattement et braquage. Purement visuel.
func _process(_delta: float) -> void:
	for i in 4:
		var v := _wheel_visuals[i]
		if v == null:
			continue
		var a := TruckSpec.ANCHORS[i]
		v.position = Vector3(a.x, a.y - _probes[i].hub_distance, a.z)
		var b := _wheel_bases[i]
		if i < 2:
			b = Basis(Vector3.UP, -deg_to_rad(_steer_deg)) * b
		v.transform.basis = b
