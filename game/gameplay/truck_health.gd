class_name TruckHealth
extends Node

## Points de vie du camion (enfant « Health » du camion, comme le cargo).
## DEUX reserves distinctes (2026-10-06 : « il faut bien distinguer les degats
## faits a la tete du camion et a la remorque ») :
##
##   - la TETE (tracteur : cabine, chassis) : max_hp (100). A 0 : explosion ;
##     la carcasse RESTE sur la route (TruckWreck, obstacle), la remorque
##     encore attelee aussi (DetachedTrailer, avec ses PV restants), et le
##     joueur reapparait apres wreck_ticks (3 s) sur un camion neuf, a cote de
##     ce qui encombre la route (respawn_provider, RaceLaps.respawn_transform
##     en course) ;
##   - la REMORQUE attelee : trailer_max_hp, ceux de la remorque choisie
##     (TrailerType.dropped_hp ; larguee : DetachedTrailer.ROAD_HP_MULT fois
##     plus). Ce qu'elle encaisse ne touche JAMAIS la tete. A 0 : elle explose et disparait, et
##     c'est l'explosion qui blesse la tete (TRAILER_EXPLOSION_DAMAGE) ; le
##     tracteur roule seul jusqu'a sa nouvelle remorque (TruckCargo).
##
## Ce qui fait des degats, a la partie touchee (tete ou remorque) :
##   - murs : de wall_damage_min (frottement) a wall_damage_max (choc frontal
##     violent), selon la vitesse normale (Truck.wall_impact) ;
##   - obstacles de la route (remorque larguee, carcasse : Truck.hazard_impact)
##     et autres camions (Truck.truck_impact : les deux s'abiment) selon
##     l'energie du choc : jusqu'a hazard_damage_max de plein fouet a
##     hazard_full_speed_ms, rien sous hazard_min_speed_ms (frottement, coude
##     a coude). Sa propre remorque larguee aussi, autant que les autres
##     (2026-10-07) ;
##   - barils explosifs : BARREL_DAMAGE a la tete, inflige par PadEffects.
## Durees en ticks physiques (CLAUDE.md §7).

signal damaged(amount: float, source: StringName)
signal destroyed
signal respawned
## Tick physique de sa derniere reapparition (meta du camion : les bots lui
## laissent un repit).
const RESPAWNED_META := &"respawned_at"
## La remorque attelee a perdu `amount` PV (il lui en reste trailer_hp).
signal trailer_damaged(amount: float, source: StringName)
## Elle vient d'exploser, centree en `at` (monde).
signal trailer_destroyed(at: Vector3)
## Bonus de reparation : `cab` PV rendus a la tete, `trailer` a la remorque.
signal repaired(cab: float, trailer: float)
## Carcasse et remorque laissees sur la route a la destruction.
signal wreck_left(wreck: TruckWreck, trailer: DetachedTrailer)

const BARREL_DAMAGE := 15.0
## Explosion de la remorque attelee : degats a la tete.
const TRAILER_EXPLOSION_DAMAGE := 20.0
## PV de remorque sans TrailerType.
const DEFAULT_TRAILER_HP := 50.0
## Decalages lateraux essayes pour reapparaitre a cote d'un obstacle (m), a
## sa hauteur puis un peu plus loin ou plus tot (RESPAWN_ALONG).
const RESPAWN_OFFSETS: PackedFloat32Array = [0.0, 7.0, -7.0, 14.0, -14.0, 21.0, -21.0]
const RESPAWN_ALONG: PackedFloat32Array = [0.0, 14.0, -14.0, 28.0]

@export var max_hp: float = 100.0
@export var wall_damage_min: float = 1.0
@export var wall_damage_max: float = 5.0
## En dessous : frottement leger (wall_damage_min) ; au-dessus : choc frontal
## violent (wall_damage_max). Vitesse normale au mur, m/s.
@export var wall_speed_light_ms: float = 2.0
@export var wall_speed_hard_ms: float = 18.0
## Obstacle percute : degats = max x (v / v_pleine)^2, plafonnes au max ; rien
## sous hazard_min_speed_ms (pousser, frotter). De plein fouet a 100 km/h :
## ~28 PV ; a 60 km/h : ~10.
@export var hazard_damage_max: float = 40.0
@export var hazard_full_speed_ms: float = 33.0
@export var hazard_min_speed_ms: float = 4.0
@export var wreck_ticks: int = 180

