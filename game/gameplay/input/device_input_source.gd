class_name DeviceInputSource
extends InputSource

## Une manette, identifiee par son device id (docs/INPUT_SPEC.md §3, §4, §6).
## Lit les evenements bruts et ignore tout ce qui ne vient pas de SA manette :
## c'est ce qui rend l'ecran partage possible sans actions p1_, p2_...
##
## Godot (SDL) nomme les boutons par POSITION, pas par etiquette :
##   bas = A Xbox / Croix PS / B Switch      droite = B Xbox / Rond PS / A Switch
##   gauche = X Xbox / Carre PS / Y Switch   haut = Y Xbox / Triangle PS / X Switch
##
## Schema par defaut (style Mario Kart, tout est reaffectable ci-dessous) :
##   accelerer        RT / R2 / ZR (analogique)  ou bouton du bas
##   freiner, reculer LT / L2 / ZL (analogique)  ou bouton de droite
##   drift            RB / R1 / R (frein a main), ou RT tant qu'on accelere
##                    avec le bouton du bas (A pour avancer, gachette pour deraper)
##   boost            LB / L1 / L
##   klaxon           bouton de gauche
##   camera           bouton du haut (signal local, hors InputFrame)
##   reset            Select / View / Share / -

## Changement de vue demande (1re / 3e personne). Local : la camera ne modifie
## pas la simulation, elle n'est pas dans l'InputFrame (INPUT_SPEC §2).
signal camera_toggle_requested

@export var device_id: int = 0
## Zone morte axiale, sur X uniquement.
@export_range(0.0, 0.5, 0.01) var steer_deadzone: float = 0.10
## Courbe de reponse de la direction : 1 = lineaire, > 1 = plus precis au centre.
@export_range(1.0, 3.0, 0.05) var steer_exponent: float = 1.5
## Au-dela, une gachette compte comme enfoncee (drift a la gachette).
@export_range(0.0, 1.0, 0.01) var trigger_press_threshold: float = 0.5

@export_group("Affectations")
@export var button_accelerate: JoyButton = JOY_BUTTON_A
@export var button_brake: JoyButton = JOY_BUTTON_B
@export var button_handbrake: JoyButton = JOY_BUTTON_RIGHT_SHOULDER
@export var button_boost: JoyButton = JOY_BUTTON_LEFT_SHOULDER
@export var button_honk: JoyButton = JOY_BUTTON_X
@export var button_camera: JoyButton = JOY_BUTTON_Y
@export var button_reset: JoyButton = JOY_BUTTON_BACK
@export var axis_accelerate: JoyAxis = JOY_AXIS_TRIGGER_RIGHT
@export var axis_brake: JoyAxis = JOY_AXIS_TRIGGER_LEFT

var connected: bool = false

var _axis_x: float = 0.0
var _rt: float = 0.0
var _lt: float = 0.0
var _accel_button: bool = false
var _brake_button: bool = false
var _handbrake: bool = false
var _boost: bool = false
var _reset_pending: bool = false
var _honk_pending: bool = false


func _ready() -> void:
	connected = Input.get_connected_joypads().has(device_id)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _input(event: InputEvent) -> void:
	if event.device != device_id:
		return
	var motion := event as InputEventJoypadMotion
	if motion != null:
		if motion.axis == JOY_AXIS_LEFT_X:
			_axis_x = motion.axis_value
		elif motion.axis == axis_accelerate:
			_rt = motion.axis_value
		elif motion.axis == axis_brake:
			_lt = motion.axis_value
		return
	var button := event as InputEventJoypadButton
	if button == null:
		return
	var p := button.pressed
	var b := button.button_index
	if b == button_accelerate:
		_accel_button = p
	elif b == button_brake:
		_brake_button = p
	elif b == button_handbrake:
		_handbrake = p
	elif b == button_boost:
		_boost = p
	elif b == button_honk:
		if p:
			_honk_pending = true
	elif b == button_camera:
		if p:
			camera_toggle_requested.emit()
	elif b == button_reset:
		if p:
			_reset_pending = true


func poll(tick: int) -> InputFrame:
	var rt := clampf(_rt, 0.0, 1.0)
	frame.tick = tick
	frame.steer = shape_steer(_axis_x)
	# accelerer : bouton du bas (plein gaz) ou gachette (analogique de bout en
	# bout, sans seuil : un demi-gaz est un demi-gaz, INPUT_SPEC §3). Quand on
	# accelere au bouton, la gachette devient le drift.
	if _accel_button:
		frame.throttle = 1.0
		frame.handbrake = _handbrake or rt >= trigger_press_threshold
	else:
		frame.throttle = rt
		frame.handbrake = _handbrake
	frame.brake = 1.0 if _brake_button else clampf(_lt, 0.0, 1.0)
	frame.boost = _boost
	frame.reset = _reset_pending
	frame.honk = _honk_pending
	_reset_pending = false
	_honk_pending = false
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
		_accel_button = false
		_brake_button = false
		_handbrake = false
		_boost = false
		_reset_pending = false
		_honk_pending = false
