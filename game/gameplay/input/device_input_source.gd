class_name DeviceInputSource
extends InputSource

## Une manette (XInput ou DualShock/DualSense, via la base SDL de Godot),
## identifiee par son device id (docs/INPUT_SPEC.md §3, §4, §6).
##
## Lit les evenements bruts et ignore tout ce qui ne vient pas de SA manette :
## c'est ce qui rend l'ecran partage possible sans actions p1_, p2_...
##
##   steer      stick gauche X     throttle  RT / R2     brake  LT / L2
##   handbrake  A / Croix          boost     X / Carre   reset  Y / Triangle

@export var device_id: int = 0
## Zone morte axiale, sur X uniquement.
@export_range(0.0, 0.5, 0.01) var steer_deadzone: float = 0.10
## Courbe de reponse de la direction : 1 = lineaire, > 1 = plus precis au centre.
@export_range(1.0, 3.0, 0.05) var steer_exponent: float = 1.5

var connected: bool = false

var _axis_x: float = 0.0
var _rt: float = 0.0
var _lt: float = 0.0
var _handbrake: bool = false
var _boost: bool = false
var _reset_pending: bool = false


func _ready() -> void:
	connected = Input.get_connected_joypads().has(device_id)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _input(event: InputEvent) -> void:
	if event.device != device_id:
		return
	var motion := event as InputEventJoypadMotion
	if motion != null:
		match motion.axis:
			JOY_AXIS_LEFT_X:
				_axis_x = motion.axis_value
			JOY_AXIS_TRIGGER_RIGHT:
				_rt = motion.axis_value
			JOY_AXIS_TRIGGER_LEFT:
				_lt = motion.axis_value
		return
	var button := event as InputEventJoypadButton
	if button != null:
		match button.button_index:
			JOY_BUTTON_A:
				_handbrake = button.pressed
			JOY_BUTTON_X:
				_boost = button.pressed
			JOY_BUTTON_Y:
				if button.pressed:
					_reset_pending = true


func poll(tick: int) -> InputFrame:
	frame.tick = tick
	frame.steer = shape_steer(_axis_x)
	# gachettes analogiques de bout en bout, sans seuil (INPUT_SPEC §3)
	frame.throttle = clampf(_rt, 0.0, 1.0)
	frame.brake = clampf(_lt, 0.0, 1.0)
	frame.handbrake = _handbrake
	frame.boost = _boost
	frame.reset = _reset_pending
	_reset_pending = false
	return frame


## Zone morte axiale puis courbe de reponse, signe conserve.
func shape_steer(x: float) -> float:
	var a := absf(x)
	if a <= steer_deadzone:
		return 0.0
	var t := clampf((a - steer_deadzone) / (1.0 - steer_deadzone), 0.0, 1.0)
	return signf(x) * pow(t, steer_exponent)


func _on_joy_connection_changed(device: int, is_connected: bool) -> void:
	if device != device_id:
		return
	connected = is_connected
	if not is_connected:
		# manette debranchee : gaz a zero, roue libre, jamais de pause (§6)
		_axis_x = 0.0
		_rt = 0.0
		_lt = 0.0
		_handbrake = false
		_boost = false
		_reset_pending = false
