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

@export_group("Inertie")
## Moments d'inertie imposes (kg.m2), axes locaux. Sans eux, Godot les deduit
## des formes : la semi-remorque (13 m de caisse) multiplie le lacet par 17 et
## tue le drift (mesure 2026-09-28 : derive 29 -> 3,5 deg). Arcade : la
## remorque pese peu dans la dynamique ; on regle le ressenti ici.
## Reference : tracteur seul, calcule par Godot = 19 989 / 16 450 / 8 338.
@export_range(0.0, 1000000.0, 1.0, "suffix:kg·m²") var inertia_pitch_kgm2: float = 0.0
@export_range(0.0, 1000000.0, 1.0, "suffix:kg·m²") var inertia_yaw_kgm2: float = 0.0
@export_range(0.0, 1000000.0, 1.0, "suffix:kg·m²") var inertia_roll_kgm2: float = 0.0

@export_group("Moteur et freins")
## Poussee moteur a bas regime. 4,63 m/s2 = 0 -> 100 km/h en 6 s sans pertes.
@export_range(0.0, 20.0, 0.01, "suffix:m/s²") var engine_accel_ms2: float = 0.0
## Vitesse max sur le plat, le long de l'axe avant. La poussee nette reste
## egale a engine_accel_ms2 (les resistances sont compensees) jusqu'a
## top_speed - engine_taper, puis decroit lineairement jusqu'a 0.
@export_range(0.0, 300.0, 0.1, "suffix:km/h") var top_speed_kmh: float = 0.0
## Largeur de la bande sous la vitesse max ou la poussee decroit.
@export_range(0.0, 100.0, 0.1, "suffix:km/h") var engine_taper_kmh: float = 0.0
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
## Angle de glissement a partir duquel l'adherence laterale sature. En
## dessous, la force croit lineairement : c'est ce qui rend la direction
## progressive a haute vitesse (un demi-stick tourne moins qu'un plein stick).
@export_range(0.0, 45.0, 0.1, "suffix:°") var grip_slip_angle_deg: float = 0.0
## A basse vitesse, glissement (m/s) auquel adherence, freins et resistance au
## roulement saturent : c'est ce qui tient le camion immobile a l'arret.
@export_range(0.0, 5.0, 0.01, "suffix:m/s") var grip_saturation_speed_ms: float = 0.0
## Multiplicateur d'adherence du train arriere au frein a main (0 .. 1).
@export_range(0.0, 1.0, 0.01) var handbrake_rear_grip_factor: float = 0.0
## Ticks pour passer de l'adherence pleine a l'adherence de frein a main.
@export_range(0.0, 60.0, 0.1, "suffix:ticks") var handbrake_engage_ticks: float = 0.0
## Ticks pour retrouver l'adherence pleine au relacher : plus long que
## l'engagement, pour une relance propre sans effet de balancier.
@export_range(0.0, 120.0, 0.1, "suffix:ticks") var handbrake_release_ticks: float = 0.0
## Freinage du train arriere au frein a main (faible : le drift garde la vitesse).
@export_range(0.0, 20.0, 0.01, "suffix:m/s²") var handbrake_decel_ms2: float = 0.0

## Frottement de la caisse (chassis, cabine, remorque) contre les murs et les
## autres camions. Jolt retient le PLUS FAIBLE des deux frottements en contact
## (mesure 2026-09-28) : un mur a 0,5 ne freine a 0,5 que si la caisse est a
## 0,5. A 0,5 : glissade le long du mur 138 -> 110 km/h, et un camion pris en
## biais a 150 km/h se couche moins (10,9 deg contre 13,2 a 0,2).
@export_range(0.0, 1.0, 0.01) var chassis_friction: float = 0.0

@export_group("Direction")
## Angle de braquage max, atteint a basse vitesse.
@export_range(0.0, 60.0, 0.1, "suffix:°") var max_steer_deg: float = 0.0
## Angle limite a haute vitesse, en multiple de l'angle qui fait tourner a la
## limite d'adherence : atan(empattement * lateral_grip_g * g / v2). 1 = le
## plein stick tourne exactement a la limite ; un peu plus = leger sous-virage
## au plein stick, sur. L'angle reel est le plus petit des deux limites : tout
## le stick reste utile a toutes les vitesses.
@export_range(0.0, 3.0, 0.01) var steer_grip_ratio: float = 0.0
## Contre-braquage automatique, stick au neutre : fraction de l'angle de
## derive que les roues avant suivent d'elles-memes (comme la chasse d'un vrai
## train avant). S'efface a mesure que le joueur braque. Rend la relance propre
## a la sortie d'un drift, et stabilise la ligne droite.
@export_range(0.0, 1.0, 0.01) var auto_countersteer_ratio: float = 0.0
## Vitesse de rotation des roues directrices.
@export_range(0.0, 20.0, 0.01, "suffix:°/tick") var steer_rate_deg_per_tick: float = 0.0

@export_group("Aides arcade")
## Inclinaison (roulis et tangage) au-dela de laquelle l'anti-retournement agit.
## Mesuree par rapport au sol sous les roues quand 3 roues touchent (une rampe
## ou un virage releve ne declenche rien), sinon par rapport a la verticale.
@export_range(0.0, 90.0, 0.1, "suffix:°") var anti_roll_threshold_deg: float = 0.0
## Acceleration angulaire de redressement par radian au-dela du seuil. Amortie
## critiquement (2 * racine de la raideur) : pas de rebond de l'autre cote.
@export_range(0.0, 200.0, 0.01, "suffix:1/s²") var anti_roll_strength: float = 0.0
## En l'air (aucune roue au sol) : raideur du ressort angulaire qui ramene le
## camion a plat, amorti critiquement. Remplace l'anti-retournement.
@export_range(0.0, 200.0, 0.01, "suffix:1/s²") var air_level_strength: float = 0.0
## En l'air : vitesse de lacet obtenue au plein stick.
@export_range(0.0, 720.0, 0.1, "suffix:°/s") var air_yaw_rate_deg_s: float = 0.0
## En l'air : acceleration angulaire max pour atteindre ce lacet.
@export_range(0.0, 50.0, 0.01, "suffix:rad/s²") var air_control_accel: float = 0.0


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
	if steer_grip_ratio > 3.0:
		errors.append("steer_grip_ratio = %s : > 3, le plein stick sature l'avant" % steer_grip_ratio)
	if grip_slip_angle_deg >= 45.0:
		errors.append("grip_slip_angle_deg = %s : doit etre < 45" % grip_slip_angle_deg)
	if auto_countersteer_ratio >= 1.0:
		errors.append("auto_countersteer_ratio = %s : doit etre < 1" % auto_countersteer_ratio)
	if handbrake_engage_ticks < 1.0 or handbrake_release_ticks < 1.0:
		errors.append("handbrake_engage_ticks / handbrake_release_ticks : au moins 1 tick")
	if engine_taper_kmh >= top_speed_kmh:
		errors.append("engine_taper_kmh (%s) >= top_speed_kmh (%s)" % [engine_taper_kmh, top_speed_kmh])
	if reverse_top_speed_kmh >= top_speed_kmh:
		errors.append("reverse_top_speed_kmh (%s) >= top_speed_kmh (%s)"
			% [reverse_top_speed_kmh, top_speed_kmh])
	return errors
