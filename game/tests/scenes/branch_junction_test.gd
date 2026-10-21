extends PhysicsTest

## Jonctions des raccourcis (2026-10-21 : « les raccourcis n'atterrissent pas
## au niveau de la piste, ça fait une sorte de muret ; quand ils croisent la
## piste, des problèmes de texture et de collision ») : les 3 circuits, chaque
## raccourci, des couloirs tous les 2 m en travers de sa chaussee, sondes
## (rayons vers le bas) tous les 0,5 m de 10 m avant son entree a 10 m apres
## sa sortie :
##   A. aucune chaussee posee sur une autre : la ou la piste et le raccourci
##      sont tous deux sous la sonde, le raccourci n'est jamais au-dessus, et
##      a plus de 25 cm du bord de la piste, il n'y est plus (sa chaussee ne
##      passe sous la piste que sur 20 cm, pour ne pas laisser de fente ;
##      avant : 3 cm au-dessus sur ~100 m a chaque bout, ca scintillait) ;
##   B. pas de marche : la pente du sol ne change pas de plus de 5 cm d'une
##      sonde a la suivante (avant : jusqu'a 1,7 m sur la marina) ;
##   C. la sonde ne rencontre que de la chaussee (ni mur, ni sol), et entre
##      ses deux jonctions, celle du raccourci (il ne croise pas la piste).
## Le tremplin et le vide d'un saut (branch_jump_test) sont hors mesure.

const TRACKS := ["res://tracks/track_01_blockout.tscn", "res://tracks/track_02_playa.tscn",
	"res://tracks/track_03_sakura.tscn"]
const STEP_M := 0.5
const KINK_M := 0.05

var _tracks: Array[TrackBlockout] = []
var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 6
	for k in TRACKS.size():
		var t := (load(TRACKS[k]) as PackedScene).instantiate() as TrackBlockout
		t.position = Vector3(k * 20000.0, 0.0, 0.0)
		add_child(t)
		_tracks.append(t)


## Ce que traverse un rayon vertical en `p` : [[nom, hauteur], ...] de haut en bas.
func _hits(space: PhysicsDirectSpaceState3D, p: Vector3) -> Array:
	var out := []
	var ex: Array[RID] = []
	for n in 4:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 25.0, p + Vector3.DOWN * 40.0, 1, ex)
		var h := space.intersect_ray(q)
		if h.is_empty():
			break
		out.append([String((h["collider"] as Node).name), (h["position"] as Vector3).y])
		ex.append(h["rid"])
	return out


static func _is_road(body: String) -> bool:
	return body == "Road" or (body.begins_with("Branch") and body.ends_with("Road"))


func _test_tick(t: int) -> void:
	if t != 4:
		return
	var space := get_world_3d().direct_space_state
	var overlap := []
	var kink := [0.0, ""]
	var foreign := []
	for ti in _tracks.size():
		var tr := _tracks[ti]
		for kb in tr.branch_count():
			var w := tr.branch_width_of(kb)
			var length := tr.branch_length(kb)
			var tag := "%s/%d" % [TRACKS[ti].get_file().get_basename(), kb]
			# decale de la grille du maillage (un rayon pile sur une arete peut la rater)
			var lat := -w / 2.0 + 2.13
			while lat <= w / 2.0 - 2.0:
				var ys := PackedFloat32Array()
				var d := -10.0 + 0.137
				while d <= length + 10.0:
					var u := d / length
					var jump := tr.branch_jump(kb)
					if jump.x >= 0.0 and u > jump.x - (TrackBlockout.BRANCH_RAMP_M + 2.0) / length and u < jump.y + 1.0 / length:
						ys.append(NAN)
						d += STEP_M
						continue
					var p := tr.branch_frame(kb, u, lat, 0.0).origin + tr.position
					var hs := _hits(space, p)
					var top := String(hs[0][0]) if not hs.is_empty() else "rien"
					var road_y := NAN
					var br_y := NAN
					for h: Array in hs:
						if String(h[0]) == "Road" and is_nan(road_y):
							road_y = float(h[1])
						elif _is_road(String(h[0])) and String(h[0]) != "Road" and is_nan(br_y):
							br_y = float(h[1])
					if not is_nan(road_y) and not is_nan(br_y):
						var depth := -float((tr.call("_branch_main", kb, p - tr.position, clampf(u, 0.0, 1.0)) as Vector2).x)
						if br_y > road_y + 0.002 or depth > 0.25:
							overlap.append("%s d=%.0f lat=%.0f dy=%.3f dans la piste de %.2f m" % [tag, d, lat,
								br_y - road_y, depth])
					# entre les jonctions (la ou ses deux bords sont loin de la piste)
					var middle := tr.on_branch(p - tr.position, -w / 2.0) == kb \
							and _far_from_road(tr, kb, u, w)
					if not _is_road(top) or (middle and top == "Road"):
						foreign.append("%s d=%.0f lat=%.0f : %s" % [tag, d, lat, top])
						ys.append(NAN)
					else:
						ys.append(float(hs[0][1]))
					d += STEP_M
				for k in range(2, ys.size()):
					if is_nan(ys[k]) or is_nan(ys[k - 1]) or is_nan(ys[k - 2]):
						continue
					var bend := absf((ys[k] - ys[k - 1]) - (ys[k - 1] - ys[k - 2]))
					if bend > float(kink[0]):
						kink = [bend, "%s d=%.1f lat=%.0f" % [tag, -10.0 + k * STEP_M, lat]]
				lat += 2.0
	_seen["a"] = overlap
	_seen["b"] = kink
	_seen["c"] = foreign


## Les deux bords du raccourci k, a sa part u, sont a plus de 5 m de la piste
## (tests : l'axe du raccourci de chaque cote, juge par la piste elle-meme).
func _far_from_road(tr: TrackBlockout, kb: int, u: float, w: float) -> bool:
	if u <= 0.0 or u >= 1.0:
		return false
	for side: float in [-1.0, 1.0]:
		var e := tr.branch_frame(kb, u, side * (w / 2.0 + 5.0), 0.0).origin
		var i := tr.closest_sample(e)
		if i >= 0 and absf((e - tr.sample_position(i)).dot(tr.sample_right(i))) < tr.width / 2.0 \
				and tr.sample_position(i).distance_to(e) < tr.width:
			return false
	return true


func _test_finish() -> void:
	var a: Array = _seen.get("a", ["pas de mesure"])
	check("A aucune chaussee posee sur une autre", a.is_empty(), "%d : %s" % [a.size(), a.slice(0, 3)])
	var b: Array = _seen.get("b", [INF, ""])
	check_below("B pas de marche : saut de pente max (m) %s" % b[1], float(b[0]), KINK_M)
	var c: Array = _seen.get("c", ["pas de mesure"])
	check("C rien que de la chaussee, celle du raccourci entre ses jonctions", c.is_empty(),
		"%d : %s" % [c.size(), c.slice(0, 3)])