var hp: float = 100.0
var trailer_hp: float = DEFAULT_TRAILER_HP
var trailer_max_hp: float = DEFAULT_TRAILER_HP
## Transformation de reapparition (Truck -> Transform3D). Par defaut : sur
## place, a plat, 1 m au-dessus.
var respawn_provider: Callable
## Vitesse de lancement a la reapparition (Transform3D -> float, m/s, vers
## l'avant). Invalide : a l'arret.
var launch_provider: Callable
## Place sur la route ? (Vector3 -> bool ; invalide : toute place libre.)
## 2026-10-22 : sur un raccourci etroit, a cote de sa carcasse, le decalage de
## 14 m passait le mur et le camion reapparaissait dans le vide.
var spot_ok: Callable
## Hors piste (AutoReset) : ni les murs ni les obstacles ne blessent, le
## camion va etre replace.
var off_track: bool = false
## Derniere carcasse laissee sur la route (tests).
var last_wreck: TruckWreck
## En ligne, chez un client (NetRace) : le host fait foi. Aucun degat n'est
## compte ici ; PV, epave et reapparition arrivent du host (net_*), et les
## effets (fumee, explosion, carcasse) suivent comme d'habitude.
var net_mirror: bool = false
## Bouclier (pouvoir, tache 4.5.8) : ticks restants sans degats, tete et
## remorque attelee.
var shield_ticks: int = 0

var _truck: Truck
var _dead_pending: bool = false
var _trailer_pending: bool = false
var _wreck_left: int = 0
var _trailer_type: TrailerType
var _respawn_query: PhysicsShapeQueryParameters3D


## Le noeud de PV d'un camion (null s'il n'en a pas).
static func of(truck: Truck) -> TruckHealth:
	return truck.get_node_or_null(^"Health") as TruckHealth if truck != null else null


## Degats d'un impact contre un mur, a cette vitesse normale (m/s) : entier,
## de wall_damage_min a wall_damage_max.
func wall_damage_for(normal_speed_ms: float) -> float:
	var u := clampf((normal_speed_ms - wall_speed_light_ms) / (wall_speed_hard_ms - wall_speed_light_ms), 0.0, 1.0)
	return roundf(lerpf(wall_damage_min, wall_damage_max, u))


## Degats d'un obstacle percute a cette vitesse d'approche (m/s), entier.
func hazard_damage_for(approach_ms: float) -> float:
	if approach_ms < hazard_min_speed_ms:
		return 0.0
	return roundf(hazard_damage_max * minf(pow(approach_ms / hazard_full_speed_ms, 2.0), 1.0))


func _ready() -> void:
	hp = max_hp
	_truck = get_parent() as Truck
	if _truck != null:
		_truck.wall_impact.connect(_on_wall_impact)
		_truck.hazard_impact.connect(_on_hazard_impact)
		_truck.truck_impact.connect(_on_truck_impact)
		_truck.trailer_reattached.connect(_on_trailer_reattached)
		_sync_trailer_type()
	var shape := BoxShape3D.new()
	# camion entier, remorque dans l'axe, au-dessus de la chaussee
	shape.size = Vector3(4.0, 3.6, 22.0)
	_respawn_query = PhysicsShapeQueryParameters3D.new()
	_respawn_query.shape = shape
	_respawn_query.collision_mask = Truck.TRAILER_BLOCK_MASK


func _on_wall_impact(normal_speed_ms: float, on_trailer: bool) -> void:
	if off_track:
		return
	if on_trailer:
		damage_trailer(wall_damage_for(normal_speed_ms), &"mur")
	else:
		damage(wall_damage_for(normal_speed_ms), &"mur")


func _on_hazard_impact(_obstacle: Node3D, approach_ms: float, on_trailer: bool, _point: Vector3,
		_normal: Vector3) -> void:
	_hit(hazard_damage_for(approach_ms), on_trailer, &"obstacle")


## Choc contre un autre camion : chacun encaisse a la partie touchee (l'autre
## recoit le meme contact de son cote).
func _on_truck_impact(_other: Truck, approach_ms: float, on_trailer: bool, _point: Vector3,
		_normal: Vector3) -> void:
	_hit(hazard_damage_for(approach_ms), on_trailer, &"camion")


func _hit(amount: float, on_trailer: bool, source: StringName) -> void:
	if off_track:
		return
	if on_trailer:
		damage_trailer(amount, source)
	else:
		damage(amount, source)


## Destruction sur le coup (chute hors piste, AutoReset) : ni le bouclier ni
## le hors piste ne la retiennent. Explosion, epave et reapparition comme a
## 0 PV, au prochain tick physique.
func crash(source: StringName = &"chute") -> void:
	if net_mirror or is_wrecked() or _dead_pending:
		return
	var lost := hp
	hp = 0.0
	damaged.emit(lost, source)
	_dead_pending = true


