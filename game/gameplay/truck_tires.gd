class_name TruckTires
extends Node3D

## Pneus du tracteur (enfant « Tires » du camion), 2026-10-07 : « quand un pneu
## est touche, il eclate, on perd en adherence, en maniabilite ».
##
## Un choc de cote (mur, autre camion, remorque larguee, epave) a la hauteur
## d'une roue et assez violent fait eclater son pneu (Truck.burst_tire) :
##   - la normale du choc est surtout laterale (repere du camion) : un choc
##     frontal prend le pare-chocs, pas les roues, et un frottement le long
##     d'un mur n'est pas assez violent ;
##   - le point touche est devant ou derriere l'essieu d'au plus AXLE_REACH_M
##     (un camion pris de cote signale le coin de l'autre, a ~1,4 m de son
##     axe) ; contre un autre corps, sous MAX_HIT_HEIGHT_M (pas la cabine, ni une
##     remorque, plus haute) ; un mur, lui, descend jusqu'au sol ;
##   - la vitesse vers l'obstacle depasse BURST_SPEED_MS (~25 km/h de plein
##     cote, ou un mur pris a ~15 deg a 100 km/h).
## Remorque (un cote de son train de roues, Truck.TRAILER_LEFT / RIGHT) : un
## choc de cote sur l'arriere de sa caisse (TRAILER_REACH_M autour du train de
## roues), a toute hauteur (la caisse est au-dessus des roues), meme seuil de
## vitesse ; elle se remet a neuf avec la remorque suivante.
## Un pneu encaisse avant de ceder (2026-10-08 : « les pneus eclatent trop
## facilement, il faut plusieurs coups ») : chaque choc qui le vise l'use de
## 1 (au seuil) a MAX_HIT_WEAR (choc violent), il eclate a HITS_TO_BURST -
## trois coups, deux au moins. L'usure repart a zero avec des pneus neufs
## (reapparition ; remorque larguee pour les siens).
## L'eclatement : detonation, bouffee de fumee, la gomme part en morceaux. La roue
## creve reste sur sa jante jusqu'a la reapparition du camion (pneus neufs) ;
## tant qu'elle roule au sol, la jante frotte la route et crache des
## etincelles (rim_sparking).
## Deterministe : aucun tirage aleatoire (CLAUDE.md §7).

## Vitesse vers l'obstacle (m/s) a partir de laquelle le pneu touche eclate.
const BURST_SPEED_MS := 7.0
## Part laterale minimale de la normale du choc (repere du camion).
const SIDE_MIN := 0.45
## Etendue d'une roue le long du camion, de part et d'autre de son essieu (m) :
## l'avant du pare-chocs et l'arriere du chassis comptent, pas le milieu.
const AXLE_REACH_M := 1.7
## Au-dessus (repere du camion, m) : cabine ou remorque, pas une roue.
const MAX_HIT_HEIGHT_M := 2.3
## Etendue du train de roues de la remorque, de part et d'autre de son centre
## (m) : ses essieux s'etalent sur 2,8 m au plus, plus le flanc des pneus.
const TRAILER_REACH_M := 2.6
## Usure a laquelle un pneu eclate (coups « au seuil »).
const HITS_TO_BURST := 3.0
## Usure d'un seul choc, au plus : il en faut toujours deux.
const MAX_HIT_WEAR := 1.5
## Vitesse (m/s) a partir de laquelle une jante au sol crache des etincelles.
const SPARK_SPEED_MS := 2.0
## Rayon de la jante, en fraction du rayon du pneu (modeles du tracteur et
## catalogue des remorques : fut a 0,6 r).
const RIM_RATIO := 0.6
## Morceaux de gomme projetes par un pneu qui explose, et rayon (m) ou ils
## partent (bande de roulement d'un pneu du tracteur ; remorque : 70 %).
const BURST_PIECES := 10
const TIRE_PIECE_RADIUS_M := 0.7

static var _bang_stream: AudioStreamWAV
static var _rubber: StandardMaterial3D

var _truck: Truck
var _bang: AudioStreamPlayer3D
## Usure de chaque pneu (ordre de Truck : FL, FR, RL, RR, remorque G, D).
var _wear: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0])
## Jante qui frotte la route ce tick, par roue (etat logique, meme sans rendu).
var _sparking: PackedByteArray = PackedByteArray([0, 0, 0, 0, 0, 0])
## Gerbes d'etincelles par roue (null : sans rendu, ou pas encore creee).
var _spark_fx: Array[GPUParticles3D] = [null, null, null, null, null, null]


