class_name TruckWreck
extends DetachedTrailer

## Carcasse d'un tracteur detruit (2026-10-06 : « quand le camion prend trop
## de degats et explose, il reste au milieu du chemin ») : elle reste sur la
## route, comme une remorque larguee, et fait obstacle a tout le monde. Meme
## regles qu'elle (DetachedTrailer) : un camion qui la percute est ralenti et
## prend des degats (TruckHealth), elle s'abime, se cabosse, et explose a 0 PV.
## Le joueur, lui, reapparait sur un camion neuf.
##
## Boites du tracteur (VEHICLE_SPEC §5), chassis prolonge jusqu'au sol : la
## carcasse repose sur ses jantes brulees. Repere : celui du camion.

const WRECK_HP := 60.0
const WRECK_MASS := TruckSpec.MASS_KG
## Le feu de la carcasse s'eteint apres ce nombre d'images (visuel).
const FIRE_FRAMES := 600

var _cab: CollisionShape3D
var _fire: GPUParticles3D
var _burn_frames: int = 0


func _init() -> void:
	super()
	name = "TruckWreck"
	trailer_mass = WRECK_MASS
	mass = WRECK_MASS
	max_hp = WRECK_HP


func _shape_box() -> void:
	var c := TruckSpec.CHASSIS_CENTER
	var s := TruckSpec.CHASSIS_SIZE
	var top := c.y + s.y / 2.0
	var box := _shape.shape as BoxShape3D
	box.size = Vector3(s.x, top - 0.05, s.z)
	_shape.position = Vector3(c.x, (top + 0.05) / 2.0, c.z)
	if _cab == null:
		_cab = CollisionShape3D.new()
		_cab.shape = BoxShape3D.new()
		add_child(_cab)
	(_cab.shape as BoxShape3D).size = TruckSpec.CAB_SIZE
	_cab.position = TruckSpec.CAB_CENTER
	box_size = Vector3(s.x, top, s.z)


## Visuel calcine : toutes les surfaces assombries d'un voile de suie.
func set_visual(v: Node3D) -> void:
	if v == null:
		return
	var soot := StandardMaterial3D.new()
	soot.albedo_color = Color(0.03, 0.025, 0.02, 0.82)
	soot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	soot.roughness = 1.0
	for n in v.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_overlay = soot
	super.set_visual(v)


func _ready() -> void:
	super._ready()
	# une carcasse fume des le debut
	DamageFx.set_smoke(_smoke, DamageFx.Smoke.WRECK)
	damage_stage = 1
	# le moteur brule encore un moment (purement visuel)
	_fire = FxKit.make_fire(40, 0.7, 1.3)
	_fire.position = TruckSpec.CAB_CENTER + Vector3(0.0, -0.6, -1.2)
	_fire.amount_ratio = FxKit.density()
	_fire.emitting = true
	add_child(_fire)


func _process(_delta: float) -> void:
	_burn_frames += 1
	if _burn_frames == FIRE_FRAMES and _fire != null:
		_fire.emitting = false
