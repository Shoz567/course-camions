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
##       au sol ; en l'air : le nez suit la trajectoire, alignement sur le sol
##       a l'approche de l'impact, lacet au stick
##   1.9 traces DebugDraw : rayons, contacts, forces, centre de masse
##   boost : poussee et vitesse max relevees pendant boost_duration_ticks, puis
##       jauge rechargee en boost_recharge_ticks (declenche a l'appui)
##   plaques : boost de plaque (coup de pouce immediat + vitesse max relevee),
##       saut de plaque (impulsion verticale, chute freinee progressivement a
##       l'approche du sol, suspension plus amortie a la reception)
##   remorque articulee : la caisse de la remorque pivote autour de la sellette
##       (VEHICLE_SPEC §5 bis), avec sa propre inertie de lacet. Elle chasse
##       vers l'exterieur en virage et en derapage, s'arrete contre les murs,
##       et balaie les adversaires qu'elle touche.
##   anti-collage : apres wall_unstick_ticks de frottement continu contre un
##       mur, -25 % de vitesse et une impulsion vers l'interieur de la piste
##       (normale du mur) : le camion ne reste jamais aimante a la glissiere.
##   remorque detachee (detach_trailer) : sa caisse de collision est coupee,
##       le tracteur seul est plus rapide, plus vif et plus nerveux jusqu'a ce
##       qu'elle se raccroche (reattach_trailer) ;
##   remorque larguee percutee (cargo_hit) : ralenti et deporte en lacet.
##   impacts contre un mur (wall_impact) : signales avec la vitesse normale et
##       la forme touchee (tracteur ou remorque) ; les PV sont l'affaire du
##       gameplay (TruckHealth). Chocs contre un obstacle de la piste
##       (hazard_impact) : idem. Epave (set_wrecked) : gelee, sans force,
##       sans collision.
##
## Interface avec le gameplay (gameplay-engineer.md), la seule autorisee :
##   set_input(frame), reset_to(xf), get_speed_kmh(), is_upside_down(),
##   wheels_on_ground(), pad_boost(), jump_pad_launch(), cargo_hit(),
##   detach_trailer(), reattach_trailer(), set_wrecked(), set_trailer_type()
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
## Vient de percuter une remorque larguee.
signal cargo_hit_taken
## Vient d'etre ralenti par la piste (flaque, panneau percute...).
signal slowed_down
## Glissade declenchee par une flaque d'eau (effet savonnette).
signal puddle_slipped(ticks: int)
## La remorque vient d'etre detachee / raccrochee.
signal trailer_detached
signal trailer_reattached
## Debut d'un contact avec un mur (glissiere) : vitesse normale a l'impact
## (m/s, vers le mur) et partie touchee (remorque, ou tracteur). Les degats
## sont l'affaire du gameplay (TruckHealth).
signal wall_impact(normal_speed_ms: float, on_trailer: bool)
## Le meme impact, avec le point de contact et la normale du mur (monde,
## tournee vers le camion) : pour les traces de choc (TruckDamageFx).
signal wall_impact_at(normal_speed_ms: float, on_trailer: bool, point: Vector3, normal: Vector3)
## Debut d'un contact avec un autre corps mobile (camion, remorque larguee) :
## vitesse d'approche, partie touchee, point et normale (monde, tournee vers
## le camion). Purement informatif : aucun degat de PV.
signal body_impact(approach_ms: float, on_trailer: bool, point: Vector3, normal: Vector3)
## Le meme debut de contact, quand l'autre corps est un obstacle de la piste
## (couche 5 : remorque larguee, epave) : c'est lui qui fait des degats
## (TruckHealth).
signal hazard_impact(obstacle: Node3D, approach_ms: float, on_trailer: bool, point: Vector3, normal: Vector3)

## Ce qui empeche la caisse de remorque de reapparaitre : decor, camions,
## obstacles (couche 5, remorques larguees, VEHICLE_SPEC §7).
const TRAILER_BLOCK_MASK := (1 << (TruckSpec.LAYER_WORLD - 1)) | (1 << (TruckSpec.LAYER_VEHICLE - 1)) \
		| (1 << (5 - 1))
