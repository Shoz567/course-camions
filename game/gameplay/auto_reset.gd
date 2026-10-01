class_name AutoReset
extends Node

## Reset automatique (tache 2.6). Replace sur la chaussee, dans le sens de
## course (TrackBlockout.get_respawn_transform), un camion :
##   - reste `zone_ticks` dans une zone de reset (hors piste, au-dela des murs) ;
##   - couche ou retourne (inclinaison > flipped_tilt_deg) et quasi immobile
##     pendant `flipped_ticks`.
## Durees en ticks (CLAUDE.md §7). Le reset manuel reste celui du joueur.

signal truck_reset(truck: Truck, reason: StringName)

@export var track: TrackBlockout
@export var zone_ticks: int = 30
@export var flipped_ticks: int = 120
@export var flipped_tilt_deg: float = 70.0
@export var flipped_speed_kmh: float = 10.0
## Optionnel : fournit la transformation de reapparition (Truck -> Transform3D),
## par exemple RaceLaps.respawn_transform, qui ne fait jamais sauter de
## checkpoint. Par defaut : la piste, au plus pres.
var respawn_provider: Callable

var _trucks: Array[Truck] = []
var _zones: Dictionary = {}       # Truck -> nombre de zones chevauchees
var _in_zone: Dictionary = {}     # Truck -> ticks passes en zone
var _flipped: Dictionary = {}     # Truck -> ticks passes couche


func _ready() -> void:
	if track != null:
		track.truck_entered_reset_zone.connect(_on_entered)
		track.truck_exited_reset_zone.connect(_on_exited)


## Surveille ce camion.
func watch(truck: Truck) -> void:
	if not _trucks.has(truck):
		_trucks.append(truck)
		_zones[truck] = 0
		_in_zone[truck] = 0
		_flipped[truck] = 0


func _on_entered(body: Node3D) -> void:
	if _zones.has(body):
		_zones[body] += 1


func _on_exited(body: Node3D) -> void:
	if _zones.has(body):
		_zones[body] = maxi(0, _zones[body] - 1)


func _physics_process(_delta: float) -> void:
	for t in _trucks:
		_in_zone[t] = _in_zone[t] + 1 if _zones[t] > 0 else 0
		var tilt := rad_to_deg(t.global_transform.basis.y.normalized().angle_to(Vector3.UP))
		var slow := t.linear_velocity.length() * 3.6 < flipped_speed_kmh
		_flipped[t] = _flipped[t] + 1 if tilt > flipped_tilt_deg and slow else 0
		if _in_zone[t] >= zone_ticks:
			_reset(t, &"hors_piste")
		elif _flipped[t] >= flipped_ticks:
			_reset(t, &"retourne")


func _reset(t: Truck, reason: StringName) -> void:
	var xf: Transform3D = respawn_provider.call(t) if respawn_provider.is_valid() 			else track.get_respawn_transform(t.global_position)
	t.reset_to(xf)
	_in_zone[t] = 0
	_flipped[t] = 0
	truck_reset.emit(t, reason)
