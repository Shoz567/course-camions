class_name TruckVisual
extends Node3D

## Habillage visuel du camion. Purement visuel : ne lit que l'etat du camion
## (rayons, braquage) et n'agit jamais sur la physique.
##
## - Roues : suivent le debattement de leur rayon et le braquage.
## - Modele externe optionnel (.glb des camarades, Assets_Visuels/, Git LFS) :
##   charge a l'execution s'il existe, sinon le camion garde ses boites de
##   blockout. Un clone neuf et les tests ne dependent donc d'aucun binaire.
##
## Le modele ne suit pas VEHICLE_SPEC.md (avant en +Z, echelle non appliquee,
## empattement 3,1 m, roues de 0,72 / 0,84 m...). Il est donc AJUSTE au
## chargement, sans jamais toucher a la physique (VEHICLE_SPEC §9) :
##   demi-tour (avant en -Z), echelle uniforme pour que le TRACTEUR mesure la
##   longueur de la spec (la semi-remorque est exclue du calage mais affichee,
##   a la meme echelle), centre sur la caisse du tracteur, bas des pneus au sol ;
##   chaque groupe de roues du tracteur recoit un pivot au moyeu et est associe
##   au rayon le plus proche PAR POSITION (les noms du modele ne sont pas
##   fiables). Les roues de la remorque restent fixes.
## - Remorque articulee : le noeud `Remorque` du modele (ou la boite de
##   blockout) est accroche a un pivot pose sur la sellette (TruckSpec.KINGPIN)
##   et tourne avec l'angle de remorque du camion, comme sa boite de collision.
## - Remorque vivante (2026-10-06) : la remorque affichee suit le sol sous ses
##   essieux (tangage autour de la sellette, roulis), chaque essieu a sa
##   suspension, les roues (remorque et tete) tournent. Purement visuel : la
##   caisse de collision reste articulee en lacet seulement (truck_trailer_ground_test).
## - Passages de roue (2026-10-06) : garde-boue releves, marchepieds recules,
##   roues reduites de 8 % ; butee visuelle mesuree sur la geometrie, penche
##   compris, et braquage visuel borne : les roues ne traversent plus la
##   carrosserie (truck_wheel_arch_test).
## - Pneu eclate (Truck.tire_burst) : le pneu de chaque groupe de roues associe
##   explose (plus de gomme sur la roue), la jante a nu pose sur la route (truck_body.gdshader,
##   tyre_burst = FLAT_TYRE) ; la roue descend jusque-la (la physique ne
##   descend que de tire_burst_drop_m, l'image fait le reste).
##   Pneus de la remorque (un cote du train de roues) : ceux de ce cote, sur
##   chaque essieu de l'habillage, et la remorque penche de ce cote.
## Les ecarts restants sont documentes (docs/ART_PIPELINE.md §4 bis).

## Chemin du modele, relatif au dossier du projet Godot (game/). Vide = boites.
@export var external_model: String = "../Assets_Visuels/Camion/Camions_Course_Export/Realiste/Camion_Bleu.glb"
## Noeuds retires du modele. Aucun : la semi-remorque fait partie de l'identite
## du jeu (VEHICLE_SPEC §2 bis).
@export var strip_prefixes: PackedStringArray = []
## Noeuds affiches mais exclus du calage : l'echelle et le centrage se font sur
## le tracteur, dont les cotes sont celles de la spec.
@export var fit_exclude_prefixes: PackedStringArray = ["Remorque"]
## Prefixe des groupes de roues dans le modele.
@export var wheel_group_prefix: String = "Roue"
## Prefixe du noeud racine de la semi-remorque dans le modele : il pivote
## autour de la sellette.
@export var trailer_prefix: String = "Remorque"

## Couleur des boites de blockout quand le modele est absent (clone neuf) :
## transparente = couleurs d'origine. Distingue les joueurs sans le modele.
@export var mock_tint: Color = Color(0, 0, 0, 0)

## Livree : repeint le modele externe sans nouveau fichier (deux camions de
## plus que de modeles). Par prefixe de nom de materiau du modele
## ("Peinture_Cabine", "Jante"...), un dictionnaire de proprietes : "albedo",
## "metallic", "roughness", "clearcoat", "emission", "emission_energy".
## Vide : le modele garde ses couleurs.
@export var livery: Dictionary = {}

## En headless (tests), le modele n'est pas charge : rien a voir, et les tests
## ne doivent pas dependre d'un fichier LFS (absent d'un clone sans Git LFS).
## Un test peut forcer.
static var load_external_in_headless: bool = false

const SPEC_LENGTH := TruckSpec.CHASSIS_SIZE.z
const MODEL_ROOT := &"ExternalModel"
const TRAILER_PIVOT := &"TrailerPivot"
## Modele de la remorque choisie, sous TRAILER_PIVOT (set_trailer_type).
const TRAILER_SKIN := &"TrailerSkin"
## Essieux des remorques du catalogue (tools/blender/catalogue_tete_commune.py).
const AXLE_PREFIX := "Gen_Essieu_"

## Chemin absolu -> PackedScene du modele ajuste (null si absent ou illisible).
## Une ressource, pas un noeud orphelin : rien ne fuit a la sortie.
static var _templates: Dictionary = {}
## Silhouettes d'ombre (ShadowProxy) : sous-arbres qui bougent seuls (roues,
## essieux de remorque) et pieces retirees apres coup (cones de flamme).
const SHADOW_MOVING: PackedStringArray = ["WheelPivot_", "Roue", AXLE_PREFIX]
const SHADOW_SKIP: PackedStringArray = ["Flamme"]
const WHEEL_SHADOW_SKIP: PackedStringArray = ["Pneu"]

var model_loaded: bool = false
## Ecarts mesures au chargement : echelle appliquee, dimensions obtenues.
var fit_report: Dictionary = {}

var _truck: Truck
## Pivot de la remorque (modele ou boite), a la sellette.
var _trailer_pivot: Node3D
var _pivots: Array[Node3D] = []
var _rest: Array[Transform3D] = []
var _steers: Array[bool] = []
## Mode modele : rayon associe a chaque pivot. Vide en mode boites (pivot i =
## rayon i).
var _probe_of: PackedInt32Array = []
## Mode modele : jeu sous le passage de chaque roue (m) et haut du pneu au
## repos (repere du camion) : butee visuelle, penche compris. Vide en boites.
var _arch_gap: PackedFloat32Array = []
var _arch_point: PackedVector3Array = []
var _arch_hw: PackedFloat32Array = []
## Braquage visuel max : ce que les passages de roue avant laissent passer.
var _steer_limit_deg: float = 90.0
## Penche courant de la carrosserie (autour du centre de masse).
var _lean_xf: Transform3D = Transform3D.IDENTITY
## Roues de la tete qui tournent : groupe de maillages sous chaque pivot, sa
## pose au repos, son rayon (m) et son angle courant.
var _wheel_groups: Array[Node3D] = []
var _wheel_group_rest: Array[Transform3D] = []
var _wheel_radius: PackedFloat32Array = []
var _wheel_spin: PackedFloat32Array = []