## Couche 5 `hazard` (VEHICLE_SPEC §7) : obstacles poses sur la piste.
const HAZARD_BIT := 1 << (5 - 1)

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
## Anti tete-a-queue : derive prevue au-dela de drift_max_slip_deg ramenee.
@export var debug_spin_guard: bool = true
## Drift : force laterale commandee au stick, la trajectoire suit le virage.
@export var debug_drift_carve: bool = true
@export var debug_air_control: bool = true
## Saut de plaque : chute freinee progressivement a l'approche du sol.
@export var debug_landing_cushion: bool = true
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
## En l'air : rayon vertical tire depuis le centre de masse, pour estimer
## l'impact (ticks restants, hauteur des roues au-dessus du sol vise, normale du
## sol vise). INF = aucun sol en vue, ou camion qui monte.
var _ground_ray: RayCast3D
var _ticks_to_impact: float = INF
var _ground_d: float = INF
var _ground_normal: Vector3 = Vector3.UP
const GROUND_RAY_LENGTH := 60.0
var _gravity: float = 9.8
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
## Remorque larguee (pouvoir cargo) : tracteur seul.
var _trailer_detached: bool = false
## Remorque raccrochee alors que sa place etait prise : caisse de collision
## coupee (« fantome ») jusqu'a ce que la place se libere.
var _trailer_ghost: bool = false
## Ralentissement impose par la piste : facteur immediat en attente, puis
## deceleration supplementaire pendant quelques ticks.
var _slow_factor_pending: float = 1.0
var _slow_ticks: int = 0
var _slow_decel: float = 0.0
## Perte d'adherence laterale temporaire (flaque savonnette)
var _slip_ticks: int = 0
var _trailer_shape: CollisionShape3D
var _trailer_query: PhysicsShapeQueryParameters3D
## Remorque choisie (null : celle du modele, caisse de TruckSpec) et sa caisse.
var trailer_type: TrailerType
var trailer_box_size: Vector3 = TruckSpec.TRAILER_SIZE
var trailer_box_center: Vector3 = TruckSpec.TRAILER_CENTER

## Mur touche au dernier pas physique (lu dans _integrate_forces) : normale
## moyenne, horizontale, tournee vers le camion. ZERO = aucun mur.
var _wall_normal: Vector3 = Vector3.ZERO
## Ticks de frottement continu contre un mur, ticks sans contact depuis.
var _wall_ticks: int = 0
var _wall_gap: int = 0
## Caisse de cargo percutee : position de la caisse, choc a appliquer.
var _cargo_hit_pending: bool = false
var _cargo_hit_from: Vector3 = Vector3.ZERO

## Impacts contre un mur : un nouveau contact apres WALL_IMPACT_GAP_TICKS sans
## contact, separement pour le tracteur et pour la remorque. Vitesse avant les
## derniers pas (le choc a deja freine le camion quand le contact est lu).
const WALL_IMPACT_GAP_TICKS := 12
var _front_wall_gap: int = WALL_IMPACT_GAP_TICKS + 1
var _trailer_wall_gap: int = WALL_IMPACT_GAP_TICKS + 1
var _vel_hist: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
## Contacts avec des corps mobiles : id du corps -> dernier pas de contact.
var _body_contacts: Dictionary = {}
var _contact_step: int = 0
## Epave (0 PV, TruckHealth) : gelee, aucune force, aucune commande.
var _wrecked: bool = false
var _layers_before_wreck: Vector2i = Vector2i.ZERO

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
	# Rayon d'estimation de l'impact : interroge a la demande (force_raycast_update),
	# jamais automatiquement ; RayCast3D plutot qu'intersect_ray, qui allouerait
	# un dictionnaire a chaque tick (CLAUDE.md §5).
	_ground_ray = RayCast3D.new()
	_ground_ray.name = "GroundRay"
	_ground_ray.position = TruckSpec.CENTER_OF_MASS
	_ground_ray.enabled = false
	_ground_ray.collision_mask = 1 << (TruckSpec.LAYER_WORLD - 1)
	_ground_ray.add_exception(self)
	add_child(_ground_ray)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity")) * gravity_scale
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
	_slip_ticks = 0


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


## Remorque detachee : pose monde de la remorque (repere de la sellette,
## articulation comprise), pour poser la remorque larguee au meme endroit. La
## caisse de collision est coupee ; le tracteur roule seul.
func detach_trailer() -> Transform3D:
	var xf := global_transform * Transform3D(Basis(Vector3.UP, _trailer_angle), TruckSpec.KINGPIN)
	_trailer_detached = true
	_trailer_yaw_rate = 0.0
	_set_trailer_angle(0.0)
	if _trailer_shape != null:
		_trailer_shape.disabled = true
	trailer_detached.emit()
	return xf


## Raccroche la remorque (dans l'axe). Refuse (faux) si sa caisse toucherait
## un mur, un camion ou un obstacle (remorque larguee d'un adversaire) : on
## reessaie au tick suivant. Force : raccrochee quand meme, mais sa caisse de
## collision reste coupee tant que la place est prise (_trailer_ghost). Avant
## le 2026-10-01, elle apparaissait dans l'obstacle et le solveur projetait
## les deux corps (truck_reattach_test).
func reattach_trailer(force: bool = false) -> bool:
	if not _trailer_detached:
		return true
	var blocked := _trailer_shape != null and _trailer_hits(0.0, TRAILER_BLOCK_MASK)
	if blocked and not force:
		return false
	_trailer_detached = false
	_trailer_ghost = blocked
	if _trailer_shape != null and not blocked:
		_trailer_shape.disabled = false
	trailer_reattached.emit()
	return true


## Vrai si la remorque est raccrochee mais encore sans collision (place prise).
func is_trailer_ghost() -> bool:
	return _trailer_ghost


func is_trailer_detached() -> bool:
	return _trailer_detached


