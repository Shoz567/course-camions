extends PhysicsTest

## Traces DebugDraw du camion (tache 1.9). Au sol, par roue : rayon (1 segment),
## contact (croix, 3), charge (fleche, 3) ; plus le centre de masse (croix, 3).
## Les forces de pneu (fleches, canal forces) s'y ajoutent quand elles sont non
## nulles. Chaque trace se coupe par canal, et le camion entier par son flag.
##
## Ce noeud passe APRES le camion (priorite physique 100) : il compte ce que le
## camion vient de poser dans le tick.

const PER_WHEEL := 1 + 3 + 3
const COM := 3
const TIRE_ARROW := 3

var _truck: Truck
var _all: int = -1
var _no_suspension: int = -1
var _flag_off: int = -1


func _test_setup() -> void:
	duration_ticks = 40
	process_physics_priority = 100
	DebugDraw.enabled = true
	DebugDraw.clear()
	add_floor()
	_truck = TruckTestUtil.spawn_truck(self, Vector3.ZERO)


func _test_tick(t: int) -> void:
	match t:
		10:
			_all = DebugDraw.segment_count()
			DebugDraw.set_channel_enabled(DebugDraw.CH_SUSPENSION, false)
		20:
			_no_suspension = DebugDraw.segment_count()
			DebugDraw.set_channel_enabled(DebugDraw.CH_SUSPENSION, true)
			_truck.debug_draw = false
		30:
			_flag_off = DebugDraw.segment_count()


func _test_finish() -> void:
	var minimum := 4 * PER_WHEEL + COM
	check("tous les canaux : rayons, contacts, charges, CdM",
		_all >= minimum and _all <= minimum + 4 * TIRE_ARROW,
		"segments=%d attendu %d .. %d" % [_all, minimum, minimum + 4 * TIRE_ARROW])
	check("canal suspension coupe : CdM et forces seulement",
		_no_suspension >= COM and _no_suspension <= COM + 4 * TIRE_ARROW, "segments=%d" % _no_suspension)
	check("flag debug_draw coupe : aucun trace", _flag_off == 0, "segments=%d" % _flag_off)
