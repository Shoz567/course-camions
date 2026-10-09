class_name ChaseCamera
extends Node3D

## Camera de poursuite (tache 2.1). Rendu seulement : lit le camion, ne le
## modifie jamais, ne decide rien du jeu.
##
## - Suit la transformation INTERPOLEE du camion (physics interpolation) : pas
##   d'a-coups a 60 Hz sur un ecran plus rapide.
## - Tout est amorti exponentiellement (independant du nombre d'images/s) ; la
##   hauteur plus que le reste : le pompage de la suspension ne secoue pas
##   l'image. La camera ne roule ni ne tangue avec le camion.
## - Vise dans la direction de la vitesse en derapage, et legerement devant.
## - Le bras la raccourcit quand le decor s'interpose (sphere lancee du pivot
##   vers la camera, couche 1 `world`) : elle ne passe jamais a travers la
##   piste. Lance A CHAQUE IMAGE (2026-10-02) : un SpringArm3D ne verifie qu'au
##   tick physique, et sur un ecran plus rapide que 60 Hz la camera entrait
##   dans le decor entre deux ticks (1,1 m a 240 Hz, camera_ground_test).
## - Le pivot, amorti en hauteur, ne descend jamais a moins de
##   focus_min_height au-dessus du camion : en montee rapide (11 m/s en 200cc
##   sur Cyber City), il trainait a 0,4 m du camion, au ras de la route, et le
##   bras ne voyait plus le sol.
## - Champ de vision un peu plus large a haute vitesse.
## - Deux vues (toggle_view) : poursuite (3e personne) et cabine (1re personne,
##   oeil derriere le pare-brise, orientation legerement amortie).
## - Post-traitement de la vue (ScreenFx, hors qualite basse) : aberration
##   sur les bords, vignettage (plus de flou de vitesse depuis le 2026-10-09).

enum View { CHASE, COCKPIT }

@export var target: Truck
## Distance au pivot, et hauteur du pivot au-dessus du camion.
## Recul depuis le tracteur : au-dela de la semi-remorque (arriere a 16,1 m).
@export var distance: float = 28.0
@export var focus_height: float = 4.8
## Hauteur minimale du pivot au-dessus du camion, malgre l'amortissement.
@export var focus_min_height: float = 2.5
## Rayon de la sphere du bras et marge gardee devant le decor (m).
@export var arm_radius: float = 0.3
@export var arm_margin: float = 0.3
## Plongee de la camera (deg) : assez pour voir par-dessus l'aileron (5,6 m).
@export var pitch_deg: float = 13.0
## Amortissements (1/s) : plus grand = plus raide.
@export var follow_damping: float = 14.0
@export var height_damping: float = 2.5
@export var yaw_damping: float = 5.0
@export var fov_damping: float = 2.0
## Anticipation : le pivot avance de vitesse * lookahead (s), borne.
@export var lookahead_s: float = 0.12
@export var lookahead_max: float = 4.0
## Part de la direction de la vitesse dans le cap de la camera (0 = cap du camion).
@export_range(0.0, 1.0) var velocity_heading_weight: float = 0.6
@export var fov_min: float = 70.0
@export var fov_max: float = 80.0
@export var fov_speed_kmh: float = 150.0

@export_group("Vue cabine")
## Position de l'oeil dans le repere du camion : dans la cabine, derriere le
## pare-brise (cabine de collision : z de -2,9 a -0,7, haut a 3,15 m).
@export var cockpit_offset: Vector3 = Vector3(0.0, 3.42, -2.16)
@export var cockpit_fov: float = 78.0
## Amortissement de l'orientation (1/s) : suit le camion sans les secousses.
@export var cockpit_damping: float = 18.0

var view: View = View.CHASE
var _cockpit_basis: Basis = Basis.IDENTITY

var _arm: Node3D
var _arm_query: PhysicsShapeQueryParameters3D
var _camera: Camera3D
var _focus: Vector3
var _yaw: float = 0.0
var _initialized: bool = false
var _last_target: Vector3
var _fx: ScreenFx
## Au-dela de ce deplacement du camion entre deux images, c'est une
## teleportation (reset) : la camera se recale au lieu de traverser la piste.
const TELEPORT_DISTANCE := 15.0


