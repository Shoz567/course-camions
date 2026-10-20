class_name InputFrame
extends RefCounted

## Consigne de conduite d'un tick (docs/INPUT_SPEC.md §2). Le camion ne consomme
## que ca : jamais Input.*.
##
## Format binaire : 6 octets. Les frames se groupent par 3 dans un paquet en
## phase 6 : write_to() / read_from() travaillent donc a un decalage donne.

const SIZE := 6

const BIT_HANDBRAKE := 1
const BIT_BOOST := 2
const BIT_RESET := 4
const BIT_HONK := 8
const BIT_CARGO := 16
## Pouvoirs (tache 4.5.8) : croix directionnelle gauche / droite.
const BIT_POWER_LEFT := 32
const BIT_POWER_RIGHT := 64
## Cible suivante (2026-10-20) : fleche haut de la croix.
const BIT_TARGET_NEXT := 128

var tick: int = 0
var steer: float = 0.0        # -1 (gauche) .. +1 (droite), zone morte appliquee
var throttle: float = 0.0     # 0 .. 1
var brake: float = 0.0        # 0 .. 1 ; a l'arret, freiner = marche arriere
var handbrake: bool = false   # etat maintenu
var boost: bool = false       # etat maintenu
var reset: bool = false       # front montant : vrai un seul tick
var honk: bool = false        # front montant : coup de klaxon (vu des autres joueurs)
var cargo: bool = false       # front montant : largage de cargo
var power_left: bool = false  # front montant : pouvoir de gauche
var power_right: bool = false # front montant : pouvoir de droite
var target_next: bool = false # front montant : cible suivante des pouvoirs


func copy_from(other: InputFrame) -> void:
	tick = other.tick
	steer = other.steer
	throttle = other.throttle
	brake = other.brake
	handbrake = other.handbrake
	boost = other.boost
	reset = other.reset
	honk = other.honk
	cargo = other.cargo
	power_left = other.power_left
	power_right = other.power_right
	target_next = other.target_next


## Remet toutes les commandes au neutre (manette debranchee : roue libre).
func clear() -> void:
	steer = 0.0
	throttle = 0.0
	brake = 0.0
	handbrake = false
	boost = false
	reset = false
	honk = false
	cargo = false
	power_left = false
	power_right = false
	target_next = false


func to_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(SIZE)
	write_to(b, 0)
	return b


static func from_bytes(b: PackedByteArray) -> InputFrame:
	var f := InputFrame.new()
	f.read_from(b, 0)
	return f


## Ecrit les 6 octets a partir de `offset`. `buf` doit etre assez grand.
func write_to(buf: PackedByteArray, offset: int) -> void:
	buf.encode_u16(offset, posmod(tick, 65536))
	buf.encode_s8(offset + 2, roundi(clampf(steer, -1.0, 1.0) * 127.0))
	buf.encode_u8(offset + 3, roundi(clampf(throttle, 0.0, 1.0) * 255.0))
	buf.encode_u8(offset + 4, roundi(clampf(brake, 0.0, 1.0) * 255.0))
	var bits := 0
	if handbrake:
		bits |= BIT_HANDBRAKE
	if boost:
		bits |= BIT_BOOST
	if reset:
		bits |= BIT_RESET
	if honk:
		bits |= BIT_HONK
	if cargo:
		bits |= BIT_CARGO
	if power_left:
		bits |= BIT_POWER_LEFT
	if power_right:
		bits |= BIT_POWER_RIGHT
	if target_next:
		bits |= BIT_TARGET_NEXT
	buf.encode_u8(offset + 5, bits)


## Lit 6 octets a partir de `offset`. `tick` revient modulo 65536.
func read_from(buf: PackedByteArray, offset: int) -> void:
	tick = buf.decode_u16(offset)
	steer = buf.decode_s8(offset + 2) / 127.0
	throttle = buf.decode_u8(offset + 3) / 255.0
	brake = buf.decode_u8(offset + 4) / 255.0
	var bits := buf.decode_u8(offset + 5)
	handbrake = (bits & BIT_HANDBRAKE) != 0
	boost = (bits & BIT_BOOST) != 0
	reset = (bits & BIT_RESET) != 0
	honk = (bits & BIT_HONK) != 0
	cargo = (bits & BIT_CARGO) != 0
	power_left = (bits & BIT_POWER_LEFT) != 0
	power_right = (bits & BIT_POWER_RIGHT) != 0
	target_next = (bits & BIT_TARGET_NEXT) != 0
