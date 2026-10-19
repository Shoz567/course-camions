class_name AutoReset
extends Node

## Reset automatique (tache 2.6). Replace sur la chaussee, dans le sens de
## course (TrackBlockout.get_respawn_transform), un camion :
##   - reste `zone_ticks` dans une zone de reset (hors piste, au-dela des murs) ;
##   - couche ou retourne (inclinaison > flipped_tilt_deg) et quasi immobile
##     pendant `flipped_ticks`.
## Hors piste se mesure aussi a la geometrie (2026-10-16 : « au lieu de se
## rediriger on atterrit hors piste et kaboom le camion ») : les zones
## s'arretent a reset_zone_height au-dessus du sol et a reset_zone_depth du
## mur ; sorti d'une corniche a 47 m, le camion tombait 4 s avant d'y entrer,
## et loin des murs il s'ecrasait sur le decor. Au-dela des murs (de
## off_track_margin) ou sous la chaussee (de below_road_m), il est hors piste
## en l'air comme au sol, et ne prend plus de degats (TruckHealth.off_track).
## Chute (2026-10-19 : « sortie de route : chute + explosion quand le camion
## touche le sol ») : un camion hors piste n'est plus replace. Il tombe, et
## explose (TruckHealth.crash) des qu'il touche quelque chose, une roue ou la
## caisse, apres fall_min_ticks hors piste ; au plus tard apres
## fall_max_ticks. Son epave reste la ; il reapparait sur la piste 3 s plus
## tard (TruckHealth). Sans TruckHealth, ou fall_explodes faux : replace
## apres zone_ticks, comme avant.
## Plus dur de sortir (2026-10-19) : un camion en l'air dont la trajectoire
## franchirait le mur (bord vise a air_return_horizon_s) est rabattu vers la
## piste, au plus air_return_accel m/s2 en travers (force proportionnelle a la
## masse, desactivable : air_return). Seulement tant qu'il n'a pas depasse le
## haut du mur de plus de air_return_capture_m.
## Durees en ticks (CLAUDE.md §7). Le reset manuel reste celui du joueur.

signal truck_reset(truck: Truck, reason: StringName)
## Tombe hors piste et touche le sol : detruit (TruckHealth.crash).
signal truck_crashed(truck: Truck)

@export var track: TrackBlockout
@export var zone_ticks: int = 30
@export var flipped_ticks: int = 120
@export var flipped_tilt_deg: float = 70.0
@export var flipped_speed_kmh: float = 10.0
## Au-dela du mur exterieur (m) : hors piste.
@export var off_track_margin: float = 3.0
## Sous la chaussee (m) : tombe d'un pont, d'une corniche.
@export var below_road_m: float = 6.0
@export var fall_explodes: bool = true
@export var fall_min_ticks: int = 6
@export var fall_max_ticks: int = 240
@export var air_return: bool = true
@export var air_return_accel: float = 30.0
@export var air_return_horizon_s: float = 0.6
## Marge gardee en deca du mur (m) : la trajectoire visee retombe sur la route.
@export var air_return_margin: float = 3.0
@export var air_return_capture_m: float = 4.0
## Optionnel : fournit la transformation de reapparition (Truck -> Transform3D),
## par exemple RaceLaps.respawn_transform, qui ne fait jamais sauter de
## checkpoint. Par defaut : la piste, au plus pres.
var respawn_provider: Callable

var _trucks: Array[Truck] = []
## Client en ligne : son camion predit n'a que l'aide en l'air (le host
## decide des remises en piste et des chutes).
var _assist_only: Array[Truck] = []
var _zones: Dictionary = {}       # Truck -> nombre de zones chevauchees
var _in_zone: Dictionary = {}     # Truck -> ticks passes en zone
var _flipped: Dictionary = {}     # Truck -> ticks passes couche
var _hint: Dictionary = {}        # Truck -> echantillon de piste le plus proche


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
		_hint[truck] = -1


## Aide en l'air seulement (camion predit d'un client en ligne).
func watch_assist(truck: Truck) -> void:
	if not _assist_only.has(truck):
		_assist_only.append(truck)
		_hint[truck] = -1


