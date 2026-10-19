class_name LocalInputSource
extends InputSource

## Un joueur local : une manette ET un jeu de touches du clavier, fusionnes
## (docs/INPUT_SPEC.md §3). La commande la plus franche l'emporte.
##
## `device` = -1 : la premiere manette connectee, adoptee a chaud (joueur seul).
## `device` >= 0 : cette manette-la, et aucune autre (ecran partage : le joueur
## 2 ne reagit jamais a la manette du joueur 1, INPUT_SPEC §4).

## Changement de vue demande, par la manette ou le clavier (local).
signal camera_toggle_requested

@export var device: int = -1
@export var keyboard_layout: KeyboardInputSource.Layout = KeyboardInputSource.Layout.BOTH
## Faux : joueur au clavier seul (salle d'attente du menu, tache 4.2), aucune
## manette ne le pilote.
@export var use_pad: bool = true

var pad: DeviceInputSource
var keyboard: KeyboardInputSource
const NO_PAD := -100


func _ready() -> void:
	pad = DeviceInputSource.new()
	pad.name = "Pad"
	# sans manette : un id qu'aucun evenement ne porte
	pad.device_id = maxi(device, 0) if use_pad else NO_PAD
	add_child(pad)
	keyboard = KeyboardInputSource.new()
	keyboard.name = "Keyboard"
	keyboard.layout = keyboard_layout
	add_child(keyboard)
	if device < 0 and use_pad:
		_pick_pad()
		Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void: _pick_pad())
	pad.camera_toggle_requested.connect(camera_toggle_requested.emit)
	keyboard.camera_toggle_requested.connect(camera_toggle_requested.emit)


## Nom lisible de la manette suivie, ou "" si aucune.
func pad_name() -> String:
	if not pad.connected:
		return ""
	return "%d — %s" % [pad.device_id, Input.get_joy_name(pad.device_id)]


func _pick_pad() -> void:
	var pads := Input.get_connected_joypads()
	if pads.has(pad.device_id):
		pad.connected = true
		return
	if not pads.is_empty():
		pad.device_id = pads[0]
		pad.connected = true


func poll(tick: int) -> InputFrame:
	var k := keyboard.poll(tick)
	var p := pad.poll(tick)
	frame.tick = tick
	frame.steer = p.steer if absf(p.steer) > absf(k.steer) else k.steer
	frame.throttle = maxf(p.throttle, k.throttle)
	frame.brake = maxf(p.brake, k.brake)
	frame.handbrake = p.handbrake or k.handbrake
	frame.boost = p.boost or k.boost
	frame.reset = p.reset or k.reset
	frame.honk = p.honk or k.honk
	frame.cargo = p.cargo or k.cargo
	return frame