@export_group("Remorque vivante")
## La remorque affichee suit le sol sous ses essieux (tangage autour de la
## sellette, roulis) : ses roues ne passent plus dans le sol sur les bosses et
## dans les creux. PUREMENT VISUEL (2026-10-06) : la caisse de collision reste
## articulee en lacet seulement (VEHICLE_SPEC §5 bis).
@export var trailer_follows_ground: bool = true
## Ressort qui amene la remorque vers le sol (Hz, amortissement).
@export_range(0.5, 10.0, 0.1, "suffix:Hz") var trailer_ground_frequency_hz: float = 4.0
@export_range(0.0, 2.0, 0.01) var trailer_ground_damping_ratio: float = 0.8
## Bornes du tangage et du roulis pris au sol.
@export_range(0.0, 30.0, 0.5, "suffix:°") var trailer_max_pitch_deg: float = 14.0
@export_range(0.0, 20.0, 0.5, "suffix:°") var trailer_max_ground_roll_deg: float = 7.0
## Debattement visuel de chaque essieu de remorque (vers le haut / le bas).
@export_range(0.0, 0.5, 0.01, "suffix:m") var trailer_axle_bump_m: float = 0.25
@export_range(0.0, 0.5, 0.01, "suffix:m") var trailer_axle_droop_m: float = 0.12

## Essieux de la remorque (modele du catalogue : Gen_Essieu_*) : noeud, pose au
## repos, rayon, debattement et angle courants ; centre du train et demi-voie
## (repere du pivot de sellette).
var _axles: Array[Node3D] = []
var _axle_rest: Array[Transform3D] = []
var _axle_radius: PackedFloat32Array = []
var _axle_offset: PackedFloat32Array = []
var _axle_spin: PackedFloat32Array = []
## Pneu eclate, a l'image : ecrase jusqu'a la jante (fraction du rayon :
## plancher juste sous le fut, RIM_RATIO du shader) ; descente visuelle des
## roues du tracteur au-dela de la physique, et de chaque essieu de remorque.
const FLAT_TYRE := 1.0 - TruckTires.RIM_RATIO * 1.03
var _flat_sink: PackedFloat32Array = []
var _axle_sink: PackedFloat32Array = []
## Sol sous les pneus, repere du camion (matieres : salissure selon la
## hauteur).
var _ground_y: float = 0.0
var _bogie_z: float = 0.0
var _bogie_half_track: float = 1.0
## Tangage et roulis pris au sol (rad) et leurs vitesses (ressort visuel).
var _trailer_pitch: float = 0.0
var _trailer_pitch_rate: float = 0.0
var _trailer_ground_roll: float = 0.0
var _trailer_ground_roll_rate: float = 0.0
## Roulis de la remorque sur un pneu creve (rad, > 0 leve la droite).
var _trailer_flat_roll: float = 0.0
## Rayon reutilise pour sonder le sol (couche world), sans allocation.
var _ground_ray: RayCast3D

@export_group("Penche visuel de la carrosserie")
## La CARROSSERIE (noeud Body) penche selon l'acceleration du camion : roulis
## vers l'exterieur en virage, plongee au freinage, cabrage a l'acceleration.
## PUREMENT VISUEL : ni la physique, ni les roues, ni la remorque ne bougent.
## Ajoute a la demande de l'utilisateur (2026-09-30 : camion « trop rigide »),
## c'est l'astuce classique des jeux arcade pour donner de la vie a un vehicule
## dont la physique reste stable.
@export var lean_enabled: bool = true
## Roulis par g d'acceleration laterale.
@export_range(0.0, 20.0, 0.1, "suffix:°/g") var lean_roll_deg_per_g: float = 4.0
## Tangage par g d'acceleration longitudinale (freinage : le nez plonge).
@export_range(0.0, 20.0, 0.1, "suffix:°/g") var lean_pitch_deg_per_g: float = 2.5
## Plafond, dans chaque axe : un choc violent ne couche pas la carrosserie.
@export_range(0.0, 30.0, 0.1, "suffix:°") var lean_max_deg: float = 6.0
## Ressort visuel qui suit la cible : frequence et amortissement. Sous 1, la
## carrosserie se balance legerement avant de se poser : c'est voulu.
@export_range(0.1, 5.0, 0.01, "suffix:Hz") var lean_frequency_hz: float = 1.3
@export_range(0.0, 2.0, 0.01) var lean_damping_ratio: float = 0.45
## Part du ROULIS reprise par la semi-remorque (autour de la sellette). C'est
## elle qu'on voit depuis la camera de poursuite : sans elle, le penche serait
## presque invisible avec le modele externe (constate sur capture). Pas de
## tangage : l'arriere de la remorque se souleverait au freinage.
@export_range(0.0, 1.5, 0.01) var lean_trailer_roll_ratio: float = 1.0

var _body: Node3D
var _body_rest: Transform3D
## Penche courant (x = tangage, y = roulis, en degres) et sa vitesse.
var _lean: Vector2 = Vector2.ZERO
var _lean_rate: Vector2 = Vector2.ZERO
var _prev_velocity: Vector3 = Vector3.ZERO
var _lean_started: bool = false


## Penche courant de la carrosserie (x = tangage, y = roulis, en degres).
func get_lean_deg() -> Vector2:
	return _lean


func _ready() -> void:
	_truck = get_parent() as Truck
	_ground_ray = RayCast3D.new()
	_ground_ray.name = "GroundProbe"
	_ground_ray.top_level = true
	_ground_ray.enabled = false
	_ground_ray.collision_mask = 1 << (TruckSpec.LAYER_WORLD - 1)
	add_child(_ground_ray)
	if _truck != null:
		_ground_ray.add_exception(_truck)
		_truck.tire_burst.connect(_on_tire_burst)
		_truck.tires_repaired.connect(_on_tires_repaired)
	if external_model != "" and (DisplayServer.get_name() != "headless" or load_external_in_headless):
		_attach_external()
	if not model_loaded:
		_trailer_pivot = get_node_or_null(NodePath(TRAILER_PIVOT)) as Node3D
		if mock_tint.a > 0.0:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = mock_tint
			for mesh_name: String in ["Body/ChassisMesh", "TrailerPivot/TrailerMesh"]:
				var mi := get_node_or_null(NodePath(mesh_name)) as MeshInstance3D
				if mi != null:
					mi.material_override = mat
		for n in TruckSpec.WHEEL_NAMES:
			var w := get_node_or_null(NodePath(n)) as Node3D
			_pivots.append(w)
			_rest.append(w.transform if w != null else Transform3D.IDENTITY)
		_steers.assign([true, true, false, false])
	var body_path := NodePath("%s/Body" % MODEL_ROOT) if model_loaded else ^"Body"
	_body = get_node_or_null(body_path) as Node3D
	if _body != null:
		_body_rest = _body.transform
	# carrosserie sur le calque des traces de choc (DamageFx) : les decalques
	# ne marquent qu'elle, jamais la route
	for n in find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).layers |= DamageFx.LAYER_BIT


