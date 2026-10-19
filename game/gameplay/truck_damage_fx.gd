class_name TruckDamageFx
extends Node3D

## Degats visibles du camion (enfant « DamageFx », purement visuel) :
##   - traces de choc localisees : a chaque impact (mur, camion, remorque
##     larguee), une cicatrice peinte (DamageFx.scar) au point touche - calandre
##     sur un choc frontal, flanc sur un frottement, remorque sur un choc
##     arriere (il suit alors l'articulation, et part avec la remorque si elle
##     est larguee). Au plus MAX_MARKS sur le tracteur, MAX_TRAILER_MARKS sur
##     la remorque : les plus anciens reperes partent, les cicatrices restent ;
##   - carrosserie cabossee (BodyDamage, 2026-10-06) : la tole s'enfonce au
##     point touche, d'autant plus que le choc est violent ; au-dela de
##     PART_SPEED, les pieces exterieures proches s'arrachent (retros, phares,
##     pare-chocs...) et des eclats de tole volent. A l'explosion de la tete ou
##     de la remorque, tout ce qui depasse part ;
##   - fumee moteur selon les PV (TruckHealth) : rien au-dessus de 70 PV,
##     grise legere de 70 a 30, noire epaisse et etincelles sous 30, feu sous
##     FIRE_HP (langues de flamme et lueur qui vacille), fumee d'epave pendant
##     les 3 s avant la reapparition ;
##   - etincelles du metal (2026-10-08, particules) : gerbe qui longe le mur
##     tant que le camion le frotte, eclat a chaque choc franc (mur, camion),
##     poussiere de beton sur un choc violent ;
##   - un camion qui reapparait est neuf (traces et bosses effacees, pieces
##     remises) ; une nouvelle remorque aussi.

const MAX_MARKS := 10
const MAX_TRAILER_MARKS := 8
## Seuils de la fumee moteur (PV).
const LIGHT_SMOKE_HP := 70.0
const HEAVY_SMOKE_HP := 30.0
## En dessous, le moteur brule (PV).
const FIRE_HP := 15.0
## Compartiment moteur, sous la cabine : la fumee sort de la calandre et
## monte devant le pare-brise (repere du camion).
const ENGINE_POS := Vector3(0.0, 1.5, -3.7)
## Etincelles : frottement contre un mur au-dela de SCRAPE_MS (vitesse le long
## du mur), pleines a SCRAPE_FULL_MS ; eclat d'un choc au-dela de BURST_MS (m/s
## vers l'obstacle), poussiere au-dela de DUST_MS.
const SCRAPE_MS := 4.0
const SCRAPE_FULL_MS := 25.0
const BURST_MS := 5.0
const DUST_MS := 11.0
## En dessous, un contact avec un autre corps ne laisse pas de trace (m/s).
const MIN_BODY_MARK_SPEED := 3.0
## Bosses : a partir de DENT_SPEED (m/s vers l'obstacle), pleines a HARD_SPEED ;
## pieces arrachees et eclats au-dela de PART_SPEED.
const DENT_SPEED := 2.5
const HARD_SPEED := 20.0
const PART_SPEED := 9.0
## Creux d'une paroi de remorque, rapporte a celui de la cabine.
const TRAILER_DENT_MULT := 1.6
## Pieces exterieures arrachees par une explosion ; celles qui fument.
const EXPLOSION_PARTS := 24
const EXPLOSION_TRAILS := 6

var _truck: Truck
var _health: TruckHealth
var _visual: TruckVisual
var _marks: Array[Node3D] = []
var _trailer_marks: Array[Node3D] = []
var _smoke: GPUParticles3D
var _sparks: GPUParticles3D
var _fire: GPUParticles3D
var _fire_light: OmniLight3D
var _scrape: GPUParticles3D
var _level: int = DamageFx.Smoke.NONE
## Hauteur de la route sous le camion (repere du camion), lue aux roues.
var _ground_y: float = 0.0
var _flicker: float = 0.0
## Bosses de la destruction, une par image (tache 7.6 : les quatre d'un coup
## figeaient l'image ~190 ms a 4 joueurs) : [point, poussee] dans le repere
## du camion, appliquees avec son transform du moment.
var _pending_dents: Array[PackedVector3Array] = []
const WRECK_DENT_RADIUS := 1.6