func _ready() -> void:
	# la camera se deplace dans _process : pas d'interpolation physique sur elle
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	_arm = Node3D.new()
	_arm.rotation.x = -deg_to_rad(pitch_deg)
	add_child(_arm)
	var sphere := SphereShape3D.new()
	sphere.radius = arm_radius
	_arm_query = PhysicsShapeQueryParameters3D.new()
	_arm_query.shape = sphere
	_arm_query.collision_mask = 1    # murs et chaussee ; jamais les camions
	_camera = Camera3D.new()
	_camera.fov = fov_min
	_camera.current = true
	_camera.position = Vector3(0.0, 0.0, distance)
	_arm.add_child(_camera)
	if DisplayServer.get_name() != "headless" \
			and GameState.graphics_quality != GraphicsSettings.Quality.LOW:
		_fx = ScreenFx.new()
		var comp := Compositor.new()
		comp.compositor_effects = [_fx]
		_camera.compositor = comp


func get_camera() -> Camera3D:
	return _camera


## Replace la camera derriere le camion, sans amortissement (depart, reset).
func snap() -> void:
	_initialized = false


## Bascule poursuite <-> cabine.
func toggle_view() -> void:
	set_view(View.COCKPIT if view == View.CHASE else View.CHASE)


func set_view(v: View) -> void:
	view = v
	var chase := v == View.CHASE
	_camera.position = Vector3(0.0, 0.0, distance if chase else 0.0)
	_arm.rotation.x = -deg_to_rad(pitch_deg) if chase else 0.0
	snap()


func _process(delta: float) -> void:
	if target == null:
		return
	var xf := target.get_global_transform_interpolated()
	if xf.origin.distance_to(_last_target) > TELEPORT_DISTANCE:
		_initialized = false
	_last_target = xf.origin
	if view == View.COCKPIT:
		_process_cockpit(xf, delta)
		return
	var v := target.linear_velocity
	var flat_v := Vector3(v.x, 0.0, v.z)
	var focus := xf.origin + Vector3.UP * focus_height \
			+ (flat_v * lookahead_s).limit_length(lookahead_max)

	# cap : celui du camion, tire vers la direction de la vitesse en marche avant
	var fwd := -xf.basis.z
	var heading := atan2(-fwd.x, -fwd.z)
	var forward_speed := v.dot(fwd)
	if forward_speed > 3.0:
		var v_heading := atan2(-flat_v.x, -flat_v.z)
		heading = lerp_angle(heading, v_heading, velocity_heading_weight)

	if not _initialized:
		_initialized = true
		_focus = focus
		_yaw = heading
	else:
		var k := 1.0 - exp(-follow_damping * delta)
		var kh := 1.0 - exp(-height_damping * delta)
		_focus.x = lerpf(_focus.x, focus.x, k)
		_focus.z = lerpf(_focus.z, focus.z, k)
		_focus.y = lerpf(_focus.y, focus.y, kh)
		_yaw = lerp_angle(_yaw, heading, 1.0 - exp(-yaw_damping * delta))
	_focus.y = maxf(_focus.y, xf.origin.y + focus_min_height)

	global_transform = Transform3D(Basis(Vector3.UP, _yaw), _focus)
	_camera.position = Vector3(0.0, 0.0, _arm_length())
	var speed_ratio := clampf(absf(forward_speed) * 3.6 / fov_speed_kmh, 0.0, 1.0)
	var fov := lerpf(fov_min, fov_max, speed_ratio)
	_camera.fov = lerpf(_camera.fov, fov, 1.0 - exp(-fov_damping * delta))


## Longueur du bras a cette image : la sphere part du pivot vers la camera et
## s'arrete au premier decor, moins arm_margin.
func _arm_length() -> float:
	var from := _arm.global_position
	_arm_query.transform = Transform3D(Basis.IDENTITY, from)
	_arm_query.motion = _arm.global_basis.z * distance
	var hit := get_world_3d().direct_space_state.cast_motion(_arm_query)
	if hit.is_empty():
		return distance
	return maxf(distance * hit[0] - arm_margin, 0.0)


func _process_cockpit(xf: Transform3D, delta: float) -> void:
	var b := xf.basis.orthonormalized()
	if not _initialized:
		_initialized = true
		_cockpit_basis = b
	else:
		_cockpit_basis = _cockpit_basis.slerp(b, 1.0 - exp(-cockpit_damping * delta)).orthonormalized()
	global_transform = Transform3D(_cockpit_basis, xf * cockpit_offset)
	_camera.fov = cockpit_fov
