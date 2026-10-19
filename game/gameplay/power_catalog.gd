class_name PowerCatalog
extends RefCounted

## Les pouvoirs proposes sur la page de selection, places sur la croix
## directionnelle (gauche / droite) ; -1 = AUCUN. Premiere serie (2026-10-17,
## tache 4.5.8 : « propose une 1re serie »), d'apres les armes modelisees par
## l'equipe (Assets_Visuels/Armes_et_camions) : bouclier, lance-missiles,
## laser. Ils agissent dans TruckPowers ; durees en ticks.
##
## Chaque pouvoir : id (stable, sauvegarde), name (affiche), tagline,
## cooldown (ticks entre deux usages, depuis l'activation), model (arme
## montee sur le toit, chemin relatif a TruckVisual.asset_base()).

enum Id { SHIELD, MISSILE, LASER }

const POWERS: Array[Dictionary] = [
	{"id": "bouclier", "name": "BOUCLIER", "tagline": "5 s sans dégâts · recharge 20 s", "cooldown": 1200,
		"model": "../Assets_Visuels/Armes_et_camions/armes/bouclier_emetteur.glb"},
	{"id": "missile", "name": "MISSILE", "tagline": "vise le camion devant · 20 PV · recharge 15 s", "cooldown": 900,
		"model": "../Assets_Visuels/Armes_et_camions/armes/lance_missiles.glb"},
	{"id": "laser", "name": "LASER", "tagline": "rayon droit devant 1,5 s · recharge 18 s", "cooldown": 1080,
		"model": "../Assets_Visuels/Armes_et_camions/armes/laser_emetteur.glb"},
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

static func count() -> int:
	return POWERS.size()


## Temps de recharge du pouvoir `index` (ticks) ; 0 pour AUCUN.
static func cooldown_ticks(index: int) -> int:
	return int(POWERS[index]["cooldown"]) if index >= 0 and index < POWERS.size() else 0


static func model(index: int) -> String:
	return String(POWERS[index]["model"]) if index >= 0 and index < POWERS.size() else ""


## Nom affiche du pouvoir `index` ; -1 (ou hors liste) : AUCUN.
static func display_name(index: int) -> String:
	return String(POWERS[index]["name"]) if index >= 0 and index < POWERS.size() else "AUCUN"


static func tagline(index: int) -> String:
	if index >= 0 and index < POWERS.size():
		return String(POWERS[index]["tagline"])
	return "pouvoirs bientôt disponibles" if POWERS.is_empty() else "emplacement libre"


## Choix suivant / precedent sur le rouleau : -1 (AUCUN), puis 0..count-1,
## en boucle.
static func step(index: int, dir: int) -> int:
	return posmod(index + 1 + dir, POWERS.size() + 1) - 1
