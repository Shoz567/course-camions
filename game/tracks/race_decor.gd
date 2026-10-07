@tool
class_name RaceDecor
extends Node3D

## Decors de course spectaculaires autour de la piste parente (Cyber City) :
##   - ponts routiers qui enjambent la piste, avec arc porteur au-dessus du
##     tablier, neons, circulation (points de lumiere qui filent) et mega-ecran
##     holographique publicitaire anime face aux camions qui arrivent ; a
##     deux niveaux (`decks`: 2), c'est un echangeur ;
##   - tribunes de part et d'autre de la ligne de depart : gradins, toit a
##     lisere neon, projecteurs, spectateurs qui sautent, font la ola et
##     prennent des photos (un MultiMesh) ;
##   - faisceaux de projecteurs derriere les tribunes, qui balaient le ciel ;
##   - de nuit, lampadaires le long de la piste (_build_street_lights).
## Purement visuel : aucune collision (ni camion, ni camera), piles toujours
## au-dela des murs. En headless (tests), rien n'est genere, sauf si un test
## le force.

## Ponts : {"segment": nom du segment, "at": m depuis son debut, "angle": deg
## entre le pont et la piste (90 = perpendiculaire), "label": publicite,
## "decks": 1 ou 2}.
@export var overpasses: Array[Dictionary] = []
@export var grandstands: bool = true
@export var sky_beams: bool = true
## Lampadaires le long de la piste (de nuit seulement).
@export var street_lights: bool = true
## Hauteur libre sous un tablier, au-dessus du point le plus haut de la
## chaussee qu'il survole (un camion en plein saut passe largement dessous).
@export var overpass_clearance: float = 20.0
## Largeur d'un tablier.
@export var deck_width: float = 24.0
## Faux : decor de jour (beton clair, pas de projecteurs, foule non lumineuse).
@export var night: bool = true
@export var decor_seed: int = 3

## Publicites qui alternent sur les mega-ecrans.
const ADS: PackedStringArray = ["NEON COLA", "HYPER FUEL", "TURBO TRUCKS", "CYBER TIRES", "NITRO+", "CRAZY WHEELS"]
const AD_SECONDS := 3.5

## Un test peut forcer la generation en headless.
static var generate_in_headless: bool = false

## Pivots des faisceaux (balayage) et enseignes des ecrans (alternance).
var beams: Array[Node3D] = []
var screen_labels: Array[Label3D] = []
var _time: float = 0.0
var _state: int = 1


func _ready() -> void:
	if DisplayServer.get_name() == "headless" and not generate_in_headless:
		set_process(false)
		return
	var track := get_parent() as TrackBlockout
	if track == null:
		return
	# la piste parente se construit dans SON _ready, apres le notre
	if track.is_node_ready():
		_generate(track)
	else:
		track.ready.connect(_generate.bind(track), CONNECT_ONE_SHOT)


func _process(delta: float) -> void:
	_time += delta
	for k in beams.size():
		var b := beams[k]
		b.rotation = Vector3(deg_to_rad(16.0 + 12.0 * sin(_time * 0.31 + k * 1.3)), b.rotation.y,
			deg_to_rad(14.0 * sin(_time * 0.23 + k * 2.1)))
	var turn := int(_time / AD_SECONDS)
	for k in screen_labels.size():
		var text := ADS[(turn + k) % ADS.size()]
		if screen_labels[k].text != text:
			screen_labels[k].text = text


func _rand() -> float:
	_state = (_state * 1103515245 + 12345) & 0x7fffffff
	return float(_state) / 2147483648.0


func _generate(track: TrackBlockout) -> void:
	_state = maxi(decor_seed, 1)
	var root := Node3D.new()
	root.name = "Decor"
	add_child(root)
	var piers: Array[Vector3] = []
	var decks: Array[Dictionary] = []
	for k in overpasses.size():
		_build_overpass(root, track, overpasses[k], k, piers, decks)
	if grandstands:
		_build_grandstands(root, track)
	if night and street_lights:
		_build_street_lights(root, track)
	if sky_beams:
		_build_beams(root, track)
	# donnees gardees pour les tests (le rendu factice du headless ne relit pas
	# les MultiMesh, et les boites ne disent pas a quoi elles servent)
	root.set_meta(&"piers", piers)
	root.set_meta(&"decks", decks)


