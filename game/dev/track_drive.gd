extends Node3D

## Scene de test de la piste n°1 (developpement) : un camion, la piste, la
## camera de poursuite, l'input local (manette + clavier).
##
##   RT / R2 ou Z (W)    gaz            stick gauche ou Q D   direction
##   LT / L2 ou S        frein, puis marche arriere a l'arret
##   A / Croix, Espace   frein a main (drift)
##   Y / Triangle ou R   reset : sur la chaussee, dans le sens de course
##   F1 .. F4            traces de debug
##
## Chrono au tour : derive du compteur de ticks (CLAUDE.md §7), passage de la
## ligne detecte par la progression le long de la ligne centrale. Les vrais
## checkpoints et la regle des tours sont les taches 2.3 et 2.5.

@onready var _track: TrackBlockout = $Track01
@onready var _truck: Truck = $Truck
@onready var _input: LocalInputSource = $LocalInput
@onready var _camera: ChaseCamera = $ChaseCamera
@onready var _hud: Label = $Hud/Label

var _idx: int = -1
var _lap_start_tick: int = -1
var _last_lap: int = -1
var _best_lap: int = -1
var _laps: int = 0


func _ready() -> void:
	# pose initiale d'un camion immobile : pas une teleportation en mouvement
	_truck.global_transform = _track.get_start_transform(0)
	_camera.snap()
	# vue propre par defaut : F1 affiche les traces de debug
	DebugDraw.enabled = false


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
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
	_truck.set_input(f)
	if f.reset:
		_truck.reset_to(_track.get_respawn_transform(_truck.global_position))
		_camera.snap()
	# passage de la ligne : l'echantillon le plus proche repasse de la fin au debut
	var n := _track.sample_count()
	var i := _track.closest_sample(_truck.global_position, _idx)
	if _idx >= 0 and _idx > n * 0.75 and i < n * 0.25:
		if _lap_start_tick >= 0:
			_last_lap = tick - _lap_start_tick
			_laps += 1
			if _best_lap < 0 or _last_lap < _best_lap:
				_best_lap = _last_lap
		_lap_start_tick = tick
	_idx = i


func _process(_delta: float) -> void:
	var tick := Engine.get_physics_frames()
	var pad := _input.pad_name()
	var current := tick - _lap_start_tick if _lap_start_tick >= 0 else -1
	_hud.text = "\n".join([
		"%5.0f km/h" % _truck.get_speed_kmh(),
		"tour %d   en cours %s   dernier %s   meilleur %s" % [
			_laps + 1, _chrono(current), _chrono(_last_lap), _chrono(_best_lap)],
		"manette : %s" % (pad if pad != "" else "aucune (clavier : ZQSD, Espace, R)"),
		"Y / Triangle / R : reset    A / Croix : frein a main    F1 : traces",
	])


## Chrono affiche, derive des ticks : 60 ticks = 1 s.
@warning_ignore("integer_division")
static func _chrono(ticks: int) -> String:
	if ticks < 0:
		return "--:--.--"
	var cs := ticks * 100 / 60
	return "%d:%02d.%02d" % [cs / 6000, (cs / 100) % 60, cs % 100]