## Niveau de fumee pour ces PV (DamageFx.Smoke).
static func smoke_level_for(hp: float, wrecked: bool) -> int:
	if wrecked:
		return DamageFx.Smoke.WRECK
	if hp > LIGHT_SMOKE_HP:
		return DamageFx.Smoke.NONE
	if hp >= HEAVY_SMOKE_HP:
		return DamageFx.Smoke.LIGHT
	return DamageFx.Smoke.HEAVY


## Le moteur brule-t-il a ces PV ?
static func fire_for(hp: float, wrecked: bool) -> bool:
	return wrecked or hp < FIRE_HP


func _ready() -> void:
	_truck = get_parent() as Truck
	if _truck == null:
		return
	_health = TruckHealth.of(_truck)
	_visual = _truck.get_node_or_null(^"Visual") as TruckVisual
	_smoke = DamageFx.make_smoke()
	_smoke.position = ENGINE_POS
	add_child(_smoke)
	_sparks = DamageFx.make_sparks()
	_sparks.position = ENGINE_POS + Vector3(0.0, -0.6, -0.2)
	add_child(_sparks)
	_fire = FxKit.make_fire(36, 0.6, 1.1)
	_fire.position = ENGINE_POS + Vector3(0.0, -0.2, 0.3)
	add_child(_fire)
	if DisplayServer.get_name() != "headless":
		_make_metal_fx()
	_truck.wall_impact_at.connect(_on_impact)
	_truck.body_impact.connect(_on_body_impact)
	_truck.trailer_reattached.connect(clear_trailer_marks)
	if _health != null:
		_health.damaged.connect(_on_damaged)
		_health.destroyed.connect(_on_destroyed)
		_health.trailer_destroyed.connect(_on_trailer_destroyed)
		_health.respawned.connect(clear_all)


## Lueur du feu, etincelles du frottement (rien en headless : purement
## visuel). La gerbe du frottement est accrochee au camion (elle herite de
## sa vitesse) et glisse vers le point de contact : un emetteur teleporte
## etale son emission sur tout le trajet (un peigne de traits paralleles).
func _make_metal_fx() -> void:
	_fire_light = OmniLight3D.new()
	_fire_light.name = "FireLight"
	_fire_light.light_color = Color(1.0, 0.5, 0.18)
	_fire_light.omni_range = 7.0
	_fire_light.position = ENGINE_POS + Vector3(0.0, 0.4, -0.3)
	_fire_light.visible = false
	add_child(_fire_light)
	_scrape = FxKit.make_sparks(140, 0.55, {
		"spread": 0.5, "speed_min": 3.0, "speed_max": 10.0, "inherit": 0.85,
		"box_extents": Vector3(0.25, 0.2, 0.25), "gravity": 15.0, "drag": 0.9,
		"life_min": 0.3, "stretch": 0.04, "max_len": 0.55, "width": 0.016, "heat": 6.0})
	_scrape.name = "ScrapeSparks"
	add_child(_scrape)


func _process(delta: float) -> void:
	refresh()
	if _truck == null:
		return
	if not _pending_dents.is_empty() and _visual != null:
		var d: PackedVector3Array = _pending_dents.pop_front()
		var xf := _truck.global_transform
		BodyDamage.dent(_visual.mark_parent(false), xf * d[0], xf.basis * d[1], WRECK_DENT_RADIUS)
	_read_ground()
	if _fire_light != null and _fire_light.visible:
		# flamme qui vacille (visuel seulement)
		_flicker += delta
		_fire_light.light_energy = 2.2 + 0.8 * sin(_flicker * 23.0) + 0.5 * sin(_flicker * 37.0 + 1.3)
	_update_scrape(delta)


## Hauteur de la route sous le camion, d'apres les roues au sol : le sol des
## etincelles (elles rebondissent dessus).
func _read_ground() -> void:
	var inv := _truck.global_transform.affine_inverse()
	var sum := 0.0
	var n := 0
	for i in 4:
		var p := _truck.get_probe(i)
		if p != null and p.in_contact:
			sum += (inv * p.contact_point).y
			n += 1
	if n == 0:
		return
	var y := sum / n
	if absf(y - _ground_y) > 0.03:
		_ground_y = y
		FxKit.spark_param(_sparks, &"floor_below", _sparks.position.y - y)