# --- ponts routiers --------------------------------------------------------------

func _build_overpass(root: Node3D, track: TrackBlockout, spec: Dictionary, index: int,
		piers: Array[Vector3], decks: Array[Dictionary]) -> void:
	var s := track.segment_start_s(String(spec.get("segment", ""))) + float(spec.get("at", 0.0))
	var levels := int(spec.get("decks", 1))
	for level in levels:
		# au 2e niveau (echangeur), le pont croise le premier de biais, plus
		# haut et 50 m plus loin : il passe derriere l'ecran, pas devant
		var i := track.index_at_s(s + 50.0 * level)
		var p := track.sample_position(i)
		var t := (track.sample_forward(i) * Vector3(1, 0, 1)).normalized()
		var dir := t.rotated(Vector3.UP, deg_to_rad(float(spec.get("angle", 90.0)) + 38.0 * level))
		var across := dir.cross(Vector3.UP).normalized()
		# l'ecran regarde les camions qui arrivent
		var facing := -1.0 if across.dot(t) > 0.0 else 1.0
		var half_len := track.width / 2.0 + 110.0
		# hauteur : au-dessus du plus haut point de chaussee sous le tablier
		var top := p.y
		for k in range(-45, 46):
			var j := track.sample_ahead(i, k * 2.0)
			var q := track.sample_position(j)
			if absf((q - p).dot(across)) < deck_width / 2.0 + 6.0:
				top = maxf(top, q.y + absf(track.sample_right(j).y) * track.width / 2.0)
		var deck_y := top + overpass_clearance + 12.0 * level
		var node := Node3D.new()
		node.name = "Overpass%d_%d" % [index, level]
		node.transform = Transform3D(Basis(dir, Vector3.UP, across), Vector3(p.x, 0.0, p.z))
		root.add_child(node)
		decks.append({"origin": Vector3(p.x, deck_y, p.z), "dir": dir, "across": across,
			"half_len": half_len, "width": deck_width, "sample": i})

		var concrete := _concrete()
		var neon: Material = preload("res://tracks/materials/neon_violet.tres") if (index + level) % 2 == 0 \
				else preload("res://tracks/materials/neon_cyan.tres")
		var length := half_len * 2.0
		_box(node, Vector3(length, 2.4, deck_width), Vector3(0.0, deck_y + 1.2, 0.0), concrete)
		for side: float in [-1.0, 1.0]:
			var z := side * (deck_width / 2.0 - 0.3)
			_box(node, Vector3(length, 1.3, 0.6), Vector3(0.0, deck_y + 3.05, z), concrete)
			# lisere neon sous le bord du tablier, et bandeau de circulation
			_box(node, Vector3(length, 0.22, 0.22), Vector3(0.0, deck_y + 0.25, side * (deck_width / 2.0 + 0.15)), neon)
			var strip := _quad_mesh(Vector2(length, 1.1), _traffic(length, 1.0, side > 0.0))
			strip.position = Vector3(0.0, deck_y + 4.3, side * (deck_width / 2.0 - 0.3))
			strip.rotation = Vector3(0.0, 0.0 if side > 0.0 else PI, 0.0)
			node.add_child(strip)
		# chaussee du pont, vue depuis les hauteurs de la piste
		var lanes := _quad_mesh(Vector2(length, deck_width - 2.0), _traffic(length, 4.0, false))
		lanes.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
		lanes.position = Vector3(0.0, deck_y + 2.45, 0.0)
		node.add_child(lanes)

		# piles : au plus pres des murs de chaque cote, puis aux extremites
		var foot := TrackBlockout.GROUND_Y - 1.0
		var xs: Array[float] = []
		for side: float in [-1.0, 1.0]:
			var x := _first_clear(track, p, dir * side, track.width / 2.0 + 12.0, i)
			if x < half_len - 20.0:
				xs.append(side * x)
			xs.append(side * (half_len - 10.0))
		for x in xs:
			var h := deck_y - foot
			_box(node, Vector3(5.0, h, deck_width - 8.0), Vector3(x, foot + h / 2.0, 0.0), concrete)
			_box(node, Vector3(0.3, h - 2.0, 0.3), Vector3(x, foot + h / 2.0, deck_width / 2.0 - 3.8), neon)
			_box(node, Vector3(0.3, h - 2.0, 0.3), Vector3(x, foot + h / 2.0, -deck_width / 2.0 + 3.8), neon)
			piers.append(node.transform * Vector3(x, 0.0, 0.0))

		if level == 0:
			_build_arch_ribs(node, deck_y + 2.4, track.width + 70.0, neon)
			_build_screen(node, deck_y, facing, String(spec.get("label", ADS[index % ADS.size()])), index)


