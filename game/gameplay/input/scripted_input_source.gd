class_name ScriptedInputSource
extends InputSource

## Source des tests headless (docs/INPUT_SPEC.md §7) : rejoue une sequence
## d'InputFrame, parfaitement reproductible. Durees en ticks.
##
## Chaque champ a sa PROPRE ligne de temps, qui part du premier poll() :
##
##   src.push_hold(&"throttle", 1.0, 600)   # plein gaz, ticks 0 .. 599
##   src.push_hold(&"steer", 0.0, 300)      # tout droit 300 ticks...
##   src.push_hold(&"steer", 1.0, 120)      # ...puis plein braquage (ticks 300 .. 419)
##   src.push_once(&"reset")                # reset au tick 0
##
## Hors de toute plage, un champ est au neutre.

const FIELDS: Array[StringName] = [&"steer", &"throttle", &"brake", &"handbrake", &"boost", &"reset"]

var _t: int = 0
var _segments: Dictionary = {}   # champ -> Array de [debut, fin exclue, valeur]
var _cursor: Dictionary = {}     # champ -> fin de la derniere plage


func _init() -> void:
	for f in FIELDS:
		_segments[f] = []
		_cursor[f] = 0


## Maintient `field` a `value` pendant `ticks` ticks, apres ses plages deja poussees.
func push_hold(field: StringName, value: Variant, ticks: int) -> void:
	assert(FIELDS.has(field), "ScriptedInputSource : champ inconnu %s" % field)
	assert(ticks > 0)
	var start: int = _cursor[field]
	(_segments[field] as Array).append([start, start + ticks, value])
	_cursor[field] = start + ticks


## Vrai pendant un seul tick (front montant : reset).
func push_once(field: StringName) -> void:
	push_hold(field, true, 1)


## Duree totale du script, en ticks.
func length_ticks() -> int:
	var n := 0
	for f in FIELDS:
		n = maxi(n, _cursor[f])
	return n


func is_finished() -> bool:
	return _t >= length_ticks()


func poll(tick: int) -> InputFrame:
	frame.tick = tick
	frame.clear()
	for f in FIELDS:
		for seg: Array in _segments[f]:
			if _t >= seg[0] and _t < seg[1]:
				frame.set(f, seg[2])
				break
	_t += 1
	return frame
