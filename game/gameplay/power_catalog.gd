class_name PowerCatalog
extends RefCounted

## Les pouvoirs proposes sur la page de selection, places sur la croix
## directionnelle (gauche / droite) ; -1 = AUCUN. Premiere serie (2026-10-17,
## tache 4.5.8 : « propose une 1re serie »), d'apres les armes modelisees par
## l'equipe (Assets_Visuels/Armes_et_camions) : bouclier, lance-missiles,
## laser. Deuxieme serie (2026-10-19, « plus de pouvoirs », d'apres les autres
## armes de l'equipe) : mitrailleuse, scie geante, boomerang aimante. Ils
## agissent dans TruckPowers ; durees en ticks.
##
## Chaque pouvoir : id (stable, sauvegarde), name (affiche), tagline,
## cooldown (ticks entre deux usages, depuis l'activation), model (arme
## montee sur le toit, chemin relatif a TruckVisual.asset_base() ;
## model_right : variante pour l'emplacement droit, s'il y en a une).

enum Id { SHIELD, MISSILE, LASER, GUN, SAW, BOOMERANG }

const POWERS: Array[Dictionary] = [
	{"id": "bouclier", "name": "BOUCLIER", "tagline": "5 s sans dégâts · recharge 20 s", "cooldown": 1200,
		"model": "../Assets_Visuels/Armes_et_camions/armes/bouclier_emetteur.glb"},
	{"id": "missile", "name": "MISSILE", "tagline": "vise le camion devant · 20 PV · recharge 15 s", "cooldown": 900,
		"model": "../Assets_Visuels/Armes_et_camions/armes/lance_missiles.glb"},
	{"id": "laser", "name": "LASER", "tagline": "rayon droit devant 1,5 s · recharge 18 s", "cooldown": 1080,
		"model": "../Assets_Visuels/Armes_et_camions/armes/laser_emetteur.glb"},
	{"id": "mitrailleuse", "name": "MITRAILLEUSE", "short": "MITRAILL.", "tagline": "rafale 2 s droit devant · recharge 14 s", "cooldown": 840,
		"model": "../Assets_Visuels/Armes_et_camions/armes/mitrailleuse.glb"},
	{"id": "scie", "name": "SCIE GÉANTE", "short": "SCIE", "tagline": "scies sur les flancs 4 s · recharge 16 s", "cooldown": 960,
		"model": "../Assets_Visuels/Armes_et_camions/armes/scie_geante_g.glb",
		"model_right": "../Assets_Visuels/Armes_et_camions/armes/scie_geante_d.glb"},
	{"id": "boomerang", "name": "BOOMERANG", "short": "BOOMER.", "tagline": "fonce sur le camion devant, aller-retour · 15 PV par passage · recharge 15 s", "cooldown": 900,
		"model": "../Assets_Visuels/Armes_et_camions/armes/boomerang_aimante.glb"},
]

