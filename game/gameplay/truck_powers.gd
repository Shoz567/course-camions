class_name TruckPowers
extends Node3D

## Pouvoirs d'un camion (tache 4.5.8, premiere serie du 2026-10-17) : deux
## emplacements, fleche gauche et fleche droite de la croix (InputFrame
## power_left / power_right, fronts montants), choisis sur la page de
## selection (GameState.power_left / power_right, PowerCatalog). Enfant
## « Powers » du camion, repere du camion.
##   BOUCLIER : SHIELD_TICKS sans degats (TruckHealth.shield_ticks), aura bleue
##              translucide qui epouse la tete du camion (shield_aura.gdshader,
##              en material_overlay sur ses pieces, remorque exclue) ;
##   MISSILE  : PowerMissile vers le camion le plus proche devant (cone et
##              portee de PowerCatalog), tout droit s'il n'y en a pas ;
##   LASER    : rayon droit devant pendant LASER_TICKS, LASER_DAMAGE_PER_TICK
##              au camion touche (le premier obstacle arrete le rayon) ;
##   MITRAILLEUSE : rafale de GUN_TICKS, une balle (rayon droit devant) tous
##              les GUN_INTERVAL ticks, GUN_DAMAGE au camion touche ;
##   SCIE     : SAW_TICKS de scies sur les flancs ; un camion a cote (zone de
##              SAW_REACH_M au-dela du flanc) perd SAW_DAMAGE_PER_TICK et est
##              ecarte ;
##   BOOMERANG : PowerBoomerang, aller tout droit puis retour aimante vers le
##              tireur, touche chaque camion une fois par passage.
## Recharge par emplacement, comptee en ticks des l'activation. Rien ne part
## d'une epave. Aucun tirage aleatoire. Sur la machine qui fait foi (hors
## ligne, host) ; les visuels ne decident rien (rien en headless).
## En ligne, chez un client (mirror) : aucune decision, ni entree lue ni
## degat. Le host annonce chaque tir (NetRace, Ev.POWER -> net_fire) ; le
## client rejoue alors recharge, aura, rayon et missile, pour l'affichage.

signal fired(slot: int, power: int)

## Les camions de la course (cibles du missile, du laser) sont dans ce groupe.
const TARGETS := &"race_trucks"
## Toit de la cabine et bouche des armes (repere du camion, avant en -Z).
const ROOF := TruckSpec.CAB_CENTER + Vector3(0.0, TruckSpec.CAB_SIZE.y / 2.0, 0.0)
const MUZZLE := Vector3(0.0, ROOF.y + 0.35, TruckSpec.CAB_CENTER.z - TruckSpec.CAB_SIZE.z / 2.0 - 0.4)
## Le laser part du milieu de la face avant : un rayon horizontal tire du toit
## passerait au-dessus des cabines devant.
const LASER_ORIGIN := Vector3(0.0, TruckSpec.CAB_CENTER.y, TruckSpec.CAB_CENTER.z - TruckSpec.CAB_SIZE.z / 2.0 - 0.3)

var slots: PackedInt32Array = PackedInt32Array([-1, -1])
var cooldown: PackedInt32Array = PackedInt32Array([0, 0])
var laser_ticks: int = 0
## Dernier camion touche par le laser (tests, HUD).
var laser_hit: Truck
## Camion vise par le dernier missile (annonce aux clients).
var last_target: Truck
## Mitrailleuse et scie : ticks restants ; derniers camions touches (tests).
var gun_ticks: int = 0
var gun_hit: Truck
var gun_hits: int = 0
var saw_ticks: int = 0
var saw_hit: Truck
## Client en ligne : effets seulement, le host decide (net_fire).
var mirror: bool = false
## Client en ligne, son propre camion (2026-10-19) : un appui joue le tir ici
## tout de suite, sans attendre l'aller-retour ; l'annonce du host qui suit
## (dans PREDICT_TICKS) ne le rejoue pas. Les degats restent ceux du host.
var predict: bool = false
const PREDICT_TICKS := 90
var _predicted: PackedInt32Array = PackedInt32Array([0, 0])

var _truck: Truck
var _health: TruckHealth
var _beam: MeshInstance3D
var _tracer: MeshInstance3D
var _tracer_ticks: int = 0
var _discs: Array[MeshInstance3D] = []
var _hit_sparks: GPUParticles3D
## Aura du bouclier : posee sur les pieces de la tete (material_overlay), et
## l'overlay qu'elles avaient avant (rendu a la fin).
var _aura_on: bool = false
var _aura_parts: Dictionary = {}
static var _aura_mat: ShaderMaterial

