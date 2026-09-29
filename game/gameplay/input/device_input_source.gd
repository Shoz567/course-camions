class_name DeviceInputSource
extends InputSource

## Une manette, identifiee par son device id (docs/INPUT_SPEC.md §3, §4, §6).
## Lit les evenements bruts et ignore tout ce qui ne vient pas de SA manette :
## c'est ce qui rend l'ecran partage possible sans actions p1_, p2_...
##
## Godot (SDL) nomme les boutons par POSITION, pas par etiquette :
##   JOY_BUTTON_A = bas    (Croix PS, A Xbox, B Switch)
##   JOY_BUTTON_B = droite (Rond PS, B Xbox, A Switch)
##   JOY_BUTTON_X = gauche (Carre PS, X Xbox, Y Switch)
##   JOY_BUTTON_Y = haut   (Triangle PS, Y Xbox, X Switch)
##   JOY_BUTTON_BACK = Create PS (View Xbox, - Switch)
##   JOY_BUTTON_START = Options PS (Menu Xbox, + Switch)
##
## Profil par defaut : Forza Horizon, manette PlayStation 5 DualSense
## (decide le 2026-09-30), reaffectable ci-dessous sans code :
##   accelerer        R2, analogique de bout en bout
##   freiner, reculer L2, analogique
##   frein a main     Croix ou R1 (derapage)
##   nitro boost      Carre (1,5 s, recharge 4 s)
##   largage remorque Triangle (recharge 30 s)
##   klaxon           L1
##   camera           R3, ou un coup franc du stick droit : signal local
##   reset            Options, Create ou pave tactile

## Changement de vue demande (1re / 3e personne). Local : la camera ne modifie
## pas la simulation, elle n'est pas dans l'InputFrame (INPUT_SPEC §2).
signal camera_toggle_requested

@export var device_id: int = 0
## Zone morte axiale, sur X uniquement.
@export_range(0.0, 0.5, 0.01) var steer_deadzone: float = 0.10
## Courbe de reponse de la direction : 1 = lineaire, > 1 = plus precis au centre.
@export_range(1.0, 3.0, 0.05) var steer_exponent: float = 1.5
## Au-dela, une gachette ou un stick compte comme enfonce (fronts).
@export_range(0.0, 1.0, 0.01) var trigger_press_threshold: float = 0.5
## Coup de stick droit (vertical) qui change la vue.
@export_range(0.0, 1.0, 0.01) var camera_flick_threshold: float = 0.85

@export_group("Affectations")
@export var buttons_accelerate: Array[JoyButton] = []
@export var buttons_brake: Array[JoyButton] = []
@export var buttons_handbrake: Array[JoyButton] = [JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER]
@export var buttons_boost: Array[JoyButton] = [JOY_BUTTON_X]
@export var buttons_honk: Array[JoyButton] = [JOY_BUTTON_LEFT_SHOULDER]
@export var buttons_cargo: Array[JoyButton] = [JOY_BUTTON_Y]
@export var buttons_camera: Array[JoyButton] = [JOY_BUTTON_RIGHT_STICK]
@export var buttons_reset: Array[JoyButton] = [JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_TOUCHPAD]
## Gachette d'accelerateur analogique (R2).
@export var axis_accelerate: JoyAxis = JOY_AXIS_TRIGGER_RIGHT
## Gachette de frein analogique (L2).
@export var axis_brake: JoyAxis = JOY_AXIS_TRIGGER_LEFT
## Gachette de largage (au franchissement du seuil) : aucune par defaut.
@export var axis_cargo: JoyAxis = JOY_AXIS_INVALID
## Axe du coup de stick qui change la vue.
@export var axis_camera: JoyAxis = JOY_AXIS_RIGHT_Y

var connected: bool = false

var _axis_x: float = 0.0
var _rt: float = 0.0
var _lt: float = 0.0
var _cargo_axis_down: bool = false
var _camera_axis_down: bool = false
var _accel_held: int = 0
var _brake_held: int = 0
var _handbrake_held: int = 0
var _boost_held: int = 0
var _reset_pending: bool = false
var _honk_pending: bool = false
var _cargo_pending: bool = false


func _ready() -> void:
	connected = Input.get_connected_joypads().has(device_id)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _input(event: InputEvent) -> void:
	if event.device != device_id:
		return
	var motion := event as InputEventJoypadMotion
	if motion != null:
		var a := motion.axis
		if a == JOY_AXIS_LEFT_X:
			_axis_x = motion.axis_value
		if a == axis_accelerate:
			_rt = motion.axis_value
		if a == axis_brake:
			_lt = motion.axis_value
		if a == axis_cargo:
			var down := motion.axis_value >= trigger_press_threshold
			if down and not _cargo_axis_down:
				_cargo_pending = true
			_cargo_axis_down = down
		if a == axis_camera:
			var flick := absf(motion.axis_value) >= camera_flick_threshold
			if flick and not _camera_axis_down:
				camera_toggle_requested.emit()
			_camera_axis_down = flick
		return
	var button := event as InputEventJoypadButton
	if button == null:
		return
	var b := button.button_index
	var step := 1 if button.pressed else -1
	# compteurs : deux boutons pour la meme action (Croix et R1) se cumulent
	if buttons_accelerate.has(b):
		_accel_held = maxi(0, _accel_held + step)
	if buttons_brake.has(b):
		_brake_held = maxi(0, _brake_held + step)
	if buttons_handbrake.has(b):
		_handbrake_held = maxi(0, _handbrake_held + step)
	if buttons_boost.has(b):
		_boost_held = maxi(0, _boost_held + step)
	if not button.pressed:
		return
	if buttons_honk.has(b):
		_honk_pending = true
	if buttons_cargo.has(b):
		_cargo_pending = true
	if buttons_camera.has(b):
		camera_toggle_requested.emit()
	if buttons_reset.has(b):
		_reset_pending = true


func poll(tick: int) -> InputFrame:
	frame.tick = tick
	frame.steer = shape_steer(_axis_x)
	# gachettes analogiques de bout en bout, sans seuil : un demi-gaz est un
	# demi-gaz (INPUT_SPEC §3) ; un bouton affecte vaut la gachette enfoncee
	frame.throttle = 1.0 if _accel_held > 0 else clampf(_rt, 0.0, 1.0)
	frame.brake = 1.0 if _brake_held > 0 else clampf(_lt, 0.0, 1.0)
	frame.handbrake = _handbrake_held > 0
	frame.boost = _boost_held > 0
	frame.reset = _reset_pending
	frame.honk = _honk_pending
	frame.cargo = _cargo_pending
	_reset_pending = false
	_honk_pending = false
	_cargo_pending = false
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
		_cargo_axis_down = false
		_camera_axis_down = false
		_accel_held = 0
		_brake_held = 0
		_handbrake_held = 0
		_boost_held = 0
		_reset_pending = false
		_honk_pending = false
		_cargo_pending = false
