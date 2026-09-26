extends PhysicsTest

## VehicleTuning : le reglage livre est valide, et validate() ATTRAPE les
## erreurs (vehicle-physics-engineer.md, « Reglages »).

const TRES_PATH := "res://vehicles/default_vehicle.tres"


func _test_setup() -> void:
	duration_ticks = 1


func _test_finish() -> void:
	var tuning := load(TRES_PATH) as VehicleTuning
	if not check("default_vehicle.tres charge", tuning != null, TRES_PATH):
		return
	var errors := tuning.validate()
	check("default_vehicle.tres valide", errors.is_empty(), "erreurs=%s" % [errors])

	var names := _float_fields(tuning)
	check_above("nombre de reglages", names.size(), 10)

	# Une ressource vierge : chaque reglage, a 0, doit etre refuse.
	var blank := VehicleTuning.new()
	var blank_errors := blank.validate()
	check("ressource vierge : chaque reglage refuse",
		blank_errors.size() >= names.size(), "%d erreurs / %d reglages" % [blank_errors.size(), names.size()])

	# Chaque reglage mis a 0 isolement est attrape.
	var missed := PackedStringArray()
	for n in names:
		var t := tuning.duplicate() as VehicleTuning
		t.set(n, 0.0)
		if t.validate().is_empty():
			missed.append(n)
	check("un reglage a 0 est toujours attrape", missed.is_empty(), "rates=%s" % [missed])

	# Regles de coherence.
	var t2 := tuning.duplicate() as VehicleTuning
	t2.steer_deg_at_top_speed = t2.max_steer_deg + 1.0
	check("braquage a haute vitesse > max refuse", not t2.validate().is_empty())
	var t3 := tuning.duplicate() as VehicleTuning
	t3.handbrake_rear_grip_factor = 1.0
	check("facteur de frein a main = 1 refuse", not t3.validate().is_empty())

	# Piege mesure : une valeur egale au defaut n'est pas ecrite dans le .tres.
	# Les defauts etant 0, chaque reglage doit y figurer explicitement.
	var text := FileAccess.get_file_as_string(TRES_PATH)
	var absent := PackedStringArray()
	for n in names:
		if not text.contains("\n%s = " % n):
			absent.append(n)
	check("chaque reglage ecrit dans le .tres", absent.is_empty(), "absents=%s" % [absent])


func _float_fields(r: Resource) -> PackedStringArray:
	var out := PackedStringArray()
	for p in r.get_property_list():
		if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and p.type == TYPE_FLOAT:
			out.append(p.name)
	return out
