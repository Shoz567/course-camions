class_name RagdollRigSpec
extends RefCounted

## Miroir en code de `docs/RIG_SPEC.md` §2-§4, §6, §7.
##
## Ce fichier n'est PAS du tuning : c'est la copie du contrat partagé avec
## `tools/blender/`. Toute valeur ici doit être identique à RIG_SPEC.md. Un
## changement se demande sur le contrat d'abord (CLAUDE.md §8), puis se
## reporte ici — jamais l'inverse.
##
## Conventions du rig placeholder :
## - 1 unité = 1 m, sol à y = 0, personnage tourné vers -Z (avant de Godot) ;
##   son côté gauche est donc en -X, son côté droit en +X.
## - Tous les `bone_rest` ont une base IDENTITÉ : seuls les décalages changent.
##   Les axes de chaque os coïncident donc avec ceux du monde au repos :
##   X = flexion, Y = torsion (axe des membres, verticaux au repos),
##   Z = abduction — exactement le repère de la table §5.
## - L'origine d'un os est son articulation avec le parent. Le corps physique
##   est décalé au milieu du segment (`body_offset`), et le joint est ramené à
##   l'origine de l'os (`joint_offset` = inverse de `body_offset`).
## - Exception : `pelvis` (racine) a son origine au centre de sa boîte.

enum Shape { BOX, CAPSULE, SPHERE }

## Direction de chaque segment depuis son articulation, au repos.
const UP := Vector3.UP
const DOWN := Vector3.DOWN

## Ordre canonique des 13 os simulés. Un parent précède toujours ses enfants.
const BONE_NAMES: PackedStringArray = [
	"pelvis",
	"spine",
	"head",
	"upperarm_l", "forearm_l",
	"upperarm_r", "forearm_r",
	"thigh_l", "shin_l", "foot_l",
	"thigh_r", "shin_r", "foot_r",
]

## Table §3 : parent, longueur (m), masse (kg), forme, dimensions de la forme.
## `size` : boîte → (x, y, z) ; capsule/sphère → (rayon, 0, 0).
const BONES: Dictionary = {
	"pelvis":     { "parent": "",           "length": 0.17, "mass": 12.0, "shape": Shape.BOX,     "size": Vector3(0.30, 0.17, 0.20) },
	"spine":      { "parent": "pelvis",     "length": 0.38, "mass": 19.0, "shape": Shape.CAPSULE, "size": Vector3(0.17, 0.0, 0.0) },
	"head":       { "parent": "spine",      "length": 0.28, "mass": 5.0,  "shape": Shape.SPHERE,  "size": Vector3(0.15, 0.0, 0.0) },
	"upperarm_l": { "parent": "spine",      "length": 0.26, "mass": 2.5,  "shape": Shape.CAPSULE, "size": Vector3(0.07, 0.0, 0.0) },
	"upperarm_r": { "parent": "spine",      "length": 0.26, "mass": 2.5,  "shape": Shape.CAPSULE, "size": Vector3(0.07, 0.0, 0.0) },
	"forearm_l":  { "parent": "upperarm_l", "length": 0.28, "mass": 1.8,  "shape": Shape.CAPSULE, "size": Vector3(0.06, 0.0, 0.0) },
	"forearm_r":  { "parent": "upperarm_r", "length": 0.28, "mass": 1.8,  "shape": Shape.CAPSULE, "size": Vector3(0.06, 0.0, 0.0) },
	"thigh_l":    { "parent": "pelvis",     "length": 0.36, "mass": 8.0,  "shape": Shape.CAPSULE, "size": Vector3(0.09, 0.0, 0.0) },
	"thigh_r":    { "parent": "pelvis",     "length": 0.36, "mass": 8.0,  "shape": Shape.CAPSULE, "size": Vector3(0.09, 0.0, 0.0) },
	"shin_l":     { "parent": "thigh_l",    "length": 0.33, "mass": 3.5,  "shape": Shape.CAPSULE, "size": Vector3(0.07, 0.0, 0.0) },
	"shin_r":     { "parent": "thigh_r",    "length": 0.33, "mass": 3.5,  "shape": Shape.CAPSULE, "size": Vector3(0.07, 0.0, 0.0) },
	"foot_l":     { "parent": "shin_l",     "length": 0.20, "mass": 1.2,  "shape": Shape.BOX,     "size": Vector3(0.10, 0.08, 0.22) },
	"foot_r":     { "parent": "shin_r",     "length": 0.20, "mass": 1.2,  "shape": Shape.BOX,     "size": Vector3(0.10, 0.08, 0.22) },
}

const TOTAL_MASS_KG := 70.0
const STANDING_HEIGHT_M := 1.60

