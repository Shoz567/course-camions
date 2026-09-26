extends Node3D

## Bac a sable de conduite en direct (developpement, pas un livrable de jeu).
##
## Branche la premiere manette connectee (XInput, DualShock, DualSense) et le
## clavier sur le camion. Arene fermee par des murs de 0,3 m (METRICS.md §4),
## un tremplin, des camions gares a percuter.
##
##   RT / R2 ou Z (W)   gaz          stick gauche ou Q D (A D)   direction
##   LT / L2 ou S       frein, puis marche arriere a l'arret
##   Y / Triangle ou R  reset : camion remis droit sur place
##
## La camera ici est un simple suivi de debug : la vraie camera de poursuite est
## la tache 2.1. Ce script joue le role du gameplay (source d'input, reset) :
## le camion, lui, ne lit jamais Input.*.

const ARENA_HALF := 150.0
const WALL_THICKNESS := 0.3
const WALL_HEIGHT := 1.5

@onready var _truck: Truck = $Truck
@onready var _pad: DeviceInputSource = $PadSource
@onready var _keyboard: KeyboardInputSource = $KeyboardSource
@onready var _camera: Camera3D = $Camera3D
@onready var _hud: Label = $Hud/Label

var _merged: InputFrame = InputFrame.new()


func _ready() -> void:
	_pick_pad()
	Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void: _pick_pad())
	_build_arena()


## Prend la premiere manette connectee, si la source n'en suit pas deja une.
func _pick_pad() -> void:
	var pads := Input.get_connected_joypads()
	if pads.has(_pad.device_id):
		_pad.connected = true
		return
	if not pads.is_empty():
		_pad.device_id = pads[0]
		_pad.connected = true


func _physics_process(_delta: float) -> void:
	var tick := Engine.get_physics_frames()
	var k := _keyboard.poll(tick)
	var p := _pad.poll(tick)
	# Fusion manette + clavier : la commande la plus franche l'emporte.
	_merged.tick = tick
	_merged.steer = p.steer if absf(p.steer) > absf(k.steer) else k.steer
	_merged.throttle = maxf(p.throttle, k.throttle)
	_merged.brake = maxf(p.brake, k.brake)
	_merged.handbrake = p.handbrake or k.handbrake
	_merged.boost = p.boost or k.boost
	_merged.reset = p.reset or k.reset
	_truck.set_input(_merged)
	if _merged.reset:
		# remis droit sur place, cap conserve, 1 m au-dessus du sol
		var pos := _truck.global_position
		var yaw := _truck.global_rotation.y
		_truck.reset_to(Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, maxf(pos.y, 0.0) + 1.0, pos.z)))


func _process(delta: float) -> void:
	var xf := _truck.global_transform
	# derriere le camion, cap horizontal seulement : la camera ne roule pas avec lui
	var back := xf.basis.z
	back.y = 0.0
	back = back.normalized() if back.length_squared() > 1e-4 else Vector3.BACK
	var want := xf.origin + back * 14.0 + Vector3.UP * 5.5
	_camera.global_position = _camera.global_position.lerp(want, clampf(delta * 5.0, 0.0, 1.0))
	_camera.look_at(xf.origin + Vector3.UP * 1.5)

	var f := _truck.get_input()
	var pad_name := "aucune (clavier : ZQSD / fleches, R reset)"
	if _pad.connected:
		pad_name = "%d — %s" % [_pad.device_id, Input.get_joy_name(_pad.device_id)]
	_hud.text = "\n".join([
		"Manette : %s" % pad_name,
		"%6.1f km/h   roues au sol %d   braquage %+.1f deg" % [
			_truck.get_speed_kmh(), _truck.wheels_on_ground(), _truck.get_steer_deg()],
		"steer     %+.2f  %s" % [f.steer, _bar(f.steer)],
		"throttle   %.2f  %s" % [f.throttle, _bar(f.throttle)],
		"brake      %.2f  %s" % [f.brake, _bar(f.brake)],
		"Y / Triangle / R : reset",
	])


func _bar(v: float) -> String:
	var n := roundi(absf(v) * 20.0)
	return ("<" if v < 0.0 else "") + "|".repeat(n)


# --- decor -------------------------------------------------------------------------

func _build_arena() -> void:
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.85, 0.85, 0.9)
	var span := ARENA_HALF * 2.0
	for side in 4:
		var along_x := side < 2
		var size := Vector3(span, WALL_HEIGHT, WALL_THICKNESS) if along_x \
				else Vector3(WALL_THICKNESS, WALL_HEIGHT, span)
		var sign_ := -1.0 if side % 2 == 0 else 1.0
		var pos := Vector3(0.0, WALL_HEIGHT / 2.0, sign_ * ARENA_HALF) if along_x \
				else Vector3(sign_ * ARENA_HALF, WALL_HEIGHT / 2.0, 0.0)
		_add_box(size, Transform3D(Basis.IDENTITY, pos), wall_mat)

	# tremplin de 12 deg, 20 m de long, sommet a ~4 m
	var ramp_mat := StandardMaterial3D.new()
	ramp_mat.albedo_color = Color(0.9, 0.55, 0.15)
	var angle := deg_to_rad(12.0)
	var ramp_len := 20.0
	var ramp_basis := Basis(Vector3.RIGHT, angle)
	var center := Vector3(0.0, sin(angle) * ramp_len / 2.0 - 0.5, -60.0)
	_add_box(Vector3(8.0, 1.0, ramp_len), Transform3D(ramp_basis, center), ramp_mat)

	# obstacles a percuter : camions gares, et plots de 1 m
	for i in 3:
		var parked := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
		parked.position = Vector3(-25.0 + i * 5.0, 0.0, -30.0)
		parked.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		add_child(parked)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.2, 0.6, 0.9)
	for i in 12:
		var x := -8.0 if i % 2 == 0 else 8.0
		_add_box(Vector3(1.0, 1.0, 1.0), Transform3D(Basis.IDENTITY, Vector3(x + 30.0, 0.5, -10.0 - i * 10.0)), post_mat)


func _add_box(size: Vector3, xf: Transform3D, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_mask = 0
	body.transform = xf
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	body.add_child(mi)
	add_child(body)
