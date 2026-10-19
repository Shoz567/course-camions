class_name TruckState
extends RefCounted

## Etat d'un camion dans un snapshot (docs/NETCODE.md §3) : 36 octets.
##
##   position            3 x float32                                   12
##   orientation         quaternion « smallest-three » (2 + 3 x 10 bits) 4
##   vitesse lineaire    3 x float16                                     6
##   vitesse angulaire   3 x float16                                     6
##   braquage            int8, +/- ANGLE_RANGE_DEG                       1
##   angle de remorque   int8, +/- ANGLE_RANGE_DEG                       1
##   flags               bitfield 16 bits (dont 6 pneus creves)          2
##   PV de la tete       u8                                              1
##   PV de la remorque   u8                                              1
##   cargo               u8 : recharge 0..127, bit 7 = verrou du depart  1
##   reserve             u8                                              1
##
## NETCODE.md prevoyait 1 octet de braquage et 3 de flags : l'angle de la
## remorque articulee (VEHICLE_SPEC §5 bis) prend l'un des trois. PV, cargo et
## pneus (2026-10-17) : ce que les clients affichent (HUD, fumee, jantes) sans
## rien decider ; dans chaque snapshot, une perte se rattrape au suivant. La compression des suspensions n'est pas envoyee : chaque machine
## la recalcule par ses rayons (purement visuel).

const SIZE := 36
## Braquage (max_steer_deg = 32) et remorque (trailer_max_angle_deg = 35) :
## une seule echelle, 0,35 deg de pas.
const ANGLE_RANGE_DEG := 45.0
## 10 bits signes par composante : +/- 511 pour +/- 1/sqrt(2).
const QUAT_SCALE := 511.0 * 1.41421356

const FLAG_BOOSTING := 1
const FLAG_HANDBRAKE := 2
const FLAG_WRECKED := 4
const FLAG_TRAILER_DETACHED := 8
const FLAG_HONK := 16
## Pneus creves : bits FLAG_TIRES_SHIFT .. +5 (ordre FL, FR, RL, RR, remorque
## gauche, droite : Truck.burst_tire).
const FLAG_TIRES_SHIFT := 5
const TIRE_COUNT := 6
const CARGO_LOCKED := 128

var position: Vector3 = Vector3.ZERO
var rotation: Quaternion = Quaternion.IDENTITY
var linear_velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO
var steer_deg: float = 0.0
var trailer_angle_deg: float = 0.0
var flags: int = 0
var hp: float = 0.0
var trailer_hp: float = 0.0
## Recharge du cargo (0 : vient de larguer, 1 : pret) et verrou du depart.
var cargo_charge: float = 1.0
var cargo_locked: bool = false


## Pneus creves (bits 0..5).
func tires() -> int:
	return (flags >> FLAG_TIRES_SHIFT) & ((1 << TIRE_COUNT) - 1)


## Etat courant de `truck` (cote host, apres le tick physique).
func capture(truck: Truck) -> void:
	var xf := truck.global_transform
	position = xf.origin
	rotation = xf.basis.get_rotation_quaternion()
	# camion gele (epave) : il garde dans ses proprietes sa vitesse d'avant ; les
	# clients l'extrapoleraient alors loin de sa place, puis le rameneraient
	var frozen := truck.freeze and not truck.is_net_puppet()
	linear_velocity = Vector3.ZERO if frozen else truck.linear_velocity
	angular_velocity = Vector3.ZERO if frozen else truck.angular_velocity
	steer_deg = truck.get_steer_deg()
	trailer_angle_deg = truck.get_trailer_angle_deg()
	flags = 0
	if truck.is_boosting():
		flags |= FLAG_BOOSTING
	if truck.get_handbrake_blend() > 0.5:
		flags |= FLAG_HANDBRAKE
	if truck.is_wrecked():
		flags |= FLAG_WRECKED
	if truck.is_trailer_detached():
		flags |= FLAG_TRAILER_DETACHED
	if truck.get_input().honk:
		flags |= FLAG_HONK
	for w in TIRE_COUNT:
		if truck.is_tire_burst(w):
			flags |= 1 << (FLAG_TIRES_SHIFT + w)
	var health := TruckHealth.of(truck)
	hp = health.hp if health != null else 0.0
	trailer_hp = health.trailer_hp if health != null else 0.0
	var cargo := truck.get_node_or_null(^"Cargo") as TruckCargo
	cargo_charge = cargo.get_charge() if cargo != null else 1.0
	cargo_locked = cargo != null and cargo.is_locked()


func copy_from(o: TruckState) -> void:
	position = o.position
	rotation = o.rotation
	linear_velocity = o.linear_velocity
	angular_velocity = o.angular_velocity
	steer_deg = o.steer_deg
	trailer_angle_deg = o.trailer_angle_deg
	flags = o.flags
	hp = o.hp
	trailer_hp = o.trailer_hp
	cargo_charge = o.cargo_charge
	cargo_locked = o.cargo_locked


