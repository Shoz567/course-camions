class_name Showroom
extends Node3D

## Decor du menu principal : le plateau tournant (les camions choisis y sont
## exposes, alignes) dans le decor du circuit choisi (2026-10-19 : « quand on
## preselect playa ou sakura ca change le background ») :
##   CYBER_CITY    le toit d'une tour de Cyber City : anneaux neon,
##                 projecteurs (cle blanche, contres magenta et cyan),
##                 faisceaux qui balaient le ciel, la ville en contrebas ;
##   PLAYA_DEL_SOL une ile au soleil : plage de sable, ponton de bois sous le
##                 plateau, lagon turquoise, palmiers, parasols, phare, rochers
##                 au large ;
##   SAKURA        un jardin japonais : gravier ratisse, cerisiers en fleur,
##                 grand torii, pagode, temple, lanternes de pierre, le Fuji a
##                 l'horizon, petales qui volent.
## Chaque decor se construit a sa premiere apparition, puis se cache ou se
## montre (set_theme). Purement visuel, sauf le dessus du plateau (couche 1
## `world`) : les rayons de suspension des camions s'y posent.

const PLATE_RADIUS := 24.0
const PLATE_TOP := 0.5
## Ecart lateral entre deux camions exposes (resserre a 5 et 6 camions).
const SLOT_SPACING := 8.0
const SLOT_SPACING_TIGHT := 6.6
## Centre de l'ensemble semi-remorque (le tracteur est a l'avant, en -Z).
const RIG_CENTER_Z := 6.3

@export var turn_speed: float = 0.12        # rad/s
@export var city_seed: int = 11

## Tourne avec les camions (les camions en sont enfants).
var turntable: Node3D
## Point vise par la camera.
var focus: Vector3 = Vector3(0.0, 3.0, 0.0)
## Decor montre (TrackTheme.Id).
var theme_id: int = -1
## Camera a suivre pour les effets autour d'elle (petales de Sakura).
var camera: Node3D
var _sets: Dictionary = {}
var _beams: Array[Node3D] = []
var _ring: MeshInstance3D
var _plate_mat: StandardMaterial3D
var _time: float = 0.0
var _state: int = 1


func _ready() -> void:
	_build_turntable()


func _process(delta: float) -> void:
	_time += delta
	turntable.rotate_y(turn_speed * delta)
	# faisceaux : balayage lent, dephase
	if theme_id == TrackTheme.Id.CYBER_CITY:
		for k in _beams.size():
			var b := _beams[k]
			b.rotation = Vector3(deg_to_rad(14.0 + 8.0 * sin(_time * 0.35 + k)), b.rotation.y,
				deg_to_rad(10.0 * sin(_time * 0.27 + k * 1.7)))


## Montre le decor du circuit `id` (TrackTheme.Id), construit au besoin ;
## l'anneau du plateau et l'etat des camions (meteo) suivent.
func set_theme(id: int) -> void:
	theme_id = id
	if not _sets.has(id):
		var node := Node3D.new()
		node.name = ["CyberSet", "PlayaSet", "SakuraSet"][clampi(id, 0, 2)]
		add_child(node)
		match id:
			TrackTheme.Id.PLAYA_DEL_SOL: _build_playa(node)
			TrackTheme.Id.SAKURA: _build_sakura(node)
			_: _build_cyber(node)
		_sets[id] = node
	for k: int in _sets:
		(_sets[k] as Node3D).visible = k == id
	TruckLights.night = false
	TruckWheelFx.spray = TruckWheelFx.Spray.NONE
	match id:
		TrackTheme.Id.PLAYA_DEL_SOL:
			# plateau blanc de bateau, liseré lagon
			TruckMaterials.set_weather(TruckMaterials.BEACH_GRIME, 0.0)
			_ring.material_override = _glow(Color(0.2, 0.95, 0.95), 1.5)
			_set_plate(Color(0.9, 0.9, 0.86), 0.1, 0.35)
		TrackTheme.Id.SAKURA:
			# laque brun-noir, liseré vermillon
			TruckMaterials.set_weather(TruckMaterials.BEACH_GRIME, 0.0)
			_ring.material_override = _glow(Color(0.95, 0.2, 0.1), 1.4)
			_set_plate(Color(0.2, 0.07, 0.035), 0.05, 0.4)
		_:
			# toit sous la pluie : camions de la ville, sales et mouilles
			TruckMaterials.set_weather(TruckMaterials.CITY_GRIME, 0.6)
			_ring.material_override = preload("res://tracks/materials/neon_magenta.tres")
			_set_plate(Color(0.04, 0.045, 0.06), 0.85, 0.18)


