class_name TargetReticle
extends Control

## Cible des pouvoirs (2026-10-20 : « une sorte de petite cible rouge, un
## crosshair sur la personne qui va prendre le missile ») : un viseur rouge
## pose sur le camion vise (TruckPowers.target_ahead), projete par la camera
## du joueur. Rouge vif quand un pouvoir qui vise est pret, terne sinon ; il
## tourne doucement. Rendu seulement : le HUD lit, il ne decide pas.

## Rayon du viseur (px, avant ui_scale) a 20 m et au loin.
const NEAR_R := 46.0
const FAR_R := 26.0
const RED := Color(1.0, 0.16, 0.2)

var ui_scale: float = 1.0
## Pret : au moins un pouvoir qui vise peut partir.
var live: bool = false
var radius: float = NEAR_R
var _spin: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Pose le viseur en `at` (pixels de la vue), `distance_m` du tireur.
func place(at: Vector2, distance_m: float, is_ready: bool) -> void:
	live = is_ready
	radius = lerpf(NEAR_R, FAR_R, clampf((distance_m - 20.0) / 120.0, 0.0, 1.0)) * ui_scale
	position = at
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_spin = fmod(_spin + delta * 1.6, TAU)
		queue_redraw()


func _draw() -> void:
	var col := RED if live else Color(RED, 0.45)
	var w := maxf(2.0, 3.0 * ui_scale)
	var r := radius
	draw_arc(Vector2.ZERO, r + w, 0.0, TAU, 40, Color(0, 0, 0, 0.45 * col.a), w + 2.0, true)
	# anneau en quatre arcs qui tournent, et quatre crans vers le centre
	for i in 4:
		var a0 := _spin + i * PI / 2.0 + 0.18
		draw_arc(Vector2.ZERO, r, a0, a0 + PI / 2.0 - 0.36, 12, col, w, true)
		var d := Vector2.from_angle(i * PI / 2.0 + PI / 4.0)
		draw_line(d * (r * 0.55), d * (r * 0.85), col, w, true)
	draw_circle(Vector2.ZERO, maxf(2.0, 3.0 * ui_scale), col)