## Remorque larguee percutee (DetachedTrailer) : au prochain tick, vitesse
## reduite a cargo_hit_speed_factor et coup de lacet du cote de l'obstacle.
## Ralentissement impose par la piste (flaque d'eau, panneau percute) : au
## prochain tick, vitesse horizontale x speed_factor, puis extra_decel_ms2 de
## freinage pendant `ticks`. Le plus fort des ralentissements en attente gagne.
func apply_slowdown(speed_factor: float, ticks: int, extra_decel_ms2: float) -> void:
	_slow_factor_pending = minf(_slow_factor_pending, clampf(speed_factor, 0.0, 1.0))
	_slow_ticks = maxi(_slow_ticks, ticks)
	_slow_decel = maxf(_slow_decel, extra_decel_ms2)


## Perte d'adherence laterale (flaque savonnette) : le camion glisse sans
## perte de vitesse longitudinale, deteriorant le controle du joueur.
func apply_puddle_slip(ticks: int = 60) -> void:
	var first := _slip_ticks == 0
	_slip_ticks = maxi(_slip_ticks, ticks)
	puddle_slipped.emit(_slip_ticks)
	if first:
		var xf := global_transform
		var up := xf.basis.y
		var v_fwd := linear_velocity.dot(-xf.basis.z)
		if absf(v_fwd) > 2.0:
			var kick_dir := 1.0 if (int(Engine.get_physics_frames()) % 2 == 0) else -1.0
			apply_torque_impulse(up * kick_dir * mass * 0.8)


func is_slipping() -> bool:
	return _slip_ticks > 0


func cargo_hit(crate_position: Vector3) -> void:
	_cargo_hit_pending = true
	_cargo_hit_from = crate_position


## Ticks de frottement continu contre un mur (0 = libre).
func get_wall_contact_ticks() -> int:
	return _wall_ticks


## Epave (0 PV) : gelee sur place, plus aucune force ni commande, jusqu'a ce
## que le gameplay la relance (set_wrecked(false) puis reset_to). Elle ne
## touche plus rien : la carcasse laissee sur la route est un obstacle a part
## (TruckWreck), le camion attend seulement sa reapparition.
func set_wrecked(on: bool) -> void:
	if on and not _wrecked:
		_layers_before_wreck = Vector2i(collision_layer, collision_mask)
		collision_layer = 0
		collision_mask = 0
	elif not on and _wrecked:
		collision_layer = _layers_before_wreck.x
		collision_mask = _layers_before_wreck.y
	_wrecked = on
	freeze = on
	_boost_ticks = 0
	_pad_boost_ticks = 0
	_pad_kick_pending = false
	_slip_ticks = 0
	_slow_ticks = 0
	_slow_factor_pending = 1.0


func is_wrecked() -> bool:
	return _wrecked


## Vitesses au debut des trois derniers pas physiques, la plus recente en
## tete : au moins l'une d'elles precede un choc qu'on vient de lire.
func get_recent_velocities() -> PackedVector3Array:
	return _vel_hist


## Angle de la remorque par rapport au tracteur (rad), > 0 : arriere de la
## remorque vers la droite du tracteur.
func get_trailer_angle() -> float:
	return _trailer_angle


func get_trailer_angle_deg() -> float:
	return rad_to_deg(_trailer_angle)


## Pose de la caisse de remorque dans le repere du camion, pour un angle donne :
## rotation en lacet autour de la sellette. `center` : centre de la caisse au
## repos (celui de la remorque choisie, TrailerType.box_center).
static func trailer_local_transform(angle: float, center: Vector3 = TruckSpec.TRAILER_CENTER) -> Transform3D:
	var b := Basis(Vector3.UP, angle)
	return Transform3D(b, TruckSpec.KINGPIN + b * (center - TruckSpec.KINGPIN))


## Remorque choisie (sas READY) : sa caisse de collision remplace celle du
## camion. A appeler camion a l'arret, remorque accrochee (avant le depart). Le
## reglage de conduite (TrailerType.apply_to) est l'affaire de la course.
func set_trailer_type(type: TrailerType) -> void:
	trailer_type = type
	trailer_box_size = type.box_size if type != null else TruckSpec.TRAILER_SIZE
	trailer_box_center = type.box_center if type != null else TruckSpec.TRAILER_CENTER
	if _trailer_shape == null:
		return
	# la forme vient de truck.tscn, partagee par tous les camions : copie propre
	var box := (_trailer_shape.shape as BoxShape3D).duplicate() as BoxShape3D
	box.size = trailer_box_size
	_trailer_shape.shape = box
	_trailer_query.shape = box
	_trailer_applied = _trailer_angle
	_trailer_shape.transform = trailer_local_transform(_trailer_angle, trailer_box_center)


# --- simulation ------------------------------------------------------------------