## Arc porteur au-dessus du tablier, de chaque cote : une parabole de poutres,
## son tube neon, et des suspentes.
func _build_arch_ribs(node: Node3D, base_y: float, span: float, neon: Material) -> void:
	var segs := 12
	var rise := 17.0
	var concrete := _concrete()
	for side: float in [-1.0, 1.0]:
		var z := side * (deck_width / 2.0 - 0.9)
		for k in segs:
			var u0 := float(k) / segs
			var u1 := float(k + 1) / segs
			var a := Vector3((u0 - 0.5) * span, base_y + rise * 4.0 * u0 * (1.0 - u0), z)
			var b := Vector3((u1 - 0.5) * span, base_y + rise * 4.0 * u1 * (1.0 - u1), z)
			var mid := (a + b) / 2.0
			var rib := _box(node, Vector3(a.distance_to(b) + 0.4, 1.3, 1.3), mid, concrete)
			rib.rotation = Vector3(0.0, 0.0, atan2(b.y - a.y, b.x - a.x))
			var tube := _box(node, Vector3(a.distance_to(b), 0.22, 0.22), mid + Vector3(0.0, 0.0, side * 0.75), neon)
			tube.rotation = rib.rotation
			if k > 0:
				var hang := a.y - base_y
				_box(node, Vector3(0.25, hang, 0.25), Vector3(a.x, base_y + hang / 2.0, z), concrete)


## Mega-ecran holographique dresse sur le bord du tablier, face aux camions
## qui arrivent : fond anime (shader) et publicite (Label3D) qui alterne.
func _build_screen(node: Node3D, deck_y: float, facing: float, label: String, index: int) -> void:
	var size := Vector2(56.0, 13.0)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://tracks/materials/holo_screen.gdshader")
	mat.set_shader_parameter("seed", float(index))
	if index % 2 == 1:
		mat.set_shader_parameter("color_a", Color(1.0, 0.15, 0.8))
		mat.set_shader_parameter("color_b", Color(1.0, 0.75, 0.1))
	var screen := _quad_mesh(size, mat)
	screen.name = "HoloScreen"
	var z := facing * (deck_width / 2.0 + 0.8)
	screen.position = Vector3(0.0, deck_y + 5.0 + size.y / 2.0, z)
	screen.rotation = Vector3(0.0, 0.0 if facing > 0.0 else PI, 0.0)
	node.add_child(screen)
	# montants du cadre
	for x: float in [-size.x / 2.0 - 0.4, size.x / 2.0 + 0.4]:
		_box(node, Vector3(0.6, size.y + 3.0, 0.6), Vector3(x, deck_y + 3.5 + size.y / 2.0, z - facing * 0.4), _concrete())
	var l := Label3D.new()
	l.name = "Ad"
	l.text = label
	l.font_size = 300
	l.pixel_size = 0.022
	l.outline_size = 0
	l.modulate = Color(2.4, 2.4, 2.6)
	l.double_sided = false
	l.position = Vector3(0.0, deck_y + 5.0 + size.y / 2.0, z + facing * 0.3)
	l.rotation = screen.rotation
	node.add_child(l)
	screen_labels.append(l)


## Plus petite distance a partir de `start`, le long de `dir` depuis `origin`,
## ou une pile de pont est hors de la chaussee et de ses murs.
static func _first_clear(track: TrackBlockout, origin: Vector3, dir: Vector3, start: float, hint: int) -> float:
	# marge : la pile fait 16 m de long, et le pont peut croiser de biais
	var need := track.width / 2.0 + track.wall_thickness + track.wall_lean + 10.0
	var x := start
	while x < 400.0:
		var c := origin + dir * x
		var j := track.closest_sample(c, hint)
		var q := track.sample_position(j)
		if Vector2(c.x - q.x, c.z - q.z).length() > need:
			return x
		x += 2.0
	return x


