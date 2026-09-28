class_name TrackAutopilot
extends RefCounted

## Pilote de test : suit la ligne de course d'une TrackBlockout en produisant
## des InputFrame, comme un joueur (jamais de force appliquee de l'exterieur).
##
## - Direction : poursuite pure d'un point vise devant (distance croissante avec
##   la vitesse), convertie en stick d'apres le braquage max du camion.
## - Vitesse : en chaque point a venir, vitesse de virage sqrt(a * R), avec
##   a = adherence laterale MESUREE (baseline.json) x marge ; freinage anticipe
##   a decel constante. Deterministe : aucun aleatoire, aucun temps reel.

## Part de l'adherence mesuree utilisee en virage (prudent : le devers et les
## bosses ne sont pas modelises ici).
const GRIP_MARGIN := 0.8
## Deceleration prevue pour anticiper un virage (m/s2), sous le freinage mesure.
const PLAN_DECEL := 6.0
## Distance de planification (m) et pas (m).
const PLAN_DISTANCE := 160.0
const PLAN_STEP := 4.0

var track: TrackBlockout
var truck: Truck
var frame: InputFrame = InputFrame.new()
var index: int = -1
var target_speed: float = 0.0
var _lateral_accel: float


func _init(t: TrackBlockout, tr: Truck, max_lateral_g: float) -> void:
	track = t
	truck = tr
	_lateral_accel = max_lateral_g * GRIP_MARGIN * TruckSpec.GRAVITY


func drive(tick: int) -> InputFrame:
	index = track.closest_sample(truck.global_position, index)
	var v := truck.linear_velocity.length()

	# direction : poursuite pure vers la ligne de course
	var look := 10.0 + v * 0.45
	var j := track.sample_ahead(index, look)
	var aim := track.sample_position(j) + track.sample_right(j) * track.line_offset(j)
	var local := truck.global_transform.affine_inverse() * aim
	var ld2 := maxf(local.x * local.x + local.z * local.z, 1.0)
	var curvature := 2.0 * local.x / ld2
	var wheelbase := TruckSpec.ANCHORS[2].z - TruckSpec.ANCHORS[0].z
	var steer_deg := rad_to_deg(atan(curvature * wheelbase))
	frame.tick = tick
	frame.steer = clampf(steer_deg / maxf(truck.get_max_steer_deg(), 0.5), -1.0, 1.0)

	# vitesse : la plus contraignante des vitesses de virage a venir
	target_speed = INF
	var d := 0.0
	while d <= PLAN_DISTANCE:
		var k := track.sample_ahead(index, d)
		var c := absf(track.curvature(k))
		if c > 1e-4:
			var v_corner := sqrt(_lateral_accel / c)
			target_speed = minf(target_speed, sqrt(v_corner * v_corner + 2.0 * PLAN_DECEL * d))
		d += PLAN_STEP
	var err := target_speed - v
	frame.throttle = clampf(err / 3.0, 0.0, 1.0)
	frame.brake = clampf(-err / 3.0, 0.0, 1.0)
	frame.handbrake = false
	frame.reset = false
	return frame
