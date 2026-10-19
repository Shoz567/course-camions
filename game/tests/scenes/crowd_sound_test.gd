extends PhysicsTest

## Foule des tribunes (tache 7.3) : la boucle (duree, crete 0,8, raccord sans
## claquement, presque rien sous 100 Hz : ce sont des voix, deux clameurs par
## boucle) ; chaque tribune de Cyber City porte sa rumeur 3D, au milieu des
## gradins, audible de pres et eteinte au loin.

var _scene: Node3D


func _test_setup() -> void:
	duration_ticks = 20
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	# le decor ne se construit pas en headless, sauf a la demande
	for d: Node in _scene.find_children("RaceDecor", "", true, false):
		d.set("generate_in_headless", true)
	add_child(_scene)


func _test_finish() -> void:
	var s := CrowdSound.build()
	var peak := 0.0
	var step := 0.0
	for i in s.size():
		peak = maxf(peak, absf(s[i]))
		if i > 0:
			step = maxf(step, absf(s[i] - s[i - 1]))
	var seam := absf(s[0] - s[s.size() - 1])
	check("boucle : %.0f s, crete %.2f, raccord %.3f <= pas max %.3f" % [CrowdSound.LOOP_S, peak, seam, step],
		s.size() == roundi(CrowdSound.RATE * CrowdSound.LOOP_S) and absf(peak - 0.8) < 0.01 and seam <= step)
	# graves : passe-bas a ~80 Hz, energie comparee au total
	var low := 0.0
	var e_low := 0.0
	var e_all := 0.0
	for v in s:
		low += (v - low) * 0.023
		e_low += low * low
		e_all += v * v
	check("des voix : moins de 3 % de l'energie sous ~80 Hz", e_low / e_all < 0.03, "%.4f" % (e_low / e_all))
	# clameurs : huitiemes 1-2 et 5-6 (autour de 1/4 et 3/4) plus forts que 0, 3-4, 7
	var e := PackedFloat32Array()
	e.resize(8)
	for i in s.size():
		e[mini(i * 8 / s.size(), 7)] += s[i] * s[i]
	check("deux clameurs par boucle", e[1] + e[2] > 1.4 * (e[0] + e[3]) and e[5] + e[6] > 1.4 * (e[4] + e[7]), str(e))
	var voices := _scene.find_children("CrowdSound", "", true, false).filter(func(n: Node) -> bool: return n is CrowdSound)
	check("Cyber City : une rumeur par tribune (4)", voices.size() == 4, str(voices.size()))
	var ok := not voices.is_empty()
	for v: Node in voices:
		var c := v as CrowdSound
		ok = ok and c.unit_size == CrowdSound.UNIT_M and c.max_distance == CrowdSound.MAX_M and c.position.y > 2.0
	check("rumeurs : portee %.0f / %.0f m, au-dessus des gradins bas" % [CrowdSound.UNIT_M, CrowdSound.MAX_M], ok)
