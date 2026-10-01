extends PhysicsTest

## Habillage visuel externe (Assets_Visuels/, hors depot). SAUTE si le modele
## est absent : un clone neuf n'a pas ce dossier, et c'est normal.
##
## Verifie que l'ajustement fait suivre au modele VEHICLE_SPEC.md sans toucher
## a la physique : avant en -Z, tracteur a la longueur de la spec, semi-remorque
## affichee et couverte par sa boite de collision (VEHICLE_SPEC §5 bis), bas des
## pneus au sol, 4 rayons couverts par des roues, roues avant a l'avant, roues
## qui suivent le debattement, et toujours exactement 3 formes de collision.

var _truck: Truck
var _visual: TruckVisual
var _pivot_y0: float = 0.0
var _pivot: Node3D
var _moved: float = 0.0


func _test_setup() -> void:
	duration_ticks = 120
	TruckVisual.load_external_in_headless = true
	add_floor()
	_truck = TruckTestUtil.spawn_truck(self, Vector3(0.0, 1.5, 0.0))
	_visual = _truck.get_node("Visual") as TruckVisual
	if not _visual.model_loaded:
		skip("modele externe absent (%s) : le camion reste en boites" % _visual.external_model)
		return
	_pivot = _visual.get_node("ExternalModel").find_children("WheelPivot_F*", "Node3D", false, false)[0] as Node3D


func _test_tick(t: int) -> void:
	if t == 1:
		_pivot_y0 = _pivot.position.y
	_moved = maxf(_moved, absf(_pivot.position.y - _pivot_y0))


func _test_finish() -> void:
	var r: Dictionary = _visual.fit_report
	var size: Vector3 = r["size"]
	check_near("longueur du tracteur ajuste (m)", size.z, TruckSpec.CHASSIS_SIZE.z, 0.01)
	var rig: Vector3 = r["rig_size"]
	print("  INFO   modele ajuste : echelle %.3f, tracteur %.2f x %.2f x %.2f m, ensemble %.2f x %.2f x %.2f m"
		% [r["scale"], size.x, size.y, size.z, rig.x, rig.y, rig.z])
	var model := _visual.get_node("ExternalModel")
	check("semi-remorque affichee", not model.find_children("Remorque*", "", true, false).is_empty())
	# la boite de collision couvre la caisse de la remorque, a 0,5 m pres
	var rear_visual: float = r["rig_rear_z"]
	var rear_box := TruckSpec.TRAILER_CENTER.z + TruckSpec.TRAILER_SIZE.z / 2.0
	check_near("arriere de la remorque : collision / visuel (m)", rear_box, rear_visual, 0.5)
	var pivots := model.find_children("WheelPivot_*", "Node3D", false, false)
	check("au moins 4 groupes de roues", pivots.size() >= 4, "n=%d" % pivots.size())
	var fronts := model.find_children("WheelPivot_F*", "Node3D", false, false)
	check("roues avant vers -Z (avant de la spec)", not fronts.is_empty(), "n=%d" % fronts.size())
	check("les roues suivent le debattement (m)", _moved > 0.02, "deplacement=%.3f" % _moved)
	var shapes := 0
	for c in _truck.get_children():
		if c is CollisionShape3D:
			shapes += 1
	check("physique intacte : 3 formes de collision", shapes == 3, "n=%d" % shapes)
	check("boites de blockout masquees", not (_visual.get_node("Body") as Node3D).visible)
	TruckVisual.load_external_in_headless = false
