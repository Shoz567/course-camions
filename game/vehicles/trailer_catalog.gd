class_name TrailerCatalog
extends RefCounted

## Les semi-remorques proposees dans le sas READY, dans l'ordre du choix. La
## premiere est celle par defaut : la remorque du modele de course, sans
## modification de la conduite.

const PATHS: PackedStringArray = [
	"res://vehicles/trailers/classique.tres",
	"res://vehicles/trailers/conteneur.tres",
	"res://vehicles/trailers/citerne.tres",
	"res://vehicles/trailers/betaillere.tres",
	"res://vehicles/trailers/porte_voitures.tres",
	"res://vehicles/trailers/grue.tres",
	"res://vehicles/trailers/pompier.tres",
	"res://vehicles/trailers/chasse_neige.tres",
	"res://vehicles/trailers/chariot_elevateur.tres",
]


static func count() -> int:
	return PATHS.size()


## Remorque numero `index`, bouclee (le choix tourne en rond dans le sas).
static func at(index: int) -> TrailerType:
	return load(PATHS[posmod(index, PATHS.size())]) as TrailerType


static func default_type() -> TrailerType:
	return at(0)