## Contact avec un corps mobile : au debut d'un contact (apres
## WALL_IMPACT_GAP_TICKS sans), signale body_impact.
func _note_body_contact(state: PhysicsDirectBodyState3D, i: int, obj: Object, at: Vector3) -> void:
	var id := state.get_contact_collider_id(i)
	var last: int = _body_contacts.get(id, -1000)
	_body_contacts[id] = _contact_step
	if _contact_step - last <= WALL_IMPACT_GAP_TICKS or obj == self:
		return
	var n := state.get_contact_local_normal(i)
	if n.dot(state.transform.origin - at) < 0.0:
		n = -n
	n = n.normalized()
	var other := state.get_contact_collider_velocity_at_position(i)
	var approach := 0.0
	for v in _vel_hist:
		approach = maxf(approach, (other - v).dot(n))
	var shape_node := shape_owner_get_owner(shape_find_owner(state.get_contact_local_shape(i)))
	body_impact.emit(approach, shape_node == _trailer_shape, at, n)
	var body := obj as CollisionObject3D
	if body != null and body.collision_layer & HAZARD_BIT:
		hazard_impact.emit(body, approach, shape_node == _trailer_shape, at, n)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# contacts avec un mur : corps statique, normale presque horizontale (le
	# sol et les rampes ont une normale verticale)
	var n_sum := Vector3.ZERO
	# impacts : vitesse vers le mur, pour le tracteur et pour la remorque (et
	# le point du contact le plus violent de chacun)
	var front := -1.0
	var rear := -1.0
	var front_at := Vector3.ZERO
	var rear_at := Vector3.ZERO
	var front_n := Vector3.ZERO
	var rear_n := Vector3.ZERO
	_contact_step += 1
	for i in state.get_contact_count():
		var obj := state.get_contact_collider_object(i)
		var at := state.get_contact_local_position(i)
		if obj is RigidBody3D:
			_note_body_contact(state, i, obj, at)
			continue
		if not (obj is StaticBody3D):
			continue
		var n := state.get_contact_local_normal(i)
		if absf(n.y) > 0.6:
			continue
		n.y = 0.0
		if n.dot(state.transform.origin - at) < 0.0:
			n = -n
		n = n.normalized()
		n_sum += n
		var into := 0.0
		for v in _vel_hist:
			into = maxf(into, -v.dot(n))
		var shape_node := shape_owner_get_owner(shape_find_owner(state.get_contact_local_shape(i)))
		if shape_node == _trailer_shape:
			if into > rear:
				rear = into
				rear_at = at
				rear_n = n
		elif into > front:
			front = into
			front_at = at
			front_n = n
	_wall_normal = n_sum.normalized() if n_sum.length_squared() > 1e-6 else Vector3.ZERO
	if front >= 0.0 and _front_wall_gap > WALL_IMPACT_GAP_TICKS:
		wall_impact.emit(front, false)
		wall_impact_at.emit(front, false, front_at, front_n)
	if rear >= 0.0 and _trailer_wall_gap > WALL_IMPACT_GAP_TICKS:
		wall_impact.emit(rear, true)
		wall_impact_at.emit(rear, true, rear_at, rear_n)
	_front_wall_gap = 0 if front >= 0.0 else _front_wall_gap + 1
	_trailer_wall_gap = 0 if rear >= 0.0 else _trailer_wall_gap + 1
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
	# vitesses au debut des derniers pas : la plus recente en tete
	_vel_hist[2] = _vel_hist[1]
	_vel_hist[1] = _vel_hist[0]
	_vel_hist[0] = linear_velocity
	if not _active or _wrecked:
		return

	var xf := global_transform
	var origin := xf.origin
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var com := xf * center_of_mass
	var v_fwd := linear_velocity.dot(fwd)
	var t := tuning
	# tracteur seul (remorque larguee) : plus leger, plus rapide, plus vif
	var top_ms := _top_speed_ms * (t.solo_top_speed_factor if _trailer_detached else 1.0)
	var accel_k := t.solo_accel_factor if _trailer_detached else 1.0

	# 1.6 frein a main : engagement rapide, relacher plus lent (relance propre).
	var hb_target := 1.0 if (_input.handbrake and debug_handbrake) else 0.0
	var hb_step := 1.0 / (t.handbrake_engage_ticks if hb_target > _handbrake_blend else t.handbrake_release_ticks)
	_handbrake_blend = move_toward(_handbrake_blend, hb_target, hb_step)
	var rear_grip := lerpf(1.0, t.handbrake_rear_grip_factor, _handbrake_blend)

	# 1.5 direction : l'angle max diminue avec la vitesse, borne par l'angle
	# qui fait tourner a la limite d'adherence (tout le stick reste utile), sans
	# descendre sous steer_floor_deg (direction jamais figee a haute vitesse),
	# et les roues tournent a vitesse bornee (pas de coup de volant instantane).
	var target_deg := 0.0
	var steer_in := clampf(_input.steer, -1.0, 1.0)
	if debug_steering:
		var max_deg := maxf(_grip_steer_deg(v_fwd), t.steer_floor_deg) 				* (t.solo_steer_factor if _trailer_detached else 1.0)
		# 1.6 contre-braquage permissif : du cote ou glisse le camion, la limite
		# s'elargit de l'angle de derive. Les roues avant peuvent toujours
		# s'aligner sur la trajectoire, et un derapage se rattrape au stick.
		var v_right := linear_velocity.dot(xf.basis.x)
		var slip_deg := 0.0   # > 0 : la vitesse part a droite du cap
		if v_fwd > STOP_SPEED_MS:
			slip_deg = rad_to_deg(atan2(v_right, v_fwd))
		if steer_in * slip_deg > 0.0:
			max_deg += absf(slip_deg)
		# drift au frein a main : train avant debride jusqu'a drift_steer_deg,
		# des deux cotes (jamais moins qu'hors drift). Le joueur inscrit le nez
		# vers la corde, et la traction des roues avant (4 roues motrices,
		# poussee dans l'axe de chaque roue) tire vers l'interieur. Au-dela de
		# ~16 deg, les roues avant freinent en travers : le drift perd son elan.
		max_deg = lerpf(max_deg, maxf(max_deg, t.drift_steer_deg), _handbrake_blend)
		target_deg = steer_in * minf(t.max_steer_deg, max_deg)
		# contre-braquage automatique, stick au neutre : relance propre
		target_deg += (1.0 - absf(steer_in)) * t.auto_countersteer_ratio * slip_deg
		target_deg = clampf(target_deg, -t.max_steer_deg, t.max_steer_deg)
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
			# sous la vitesse max ; les resistances sont compensees jusqu'a la
			# vitesse max, pas au-dela : apres un boost, le camion y redescend.
			var taper := clampf((top_ms - v_fwd) / _taper_ms, 0.0, 1.0)
			drive = thr * (t.engine_accel_ms2 * accel_k * taper + (resist if v_fwd <= top_ms else 0.0))
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
			var kick := clampf(top_ms + _pad_boost_extra_ms - v_fwd, 0.0, _pad_boost_extra_ms)
			apply_central_impulse(fwd * kick * mass)
	if boost_push > 0.0 and debug_boost and v_fwd > -STOP_SPEED_MS:
		var top_b := top_ms + boost_extra
		var taper_b := clampf((top_b - v_fwd) / _taper_ms, 0.0, 1.0)
		drive = (thr * t.engine_accel_ms2 * accel_k + boost_push) * taper_b + (resist if v_fwd <= top_b else 0.0)
		braking = 0.0 if brk <= 0.0 else braking
	elif v_fwd > top_ms and fwd.y > -0.03:
		# frein moteur au-dessus de la vitesse max (rampe sur 2 m/s : pas de
		# pompage autour de la vitesse max). Pas en descente : la gravite doit
		# pouvoir y emballer le camion.
		drive -= t.overspeed_decel_ms2 * clampf((v_fwd - top_ms) / 2.0, 0.0, 1.0)
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
	if _slow_factor_pending < 1.0:
		var flat := linear_velocity - up * linear_velocity.dot(up)
		apply_central_impulse(-flat * (1.0 - _slow_factor_pending) * mass)
		_slow_factor_pending = 1.0
		slowed_down.emit()
	if _slow_ticks > 0:
		_slow_ticks -= 1
		if v_fwd > 2.0:
			apply_central_force(-fwd * _slow_decel * mass)
		if _slow_ticks == 0:
			_slow_decel = 0.0
	if _slip_ticks > 0:
		_slip_ticks -= 1

	# saut de plaque : impulsion verticale ; a la reception (apres un vrai vol),
	# suspension plus amortie. La chute, elle, a ete freinee avant le contact
	# (_apply_landing_cushion).
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
			# La chute a deja ete freinee pendant l'approche (_apply_landing_cushion).
			# Plus de plafonnement instantane ici : il donnait 36,6 g en un tick.
			last_landing_fall_ms = -linear_velocity.y

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
			var bump := maxf(t.bump_stop_start_m - p.hub_distance, 0.0)
			fs = maxf(_k * (_free_length[i] - p.hub_distance + bump * t.bump_stop_stiffness_ratio)
				- damp * v_up, 0.0)
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
			if _slip_ticks > 0:
				mu *= 0.12 if rear else 0.22
			f_lat = -mu * fs * clampf(v_lat / v_ref, -1.0, 1.0)

		# 1.4 longitudinal : 4 roues motrices, forces proportionnelles a la masse.
		var f_long := drive * m_wheel
		if debug_drive:
			var decel := braking * t.brake_decel_ms2 + t.rolling_resistance_ms2
			if rear:
				# frein a main + gaz = drift, pas freinage : la deceleration du frein
				# a main s'efface avec l'accelerateur (2026-10-01, « le derapage
				# freine trop »)
				decel += _handbrake_blend * t.handbrake_decel_ms2 * (1.0 - _input.throttle)
			var sat := clampf(v_long / t.grip_saturation_speed_ms, -1.0, 1.0)
			f_long -= decel * m_wheel * sat

		_tire_force[i] = s_dir * f_lat + f_dir * f_long
		apply_force(_tire_force[i], p.contact_point - origin)

	# 1.4 trainee aerodynamique, explicite (linear_damp = 0, SPIKE A10).
	if debug_drag:
		apply_central_force(-linear_velocity * linear_velocity.length() * t.aero_drag_per_m * mass)

	# derapage maitrise : cible de derive au frein a main
	if debug_handbrake:
		_apply_drift_assist(t, up, fwd, steer_in, v_fwd)
		_apply_drift_momentum(t, up, fwd)
		if debug_drift_carve:
			_apply_drift_carve(t, up, fwd)

	# 1.6 au sol : anti-retournement (prioritaire : les camions se percutent
	# souvent). En l'air : assiette automatique et lacet au stick.
	if _grounded > 0:
		if debug_anti_roll:
			_apply_anti_roll(up, fwd)
	else:
		# gravite de vol : le complement au-dela de la gravite du projet
		apply_central_force(Vector3.DOWN * _gravity * (t.air_gravity_factor - 1.0) * mass)
		_update_landing_estimate()
		if debug_air_control:
			_apply_air_control(up, steer_in)
		if debug_landing_cushion:
			_apply_landing_cushion(t)

	# remorque articulee : angle de la caisse, murs, adversaires balayes
	if _trailer_shape != null and not _trailer_detached:
		if _trailer_ghost and not _trailer_hits(_trailer_angle, TRAILER_BLOCK_MASK):
			_trailer_ghost = false
			_trailer_shape.disabled = false
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