## Roue (ordre FL, FR, RL, RR) dont le pneu eclate sous ce choc, ou -1.
## `point` et `normal` (tournee vers le camion) en monde, `speed_ms` : vitesse
## vers l'obstacle. Un mur descend jusqu'au sol : sa hauteur de contact ne
## compte pas (il touche souvent le haut de la cabine en premier), max_height
## INF.
static func wheel_hit(truck_xf: Transform3D, point: Vector3, normal: Vector3, speed_ms: float,
		max_height: float = MAX_HIT_HEIGHT_M) -> int:
	if speed_ms < BURST_SPEED_MS:
		return -1
	var n := (truck_xf.basis.inverse() * normal).normalized()
	if absf(n.x) < SIDE_MIN:
		return -1
	var p := truck_xf.affine_inverse() * point
	if p.y > max_height:
		return -1
	# normale vers le camion : choc venu de la gauche -> normale vers +X
	var left := n.x > 0.0
	for i in 4:
		var a := TruckSpec.ANCHORS[i]
		if (a.x < 0.0) == left and absf(p.z - a.z) <= AXLE_REACH_M:
			return i
	return -1


## Cote du train de roues de la remorque (Truck.TRAILER_LEFT, TRAILER_RIGHT)
## dont les pneus eclatent sous ce choc sur sa caisse, ou -1. `box_xf` : pose
## monde de la caisse (centre, articulation comprise), `box_size` sa taille ;
## le reste comme wheel_hit. La hauteur ne compte pas : la caisse est tout
## entiere au-dessus des roues.
static func trailer_hit(box_xf: Transform3D, box_size: Vector3, point: Vector3, normal: Vector3,
		speed_ms: float) -> int:
	if speed_ms < BURST_SPEED_MS:
		return -1
	var n := (box_xf.basis.inverse() * normal).normalized()
	if absf(n.x) < SIDE_MIN:
		return -1
	var p := box_xf.affine_inverse() * point
	var bogie_z := box_size.z / 2.0 - Truck.TRAILER_BOGIE_FROM_REAR_M
	if absf(p.z - bogie_z) > TRAILER_REACH_M:
		return -1
	return Truck.TRAILER_LEFT if n.x > 0.0 else Truck.TRAILER_RIGHT


## En ligne, chez un client (NetRace) : aucun pneu n'eclate ici ; le host
## fait foi (Truck.burst_tire recu), les effets (eclatement, jantes) suivent.
var net_mirror: bool = false


func _ready() -> void:
	_truck = get_parent() as Truck
	if _truck == null:
		return
	_truck.wall_impact_at.connect(_on_impact.bind(INF))
	_truck.body_impact.connect(_on_impact.bind(MAX_HIT_HEIGHT_M))
	_truck.tire_burst.connect(_on_tire_burst)
	_truck.trailer_detached.connect(_on_trailer_detached)
	var health := TruckHealth.of(_truck)
	if health != null:
		health.respawned.connect(_on_respawned)
	if DisplayServer.get_name() != "headless":
		if _bang_stream == null:
			_bang_stream = _build_bang_stream()
		_bang = AudioStreamPlayer3D.new()
		_bang.name = "Bang"
		_bang.stream = _bang_stream
		_bang.unit_size = 18.0
		_bang.max_distance = 160.0
		add_child(_bang)
		for w in _spark_fx.size():
			_spark_fx[w] = _make_rim_sparks()
			if w >= Truck.TRAILER_LEFT:
				# tout le train de roues frotte (jusqu'a 2,8 m d'essieux)
				FxKit.spark_param(_spark_fx[w], &"box_extents", Vector3(0.1, 0.02, 1.3))
				_spark_fx[w].amount = 160
			add_child(_spark_fx[w])


func _on_impact(speed: float, on_trailer: bool, point: Vector3, normal: Vector3, max_height: float) -> void:
	if _truck.is_wrecked():
		return
	var i := -1
	if on_trailer:
		var box_xf := _truck.global_transform \
				* Truck.trailer_local_transform(_truck.get_trailer_angle(), _truck.trailer_box_center)
		i = trailer_hit(box_xf, _truck.trailer_box_size, point, normal, speed)
	else:
		i = wheel_hit(_truck.global_transform, point, normal, speed, max_height)
	if i >= 0:
		take_hit(i, speed)


