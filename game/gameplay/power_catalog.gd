class_name PowerCatalog
extends RefCounted

## Les pouvoirs proposes sur la page de selection, places sur la croix
## directionnelle (gauche / droite). Aucun pour l'instant (2026-10-16 : « on
## a pas mis de pouvoir ... laisse nous appuyer sur select ») : le choix vaut
## alors -1 (AUCUN) et la page le valide quand meme.
##
## Chaque pouvoir : id (stable, sauvegarde), name (affiche), tagline.

const POWERS: Array[Dictionary] = []


static func count() -> int:
	return POWERS.size()


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
