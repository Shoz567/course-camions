class_name VehicleTuning
extends Resource

## Tous les nombres de reglage du camion (CLAUDE.md §5). Jamais en dur ailleurs.
##
## Piege mesure : Godot n'ecrit pas dans un .tres une valeur egale au defaut du
## script. Tous les defauts valent donc 0 et validate() les refuse : une valeur
## reelle est toujours ecrite explicitement dans le .tres, et changer un defaut
## ici ne peut plus modifier un reglage en silence.
##
## Unites : les poussees sont des accelerations (m/s2), jamais des newtons
## (CLAUDE.md §6) ; les durees sont en ticks (CLAUDE.md §7).
##
## Les grandeurs de CONTRAT (masse, dimensions, ancrages, hauteur de repos) ne
## sont pas ici : elles vivent dans TruckSpec, miroir de docs/VEHICLE_SPEC.md.

@export_group("Suspension")
## Frequence propre d'une roue, sur m_roue = masse / 4. Spike V1 : 1,6 Hz.
@export_range(0.0, 5.0, 0.01, "suffix:Hz") var suspension_frequency_hz: float = 0.0
## Taux d'amortissement (1 = critique). Spike V1 : 0,45.
@export_range(0.0, 2.0, 0.01) var suspension_damping_ratio: float = 0.0

@export_group("Moteur et freins")
## Poussee moteur a bas regime. 4,63 m/s2 = 0 -> 100 km/h en 6 s sans pertes.
@export_range(0.0, 20.0, 0.01, "suffix:m/s²") var engine_accel_ms2: float = 0.0
## Vitesse a laquelle la poussee moteur s'annule, le long de l'axe avant.
@export_range(0.0, 300.0, 0.1, "suffix:km/h") var top_speed_kmh: float = 0.0
@export_range(0.0, 20.0, 0.01, "suffix:m/s²") var reverse_accel_ms2: float = 0.0
@export_range(0.0, 100.0, 0.1, "suffix:km/h") var reverse_top_speed_kmh: float = 0.0
## Deceleration au frein. 100 -> 0 en < 45 m exige au moins 8,57 m/s2.
@export_range(0.0, 30.0, 0.01, "suffix:m/s²") var brake_decel_ms2: float = 0.0

@export_group("Resistances")
## Trainee aerodynamique : a = coef * v2 (1/m). Remplace le linear_damp du
## corps, force a 0 (docs/SPIKE.md A10).
@export_range(0.0, 0.01, 0.00001, "suffix:1/m") var aero_drag_per_m: float = 0.0
## Resistance au roulement, sature a basse vitesse : tient le camion immobile.
@export_range(0.0, 5.0, 0.01, "suffix:m/s²") var rolling_resistance_ms2: float = 0.0

@export_group("Adherence")
## Adherence laterale max, en g, ponderee par la charge de chaque roue.
@export_range(0.0, 2.0, 0.01, "suffix:g") var lateral_grip_g: float = 0.0
## Vitesse de glissement laterale a laquelle l'adherence sature.
@export_range(0.0, 5.0, 0.01, "suffix:m/s") var grip_saturation_speed_ms: float = 0.0
## Multiplicateur d'adherence du train arriere au frein a main (0 .. 1).
@export_range(0.0, 1.0, 0.01) var handbrake_rear_grip_factor: float = 0.0

@export_group("Direction")
## Angle de braquage a l'arret.
@export_range(0.0, 60.0, 0.1, "suffix:°") var max_steer_deg: float = 0.0
## Angle de braquage a top_speed_kmh (<= max_steer_deg).
@export_range(0.0, 60.0, 0.1, "suffix:°") var steer_deg_at_top_speed: float = 0.0
## Vitesse de rotation des roues directrices.
@export_range(0.0, 20.0, 0.01, "suffix:°/tick") var steer_rate_deg_per_tick: float = 0.0

@export_group("Aides arcade")
## Roulis au-dela duquel l'anti-retournement agit.
@export_range(0.0, 90.0, 0.1, "suffix:°") var anti_roll_threshold_deg: float = 0.0
## Acceleration angulaire de redressement par radian de roulis au-dela du seuil.
@export_range(0.0, 50.0, 0.01, "suffix:1/s²") var anti_roll_strength: float = 0.0
## Acceleration angulaire max du controle en l'air.
@export_range(0.0, 20.0, 0.01, "suffix:rad/s²") var air_control_accel: float = 0.0


## Liste des erreurs de reglage ; vide = valide.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for p in get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if p.type != TYPE_FLOAT:
			continue
		var v: float = get(p.name)
		if not is_finite(v) or v <= 0.0:
			errors.append("%s = %s : doit etre > 0 (0 = valeur par defaut non renseignee)"
				% [p.name, v])
	if suspension_damping_ratio >= 2.0:
		errors.append("suspension_damping_ratio = %s : >= 2, suspension figee" % suspension_damping_ratio)
	if handbrake_rear_grip_factor >= 1.0:
		errors.append("handbrake_rear_grip_factor = %s : doit etre < 1" % handbrake_rear_grip_factor)
	if steer_deg_at_top_speed > max_steer_deg:
		errors.append("steer_deg_at_top_speed (%s) > max_steer_deg (%s)"
			% [steer_deg_at_top_speed, max_steer_deg])
	if reverse_top_speed_kmh >= top_speed_kmh:
		errors.append("reverse_top_speed_kmh (%s) >= top_speed_kmh (%s)"
			% [reverse_top_speed_kmh, top_speed_kmh])
	return errors
