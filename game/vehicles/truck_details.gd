class_name TruckDetails
extends RefCounted

## Details qui separent un vrai camion d'un jouet (2026-10-07, « pas qu'ils
## ressemblent a des jouets ») :
##   - les cones de flamme figes au bout des cheminees d'echappement
##     disparaissent (les flammes du boost restent : TruckVfx) ;
##   - des bavettes de caoutchouc pendent derriere les dernieres roues du
##     tracteur et de la remorque (sauf si le modele en a deja).
## Elles s'arrachent dans un gros choc (BodyDamage, prefixe « Bavette »).
## Purement visuel.

const FLAP_PREFIX := "Bavette"
const FLAP_THICKNESS := 0.025
## Garde au sol du bas de la bavette (m).
const FLAP_CLEARANCE := 0.22

static var _rubber: Material


## Retire les pieces de decor « jouet » du modele. Renvoie leur nombre.
static func strip_toy_parts(model: Node) -> int:
	var count := 0
	for n in model.find_children("Flamme*", "MeshInstance3D", true, false):
		n.get_parent().remove_child(n)
		n.queue_free()
		count += 1
	return count


## Vrai si `root` a deja des bavettes (modele de l'equipe), hors celles dont
## le nom commence par `ignore` (la remorque d'origine, cachee, du tracteur).
static func has_flaps(root: Node, ignore: String = "") -> bool:
	for n in root.find_children("*Bavette*", "Node3D", true, false):
		if ignore == "" or not String(n.name).begins_with(ignore):
			return true
	return false


## Bavette sous `parent`, derriere une roue : centre de la roue `hub`
## (repere du parent), rayon `radius`, sur `width` m de large, l'arriere
## en +Z. `ground_y` : hauteur du sol dans le repere du parent.
static func add_flap(parent: Node3D, hub: Vector3, radius: float, width: float, ground_y: float,
		label: String) -> MeshInstance3D:
	var top := hub.y + radius * 0.15
	var bottom := ground_y + FLAP_CLEARANCE
	var h := maxf(top - bottom, 0.2)
	var box := BoxMesh.new()
	box.size = Vector3(width, h, FLAP_THICKNESS)
	var mi := MeshInstance3D.new()
	mi.name = "%s_%s" % [FLAP_PREFIX, label]
	mi.mesh = box
	mi.position = Vector3(hub.x, bottom + h / 2.0, hub.z + radius + 0.18)
	mi.set_surface_override_material(0, _rubber_material())
	parent.add_child(mi)
	# patte de fixation en acier, au-dessus
	var bar := MeshInstance3D.new()
	bar.name = "Support_%s" % label
	var bar_box := BoxMesh.new()
	bar_box.size = Vector3(width + 0.06, 0.05, 0.05)
	bar.mesh = bar_box
	bar.position = Vector3(0.0, h / 2.0 + 0.025, 0.0)
	var steel := StandardMaterial3D.new()
	steel.resource_name = "Chassis_Support"
	steel.albedo_color = Color(0.2, 0.2, 0.21)
	bar.set_surface_override_material(0, steel)
	mi.add_child(bar)
	return mi


static func _rubber_material() -> Material:
	if _rubber == null:
		var m := StandardMaterial3D.new()
		m.resource_name = "Caoutchouc_Bavette"
		m.albedo_color = Color(0.05, 0.05, 0.05)
		_rubber = m
	return _rubber