## Hauteur de cheville = hauteur de la boîte du pied (§3, note sous la table).
const ANKLE_HEIGHT_M := 0.08

## --- Placement latéral / vertical des attaches : NON spécifié par RIG_SPEC ---
## Valeurs dérivées, justifiées une par une.

## Épaule : 4 cm sous la base du cou. Dérivé de §4 : centre de `upperarm` à
## y = 1,15 et longueur 0,26 → épaule à 1,28 ; base du cou à 1,32.
const SHOULDER_DROP_M := 0.04
## Épaule à ±0,25 m : rayon du torse 0,17 + rayon du bras 0,07 = 0,24, plus
## 1 cm de jeu pour que les capsules ne s'interpénètrent pas au repos.
const SHOULDER_HALF_WIDTH_M := 0.25
## Hanche à ±0,125 m : jambes verticales au repos → pieds écartés de 0,25 m,
## l'écart de la pose `idle` (§8). Reste dans la boîte du bassin (±0,15).
const HIP_HALF_WIDTH_M := 0.125
## Le centre de la boîte du pied est 5 cm en avant (-Z) de la cheville :
## talon 6 cm derrière, orteils 16 cm devant.
const FOOT_FORWARD_OFFSET_M := 0.05

## Couches de collision §7 (numéros de couche, 1-based).
const LAYER_WORLD := 1
const LAYER_PLAYER_BODY := 2

## Matériaux §6 : [friction, rebond]. « torse, tête, cuisses » = défaut.
const MATERIAL_DEFAULT := Vector2(0.4, 0.05)
const MATERIAL_BY_BONE: Dictionary = {
	"foot_l": Vector2(1.2, 0.0),
	"foot_r": Vector2(1.2, 0.0),
	"forearm_l": Vector2(0.9, 0.0),
	"forearm_r": Vector2(0.9, 0.0),
}

## Marqueurs de main (§2) : portés par l'avant-bras, à son extrémité.
const HAND_MARKERS: Dictionary = {
	"forearm_l": "hand_l",
	"forearm_r": "hand_r",
}


static func parent_of(bone: String) -> String:
	return (BONES[bone] as Dictionary)["parent"] as String


static func length_of(bone: String) -> float:
	return (BONES[bone] as Dictionary)["length"] as float


static func mass_of(bone: String) -> float:
	return (BONES[bone] as Dictionary)["mass"] as float


static func shape_of(bone: String) -> Shape:
	return (BONES[bone] as Dictionary)["shape"] as Shape


static func size_of(bone: String) -> Vector3:
	return (BONES[bone] as Dictionary)["size"] as Vector3


## -1 pour le côté gauche (-X), +1 pour le droit, 0 pour l'axe du corps.
static func side_of(bone: String) -> float:
	if bone.ends_with("_l"):
		return -1.0
	if bone.ends_with("_r"):
		return 1.0
	return 0.0


## Direction du segment depuis son articulation, au repos.
static func direction_of(bone: String) -> Vector3:
	if bone == "spine" or bone == "head":
		return UP
	return DOWN


## Position de la racine `pelvis` dans l'espace du squelette : centre de la
## boîte, posée sur des jambes tendues (§4 : bas du bassin à 0,77 m).
static func pelvis_rest_origin() -> Vector3:
	var hip_y: float = ANKLE_HEIGHT_M + length_of("shin_l") + length_of("thigh_l")
	return Vector3(0.0, hip_y + length_of("pelvis") * 0.5, 0.0)


## Décalage de l'origine de `bone` dans le repère de son parent (= bone_rest.origin).
static func rest_offset(bone: String) -> Vector3:
	var side: float = side_of(bone)
	var parent: String = parent_of(bone)
	match bone:
		"pelvis":
			return pelvis_rest_origin()
		"spine":
			return Vector3(0.0, length_of("pelvis") * 0.5, 0.0)
		"head":
			return Vector3(0.0, length_of("spine"), 0.0)
		"upperarm_l", "upperarm_r":
			return Vector3(side * SHOULDER_HALF_WIDTH_M, length_of("spine") - SHOULDER_DROP_M, 0.0)
		"thigh_l", "thigh_r":
			return Vector3(side * HIP_HALF_WIDTH_M, -length_of("pelvis") * 0.5, 0.0)
	# Maillon de chaîne : l'articulation est à l'extrémité du parent.
	return direction_of(parent) * length_of(parent)


## Position du centre du corps physique dans le repère de l'os (= body_offset.origin).
static func body_center_offset(bone: String) -> Vector3:
	match bone:
		"pelvis":
			return Vector3.ZERO
		"foot_l", "foot_r":
			return Vector3(0.0, -size_of(bone).y * 0.5, -FOOT_FORWARD_OFFSET_M)
	return direction_of(bone) * length_of(bone) * 0.5