## Retire `amount` PV a la tete (sans effet sur une epave). A 0 : destruction
## au prochain tick physique (le camion n'est jamais modifie pendant un pas).
func damage(amount: float, source: StringName = &"") -> void:
	if net_mirror or amount <= 0.0 or is_wrecked() or _dead_pending or shield_ticks > 0:
		return
	hp = maxf(0.0, hp - amount)
	damaged.emit(amount, source)
	if hp <= 0.0:
		_dead_pending = true


## Retire `amount` PV a la remorque attelee, jamais a la tete. A 0 : elle
## explose au prochain tick physique.
func damage_trailer(amount: float, source: StringName = &"") -> void:
	if net_mirror or amount <= 0.0 or is_wrecked() or _dead_pending or _trailer_pending or shield_ticks > 0:
		return
	if _truck == null or _truck.is_trailer_detached():
		return
	trailer_hp = maxf(0.0, trailer_hp - amount)
	trailer_damaged.emit(amount, source)
	if trailer_hp <= 0.0:
		_trailer_pending = true


## Bonus de reparation (TrackPickup, 2026-10-20) : PV rendus a la tete et a
## la remorque attelee, sans depasser leur maximum ; rien sur une epave ni
## chez un client en ligne (les PV viennent du host).
func repair(cab: float, trailer: float) -> void:
	if net_mirror or is_wrecked() or _dead_pending:
		return
	var c := minf(cab, max_hp - hp)
	hp += c
	var tr := 0.0
	if not _truck.is_trailer_detached():
		tr = minf(trailer, trailer_max_hp - trailer_hp)
		trailer_hp += tr
	repaired.emit(c, tr)


## Plus de reapparition (elimine, sans vie en arene) : l'epave reste.
var no_respawn: bool = false


## Bouclier actif : ni PV, ni tole, ni pneus.
func is_shielded() -> bool:
	return shield_ticks > 0


func is_wrecked() -> bool:
	return _wreck_left > 0 or _dead_pending


## Secondes avant la reapparition (0 : en course).
func wreck_seconds_left() -> int:
	return ceili(_wreck_left / 60.0)


func _physics_process(_delta: float) -> void:
	if _truck == null:
		return
	if shield_ticks > 0:
		shield_ticks -= 1
	_sync_trailer_type()
	if _dead_pending:
		_dead_pending = false
		_trailer_pending = false
		_destroy()
		return
	if _trailer_pending:
		_trailer_pending = false
		_explode_trailer()
	if _wreck_left > 0:
		_wreck_left -= 1
		if _wreck_left == 0 and not no_respawn:
			_respawn()


## Remorque choisie (sas READY) : ses PV, remorque neuve.
func _sync_trailer_type() -> void:
	if _truck.trailer_type == _trailer_type and trailer_max_hp > 0.0:
		return
	_trailer_type = _truck.trailer_type
	trailer_max_hp = _trailer_type.dropped_hp if _trailer_type != null else DEFAULT_TRAILER_HP
	trailer_hp = trailer_max_hp


func _on_trailer_reattached() -> void:
	trailer_hp = trailer_max_hp


## Centre monde de la caisse de remorque attelee.
func trailer_center() -> Vector3:
	return _truck.global_transform * Truck.trailer_local_transform(_truck.get_trailer_angle(),
		_truck.trailer_box_center).origin


func _explode_trailer() -> void:
	if _truck.is_trailer_detached():
		return
	var at := trailer_center()
	# la remorque disparait (ses debris sont l'affaire de TruckDamageFx)
	trailer_destroyed.emit(at)
	var cargo := _truck.get_node_or_null(^"Cargo") as TruckCargo
	if cargo != null:
		cargo.lose_trailer()
	else:
		_truck.detach_trailer()
	trailer_hp = 0.0
	ExplosionFx.spawn(_truck.get_parent(), at, 9.0)
	damage(TRAILER_EXPLOSION_DAMAGE, &"remorque")


## 0 PV : explosion ; la carcasse et la remorque attelee restent sur la route,
## le camion (cache, sans collision) attend sa reapparition.
func _destroy() -> void:
	_wreck_left = wreck_ticks
	_leave_wreck()