func _set_plate(color: Color, metallic: float, roughness: float) -> void:
	_plate_mat.albedo_color = color
	_plate_mat.metallic = metallic
	_plate_mat.roughness = roughness


## Decor monte (tests).
func set_node(id: int) -> Node3D:
	return _sets.get(id) as Node3D


func _rand() -> float:
	_state = (_state * 1103515245 + 12345) & 0x7fffffff
	return float(_state) / 2147483648.0


func _range(a: float, b: float) -> float:
	return a + (b - a) * _rand()


## Pose du camion `i` quand `n` camions sont exposes : alignes cote a cote,
## centres sur le plateau (repere du plateau tournant).
static func slot(i: int, n: int) -> Transform3D:
	var x := (i - (n - 1) / 2.0) * (SLOT_SPACING if n <= 4 else SLOT_SPACING_TIGHT)
	return Transform3D(Basis.IDENTITY, Vector3(x, PLATE_TOP, -RIG_CENTER_Z))


func _build_turntable() -> void:
	turntable = Node3D.new()
	turntable.name = "Turntable"
	# tourne dans _process : pas d'interpolation physique (ni pour les camions)
	turntable.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(turntable)
	var plate := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = PLATE_RADIUS
	cyl.bottom_radius = PLATE_RADIUS
	cyl.height = PLATE_TOP
	cyl.radial_segments = 96
	plate.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.045, 0.06)
	mat.metallic = 0.85
	mat.roughness = 0.18
	plate.material_override = mat
	_plate_mat = mat
	plate.position = Vector3(0.0, PLATE_TOP / 2.0, 0.0)
	turntable.add_child(plate)
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = PLATE_RADIUS - 0.25
	torus.outer_radius = PLATE_RADIUS + 0.25
	torus.rings = 96
	_ring.mesh = torus
	_ring.material_override = preload("res://tracks/materials/neon_magenta.tres")
	_ring.position = Vector3(0.0, PLATE_TOP, 0.0)
	turntable.add_child(_ring)
	# dessus du plateau : fixe (un disque qui tourne sur son axe ne change pas
	# de forme), sur la couche 1 pour les rayons de suspension
	var body := StaticBody3D.new()
	body.name = "PlateCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = PLATE_RADIUS
	shape.height = PLATE_TOP
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(0.0, PLATE_TOP / 2.0, 0.0)
	add_child(body)


# --- Cyber City : le toit de la tour ---------------------------------------------

func _build_cyber(root: Node3D) -> void:
	# toit de la tour : grande dalle, bord lumineux, facades qui plongent
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = preload("res://ui/showroom_floor.gdshader")
	var roof := _box(root, Vector3(150.0, 2.0, 150.0), Vector3(0.0, -1.0, 0.0), floor_mat)
	roof.name = "Roof"
	var tower_mat := StandardMaterial3D.new()
	tower_mat.albedo_color = Color(0.03, 0.035, 0.05)
	tower_mat.metallic = 0.5
	tower_mat.roughness = 0.4
	_box(root, Vector3(146.0, 140.0, 146.0), Vector3(0.0, -72.0, 0.0), tower_mat)
	var edge := preload("res://tracks/materials/neon_cyan.tres")
	for k in 4:
		var along := Vector3(150.0, 0.25, 0.25) if k < 2 else Vector3(0.25, 0.25, 150.0)
		var pos := Vector3(0.0, 0.1, 75.0 * (1 if k == 0 else -1)) if k < 2 \
				else Vector3(75.0 * (1 if k == 2 else -1), 0.1, 0.0)
		_box(root, along, pos, edge)
	# sol de la ville, loin en contrebas
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000.0, 4000.0)
	ground.mesh = pm
	ground.material_override = preload("res://tracks/materials/grass.tres")
	ground.position = Vector3(0.0, -140.0, 0.0)
	root.add_child(ground)
	_spot(root, "KeyLight", Vector3(6.0, 32.0, 30.0), Color(0.85, 0.9, 1.0), 7.0, true)
	_spot(root, "RimMagenta", Vector3(-32.0, 16.0, -24.0), Color(1.0, 0.2, 0.8), 6.0, false)
	_spot(root, "RimCyan", Vector3(32.0, 16.0, -24.0), Color(0.1, 0.9, 1.0), 6.0, false)
	_build_beams(root)
	if DisplayServer.get_name() != "headless" or CityBackdrop.generate_in_headless:
		var cb := CityBuilder.new(city_seed)
		cb.add_ring(Vector3(0.0, -140.0, 0.0), 110.0, 950.0, 260, 60.0, 250.0)
		root.add_child(cb.build())


