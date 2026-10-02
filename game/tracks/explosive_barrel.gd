class_name ExplosiveBarrel
extends RigidBody3D

## Baril explosif pose sur la piste (style Mario Kart / arcade).
## Gele sur la route tant que personne n'y touche.
## Au contact d'un camion :
##   - Detonation avec flash lumineux / onde de choc et son d'explosion procedural ;
##   - Yeet physique leger sur le camion (impulsion de rebond vers le haut et l'exterieur) ;
##   - Le baril lui-meme est projete en l'air en tournoyant ;
##   - Respawn a sa position d'origine apres respawn_ticks.
## (Les degats de PV seront ajoutes lors du lot PV / combat).

signal exploded(truck: Truck)

const HAZARD_LAYER := 5
const BARREL_RADIUS := 0.65
const BARREL_HEIGHT := 1.35
const AUDIO_RATE := 22050
const AUDIO_DURATION_S := 0.55

@export var respawn_ticks: int = 360
@export var yeet_up_speed: float = 3.2
@export var yeet_out_speed: float = 4.2

var exploded_state: bool = false
var _home: Transform3D
var _exploded_ticks: int = 0
var _barrel_model: Node3D
var _blast_fx: MeshInstance3D
var _blast_mat: StandardMaterial3D
var _blast_light: OmniLight3D
var _audio_player: AudioStreamPlayer3D
static var _shared_stream: AudioStreamWAV