## Pneu de la roue physique `wheel` eclate : les pneus de ses groupes de roues
## s'ecrasent du rayon perdu (en fraction de leur rayon).
func _on_tire_burst(_wheel: int) -> void:
	_sync_tyres()


func _on_tires_repaired() -> void:
	_sync_tyres()


## Pneus affiches = pneus du camion (Truck.is_tire_burst) : groupes de roues
## du tracteur, cotes du train de roues de la remorque.
func _sync_tyres() -> void:
	if _truck == null:
		return
	var drop := _truck.tuning.tire_burst_drop_m if _truck.tuning != null else 0.0
	_flat_sink.resize(_pivots.size())
	for k in _pivots.size():
		_flat_sink[k] = 0.0
		if _pivots[k] != null:
			var r := _wheel_radius[k] if k < _wheel_radius.size() else TruckSpec.WHEEL_RADIUS
			var on := _truck.is_tire_burst(_probe_index(k))
			set_tyre_burst(_pivots[k], FLAT_TYRE if on else 0.0)
			# la physique ne descend que de tire_burst_drop_m ; le reste, a
			# l'image : la jante pose sur la route
			if on:
				_flat_sink[k] = maxf(r * FLAT_TYRE - drop, 0.0)
	var left := _truck.is_tire_burst(Truck.TRAILER_LEFT)
	var right := _truck.is_tire_burst(Truck.TRAILER_RIGHT)
	_axle_sink.resize(_axles.size())
	var sink := 0.0
	for i in _axles.size():
		var amount := FLAT_TYRE if left or right else 0.0
		set_tyre_burst(_axles[i], amount, left or not right, right or not left, _trailer_pivot)
		# un cote a plat : l'essieu descend de moitie, la remorque penche (la
		# jante du cote creve sur la route, le pneu neuf d'en face aussi)
		_axle_sink[i] = _axle_radius[i] * amount * (1.0 if left and right else 0.5)
		sink = maxf(sink, _axle_radius[i] * amount)
	var sag := atan2(sink, 2.0 * _bogie_half_track)
	_trailer_flat_roll = (sag if left else 0.0) - (sag if right else 0.0)


## Ecrasement `amount` (fraction du rayon, 0 : pneu neuf) des pneus de
## `wheel_root` et de ses enfants : les maillages en gomme sculptee (relief de
## pneu). Un seul cote (`left` ou `right`, x < 0 ou x > 0 dans le repere de
## `frame`, par defaut `wheel_root`) : un pneu de l'autre cote reste neuf, un
## maillage d'essieu entier (les deux pneus, remorque) ne s'ecrase que de ce
## cote (tyre_side).
static func set_tyre_burst(wheel_root: Node3D, amount: float, left: bool = true, right: bool = true,
		frame: Node3D = null) -> int:
	var n := 0
	var both := left == right
	if frame == null:
		frame = wheel_root
	var inv := Transform3D.IDENTITY if both else frame.global_transform.affine_inverse()
	var meshes := wheel_root.find_children("*", "MeshInstance3D", true, false)
	if wheel_root is MeshInstance3D:
		meshes.append(wheel_root)
	for c in meshes:
		var mi := c as MeshInstance3D
		var ax: Variant = mi.get_instance_shader_parameter(&"relief_axis")
		if not (ax is Vector4 and (ax as Vector4).w > 0.0):
			continue
		var a := amount
		var side := 0.0
		if not both:
			var want := -1.0 if left else 1.0
			var local := inv * mi.global_transform
			var x := (local * mi.get_aabb().get_center()).x
			if absf(x) > 0.3:
				# pneu seul, d'un cote
				a = amount if signf(x) == want else 0.0
			else:
				# essieu entier : le cote voulu, le long de son axe de relief
				var ax3 := Vector3((ax as Vector4).x, (ax as Vector4).y, (ax as Vector4).z)
				side = want * signf((local.basis * ax3).x)
		mi.set_instance_shader_parameter(&"tyre_burst", a)
		mi.set_instance_shader_parameter(&"tyre_side", side)
		n += 1
	return n


## Noeud qui porte les traces de choc : la caisse de la remorque (elle suit
## l'articulation, et sa copie larguee les emporte), ou la carrosserie du
## tracteur (elle suit le penche).
func mark_parent(on_trailer: bool) -> Node3D:
	if on_trailer and _trailer_pivot != null:
		return _trailer_pivot
	return _body if _body != null else self


## Apres le camion (enfant : meme tick, apres ses forces). Les transformations
## posees ici sont interpolees au rendu (physics interpolation).
func _physics_process(delta: float) -> void:
	if _truck == null:
		return
	_update_lean(delta)
	# chemin parcouru ce tick le long de l'axe du camion : rotation des roues
	var roll_dist := _truck.linear_velocity.dot(-_truck.global_basis.z) * delta
	if _trailer_pivot != null:
		_update_trailer_pose(delta, roll_dist)
		# remorque larguee : elle est sur la route, plus derriere le tracteur
		_trailer_pivot.visible = not _truck.is_trailer_detached()
	if _pivots.is_empty():
		return
	var steer_deg := clampf(_truck.get_steer_deg(), -_steer_limit_deg, _steer_limit_deg)
	var steer := Basis(Vector3.UP, -deg_to_rad(steer_deg))
	var rest_hub := TruckSpec.rest_hub_distance()
	for i in _pivots.size():
		var p := _pivots[i]
		if p == null:
			continue
		var probe := _truck.get_probe(_probe_index(i))
		var xf := _rest[i]
		var up := rest_hub - probe.hub_distance
		if not _arch_gap.is_empty():
			# butee visuelle : le pneu reste sous son passage de roue, meme quand
			# la carrosserie penche vers lui (la physique n'est pas touchee)
			# abaissement de la carrosserie au-dessus des DEUX bords du pneu (le
			# roulis la fait descendre d'un cote du moyeu, monter de l'autre)
			var a := _arch_point[i]
			var edge := Vector3(_arch_hw[i], 0.0, 0.0)
			var drop := maxf(a.y - edge.y - (_lean_xf * (a - edge)).y, a.y + edge.y - (_lean_xf * (a + edge)).y)
			up = minf(up, _arch_gap[i] - drop - ARCH_SAFETY)
			if not _steers[i]:
				# roues arriere : sous la remorque, qui pivote et penche au-dessus
				up = minf(up, REAR_WHEEL_MAX_UP)
		xf.origin.y += up
		if i < _flat_sink.size():
			xf.origin.y -= _flat_sink[i]
		if _steers[i]:
			xf.basis = steer * xf.basis
		p.transform = xf
		# roues qui tournent : autour de l'axe du moyeu (le pivot porte le
		# demi-tour du modele : +X local = -X du camion, d'ou le signe)
		if i < _wheel_groups.size() and _wheel_groups[i] != null:
			_wheel_spin[i] = fposmod(_wheel_spin[i] + roll_dist / _wheel_radius[i], TAU)
			_wheel_groups[i].transform = Transform3D(Basis(Vector3.RIGHT, _wheel_spin[i]), Vector3.ZERO) \
				* _wheel_group_rest[i]