## Lancement du drift. La derive (angle entre le cap et la vitesse, > 0 :
## vitesse a droite du cap) varie comme lacet - rotation de la trajectoire ; au
## frein a main, on pousse donc le lacet vers une derive cible proportionnelle
## au braquage (drift_target_slip_deg au plein stick) : le nez pivote tout de
## suite. Acceleration angulaire bornee (drift_assist_accel).
## L'aide ne tient jamais l'angle (2026-10-01, « ne la bloque pas du tout ») :
## elle ne freine jamais la rotation et se coupe au-dela de la cible. Le joueur
## tient l'angle au stick et au contre-braquage, jusqu'a drift_max_slip_deg ;
## au-dela, la garde anti tete-a-queue reprend la main (_apply_spin_guard).
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
	var w := angular_velocity.dot(up)
	if debug_spin_guard and _apply_spin_guard(t, up, slip, w, path_rate):
		return
	if _handbrake_blend <= 0.2:
		return
	var target := -steer_in * deg_to_rad(t.drift_target_slip_deg)
	# deja au-dela de la cible, du meme cote (ou stick au neutre) : angle libre
	if slip * target >= 0.0 and absf(slip) >= absf(target):
		return
	var desired_w := path_rate + t.drift_assist_gain * (target - slip)
	var alpha := clampf((desired_w - w) * 8.0, -t.drift_assist_accel, t.drift_assist_accel) * _handbrake_blend
	# la derive suit lacet - trajectoire : pousser vers la cible, jamais freiner
	if alpha * (target - slip) <= 0.0:
		return
	apply_torque(up * alpha * t.inertia_yaw_kgm2)