# --- tribunes ---------------------------------------------------------------------

func _build_grandstands(root: Node3D, track: TrackBlockout) -> void:
	var stands := Node3D.new()
	stands.name = "Grandstands"
	root.add_child(stands)
	var xfs: Array[Transform3D] = []
	var colors := PackedColorArray()
	var custom := PackedColorArray()
	var concrete := _concrete()
	var beyond := track.width / 2.0 + track.wall_thickness + track.wall_lean + 5.0
	var rows := 8
	var row_depth := 1.7
	var row_rise := 1.05
	# deux blocs par cote : le long de la grille, puis apres la ligne de depart
	for block: Array in [[-105.0, -14.0], [16.0, 112.0]]:
		var s_mid := (float(block[0]) + float(block[1])) / 2.0
		var length := float(block[1]) - float(block[0])
		var i := track.index_at_s(s_mid)
		var p := track.sample_position(i)
		var t := (track.sample_forward(i) * Vector3(1, 0, 1)).normalized()
		var r := t.cross(Vector3.UP).normalized()
		for side: float in [-1.0, 1.0]:
			var stand := Node3D.new()
			stand.name = "Stand%d" % stands.get_child_count()
			# repere de la tribune : X le long de la piste, Z vers l'exterieur
			var out := r * side
			stand.transform = Transform3D(Basis(out.cross(Vector3.UP) * -1.0, Vector3.UP, out), p + out * beyond)
			stands.add_child(stand)
			for k in rows:
				var y := 1.2 + k * row_rise
				_box(stand, Vector3(length, y, row_depth), Vector3(0.0, y / 2.0, k * row_depth + row_depth / 2.0), concrete)
				# spectateurs du rang
				var seats := int(length / 0.85)
				for n in seats:
					if _rand() < 0.12:
						continue
					var x := (n + 0.5) / seats * length - length / 2.0
					var local := Vector3(x, y + 0.55, k * row_depth + row_depth * 0.55)
					xfs.append(stand.transform * Transform3D(Basis.IDENTITY.scaled(Vector3(0.5, 1.1, 0.4)), local))
					# vetements : couleurs ternes, beaucoup de noir, de gris et de blanc
					var sat := 0.05 if _rand() < 0.4 else 0.55
					colors.append(Color.from_hsv(_rand(), sat, 0.08 + 0.6 * _rand()))
					custom.append(Color(_rand(), (x + length / 2.0) / length, 0.0, 0.0))
			var depth := rows * row_depth
			var top := 1.2 + rows * row_rise
			# mur du fond, toit en porte-a-faux, lisere neon, rampe de projecteurs
			_box(stand, Vector3(length, top + 7.0, 0.8), Vector3(0.0, (top + 7.0) / 2.0, depth + 0.4), concrete)
			var roof := _box(stand, Vector3(length, 0.5, depth + 5.0), Vector3(0.0, top + 6.2, depth / 2.0 - 1.5), concrete)
			roof.rotation = Vector3(deg_to_rad(7.0), 0.0, 0.0)
			var neon: Material = preload("res://tracks/materials/neon_cyan.tres") if side < 0.0 \
					else preload("res://tracks/materials/neon_magenta.tres")
			_box(stand, Vector3(length, 0.3, 0.3), Vector3(0.0, top + 5.5, -3.9), neon)
			_box(stand, Vector3(length, 0.25, 0.25), Vector3(0.0, 1.25, -0.2), neon)
			if not night:
				continue
			_box(stand, Vector3(length - 6.0, 0.5, 0.7), Vector3(0.0, top + 5.0, -3.2), _lamp())
			for lx: float in [-length / 4.0, length / 4.0]:
				var light := OmniLight3D.new()
				light.light_color = Color(0.95, 0.95, 1.0)
				light.light_energy = 2.2
				light.omni_range = 34.0
				light.shadow_enabled = false
				light.position = Vector3(lx, top + 4.0, -2.0)
				stand.add_child(light)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var person := CylinderMesh.new()
	person.top_radius = 0.5
	person.bottom_radius = 0.45
	person.height = 1.0
	person.radial_segments = 8
	person.rings = 8
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://tracks/materials/crowd.gdshader")
	mat.set_shader_parameter("glow", 0.08 if night else 0.0)
	person.material = mat
	mm.mesh = person
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		mm.set_instance_color(k, colors[k])
		mm.set_instance_custom_data(k, custom[k])
	var crowd := MultiMeshInstance3D.new()
	crowd.name = "Crowd"
	crowd.multimesh = mm
	crowd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stands.add_child(crowd)
	stands.set_meta(&"spectators", xfs.size())


