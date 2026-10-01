class_name TrackTheme
extends RefCounted

## Habillage d'un circuit genere par TrackBlockout : materiaux de la chaussee,
## des glissieres, du sol, des arches, des pieges. Purement visuel : deux
## circuits au meme trace se conduisent pareil quel que soit leur theme.
##
##   CYBER_CITY    nuit pluvieuse, neons, megalopole (le theme d'origine)
##   PLAYA_DEL_SOL plage tropicale en plein soleil : ile, ocean turquoise,
##                 falaises, ponts sur l'eau, bancs de sable

enum Id { CYBER_CITY, PLAYA_DEL_SOL }

## Chaussee (ShaderMaterial avec le parametre `road_width`). COLOR.r du
## maillage : 0 sur la terre, 0,5 sur un pont en beton, 1 sur un pont en bois.
var road: ShaderMaterial
var ground: Material
var wall: Material
## Bandeau du bord haut des glissieres, a gauche et a droite.
var edge_left: Material
var edge_right: Material
## Arches : materiau des tubes et couleur (enseigne, lumiere), en alternance.
var arch_tubes: Array[Material] = []
var arch_colors: Array[Color] = []
var arch_light_energy: float = 3.0
## Contour sombre de l'enseigne (0 : aucun ; de jour, elle se detache du ciel).
var arch_label_outline: int = 0
var arch_frame: Material
## Piege ralentisseur (flaque d'eau, banc de sable).
var hazard: Material
## Hauteur du piege au-dessus de la chaussee (m) : une flaque est plate, un
## banc de sable fait une petite bosse visible.
var hazard_height: float = 0.05
## Talus sous les portions hautes (null : les murs descendent jusqu'au sol).
var embankment: Material
## Dessous des ponts et piles.
var bridge_concrete: Material
var bridge_wood: Material
## Vrai : le sol recoit un masque terre / mer calcule sur le trace (ile).
var coast: bool = false
## Rayon de terre autour du trace, et de baie creusee sous les ponts (m).
var coast_land_radius: float = 130.0
var coast_bay_radius: float = 105.0

static var _cache: Dictionary = {}


static func of(id: int) -> TrackTheme:
	if not _cache.has(id):
		_cache[id] = _playa() if id == Id.PLAYA_DEL_SOL else _cyber()
	return _cache[id]


static func _cyber() -> TrackTheme:
	var t := TrackTheme.new()
	t.road = preload("res://tracks/materials/road.tres")
	t.ground = preload("res://tracks/materials/grass.tres")
	t.wall = preload("res://tracks/materials/wall.tres")
	t.edge_left = preload("res://tracks/materials/neon_cyan.tres")
	t.edge_right = preload("res://tracks/materials/neon_magenta.tres")
	t.arch_tubes = [preload("res://tracks/materials/neon_magenta.tres"), preload("res://tracks/materials/neon_cyan.tres")]
	t.arch_colors = [Color(1.0, 0.12, 0.78), Color(0.08, 0.95, 1.0)]
	t.arch_frame = _metal(Color(0.05, 0.055, 0.07), 0.7, 0.35)
	t.hazard = preload("res://tracks/materials/puddle.tres")
	t.bridge_concrete = _metal(Color(0.07, 0.075, 0.09), 0.3, 0.6)
	t.bridge_wood = t.bridge_concrete
	return t


static func _playa() -> TrackTheme:
	var t := TrackTheme.new()
	t.road = _shader(preload("res://tracks/materials/playa_road.gdshader"))
	t.ground = _shader(preload("res://tracks/materials/playa_coast.gdshader"))
	t.wall = _shader(preload("res://tracks/materials/playa_wall.gdshader"))
	t.edge_left = _paint(Color(0.05, 0.75, 0.8), 0.6)
	t.edge_right = _paint(Color(1.0, 0.42, 0.3), 0.6)
	t.arch_tubes = [_paint(Color(1.0, 0.42, 0.3), 1.2), _paint(Color(0.05, 0.75, 0.8), 1.2)]
	t.arch_colors = [Color(1.0, 0.8, 0.25), Color(0.45, 1.0, 0.95)]
	t.arch_light_energy = 0.0
	t.arch_label_outline = 28
	t.arch_frame = _metal(Color(0.04, 0.12, 0.26), 0.0, 0.6)
	t.hazard = _shader(preload("res://tracks/materials/playa_sandbank.gdshader"))
	t.hazard_height = 0.22
	t.embankment = _shader(preload("res://tracks/materials/playa_rock.gdshader"))
	t.bridge_concrete = _metal(Color(0.78, 0.76, 0.72), 0.0, 0.8)
	t.bridge_wood = _metal(Color(0.36, 0.23, 0.13), 0.0, 0.85)
	t.coast = true
	return t


static func _shader(s: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = s
	return m


static func _metal(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


## Peinture vive, un peu lumineuse (lisible a l'ombre comme au soleil).
static func _paint(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = glow
	m.roughness = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
