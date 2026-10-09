extends PhysicsTest

## Pas de plaque de boost piege (2026-10-06 : « dans le dernier virage de
## Cyber City, le camion ne tourne pas bien »). La plaque etait 50 m avant
## l'epingle (rayon 140 m) : lance a ~180 km/h (220 en categories rapides),
## le camion ne pouvait ni freiner a temps ni tenir le virage, il filait au
## mur, stick en butee (track-designer.md : « pas de piege invisible »,
## « punir sans frustrer »).
##
## Regle, pour chaque plaque des deux circuits : entre la plaque et chaque
## virage qui suit, assez de place pour freiner de la vitesse de boost jusqu'a
## la vitesse que ce virage permet. Tout vient des mesures (baseline.json,
## METRICS.md) : adherence laterale, freinage 100 -> 0, vitesse max en boost.

## Vitesse max en boost, categorie Normale (METRICS.md, truck_boost_test).
const BOOST_TOP_KMH := 179.0
## Virages concernes : ceux qui obligent a ralentir. Sur ces pistes larges
## (75 m), une courbe plus douce se coupe a la corde (rayon de trajectoire bien
## plus grand que celui de l'axe) ; une epingle ou un demi-tour, non.
const MIN_TURN_DEG := 120.0
## Distance regardee apres la plaque (m).
const LOOK_AHEAD := 600.0
const STEP := 2.0
const TRACKS: PackedStringArray = ["res://tracks/track_01_blockout.tscn", "res://tracks/track_02_playa.tscn"]

var _report: PackedStringArray = []
var _pads: int = 0


func _test_setup() -> void:
	duration_ticks = 1
	var lat_g: Variant = require_baseline("max_lateral_g")
	var braking_m: Variant = require_baseline("braking_100_0_m")
	if lat_g == null or braking_m == null:
		return
	var a_lat := float(lat_g) * TruckSpec.GRAVITY
	var decel := pow(100.0 / 3.6, 2.0) / (2.0 * float(braking_m))
	var v_boost := BOOST_TOP_KMH / 3.6
	for path in TRACKS:
		var track := (load(path) as PackedScene).instantiate() as TrackBlockout
		add_child(track)
		for k in track.boost_pad_count():
			_pads += 1
			var i := track.closest_sample(track.boost_pad_transform(k).origin)
			var d := 0.0
			# plaque posee DANS un virage (grande courbe du pont de Playa) : autre
			# choix de conception, pas le piege vise ; on regarde les virages
			# suivants, a partir de la sortie de celui-ci
			while d <= LOOK_AHEAD and absf(track.curvature(track.sample_ahead(i, d))) > 1e-4:
				d += STEP
			while d <= LOOK_AHEAD:
				var c := absf(track.curvature(track.sample_ahead(i, d)))
				if c > 1e-4:
					# tout le virage : angle total et rayon moyen
					var turn := 0.0
					var length := 0.0
					var sign := signf(track.curvature(track.sample_ahead(i, d)))
					while length < 1000.0:
						var ck := track.curvature(track.sample_ahead(i, d + length))
						if absf(ck) <= 1e-4 or signf(ck) != sign:
							break
						turn += absf(ck) * STEP
						length += STEP
					if turn >= deg_to_rad(MIN_TURN_DEG):
						var v_corner := sqrt(a_lat * length / turn)
						if v_corner < v_boost:
							var need := (v_boost * v_boost - v_corner * v_corner) / (2.0 * decel)
							if d < need:
								_report.append("%s, plaque %d : virage de %.0f deg (rayon %.0f m) a %.0f m (il en faut %.0f pour freiner de %.0f a %.0f km/h)"
									% [path.get_file().get_basename(), k, rad_to_deg(turn), length / turn, d, need,
										BOOST_TOP_KMH, v_corner * 3.6])
							break   # le premier virage limitant suffit : apres, on a deja freine
					d += length
				d += STEP
		track.queue_free()


func _test_finish() -> void:
	check_above("plaques de boost examinees", _pads, 0)
	check("aucune plaque de boost juste avant un virage qu'on ne peut plus tenir", _report.is_empty(),
		" | ".join(_report))
