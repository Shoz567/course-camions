class_name ExplosiveBarrel
extends RigidBody3D

## Baril explosif pose sur la piste (style Mario Kart / arcade).
## Gele sur la route tant que personne n'y touche. Remasterise le 2026-10-02 :
## taille arcade (1,2 m de rayon, 2,5 m de haut : visible a 150 km/h sur 75 m
## de large), deux bandes de chevrons jaunes et noirs lumineux, et un
## gyrophare stroboscopique au sommet (dome, lumiere, halo qui garde une
## taille minimale a l'ecran : repere a plus de 250 m).
## Au contact d'un camion :
##   - Detonation avec flash lumineux / onde de choc et son d'explosion procedural ;
##   - Yeet physique leger sur le camion (impulsion de rebond vers le haut et l'exterieur) ;
##   - Le baril lui-meme est projete en l'air en tournoyant ;
##   - Respawn a sa position d'origine apres respawn_ticks.
## Degats : -15 PV au camion qui le fait sauter (PadEffects, TruckHealth).

signal exploded(truck: Truck)

const HAZARD_LAYER := 5
const BARREL_RADIUS := 1.2
const BARREL_HEIGHT := 2.5
## Gyrophare : periode du motif (double eclair) et intensites au maximum.
const STROBE_PERIOD_S := 0.9
const BEACON_ENERGY := 6.0
const BEACON_GLOW := 9.0
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
var _beacon_light: OmniLight3D
var _beacon_mat: StandardMaterial3D
var _halo_mat: ShaderMaterial
## Phase propre a chaque baril (ils ne clignotent pas tous ensemble).
var _strobe_phase: float = 0.0
static var _shared_stream: AudioStreamWAV