## Penche de la carrosserie : cible deduite de l'acceleration du camion (au sol
## seulement : en l'air, la cible revient a zero), suivie par un ressort visuel.
## Rotation autour du centre de masse. Aucune allocation.
func _update_lean(delta: float) -> void:
	if _body == null or delta <= 0.0:
		return
	var v := _truck.linear_velocity
	if not _lean_started:
		_prev_velocity = v
		_lean_started = true
	var accel := (v - _prev_velocity) / delta
	_prev_velocity = v

	var target := Vector2.ZERO
	if lean_enabled and _truck.wheels_on_ground() >= 2:
		var b := _truck.global_basis
		# virage a droite : acceleration centripete vers +X -> roulis > 0, la
		# carrosserie penche a GAUCHE, vers l'exterieur
		var a_lat := accel.dot(b.x) / 9.81
		# freinage : acceleration vers l'arriere -> tangage < 0, le nez plonge
		var a_long := accel.dot(-b.z) / 9.81
		target.x = clampf(a_long * lean_pitch_deg_per_g, -lean_max_deg, lean_max_deg)
		target.y = clampf(a_lat * lean_roll_deg_per_g, -lean_max_deg, lean_max_deg)

	var w := TAU * lean_frequency_hz
	var acc := (target - _lean) * (w * w) - _lean_rate * (2.0 * lean_damping_ratio * w)
	_lean_rate += acc * delta
	_lean += _lean_rate * delta

	var lean_basis := Basis(Vector3.RIGHT, deg_to_rad(_lean.x)) * Basis(Vector3.BACK, deg_to_rad(_lean.y))
	var pivot := TruckSpec.CENTER_OF_MASS
	_lean_xf = Transform3D(lean_basis, pivot - lean_basis * pivot)
	_body.transform = _lean_xf * _body_rest


## Copie de la remorque (modele ou boite), dans le repere de la sellette : le
## visuel de la remorque larguee. Maillages partages, rien n'est recharge.
func make_trailer_copy() -> Node3D:
	if _trailer_pivot == null:
		return null
	var copy := _trailer_pivot.duplicate() as Node3D
	copy.transform = Transform3D.IDENTITY
	copy.visible = true
	return copy


## Copie du tracteur seul (carrosserie cabossee, roues, sans la remorque),
## dans le repere du camion : le visuel de la carcasse (TruckWreck). Maillages
## partages, rien n'est recharge.
func make_wreck_copy() -> Node3D:
	var root := Node3D.new()
	root.name = "WreckVisual"
	root.transform = transform
	for c in get_children():
		var n := c as Node3D
		if n == null or not n.visible or n == _ground_ray or String(n.name) == String(TRAILER_PIVOT):
			continue
		var copy := n.duplicate() as Node3D
		var pivot := copy.get_node_or_null(NodePath(TRAILER_PIVOT))
		if pivot != null:
			copy.remove_child(pivot)
			pivot.free()
		root.add_child(copy)
	return root


## Remorque choisie (sas READY) : son modele remplace celui de la remorque du
## camion, sous le pivot de la sellette (il suit donc l'articulation, le penche
## et la copie larguee). Sans modele charge (boites, headless), la boite de
## blockout prend la taille de la caisse. null ou sans modele : remorque
## d'origine.
func set_trailer_type(type: TrailerType) -> void:
	if _trailer_pivot == null:
		return
	var old := _trailer_pivot.get_node_or_null(NodePath(TRAILER_SKIN))
	if old != null:
		_trailer_pivot.remove_child(old)
		old.queue_free()
	var skin: Node3D = null
	if model_loaded and type != null and type.model != "":
		var path := ProjectSettings.globalize_path("res://").path_join(type.model).simplify_path()
		var template := _trailer_template(path)
		if template != null:
			skin = template.instantiate() as Node3D
			skin.name = TRAILER_SKIN
			for n in skin.find_children("*", "MeshInstance3D", true, false):
				(n as MeshInstance3D).layers |= DamageFx.LAYER_BIT
			_trailer_pivot.add_child(skin)
	_collect_axles(skin)
	if skin != null and is_inside_tree():
		if not TruckDetails.has_flaps(skin):
			_add_trailer_flaps(skin)
		# coque creuse : les chocs graves la percent, on voit l'interieur vide
		TruckMaterials.upgrade(skin, self, _ground_y, true)
		_sync_tyres()
	# remorque d'origine (modele du camion ou boite) : cachee sous un habillage
	for c in _trailer_pivot.get_children():
		if c != skin and c is Node3D and String(c.name) != TRAILER_SKIN:
			(c as Node3D).visible = skin == null
	if model_loaded:
		TruckLights.set_tail_lights(_trailer_pivot,
			type.box_center if type != null else TruckSpec.TRAILER_CENTER,
			type.box_size if type != null else TruckSpec.TRAILER_SIZE)
	if not model_loaded:
		var mesh := _trailer_pivot.get_node_or_null(^"TrailerMesh") as Node3D
		if mesh != null:
			var size := type.box_size if type != null else TruckSpec.TRAILER_SIZE
			var center := type.box_center if type != null else TruckSpec.TRAILER_CENTER
			mesh.transform = Transform3D(Basis.from_scale(size / TruckSpec.TRAILER_SIZE),
				center - TruckSpec.KINGPIN)


## Essieux de l'habillage (Gen_Essieu_*, origine au centre de l'essieu) : ce
## sont eux qui suivent le sol et tournent. Sans habillage : aucun, et la
## remorque garde la pose rigide d'avant (boites, remorque d'origine).
func _collect_axles(skin: Node3D) -> void:
	_axles.clear()
	_axle_rest.clear()
	_axle_radius.clear()
	_axle_offset.clear()
	_axle_spin.clear()
	_trailer_pitch = 0.0
	_trailer_pitch_rate = 0.0
	_trailer_ground_roll = 0.0
	_trailer_ground_roll_rate = 0.0
	if skin == null:
		return
	var z_sum := 0.0
	var half := 0.0
	for n in skin.find_children(AXLE_PREFIX + "*", "Node3D", true, false):
		var a := n as Node3D
		var box := _subtree_aabb(a, Transform3D.IDENTITY)
		_axles.append(a)
		_axle_rest.append(a.transform)
		_axle_radius.append(maxf(box.size.y / 2.0, 0.1))
		_axle_offset.append(0.0)
		_axle_spin.append(0.0)
		z_sum += (skin.transform * a.position).z
		half = maxf(half, box.size.x / 2.0)
	if not _axles.is_empty():
		_bogie_z = z_sum / _axles.size()
		# sonde sous les pneus exterieurs, pas sous l'essieu
		_bogie_half_track = maxf(half - 0.3, 0.5)


## Bavettes derriere les roues les plus en arriere du tracteur, de chaque cote.
func _add_tractor_flaps(model: Node3D) -> void:
	var ground := TruckMaterials.lowest_point(model, model)
	for side: float in [-1.0, 1.0]:
		var best := -1
		for k in _pivots.size():
			if _probe_of[k] >= 2 and signf(_pivots[k].position.x) == side \
					and (best < 0 or _pivots[k].position.z > _pivots[best].position.z):
				best = k
		if best < 0:
			continue
		var hw := _arch_hw[best] if _arch_hw[best] > 0.05 else 0.3
		TruckDetails.add_flap(model, _pivots[best].position, _wheel_radius[best], hw * 2.0 + 0.12, ground,
			"Tracteur_%s" % ("G" if side < 0.0 else "D"))


