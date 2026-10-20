class_name TruckPreview
extends SubViewportContainer

## Vitrine 3D d'un joueur sur la page de selection : son camion (modele,
## livree) et la remorque choisie, sur un socle qui tourne lentement, eclaire
## a sa couleur. Monde 3D a part (own_world_3d) et fond transparent : le
## panneau dessine le fond. Le camion est gele : du decor, pas de physique.

const LocalRace := preload("res://dev/local_race.gd")
const RIG_CENTER_Z := 6.3

var player: int = 0
var accent: Color = Color.WHITE
var truck: Truck
var _pivot: Node3D
var _view: SubViewport
var _ring: MeshInstance3D
var _spin: float = 0.0


func _init(player_index: int = 0, accent_color: Color = Color.WHITE) -> void:
	player = player_index
	accent = accent_color
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_view)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.8)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# halo du socle : neon seulement (Playa, Sakura : pas d'effet neon)
	env.glow_enabled = UiKit.skin == UiKit.Look.NEON
	env.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	_view.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	_view.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20.0, 200.0, 0.0)
	rim.light_color = accent
	rim.light_energy = 1.4
	_view.add_child(rim)
	_pivot = Node3D.new()
	_view.add_child(_pivot)
	# socle : disque sombre et anneau lumineux a la couleur du joueur
	var plate := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 13.0
	cyl.bottom_radius = 13.4
	cyl.height = 0.5
	cyl.radial_segments = 64
	plate.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.05, 0.055, 0.1)
	pm.metallic = 0.6
	pm.roughness = 0.25
	plate.material_override = pm
	plate.position.y = -0.25
	_pivot.add_child(plate)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 13.0
	torus.outer_radius = 13.5
	torus.rings = 64
	_ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = accent * (2.2 if UiKit.skin == UiKit.Look.NEON else 1.0)
	_ring.material_override = rm
	_ring.position.y = 0.02
	_pivot.add_child(_ring)
	truck = (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	truck.name = "PreviewTruck"
	truck.freeze = true
	truck.position = Vector3(0.0, 0.0, -RIG_CENTER_Z)
	LocalRace.dress(truck.get_node("Visual") as TruckVisual, player)
	_pivot.add_child(truck)
	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.position = Vector3(18.5, 7.5, -19.5)
	_view.add_child(cam)
	cam.look_at(Vector3(0.0, 1.6, 0.0), Vector3.UP)
	cam.current = true
	_spin = deg_to_rad(-25.0)


func set_trailer(type: TrailerType) -> void:
	if truck != null:
		(truck.get_node("Visual") as TruckVisual).set_trailer_type(type)


func _process(delta: float) -> void:
	if _pivot == null:
		return
	_spin += delta * 0.35
	_pivot.rotation.y = _spin