func _init() -> void:
	name = "ExplosiveBarrel"
	mass = 120.0
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

	# Fut principal en metal rouge industriel
	var body_mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = BARREL_RADIUS
	cm.bottom_radius = BARREL_RADIUS
	cm.height = BARREL_HEIGHT
	cm.radial_segments = 28
	body_mesh.mesh = cm
	var red_metal := StandardMaterial3D.new()
	red_metal.albedo_color = Color(0.88, 0.12, 0.06)
	red_metal.roughness = 0.35
	red_metal.metallic = 0.6
	red_metal.emission_enabled = true
	red_metal.emission = Color(0.9, 0.08, 0.02)
	red_metal.emission_energy_multiplier = 0.35
	body_mesh.material_override = red_metal
	body_mesh.position = Vector3(0.0, BARREL_HEIGHT / 2.0, 0.0)
	_barrel_model.add_child(body_mesh)

	# Cerclages noirs (haut, milieu, bas)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.06, 0.06, 0.08)
	ring_mat.roughness = 0.5
	ring_mat.metallic = 0.8
	for y_off: float in [0.3, BARREL_HEIGHT * 0.5, BARREL_HEIGHT - 0.3]:
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = BARREL_RADIUS + 0.04
		rm.bottom_radius = BARREL_RADIUS + 0.04
		rm.height = 0.16
		rm.radial_segments = 28
		ring.mesh = rm
		ring.material_override = ring_mat
		ring.position = Vector3(0.0, y_off, 0.0)
		_barrel_model.add_child(ring)

	# Deux bandes de chevrons jaunes et noirs lumineux
	var chevron_mat := ShaderMaterial.new()
	chevron_mat.shader = preload("res://tracks/materials/barrel_chevrons.gdshader")
	for y_band: float in [BARREL_HEIGHT * 0.3, BARREL_HEIGHT * 0.7]:
		var band := MeshInstance3D.new()
		band.name = "Chevrons"
		var bm := CylinderMesh.new()
		bm.top_radius = BARREL_RADIUS + 0.03
		bm.bottom_radius = BARREL_RADIUS + 0.03
		bm.height = 0.55
		bm.radial_segments = 28
		bm.cap_top = false
		bm.cap_bottom = false
		band.mesh = bm
		band.material_override = chevron_mat
		band.position = Vector3(0.0, y_band, 0.0)
		_barrel_model.add_child(band)

	# Gyrophare stroboscopique au sommet : socle, dome lumineux, lumiere et
	# halo (visible de tres loin, voir beacon_halo.gdshader)
	var base := MeshInstance3D.new()
	var basem := CylinderMesh.new()
	basem.top_radius = 0.42
	basem.bottom_radius = 0.5
	basem.height = 0.22
	base.mesh = basem
	base.material_override = ring_mat
	base.position = Vector3(0.0, BARREL_HEIGHT + 0.11, 0.0)
	_barrel_model.add_child(base)
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(1.0, 0.55, 0.05)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.5, 0.02)
	_beacon_mat.emission_energy_multiplier = BEACON_GLOW
	var dome := MeshInstance3D.new()
	dome.name = "BeaconDome"
	var dm := SphereMesh.new()
	dm.radius = 0.4
	dm.height = 0.8
	dm.is_hemisphere = true
	dome.mesh = dm
	dome.material_override = _beacon_mat
	dome.position = Vector3(0.0, BARREL_HEIGHT + 0.22, 0.0)
	_barrel_model.add_child(dome)
	_beacon_light = OmniLight3D.new()
	_beacon_light.name = "Beacon"
	_beacon_light.light_color = Color(1.0, 0.55, 0.08)
	_beacon_light.light_energy = BEACON_ENERGY
	_beacon_light.omni_range = 24.0
	_beacon_light.shadow_enabled = false
	_beacon_light.position = Vector3(0.0, BARREL_HEIGHT + 0.6, 0.0)
	_barrel_model.add_child(_beacon_light)
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = preload("res://tracks/materials/beacon_halo.gdshader")
	_halo_mat.set_shader_parameter("min_pixels", 40.0)
	var halo := MeshInstance3D.new()
	halo.name = "BeaconHalo"
	var hm := QuadMesh.new()
	hm.size = Vector2(3.0, 3.0)
	halo.mesh = hm
	halo.material_override = _halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# le halo grandit au loin (shader) : boite englobante large, jamais coupee
	halo.custom_aabb = AABB(Vector3(-40.0, -40.0, -40.0), Vector3(80.0, 80.0, 80.0))
	halo.position = Vector3(0.0, BARREL_HEIGHT + 0.5, 0.0)
	_barrel_model.add_child(halo)

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
	acyl.radius = BARREL_RADIUS + 1.0
	acyl.height = BARREL_HEIGHT + 1.5
	acs.shape = acyl
	acs.position = Vector3(0.0, BARREL_HEIGHT / 2.0, 0.0)
	area.add_child(acs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _ready() -> void:
	_home = transform
	_strobe_phase = fposmod(_home.origin.x * 0.37 + _home.origin.z * 0.11, STROBE_PERIOD_S)


## Intensite du gyrophare (0 .. 1) a l'instant t (s) : double eclair bref,
## puis une lueur residuelle.
static func strobe(t: float) -> float:
	var u := fposmod(t, STROBE_PERIOD_S)
	if u < 0.07 or (u > 0.16 and u < 0.23):
		return 1.0
	return 0.3


func _process(_delta: float) -> void:
	var k := strobe(Time.get_ticks_msec() / 1000.0 + _strobe_phase)
	if exploded_state:
		k = 0.0
	_beacon_light.light_energy = BEACON_ENERGY * k
	_beacon_mat.emission_energy_multiplier = BEACON_GLOW * maxf(k, 0.25)
	_halo_mat.set_shader_parameter("flash", k)


func _physics_process(_delta: float) -> void:
	if not exploded_state:
		return
	_exploded_ticks += 1

	# Animation d'expansion et d'attenuation de l'onde de choc
	if _exploded_ticks <= 20:
		var u := float(_exploded_ticks) / 20.0
		_blast_fx.scale = Vector3.ONE * lerpf(1.0, 7.5, u)
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
	_blast_fx.scale = Vector3.ONE * 1.0
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
