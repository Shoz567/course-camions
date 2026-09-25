extends PhysicsTest

## Test de conformité géométrique du rig (Tâche 1.3).
## Vérifie au repos (sans simulation physique, t=0 géométrique) :
## - 13 os physiques
## - Masse totale = 70.0 kg (±0.1 kg)
## - Hauteur du centre de la tête = 1.46 m (±0.03 m)
## - Centre de masse global = 0.846 m (±0.03 m)

const REF_HEAD_Y: float = 1.46
const REF_COM_Y: float = 0.846
const REF_MASS: float = 70.0
const REF_BONE_COUNT: int = 13
const TOLERANCE_METERS: float = 0.03
const TOLERANCE_MASS: float = 0.1

func _test_setup() -> void:
	duration_ticks = 1
	var ragdoll_scene: PackedScene = load("res://characters/ragdoll/character_ragdoll.tscn")
	if ragdoll_scene == null:
		abort("Impossible de charger character_ragdoll.tscn")
		return

	var ragdoll: CharacterRagdoll = ragdoll_scene.instantiate() as CharacterRagdoll
	ragdoll.simulate_on_ready = false
	ragdoll.drive_enabled = false
	add_child(ragdoll)

	# 1. Nombre d'os
	var count := ragdoll.bones.size()
	check("13 os physiques presents", count == REF_BONE_COUNT, "compte=%d attendu=%d" % [count, REF_BONE_COUNT])

	# 2. Masse totale
	check_near("masse totale = 70.0 kg", ragdoll.get_total_mass(), REF_MASS, TOLERANCE_MASS)

	# 3. Hauteur de la tête (via get_bone_body)
	var head: PhysicalBone3D = ragdoll.get_bone_body(&"head")
	if head != null:
		check_near("hauteur centre tete (y)", head.global_position.y, REF_HEAD_Y, TOLERANCE_METERS)
	else:
		abort("Os 'head' introuvable")

	# 4. Centre de masse
	var com: Vector3 = ragdoll.get_center_of_mass()
	check_near("centre de masse (y)", com.y, REF_COM_Y, TOLERANCE_METERS)