static var _models: Dictionary = {}


## Pose les pouvoirs `left` / `right` (PowerCatalog, -1 = aucun) sur `truck` ;
## null si aucun.
static func setup(truck: Truck, left: int, right: int, as_mirror: bool = false) -> TruckPowers:
	if left < 0 and right < 0:
		return null
	var p := TruckPowers.new()
	p.name = "Powers"
	p.mirror = as_mirror
	p.slots = PackedInt32Array([left, right])
	truck.add_child(p)
	return p


static func of(truck: Truck) -> TruckPowers:
	return truck.get_node_or_null(^"Powers") as TruckPowers if truck != null else null


func _ready() -> void:
	_truck = get_parent() as Truck
	_health = TruckHealth.of(_truck)
	if DisplayServer.get_name() == "headless":
		return
	# armes de l'equipe montees sur le toit, gauche et droite
	for k in 2:
		var m := _weapon(PowerCatalog.model(slots[k], k))
		if m != null:
			m.position = ROOF + Vector3(-0.7 if k == 0 else 0.7, 0.0, 0.3)
			add_child(m)
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.12
	cyl.height = 1.0
	_beam.mesh = cyl
	_beam.material_override = _glow(Color(1.0, 0.15, 0.3), 6.0, 0.9)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	# balles de la mitrailleuse : trainee jaune d'un instant
	_tracer = MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.05
	tc.bottom_radius = 0.05
	tc.height = 1.0
	_tracer.mesh = tc
	_tracer.material_override = _glow(UiKit.GOLD, 5.0, 0.85)
	_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tracer.visible = false
	add_child(_tracer)
	# scies : un disque lumineux qui tourne de chaque cote de la cabine
	for side in [-1.0, 1.0]:
		var d := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 0.08
		disc.radial_segments = 12
		d.mesh = disc
		d.material_override = _glow(Color(1.0, 0.55, 0.15), 3.0, 0.75)
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.position = Vector3(side * (TruckSpec.CAB_SIZE.x / 2.0 + 0.5), 0.9, TruckSpec.CAB_CENTER.z)
		d.rotation = Vector3(0.0, 0.0, PI / 2.0)
		d.visible = false
		add_child(d)
		_discs.append(d)
	_hit_sparks = FxKit.make_sparks(18, 0.35)
	_hit_sparks.one_shot = true
	_hit_sparks.top_level = true
	add_child(_hit_sparks)


func _physics_process(_delta: float) -> void:
	if _truck == null:
		return
	for k in 2:
		if cooldown[k] > 0:
			cooldown[k] -= 1
	if _truck.is_wrecked():
		laser_ticks = 0
		gun_ticks = 0
		saw_ticks = 0
	if laser_ticks > 0:
		laser_ticks -= 1
		_laser_tick()
	elif _beam != null:
		_beam.visible = false
	if gun_ticks > 0:
		gun_ticks -= 1
		if gun_ticks % PowerCatalog.GUN_INTERVAL == 0:
			_gun_shot()
	if _tracer_ticks > 0:
		_tracer_ticks -= 1
		if _tracer_ticks == 0 and _tracer != null:
			_tracer.visible = false
	if saw_ticks > 0:
		saw_ticks -= 1
		_saw_tick()
	for d in _discs:
		d.visible = saw_ticks > 0
		if d.visible:
			d.rotate_object_local(Vector3.UP, 0.6)
	if DisplayServer.get_name() != "headless":
		_set_aura(_health != null and _health.shield_ticks > 0)
	if mirror:
		for k in 2:
			if _predicted[k] > 0:
				_predicted[k] -= 1
		if predict:
			var g := _truck.get_input()
			for k in 2:
				var pressed := g.power_left if k == 0 else g.power_right
				if pressed and slots[k] >= 0 and cooldown[k] == 0 and not _truck.is_wrecked():
					_fire(k, target_ahead() if slots[k] == PowerCatalog.Id.MISSILE else null)
					_predicted[k] = PREDICT_TICKS
		return
	var f := _truck.get_input()
	if f.power_left:
		use(0)
	if f.power_right:
		use(1)


