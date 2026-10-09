class_name TruckLights
extends RefCounted

## Phares qui eclairent vraiment (2026-10-07, realisme) : la nuit (Cyber
## City), deux projecteurs sous les phares avant du tracteur eclairent la
## route devant le camion, et les feux arriere de la remorque baignent le sol
## de rouge. De jour, les lampes restent eteintes (seuls les verres brillent).
## Sans ombres : 6 camions x 4 lampes restent bon marche en rendu Forward+
## (eclairage par grappes). Purement visuel.

## Vrai sur un circuit de nuit : a poser avant de creer les camions
## (LocalRace).
static var night: bool = false

const HEAD_PREFIX := "Phare_0"
const HEAD_RANGE := 70.0
const HEAD_ANGLE_DEG := 26.0
const HEAD_ENERGY := 9.0
## Les phares visent la route : un peu vers le bas (degres).
const HEAD_TILT_DEG := 4.0
const HEAD_COLOR := Color(1.0, 0.95, 0.86)
const TAIL_COLOR := Color(1.0, 0.06, 0.03)
const TAIL_RANGE := 5.0
const TAIL_ENERGY := 1.6
## Hauteur des feux arriere de la remorque au-dessus du sol (m).
const TAIL_HEIGHT := 1.3
const GROUP := &"truck_lamp"


## Projecteurs sous les phares avant du modele `model` (maillages Phare_0*).
static func add_headlights(model: Node3D) -> int:
	if not night:
		return 0
	var count := 0
	for n in model.find_children(HEAD_PREFIX + "*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var spot := SpotLight3D.new()
		spot.name = "Lamp_" + mi.name
		spot.add_to_group(GROUP)
		spot.light_color = HEAD_COLOR
		spot.light_energy = HEAD_ENERGY
		spot.spot_range = HEAD_RANGE
		spot.spot_angle = HEAD_ANGLE_DEG
		spot.spot_angle_attenuation = 0.6
		spot.spot_attenuation = 0.5
		spot.light_specular = 0.6
		# halo dans la bruine (brouillard volumetrique), sans aveugler
		spot.light_volumetric_fog_energy = 0.35
		spot.shadow_enabled = false
		spot.distance_fade_enabled = true
		spot.distance_fade_begin = 120.0
		spot.distance_fade_length = 40.0
		# sous le parent du verre (il suit le penche de la caisse), mais vise
		# dans le repere du camion (avant en -Z) : le parent peut etre
		# retourne dans le modele
		var ab := mi.get_aabb()
		var to_model := model.global_transform.affine_inverse() * mi.global_transform
		var at := to_model * (ab.position + ab.size / 2.0) + Vector3(0.0, 0.0, -0.1)
		var aim := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-HEAD_TILT_DEG)), at)
		var parent := mi.get_parent() as Node3D
		var parent_in_model := model.global_transform.affine_inverse() * parent.global_transform
		var local := parent_in_model.affine_inverse() * aim
		spot.transform = Transform3D(local.basis.orthonormalized(), local.origin)
		parent.add_child(spot)
		count += 1
	return count


## Feux arriere au bout de la remorque (caisse `box_size` centree en
## `box_center`, repere du camion), sous `pivot` (TrailerPivot, origine a la
## sellette). Remplace ceux de la remorque precedente.
static func set_tail_lights(pivot: Node3D, box_center: Vector3, box_size: Vector3) -> void:
	for c in pivot.get_children():
		if c.is_in_group(GROUP):
			pivot.remove_child(c)
			c.queue_free()
	if not night:
		return
	var rear := box_center - TruckSpec.KINGPIN + Vector3(0.0, 0.0, box_size.z / 2.0 + 0.15)
	rear.y = TAIL_HEIGHT - TruckSpec.KINGPIN.y
	for side: float in [-1.0, 1.0]:
		var l := OmniLight3D.new()
		l.name = "TailLamp%s" % ("L" if side < 0.0 else "R")
		l.add_to_group(GROUP)
		l.light_color = TAIL_COLOR
		l.light_energy = TAIL_ENERGY
		l.omni_range = TAIL_RANGE
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 60.0
		l.distance_fade_length = 20.0
		l.position = rear + Vector3(side * (box_size.x / 2.0 - 0.3), 0.0, 0.0)
		pivot.add_child(l)