func _on_entered(body: Node3D) -> void:
	if _zones.has(body):
		_zones[body] += 1


func _on_exited(body: Node3D) -> void:
	if _zones.has(body):
		_zones[body] = maxi(0, _zones[body] - 1)


func _physics_process(_delta: float) -> void:
	for t in _assist_only:
		if is_instance_valid(t) and not t.is_wrecked():
			_air_return(t)
	for t in _trucks:
		if t.is_wrecked():
			# epave (0 PV) : sa reapparition est l'affaire de TruckHealth
			_in_zone[t] = 0
			_flipped[t] = 0
			continue
		_air_return(t)
		var off: bool = _zones[t] > 0 or is_off_track(t)
		var health := TruckHealth.of(t)
		if health != null:
			health.off_track = off
		_in_zone[t] = _in_zone[t] + 1 if off else 0
		if off and fall_explodes and health != null:
			# chute : explosion au premier contact, jamais de remise en piste
			var landed := t.wheels_on_ground() > 0 or t.get_contact_count() > 0
			if (landed and _in_zone[t] >= fall_min_ticks) or _in_zone[t] >= fall_max_ticks:
				health.crash(&"chute")
				_in_zone[t] = 0
				_flipped[t] = 0
				truck_crashed.emit(t)
			continue
		var tilt := rad_to_deg(t.global_transform.basis.y.normalized().angle_to(Vector3.UP))
		var slow := t.linear_velocity.length() * 3.6 < flipped_speed_kmh
		_flipped[t] = _flipped[t] + 1 if tilt > flipped_tilt_deg and slow else 0
		if _in_zone[t] >= zone_ticks:
			_reset(t, &"hors_piste")
		elif _flipped[t] >= flipped_ticks:
			_reset(t, &"retourne")


## En l'air et vers l'exterieur : la ou il sera dans air_return_horizon_s,
## en travers ; au-dela du bord vise, une acceleration vers la piste.
func _air_return(t: Truck) -> void:
	if not air_return or track == null or t.wheels_on_ground() > 0 or t.freeze:
		return
	var p := t.global_position
	var i := track.closest_sample(p, int(_hint.get(t, -1)))
	_hint[t] = i
	var right := track.sample_right(i)
	var lateral := (p - track.sample_position(i)).dot(right)
	var v_lat := t.linear_velocity.dot(right)
	var wall := track.width / 2.0
	if absf(lateral) > wall + track.wall_thickness + air_return_capture_m:
		return    # deja loin : il tombe
	if signf(v_lat) != signf(lateral):
		return    # revient deja vers la piste
	var ahead := absf(lateral + v_lat * air_return_horizon_s)
	var edge := wall - air_return_margin
	if ahead <= edge:
		return
	# vitesse en travers a annuler pour retomber au bord vise, sur l'horizon
	var need := (ahead - edge) / air_return_horizon_s
	var a := minf(need / air_return_horizon_s, air_return_accel)
	t.apply_central_force(-right * signf(lateral) * a * t.mass)


## Vrai si le camion est au-dela des murs ou sous la chaussee.
func is_off_track(t: Truck) -> bool:
	if track == null:
		return false
	var p := t.global_position
	var i := track.closest_sample(p, int(_hint.get(t, -1)))
	if track.sample_position(i).distance_to(p) > 60.0:
		i = track.closest_sample(p)    # teleporte : recherche complete
	_hint[t] = i
	var d := p - track.sample_position(i)
	var edge := track.width / 2.0 + track.wall_thickness + track.wall_lean + off_track_margin
	return absf(d.dot(track.sample_right(i))) > edge or d.dot(track.sample_up(i)) < -below_road_m


func _reset(t: Truck, reason: StringName) -> void:
	var xf: Transform3D = respawn_provider.call(t) if respawn_provider.is_valid() 			else track.get_respawn_transform(t.global_position)
	t.reset_to(xf)
	_in_zone[t] = 0
	_flipped[t] = 0
	truck_reset.emit(t, reason)