## Anti tete-a-queue (remis le 2026-10-02 a la demande de l'utilisateur, apres
## son retrait la veille) : si la derive PREVUE a 0,3 s depasse
## drift_max_slip_deg (un choc lance la rotation trop vite pour attendre la
## limite), le lacet est ramene vers la limite, frein a main ou non, a
## spin_guard_accel. En dessous, l'angle reste libre : la garde ne tient pas
## le drift, elle empeche seulement le tete-a-queue. Vrai si elle a agi.
func _apply_spin_guard(t: VehicleTuning, up: Vector3, slip: float, w: float, path_rate: float) -> bool:
	var max_slip := deg_to_rad(t.drift_max_slip_deg)
	var predicted := slip + (w - path_rate) * 0.3
	if absf(predicted) <= max_slip:
		return false
	var desired_w := path_rate + t.drift_assist_gain * (signf(predicted) * max_slip - slip)
	var alpha := clampf((desired_w - w) * 8.0, -t.spin_guard_accel, t.spin_guard_accel)
	apply_torque(up * alpha * t.inertia_yaw_kgm2)
	return true


## Elan en drift : en derapage, les pneus « raclent » la vitesse (leur force
## laterale s'oppose en grande partie au mouvement des qu'ils glissent de
## 40 deg). On restitue drift_speed_keep de cette perte, le long de la
## trajectoire. Le camion glisse en gardant son elan : c'est l'usage des jeux
## de course arcade. Avant le 2026-10-01, un drift de 4 s a 90 km/h perdait
## 26 % de la vitesse.
##
## Engagement : le plus grand du frein a main et de la GLISSE elle-meme (de 0 a
## 10 deg de derive a 1 a 25 deg). La glisse compte aussi parce que la sortie
## du drift, frein a main relache, glisse encore a 50 deg : sans elle, le
## camion y perdait 39 % de sa vitesse. Un virage normal (< 10 deg) n'est pas
## concerne.
func _apply_drift_momentum(t: VehicleTuning, up: Vector3, fwd: Vector3) -> void:
	if _grounded < 2:
		return
	var flat := linear_velocity - up * linear_velocity.dot(up)
	var speed := flat.length()
	if speed < t.drift_min_speed_ms:
		return
	var slip := absf(atan2(flat.dot(fwd.cross(up)), flat.dot(fwd)))
	var engage := maxf(_handbrake_blend, smoothstep(deg_to_rad(10.0), deg_to_rad(25.0), slip))
	if engage <= 0.0:
		return
	var dir := flat / speed
	var scrub := 0.0
	for i in 4:
		scrub += _tire_force[i].dot(dir)
	if scrub < 0.0:
		apply_central_force(-dir * scrub * t.drift_speed_keep * engage)


