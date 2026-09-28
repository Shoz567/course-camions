class_name LocalInputSource
extends InputSource

## Joueur local unique : la premiere manette connectee ET le clavier, fusionnes
## (docs/INPUT_SPEC.md §3). La commande la plus franche l'emporte. Suit les
## branchements a chaud : une manette branchee en cours de route est adoptee.
##
## Pour l'ecran partage (phase 4), un joueur = une DeviceInputSource : cette
## source ne sert qu'au jeu solo et au developpement.

## Changement de vue demande, par la manette ou le clavier (local).
signal camera_toggle_requested

var pad: DeviceInputSource
var keyboard: KeyboardInputSource


func _ready() -> void:
	pad = DeviceInputSource.new()
	pad.name = "Pad"
	add_child(pad)
	keyboard = KeyboardInputSource.new()
	keyboard.name = "Keyboard"
	add_child(keyboard)
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
	return frame
