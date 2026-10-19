class_name RoadsideSign
extends RigidBody3D

## Panneau de bord de piste (fleches de virage lumineuses). Gele debout tant
## que personne n'y touche ; une zone un peu plus large que lui detecte le
## camion qui arrive : le panneau est ejecte (vitesse du camion x 1,3, 9 m/s
## vers le haut, en toupie) et signale le choc (`hit`) - le ralentissement du
## camion est l'affaire du gameplay (PadEffects). Il ne heurte jamais les
## camions (couche 5 `hazard`, masque : le decor seulement) : c'est la zone
## qui decide, pas un mur surprise. respawn_ticks plus tard, il reprend sa
## place, pour le tour suivant.

signal hit(truck: Truck)

const HAZARD_LAYER := 5
const POST_HEIGHT := 3.2
const PANEL_SIZE := Vector2(4.0, 2.2)

@export var respawn_ticks: int = 300
## Fleches vers la droite du panneau (vu de face) ; faux : vers la gauche.
@export var arrows_right: bool = false

var knocked: bool = false
var _home: Transform3D
var _knocked_ticks: int = 0


func _init() -> void:
	name = "RoadsideSign"
	mass = 60.0
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1 << (HAZARD_LAYER - 1)
	collision_mask = 1 << (TruckSpec.LAYER_WORLD - 1)
	var body := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(PANEL_SIZE.x, POST_HEIGHT + PANEL_SIZE.y, 0.3)
	body.shape = box
	body.position = Vector3(0.0, (POST_HEIGHT + PANEL_SIZE.y) / 2.0, 0.0)
	add_child(body)
	# poteau et cadre sombres, panneau a chevrons lumineux (les deux faces)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.06, 0.065, 0.08)
	metal.metallic = 0.6
	metal.roughness = 0.4
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.25, POST_HEIGHT, 0.25)
	post.mesh = pm
	post.material_override = metal
	post.position = Vector3(0.0, POST_HEIGHT / 2.0, 0.0)
	add_child(post)
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(PANEL_SIZE.x + 0.2, PANEL_SIZE.y + 0.2, 0.12)
	frame.mesh = fm
	frame.material_override = metal
	frame.position = Vector3(0.0, POST_HEIGHT + PANEL_SIZE.y / 2.0, 0.0)
	add_child(frame)
	for side: float in [1.0, -1.0]:
		var face := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(PANEL_SIZE.y, PANEL_SIZE.x)   # tourne de 90 deg : chevrons horizontaux
		face.mesh = qm
		face.material_override = preload("res://tracks/materials/sign_arrows.tres")
		face.position = Vector3(0.0, POST_HEIGHT + PANEL_SIZE.y / 2.0, 0.07 * side)
		face.rotation = Vector3(0.0, 0.0 if side > 0.0 else PI, 0.0)
		face.name = "Face"
		add_child(face)
	var area := Area3D.new()
	area.name = "Trigger"
	area.collision_layer = 0
	area.collision_mask = 1 << (TruckSpec.LAYER_VEHICLE - 1)
	area.monitorable = false
	var acs := CollisionShape3D.new()
	var abox := BoxShape3D.new()
	abox.size = Vector3(PANEL_SIZE.x + 3.0, 6.0, 3.0)
	acs.shape = abox
	acs.position = Vector3(0.0, 3.0, 0.0)
	area.add_child(acs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _ready() -> void:
	_home = transform
	# fleches vers le virage : pointe a gauche ou a droite du panneau vu de face
	for c in get_children():
		if c.name.begins_with("Face"):
			var f := c as MeshInstance3D
			f.rotate_object_local(Vector3.BACK, PI / 2.0 if arrows_right else -PI / 2.0)


func _physics_process(_delta: float) -> void:
	if not knocked:
		return
	_knocked_ticks += 1
	if _knocked_ticks >= respawn_ticks:
		# retour a sa place, gele, pour le tour suivant
		knocked = false
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		transform = _home


func _on_body_entered(body: Node3D) -> void:
	var truck := body as Truck
	if truck == null or knocked:
		return
	knocked = true
	_knocked_ticks = 0
	hit.emit(truck)
	# pendant le signal (rincage des requetes physiques), on differe l'envol
	_yeet.call_deferred(truck.linear_velocity)


## En ligne, chez un client : le host l'a renverse (camion a `velocity`) ; deja
## renverse ici (notre camion) : rien.
func net_knock(velocity: Vector3) -> void:
	if knocked:
		return
	knocked = true
	_knocked_ticks = 0
	_yeet(velocity)


func _yeet(truck_velocity: Vector3) -> void:
	freeze = false
	var flat := truck_velocity * Vector3(1, 0, 1)
	linear_velocity = flat * 1.3 + Vector3.UP * 9.0
	var spin_axis := Vector3.UP.cross(flat).normalized() if flat.length() > 0.5 else Vector3.RIGHT
	angular_velocity = spin_axis * 9.0 + Vector3.UP * 4.0