## Hauteur du point monde `at` au-dessus de la route sous le camion.
func _above_ground(at: Vector3) -> float:
	return maxf((_truck.global_transform.affine_inverse() * at).y - _ground_y, 0.05)


## Frottement contre un mur : la gerbe sort du point de contact, vers
## l'arriere le long du mur et vers la piste, d'autant plus fournie que le
## camion glisse vite. Repere du camion (le noeud le suit).
func _update_scrape(delta: float) -> void:
	if _scrape == null:
		return
	var n := _truck.get_wall_normal()
	var slide := Vector3.ZERO
	if n != Vector3.ZERO and not _truck.is_wrecked():
		var v := _truck.linear_velocity
		slide = v - n * v.dot(n)
		slide.y = 0.0
	var speed := slide.length()
	var on := speed >= SCRAPE_MS
	if on:
		var inv := _truck.global_transform.affine_inverse()
		var at := inv * (_truck.get_wall_point() + n * 0.15)
		# a l'allumage : sur place ; ensuite : glisse vers le contact
		_scrape.position = at if not _scrape.emitting else _scrape.position.lerp(at, minf(delta * 12.0, 1.0))
		var dir := (-slide / speed + n * 0.6 + Vector3.UP * 0.5).normalized()
		FxKit.spark_param(_scrape, &"direction", inv.basis * dir)
		FxKit.spark_param(_scrape, &"floor_below", maxf(_scrape.position.y - _ground_y, 0.05))
		_scrape.amount_ratio = clampf(speed / SCRAPE_FULL_MS, 0.3, 1.0) * FxKit.density()
	if _scrape.emitting != on:
		_scrape.emitting = on


func is_scraping() -> bool:
	return _scrape != null and _scrape.emitting


## Eclat d'etincelles (et poussiere si le choc est violent) au point `at`,
## renvoye du cote du camion (`normal`) : emetteurs neufs, poses sur le
## point, qui se liberent seuls (FxKit.fire_once ; rien en headless).
func spark_burst(at: Vector3, normal: Vector3, speed: float) -> void:
	if _truck == null or not is_inside_tree():
		return
	var world := _truck.get_parent()
	var k := clampf((speed - BURST_MS) / (HARD_SPEED - BURST_MS), 0.0, 1.0)
	var sparks := FxKit.make_sparks(roundi(60 * FxKit.density()), 0.7, {
		"direction": (normal + Vector3.UP * 0.7).normalized(), "spread": 1.1,
		"speed_min": 4.0, "speed_max": lerpf(7.0, 16.0, k), "inherit": 0.0,
		"box_extents": Vector3(0.3, 0.3, 0.3), "gravity": 14.0, "drag": 0.7,
		"floor_below": _above_ground(at), "life_min": 0.3, "stretch": 0.035, "max_len": 0.6,
		"width": 0.02, "streak_follow": 0.0, "heat": 7.0})
	sparks.name = "ImpactSparks"
	sparks.amount_ratio = lerpf(0.35, 1.0, k)
	FxKit.fire_once(world, sparks, at + normal * 0.2)
	if speed < DUST_MS:
		return
	var dust := FxKit.make_smoke(14, 1.6, 2.0)
	dust.name = "ImpactDust"
	var pm := dust.process_material as ParticleProcessMaterial
	pm.color = Color(0.62, 0.6, 0.56, 0.45)
	pm.direction = normal + Vector3.UP * 0.5
	pm.spread = 70.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 5.5
	pm.inherit_velocity_ratio = 0.0
	pm.gravity = Vector3(0.0, 0.4, 0.0)
	dust.amount_ratio = lerpf(0.5, 1.0, k)
	FxKit.fire_once(world, dust, at + normal * 0.4, 0.9)