## Bavettes derriere le dernier essieu de la remorque, de chaque cote.
func _add_trailer_flaps(skin: Node3D) -> void:
	var last: Node3D = null
	var last_z := -INF
	var inv := skin.global_transform.affine_inverse()
	for a in _axles:
		var z := (inv * a.global_transform).origin.z
		if z > last_z:
			last_z = z
			last = a
	if last == null:
		return
	var hub := (inv * last.global_transform).origin
	var box := _subtree_aabb(last, Transform3D.IDENTITY)
	var half := box.size.x / 2.0
	var r := maxf(box.size.y / 2.0, 0.3)
	var ground := TruckMaterials.lowest_point(skin, skin)
	for side: float in [-1.0, 1.0]:
		TruckDetails.add_flap(skin, Vector3(side * (half - 0.32), hub.y, hub.z), r, 0.62, ground,
			"Remorque_%s" % ("G" if side < 0.0 else "D"))


## Pose de la remorque affichee : lacet de la physique, roulis du penche, et
## (habillage a essieux) tangage + roulis pris au sol sous le train de roues,
## suspension de chaque essieu, roues qui tournent. Aucune allocation.
func _update_trailer_pose(delta: float, roll_dist: float) -> void:
	var yaw := Basis(Vector3.UP, _truck.get_trailer_angle())
	var lean_roll := deg_to_rad(_lean.y * lean_trailer_roll_ratio)
	if _axles.is_empty() or not trailer_follows_ground or delta <= 0.0:
		_trailer_pivot.basis = yaw * Basis(Vector3.BACK, lean_roll + _trailer_flat_roll)
		return
	# pose du camion APRES le pas physique qui suit (ce code passe avant lui) :
	# sans cette prediction, la remorque a un tick de retard sur l'assiette du
	# tracteur, soit jusqu'a 7 cm a 13 m de la sellette quand il tangue
	var txf := _predicted_truck_xf(delta)
	var kp := TruckSpec.KINGPIN
	var target_pitch := 0.0
	var target_roll := 0.0
	var grounded := false
	if not _truck.is_trailer_detached():
		# bas des pneus du train (exterieurs gauche et droit), remorque a plat
		var bl := txf * (kp + yaw * Vector3(-_bogie_half_track, -kp.y, _bogie_z))
		var br := txf * (kp + yaw * Vector3(_bogie_half_track, -kp.y, _bogie_z))
		var hl := _ground_height(bl)
		var hr := _ground_height(br)
		if not is_nan(hl) and not is_nan(hr):
			grounded = true
			var el := hl - bl.y   # > 0 : le pneu serait dans le sol
			var er := hr - br.y
			# tangage autour de la sellette (> 0 abaisse l'arriere) ; roulis (> 0
			# leve la droite)
			target_pitch = -atan2((el + er) * 0.5, _bogie_z)
			target_roll = atan2(er - el, 2.0 * _bogie_half_track)
	var max_pitch := deg_to_rad(trailer_max_pitch_deg)
	var max_roll := deg_to_rad(trailer_max_ground_roll_deg)
	target_pitch = clampf(target_pitch, -max_pitch, max_pitch)
	target_roll = clampf(target_roll + _trailer_flat_roll, -max_roll, max_roll)
	var w := TAU * trailer_ground_frequency_hz
	var c := 2.0 * trailer_ground_damping_ratio * w
	_trailer_pitch_rate += (w * w * (target_pitch - _trailer_pitch) - c * _trailer_pitch_rate) * delta
	_trailer_pitch += _trailer_pitch_rate * delta
	_trailer_ground_roll_rate += (w * w * (target_roll - _trailer_ground_roll) - c * _trailer_ground_roll_rate) * delta
	_trailer_ground_roll += _trailer_ground_roll_rate * delta
	if grounded and _trailer_pitch > target_pitch:
		# butee : le ressort peut etre en retard, les roues jamais dans le sol
		_trailer_pitch = target_pitch
		_trailer_pitch_rate = minf(_trailer_pitch_rate, 0.0)
	var b := yaw * Basis(Vector3.RIGHT, _trailer_pitch) * Basis(Vector3.BACK, _trailer_ground_roll + lean_roll)
	_trailer_pivot.basis = b
	# suspension de chaque essieu (le sol sous lui) et rotation des roues
	var skin_xf := _axles[0].get_parent_node_3d().transform
	for i in _axles.size():
		var rest := _axle_rest[i]
		var target := 0.0
		if grounded:
			var flat := _axle_sink[i] if i < _axle_sink.size() else 0.0
			var bottom := txf * (kp + b * (skin_xf * (rest.origin + Vector3(0.0, -_axle_radius[i] + flat + _axle_offset[i], 0.0))))
			var h := _ground_height(bottom)
			if not is_nan(h):
				target = clampf(_axle_offset[i] + h - bottom.y, -trailer_axle_droop_m - flat, trailer_axle_bump_m)
		# le sol pousse : l'essieu remonte tout de suite ; il redescend en douceur
		_axle_offset[i] = target if target > _axle_offset[i] else lerpf(_axle_offset[i], target, 0.5)
		_axle_spin[i] = fposmod(_axle_spin[i] - roll_dist / _axle_radius[i], TAU)
		_axles[i].transform = Transform3D(rest.basis * Basis(Vector3.RIGHT, _axle_spin[i]),
			rest.origin + Vector3(0.0, _axle_offset[i], 0.0))


## Hauteur du sol (couche world) sous le point monde `p`, NAN si rien a moins
## de 3 m en dessous (en l'air).
func _ground_height(p: Vector3) -> float:
	_ground_ray.global_position = p + Vector3(0.0, 2.5, 0.0)
	_ground_ray.target_position = Vector3(0.0, -5.5, 0.0)
	_ground_ray.force_raycast_update()
	if not _ground_ray.is_colliding():
		return NAN
	return _ground_ray.get_collision_point().y


## Habillage de remorque en place (null : remorque d'origine).
func get_trailer_skin() -> Node3D:
	if _trailer_pivot == null:
		return null
	return _trailer_pivot.get_node_or_null(NodePath(TRAILER_SKIN)) as Node3D


func _probe_index(i: int) -> int:
	return _probe_of[i] if not _probe_of.is_empty() else i


# --- modele externe ---------------------------------------------------------------