## Declenche l'emplacement `k` (0 gauche, 1 droite) ; faux s'il est vide, en
## recharge, ou si le camion est une epave.
func use(k: int) -> bool:
	var p := slots[k]
	if mirror or p < 0 or cooldown[k] > 0 or _truck == null or _truck.is_wrecked():
		return false
	last_target = target_ahead() if p == PowerCatalog.Id.MISSILE else null
	_fire(k, last_target)
	fired.emit(k, p)
	return true


## Client en ligne : le host a declenche l'emplacement `k` (missile vers
## `aim`) ; memes effets ici, sans degat (le host les a deja comptes).
func net_fire(k: int, aim: Truck) -> void:
	if k < 0 or k > 1 or slots[k] < 0:
		return
	if _predicted[k] > 0:
		_predicted[k] = 0    # deja joue ici a l'appui (predict)
		return
	_fire(k, aim)


func _fire(k: int, aim: Truck) -> void:
	var p := slots[k]
	cooldown[k] = PowerCatalog.cooldown_ticks(p)
	match p:
		PowerCatalog.Id.SHIELD:
			if _health != null:
				_health.shield_ticks = PowerCatalog.SHIELD_TICKS
		PowerCatalog.Id.MISSILE:
			PowerMissile.launch(_truck, aim, mirror)
		PowerCatalog.Id.LASER:
			laser_ticks = PowerCatalog.LASER_TICKS
		PowerCatalog.Id.GUN:
			gun_ticks = PowerCatalog.GUN_TICKS
		PowerCatalog.Id.SAW:
			saw_ticks = PowerCatalog.SAW_TICKS
		PowerCatalog.Id.BOOMERANG:
			PowerBoomerang.launch(_truck, mirror)


## L'effet de l'emplacement `k` dure encore (laser, rafale, scies, bouclier).
func active(k: int) -> bool:
	match slots[k]:
		PowerCatalog.Id.LASER:
			return laser_ticks > 0
		PowerCatalog.Id.GUN:
			return gun_ticks > 0
		PowerCatalog.Id.SAW:
			return saw_ticks > 0
		PowerCatalog.Id.SHIELD:
			return _health != null and _health.shield_ticks > 0
	return false


## Secondes avant que l'emplacement `k` soit pret (0 : pret ; -1 : vide).
func seconds_left(k: int) -> int:
	if slots[k] < 0:
		return -1
	return ceili(cooldown[k] / 60.0)


## Camion vise : le plus proche devant, dans le cone et a portee ; null sinon.
func target_ahead() -> Truck:
	var from := _truck.global_transform * MUZZLE
	var fwd := -_truck.global_basis.z
	var best: Truck = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(TARGETS):
		var t := n as Truck
		if t == null or t == _truck or t.is_wrecked():
			continue
		var to := t.global_position + Vector3.UP * 1.5 - from
		var d := to.length()
		if d > PowerCatalog.MISSILE_RANGE_M or d < 1.0:
			continue
		if rad_to_deg(fwd.angle_to(to)) > PowerCatalog.MISSILE_CONE_DEG:
			continue
		if d < best_d:
			best_d = d
			best = t
	return best


func _laser_tick() -> void:
	var from := _truck.global_transform * LASER_ORIGIN
	var fwd := -_truck.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * PowerCatalog.LASER_RANGE_M,
		(1 << (TruckSpec.LAYER_WORLD - 1)) | (1 << (TruckSpec.LAYER_VEHICLE - 1)), [_truck.get_rid()])
	var hit := _truck.get_world_3d().direct_space_state.intersect_ray(q)
	var length := PowerCatalog.LASER_RANGE_M
	laser_hit = null
	if not hit.is_empty():
		length = from.distance_to(hit["position"])
		var other := hit["collider"] as Truck
		if other != null:
			laser_hit = other
			var h := TruckHealth.of(other) if not mirror else null
			if h != null:
				h.damage(PowerCatalog.LASER_DAMAGE_PER_TICK, &"laser")
	if _beam != null:
		_beam.visible = true
		(_beam.mesh as CylinderMesh).height = length
		_beam.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), LASER_ORIGIN + Vector3(0.0, 0.0, -length / 2.0))


