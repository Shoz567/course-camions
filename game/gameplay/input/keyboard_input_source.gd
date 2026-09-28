class_name KeyboardInputSource
extends InputSource

## Clavier du joueur 1, pour le developpement (docs/INPUT_SPEC.md §3).
## Touches par position physique : Z Q S D sur AZERTY (W A S D sur QWERTY),
## ou les fleches. Espace drift (frein a main), Maj boost, H klaxon, C camera,
## R reset.
##
## Le clavier est binaire : steer et throttle montent en `ramp_ticks` ticks
## pour ne pas donner de coups de volant qu'aucune manette ne produit.

## Changement de vue (local, hors InputFrame).
signal camera_toggle_requested

@export_range(1, 30) var ramp_ticks: int = 8

var _left: bool = false
var _right: bool = false
var _up: bool = false
var _down: bool = false
var _handbrake: bool = false
var _boost: bool = false
var _reset_pending: bool = false
var _honk_pending: bool = false


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo:
		return
	var p := key.pressed
	match key.physical_keycode:
		KEY_A, KEY_LEFT:
			_left = p
		KEY_D, KEY_RIGHT:
			_right = p
		KEY_W, KEY_UP:
			_up = p
		KEY_S, KEY_DOWN:
			_down = p
		KEY_SPACE:
			_handbrake = p
		KEY_SHIFT:
			_boost = p
		KEY_H:
			if p:
				_honk_pending = true
		KEY_C:
			if p:
				camera_toggle_requested.emit()
		KEY_R:
			if p:
				_reset_pending = true


func poll(tick: int) -> InputFrame:
	var step := 1.0 / ramp_ticks
	var steer_target := (1.0 if _right else 0.0) - (1.0 if _left else 0.0)
	frame.tick = tick
	frame.steer = move_toward(frame.steer, steer_target, step)
	frame.throttle = move_toward(frame.throttle, 1.0 if _up else 0.0, step)
	frame.brake = 1.0 if _down else 0.0
	frame.handbrake = _handbrake
	frame.boost = _boost
	frame.reset = _reset_pending
	frame.honk = _honk_pending
	_reset_pending = false
	_honk_pending = false
	return frame