## Explosion, carcasse et remorque laissees sur la route, camion cache.
func _leave_wreck() -> Array:
	# d'abord les effets (pieces arrachees, suie) : la carcasse les reprend
	destroyed.emit()
	var world := _truck.get_parent()
	var visual := _truck.get_node_or_null(^"Visual") as TruckVisual
	var wreck := TruckWreck.new()
	# sa propre carcasse : il ne s'y heurte pas en reapparaissant
	wreck.dropped_by = _truck
	if visual != null:
		wreck.set_visual(visual.make_wreck_copy())
	wreck.transform = _truck.global_transform
	world.add_child(wreck)
	wreck.linear_velocity = _truck.linear_velocity * 0.6
	var left_trailer: DetachedTrailer = null
	if not _truck.is_trailer_detached():
		left_trailer = DetachedTrailer.new()
		left_trailer.configure(_truck.trailer_type)
		left_trailer.dropped_by = _truck
		left_trailer.initial_hp = trailer_hp
		if visual != null:
			left_trailer.set_visual(visual.make_trailer_copy())
		left_trailer.transform = _truck.detach_trailer()
		world.add_child(left_trailer)
		left_trailer.linear_velocity = _truck.linear_velocity * 0.6
		# carcasse et remorque se chevauchent a l'attelage : jamais repoussees
		left_trailer.add_collision_exception_with(wreck)
	last_wreck = wreck
	_truck.set_wrecked(true)
	if visual != null:
		visual.visible = false
	ExplosionFx.spawn(world, _truck.global_transform * TruckSpec.CENTER_OF_MASS, 8.0)
	wreck_left.emit(wreck, left_trailer)
	return [wreck, left_trailer]


# --- en ligne, chez un client (net_mirror) --------------------------------------

## PV recus du host ; une baisse rejoue les effets (fumee, etincelles).
func net_apply_hp(new_hp: float, new_trailer_hp: float) -> void:
	if new_hp < hp - 0.5:
		damaged.emit(hp - new_hp, &"reseau")
	if new_trailer_hp < trailer_hp - 0.5:
		trailer_damaged.emit(trailer_hp - new_trailer_hp, &"reseau")
	hp = new_hp
	trailer_hp = new_trailer_hp


## Le host a detruit le camion : explosion, carcasse et remorque laissees sur
## la route, comme chez lui ([carcasse, remorque ou null], a relier aux
## siennes). Pas de minuterie : la reapparition vient du host.
func net_wreck() -> Array:
	if _truck.is_wrecked():
		return []
	return _leave_wreck()


## Le host a fait reapparaitre le camion (sa pose arrive par les snapshots).
func net_respawn() -> void:
	_truck.set_wrecked(false)
	_truck.reattach_trailer(true)
	var visual := _truck.get_node_or_null(^"Visual") as Node3D
	if visual != null:
		visual.visible = true
	hp = max_hp
	trailer_hp = trailer_max_hp
	respawned.emit()


## La remorque attelee a explose chez le host, centree en `at`.
func net_trailer_exploded(at: Vector3) -> void:
	if _truck.is_trailer_detached():
		return
	trailer_destroyed.emit(at)
	var cargo := _truck.get_node_or_null(^"Cargo") as TruckCargo
	if cargo != null:
		cargo.lose_trailer()
	else:
		_truck.detach_trailer()
	trailer_hp = 0.0
	ExplosionFx.spawn(_truck.get_parent(), at, 9.0)


func _respawn() -> void:
	var xf: Transform3D
	if respawn_provider.is_valid():
		xf = respawn_provider.call(_truck)
	else:
		var f := -_truck.global_basis.z
		xf = Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.z)), _truck.global_position + Vector3.UP)
	xf = free_spot(xf)
	_truck.set_wrecked(false)
	var launch := float(launch_provider.call(xf)) if launch_provider.is_valid() else 0.0
	_truck.reset_to(xf, -xf.basis.z.normalized() * launch)
	# camion neuf : remorque neuve attelee
	_truck.reattach_trailer(true)
	var visual := _truck.get_node_or_null(^"Visual") as Node3D
	if visual != null:
		visual.visible = true
	hp = max_hp
	trailer_hp = trailer_max_hp
	_truck.set_meta(RESPAWNED_META, GameClock.now())
	respawned.emit()


## `xf`, ou la place libre la plus proche sur sa transversale : jamais dans la
## carcasse ni dans une remorque laissee sur la route.
func free_spot(xf: Transform3D) -> Transform3D:
	var space := _truck.get_world_3d().direct_space_state
	for dz in RESPAWN_ALONG:
		for dx in RESPAWN_OFFSETS:
			# l'avant du camion est -Z
			var cand := xf.translated(xf.basis.x.normalized() * dx - xf.basis.z.normalized() * dz)
			if spot_ok.is_valid() and not bool(spot_ok.call(cand.origin)):
				continue
			# boite au-dessus de la chaussee, de l'avant du tracteur au bout de
			# la remorque
			_respawn_query.transform = cand * Transform3D(Basis.IDENTITY, Vector3(0.0, 2.4, 6.5))
			var blocked := false
			for h: Dictionary in space.intersect_shape(_respawn_query, 4):
				if h["collider"] != _truck:
					blocked = true
					break
			if not blocked:
				return cand
	return xf
