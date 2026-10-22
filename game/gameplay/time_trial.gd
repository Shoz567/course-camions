class_name TimeTrial
extends Node

## Contre-la-montre (2026-10-20 : « seul sur la piste, tu cours contre le
## fantome de ton meilleur tour enregistre »). Suit le camion du joueur :
##   - enregistre sa pose (position, orientation, angle de la remorque) tous
##     les SAMPLE_EVERY ticks pendant le tour ;
##   - a chaque tour boucle plus vite que le record, le record et ce tour
##     deviennent le fantome, sauvegardes (un fichier par circuit et par
##     categorie de vitesse) : il revient a la course suivante ;
##   - rejoue le fantome au meme instant du tour : une copie transparente du
##     camion, sans collision ni physique (rendu seulement).
## Les durees sont des ticks (le chrono du HUD aussi).

signal new_record(ticks: int)

const SAMPLE_EVERY := 2
## Flottants par pose : position (3), orientation (quaternion, 4), remorque (1).
const STRIDE := 8
const DIR := "user://ghosts"
const GHOST_ALPHA := 0.55

var race: RaceLaps
var truck: Truck
## Meilleur tour (ticks, -1 : aucun) et ses poses.
var best_ticks: int = -1
var ghost_frames: PackedFloat32Array = PackedFloat32Array()
## Sauvegarde sur disque (faux dans les tests : chemin de test a part).
var persist: bool = true
var path: String = ""
var _rec: PackedFloat32Array = PackedFloat32Array()
## Debut du tour enregistre : il change a chaque passage de la ligne (le
## premier compris, qui n'est pas un tour boucle) ; on repart de zero.
var _lap_start_seen: int = -1
var _ghost: Node3D
var _ghost_trailer: Node3D


## Suit `t` dans la course `r` ; record et fantome du circuit `track_id` a la
## categorie `speed_class` (charges s'il y en a).
func setup(r: RaceLaps, t: Truck, track_id: int, speed_class: int) -> void:
	race = r
	truck = t
	if path == "":
		path = "%s/t%d_c%d.ghost" % [DIR, track_id, speed_class]
	_load()
	race.lap_completed.connect(_on_lap)


func _load() -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d: Variant = f.get_var()
	if d is Dictionary and int((d as Dictionary).get("v", 0)) == 1:
		best_ticks = int(d["ticks"])
		ghost_frames = d["frames"]


func _save() -> void:
	if not persist:
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_var({"v": 1, "ticks": best_ticks, "frames": ghost_frames})


func _physics_process(_delta: float) -> void:
	if race == null or truck == null or not race.is_started():
		return
	var r := race.racer(truck)
	if r == null or r.finished:
		return
	var start := _lap_start(r)
	if start != _lap_start_seen:
		_lap_start_seen = start
		_rec.clear()
	if (GameClock.now() - start) % SAMPLE_EVERY != 0:
		return
	var xf := truck.global_transform
	var q := xf.basis.get_rotation_quaternion()
	_rec.append_array(PackedFloat32Array([xf.origin.x, xf.origin.y, xf.origin.z, q.x, q.y, q.z, q.w,
		truck.get_trailer_angle()]))


## Debut du tour en cours, comme le chrono de RaceLaps (le 1er tour part du
## depart, grille comprise).
func _lap_start(r: RaceLaps.Racer) -> int:
	return r.lap_start_tick if r.lap > 0 else race.start_tick


func _on_lap(t: Truck, _lap: int, lap_ticks: int) -> void:
	if t != truck:
		return
	if best_ticks < 0 or lap_ticks < best_ticks:
		best_ticks = lap_ticks
		ghost_frames = _rec.duplicate()
		_save()
		new_record.emit(lap_ticks)


## Pose du fantome `ticks` apres le debut du tour (fin du tour : derniere pose).
func ghost_pose(ticks: float) -> Transform3D:
	var n := ghost_frames.size() / STRIDE
	if n == 0:
		return Transform3D()
	var at := clampf(ticks / SAMPLE_EVERY, 0.0, n - 1.0)
	var i := floori(at)
	var j := mini(i + 1, n - 1)
	var w := at - i
	var a := _frame(i)
	var b := _frame(j)
	return Transform3D(Basis((a[1] as Quaternion).slerp(b[1] as Quaternion, w)), (a[0] as Vector3).lerp(b[0] as Vector3, w))


func _frame(i: int) -> Array:
	var k := i * STRIDE
	var f := ghost_frames
	return [Vector3(f[k], f[k + 1], f[k + 2]), Quaternion(f[k + 3], f[k + 4], f[k + 5], f[k + 6]), f[k + 7]]


func _process(_delta: float) -> void:
	if race == null or truck == null or ghost_frames.is_empty() or not race.is_started():
		if _ghost != null:
			_ghost.visible = false
		return
	var r := race.racer(truck)
	if r == null or r.finished:
		if _ghost != null:
			_ghost.visible = false
		return
	if _ghost == null:
		_build_ghost()
		if _ghost == null:
			return
	var t := float(GameClock.now() - _lap_start(r)) + Engine.get_physics_interpolation_fraction()
	_ghost.global_transform = ghost_pose(t)
	_ghost.visible = true
	if _ghost_trailer != null:
		var k := clampi(floori(t / SAMPLE_EVERY), 0, ghost_frames.size() / STRIDE - 1)
		_ghost_trailer.rotation.y = ghost_frames[k * STRIDE + 7]


## Copie transparente du camion (tracteur, remorque sur son pivot).
func _build_ghost() -> void:
	var visual := truck.get_node_or_null(^"Visual") as TruckVisual
	if visual == null:
		return
	_ghost = Node3D.new()
	_ghost.name = "Ghost"
	_ghost.top_level = true
	add_child(_ghost)
	var cab := visual.make_wreck_copy()
	_ghost.add_child(cab)
	var pivot := visual.get_node_or_null(NodePath(TruckVisual.TRAILER_PIVOT)) as Node3D
	var trailer := visual.make_trailer_copy()
	if trailer != null and pivot != null:
		var holder := Node3D.new()
		holder.transform = visual.transform * pivot.transform
		_ghost.add_child(holder)
		holder.add_child(trailer)
		_ghost_trailer = holder
	for n in _ghost.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		g.transparency = GHOST_ALPHA
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func ghost_visible() -> bool:
	return _ghost != null and _ghost.visible


## Bandeau du HUD : le record (ou son absence).
func ticker_text() -> String:
	if best_ticks < 0:
		return "CONTRE-LA-MONTRE  ·  pas encore de record : ton premier tour fera le fantôme"
	return "CONTRE-LA-MONTRE  ·  RECORD %s  ·  FANTÔME EN PISTE" % RaceHud.chrono(best_ticks)