## Etat entre `a` (t = 0) et `b` (t = 1) : positions et angles en lineaire,
## orientation en slerp, flags de `b` des la moitie.
func interpolate(a: TruckState, b: TruckState, t: float) -> void:
	position = a.position.lerp(b.position, t)
	rotation = a.rotation.slerp(b.rotation, t)
	linear_velocity = a.linear_velocity.lerp(b.linear_velocity, t)
	angular_velocity = a.angular_velocity.lerp(b.angular_velocity, t)
	steer_deg = lerpf(a.steer_deg, b.steer_deg, t)
	trailer_angle_deg = lerpf(a.trailer_angle_deg, b.trailer_angle_deg, t)
	flags = b.flags if t >= 0.5 else a.flags
	hp = b.hp
	trailer_hp = b.trailer_hp
	cargo_charge = b.cargo_charge
	cargo_locked = b.cargo_locked


## Etat de `from` projete de `ticks` ticks par ses vitesses (snapshot en
## retard ou perdu, NETCODE.md §4).
func extrapolate(from: TruckState, ticks: float, tick_s: float) -> void:
	copy_from(from)
	var dt := ticks * tick_s
	position = from.position + from.linear_velocity * dt
	var w := from.angular_velocity
	if w.length_squared() > 1e-8:
		rotation = (Quaternion(w.normalized(), w.length() * dt) * from.rotation).normalized()


func write_to(buf: PackedByteArray, offset: int) -> void:
	buf.encode_float(offset, position.x)
	buf.encode_float(offset + 4, position.y)
	buf.encode_float(offset + 8, position.z)
	buf.encode_u32(offset + 12, encode_quaternion(rotation))
	buf.encode_half(offset + 16, linear_velocity.x)
	buf.encode_half(offset + 18, linear_velocity.y)
	buf.encode_half(offset + 20, linear_velocity.z)
	buf.encode_half(offset + 22, angular_velocity.x)
	buf.encode_half(offset + 24, angular_velocity.y)
	buf.encode_half(offset + 26, angular_velocity.z)
	buf.encode_s8(offset + 28, _angle_to_s8(steer_deg))
	buf.encode_s8(offset + 29, _angle_to_s8(trailer_angle_deg))
	buf.encode_u16(offset + 30, flags & 0xFFFF)
	buf.encode_u8(offset + 32, clampi(roundi(hp), 0, 255))
	buf.encode_u8(offset + 33, clampi(roundi(trailer_hp), 0, 255))
	buf.encode_u8(offset + 34, clampi(roundi(cargo_charge * 127.0), 0, 127) | (CARGO_LOCKED if cargo_locked else 0))
	buf.encode_u8(offset + 35, 0)


func read_from(buf: PackedByteArray, offset: int) -> void:
	position = Vector3(buf.decode_float(offset), buf.decode_float(offset + 4), buf.decode_float(offset + 8))
	rotation = decode_quaternion(buf.decode_u32(offset + 12))
	linear_velocity = Vector3(buf.decode_half(offset + 16), buf.decode_half(offset + 18), buf.decode_half(offset + 20))
	angular_velocity = Vector3(buf.decode_half(offset + 22), buf.decode_half(offset + 24), buf.decode_half(offset + 26))
	steer_deg = buf.decode_s8(offset + 28) / 127.0 * ANGLE_RANGE_DEG
	trailer_angle_deg = buf.decode_s8(offset + 29) / 127.0 * ANGLE_RANGE_DEG
	flags = buf.decode_u16(offset + 30)
	hp = buf.decode_u8(offset + 32)
	trailer_hp = buf.decode_u8(offset + 33)
	var cg := buf.decode_u8(offset + 34)
	cargo_charge = (cg & 127) / 127.0
	cargo_locked = cg & CARGO_LOCKED != 0


static func _angle_to_s8(deg: float) -> int:
	return roundi(clampf(deg / ANGLE_RANGE_DEG, -1.0, 1.0) * 127.0)


## « Smallest-three » : on omet la plus grande composante (son index sur 2
## bits), on la rend positive (q et -q sont la meme rotation), et les trois
## autres, toutes dans [-1/sqrt(2), 1/sqrt(2)], tiennent sur 10 bits signes.
static func encode_quaternion(q: Quaternion) -> int:
	q = q.normalized()
	var c := PackedFloat32Array([q.x, q.y, q.z, q.w])
	var big := 0
	for i in range(1, 4):
		if absf(c[i]) > absf(c[big]):
			big = i
	var s := -1.0 if c[big] < 0.0 else 1.0
	var packed := big
	var shift := 2
	for i in 4:
		if i == big:
			continue
		var v := clampi(roundi(c[i] * s * QUAT_SCALE), -511, 511)
		packed |= (v & 0x3FF) << shift
		shift += 10
	return packed


static func decode_quaternion(packed: int) -> Quaternion:
	var big := packed & 3
	var c := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var shift := 2
	var sum := 0.0
	for i in 4:
		if i == big:
			continue
		var v := (packed >> shift) & 0x3FF
		if v >= 512:
			v -= 1024
		var f := v / QUAT_SCALE
		c[i] = f
		sum += f * f
		shift += 10
	c[big] = sqrt(maxf(0.0, 1.0 - sum))
	return Quaternion(c[0], c[1], c[2], c[3]).normalized()