## Met la fumee (et le feu) au niveau des PV courants.
func refresh() -> void:
	if _health == null:
		return
	var level := smoke_level_for(_health.hp, _health.is_wrecked())
	var burning := fire_for(_health.hp, _health.is_wrecked())
	if burning != _fire.emitting:
		_fire.emitting = burning
		_fire.amount_ratio = FxKit.density()
		if _fire_light != null:
			_fire_light.visible = burning
		# la fumee d'un moteur en feu sort rougeoyante
		var mat := FxKit.smoke_material(Color(0.9, 0.35, 0.08), 0.25) if burning else FxKit.smoke_material()
		(_smoke.draw_pass_1 as QuadMesh).material = mat
	if level == _level:
		return
	_level = level
	DamageFx.set_smoke(_smoke, level)
	_sparks.emitting = level == DamageFx.Smoke.HEAVY or level == DamageFx.Smoke.WRECK


func smoke_level() -> int:
	return _level


func is_burning() -> bool:
	return _fire != null and _fire.emitting


func is_smoking() -> bool:
	return _smoke != null and _smoke.emitting


func is_sparking() -> bool:
	return _sparks != null and _sparks.emitting


## Traces de choc posees (tracteur, ou remorque attachee).
func marks(on_trailer: bool = false) -> Array[Node3D]:
	return _trailer_marks if on_trailer else _marks


func _on_impact(speed: float, on_trailer: bool, point: Vector3, normal: Vector3) -> void:
	add_mark(_on_body(point, normal, on_trailer), -normal, clampf((speed - 1.0) / 16.0, 0.1, 1.0), on_trailer)
	crush(point, normal, speed, on_trailer)
	if speed >= BURST_MS:
		spark_burst.call_deferred(point, normal, speed)


func _on_body_impact(speed: float, on_trailer: bool, point: Vector3, normal: Vector3) -> void:
	if speed >= MIN_BODY_MARK_SPEED:
		add_mark(_on_body(point, normal, on_trailer), -normal, clampf((speed - 1.0) / 16.0, 0.15, 1.0), on_trailer)
		crush(point, normal, speed, on_trailer)
		if speed >= BURST_MS:
			spark_burst.call_deferred(point, normal, speed)


## Choc a `speed` (m/s) au point `point`, `normal` tournee vers le camion :
## la tole s'enfonce dans le sens du choc (creux de 3 a 45 cm, sur 0,7 a
## 1,9 m ; TRAILER_DENT_MULT fois plus sur la remorque), et au-dela de PART_SPEED les pieces proches s'arrachent et des
## eclats volent. Purement visuel.
func crush(point: Vector3, normal: Vector3, speed: float, on_trailer: bool) -> void:
	if _visual == null or speed < DENT_SPEED:
		return
	var root := _visual.mark_parent(on_trailer)
	point = _on_body(point, normal, on_trailer)
	var sev := clampf((speed - DENT_SPEED) / (HARD_SPEED - DENT_SPEED), 0.0, 1.0)
	# la caisse d'une remorque est une tole mince sur un cadre : elle cede
	# plus que la cabine (2026-10-07 : « enfoncer la coque
	# plutot que faire des trous »)
	var deep := TRAILER_DENT_MULT if on_trailer else 1.0
	BodyDamage.dent(root, point, normal * lerpf(0.03, 0.45, sev) * deep, lerpf(0.7, 1.9, sev))
	if speed < PART_SPEED:
		return
	var world := _truck.get_parent()
	BodyDamage.detach_parts(root, world, point, lerpf(1.2, 2.2, sev), 1 + roundi(sev * 2.0),
		_truck.linear_velocity * 0.85, 3.0 + 5.0 * sev)
	BodyDamage.shards(world, point, -normal, 2 + roundi(sev * 4.0), _truck.linear_velocity * 0.85,
		4.0 + 6.0 * sev, BodyDamage.nearest_material(root, point), Engine.get_physics_frames())


## Point de contact ramene sur la carrosserie : une boite de collision touche
## un mur plat par ses coins (au ras du sol, ou au bord du toit), loin de la
## tole. Il glisse vers le milieu de la face touchee, dans le repere de la
## caisse (tracteur, ou remorque articulee).
func _on_body(point: Vector3, normal: Vector3, on_trailer: bool) -> Vector3:
	var frame := _truck.global_transform
	var half := Vector3(1.35, 0.0, 0.0)
	var y_range := Vector2(1.0, 3.4)
	if on_trailer:
		frame = frame * Truck.trailer_local_transform(_truck.get_trailer_angle(), _truck.trailer_box_center)
		half = _truck.trailer_box_size / 2.0
		# caisse ronde ou ajouree (citerne, plateau) : vers le coeur de la face
		y_range = Vector2(-half.y, half.y) * 0.3
		half.x *= 0.5
	var p := frame.affine_inverse() * point
	# la face touchee garde sa profondeur : seules les deux autres directions
	# sont ramenees vers le milieu
	var n := (frame.basis.inverse() * normal).abs()
	if n.x < maxf(n.y, n.z):
		p.x = clampf(p.x, -half.x, half.x)
	if n.y < maxf(n.x, n.z):
		p.y = clampf(p.y, y_range.x, y_range.y)
	return frame * p


