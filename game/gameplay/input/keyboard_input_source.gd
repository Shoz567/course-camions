class_name KeyboardInputSource
extends InputSource

## Clavier, pour le developpement et le 2 joueurs sur un meme clavier
## (docs/INPUT_SPEC.md §3). Touches par POSITION physique (clavier QWERTY de
## reference) : Z Q S D sur AZERTY = W A S D sur QWERTY.
##
##   ZQSD    : Z Q S D, Espace drift, Maj gauche boost, E cargo, H klaxon,
##             C camera, R reset
##   FLECHES : fleches, Ctrl droit drift, Maj droite boost, touche a gauche de
##             Maj droite (! en AZERTY) klaxon, la suivante (: en AZERTY)
##             camera, encore la suivante (; en AZERTY) cargo, Retour arriere
##             reset
##   LES DEUX: les deux jeux de touches (joueur seul)
##   AUCUN   : pas de clavier (J3 et J4, manette seulement)
##
## Le clavier est binaire : steer et throttle montent en `ramp_ticks` ticks
## pour ne pas donner de coups de volant qu'aucune manette ne produit.

## Changement de vue (local, hors InputFrame).
signal camera_toggle_requested

enum Layout { BOTH, ZQSD, ARROWS, NONE }

@export var layout: Layout = Layout.BOTH
@export_range(1, 30) var ramp_ticks: int = 8

var _left: bool = false
var _right: bool = false
var _up: bool = false
var _down: bool = false
var _handbrake: bool = false
var _boost: bool = false
var _reset_pending: bool = false
var _honk_pending: bool = false
var _cargo_pending: bool = false


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo or layout == Layout.NONE:
		return
	var p := key.pressed
	var right_side := key.location == KEY_LOCATION_RIGHT
	var zqsd := layout != Layout.ARROWS
	var arrows := layout != Layout.ZQSD
	match key.physical_keycode:
		KEY_A:
			if zqsd: _left = p
		KEY_D:
			if zqsd: _right = p
		KEY_W:
			if zqsd: _up = p
		KEY_S:
			if zqsd: _down = p
		KEY_LEFT:
			if arrows: _left = p
		KEY_RIGHT:
			if arrows: _right = p
		KEY_UP:
			if arrows: _up = p
		KEY_DOWN:
			if arrows: _down = p
		KEY_SPACE:
			if zqsd: _handbrake = p
		KEY_CTRL:
			if arrows and right_side: _handbrake = p
		KEY_SHIFT:
			if (zqsd and not right_side) or (arrows and right_side) or layout == Layout.BOTH:
				_boost = p
		KEY_H:
			if zqsd and p: _honk_pending = true
		KEY_SLASH:
			if arrows and p: _honk_pending = true
		KEY_C:
			if zqsd and p: camera_toggle_requested.emit()
		KEY_PERIOD:
			if arrows and p: camera_toggle_requested.emit()
		KEY_E:
			if zqsd and p: _cargo_pending = true
		KEY_COMMA:
			if arrows and p: _cargo_pending = true
		KEY_R:
			if zqsd and p: _reset_pending = true
		KEY_BACKSPACE:
			if arrows and p: _reset_pending = true


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
	frame.cargo = _cargo_pending
	_reset_pending = false
	_honk_pending = false
	_cargo_pending = false
	return frame
