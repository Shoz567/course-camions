extends PhysicsTest

## Decor Cyber City (purement visuel : il ne doit rien changer au jeu).
##   - environnement de nuit partage : ciel bleu nuit a horizon pourpre,
##     brouillard, glow ;
##   - piste n°1 : neon cyan (gauche) et magenta (droite) sur les deux
##     glissieres ; 3 arches lumineuses au-dessus de la chaussee (hauteur libre
##     >= arch_height), piliers au-dela des murs, aucune collision ;
##   - ville : au moins 250 tours, TOUTES au-dela des zones de reset (un camion
##     qui sort retombe dans une zone avant d'atteindre une tour), aucune qui
##     en chevauche une autre, aucun corps physique, trois MultiMesh sans
##     ombre portee (trois appels de rendu) ;
##   - showroom du menu : ville en contrebas, dessus du plateau sur la couche 1 ;
##   - phares des camions sans ombres (cout du rendu a 4 vues).
## La ville n'est generee en headless que parce que ce test le force.

var _track: TrackBlockout
var _showroom: Showroom
var _build_ms: float = 0.0


func _test_setup() -> void:
	duration_ticks = 1
	CityBackdrop.generate_in_headless = true
	var t0 := Time.get_ticks_usec()
	_track = (load("res://tracks/track_01_blockout.tscn") as PackedScene).instantiate() as TrackBlockout
	add_child(_track)
	_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_showroom = Showroom.new()
	add_child(_showroom)


func _test_finish() -> void:
	CityBackdrop.generate_in_headless = false
	_check_environment()
	_check_track()
	_check_city()
	_check_showroom()
	var truck := (load("res://vehicles/truck.tscn") as PackedScene).instantiate() as Truck
	var lights := truck.get_node_or_null("Headlights") as SpotLight3D
	check("camion : phares (SpotLight3D) sans ombres", lights != null and not lights.shadow_enabled)
	truck.free()


func _check_environment() -> void:
	var env := load("res://tracks/cyber_night.tres") as Environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	check("nuit : glow et brouillard actifs", env.glow_enabled and env.fog_enabled)
	check("nuit : ciel bleu nuit en haut", sky.sky_top_color.get_luminance() < 0.05
		and sky.sky_top_color.b > sky.sky_top_color.r, str(sky.sky_top_color))
	var hz := sky.sky_horizon_color
	check("nuit : horizon pourpre", hz.r > hz.g and hz.b > hz.g, str(hz))
	var fog := env.fog_light_color
	check("nuit : brouillard bleute", fog.b > fog.r and fog.g > fog.r, str(fog))


func _check_track() -> void:
	var walls := _track.get_node("Walls")
	var left := walls.get_node_or_null("NeonLeft") as MeshInstance3D
	var right := walls.get_node_or_null("NeonRight") as MeshInstance3D
	check("glissieres : neon cyan a gauche, magenta a droite", left != null and right != null
		and left.material_override == preload("res://tracks/materials/neon_cyan.tres")
		and right.material_override == preload("res://tracks/materials/neon_magenta.tres"))
	check("3 arches", _track.arch_count() == 3, "%d" % _track.arch_count())
	var arches := _track.get_node("Arches")
	var bodies := arches.find_children("*", "CollisionObject3D", true, false)
	check("arches : aucune collision (ni camion, ni camera)", bodies.is_empty(), "%d corps" % bodies.size())
	var clearance := INF
	var pillars_out := true
	for k in _track.arch_count():
		var arch := arches.get_node("Arch%d" % k) as Node3D
		var i := _track.index_at_s(_track.arch_s(k))
		var road := _track.sample_position(i)
		for mi: Node in arch.get_children():
			var m := mi as MeshInstance3D
			if m == null:
				continue
			var box := (m.mesh as BoxMesh).size
			var lateral := absf(m.position.x)
			if lateral < 1.0 or lateral + box.x / 2.0 < _track.width / 2.0 + 0.5:
				# au-dessus de la chaussee : la poutre et ses tubes
				clearance = minf(clearance, arch.global_position.y + m.position.y - box.y / 2.0 - road.y)
			elif box.y > 10.0 and lateral - box.x / 2.0 < _track.width / 2.0 + _track.wall_thickness:
				pillars_out = false
	check_above("arches : hauteur libre au-dessus de la chaussee (m)", clearance, _track.arch_height - 0.5)
	check("arches : piliers au-dela des murs", pillars_out)


func _check_city() -> void:
	var city := _track.get_node("CityBackdrop").get_child(0) as Node3D
	check("ville generee", city != null)
	if city == null:
		return
	var mms := city.find_children("*", "MultiMeshInstance3D", false, false)
	var no_shadow := true
	for m: Node in mms:
		no_shadow = no_shadow and (m as MultiMeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	check("ville : 3 MultiMesh sans ombre portee", mms.size() == 3 and no_shadow, "%d" % mms.size())
	check("ville : aucun corps physique", city.find_children("*", "CollisionObject3D", true, false).is_empty())
	# emprises relues dans les donnees du generateur (le rendu factice du
	# headless ne garde pas les transformations des MultiMesh)
	var towers: Array = city.get_meta(&"buildings", [])
	var n := towers.size()
	var clear := _track.width / 2.0 + _track.wall_thickness + _track.wall_lean + _track.reset_zone_margin \
			+ _track.reset_zone_depth
	var worst := INF
	var fp := PackedVector3Array()
	for k in n:
		var xf: Transform3D = towers[k]
		var w := xf.basis.x.length()
		var d := xf.basis.z.length()
		var radius := 0.5 * sqrt(w * w + d * d)
		fp.append(Vector3(xf.origin.x, xf.origin.z, radius))
		var c := _track.sample_position(_track.closest_sample(xf.origin))
		worst = minf(worst, Vector2(xf.origin.x - c.x, xf.origin.z - c.z).length() - radius - clear)
	var overlaps := 0
	for a in n:
		for b in range(a + 1, n):
			if Vector2(fp[a].x - fp[b].x, fp[a].y - fp[b].y).length() < fp[a].z + fp[b].z:
				overlaps += 1
	print("  INFO   ville : %d tours, %d antennes, %d enseignes, generee avec la piste en %.0f ms"
		% [n, (city.get_node("Antennas") as MultiMeshInstance3D).multimesh.instance_count,
		(city.get_node("Signs") as MultiMeshInstance3D).multimesh.instance_count, _build_ms])
	check_above("ville : au moins 250 tours", n, 249)
	check_above("ville : toutes les tours au-dela des zones de reset (marge, m)", worst, 0.0)
	check("ville : aucune tour n'en chevauche une autre", overlaps == 0, "%d" % overlaps)


func _check_showroom() -> void:
	var body := _showroom.get_node("PlateCollision") as StaticBody3D
	check("showroom : dessus du plateau sur la couche 1 (suspension)", body != null and body.collision_layer == 1)
	var city := _showroom.find_child("City", false, false) as Node3D
	var towers: Array = city.get_meta(&"buildings", []) if city != null else []
	var below := 0
	for xf: Transform3D in towers:
		below += 1 if xf.origin.y - xf.basis.y.length() / 2.0 < -100.0 else 0
	check("showroom : ville en contrebas (au moins 200 tours au pied du toit)", below >= 200, "%d tours" % below)