## Pose une trace au point monde `point`, la carrosserie regardant vers
## `outward` (monde) : cicatrice peinte et son repere (DamageFx.scar). Sur la
## remorque : accrochee a son pivot. Au-dela de MAX_MARKS, les plus anciens
## reperes partent ; les cicatrices restent jusqu'a la remise a neuf.
func add_mark(point: Vector3, outward: Vector3, severity: float, on_trailer: bool) -> Node3D:
	var parent: Node3D = self
	if _visual != null:
		parent = _visual.mark_parent(on_trailer)
	var d := DamageFx.scar(parent, point, outward, severity)
	var list := _trailer_marks if on_trailer else _marks
	list.append(d)
	if list.size() > (MAX_MARKS if not on_trailer else MAX_TRAILER_MARKS):
		var old: Node3D = list.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return d


## Baril : brulure sur le bas de caisse avant.
func _on_damaged(_amount: float, source: StringName) -> void:
	if source == &"baril":
		var xf := _truck.global_transform
		add_mark(xf * Vector3(0.0, 1.0, -3.6), xf.basis * Vector3(0.0, -0.2, -1.0), 0.8, false)


## Destruction : la cabine est noircie de toutes parts, enfoncee, et les
## pieces exterieures volent avec des eclats de tole.
func _on_destroyed() -> void:
	var xf := _truck.global_transform
	for side: Vector3 in [Vector3(0.0, 0.0, -1.0), Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0), Vector3.UP]:
		var at := TruckSpec.CAB_CENTER + side * (TruckSpec.CAB_SIZE / 2.0)
		add_mark(xf * at, xf.basis * side, 1.0, false)
		if _visual != null:
			_pending_dents.append(PackedVector3Array([at, -side * 0.35]))
	if _visual != null:
		var world := _truck.get_parent()
		var c := xf * TruckSpec.CAB_CENTER
		BodyDamage.detach_parts(_visual.mark_parent(false), world, c, 8.0, EXPLOSION_PARTS,
			_truck.linear_velocity, 11.0, EXPLOSION_TRAILS)
		BodyDamage.shards(world, c, Vector3.UP, 10, _truck.linear_velocity, 13.0,
			BodyDamage.nearest_material(_visual.mark_parent(false), c), Engine.get_physics_frames())
	refresh()


## Remorque attelee detruite (TruckHealth) : elle vole en eclats - ses pieces
## exterieures et des plaques de tole de sa couleur.
func _on_trailer_destroyed(at: Vector3) -> void:
	if _visual == null:
		return
	var root := _visual.mark_parent(true)
	var world := _truck.get_parent()
	var mat := BodyDamage.nearest_material(root, at)
	BodyDamage.detach_parts(root, world, at, 12.0, EXPLOSION_PARTS, _truck.linear_velocity, 12.0,
		EXPLOSION_TRAILS)
	BodyDamage.shards(world, at, Vector3.UP, 18, _truck.linear_velocity, 15.0, mat, Engine.get_physics_frames())


## Nouvelle remorque : neuve (ni traces, ni bosses).
func clear_trailer_marks() -> void:
	for d in _trailer_marks:
		if is_instance_valid(d):
			d.queue_free()
	_trailer_marks.clear()
	if _visual != null:
		BodyDamage.restore(_visual.mark_parent(true))


## Camion neuf (reapparition) : plus aucune trace, aucune bosse, toutes ses
## pieces, plus de fumee.
func clear_all() -> void:
	_pending_dents.clear()
	for d in _marks:
		if is_instance_valid(d):
			d.queue_free()
	_marks.clear()
	clear_trailer_marks()
	if _visual != null:
		BodyDamage.restore(_visual)
	refresh()
