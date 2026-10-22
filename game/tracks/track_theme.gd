class_name TrackTheme
extends RefCounted

## Habillage d'un circuit genere par TrackBlockout : materiaux de la chaussee,
## des glissieres, du sol, des arches, des pieges. Purement visuel : deux
## circuits au meme trace se conduisent pareil quel que soit leur theme.
##
##   CYBER_CITY    nuit pluvieuse, neons, megalopole (le theme d'origine)
##   PLAYA_DEL_SOL plage tropicale en plein soleil : ile, ocean turquoise,
##                 falaises, ponts sur l'eau, bancs de sable
##   SAKURA        Japon au printemps (2026-10-19) : cerisiers en fleur,
##                 petales sur la route, murs de temple, torii vermillon,
##                 pont laque, murs de pierre de chateau, flaques de bassin

enum Id { CYBER_CITY, PLAYA_DEL_SOL, SAKURA }
## Forme des arches : portique a neons, ou torii.
enum ArchStyle { NEON, TORII }

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
## Dessous des tabliers (null : la matiere du pont). Sakura : bois sombre
## (le vermillon des piles, en plafond, teintait toute l'avenue de rouge).
var bridge_under: Material
## Vrai : le sol recoit un masque terre / mer calcule sur le trace (ile).
var coast: bool = false
## Rayon de terre autour du trace, et de baie creusee sous les ponts (m).
var coast_land_radius: float = 130.0
var coast_bay_radius: float = 105.0
var arch_style: ArchStyle = ArchStyle.NEON
## Habillage des barils explosifs (ExplosiveBarrel.Style).
var barrel_style: int = 0
## Lanterne de papier lumineuse (torii, decor).
var lantern: Material

static var _cache: Dictionary = {}


static func of(id: int) -> TrackTheme:
	if not _cache.has(id):
		match id:
			Id.PLAYA_DEL_SOL: _cache[id] = _playa()
			Id.SAKURA: _cache[id] = _sakura()
			_: _cache[id] = _cyber()
	return _cache[id]


## Police des enseignes japonaises (kanji, kana), avec repli latin.
static func cjk_font() -> Font:
	if not _cache.has(&"cjk"):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Yu Mincho", "Yu Gothic", "Meiryo", "MS Gothic", "Noto Serif CJK JP",
			"Noto Sans CJK JP", "sans-serif"])
		f.font_weight = 700
		_cache[&"cjk"] = f
	return _cache[&"cjk"]


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


static func _sakura() -> TrackTheme:
	var t := TrackTheme.new()
	t.road = _shader(preload("res://tracks/materials/sakura_road.gdshader"))
	t.ground = _shader(preload("res://tracks/materials/sakura_ground.gdshader"))
	t.wall = _shader(preload("res://tracks/materials/sakura_wall.gdshader"))
	# bandeau du haut des murs : laque vermillon a gauche, rose a droite
	t.edge_left = _paint(Color(0.85, 0.16, 0.08), 0.35)
	t.edge_right = _paint(Color(1.0, 0.62, 0.74), 0.35)
	t.arch_style = ArchStyle.TORII
	var lacquer := StandardMaterial3D.new()
	lacquer.albedo_color = Color(0.82, 0.14, 0.06)
	lacquer.roughness = 0.32
	lacquer.emission_enabled = true
	lacquer.emission = Color(0.82, 0.14, 0.06)
	lacquer.emission_energy_multiplier = 0.12
	t.arch_tubes = [lacquer]
	t.arch_colors = [Color(1.0, 0.82, 0.35)]
	t.arch_light_energy = 0.0
	t.arch_frame = _metal(Color(0.05, 0.045, 0.045), 0.0, 0.45)
	t.hazard = _shader(preload("res://tracks/materials/sakura_puddle.gdshader"))
	t.embankment = _shader(preload("res://tracks/materials/sakura_stone.gdshader"))
	t.bridge_concrete = _metal(Color(0.56, 0.54, 0.5), 0.0, 0.85)
	t.bridge_wood = lacquer
	t.bridge_under = _metal(Color(0.16, 0.09, 0.06), 0.0, 0.9)
	t.barrel_style = 1
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.85, 0.1, 0.06)
	paper.roughness = 0.7
	paper.emission_enabled = true
	paper.emission = Color(1.0, 0.25, 0.1)
	paper.emission_energy_multiplier = 0.7
	paper.backlight_enabled = true
	paper.backlight = Color(1.0, 0.5, 0.3)
	t.lantern = paper
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
