extends PhysicsTest

## Tache 1.2 — le rig INERTE (sans PD) tombe de facon credible.
##
## RIG_SPEC.md §10, etape 2 : "le perso inerte doit tomber de facon credible,
## sans membre qui se retourne". Ce test lache le rig et verifie :
##   - pas d'explosion du solveur (aucun NaN) ;
##   - aucun corps ne traverse le sol ;
##   - il s'effondre vraiment, puis s'immobilise ;
##   - au repos, chaque articulation est dans sa plage de flexion RIG_SPEC §5,
##     et les axes verrouilles des genoux tiennent (detail et limites de la
##     mesure dans _test_finish).
##
## Le controle de flexion verifie aussi la convention de signe des limites,
## mesuree par l'auteur du rig sur Godot 4.7.2 alors que le projet est fige
## sur 4.6.3 : si le moteur inversait autrement, les genoux plieraient en
## positif et sortiraient de leur plage [-135, 0].

const RIG_SCENE := "res://characters/ragdoll/character_ragdoll.tscn"

## Marge sur l'angle final, au repos. Jolt tient ses butees avec un leger jeu
## sous charge statique.
const FINAL_MARGIN_DEG := 5.0

var _rig: CharacterRagdoll
var _min_y: float = INF
var _worst: Dictionary = {}   # os -> [axe, angle, borne, depassement]


func _test_setup() -> void:
	duration_ticks = 300   # 5 s
	add_floor()
	_rig = (load(RIG_SCENE) as PackedScene).instantiate() as CharacterRagdoll
	add_child(_rig)


func _test_tick(_t: int) -> void:
	for bone in _rig.bones:
		_min_y = minf(_min_y, bone.global_position.y)
	for bone_name in CharacterTuning.DRIVEN_BONES:
		_track_limits(bone_name)


func _test_finish() -> void:
	var all_finite := true
	var max_speed := 0.0
	for bone in _rig.bones:
		if not (bone.global_position.is_finite() and bone.linear_velocity.is_finite()):
			all_finite = false
		max_speed = maxf(max_speed, bone.linear_velocity.length())

	check("aucun NaN apres 5 s de chute", all_finite, "positions et vitesses finies=%s" % all_finite)
	check_above("aucun corps sous le sol", _min_y, -0.05)
	check_below("le rig inerte s'est effondre (tete)", _rig.get_head().global_position.y, 0.6)
	check_below("le rig est immobile apres 5 s (m/s)", max_speed, 0.2)

	# --- limites articulaires, sur ce que la mesure sait trancher ------------
	#
	# Ce qu'on VERIFIE :
	#   - l'angle de flexion (X) final de chaque articulation, au repos ;
	#   - les axes verrouilles des GENOUX, seule articulation a un seul axe
	#     libre : la decomposition d'Euler y est exacte.
	#
	# Ce qu'on NE verifie PAS, volontairement :
	#   - les pics pendant la chute : Jolt laisse depasser une butee sous choc
	#     (mesure : +10,5 deg aux genoux a l'impact, retour a -85 deg au repos).
	#     Ils sont affiches ci-dessous, pas comptes comme des echecs.
	#   - les axes verrouilles des articulations a PLUSIEURS axes libres (coude,
	#     cheville, epaule) : quand deux axes bougent a la fois, une
	#     decomposition d'Euler ne correspond pas a celle de la contrainte Jolt,
	#     et fait apparaitre de faux angles sur l'axe verrouille (jusqu'a 15 deg
	#     au repos sur un coude). Il faut une decomposition swing-twist pour
	#     trancher : TODO, a ecrire avant de s'appuyer sur ces limites.
	var x_out: PackedStringArray = []
	for bone_name in CharacterTuning.DRIVEN_BONES:
		var lim: Vector2 = RagdollRigSpec.joint_limits_deg(bone_name)[0]
		var x := _angles_of(bone_name).x
		if x < lim.x - FINAL_MARGIN_DEG or x > lim.y + FINAL_MARGIN_DEG:
			x_out.append("%s X=%.1f hors [%.0f, %.0f]" % [bone_name, x, lim.x, lim.y])
	check("flexion (X) de chaque articulation dans sa plage, au repos",
		x_out.is_empty(), "hors plage=%s" % str(x_out))

	var knee_drift := 0.0
	for knee in [&"shin_l", &"shin_r"]:
		var a := _angles_of(knee)
		knee_drift = maxf(knee_drift, maxf(absf(a.y), absf(a.z)))
	check_below("genoux : axes verrouilles Y et Z tenus au repos (deg)", knee_drift, 2.0)

	# Detail par articulation : le plus grand depassement observe (pic) et
	# l'angle final, au repos. Un pic sous choc est tolere par Jolt ; un
	# depassement qui PERSISTE au repos est un defaut de contrainte.
	for bone_name in CharacterTuning.DRIVEN_BONES:
		var f := _angles_of(bone_name)
		var peak := ""
		if _worst.has(bone_name):
			var w: Array = _worst[bone_name]
			peak = "pic : axe %s %6.1f (borne %6.1f, +%4.1f)" % [w[0], w[1], w[2], w[3]]
		print("  INFO   %-11s final X=%7.1f Y=%6.1f Z=%6.1f   %s" % [bone_name, f.x, f.y, f.z, peak])


func _angles_of(bone_name: StringName) -> Vector3:
	var child := _rig.get_bone(bone_name)
	var parent := _rig.get_bone(StringName(RagdollRigSpec.parent_of(bone_name)))
	var e := (parent.global_basis.inverse() * child.global_basis).get_euler(EULER_ORDER_XYZ)
	return Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))


## Rotation de l'enfant dans le repere de son parent, comparee a RIG_SPEC §5.
## Les bases de repos sont l'identite (membres alignes sur les axes), donc la
## rotation relative courante EST la rotation articulaire.
func _track_limits(bone_name: StringName) -> void:
	var child := _rig.get_bone(bone_name)
	var parent := _rig.get_bone(StringName(RagdollRigSpec.parent_of(bone_name)))
	var rel := parent.global_basis.inverse() * child.global_basis
	# Ordre XYZ, pas l'ordre par defaut YXZ : l'angle du MILIEU d'une
	# decomposition d'Euler est borne a +/-90 deg. En YXZ c'est X, alors qu'un
	# genou plie jusqu'a 135 deg et une hanche jusqu'a 110 : au-dela de 90, la
	# decomposition bascule et invente des 180 deg sur Y et Z (premiere version
	# de ce test : faux depassements de 180 deg aux genoux et aux hanches). En
	# XYZ, l'angle du milieu est Y, dont les plages ne depassent pas +/-70.
	var e := rel.get_euler(EULER_ORDER_XYZ)
	var angles := Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))

	var limits: Array[Vector2] = RagdollRigSpec.joint_limits_deg(bone_name)
	# Cote gauche : Y et Z en miroir de la table (ecrite pour le cote droit).
	var left := String(bone_name).ends_with("_l")
	for axis in 3:
		var lo: float = limits[axis].x
		var hi: float = limits[axis].y
		if left and axis > 0:
			var tmp := lo
			lo = -hi
			hi = -tmp
		var a: float = angles[axis]
		var excess := 0.0
		var bound := 0.0
		if a < lo:
			excess = lo - a
			bound = lo
		elif a > hi:
			excess = a - hi
			bound = hi
		if excess > 0.0 and (not _worst.has(bone_name) or excess > (_worst[bone_name] as Array)[3]):
			_worst[bone_name] = ["XYZ"[axis], a, bound, excess]
