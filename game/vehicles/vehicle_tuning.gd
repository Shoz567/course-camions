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
## Au-dessus de la vitesse max, hors boost (fin de boost, descente) : frein
## moteur qui y ramene le camion en quelques secondes.
@export_range(0.0, 20.0, 0.01, "suffix:m/s²") var overspeed_decel_ms2: float = 0.0

@export_group("Boost")
## Poussee ajoutee pendant le boost (m/s2), meme sans gaz.
@export_range(0.0, 30.0, 0.01, "suffix:m/s²") var boost_accel_ms2: float = 0.0
## Vitesse max relevee pendant le boost.
@export_range(0.0, 100.0, 0.1, "suffix:km/h") var boost_top_speed_kmh: float = 0.0
## Duree du boost, puis duree de recharge de la jauge (qui commence a la fin
## du boost). 60 ticks = 1 s.
@export_range(0.0, 600.0, 1.0, "suffix:ticks") var boost_duration_ticks: float = 0.0
@export_range(0.0, 1200.0, 1.0, "suffix:ticks") var boost_recharge_ticks: float = 0.0
## Plaque de boost (piste) : poussee qui tient la vitesse max relevee pendant
## la duree de la plaque (le coup de pouce initial est immediat).
@export_range(0.0, 40.0, 0.01, "suffix:m/s²") var pad_boost_accel_ms2: float = 0.0

@export_group("Remorque articulee")
## Angle max de la remorque par rapport au tracteur, de chaque cote : au-dela,
## tete-a-queue ingerable.
@export_range(0.0, 90.0, 0.1, "suffix:°") var trailer_max_angle_deg: float = 0.0
## La remorque suit son angle de consigne comme un ressort amorti, avec sa
## propre inertie de lacet : le tracteur tourne, elle suit avec du retard.
@export_range(0.0, 5.0, 0.01, "suffix:Hz") var trailer_frequency_hz: float = 0.0
## 1 = critique ; en dessous, la remorque depasse sa consigne (effet de balancier).
@export_range(0.0, 2.0, 0.01) var trailer_damping_ratio: float = 0.0
## Consigne en virage : la remorque chasse vers l'exterieur, de tant de degres
## par g d'acceleration laterale du tracteur.
@export_range(0.0, 60.0, 0.1, "suffix:°/g") var trailer_sweep_deg_per_g: float = 0.0
## En derapage : part de l'angle de derive du tracteur ajoutee a la consigne,
## vers l'exterieur (balayage).
@export_range(0.0, 3.0, 0.01) var trailer_drift_sweep_ratio: float = 0.0
## Sous cette vitesse, la consigne est nulle : la remorque se realigne.
@export_range(0.0, 20.0, 0.01, "suffix:m/s") var trailer_min_speed_ms: float = 0.0
## Un mur arrete le balayage ; deja contre le mur, la remorque se replie vers
## l'axe du tracteur a cette vitesse.
@export_range(0.0, 10.0, 0.01, "suffix:°/tick") var trailer_wall_fold_deg_per_tick: float = 0.0
## Remorque qui balaie un adversaire : coefficient de restitution du choc.
@export_range(0.0, 1.0, 0.01) var trailer_shove_restitution: float = 0.0
## Vitesse max donnee a l'adversaire par un coup de remorque.
@export_range(0.0, 30.0, 0.01, "suffix:m/s") var trailer_shove_max_dv_ms: float = 0.0
## Delai entre deux coups de remorque au meme adversaire.
@export_range(0.0, 600.0, 1.0, "suffix:ticks") var trailer_shove_cooldown_ticks: float = 0.0
## Part du choc renvoyee au camion qui balaie (arcade : l'attaquant garde sa
## ligne ; 1 = conservation de la quantite de mouvement).
@export_range(0.0, 1.0, 0.01) var trailer_shove_reaction: float = 0.0