## Une balle : rayon droit devant depuis la face avant ; GUN_DAMAGE au camion
## touche (pas en miroir), trainee et etincelles.
func _gun_shot() -> void:
	var from := _truck.global_transform * LASER_ORIGIN
	var fwd := -_truck.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * PowerCatalog.GUN_RANGE_M,
		(1 << (TruckSpec.LAYER_WORLD - 1)) | (1 << (TruckSpec.LAYER_VEHICLE - 1)), [_truck.get_rid()])
	var hit := _truck.get_world_3d().direct_space_state.intersect_ray(q)
	var length := PowerCatalog.GUN_RANGE_M
	if not hit.is_empty():
		length = from.distance_to(hit["position"])
		var other := hit["collider"] as Truck
		if other != null:
			gun_hit = other
			gun_hits += 1
			var h := TruckHealth.of(other) if not mirror else null
			if h != null:
				h.damage(PowerCatalog.GUN_DAMAGE, &"mitrailleuse")
		if _hit_sparks != null:
			_hit_sparks.global_position = hit["position"]
			_hit_sparks.restart()
	if _tracer != null:
		_tracer.visible = true
		_tracer_ticks = 2
		(_tracer.mesh as CylinderMesh).height = length
		_tracer.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), LASER_ORIGIN + Vector3(0.0, 0.0, -length / 2.0))


## Scies : chaque camion dont le centre est a cote de la cabine, dans la zone
## des lames, perd des PV et est ecarte (pas en miroir).
func _saw_tick() -> void:
	var inv := _truck.global_transform.affine_inverse()
	var reach := TruckSpec.CAB_SIZE.x + PowerCatalog.SAW_REACH_M
	for n in get_tree().get_nodes_in_group(TARGETS):
		var t := n as Truck
		if t == null or t == _truck or t.is_wrecked():
			continue
		var local := inv * t.global_position
		if absf(local.z - TruckSpec.CAB_CENTER.z) > PowerCatalog.SAW_HALF_LENGTH_M or absf(local.x) > reach:
			continue
		saw_hit = t
		if _hit_sparks != null and (Engine.get_physics_frames() % 6) == 0:
			_hit_sparks.global_position = (_truck.global_position + t.global_position) / 2.0 + Vector3.UP
			_hit_sparks.restart()
		if mirror:
			continue
		var h := TruckHealth.of(t)
		if h != null:
			h.damage(PowerCatalog.SAW_DAMAGE_PER_TICK, &"scie")
		var away := _truck.global_basis.x * signf(local.x)
		t.apply_central_force(away * PowerCatalog.SAW_PUSH_MS2 * t.mass)


## Aura du bouclier sur les pieces visibles de la tete (pas la remorque, ni
## les armes du toit). Les pieces arrachees en cours de route n'en ont plus.
func _set_aura(on: bool) -> void:
	if on == _aura_on:
		return
	_aura_on = on
	var visual := _truck.get_node_or_null(^"Visual") as Node3D
	if visual == null:
		return
	if on:
		if _aura_mat == null:
			_aura_mat = ShaderMaterial.new()
			_aura_mat.shader = preload("res://gameplay/shield_aura.gdshader")
		_aura_parts.clear()
		for n in visual.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree() or _in_trailer(mi, visual):
				continue
			_aura_parts[mi] = mi.material_overlay
			mi.material_overlay = _aura_mat
	else:
		for mi: Variant in _aura_parts:
			if is_instance_valid(mi):
				(mi as MeshInstance3D).material_overlay = _aura_parts[mi]
		_aura_parts.clear()


## Pieces visibles portant l'aura (tests).
func aura_parts() -> int:
	return _aura_parts.size() if _aura_on else 0


static func _in_trailer(node: Node, root: Node) -> bool:
	var n := node
	while n != null and n != root:
		if n.name == TruckVisual.TRAILER_PIVOT:
			return true
		n = n.get_parent()
	return false


static func _glow(color: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Arme de l'equipe (.glb, Assets_Visuels/Armes_et_camions/armes), lue une fois
## a l'execution comme les camions (TruckVisual.asset_base) ; null si absente.
static func _weapon(relative: String) -> Node3D:
	if relative == "":
		return null
	var path := TruckVisual.asset_base().path_join(relative).simplify_path()
	if not _models.has(path):
		_models[path] = null
		if FileAccess.file_exists(path):
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			if doc.append_from_file(path, state) == OK:
				var root := doc.generate_scene(state)
				var packed := PackedScene.new()
				packed.pack(root)
				root.free()
				_models[path] = packed
	var ps := _models[path] as PackedScene
	return ps.instantiate() as Node3D if ps != null else null