# --- faisceaux ---------------------------------------------------------------------

## Projecteurs derriere les tribunes : faisceaux vers le ciel, qui balaient.
func _build_beams(root: Node3D, track: TrackBlockout) -> void:
	var colors := [Color(0.1, 0.9, 1.0), Color(1.0, 0.15, 0.8), Color(0.55, 0.3, 1.0), Color(1.0, 0.85, 0.3)]
	var beyond := track.width / 2.0 + 28.0
	var k := 0
	for s: float in [-95.0, -35.0, 35.0, 95.0]:
		var i := track.index_at_s(s)
		var p := track.sample_position(i)
		var t := (track.sample_forward(i) * Vector3(1, 0, 1)).normalized()
		var r := t.cross(Vector3.UP).normalized()
		for side: float in [-1.0, 1.0]:
			var col: Color = colors[k % colors.size()]
			var base := p + r * side * beyond
			var lamp := StandardMaterial3D.new()
			lamp.albedo_color = col
			lamp.emission_enabled = true
			lamp.emission = col
			lamp.emission_energy_multiplier = 5.0
			_box(root, Vector3(2.2, 1.0, 2.2), base + Vector3(0.0, 13.5, 0.0), lamp)
			_box(root, Vector3(1.0, 13.0, 1.0), base + Vector3(0.0, 6.5, 0.0), _concrete())
			var pivot := Node3D.new()
			pivot.name = "Beam%d" % k
			pivot.position = base + Vector3(0.0, 14.0, 0.0)
			pivot.rotation.y = atan2(r.x * side, r.z * side) + PI / 2.0
			# balaye dans _process : pas d'interpolation physique
			pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			root.add_child(pivot)
			var beam := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 9.0
			cone.bottom_radius = 0.7
			cone.height = 170.0
			cone.cap_top = false
			cone.cap_bottom = false
			cone.radial_segments = 20
			beam.mesh = cone
			var bm := ShaderMaterial.new()
			bm.shader = preload("res://ui/light_beam.gdshader")
			bm.set_shader_parameter("color", col)
			bm.set_shader_parameter("height", cone.height)
			bm.set_shader_parameter("strength", 0.3)
			beam.material_override = bm
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			beam.position = Vector3(0.0, cone.height / 2.0, 0.0)
			pivot.add_child(beam)
			beams.append(pivot)
			k += 1


# --- utilitaires ------------------------------------------------------------------

static var _mat_concrete: StandardMaterial3D
static var _mat_lamp: StandardMaterial3D


static var _mat_concrete_day: StandardMaterial3D


func _concrete() -> StandardMaterial3D:
	if not night:
		if _mat_concrete_day == null:
			_mat_concrete_day = StandardMaterial3D.new()
			_mat_concrete_day.albedo_color = Color(0.74, 0.72, 0.68)
			_mat_concrete_day.roughness = 0.85
		return _mat_concrete_day
	if _mat_concrete == null:
		_mat_concrete = StandardMaterial3D.new()
		_mat_concrete.albedo_color = Color(0.07, 0.075, 0.095)
		_mat_concrete.metallic = 0.35
		_mat_concrete.roughness = 0.5
	return _mat_concrete


static func _lamp() -> StandardMaterial3D:
	if _mat_lamp == null:
		_mat_lamp = StandardMaterial3D.new()
		_mat_lamp.albedo_color = Color(1.0, 0.97, 0.9)
		_mat_lamp.emission_enabled = true
		_mat_lamp.emission = Color(1.0, 0.96, 0.88)
		_mat_lamp.emission_energy_multiplier = 4.0
	return _mat_lamp


