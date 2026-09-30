class_name TruckVisual
extends Node3D

## Habillage visuel du camion. Purement visuel : ne lit que l'etat du camion
## (rayons, braquage) et n'agit jamais sur la physique.
##
## - Roues : suivent le debattement de leur rayon et le braquage.
## - Modele externe optionnel (.glb des camarades, Assets_Visuels/, hors git) :
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
## Les ecarts restants sont documentes (docs/ART_PIPELINE.md §4 bis).

## Chemin du modele, relatif au dossier du projet Godot (game/). Vide = boites.
@export var external_model: String = "../Assets_Visuels/Camion/Camions_Course_Export/Camion_Bleu.glb"
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

## En headless (tests), le modele n'est pas charge : rien a voir, et les tests
## ne doivent pas dependre d'un fichier hors depot. Un test peut forcer.
static var load_external_in_headless: bool = false

const SPEC_LENGTH := TruckSpec.CHASSIS_SIZE.z
const MODEL_ROOT := &"ExternalModel"
const TRAILER_PIVOT := &"TrailerPivot"

## Chemin absolu -> PackedScene du modele ajuste (null si absent ou illisible).
## Une ressource, pas un noeud orphelin : rien ne fuit a la sortie.
static var _templates: Dictionary = {}

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


## Apres le camion (enfant : meme tick, apres ses forces). Les transformations
## posees ici sont interpolees au rendu (physics interpolation).
func _physics_process(delta: float) -> void:
	if _truck == null:
		return
	_update_lean(delta)
	if _trailer_pivot != null:
		_trailer_pivot.basis = Basis(Vector3.UP, _truck.get_trailer_angle()) \
			* Basis(Vector3.BACK, deg_to_rad(_lean.y * lean_trailer_roll_ratio))
		# remorque larguee : elle est sur la route, plus derriere le tracteur
		_trailer_pivot.visible = not _truck.is_trailer_detached()
	if _pivots.is_empty():
		return
	var steer := Basis(Vector3.UP, -deg_to_rad(_truck.get_steer_deg()))
	var rest_hub := TruckSpec.rest_hub_distance()
	for i in _pivots.size():
		var p := _pivots[i]
		if p == null:
			continue
		var probe := _truck.get_probe(_probe_index(i))
		var xf := _rest[i]
		xf.origin.y += rest_hub - probe.hub_distance
		if _steers[i]:
			xf.basis = steer * xf.basis
		p.transform = xf


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
	_body.transform = Transform3D(lean_basis, pivot - lean_basis * pivot) * _body_rest


## Copie de la remorque (modele ou boite), dans le repere de la sellette : le
## visuel de la remorque larguee. Maillages partages, rien n'est recharge.
func make_trailer_copy() -> Node3D:
	if _trailer_pivot == null:
		return null
	var copy := _trailer_pivot.duplicate() as Node3D
	copy.transform = Transform3D.IDENTITY
	copy.visible = true
	return copy


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
	# les boites de blockout s'effacent, sans disparaitre (tests, repli)
	for n in [&"Body", TRAILER_PIVOT, &"Wheel_FL", &"Wheel_FR", &"Wheel_RL", &"Wheel_RR"]:
		var mock := get_node_or_null(NodePath(n)) as Node3D
		if mock != null:
			mock.visible = false
	model_loaded = true


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
	var raw := doc.generate_scene(state) as Node3D
	# on va deplacer des noeuds : plus de proprietaire le temps de l'ajustement
	for n in raw.find_children("*", "", true, false):
		n.owner = null
	var fitted := _fit(raw, strip, exclude, wheel_prefix, trailer_prefix)
	raw.free()
	if fitted == null:
		return null
	for n in fitted.find_children("*", "", true, false):
		n.owner = fitted
	var packed := PackedScene.new()
	packed.pack(fitted)
	fitted.free()
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
		pivot.add_child(g)
		root.add_child(pivot)
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