## Courbe du drift (2026-10-01, « je me deporte contre la rambarde
## exterieure ») : la TRAJECTOIRE d'un drift ne courbe que de la force laterale
## des pneus qui glissent, ~0,75 g. Rayon r = v^2 / a : 237 m a 150 km/h, plus
## large que tous les virages du jeu. On ajoute jusqu'a drift_carve_g,
## perpendiculaire a la vitesse, vers le cote ou pointe le nez : la vitesse
## n'en change pas, seule la courbe se resserre.
## Dosee par l'ANGLE de glisse (pleine des drift_target_slip_deg), pas par le
## stick : depuis que l'angle est libre (2026-10-01), le joueur tient le drift
## en contre-braquant, et une force pilotee au stick se coupait justement la.
## Engagee par le frein a main, estompee sous drift_min_speed_ms.
func _apply_drift_carve(t: VehicleTuning, up: Vector3, fwd: Vector3) -> void:
	if _grounded < 2 or _handbrake_blend <= 0.0:
		return
	var flat := linear_velocity - up * linear_velocity.dot(up)
	var speed := flat.length()
	var fade := smoothstep(t.drift_min_speed_ms * 0.5, t.drift_min_speed_ms, speed)
	if fade <= 0.0:
		return
	var right := (flat / speed).cross(up)
	var nose := right.dot(fwd)   # sin(derive), du cote ou pointe le nez
	var amount := minf(absf(nose) / sin(deg_to_rad(t.drift_target_slip_deg)), 1.0)
	apply_central_force(right * (signf(nose) * amount * t.drift_carve_g * _gravity * _handbrake_blend * fade * mass))


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
	if absf(rel) > 0.3 and not _trailer_ghost:
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
	_trailer_query.transform = global_transform * trailer_local_transform(angle, trailer_box_center)
	_trailer_query.collision_mask = 1 << (TruckSpec.LAYER_VEHICLE - 1)
	var hits := get_world_3d().direct_space_state.intersect_shape(_trailer_query, 4)
	if hits.is_empty():
		return rel
	var now := Engine.get_physics_frames()
	var tb := global_basis * Basis(Vector3.UP, angle)
	var kingpin := global_transform * TruckSpec.KINGPIN
	var reach := trailer_box_center.z + trailer_box_size.z / 2.0 - TruckSpec.KINGPIN.z
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
	_trailer_query.transform = global_transform * trailer_local_transform(angle, trailer_box_center)
	_trailer_query.collision_mask = mask
	return not get_world_3d().direct_space_state.intersect_shape(_trailer_query, 1).is_empty()


## Pose la caisse de collision a l'angle donne. Jolt reconstruit la forme du
## corps a chaque changement : on ne le fait qu'au-dela d'un centieme de degre.
func _set_trailer_angle(angle: float) -> void:
	_trailer_angle = angle
	if _trailer_shape != null and absf(angle - _trailer_applied) > 1.7e-4:
		_trailer_applied = angle
		_trailer_shape.transform = trailer_local_transform(angle, trailer_box_center)


## En l'air : ressort angulaire amorti critiquement vers l'horizontale (sans
## seuil, plus doux que l'anti-retournement), et lacet pilote au stick vers une
## vitesse de consigne, a acceleration bornee. Le camion retombe a plat, dans
## la direction choisie.
## En l'air, deux phases (VehicleTuning, groupe « Aides arcade ») :
##   1. en vol, le nez SUIT la trajectoire (ressort doux, sous-amorti) ;
##   2. a l'approche du sol, alignement sur la normale du sol vise (ressort
##      raide, amorti critiquement), en fondu selon le temps avant l'impact.
## Avant le 2026-09-30, le camion etait ramene a plat pendant TOUT le vol par
## un ressort amorti critiquement : tangage fige a 0 pendant que la trajectoire
## plongeait, reception parfaitement a plat. D'ou « trop rigide en l'air ».
func _apply_air_control(up: Vector3, steer_in: float) -> void:
	var t := tuning
	var alpha := Vector3.ZERO
	var body_up := up.normalized()

	# phase 1 : assiette visee = pente de la trajectoire x air_follow_ratio,
	# roulis nul. Un camion qui recule suit sa trajectoire a l'envers.
	var target_up := Vector3.UP
	var fwd_h := -global_basis.z
	fwd_h.y = 0.0
	if fwd_h.length_squared() > 1e-6:
		fwd_h = fwd_h.normalized()
		var v := linear_velocity
		var v_h := Vector3(v.x, 0.0, v.z)
		var h_speed := v_h.length()
		var path := atan2(v.y, maxf(h_speed, 0.1))
		if v_h.dot(fwd_h) < 0.0:
			path = -path
		# Sans vitesse horizontale, la « trajectoire » pointe droit vers le sol :
		# la suivre ferait piquer le camion a la verticale (mesure : 37 deg au
		# contact sur une chute droite). Le suivi s'efface donc entre 10 et
		# 3 m/s horizontaux, et le tangage vise est plafonne.
		var follow := smoothstep(3.0, 10.0, h_speed) * t.air_follow_ratio
		var max_pitch := deg_to_rad(t.air_follow_max_deg)
		var pitch := clampf(path * follow, -max_pitch, max_pitch)
		var f_des := fwd_h * cos(pitch) + Vector3.UP * sin(pitch)
		var right_h := f_des.cross(Vector3.UP).normalized()
		target_up = right_h.cross(f_des).normalized()
	var k := t.air_follow_strength
	var zeta := t.air_follow_damping_ratio

	# phase 2 : fondu vers la normale du sol vise, ressort plus raide et amorti
	# critiquement, a mesure que l'impact approche.
	var s := _landing_blend()
	if s > 0.0:
		var k_land := t.air_level_strength
		if _jump_assist_ticks > 0:
			k_land *= t.jump_air_level_factor
		target_up = target_up.slerp(_ground_normal, s).normalized()
		k = lerpf(k, k_land, s)
		zeta = lerpf(zeta, 1.0, s)

	var axis := body_up.cross(target_up)
	if axis.length_squared() > 1e-8:
		axis = axis.normalized()
		var err := body_up.angle_to(target_up)
		alpha += axis * (k * err - 2.0 * zeta * sqrt(k) * angular_velocity.dot(axis))
	# lacet : stick a droite = rotation horaire vue de dessus = -Y
	var target_yaw := -steer_in * deg_to_rad(t.air_yaw_rate_deg_s)
	var dt := 1.0 / Engine.physics_ticks_per_second
	alpha.y += clampf((target_yaw - angular_velocity.y) / dt, -t.air_control_accel, t.air_control_accel)
	var inertia := get_inverse_inertia_tensor().inverse()
	apply_torque(inertia * alpha)