## Un choc a `speed_ms` sur le pneu `wheel` : il s'use, et eclate s'il a
## assez encaisse. Vrai s'il vient d'eclater.
func take_hit(wheel: int, speed_ms: float) -> bool:
	if net_mirror:
		return false   # en ligne, chez un client : les crevaisons viennent du host
	if wheel < 0 or wheel >= _wear.size() or _truck.is_tire_burst(wheel):
		return false
	_wear[wheel] += clampf(speed_ms / BURST_SPEED_MS, 1.0, MAX_HIT_WEAR)
	if _wear[wheel] < HITS_TO_BURST - 1e-4:
		return false
	return _truck.burst_tire(wheel)


## Usure du pneu `wheel` (0 : neuf ; HITS_TO_BURST : eclate).
func wear(wheel: int) -> float:
	return _wear[wheel]


## Vrai si la jante de la roue `wheel` frotte la route (pneu eclate, au sol, en
## mouvement) : etincelles.
func rim_sparking(wheel: int) -> bool:
	return _sparking[wheel] != 0


func _on_respawned() -> void:
	_wear.fill(0.0)
	_truck.repair_tires()


func _on_trailer_detached() -> void:
	_wear[Truck.TRAILER_LEFT] = 0.0
	_wear[Truck.TRAILER_RIGHT] = 0.0


## Etincelles des jantes : apres les forces du camion (enfant : meme tick).
func _physics_process(_delta: float) -> void:
	if _truck == null:
		return
	var speed := _truck.linear_velocity.length()
	for w in _wear.size():
		var on := false
		if _truck.is_tire_burst(w) and speed >= SPARK_SPEED_MS and not _truck.is_wrecked():
			if w < 4:
				on = _truck.get_probe(w).in_contact
			else:
				on = not _truck.is_trailer_detached() and _truck.wheels_on_ground() >= 2
		_sparking[w] = 1 if on else 0
		var fx := _spark_fx[w]
		if fx == null:
			continue
		if on:
			# au ras du sol sous la jante, dans le repere du camion (le noeud
			# suit le camion interpole) ; la gerbe part vers l'arriere, plus
			# vite et plus loin avec la vitesse
			fx.position = _contact_local(w)
			var back := _truck.global_basis.inverse() * -_truck.linear_velocity.normalized()
			FxKit.spark_param(fx, &"direction", (back + Vector3.UP * 0.35).normalized())
			var k := clampf(speed / 25.0, 0.0, 1.0)
			FxKit.spark_param(fx, &"speed_min", lerpf(2.0, 6.0, k))
			FxKit.spark_param(fx, &"speed_max", lerpf(5.0, 13.0, k))
			fx.amount_ratio = lerpf(0.4, 1.0, k) * FxKit.density()
		if fx.emitting != on:
			fx.emitting = on


## Point de contact jante / route de la roue `wheel`, repere du camion.
func _contact_local(wheel: int) -> Vector3:
	if wheel >= Truck.TRAILER_LEFT:
		return _truck.trailer_wheel_local(wheel) + Vector3(0.0, 0.05, 0.0)
	var p := _truck.get_probe(wheel)
	var at := _truck.global_transform.affine_inverse() * p.contact_point
	# cote exterieur de la roue, la ou la jante se voit
	return at + Vector3(signf(TruckSpec.ANCHORS[wheel].x) * 0.15, 0.05, 0.0)


## Gerbe d'etincelles continue (eteinte) : traits jaune-orange etires sur
## leur vitesse, qui fusent vers l'arriere en gerbe de coq, ricochent sur la
## route (le sol est sous l'emetteur, au ras de la jante) et refroidissent.
static func _make_rim_sparks() -> GPUParticles3D:
	var p := FxKit.make_sparks(110, 0.55, {
		"spread": 0.45, "inherit": 0.3, "box_extents": Vector3(0.1, 0.02, 0.12),
		"gravity": 16.0, "drag": 0.9, "bounce": 0.4, "floor_below": 0.05, "life_min": 0.35,
		"stretch": 0.035, "max_len": 0.5, "width": 0.014, "heat": 6.0})
	p.name = "RimSparks"
	p.randomness = 0.5
	return p


## Centre de la roue `wheel` (monde) : sous son ancrage, au moyeu ; remorque :
## pneu exterieur de son train de roues.
func wheel_center(wheel: int) -> Vector3:
	if wheel >= Truck.TRAILER_LEFT:
		return _truck.global_transform * (_truck.trailer_wheel_local(wheel) + Vector3(0.0, 0.5, 0.0))
	var p := _truck.get_probe(wheel)
	return p.global_position - _truck.global_basis.y * p.hub_distance


