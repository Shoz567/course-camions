extends Node3D

## Bac a sable de conduite en direct (developpement, pas un livrable de jeu).
##
## Branche la premiere manette connectee (XInput, DualShock, DualSense) et le
## clavier sur le camion, et affiche l'InputFrame recue a chaque tick. Sert a
## verifier l'input AVANT que les forces existent, puis a conduire des qu'elles
## arrivent (taches 1.3 a 1.5).
##
## La camera ici est un simple suivi de debug : la vraie camera de poursuite est
## la tache 2.1.

@onready var _truck: Truck = $Truck
@onready var _pad: DeviceInputSource = $PadSource
@onready var _keyboard: KeyboardInputSource = $KeyboardSource
@onready var _camera: Camera3D = $Camera3D
@onready var _hud: Label = $Hud/Label

var _merged: InputFrame = InputFrame.new()


func _ready() -> void:
	_pick_pad()
	Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void: _pick_pad())
	for i in 20:
		var pillar := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.5, 3.0, 0.5)
		pillar.mesh = m
		pillar.position = Vector3(-8.0 if i % 2 == 0 else 8.0, 1.5, -20.0 * floorf(i / 2.0))
		add_child(pillar)


## Prend la premiere manette connectee, si la source n'en suit pas deja une.
func _pick_pad() -> void:
	var pads := Input.get_connected_joypads()
	if pads.has(_pad.device_id):
		_pad.connected = true
		return
	if not pads.is_empty():
		_pad.device_id = pads[0]
		_pad.connected = true


func _physics_process(_delta: float) -> void:
	var tick := Engine.get_physics_frames()
	var k := _keyboard.poll(tick)
	var p := _pad.poll(tick)
	# Fusion manette + clavier : la commande la plus franche l'emporte.
	_merged.tick = tick
	_merged.steer = p.steer if absf(p.steer) > absf(k.steer) else k.steer
	_merged.throttle = maxf(p.throttle, k.throttle)
	_merged.brake = maxf(p.brake, k.brake)
	_merged.handbrake = p.handbrake or k.handbrake
	_merged.boost = p.boost or k.boost
	_merged.reset = p.reset or k.reset
	_truck.set_input(_merged)


func _process(delta: float) -> void:
	var xf := _truck.global_transform
	var want := xf.origin + xf.basis.z * 13.0 + Vector3.UP * 5.5
	_camera.global_position = _camera.global_position.lerp(want, clampf(delta * 4.0, 0.0, 1.0))
	_camera.look_at(xf.origin + Vector3.UP * 1.5)

	var f := _truck.get_input()
	var pad_name := "aucune (clavier : ZQSD / fleches, Espace, Maj, R)"
	if _pad.connected:
		pad_name = "%d — %s" % [_pad.device_id, Input.get_joy_name(_pad.device_id)]
	_hud.text = "\n".join([
		"Manette : %s" % pad_name,
		"tick %d" % f.tick,
		"steer     %+.2f  %s" % [f.steer, _bar(f.steer)],
		"throttle   %.2f  %s" % [f.throttle, _bar(f.throttle)],
		"brake      %.2f  %s" % [f.brake, _bar(f.brake)],
		"handbrake %s   boost %s   reset %s" % [f.handbrake, f.boost, f.reset],
		"vitesse %.1f km/h   roues au sol %d" % [_truck.get_speed_kmh(), _truck.wheels_on_ground()],
		"",
		"Forces du camion pas encore ecrites (taches 1.3 a 1.5) : il repose sur son chassis.",
	])


func _bar(v: float) -> String:
	var n := roundi(absf(v) * 20.0)
	return ("<" if v < 0.0 else "") + "|".repeat(n)