@export_group("Murs et obstacles")
## Frottement continu contre un mur au-dela duquel le camion est decolle
## (90 ticks = 1,5 s).
@export_range(0.0, 600.0, 1.0, "suffix:ticks") var wall_unstick_ticks: float = 0.0
## Ticks sans contact toleres dans un frottement (rebonds sur la glissiere).
@export_range(0.0, 60.0, 1.0, "suffix:ticks") var wall_contact_grace_ticks: float = 0.0
## Vitesse gardee au decollage (0,75 = -25 %).
@export_range(0.0, 1.0, 0.01) var wall_unstick_speed_factor: float = 0.0
## Vitesse donnee vers l'interieur de la piste, le long de la normale du mur.
@export_range(0.0, 20.0, 0.01, "suffix:m/s") var wall_bump_speed_ms: float = 0.0
## Lacet max pour ramener le nez parallele au mur.
@export_range(0.0, 5.0, 0.01, "suffix:rad/s") var wall_bump_align_rad_s: float = 0.0
## Caisse de cargo percutee : vitesse gardee, et coup de lacet.
@export_range(0.0, 1.0, 0.01) var cargo_hit_speed_factor: float = 0.0
@export_range(0.0, 10.0, 0.01, "suffix:rad/s") var cargo_hit_yaw_kick_rad_s: float = 0.0

@export_group("Sauts (plaques)")
## Pendant un saut de plaque : raideur de l'assiette automatique multipliee.
@export_range(0.0, 10.0, 0.01) var jump_air_level_factor: float = 0.0
## A la reception d'un saut de plaque, vitesse de chute ramenee a cette valeur.
@export_range(0.0, 20.0, 0.01, "suffix:m/s") var jump_landing_max_down_ms: float = 0.0
## Apres cette reception, amortissement de suspension multiplie, pendant
## jump_landing_damping_ticks : pas de rebond.
@export_range(0.0, 5.0, 0.01) var jump_landing_damping_factor: float = 0.0
@export_range(0.0, 120.0, 1.0, "suffix:ticks") var jump_landing_damping_ticks: float = 0.0
## L'aide au saut s'eteint si le camion n'a pas atterri apres ce delai.
@export_range(0.0, 1200.0, 1.0, "suffix:ticks") var jump_assist_max_ticks: float = 0.0

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

@export_group("Derapage maitrise")
## Derive tenue au frein a main, au plein braquage (proportionnelle au stick).
@export_range(0.0, 60.0, 0.1, "suffix:°") var drift_target_slip_deg: float = 0.0
## Derive jamais depassee, frein a main ou non : pas de tete-a-queue.
@export_range(0.0, 89.0, 0.1, "suffix:°") var drift_max_slip_deg: float = 0.0
## Raideur du retour vers la derive cible (1/s).
@export_range(0.0, 20.0, 0.01, "suffix:1/s") var drift_assist_gain: float = 0.0
## Acceleration angulaire max de l'aide (une aide, pas un rail).
@export_range(0.0, 30.0, 0.01, "suffix:rad/s²") var drift_assist_accel: float = 0.0
## Garde anti tete-a-queue (derive prevue au-dela de la limite) : autorite.
@export_range(0.0, 60.0, 0.01, "suffix:rad/s²") var spin_guard_accel: float = 0.0
## En dessous, pas d'aide (manoeuvres a basse vitesse).
@export_range(0.0, 30.0, 0.01, "suffix:m/s") var drift_min_speed_ms: float = 0.0

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
	if drift_target_slip_deg >= drift_max_slip_deg:
		errors.append("drift_target_slip_deg (%s) >= drift_max_slip_deg (%s)"
			% [drift_target_slip_deg, drift_max_slip_deg])
	if wall_unstick_speed_factor >= 1.0 or cargo_hit_speed_factor >= 1.0:
		errors.append("wall_unstick_speed_factor / cargo_hit_speed_factor : doivent etre < 1")
	if trailer_damping_ratio >= 2.0:
		errors.append("trailer_damping_ratio = %s : >= 2, remorque figee" % trailer_damping_ratio)
	if trailer_shove_restitution > 1.0 or trailer_shove_reaction > 1.0:
		errors.append("trailer_shove_restitution / trailer_shove_reaction : au plus 1")
	if reverse_top_speed_kmh >= top_speed_kmh:
		errors.append("reverse_top_speed_kmh (%s) >= top_speed_kmh (%s)"
			% [reverse_top_speed_kmh, top_speed_kmh])
	return errors