## En l'air : estime l'impact par un rayon vertical tire du centre de masse.
## Renseigne _ground_d (hauteur des roues au-dessus du sol vise, en supposant
## le camion a plat), _ground_normal et _ticks_to_impact (INF si le camion
## monte ou si aucun sol n'est en vue). Aucune allocation.
func _update_landing_estimate() -> void:
	_ticks_to_impact = INF
	_ground_d = INF
	_ground_ray.target_position = _ground_ray.global_basis.inverse() * (Vector3.DOWN * GROUND_RAY_LENGTH)
	_ground_ray.force_raycast_update()
	if not _ground_ray.is_colliding():
		return
	var hit_y := _ground_ray.get_collision_point().y
	_ground_d = maxf(_ground_ray.global_position.y - hit_y - TruckSpec.CENTER_OF_MASS.y, 0.0)
	_ground_normal = _ground_ray.get_collision_normal()
	# Temps de chute sous gravite, d = v t + g t^2 / 2 : valable aussi a vitesse
	# verticale nulle ou en montee. Une estimation a vitesse constante (d / v)
	# surestimait le temps restant : l'alignement sur le sol demarrait trop tard,
	# et un camion secoue en vol touchait le sol a 26 deg, chassis compris.
	var v_down := -linear_velocity.y
	var g := _gravity * tuning.air_gravity_factor
	# racine positive de g t^2 / 2 + v_down t - d = 0
	_ticks_to_impact = (-v_down + sqrt(v_down * v_down + 2.0 * g * _ground_d)) / g \
		* Engine.physics_ticks_per_second


## Poids de la phase « approche du sol » : 0 a air_landing_prep_ticks de
## l'impact, 1 des 40 % de ce delai, et 1 jusqu'au contact. Les derniers ticks
## servent donc entierement a se poser a plat. Un fondu lineaire jusqu'a
## l'impact laissait le camion a moitie aligne au contact (28 deg apres un choc
## en vol, chassis au sol).
func _landing_blend() -> float:
	if _ticks_to_impact == INF:
		return 0.0
	var prep := tuning.air_landing_prep_ticks
	return smoothstep(prep, prep * 0.4, _ticks_to_impact)


## Saut de plaque : a l'approche du sol, deceleration verticale CONSTANTE qui
## amene la chute a jump_landing_max_down_ms exactement au contact
## (a = (v^2 - v_max^2) / 2d), plafonnee a jump_landing_max_decel_ms2. La
## suspension absorbe le reste. Remplace le plafonnement en un tick au contact.
func _apply_landing_cushion(t: VehicleTuning) -> void:
	if _jump_assist_ticks <= 0 or _ticks_to_impact > t.air_landing_prep_ticks:
		return
	var fall := -linear_velocity.y
	var v_max := t.jump_landing_max_down_ms
	if fall <= v_max or _ground_d < 0.05:
		return
	var a := minf((fall * fall - v_max * v_max) / (2.0 * _ground_d), t.jump_landing_max_decel_ms2)
	apply_central_force(Vector3.UP * a * mass)


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


## Braquage max au plein stick a la vitesse actuelle, hors derive et hors
## frein a main (deg). Lecture seule : sert a un pilote (IA, test) a doser son
## stick.
func get_max_steer_deg() -> float:
	return minf(tuning.max_steer_deg,
		maxf(_grip_steer_deg(get_speed_kmh() / 3.6), tuning.steer_floor_deg))
