class_name CharacterRagdoll
extends Node3D

## Personnage en ragdoll — racine de l'architecture imposée
## (cf. `.claude/agents/ragdoll-engineer.md`) :
##
##     CharacterRagdoll (Node3D)
##     ├── Skeleton3D
##     │   └── PhysicalBoneSimulator3D
##     │       └── PhysicalBone3D × 13
##     ├── PoseProvider        (tâche 1.5)
##     ├── JointDriver         (tâche 1.6)
##     ├── BalanceController   (tâche 1.7)
##     └── StunState           (tâche 1.9)
##
## Tâche 1.1 : seul le rig physique existe. Il est construit par code au
## `_ready` (`RagdollRigBuilder`) à partir de `RagdollRigSpec`, miroir de
## `docs/RIG_SPEC.md`. L'origine du nœud est au sol, entre les pieds ; le
## personnage regarde vers -Z.

## Démarre la simulation physique dès `_ready`. À désactiver pour inspecter
## le rig au repos (le squelette reste alors dans sa pose de repos).
@export var simulate_on_ready: bool = true

var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
## Os physiques, dans l'ordre de `RagdollRigSpec.BONE_NAMES`.
var bones: Array[PhysicalBone3D] = []

var _bones_by_name: Dictionary = {}
var _head: PhysicalBone3D
var _pelvis: PhysicalBone3D
var _total_mass: float = 0.0


func _ready() -> void:
	skeleton = RagdollRigBuilder.build(self)
	simulator = skeleton.get_node(RagdollRigBuilder.SIMULATOR_NAME) as PhysicalBoneSimulator3D
	for bone_name: String in RagdollRigSpec.BONE_NAMES:
		var bone := simulator.get_node(bone_name) as PhysicalBone3D
		assert(bone != null, "os physique manquant : %s" % bone_name)
		bones.append(bone)
		_bones_by_name[bone_name] = bone
		_total_mass += bone.mass
	_head = _bones_by_name["head"] as PhysicalBone3D
	_pelvis = _bones_by_name["pelvis"] as PhysicalBone3D

	if simulate_on_ready:
		start_simulation()


func start_simulation() -> void:
	simulator.physical_bones_start_simulation()


func stop_simulation() -> void:
	simulator.physical_bones_stop_simulation()


func get_bone(bone_name: StringName) -> PhysicalBone3D:
	return _bones_by_name.get(bone_name) as PhysicalBone3D


func get_head() -> PhysicalBone3D:
	return _head


func get_pelvis() -> PhysicalBone3D:
	return _pelvis


func get_total_mass() -> float:
	return _total_mass


## Centre de masse global du personnage. Sans allocation : utilisable depuis
## `_physics_process`. Le centre de chaque corps est son origine (formes
## centrées sur le `PhysicalBone3D`).
func get_center_of_mass() -> Vector3:
	var weighted := Vector3.ZERO
	for bone: PhysicalBone3D in bones:
		weighted += bone.global_position * bone.mass
	return weighted / _total_mass