func _attach_external() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join(external_model).simplify_path()
	var template := _template(path, strip_prefixes, fit_exclude_prefixes, wheel_group_prefix, trailer_prefix)
	if template == null:
		return
	var model := template.instantiate() as Node3D
	model.name = MODEL_ROOT
	add_child(model)
	fit_report = model.get_meta(&"fit_report", {})
	if not livery.is_empty():
		apply_livery(model, livery)
	# pas de cones de flamme figes au bout des cheminees (jouet)
	TruckDetails.strip_toy_parts(model)
	# phares qui eclairent
	if TruckLights.add_headlights(model) > 0 and get_parent() != null:
		# les deux projecteurs remplacent le phare central du camion
		var central := get_parent().get_node_or_null(^"Headlights") as Light3D
		if central != null:
			central.visible = false
	_trailer_pivot = model.get_node_or_null(NodePath(TRAILER_PIVOT)) as Node3D
	# groupes de roues : pivot au moyeu, associe au rayon le plus proche
	for pivot in model.find_children("WheelPivot_*", "Node3D", false, false):
		var p := pivot as Node3D
		_pivots.append(p)
		_rest.append(p.transform)
		var best := 0
		var best_d := INF
		for i in 4:
			var d := Vector2(p.position.x - TruckSpec.ANCHORS[i].x, p.position.z - TruckSpec.ANCHORS[i].z).length()
			if d < best_d:
				best_d = d
				best = i
		_probe_of.append(best)
		_steers.append(best < 2)
		var arch: Vector4 = p.get_meta(&"arch", Vector4(INF, 0.0, 0.0, 0.0))
		_arch_gap.append(arch.x)
		_arch_point.append(Vector3(arch.y, arch.z, arch.w))
		_arch_hw.append((p.get_meta(&"tire", Vector2.ZERO) as Vector2).y)
		# groupe de maillages de la roue (seul enfant du pivot) : il tourne
		var g: Node3D = p.get_child(0) as Node3D if p.get_child_count() > 0 else null
		_wheel_groups.append(g)
		_wheel_group_rest.append(g.transform if g != null else Transform3D.IDENTITY)
		_wheel_radius.append(maxf((p.get_meta(&"tire", Vector2(0.5, 0.0)) as Vector2).x, 0.1))
		_wheel_spin.append(0.0)
	_steer_limit_deg = float(model.get_meta(&"visual_steer_max_deg", 90.0))
	# bavettes derriere les roues arriere, puis matieres realistes (vernis,
	# chrome, gomme, salissure de la route d'apres la hauteur au sol)
	_ground_y = TruckMaterials.lowest_point(model, self)
	if not TruckDetails.has_flaps(model, "Remorque"):
		_add_tractor_flaps(model)
	TruckMaterials.upgrade(model, self, _ground_y)
	# les boites de blockout s'effacent, sans disparaitre (tests, repli)
	for n in [&"Body", TRAILER_PIVOT, &"Wheel_FL", &"Wheel_FR", &"Wheel_RL", &"Wheel_RR"]:
		var mock := get_node_or_null(NodePath(n)) as Node3D
		if mock != null:
			mock.visible = false
	model_loaded = true


## Repeint les surfaces de `root` dont le materiau porte un nom commencant par
## une cle de `paint` : copie du materiau (celui du modele, partage, n'est
## jamais modifie), posee en surcharge de surface. Renvoie le nombre de
## surfaces repeintes.
static func apply_livery(root: Node, paint: Dictionary) -> int:
	var painted := 0
	var copies := {}   # materiau d'origine -> copie repeinte (ou null)
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			if not copies.has(src):
				copies[src] = _painted(src, paint)
			if copies[src] != null:
				mi.set_surface_override_material(s, copies[src])
				painted += 1
	return painted


static func _painted(src: BaseMaterial3D, paint: Dictionary) -> BaseMaterial3D:
	for prefix: String in paint:
		if not src.resource_name.begins_with(prefix):
			continue
		var props: Dictionary = paint[prefix]
		var m := src.duplicate() as BaseMaterial3D
		if props.has("albedo"):
			m.albedo_color = props["albedo"]
		if props.has("metallic"):
			m.metallic = props["metallic"]
		if props.has("roughness"):
			m.roughness = props["roughness"]
		if props.has("clearcoat"):
			m.clearcoat_enabled = true
			m.clearcoat = props["clearcoat"]
			m.clearcoat_roughness = 0.1
		if props.has("emission"):
			m.emission_enabled = true
			m.emission = props["emission"]
			m.emission_energy_multiplier = float(props.get("emission_energy", 1.0))
		return m
	return null


## Charge et ajuste le modele une seule fois par chemin ; les camions suivants
## dupliquent le resultat (maillages partages).
static func _template(path: String, strip: PackedStringArray, exclude: PackedStringArray,
		wheel_prefix: String, trailer_prefix: String) -> PackedScene:
	if _templates.has(path):
		return _templates[path]
	_templates[path] = null
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("TruckVisual : %s illisible, camion en boites" % path)
		return null
	_generate_lods(state)
	var raw := doc.generate_scene(state) as Node3D
	# on va deplacer des noeuds : plus de proprietaire le temps de l'ajustement
	for n in raw.find_children("*", "", true, false):
		n.owner = null
	var fitted := _fit(raw, strip, exclude, wheel_prefix, trailer_prefix)
	raw.free()
	if fitted == null:
		return null
	# silhouettes d'ombre (ShadowProxy) : carrosserie, et remorque d'origine
	# (cachee avec elle quand une remorque du catalogue la remplace)
	var body_node := fitted.get_node_or_null(^"Body") as Node3D
	if body_node != null:
		ShadowProxy.build(body_node, SHADOW_MOVING, SHADOW_SKIP)
	var own_trailer := fitted.get_node_or_null(NodePath(TRAILER_PIVOT)) as Node3D
	if own_trailer != null and own_trailer.get_child_count() > 0:
		ShadowProxy.build(own_trailer.get_child(0) as Node3D, SHADOW_MOVING, SHADOW_SKIP)
	# roues : jante, moyeu, ecrous ; le pneu garde son ombre (il disparait
	# quand il eclate)
	for pivot in fitted.find_children("WheelPivot_*", "Node3D", false, false):
		if pivot.get_child_count() > 0:
			ShadowProxy.build(pivot.get_child(0) as Node3D, PackedStringArray(), WHEEL_SHADOW_SKIP)
	_set_visibility_ranges(fitted)
	for n in fitted.find_children("*", "", true, false):
		n.owner = fitted
	var packed := PackedScene.new()
	packed.pack(fitted)
	fitted.free()
	_templates[path] = packed
	return packed


## Niveaux de detail (2026-10-09, « gros problemes de performance sur les
## petites configurations ») : le modele est charge a l'execution, sans
## l'import de l'editeur, donc sans LOD - 125 a 150 k triangles par camion
## dessines en entier a 50 m comme a 2 m, ombres comprises. Ils sont generes
## ici, une fois par fichier ; le moteur choisit le niveau selon la taille a
## l'ecran (un pixel d'ecart au plus : rien ne se voit). Une piece cabossee
## (BodyDamage) repart d'un maillage neuf, sans LOD.
static func _generate_lods(state: GLTFState) -> void:
	for gm: GLTFMesh in state.get_meshes():
		var im := gm.mesh
		if im != null and im.get_surface_count() > 0:
			im.generate_lods(60.0, 25.0, [])


