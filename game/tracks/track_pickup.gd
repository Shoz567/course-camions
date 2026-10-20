class_name TrackPickup
extends Area3D

## Bonus pose sur la piste (2026-10-20 : « des bonus sur la piste :
## reparation, recharge de pouvoir »). Un cube lumineux qui tourne et flotte,
## frappe de son symbole (croix verte : reparation ; eclair jaune :
## recharge). Un camion qui le traverse le prend (`taken`) ; il disparait,
## puis revient a sa place apres respawn_ticks. L'effet est l'affaire du
## gameplay (PadEffects). En ligne, chez un client (net_mirror) : il ne se
## prend pas ici, le host annonce qui l'a pris (net_take).
## Deterministe : aucun tirage ; durees en ticks.

signal taken(truck: Truck, pickup: TrackPickup)

enum Kind { REPAIR, POWER }

const RADIUS_M := 3.2
const SIZE_M := 2.4
const FLOAT_M := 1.8

@export var kind: Kind = Kind.REPAIR
@export var respawn_ticks: int = 900
var net_mirror: bool = false
var index: int = -1
var _away: int = 0
var _visual: Node3D
var _spin: float = 0.0


func _init() -> void:
	collision_layer = 0
	collision_mask = 1 << (TruckSpec.LAYER_VEHICLE - 1)
	monitorable = false
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS_M
	cs.shape = sphere
	cs.position = Vector3(0.0, FLOAT_M, 0.0)
	add_child(cs)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if DisplayServer.get_name() == "headless":
		return
	_visual = Node3D.new()
	_visual.position = Vector3(0.0, FLOAT_M, 0.0)
	add_child(_visual)
	var col := color_of(kind)
	var cube := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * SIZE_M
	cube.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cube.material_override = mat
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(cube)
	var mark := Label3D.new()
	mark.text = "✚" if kind == Kind.REPAIR else "⚡"
	mark.font_size = 220
	mark.pixel_size = 0.012
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.modulate = Color.WHITE
	mark.outline_size = 24
	mark.outline_modulate = Color(col.darkened(0.6), 1.0)
	mark.no_depth_test = false
	_visual.add_child(mark)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.6
	light.omni_range = 9.0
	_visual.add_child(light)


static func color_of(k: Kind) -> Color:
	return Color(0.25, 1.0, 0.45) if k == Kind.REPAIR else Color(1.0, 0.85, 0.15)


## Pret a etre pris.
func available() -> bool:
	return _away == 0


func _physics_process(_delta: float) -> void:
	if _away > 0:
		_away -= 1
		if _away == 0:
			_show(true)


func _process(delta: float) -> void:
	if _visual != null and _visual.visible:
		_spin = fmod(_spin + delta * 1.8, TAU)
		_visual.rotation = Vector3(0.35, _spin, 0.2)
		_visual.position.y = FLOAT_M + sin(_spin * 2.0) * 0.25


func _on_body_entered(body: Node3D) -> void:
	var truck := body as Truck
	if truck == null or net_mirror or _away > 0 or truck.is_wrecked():
		return
	_take(truck)


## Client en ligne : le host a vu `truck` le prendre.
func net_take(truck: Truck) -> void:
	if truck != null:
		_take(truck)


func _take(truck: Truck) -> void:
	_away = respawn_ticks
	_show(false)
	taken.emit(truck, self)


func _show(on: bool) -> void:
	set_deferred(&"monitoring", on)
	if _visual != null:
		_visual.visible = on
