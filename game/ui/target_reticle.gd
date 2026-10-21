class_name TargetReticle
extends Control

## Cible des pouvoirs (2026-10-20 : « une sorte de petite cible rouge, un
## crosshair sur la personne qui va prendre le missile ») : un viseur rouge
## pose sur le camion vise (TruckPowers.target_ahead), projete par la camera
## du joueur. Il tourne doucement. Rendu seulement : le HUD lit, il ne decide
## pas.
## Portee (2026-10-20 : « le viseur indique la portee ») : rouge vif quand un
## pouvoir pret l'atteint, gris quand les pouvoirs prets sont trop courts ;
## en recharge, pas de viseur (2026-10-21) ; une fleche par emplacement (◄ gauche, ► droite)
## allumee si son pouvoir est pret et a portee, et la distance dessous.
## Retour de coup : une croix eclate un instant quand un coup touche (flash) ;
## un changement de cible le fait battre (pulse).

enum State { READY, OUT_OF_RANGE }

## Rayon du viseur (px, avant ui_scale) a 20 m et au loin.
const NEAR_R := 46.0
const FAR_R := 26.0
const RED := Color(1.0, 0.16, 0.2)
const GREY := Color(0.82, 0.84, 0.9)
## Duree de la croix de touche et du battement (s).
const FLASH_S := 0.16
const PULSE_S := 0.22

var ui_scale: float = 1.0
var state: State = State.READY
## Fleches allumees : emplacement gauche, droit (pret et a portee) ; -1 :
## emplacement sans pouvoir qui vise (pas de fleche).
var slots: PackedInt32Array = PackedInt32Array([-1, -1])
var distance_m: float = 0.0
var radius: float = NEAR_R
var _spin: float = 0.0
var _flash: float = 0.0
var _pulse: float = 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = UiKit.font(800)


## Pose le viseur en `at` (pixels de la vue), a `dist` m du tireur.
func place(at: Vector2, dist: float, s: State, lit: PackedInt32Array) -> void:
	state = s
	slots = lit
	distance_m = dist
	radius = lerpf(NEAR_R, FAR_R, clampf((dist - 20.0) / 120.0, 0.0, 1.0)) * ui_scale
	position = at
	visible = true
	queue_redraw()


## Un coup vient de toucher.
func flash() -> void:
	_flash = FLASH_S


## La cible vient de changer.
func pulse() -> void:
	_pulse = PULSE_S


func flashing() -> bool:
	return _flash > 0.0


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_pulse = maxf(0.0, _pulse - delta)
	if visible:
		_spin = fmod(_spin + delta * 1.6, TAU)
		queue_redraw()


func _color() -> Color:
	return RED if state == State.READY else Color(GREY, 0.7)


func _draw() -> void:
	var col := _color()
	var w := maxf(2.0, 3.0 * ui_scale)
	var r := radius * (1.0 + 0.35 * _pulse / PULSE_S)
	draw_arc(Vector2.ZERO, r + w, 0.0, TAU, 40, Color(0, 0, 0, 0.45 * col.a), w + 2.0, true)
	# anneau en quatre arcs qui tournent, et quatre crans vers le centre
	for i in 4:
		var a0 := _spin + i * PI / 2.0 + 0.18
		draw_arc(Vector2.ZERO, r, a0, a0 + PI / 2.0 - 0.36, 12, col, w, true)
		var d := Vector2.from_angle(i * PI / 2.0 + PI / 4.0)
		draw_line(d * (r * 0.55), d * (r * 0.85), col, w, true)
	draw_circle(Vector2.ZERO, maxf(2.0, 3.0 * ui_scale), col)
	# croix de touche : quatre traits blancs qui jaillissent du centre
	if _flash > 0.0:
		var k := _flash / FLASH_S
		var white := Color(1, 1, 1, k)
		for i in 4:
			var d := Vector2.from_angle(i * PI / 2.0 + PI / 4.0)
			draw_line(d * r * (0.2 + 0.3 * (1.0 - k)), d * r * (0.75 + 0.5 * (1.0 - k)), white, w * 1.4, true)
	# fleches des emplacements et distance
	var fs := maxi(9, roundi(15 * ui_scale))
	for k in 2:
		if slots[k] < 0:
			continue
		var on := slots[k] == 1
		var arrow := "◄" if k == 0 else "►"
		var aw := _font.get_string_size(arrow, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := (-r - 6.0 * ui_scale - aw) if k == 0 else (r + 6.0 * ui_scale)
		var c := RED if on else Color(GREY, 0.35)
		draw_string_outline(_font, Vector2(x, fs * 0.36), arrow, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.7))
		draw_string(_font, Vector2(x, fs * 0.36), arrow, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
	var txt := "%d m" % roundi(distance_m)
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(-tw / 2.0, r + w + fs * 1.1)
	draw_string_outline(_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.7))
	draw_string(_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
