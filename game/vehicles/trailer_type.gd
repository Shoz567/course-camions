class_name TrailerType
extends Resource

## Une semi-remorque au choix (sas READY) : son modele, sa caisse de collision
## et ses stats. Chaque remorque a sa taille et, a terme, sa capacite propre ;
## les stats servent a les equilibrer (decision du 2026-10-06).
##
## Les stats sont des MULTIPLICATEURS du reglage du camion (deja ajuste a la
## categorie de vitesse) : la remorque « Classique » vaut 1 partout et laisse
## la conduite mesuree (baseline.json) intacte. La masse du camion, elle, ne
## change pas (VEHICLE_SPEC §2) : le poids se traduit en acceleration.
##
## Meme piege que VehicleTuning : un defaut a 0 n'est pas ecrit dans le .tres,
## validate() refuse donc tout 0 - chaque valeur est ecrite explicitement.

## Identifiant stable (sauvegarde du choix, tests).
@export var id: StringName = &""
## Nom affiche dans le sas READY.
@export var display_name: String = ""
## Une ligne de description affichee sous le nom.
@export var tagline: String = ""
## Modele : .glb du catalogue (chemin relatif au dossier du projet Godot) dont
## on prend le noeud `Remorque`, pose a la sellette. Vide : la remorque du
## modele du camion (Camion_*.glb).
@export var model: String = ""

@export_group("Caisse de collision")
## Boite de la caisse, dans le repere du camion (comme TruckSpec.TRAILER_*) :
## mesuree sur le modele, debut a z = 0,48 m derriere la sellette.
@export var box_size: Vector3 = Vector3.ZERO
@export var box_center: Vector3 = Vector3.ZERO

@export_group("Stats (multiplicateurs du reglage)")
@export_range(0.5, 1.5, 0.01) var top_speed_mult: float = 0.0
@export_range(0.5, 1.5, 0.01) var accel_mult: float = 0.0
@export_range(0.5, 1.5, 0.01) var grip_mult: float = 0.0

@export_group("Remorque larguee")
## PV de la remorque une fois larguee (DetachedTrailer).
@export_range(1.0, 500.0, 1.0, "suffix:PV") var dropped_hp: float = 0.0
## Masse de la remorque larguee : plus lourde, elle tient mieux la route.
@export_range(500.0, 50000.0, 10.0, "suffix:kg") var dropped_mass_kg: float = 0.0

@export_group("Capacite")
## Capacite propre de la remorque (Module 8, a definir). Vide = aucune.
@export var ability: StringName = &""


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("id vide")
	if display_name.is_empty():
		errors.append("display_name vide")
	for n: String in ["top_speed_mult", "accel_mult", "grip_mult", "dropped_hp", "dropped_mass_kg"]:
		var v: float = get(n)
		if not is_finite(v) or v <= 0.0:
			errors.append("%s = %s : doit etre > 0" % [n, v])
	for n: String in ["top_speed_mult", "accel_mult", "grip_mult"]:
		var v: float = get(n)
		if v > 0.0 and (v < 0.8 or v > 1.2):
			errors.append("%s = %s : hors de [0,8 ; 1,2], desequilibre" % [n, v])
	if box_size.x <= 0.0 or box_size.y <= 0.0 or box_size.z <= 0.0:
		errors.append("box_size = %s : chaque cote doit etre > 0" % box_size)
	elif box_center.z - box_size.z / 2.0 < TruckSpec.KINGPIN.z - 1.0:
		errors.append("caisse trop en avant : elle entrerait dans la cabine")
	return errors


## Reglage du camion avec cette remorque : copie de `base` (jamais modifie).
func apply_to(base: VehicleTuning) -> VehicleTuning:
	var t := base.duplicate() as VehicleTuning
	t.top_speed_kmh = base.top_speed_kmh * top_speed_mult
	t.engine_accel_ms2 = base.engine_accel_ms2 * accel_mult
	t.boost_accel_ms2 = base.boost_accel_ms2 * accel_mult
	t.lateral_grip_g = base.lateral_grip_g * grip_mult
	t.reverse_top_speed_kmh = minf(base.reverse_top_speed_kmh, t.top_speed_kmh * 0.5)
	return t