## Distance d'affichage de chaque piece (2026-10-09, performance) : au-dela,
## elle tient dans moins d'un pixel et demi (FOV 62 deg, 1080 lignes) - un
## ecrou, une poignee, un feu de gabarit ne sont plus envoyes au rendu ni aux
## ombres quand ils sont invisibles de toute facon. L'interieur de la cabine
## (sieges, volant, tableau de bord : derriere le pare-brise fume) au-dela de
## INTERIOR_RANGE. Rien ne change pour une piece de plus d'un metre.
const PIXEL_ANGLE := 0.0015
const INTERIOR_RANGE := 30.0
const INTERIOR_MATERIALS: PackedStringArray = ["Plastique_Interieur", "Tissu_Siege"]


static func _set_visibility_ranges(root: Node3D) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _transform_to(mi, root)
		var size := (xf.basis * mi.mesh.get_aabb().size).abs()
		var span := maxf(maxf(size.x, size.y), size.z)
		var far := span / PIXEL_ANGLE
		var inside := mi.mesh.get_surface_count() > 0
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			var mat_name := String(m.resource_name) if m != null else ""
			var interior := false
			for p in INTERIOR_MATERIALS:
				interior = interior or mat_name.begins_with(p)
			inside = inside and interior
		if inside:
			far = minf(far, INTERIOR_RANGE)
		if far < 400.0:
			mi.visibility_range_end = far

## Remorque d'un vehicule du catalogue (Assets_Visuels/Armes_et_camions) : le
## noeud `Remorque` du .glb, dans le repere de la sellette. Les modeles du
## catalogue suivent deja VEHICLE_SPEC (pivot de `Remorque` a la sellette) :
## aucun ajustement. Charge une fois par chemin.
static func _trailer_template(path: String) -> PackedScene:
	if _templates.has(path):
		return _templates[path]
	_templates[path] = null
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("TruckVisual : %s illisible, remorque d'origine" % path)
		return null
	_generate_lods(state)
	var raw := doc.generate_scene(state) as Node3D
	for n in raw.find_children("*", "", true, false):
		n.owner = null
	var trailer := _first_with_prefix(raw, "Remorque")
	if trailer == null:
		raw.free()
		push_warning("TruckVisual : pas de noeud Remorque dans %s" % path)
		return null
	var xf := Transform3D(Basis.IDENTITY, TruckSpec.KINGPIN).affine_inverse() * _transform_to(trailer, raw)
	trailer.get_parent().remove_child(trailer)
	raw.free()
	trailer.transform = xf
	ShadowProxy.build(trailer, SHADOW_MOVING, SHADOW_SKIP)
	_set_visibility_ranges(trailer)
	for n in trailer.find_children("*", "", true, false):
		n.owner = trailer
	var packed := PackedScene.new()
	packed.pack(trailer)
	trailer.free()
	_templates[path] = packed
	return packed


