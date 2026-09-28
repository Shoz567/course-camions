extends Node3D

## Course de 3 tours sur la piste n°1 (scene principale de test).
##
## Compte a rebours, puis course : RaceLaps compte les tours (checkpoints dans
## l'ordre), AutoReset replace hors piste ou retourne, RaceHud affiche. A
## l'arrivee, Start / Entree relance. Commandes : voir DeviceInputSource
## (manette, style Mario Kart) et KeyboardInputSource.
##
## Le compte a rebours et l'enchainement de la course migreront dans
## RaceManager (tache 3.1) ; ici, le minimum pour courir.

const COUNTDOWN_TICKS := 180      # 3 s
const GO_TICKS := 60              # "GO !" reste 1 s

enum State { COUNTDOWN, RACING, FINISHED }

@onready var _track: TrackBlockout = $Track01
@onready var _truck: Truck = $Truck
@onready var _input: LocalInputSource = $LocalInput
@onready var _camera: ChaseCamera = $ChaseCamera
@onready var _auto_reset: AutoReset = $AutoReset
@onready var _race: RaceLaps = $RaceLaps
@onready var _hud: RaceHud = $RaceHud

var _state: State = State.COUNTDOWN
var _state_tick: int = 0
var _neutral: InputFrame = InputFrame.new()


func _ready() -> void:
	# pose initiale d'un camion immobile : pas une teleportation en mouvement
	_truck.global_transform = _track.get_start_transform(0)
	_camera.snap()
	# vue propre par defaut : F1 affiche les traces de debug
	DebugDraw.enabled = false
	_race.watch(_truck)
	_auto_reset.watch(_truck)
	_auto_reset.respawn_provider = _race.respawn_transform
	_input.camera_toggle_requested.connect(_camera.toggle_view)
	_race.race_finished.connect(_on_race_finished)
	_state_tick = Engine.get_physics_frames()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var pad := event as InputEventJoypadButton
	var restart := (key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ENTER) \
			or (pad != null and pad.pressed and pad.button_index == JOY_BUTTON_START)
	if restart and _state == State.FINISHED:
		get_tree().reload_current_scene()
		return
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F1:
			DebugDraw.enabled = not DebugDraw.enabled
		KEY_F2:
			_toggle_channel(DebugDraw.CH_SUSPENSION)
		KEY_F3:
			_toggle_channel(DebugDraw.CH_FORCES)
		KEY_F4:
			_toggle_channel(DebugDraw.CH_COM)


func _toggle_channel(ch: StringName) -> void:
	DebugDraw.set_channel_enabled(ch, not DebugDraw.is_channel_enabled(ch))


func _physics_process(_delta: float) -> void:
	var tick := Engine.get_physics_frames()
	var f := _input.poll(tick)
	if _state == State.COUNTDOWN:
		# camion immobilise jusqu'au depart
		_neutral.tick = tick
		_truck.set_input(_neutral)
		if tick - _state_tick >= COUNTDOWN_TICKS:
			_race.start()
			_state = State.RACING
			_state_tick = tick
		return
	_truck.set_input(f)
	if f.reset:
		_truck.reset_to(_race.respawn_transform(_truck))
		_camera.snap()


func _process(_delta: float) -> void:
	var elapsed := Engine.get_physics_frames() - _state_tick
	match _state:
		State.COUNTDOWN:
			var n := 3 - floori(elapsed / 60.0)
			_hud.set_center_message(str(maxi(n, 1)), Color(1.0, 0.85, 0.2))
		State.RACING:
			_hud.set_center_message("GO !" if elapsed < GO_TICKS else "", Color(0.4, 1.0, 0.4))
		State.FINISHED:
			var r := _race.racer(_truck)
			_hud.set_center_message("ARRIVEE !\n%s   meilleur tour %s\nStart / Entree : rejouer" % [
				RaceHud.chrono(r.finish_ticks), RaceHud.chrono(r.best_lap)], Color.WHITE)


func _on_race_finished(truck: Truck, _total: int) -> void:
	if truck == _truck:
		_state = State.FINISHED
		_state_tick = Engine.get_physics_frames()
