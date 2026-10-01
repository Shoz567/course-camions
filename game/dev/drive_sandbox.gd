extends Node3D

## Bac a sable de conduite en direct (developpement, pas un livrable de jeu).
##
## Branche la premiere manette connectee (XInput, DualShock, DualSense) et le
## clavier sur le camion. Arene fermee par des murs de 0,3 m (METRICS.md §4),
## un tremplin, des camions gares a percuter.
##
##   RT / R2 ou Z (W)   gaz          stick gauche ou Q D (A D)   direction
##   LT / L2 ou S       frein, puis marche arriere a l'arret
##   A / Croix ou Espace frein a main : drift (contre-braquer pour le tenir)
##   Y / Triangle ou R  reset : camion remis droit sur place
##   En l'air : stick gauche = lacet ; l'assiette se corrige seule
##   F1 traces de debug   F2 suspension   F3 forces de pneu   F4 centre de masse
##
## Ce script joue le role du gameplay (source d'input, reset) : le camion, lui,
## ne lit jamais Input.*. La piste de test est dev/track_drive.tscn (make run).

const ARENA_HALF := 150.0
const WALL_THICKNESS := 0.3
const WALL_HEIGHT := 1.5

@onready var _truck: Truck = $Truck
@onready var _input: LocalInputSource = $LocalInput
@onready var _camera: ChaseCamera = $ChaseCamera
@onready var _hud: Label = $Hud/Label


func _ready() -> void:
	_build_arena()
	_camera.snap()


## Bascules des traces DebugDraw (outil de dev, pas une commande de conduite).
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F1:
			DebugDraw.enabled = not DebugDraw.enabled
		KEY_F2:
			_toggle_channel(DebugDraw.CH_SUSPENSION)
		KEY_F3:
			_toggle_channel(DebugDraw.CH_FORCES)
		KEY_F4:
			_toggle_channel(DebugDraw.CH_COM)


func _toggle_channel(ch: StringName) -> void:
	DebugDraw.set_channel_enabled(ch, not DebugDraw.is_channel_enabled(ch))


func _physics_process(_delta: float) -> void:
	var f := _input.poll(Engine.get_physics_frames())
	_truck.set_input(f)
	if f.reset:
		# remis droit sur place, cap conserve, 1 m au-dessus du sol
		var pos := _truck.global_position
		var yaw := _truck.global_rotation.y
		_truck.reset_to(Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, maxf(pos.y, 0.0) + 1.0, pos.z)))
		_camera.snap()


func _process(_delta: float) -> void:
	var xf := _truck.global_transform
	var f := _truck.get_input()
	var v := _truck.linear_velocity
	var slip := 0.0
	var v_fwd := v.dot(-xf.basis.z)
	if v_fwd > 1.0:
		slip = rad_to_deg(atan2(v.dot(xf.basis.x), v_fwd))
	var state := "au sol" if _truck.wheels_on_ground() > 0 else "EN L'AIR"
	var pad_name := _input.pad_name()
	if pad_name == "":
		pad_name = "aucune (clavier : ZQSD / fleches, Espace, R)"
	_hud.text = "\n".join([
		"Manette : %s" % pad_name,
		"%6.1f km/h   roues au sol %d   braquage %+.1f deg" % [
			_truck.get_speed_kmh(), _truck.wheels_on_ground(), _truck.get_steer_deg()],
		"steer     %+.2f  %s" % [f.steer, _bar(f.steer)],
		"throttle   %.2f  %s" % [f.throttle, _bar(f.throttle)],
		"brake      %.2f  %s" % [f.brake, _bar(f.brake)],
		"frein a main %3d %%   derive %+5.1f deg   %s" % [
			roundi(_truck.get_handbrake_blend() * 100.0), slip, state],
		"A/Croix : frein a main   Y/Triangle : reset   F1-F4 : traces (%s)"
			% ("actifs" if DebugDraw.enabled else "coupes"),
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
		# alignes dans le sens de la marche : leurs semi-remorques (13 m) ne se
		# chevauchent pas
		parked.position = Vector3(-30.0 + i * 6.0, 0.0, -30.0)
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