## Construit un Node3D dans le repere du camion : corps ajuste, pivots de roue,
## pivot de remorque a la sellette.
static func _fit(raw: Node3D, strip: PackedStringArray, exclude: PackedStringArray,
		wheel_prefix: String, trailer_prefix: String) -> Node3D:
	# 1. retirer la remorque (et tout ce qui commence par un prefixe exclu)
	for n in raw.find_children("*", "Node3D", true, false):
		if not is_instance_valid(n):
			continue   # deja libere avec son parent
		for pre in strip:
			if String(n.name).begins_with(pre):
				n.get_parent().remove_child(n)
				n.free()
				break
	# 2. boite englobante du tracteur (hors parties exclues du calage), boite de
	#    l'ensemble, et groupes de roues, dans le repere du modele
	var box := AABB()
	var first := true
	var rig := AABB()
	var rig_first := true
	var groups: Array[Node3D] = []
	var group_xf: Array[Transform3D] = []
	var stack: Array = [[raw, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is Node3D and node != raw:
			xf = xf * (node as Node3D).transform
		var excluded := _under_prefix(node, raw, exclude)
		if node is MeshInstance3D:
			var a := xf * (node as MeshInstance3D).get_aabb()
			rig = a if rig_first else rig.merge(a)
			rig_first = false
			if not excluded:
				box = a if first else box.merge(a)
				first = false
		if node.get_class() == "Node3D" and String(node.name).begins_with(wheel_prefix) and not excluded:
			groups.append(node as Node3D)
			group_xf.append(xf)
		for c in node.get_children():
			stack.append([c, xf])
	if first:
		return null
	# 3. ajustement : demi-tour, echelle uniforme sur la longueur, centre, sol
	var s := SPEC_LENGTH / box.size.z
	var center := box.get_center()
	var f := Transform3D(Basis(Vector3.UP, PI).scaled(Vector3(s, s, s)), Vector3.ZERO)
	f.origin = -(f.basis * Vector3(center.x, box.position.y, center.z))
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = &"Body"
	body.transform = f
	root.add_child(body)
	# 4. chaque groupe de roues sous un pivot au moyeu (centre de sa boite)
	var hubs: Array[Vector3] = []
	for gi in groups.size():
		var g := groups[gi]
		var gbox := _subtree_aabb(g, group_xf[gi])
		hubs.append(gbox.get_center())
	for gi in groups.size():
		var g := groups[gi]
		g.get_parent().remove_child(g)
		var hub_m := hubs[gi]
		var pivot := Node3D.new()
		pivot.transform = f * Transform3D(Basis.IDENTITY, hub_m)
		var name_side := ("L" if pivot.position.x < 0.0 else "R")
		var name_axle := ("F" if pivot.position.z < 0.0 else "R")
		pivot.name = "WheelPivot_%s%s_%d" % [name_axle, name_side, gi]
		g.transform = Transform3D(group_xf[gi].basis, group_xf[gi].origin - hub_m)
		# rayon et demi-largeur du pneu, dans le repere du camion
		var gsize := _subtree_aabb(g, Transform3D(group_xf[gi].basis, Vector3.ZERO)).size * s
		# roues un peu reduites, bas du pneu toujours au sol : du jeu sous les
		# passages de roue (le modele a des roues plus grandes que la spec)
		var r := gsize.y / 2.0
		g.transform = Transform3D(g.transform.basis.scaled(Vector3.ONE * WHEEL_SCALE),
			g.transform.origin * WHEEL_SCALE)
		pivot.position.y -= r * (1.0 - WHEEL_SCALE)
		pivot.add_child(g)
		root.add_child(pivot)
		pivot.set_meta(&"tire", Vector2(r * WHEEL_SCALE, gsize.x / 2.0 * WHEEL_SCALE))
	# 4 bis. passages de roue : pieces deplacees, puis jeu mesure roue par roue
	_open_wheel_arches(raw, f, trailer_prefix)
	_measure_arches(raw, f, trailer_prefix, root)
	# 5. la semi-remorque sous un pivot a la sellette (meme pose au repos)
	var trailer := _first_with_prefix(raw, trailer_prefix)
	if trailer != null:
		var pivot := Node3D.new()
		pivot.name = TRAILER_PIVOT
		pivot.position = TruckSpec.KINGPIN
		var acc := _transform_to(trailer, raw)
		trailer.get_parent().remove_child(trailer)
		trailer.transform = pivot.transform.affine_inverse() * f * acc
		pivot.add_child(trailer)
		root.add_child(pivot)
	# le reste du modele sous le corps
	for c in raw.get_children():
		raw.remove_child(c)
		body.add_child(c)
	var fitted_box := AABB(f * box.position, Vector3.ZERO).expand(f * box.end)
	var fitted_rig := AABB(f * rig.position, Vector3.ZERO).expand(f * rig.end)
	root.set_meta(&"fit_report", {
		"scale": s,
		"size": fitted_box.size,
		"rig_size": fitted_rig.size,
		"rig_rear_z": fitted_rig.end.z,
		"wheel_groups": groups.size(),
	})
	return root


## Passages de roue du modele de l'equipe, trop justes (mesure 2026-10-06 :
## 10 cm sous les garde-boue et l'embleme, le support de marchepied dans la roue avant au
## repos) : garde-boue releves, marchepieds recules (repere du camion, m).
const ARCH_MOVES := {
	"Garde_Boue": Vector3(0.0, 0.12, 0.0),
	"Embleme": Vector3(0.0, 0.12, 0.0),
	"Marchepied": Vector3(0.0, 0.0, 0.2),
	"Support_Marche": Vector3(0.0, 0.0, 0.2),
}
## Roues de la tete reduites de 8 % (bas du pneu au sol) : 13 a 15 cm de jeu
## gagnes sous les passages de roue, que la cabine (joints de porte) bornait.
const WHEEL_SCALE := 0.92
## Jeu garde entre le pneu et la carrosserie a la butee visuelle (m).
const ARCH_SAFETY := 0.03
## Montee visuelle max des roues arriere : la remorque pivote (+-35 deg) et
## penche au-dessus d'elles ; ses pieces basses sont dessinees pour ce jeu
## (tools/blender/catalogue_tete_commune.py, REAR_WHEEL_MAX_UP : garder en accord).
const REAR_WHEEL_MAX_UP := 0.08
## Braquage visuel max quand aucun angle ne passe (garde-fou).
const MIN_VISUAL_STEER_DEG := 10.0


static func _open_wheel_arches(raw: Node3D, f: Transform3D, trailer_prefix: String) -> void:
	for n in raw.find_children("*", "Node3D", true, false):
		var node := n as Node3D
		if _under_prefix(node, raw, PackedStringArray([trailer_prefix])):
			continue
		for prefix: String in ARCH_MOVES:
			if String(node.name).begins_with(prefix):
				var parent_xf := f * _transform_to(node.get_parent() as Node3D, raw) \
					if node.get_parent() != raw else f
				node.position += parent_xf.basis.inverse() * (ARCH_MOVES[prefix] as Vector3)
				break


## Jeu sous chaque passage de roue (meta `arch` du pivot : jeu au-dessus du
## pneu, point du haut du pneu) et braquage visuel possible pour les roues
## avant (meta `visual_steer_max_deg` de la racine). Mesure une fois, sur les
## sommets de la carrosserie (ni roues, ni remorque), dans le repere du camion.
static func _measure_arches(raw: Node3D, f: Transform3D, trailer_prefix: String, root: Node3D) -> void:
	var verts := PackedVector3Array()
	for n in raw.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or _under_prefix(mi, raw, PackedStringArray([trailer_prefix])):
			continue
		var xf := f * _transform_to(mi, raw)
		for si in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				verts.append(xf * v)
	var steer_max := 90.0
	for p in root.get_children():
		var pivot := p as Node3D
		if pivot == null or not pivot.has_meta(&"tire"):
			continue
		var tire: Vector2 = pivot.get_meta(&"tire")
		var r := tire.x
		var hw := tire.y
		var hub := pivot.position
		# sommets proches : dans la bande du pneu (x), au-dessus du bas du moyeu
		var near := PackedVector3Array()
		for v in verts:
			if absf(v.x - hub.x) <= hw + 0.4 and v.y > hub.y - r * 0.3 and Vector2(v.y - hub.y, v.z - hub.z).length() < r + 0.8:
				near.append(v - hub)
		var gap := 1.0
		for d in near:
			if absf(d.x) <= hw:
				gap = minf(gap, Vector2(d.y, d.z).length() - r)
		gap = maxf(gap, 0.0)
		pivot.set_meta(&"arch", Vector4(gap, hub.x, hub.y + r, hub.z))
		if hub.z >= 0.0:
			continue
		# roue avant : plus grand angle (1 deg pres) sans sommet de carrosserie
		# dans le pneu, au repos ; les sommets deja dedans au repos ne comptent pas
		var inside0 := _inside_tire(near, r, hw, 0.0)
		var limit := 0.0
		for deg in range(1, 46):
			if _inside_tire(near, r, hw, deg_to_rad(float(deg))) > inside0 \
					or _inside_tire(near, r, hw, -deg_to_rad(float(deg))) > inside0:
				break
			limit = float(deg)
		steer_max = minf(steer_max, maxf(limit, MIN_VISUAL_STEER_DEG))
	root.set_meta(&"visual_steer_max_deg", steer_max)


## Nombre de sommets (repere du moyeu) dans le pneu braque de `angle`.
static func _inside_tire(near: PackedVector3Array, r: float, hw: float, angle: float) -> int:
	var b := Basis(Vector3.UP, -angle)
	var count := 0
	for d in near:
		var l := b * d
		if absf(l.x) <= hw and Vector2(l.y, l.z).length() <= r:
			count += 1
	return count


## Vrai si `node` ou l'un de ses ancetres (jusqu'a `root` exclu) porte un nom
## commencant par l'un des prefixes.
static func _under_prefix(node: Node, root: Node, prefixes: PackedStringArray) -> bool:
	var n := node
	while n != null and n != root:
		for pre in prefixes:
			if String(n.name).begins_with(pre):
				return true
		n = n.get_parent()
	return false


## Premier noeud (le moins profond) dont le nom commence par `prefix`.
static func _first_with_prefix(root: Node, prefix: String) -> Node3D:
	if prefix == "":
		return null
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n != root and n is Node3D and String(n.name).begins_with(prefix):
			return n as Node3D
		queue.append_array(n.get_children())
	return null


## Transformation de `node` dans le repere de `root` (celle de `root` exclue,
## comme pour les boites englobantes).
static func _transform_to(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _subtree_aabb(node: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [[node, xf]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var t: Transform3D = item[1]
		if n != node and n is Node3D:
			t = t * (n as Node3D).transform
		if n is MeshInstance3D:
			var a := t * (n as MeshInstance3D).get_aabb()
			box = a if first else box.merge(a)
			first = false
		for c in n.get_children():
			stack.append([c, t])
	return box


## Pose du camion apres le prochain pas physique, extrapolee de ses vitesses.
func _predicted_truck_xf(delta: float) -> Transform3D:
	var xf := _truck.global_transform
	var w := _truck.angular_velocity
	var angle := w.length() * delta
	if angle > 1e-6:
		xf.basis = Basis(w / w.length(), angle) * xf.basis
	xf.origin += _truck.linear_velocity * delta
	return xf