func _spot(root: Node3D, light_name: String, pos: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var l := SpotLight3D.new()
	l.name = light_name
	l.light_color = color
	l.light_energy = energy
	l.spot_range = 90.0
	l.spot_angle = 34.0
	l.shadow_enabled = shadows
	root.add_child(l)
	l.look_at_from_position(pos, focus, Vector3.UP)


## Projecteurs au sol autour du plateau, et leurs faisceaux vers le ciel.
func _build_beams(root: Node3D) -> void:
	var colors := [Color(0.1, 0.9, 1.0), Color(1.0, 0.15, 0.8), Color(0.55, 0.3, 1.0)]
	for k in 6:
		var a := TAU * k / 6.0 + 0.3
		var base := Vector3(cos(a), 0.0, sin(a)) * 32.0
		var col: Color = colors[k % 3]
		var lamp := StandardMaterial3D.new()
		lamp.albedo_color = col
		lamp.emission_enabled = true
		lamp.emission = col
		lamp.emission_energy_multiplier = 5.0
		_box(root, Vector3(1.6, 0.7, 1.6), base + Vector3(0.0, 0.35, 0.0), lamp)
		var pivot := Node3D.new()
		pivot.position = base + Vector3(0.0, 0.7, 0.0)
		pivot.rotation.y = -a + PI / 2.0
		root.add_child(pivot)
		var beam := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 5.0
		cone.bottom_radius = 0.5
		cone.height = 70.0
		cone.cap_top = false
		cone.cap_bottom = false
		cone.radial_segments = 24
		beam.mesh = cone
		var bm := ShaderMaterial.new()
		bm.shader = preload("res://ui/light_beam.gdshader")
		bm.set_shader_parameter("color", col)
		beam.material_override = bm
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3(0.0, 35.0, 0.0)
		pivot.add_child(beam)
		_beams.append(pivot)


# --- Playa Del Sol : l'ile au soleil ---------------------------------------------

func _build_playa(root: Node3D) -> void:
	_state = 5
	# lagon a perte de vue, ile de sable en pente douce, ponton sous le plateau
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var sp := PlaneMesh.new()
	sp.size = Vector2(6000.0, 6000.0)
	sea.mesh = sp
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.02, 0.42, 0.52)
	water.metallic = 0.2
	water.roughness = 0.04
	sea.material_override = water
	sea.position = Vector3(0.0, -0.9, 0.0)
	root.add_child(sea)
	var shallow := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 230.0
	sm.bottom_radius = 230.0
	sm.height = 0.1
	sm.radial_segments = 64
	shallow.mesh = sm
	var lagoon := StandardMaterial3D.new()
	lagoon.albedo_color = Color(0.2, 0.85, 0.82, 0.75)
	lagoon.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lagoon.roughness = 0.05
	shallow.material_override = lagoon
	shallow.position = Vector3(0.0, -0.82, 0.0)
	root.add_child(shallow)
	var island := MeshInstance3D.new()
	island.name = "Island"
	var im := CylinderMesh.new()
	im.top_radius = 150.0
	im.bottom_radius = 205.0
	im.height = 1.6
	im.radial_segments = 72
	island.mesh = im
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.9, 0.8, 0.6)
	sand.roughness = 0.95
	island.material_override = sand
	island.position = Vector3(0.0, -0.8, 0.0)
	root.add_child(island)
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	var dm := CylinderMesh.new()
	dm.top_radius = PLATE_RADIUS + 6.0
	dm.bottom_radius = PLATE_RADIUS + 6.0
	dm.height = 0.3
	dm.radial_segments = 64
	deck.mesh = dm
	deck.material_override = TrackTheme.of(TrackTheme.Id.PLAYA_DEL_SOL).bridge_wood
	deck.position = Vector3(0.0, 0.1, 0.0)
	root.add_child(deck)
	# palmiers, parasols, rochers au large (maillages de PlayaBackdrop)
	var palms: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	for k in 46:
		var a := _rand() * TAU
		var d := _range(PLATE_RADIUS + 12.0, 135.0)
		var at := Vector3(cos(a) * d, 0.0, sin(a) * d)
		var h := _range(9.0, 15.0)
		var b := Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(h, h, h))
		palms.append(Transform3D(b, at))
		var cs := h * _range(0.42, 0.55)
		crowns.append(Transform3D(Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(cs, cs, cs)), at + b * Vector3(0.14, 1.0, 0.0)))
	root.add_child(PlayaBackdrop._multimesh("Palms", PlayaBackdrop._trunk_mesh(), palms, PackedColorArray(), true))
	root.add_child(PlayaBackdrop._multimesh("PalmCrowns", PlayaBackdrop._crown_mesh(), crowns, PackedColorArray(), true))
	var parasols: Array[Transform3D] = []
	var poles: Array[Transform3D] = []
	var colors := PackedColorArray()
	var tints := [Color(0.95, 0.2, 0.2), Color(1.0, 0.8, 0.1), Color(0.1, 0.6, 0.95), Color(0.98, 0.98, 0.95),
		Color(1.0, 0.45, 0.7), Color(0.2, 0.8, 0.55)]
	for k in 16:
		var a := _rand() * TAU
		var d := _range(PLATE_RADIUS + 10.0, 80.0)
		var at := Vector3(cos(a) * d, 0.0, sin(a) * d)
		var size := _range(1.9, 2.6)
		parasols.append(Transform3D(Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(size, size, size)), at + Vector3(0, 2.3, 0)))
		poles.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.07, 2.5, 0.07)), at + Vector3(0, 1.25, 0)))
		colors.append(tints[k % tints.size()])
	root.add_child(PlayaBackdrop._multimesh("Parasols", PlayaBackdrop._parasol_mesh(), parasols, colors, true))
	root.add_child(PlayaBackdrop._multimesh("ParasolPoles", PlayaBackdrop._pole_mesh(), poles, PackedColorArray(), false))
	var rocks: Array[Transform3D] = []
	for k in 14:
		var a := _rand() * TAU
		var d := _range(360.0, 1200.0)
		var w := _range(25.0, 80.0)
		var h := w * _range(0.3, 1.2)
		rocks.append(Transform3D(Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(w, h, w * _range(0.7, 1.3))),
			Vector3(cos(a) * d, -h * 0.15, sin(a) * d)))
	root.add_child(PlayaBackdrop._multimesh("Rocks", PlayaBackdrop._rock_mesh(), rocks, PackedColorArray(), true))
	root.add_child(PlayaBackdrop.build_lighthouse(Vector3(-95.0, 0.0, -70.0)))