## Bouclier : duree (ticks).
const SHIELD_TICKS := 300
## Missile : vitesse (m/s), virage maximal (deg par tick), duree de vie (ticks),
## degats, cone de visee (deg) et portee (m) pour choisir sa cible.
const MISSILE_SPEED_MS := 70.0
const MISSILE_TURN_DEG := 3.0
const MISSILE_LIFE_TICKS := 150
const MISSILE_DAMAGE := 20.0
const MISSILE_CONE_DEG := 35.0
const MISSILE_RANGE_M := 160.0
## Coup recu : vitesse ajoutee (m/s), vers le haut et dans le sens du missile.
const MISSILE_KICK_UP_MS := 5.0
const MISSILE_KICK_MS := 3.0
## Laser : duree (ticks), portee (m), degats par tick.
const LASER_TICKS := 90
const LASER_RANGE_M := 120.0
const LASER_DAMAGE_PER_TICK := 0.4
## Mitrailleuse : duree de la rafale (ticks), une balle tous les GUN_INTERVAL
## ticks (rayon droit devant), portee (m), degats par balle (20 balles : 24 PV).
const GUN_TICKS := 120
const GUN_INTERVAL := 6
const GUN_RANGE_M := 90.0
const GUN_DAMAGE := 1.2
## Scie geante : duree (ticks). 2026-10-20 (« elle n'a pas vraiment de
## portee... rotation de 90 degres pour qu'elle soit parallele a la route...
## crever les pneus ») : les lames sortent a plat, a hauteur des pneus, de
## chaque cote du tracteur. Zone touchee : de SAW_REACH_M au-dela du flanc,
## sur SAW_HALF_LENGTH_M de part et d'autre du centre du tracteur (tout son
## flanc). Degats par tick a la tete d'un camion dans la zone (sa remorque :
## par son train de roues), et un coup de lame tous les SAW_TIRE_INTERVAL
## ticks a chaque pneu dans la zone (TruckTires : il eclate au 3e, ~0,4 s).
const SAW_TICKS := 240
## Degats visuels des pouvoirs (2026-10-20 : « tout ce qui est capacite
## puisse endommager les remorques et les camions, en plus des PV de maniere
## visuelle ») : chaque coup marque la tole, tete ou remorque, comme un choc
## a cette vitesse (m/s ; TruckDamageFx.crush : creux des 2,5, pieces
## arrachees des 9). Laser : un coup tous les LASER_HIT_INTERVAL ticks.
const MISSILE_HIT_MS := 18.0
const BOOMERANG_HIT_MS := 12.0
const SAW_HIT_MS := 10.0
const LASER_HIT_MS := 7.0
const LASER_HIT_INTERVAL := 15
const GUN_HIT_MS := 4.0
const SAW_REACH_M := 2.7
const SAW_HALF_LENGTH_M := 3.6
const SAW_DAMAGE_PER_TICK := 0.12
const SAW_TIRE_INTERVAL := 12
const SAW_PUSH_MS2 := 16.0
## Boomerang (2026-10-20 : « il ne va pas tres loin, il revient sans faire
## grand-chose ») : vitesse par rapport au tireur (m/s, il garde son avance a
## toute allure) ; a l'aller il fonce sur le camion vise (cone et portee du
## missile) en tournant d'au plus BOOMERANG_SEEK_DEG par tick, le traverse et
## fait demi-tour BOOMERANG_PASS_TICKS apres l'avoir touche (il repasse
## dessus), ou a BOOMERANG_RANGE_M du tireur ; au retour
## il le rejoint en tournant d'au plus BOOMERANG_TURN_DEG. Duree de vie
## (ticks), degats et coup par camion touche (une fois a l'aller, une fois au
## retour), rayon de contact (m).
const BOOMERANG_SPEED_MS := 50.0
const BOOMERANG_RANGE_M := 85.0
const BOOMERANG_SEEK_DEG := 4.0
const BOOMERANG_PASS_TICKS := 15
const BOOMERANG_LIFE_TICKS := 360
const BOOMERANG_TURN_DEG := 8.0
const BOOMERANG_DAMAGE := 15.0
const BOOMERANG_KICK_MS := 3.0
const BOOMERANG_RADIUS_M := 2.2

static func count() -> int:
	return POWERS.size()


## Temps de recharge du pouvoir `index` (ticks) ; 0 pour AUCUN.
static func cooldown_ticks(index: int) -> int:
	return int(POWERS[index]["cooldown"]) if index >= 0 and index < POWERS.size() else 0


## Arme de l'emplacement `slot` (0 gauche, 1 droit) pour le pouvoir `index`.
static func model(index: int, slot: int = 0) -> String:
	if index < 0 or index >= POWERS.size():
		return ""
	var p: Dictionary = POWERS[index]
	return String(p["model_right"]) if slot == 1 and p.has("model_right") else String(p["model"])


## Nom affiche du pouvoir `index` ; -1 (ou hors liste) : AUCUN.
static func display_name(index: int) -> String:
	return String(POWERS[index]["name"]) if index >= 0 and index < POWERS.size() else "AUCUN"


## Nom court (pastilles du cadran de course, HudDial).
static func short_name(index: int) -> String:
	if index < 0 or index >= POWERS.size():
		return ""
	var p: Dictionary = POWERS[index]
	return String(p.get("short", p["name"]))


static func tagline(index: int) -> String:
	if index >= 0 and index < POWERS.size():
		return String(POWERS[index]["tagline"])
	return "pouvoirs bientôt disponibles" if POWERS.is_empty() else "emplacement libre"


## Choix suivant / precedent sur le rouleau : -1 (AUCUN), puis 0..count-1,
## en boucle.
static func step(index: int, dir: int) -> int:
	return posmod(index + 1 + dir, POWERS.size() + 1) - 1