func _init() -> void:
	name = "ExplosiveBarrel"
	mass = 45.0
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1 << (HAZARD_LAYER - 1)
	collision_mask = 1 << (TruckSpec.LAYER_WORLD - 1)

	# Forme physique du baril
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = BARREL_RADIUS
	cyl.height = BARREL_HEIGHT
	cs.shape = cyl
	cs.position = Vector3(0.0, BARREL_HEIGHT / 2.0, 0.0)
	add_child(cs)

	# Modele visuel du baril
	_barrel_model = Node3D.new()
	_barrel_model.name = "Model"
	add_child(_barrel_model)

	# Fût principal en metal rouge industriel
	var body_mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = BARREL_RADIUS
	cm.bottom_radius = BARREL_RADIUS
	cm.height = BARREL_HEIGHT
	cm.radial_segments = 20
	body_mesh.mesh = cm
	var red_metal := StandardMaterial3D.new()
	red_metal.albedo_color = Color(0.88, 0.14, 0.08)
	red_metal.roughness = 0.35
	red_metal.metallic = 0.65
	body_mesh.material_override = red_metal
	body_mesh.position = Vector3(0.0, BARREL_HEIGHT / 2.0, 0.0)
	_barrel_model.add_child(body_mesh)

	# Cerclages noirs (haut et bas)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.08, 0.08, 0.1)
	ring_mat.roughness = 0.5
	ring_mat.metallic = 0.8
	for y_off: float in [0.22, BARREL_HEIGHT - 0.22]:
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = BARREL_RADIUS + 0.02
		rm.bottom_radius = BARREL_RADIUS + 0.02
		rm.height = 0.12
		rm.radial_segments = 20
		ring.mesh = rm
		ring.material_override = ring_mat
		ring.position = Vector3(0.0, y_off, 0.0)
		_barrel_model.add_child(ring)

	# Bande centrale jaune d'avertissement emissive
	var warn_ring := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = BARREL_RADIUS + 0.015
	wm.bottom_radius = BARREL_RADIUS + 0.015
	wm.height = 0.28
	wm.radial_segments = 20
	warn_ring.mesh = wm
	var warn_mat := StandardMaterial3D.new()
	warn_mat.albedo_color = Color(1.0, 0.82, 0.1)
	warn_mat.emission_enabled = true
	warn_mat.emission = Color(1.0, 0.72, 0.05)
	warn_mat.emission_energy_multiplier = 1.6
	warn_ring.material_override = warn_mat
	warn_ring.position = Vector3(0.0, BARREL_HEIGHT / 2.0, 0.0)
	_barrel_model.add_child(warn_ring)

	# Effet visuel d'explosion (onde de choc spherique)
	_blast_fx = MeshInstance3D.new()
	_blast_fx.name = "BlastFX"
	var blast_sphere := SphereMesh.new()
	blast_sphere.radius = 1.0
	blast_sphere.height = 2.0
	_blast_fx.mesh = blast_sphere
	_blast_mat = StandardMaterial3D.new()
	_blast_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blast_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blast_mat.albedo_color = Color(1.0, 0.55, 0.1, 0.85)
	_blast_fx.material_override = _blast_mat
	_blast_fx.position = Vector3(0.0, BARREL_HEIGHT / 2.0, 0.0)
	_blast_fx.visible = false
	add_child(_blast_fx)

	# Flash lumineux d'explosion
	_blast_light = OmniLight3D.new()
	_blast_light.name = "BlastLight"
	_blast_light.light_color = Color(1.0, 0.65, 0.2)
	_blast_light.light_energy = 5.0
	_blast_light.omni_range = 15.0
	_blast_light.position = Vector3(0.0, BARREL_HEIGHT / 2.0, 0.0)
	_blast_light.visible = false
	add_child(_blast_light)

	# Audio d'explosion
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.name = "ExplosionAudio"
	_audio_player.unit_size = 25.0
	_audio_player.max_distance = 180.0
	if _shared_stream == null:
		_shared_stream = _build_explosion_stream()
	_audio_player.stream = _shared_stream
	add_child(_audio_player)

	# Zone de declenchement pour capter l'arrivee d'un camion
	var area := Area3D.new()
	area.name = "Trigger"
	area.collision_layer = 0
	area.collision_mask = 1 << (TruckSpec.LAYER_VEHICLE - 1)
	area.monitorable = false
	var acs := CollisionShape3D.new()
	var acyl := CylinderShape3D.new()
	acyl.radius = BARREL_RADIUS + 0.85
	acyl.height = BARREL_HEIGHT + 1.2
	acs.shape = acyl
	acs.position = Vector3(0.0, BARREL_HEIGHT / 2.0, 0.0)
	area.add_child(acs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _ready() -> void:
	_home = transform


func _physics_process(_delta: float) -> void:
	if not exploded_state:
		return
	_exploded_ticks += 1

	# Animation d'expansion et d'attenuation de l'onde de choc
	if _exploded_ticks <= 20:
		var u := float(_exploded_ticks) / 20.0
		_blast_fx.scale = Vector3.ONE * lerpf(0.6, 4.6, u)
		_blast_light.light_energy = lerpf(5.0, 0.0, u)
		if _blast_mat != null:
			_blast_mat.albedo_color.a = (1.0 - u) * 0.85
	elif _blast_fx.visible:
		_blast_fx.visible = false
		_blast_light.visible = false

	if _exploded_ticks >= respawn_ticks:
		# Reapparition a l'emplacement d'origine
		exploded_state = false
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		transform = _home
		_barrel_model.visible = true
		_blast_fx.visible = false
		_blast_light.visible = false


func _on_body_entered(body: Node3D) -> void:
	var truck := body as Truck
	if truck == null or exploded_state:
		return
	explode(truck)


## Declenche la detonation du baril.
func explode(truck: Truck) -> void:
	if exploded_state:
		return
	exploded_state = true
	_exploded_ticks = 0
	exploded.emit(truck)

	# Yeet physique leger sur le camion (propulsion vers le haut + ecartement)
	var to_truck := truck.global_position - global_position
	to_truck.y = 0.0
	var shove_dir := to_truck.normalized() if to_truck.length() > 0.1 else -truck.global_transform.basis.z
	var impulse := (shove_dir * yeet_out_speed + Vector3.UP * yeet_up_speed) * truck.mass
	truck.apply_central_impulse(impulse)

	# Ejection physique du baril
	freeze = false
	linear_velocity = Vector3.UP * 11.5 - shove_dir * 4.0
	angular_velocity = Vector3(randf_range(-9.0, 9.0), randf_range(-5.0, 5.0), randf_range(-9.0, 9.0))

	# Flash visuel
	_blast_fx.visible = true
	_blast_fx.scale = Vector3.ONE * 0.6
	_blast_light.visible = true
	_blast_light.light_energy = 5.0
	if _blast_mat != null:
		_blast_mat.albedo_color.a = 0.85

	# Son d'explosion
	if DisplayServer.get_name() != "headless" and _audio_player != null:
		_audio_player.play()


static func _build_explosion_stream() -> AudioStreamWAV:
	var n := roundi(AUDIO_RATE * AUDIO_DURATION_S)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lcg := 42
	var low := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / AUDIO_RATE
		var u := t / AUDIO_DURATION_S
		# Attaque fulgurante (4 ms), decroissance avec rumble
		var env := minf(1.0, t / 0.004) * pow(1.0 - u, 2.2)
		# Chute de frequence sub-bass : 110 Hz -> 35 Hz
		phase += lerpf(110.0, 35.0, u) / AUDIO_RATE
		var bass := sin(TAU * phase) * 0.55
		# Bruit blanc filtre passe-bas pour l'impact sourd
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		var noise := float(lcg) / 1073741824.0 - 1.0
		var cutoff := lerpf(0.5, 0.08, u)
		low += (noise - low) * cutoff
		var v := (bass + low * 0.8) * env
		data.encode_s16(i * 2, clampi(roundi(v * 0.7 * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = AUDIO_RATE
	wav.stereo = false
	wav.data = data
	return wav