# --- Sakura : le jardin japonais -------------------------------------------------

func _build_sakura(root: Node3D) -> void:
	_state = 7
	var ground := MeshInstance3D.new()
	ground.name = "Garden"
	var gp := PlaneMesh.new()
	gp.size = Vector2(5000.0, 5000.0)
	ground.mesh = gp
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://tracks/materials/sakura_ground.gdshader")
	ground.material_override = gm
	root.add_child(ground)
	# cour de gravier ratisse sous le plateau, bordee de pierre
	var court := MeshInstance3D.new()
	court.name = "Gravel"
	var cm := CylinderMesh.new()
	cm.top_radius = PLATE_RADIUS + 9.0
	cm.bottom_radius = PLATE_RADIUS + 9.5
	cm.height = 0.12
	cm.radial_segments = 72
	court.mesh = cm
	var gravel := StandardMaterial3D.new()
	gravel.albedo_color = Color(0.82, 0.78, 0.7)
	gravel.roughness = 0.95
	court.material_override = gravel
	court.position = Vector3(0.0, 0.06, 0.0)
	root.add_child(court)
	var kit := JapanKit.new()
	var stone := ShaderMaterial.new()
	stone.shader = preload("res://tracks/materials/sakura_stone.gdshader")
	# grand torii derriere le plateau, pagode, temple, lanternes de pierre
	kit.torii(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, 0.0, -58.0)), 34.0, 16.0)
	kit.pagoda(Transform3D(Basis(Vector3.UP, 0.6), Vector3(-82.0, 0.0, -96.0)), 5, 11.0)
	kit.temple(Transform3D(Basis(Vector3.UP, -2.4), Vector3(95.0, 0.0, 70.0)), 30.0, 20.0)
	for k in 10:
		var a := TAU * k / 10.0 + 0.3
		kit.stone_lantern(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a), 0, sin(a)) * (PLATE_RADIUS + 11.0)))
	var mats := {JapanKit.Mat.PLASTER: _shader_mat(preload("res://tracks/materials/sakura_house.gdshader")),
		JapanKit.Mat.WOOD: SakuraBackdrop._wood(), JapanKit.Mat.LACQUER: TrackTheme.of(TrackTheme.Id.SAKURA).arch_tubes[0],
		JapanKit.Mat.ROOF: _shader_mat(preload("res://tracks/materials/sakura_roof.gdshader")), JapanKit.Mat.STONE: stone,
		JapanKit.Mat.GOLD: _glow(Color(0.95, 0.72, 0.25), 0.0), JapanKit.Mat.PAPER: _glow(Color(1.0, 0.8, 0.5), 1.4)}
	var mi := MeshInstance3D.new()
	mi.name = "Shrine"
	mi.mesh = kit.commit(mats)
	root.add_child(mi)
	# cerisiers tout autour, quelques pins (maillages de SakuraBackdrop)
	var trees: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var colors := PackedColorArray()
	var tries := 0
	while trees.size() < 70 and tries < 600:
		tries += 1
		var a := _rand() * TAU
		var d := _range(PLATE_RADIUS + 16.0, 150.0)
		var at := Vector3(cos(a) * d, 0.0, sin(a) * d)
		# pas devant le torii ni sur les monuments
		if Vector2(at.x, at.z + 58.0).length() < 24.0 or Vector2(at.x + 82.0, at.z + 96.0).length() < 22.0 \
				or Vector2(at.x - 95.0, at.z - 70.0).length() < 30.0:
			continue
		var h := _range(4.5, 7.0)
		var pine := _rand() < 0.15
		trees.append(Transform3D(Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(h * 0.1, h, h * 0.1)), at))
		var s := h * _range(0.95, 1.25) * (0.8 if pine else 1.0)
		crowns.append(Transform3D(Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(s, s * (0.55 if pine else 0.75), s)),
			at + Vector3(0, h * 0.92, 0)))
		colors.append(SakuraBackdrop.PINE if pine else SakuraBackdrop.BLOSSOMS[int(_rand() * 6.0) % 6])
	var trunk := SakuraBackdrop._trunk_mesh()
	var crown := SakuraBackdrop._crown_mesh()
	crown.surface_set_material(0, _shader_mat(preload("res://tracks/materials/sakura_blossom.gdshader")))
	root.add_child(PlayaBackdrop._multimesh("Trunks", trunk, trees, PackedColorArray(), true))
	root.add_child(PlayaBackdrop._multimesh("Crowns", crown, crowns, colors, true))
	root.add_child(SakuraBackdrop.build_mountains(Vector3.ZERO, Vector3(0, 0, -1).rotated(Vector3.UP, 0.5)))
	_spot(root, "KeyLight", Vector3(10.0, 30.0, 32.0), Color(1.0, 0.9, 0.8), 3.0, false)
	_spot(root, "RimPink", Vector3(-30.0, 14.0, -24.0), Color(1.0, 0.55, 0.7), 4.0, false)
	if camera != null and DisplayServer.get_name() != "headless":
		root.add_child(SakuraPetals.make(camera, 0))


static func _shader_mat(s: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = s
	return m


## Matiere lumineuse (anneau du plateau, papier des lanternes, or).
static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
	else:
		m.metallic = 1.0
		m.roughness = 0.25
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