## Effets apres le pas physique (l'eclatement arrive pendant un contact).
func _on_tire_burst(wheel: int) -> void:
	_burst_fx.call_deferred(wheel)


func _burst_fx(wheel: int) -> void:
	if not is_inside_tree():
		return
	var at := wheel_center(wheel)
	var left := wheel == Truck.TRAILER_LEFT or (wheel < 4 and TruckSpec.ANCHORS[wheel].x < 0.0)
	var side := _truck.global_basis.x * (-1.0 if left else 1.0)
	var world := _truck.get_parent()
	if world == null:
		return
	# la gomme explose (2026-10-08 : « elle part en morceaux », plus rien ne
	# reste sur la roue) : morceaux de bande de roulement tout autour du
	# pneu, chacun chasse dans le sens de son rayon et vers l'exterieur, plus
	# des lanieres de flanc (deterministe)
	if _rubber == null:
		_rubber = StandardMaterial3D.new()
		_rubber.albedo_color = Color(0.035, 0.035, 0.037)
		_rubber.roughness = 0.9
	var b := _truck.global_basis
	var r := TIRE_PIECE_RADIUS_M if wheel < 4 else TIRE_PIECE_RADIUS_M * 0.7
	var salt := float(Engine.get_physics_frames()) * 0.731
	for k in BURST_PIECES:
		var h := fposmod(sin(float(k * 7 + wheel) * 12.9898 + salt) * 43758.55, 1.0)
		var h2 := fposmod(sin(float(k * 3 + wheel) * 78.233 + salt) * 24634.63, 1.0)
		var a := (float(k) + h * 0.6) / float(BURST_PIECES) * TAU
		var radial := b.y * cos(a) + b.z * sin(a)
		# le sol renvoie les morceaux du bas : vers le haut
		if radial.dot(Vector3.UP) < -0.3:
			radial = (radial * 0.3 + Vector3.UP).normalized()
		var dir := (radial + side * lerpf(0.4, 1.1, h2) + Vector3.UP * 0.3).normalized()
		var size := Vector3(lerpf(0.12, 0.3, h), lerpf(0.04, 0.07, h2), lerpf(0.2, 0.45, 1.0 - h))
		# remorque : les pneus de ce cote, sur tout le train de roues
		var along := b.z * (h2 - 0.5) * 2.6 if wheel >= Truck.TRAILER_LEFT else Vector3.ZERO
		Debris.shard(world, at + (b.y * cos(a) + b.z * sin(a)) * r + side * 0.1 + along, size, _rubber,
			_truck.linear_velocity * 0.9 + dir * lerpf(5.0, 10.0, h2))
	# bouffee de poussiere et de caoutchouc
	var puff := FxKit.make_smoke(16, 1.3, 1.4)
	puff.name = "TirePuff"
	var pm := puff.process_material as ParticleProcessMaterial
	pm.color = Color(0.55, 0.53, 0.5, 0.75)
	pm.direction = side + Vector3.UP * 0.4
	pm.spread = 45.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 6.0
	pm.inherit_velocity_ratio = 0.7
	FxKit.fire_once(world, puff, at, 0.9)
	# la jante mord la route : eclat d'etincelles
	FxKit.fire_once(world, FxKit.make_sparks(40, 0.6, {
		"direction": side + Vector3.UP * 0.5, "spread": 1.0, "speed_min": 4.0, "speed_max": 10.0,
		"inherit": 0.85, "box_extents": Vector3(0.2, 0.05, 0.3), "floor_below": 0.6,
		"life_min": 0.3, "stretch": 0.03, "max_len": 0.4, "width": 0.016, "heat": 6.0}), at)
	if _bang != null:
		_bang.global_position = at
		_bang.play()


## Detonation : claquement de bruit blanc tres bref sur un coup sourd, puis le
## souffle de l'air qui s'echappe. Genere une fois, partage.
static func _build_bang_stream() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION_S := 0.6
	var n := roundi(RATE * DURATION_S)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.08)
		var crack := noise * exp(-t / 0.018)
		var thump := sin(TAU * 58.0 * t) * exp(-t / 0.07)
		var hiss := low * 2.5 * exp(-t / 0.22) * minf(1.0, t / 0.02)
		var v := crack * 0.9 + thump * 0.8 + hiss * 0.35
		data.encode_s16(i * 2, clampi(roundi(clampf(v, -1.0, 1.0) * 32000.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
