extends PhysicsTest

## Ambiance des circuits (tache 7.3) : pour chaque theme, une boucle de
## LOOP_S s, crete 0,8, sans claquement au raccord (le saut entre la fin et
## le debut ne depasse pas le plus grand pas a l'interieur), deux boucles
## differentes ; sur la plage, les vagues s'entendent (deux bosses
## d'energie grave par boucle) ; la course pose l'ambiance de son circuit.
## Sakura (2026-10-19) : brise, clochettes, oiseau et cloche, sa propre boucle.

var _scene: Node3D


func _test_setup() -> void:
	duration_ticks = 20
	_scene = (load("res://dev/race_playa.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	add_child(_scene)


func _test_finish() -> void:
	var city := AmbienceSound.build(TrackTheme.Id.CYBER_CITY)
	var playa := AmbienceSound.build(TrackTheme.Id.PLAYA_DEL_SOL)
	var sakura := AmbienceSound.build(TrackTheme.Id.SAKURA)
	for pair: Array in [["Cyber City", city], ["Playa Del Sol", playa], ["Sakura", sakura]]:
		var s: PackedFloat32Array = pair[1]
		var peak := 0.0
		var step := 0.0
		var finite := true
		for i in s.size():
			peak = maxf(peak, absf(s[i]))
			finite = finite and is_finite(s[i])
			if i > 0:
				step = maxf(step, absf(s[i] - s[i - 1]))
		var seam := absf(s[0] - s[s.size() - 1])
		check("%s : %.0f s, crete %.2f, raccord %.3f <= pas max %.3f" % [pair[0], AmbienceSound.LOOP_S, peak, seam, step],
			s.size() == roundi(AmbienceSound.RATE * AmbienceSound.LOOP_S) and finite
			and absf(peak - 0.8) < 0.01 and seam <= step)
	var same := 0
	for i in range(0, city.size(), 997):
		if absf(city[i] - playa[i]) < 0.0001:
			same += 1
	check("deux ambiances differentes", same < 5, "%d echantillons egaux" % same)
	var same3 := 0
	for i in range(0, sakura.size(), 997):
		if absf(sakura[i] - playa[i]) < 0.0001 or absf(sakura[i] - city[i]) < 0.0001:
			same3 += 1
	check("Sakura : une troisieme ambiance, differente", same3 < 5, "%d echantillons egaux" % same3)
	# vagues : energie grave par huitieme de boucle ; chaque vague (4 s) culmine
	# en son milieu (huitiemes 1-2 et 5-6) et retombe a ses bords (0, 3, 4, 7)
	var e := _eighths(playa)
	check("plage : deux vagues, fortes au milieu, faibles aux bords",
		e[1] + e[2] > 1.5 * (e[0] + e[3]) and e[5] + e[6] > 1.5 * (e[4] + e[7]), str(e))
	var amb := _scene.get_node_or_null(^"Ambience") as AmbienceSound
	check("la course pose l'ambiance de son circuit", amb != null and amb.theme_id == TrackTheme.Id.PLAYA_DEL_SOL)


## Energie de chaque huitieme de boucle, apres un passe-bas (les vagues sont
## graves).
static func _eighths(s: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(8)
	var low := 0.0
	var n := s.size()
	for i in n:
		low += (s[i] - low) * 0.02
		out[mini(i * 8 / n, 7)] += low * low
	return out
