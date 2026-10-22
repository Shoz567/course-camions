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
##   nitro boost      Carre (1,5 s, recharge 6 s)
##   largage remorque Triangle (recharge 30 s)
##   klaxon           L3 (L1 jusqu'au 2026-10-20)
##   camera           R3 : signal local
##   regard           stick droit (petite amplitude) et L1 maintenu : regarder
##                    derriere ; local, hors InputFrame (look, looking_back)
##   reset            Create ou pave tactile (Options : menu pause, LocalRace)
##   pouvoirs         fleches gauche / droite de la croix (4.5.8)
##   cible suivante   fleche haut de la croix (2026-10-20)

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
## Coup de stick (axis_camera) qui change la vue.
@export_range(0.0, 1.0, 0.01) var camera_flick_threshold: float = 0.85
## Zone morte radiale du stick droit (regard).
@export_range(0.0, 0.5, 0.01) var look_deadzone: float = 0.15

@export_group("Affectations")
@export var buttons_accelerate: Array[JoyButton] = []
@export var buttons_brake: Array[JoyButton] = []
@export var buttons_handbrake: Array[JoyButton] = [JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER]
@export var buttons_boost: Array[JoyButton] = [JOY_BUTTON_X]
@export var buttons_honk: Array[JoyButton] = [JOY_BUTTON_LEFT_STICK]
## Regarder derriere, tant que le bouton est tenu (2026-10-20).
@export var buttons_look_back: Array[JoyButton] = [JOY_BUTTON_LEFT_SHOULDER]
@export var buttons_cargo: Array[JoyButton] = [JOY_BUTTON_Y]
## Pouvoirs (tache 4.5.8) : fleches gauche / droite de la croix.
@export var buttons_power_left: Array[JoyButton] = [JOY_BUTTON_DPAD_LEFT]
@export var buttons_power_right: Array[JoyButton] = [JOY_BUTTON_DPAD_RIGHT]
## Cible suivante des pouvoirs (2026-10-20) : fleche haut de la croix.
@export var buttons_target: Array[JoyButton] = [JOY_BUTTON_DPAD_UP]
@export var buttons_camera: Array[JoyButton] = [JOY_BUTTON_RIGHT_STICK]
@export var buttons_reset: Array[JoyButton] = [JOY_BUTTON_BACK, JOY_BUTTON_TOUCHPAD]
## Gachette d'accelerateur analogique (R2).
@export var axis_accelerate: JoyAxis = JOY_AXIS_TRIGGER_RIGHT
## Gachette de frein analogique (L2).
@export var axis_brake: JoyAxis = JOY_AXIS_TRIGGER_LEFT
## Gachette de largage (au franchissement du seuil) : aucune par defaut.
@export var axis_cargo: JoyAxis = JOY_AXIS_INVALID
## Axe du coup de stick qui change la vue : aucun par defaut depuis que le
## stick droit oriente le regard (2026-10-20).
@export var axis_camera: JoyAxis = JOY_AXIS_INVALID

var connected: bool = false
## Debranchee en cours de route, pas encore rebranchee (INPUT_SPEC §6 : la vue
## de son joueur l'affiche).
var unplugged: bool = false

var _axis_x: float = 0.0
var _rt: float = 0.0
var _lt: float = 0.0
var _cargo_axis_down: bool = false
var _camera_axis_down: bool = false
var _accel_held: int = 0
var _brake_held: int = 0
var _handbrake_held: int = 0
var _boost_held: int = 0
var _look_back_held: int = 0
var _rx: float = 0.0
var _ry: float = 0.0
var _reset_pending: bool = false
var _honk_pending: bool = false
var _cargo_pending: bool = false
var _power_left_pending: bool = false
var _power_right_pending: bool = false
var _target_pending: bool = false


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
		if a == JOY_AXIS_RIGHT_X:
			_rx = motion.axis_value
		if a == JOY_AXIS_RIGHT_Y:
			_ry = motion.axis_value
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
	if buttons_look_back.has(b):
		_look_back_held = maxi(0, _look_back_held + step)
	if not button.pressed:
		return
	if buttons_honk.has(b):
		_honk_pending = true
	if buttons_cargo.has(b):
		_cargo_pending = true
	if buttons_power_left.has(b):
		_power_left_pending = true
	if buttons_power_right.has(b):
		_power_right_pending = true
	if buttons_target.has(b):
		_target_pending = true
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
	frame.power_left = _power_left_pending
	frame.power_right = _power_right_pending
	frame.target_next = _target_pending
	_power_left_pending = false
	_power_right_pending = false
	_target_pending = false
	_reset_pending = false
	_honk_pending = false
	_cargo_pending = false
	return frame


## Regard du stick droit (-1..1 ; x vers la droite, y vers le bas), zone
## morte radiale puis remise a l'echelle. Local : lu par la camera.
func look() -> Vector2:
	var v := Vector2(_rx, _ry)
	var a := v.length()
	if a <= look_deadzone:
		return Vector2.ZERO
	return v / a * clampf((a - look_deadzone) / (1.0 - look_deadzone), 0.0, 1.0)


## Bouton « regarder derriere » tenu.
func looking_back() -> bool:
	return _look_back_held > 0


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
	unplugged = not is_connected
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
		_look_back_held = 0
		_rx = 0.0
		_ry = 0.0
		_reset_pending = false
		_honk_pending = false
		_cargo_pending = false
		_power_left_pending = false
		_power_right_pending = false
		_target_pending = false
