class_name RagdollRigBuilder
extends RefCounted

## Construit par code le rig physique placeholder (tâche 1.1) :
##
##     Skeleton3D
##     └── PhysicalBoneSimulator3D
##         └── PhysicalBone3D × 13
##
## Toutes les données viennent de `RagdollRigSpec` (miroir de RIG_SPEC.md).
##
## ⚠️ Piège mesuré au spike S4 : `physical_bones_start_simulation()` place les
## corps d'après les `bone_rest` du SQUELETTE. C'est donc le squelette qui porte
## la géométrie ; le `PhysicalBone3D` ne porte que le décalage du corps par
## rapport à son os (`body_offset`) et celui de son joint (`joint_offset`).
##
## Hors périmètre (tâche 1.2) : les limites angulaires. Chaque os non racine
## reçoit `joint_type = JOINT_TYPE_6DOF` (structure du rig), mais aucune
## propriété `joint_constraints/*` n'est écrite ici.

const SKELETON_NAME := "Skeleton3D"
const SIMULATOR_NAME := "PhysicalBoneSimulator3D"


## Construit le squelette et ses os physiques, et les ajoute sous `root`.
## Renvoie le `Skeleton3D` créé.
static func build(root: Node3D) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = SKELETON_NAME
	_add_skeleton_bones(skeleton)

	var simulator := PhysicalBoneSimulator3D.new()
	simulator.name = SIMULATOR_NAME
	skeleton.add_child(simulator)

	var bones: Array[PhysicalBone3D] = []
	for bone_name: String in RagdollRigSpec.BONE_NAMES:
		var bone: PhysicalBone3D = _make_physical_bone(bone_name)
		simulator.add_child(bone)
		bones.append(bone)

	_exclude_self_collisions(bones)

	# Ajout à l'arbre en dernier : à l'entrée dans l'arbre, chaque
	# PhysicalBone3D résout son `bone_name` et se place d'après le squelette,
	# qui doit donc être complet.
	root.add_child(skeleton)
	return skeleton


static func _add_skeleton_bones(skeleton: Skeleton3D) -> void:
	for bone_name: String in RagdollRigSpec.BONE_NAMES:
		var index: int = skeleton.add_bone(bone_name)
		var parent: String = RagdollRigSpec.parent_of(bone_name)
		if parent != "":
			var parent_index: int = skeleton.find_bone(parent)
			assert(parent_index >= 0, "parent inconnu pour %s : %s" % [bone_name, parent])
			skeleton.set_bone_parent(index, parent_index)
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, RagdollRigSpec.rest_offset(bone_name)))
	# `set_bone_rest` ne touche pas à la pose courante : on l'aligne sur le repos.
	skeleton.reset_bone_poses()


static func _make_physical_bone(bone_name: String) -> PhysicalBone3D:
	var bone := PhysicalBone3D.new()
	bone.name = bone_name
	bone.bone_name = bone_name
	bone.mass = RagdollRigSpec.mass_of(bone_name)

	var body_offset := Transform3D(Basis.IDENTITY, RagdollRigSpec.body_center_offset(bone_name))
	bone.body_offset = body_offset
	# Le joint est à l'origine de l'os, c'est-à-dire l'articulation avec le parent.
	bone.joint_offset = body_offset.affine_inverse()
	# Valeurs par défaut du 6DOF (mesurées) : 3 axes linéaires ET 3 axes
	# angulaires limités à [0, 0] → rig soudé en statue tant que la tâche 1.2
	# n'a pas posé les limites de RIG_SPEC §5.
	if RagdollRigSpec.parent_of(bone_name) != "":
		bone.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF

	var material: Vector2 = RagdollRigSpec.MATERIAL_BY_BONE.get(bone_name, RagdollRigSpec.MATERIAL_DEFAULT)
	# `PhysicalBone3D.friction` refuse toute valeur > 1 (erreur moteur
	# « p_friction > 1 »), alors que RIG_SPEC §6 exige 1,2 aux pieds. Le
	# serveur, lui, l'accepte et la conserve à travers stop/start de la
	# simulation (mesuré) : la propriété reçoit la valeur bornée, le corps
	# reçoit la valeur du contrat.
	bone.friction = minf(material.x, 1.0)
	PhysicsServer3D.body_set_param(bone.get_rid(), PhysicsServer3D.BODY_PARAM_FRICTION, material.x)
	bone.bounce = material.y

	bone.collision_layer = 0
	bone.collision_mask = 0
	bone.set_collision_layer_value(RagdollRigSpec.LAYER_PLAYER_BODY, true)
	bone.set_collision_mask_value(RagdollRigSpec.LAYER_WORLD, true)
	bone.set_collision_mask_value(RagdollRigSpec.LAYER_PLAYER_BODY, true)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = _make_shape(bone_name)
	bone.add_child(collision)

	if RagdollRigSpec.HAND_MARKERS.has(bone_name):
		var hand := Marker3D.new()
		hand.name = RagdollRigSpec.HAND_MARKERS[bone_name] as String
		# Extrémité du segment, exprimée dans le repère du corps.
		var bone_end: Vector3 = RagdollRigSpec.direction_of(bone_name) * RagdollRigSpec.length_of(bone_name)
		hand.position = bone_end - body_offset.origin
		bone.add_child(hand)

	return bone


static func _make_shape(bone_name: String) -> Shape3D:
	var size: Vector3 = RagdollRigSpec.size_of(bone_name)
	match RagdollRigSpec.shape_of(bone_name):
		RagdollRigSpec.Shape.BOX:
			var box := BoxShape3D.new()
			box.size = size
			return box
		RagdollRigSpec.Shape.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = size.x
			return sphere
	# Capsule le long de Y local = axe du segment (bases identité, membres
	# verticaux au repos). `height` Godot = longueur totale, calottes comprises.
	var capsule := CapsuleShape3D.new()
	capsule.radius = size.x
	capsule.height = RagdollRigSpec.length_of(bone_name)
	return capsule


## RIG_SPEC §7 : les os d'un même personnage ne se collisionnent pas entre eux.
static func _exclude_self_collisions(bones: Array[PhysicalBone3D]) -> void:
	for i: int in bones.size():
		for j: int in range(i + 1, bones.size()):
			bones[i].add_collision_exception_with(bones[j])
