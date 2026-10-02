class_name Catalogue
extends RefCounted

## Catalogue des modeles generes par Blender (docs/ART_PIPELINE.md §4 ter).
##
## Chaque modele a sa scene dans res://catalogue/<categorie>/<nom>.tscn :
## une scene heritee du .glb (res://assets/generated/...), a glisser dans
## l'editeur ou a instancier en code. On peut y ajouter des noeuds et des
## scripts sans toucher au .glb, qui reste regenere par `make assets`.
##
## VISUELS SEULEMENT : aucune regle de jeu ici. Les .glb sont git-ignores :
## sans `make assets`, ces scenes ne se chargent pas (load() renvoie null).
##
## Monter une arme sur un camion :
##     var camion := (load(Catalogue.VEHICULES[&"citerne"]) as PackedScene).instantiate()
##     Catalogue.monter(camion, &"mitrailleuse")   # sur son socket par defaut
##     Catalogue.monter(camion, &"scie_geante_g", &"Socket_Lateral_G")

const VEHICULES: Dictionary = {
	&"citerne": "res://catalogue/vehicules/citerne.tscn",
	&"betaillere": "res://catalogue/vehicules/betaillere.tscn",
	&"remorque": "res://catalogue/vehicules/remorque.tscn",
	&"porte_voitures": "res://catalogue/vehicules/porte_voitures.tscn",
	&"grue": "res://catalogue/vehicules/grue.tscn",
	&"chasse_neige": "res://catalogue/vehicules/chasse_neige.tscn",
	&"pompier": "res://catalogue/vehicules/pompier.tscn",
	&"chariot_elevateur": "res://catalogue/vehicules/chariot_elevateur.tscn",
}

const ARMES: Dictionary = {
	&"lance_missiles": "res://catalogue/armes/lance_missiles.tscn",
	&"scie_geante_g": "res://catalogue/armes/scie_geante_g.tscn",
	&"scie_geante_d": "res://catalogue/armes/scie_geante_d.tscn",
	&"mitrailleuse": "res://catalogue/armes/mitrailleuse.tscn",
	&"laser_emetteur": "res://catalogue/armes/laser_emetteur.tscn",
	&"bouclier_emetteur": "res://catalogue/armes/bouclier_emetteur.tscn",
	&"boomerang_aimante": "res://catalogue/armes/boomerang_aimante.tscn",
}

const PROJECTILES: Dictionary = {
	&"missile": "res://catalogue/projectiles/missile.tscn",
	&"grenade": "res://catalogue/projectiles/grenade.tscn",
	&"camion_projectile": "res://catalogue/projectiles/camion_projectile.tscn",
	&"doudou_geant": "res://catalogue/projectiles/doudou_geant.tscn",
	&"voiture_rouge": "res://catalogue/projectiles/voiture_rouge.tscn",
	&"voiture_bleue": "res://catalogue/projectiles/voiture_bleue.tscn",
	&"voiture_jaune": "res://catalogue/projectiles/voiture_jaune.tscn",
	&"voiture_verte": "res://catalogue/projectiles/voiture_verte.tscn",
	&"voiture_blanche": "res://catalogue/projectiles/voiture_blanche.tscn",
}

const EFFETS: Dictionary = {
	&"bouclier_coque": "res://catalogue/effets/bouclier_coque.tscn",
	&"laser_faisceau": "res://catalogue/effets/laser_faisceau.tscn",
}

## Points d'accroche presents sur chaque vehicule (vides Socket_* du .glb).
## Ceux de la remorque (Socket_Arriere, Socket_Conteneur) sont enfants du
## noeud `Remorque` et suivent son articulation.
const SOCKETS: Array[StringName] = [
	&"Socket_Toit", &"Socket_Avant", &"Socket_Lateral_G", &"Socket_Lateral_D",
	&"Socket_Arriere", &"Socket_Conteneur",
]

## Socket par defaut de chaque arme.
const SOCKET_PAR_DEFAUT: Dictionary = {
	&"lance_missiles": &"Socket_Arriere",
	&"scie_geante_g": &"Socket_Lateral_G",
	&"scie_geante_d": &"Socket_Lateral_D",
	&"mitrailleuse": &"Socket_Toit",
	&"laser_emetteur": &"Socket_Toit",
	&"bouclier_emetteur": &"Socket_Toit",
	&"boomerang_aimante": &"Socket_Avant",
}


## Le point d'accroche `socket` d'un vehicule instancie, ou null.
static func socket(vehicule: Node, nom: StringName) -> Node3D:
	return vehicule.find_child(String(nom), true, false) as Node3D


## Instancie l'arme `arme` (cle de ARMES) et la pose sur `nom_socket`
## (par defaut : SOCKET_PAR_DEFAUT). Renvoie l'arme, ou null si le socket
## ou le modele manque.
static func monter(vehicule: Node, arme: StringName, nom_socket: StringName = &"") -> Node3D:
	var nom: StringName = nom_socket if nom_socket != &"" else SOCKET_PAR_DEFAUT.get(arme, &"") as StringName
	var point := socket(vehicule, nom)
	if point == null:
		push_warning("Catalogue.monter : socket %s absent" % nom)
		return null
	var scene := load(ARMES[arme]) as PackedScene
	if scene == null:
		push_warning("Catalogue.monter : %s introuvable (lancer make assets)" % arme)
		return null
	var instance := scene.instantiate() as Node3D
	point.add_child(instance)
	return instance