static func _traffic(length: float, lanes: float, tail: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://tracks/materials/overpass_traffic.gdshader")
	m.set_shader_parameter("length_m", length)
	m.set_shader_parameter("lanes", lanes)
	m.set_shader_parameter("tail_lights", tail)
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Panneau vertical (dans le plan XY, face avant vers +Z).
static func _quad_mesh(size: Vector2, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- eclairage public -------------------------------------------------------------

## Lampadaires de nuit (2026-10-07 : « Night City est trop sombre, la vision
## est compliquee ») : un tous les STREET_LIGHT_SPACING metres, en quinconce,
## plantes sur le muret, crosse au-dessus de la chaussee et projecteur LED
## dirige vers le sol (SpotLight3D sans ombre : la route, les camions et les
## virages a venir sont eclaires par flaques). Aucun la ou une autre partie
## de la piste passe (croisement, echangeur). Mats et crosses : MultiMesh.
const STREET_LIGHT_SPACING := 34.0
const STREET_LIGHT_HEIGHT := 9.5
const STREET_LIGHT_ARM := 3.2
const STREET_LIGHT_ENERGY := 14.0
const STREET_LIGHT_RANGE := 28.0
const STREET_LIGHT_ANGLE := 58.0
const STREET_LIGHT_COLOR := Color(0.92, 0.94, 1.0)


func _build_street_lights(root: Node3D, track: TrackBlockout) -> void:
	var node := Node3D.new()
	node.name = "StreetLights"
	root.add_child(node)
	var poles: Array[Transform3D] = []
	var arms: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var beyond := track.width / 2.0 + track.wall_thickness + track.wall_lean + 0.35
	var count := floori(track.length() / STREET_LIGHT_SPACING)
	for k in count:
		var s := (k + 0.5) * STREET_LIGHT_SPACING
		var i := track.index_at_s(s)
		var side := 1.0 if k % 2 == 0 else -1.0
		var p := track.sample_position(i)
		var right := (track.sample_right(i) * Vector3(1, 0, 1)).normalized()
		var fwd := (track.sample_forward(i) * Vector3(1, 0, 1)).normalized()
		var foot := p + right * side * beyond
		# rien a cote d'une autre partie de la piste (croisement, echangeur)
		var other := track.closest_sample(foot + right * side * 2.0)
		var gap := absi(other - i)
		if mini(gap, track.sample_count() - gap) > 20:
			continue
		var top := foot + Vector3.UP * STREET_LIGHT_HEIGHT
		var basis := Basis.looking_at(-right * side, Vector3.UP)
		poles.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.24, STREET_LIGHT_HEIGHT, 0.24)),
			foot + Vector3.UP * STREET_LIGHT_HEIGHT / 2.0))
		var arm_c := top - right * side * STREET_LIGHT_ARM / 2.0
		arms.append(Transform3D(basis * Basis.IDENTITY.scaled(Vector3(0.14, 0.14, STREET_LIGHT_ARM)), arm_c))
		var head_p := top - right * side * (STREET_LIGHT_ARM - 0.3) + Vector3.DOWN * 0.12
		heads.append(Transform3D(basis * Basis.IDENTITY.scaled(Vector3(0.5, 0.12, 0.9)), head_p))
		var light := SpotLight3D.new()
		light.light_color = STREET_LIGHT_COLOR
		light.light_energy = STREET_LIGHT_ENERGY
		light.spot_range = STREET_LIGHT_RANGE
		light.spot_angle = STREET_LIGHT_ANGLE
		light.spot_angle_attenuation = 0.8
		light.spot_attenuation = 0.6
		light.shadow_enabled = false
		light.light_volumetric_fog_energy = 0.25
		# vers le sol, un peu vers le milieu de la chaussee
		light.transform = Transform3D(Basis.looking_at(Vector3.DOWN * 3.0 - right * side, fwd), head_p + Vector3.DOWN * 0.2)
		node.add_child(light)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.33, 0.35)
	steel.metallic = 0.6
	steel.roughness = 0.45
	_multimesh(node, "Poles", poles, steel)
	_multimesh(node, "Arms", arms, steel)
	_multimesh(node, "Heads", heads, _lamp())
	node.set_meta(&"count", heads.size())


static func _multimesh(parent: Node3D, label: String, xfs: Array[Transform3D], mat: Material) -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bm
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)
