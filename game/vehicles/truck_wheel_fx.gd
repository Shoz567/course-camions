class_name TruckWheelFx
extends Node3D

## Effets des roues (enfant « WheelFx » du camion, 2026-10-08 : graphismes et
## effets de course). Purement visuel ; le calcul du glissement tourne aussi
## en headless (tests), les effets n'y sont pas crees.
##   - glissement des roues arriere (motrices, jamais braquees) : vitesse
##     laterale du pneu sur la route (m/s), au point de contact ;
##   - traces de gomme : au-dela de SKID_SLIDE_MS, chaque roue arriere pose
##     des segments sombres sur la route, en coordonnees monde (un MultiMesh
##     par camion, anneau de MAX_SEGMENTS : les plus anciennes s'effacent) ;
##   - fumee de pneus : au-dela de SMOKE_SLIDE_MS, d'autant plus epaisse que
##     le pneu glisse ;
##   - projections derriere les roues motrices et le train de la remorque,
##     au-dela de SPRAY_FROM_KMH, selon le circuit (`spray`, pose par la
##     course) : poussiere de sable a Playa del Sol, gerbes d'eau sous la
##     pluie de Cyber City.
## Bouffees dessinees comme la fumee des degats (FxKit.smoke_material).
## Rien sur une roue en l'air, ni sur un pneu eclate (la jante crache deja
## ses etincelles, TruckTires). Aucun tirage aleatoire cote jeu.

enum Spray { NONE, DUST, WATER }

## Projections des camions de la course en cours (LocalRace, selon le theme).
static var spray: int = Spray.NONE

## Roues observees : arriere gauche et droite du tracteur.
const WHEELS: PackedInt32Array = [2, 3]
const SKID_SLIDE_MS := 3.5
const SMOKE_SLIDE_MS := 5.0
## Glissement auquel la fumee est la plus epaisse.
const SMOKE_FULL_MS := 14.0
const SPRAY_FROM_KMH := 40.0
const SPRAY_FULL_KMH := 140.0
## Segments de trace par camion, largeur (m), pas minimal entre deux points,
## et saut au-dela duquel la trace repart de zero (reapparition, saut).
const MAX_SEGMENTS := 720
const MARK_WIDTH := 0.42
const MARK_STEP_M := 0.35
const MARK_BREAK_M := 3.0
## Hauteur des traces au-dessus de la route (pas de scintillement).
const MARK_LIFT_M := 0.025

var _truck: Truck
var _slide := PackedFloat32Array([0.0, 0.0])
var _marking := PackedByteArray([0, 0])
var _last := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var _visual := false
var _mm: MultiMesh
var _next := 0
var _count := 0
var _smoke: Array[GPUParticles3D] = []
## Projections : roues arriere du tracteur, puis train de la remorque
## (gauche, droite).
var _spray: Array[GPUParticles3D] = []

static var _mark_mat: StandardMaterial3D


func _ready() -> void:
	_truck = get_parent() as Truck
	if _truck == null or DisplayServer.get_name() == "headless":
		return
	_visual = true
	_build_marks()
	for k in WHEELS.size():
		var s := _make_smoke()
		add_child(s)
		_smoke.append(s)
	if spray != Spray.NONE:
		for k in 4:
			var p := _make_spray(spray)
			add_child(p)
			_spray.append(p)


## Glissement (m/s) de la roue arriere `k` (0 : gauche, 1 : droite) au
## dernier tick ; 0 en l'air.
func slide(k: int) -> float:
	return _slide[k]


## Vrai si la roue arriere `k` pose une trace a ce tick.
func is_marking(k: int) -> bool:
	return _marking[k] == 1


## Segments de trace poses depuis le debut (borne a MAX_SEGMENTS).
func mark_count() -> int:
	return _count


## Intensite de la fumee pour ce glissement (m/s) : 0 .. 1.
static func smoke_for(slide_ms: float) -> float:
	return clampf((slide_ms - SMOKE_SLIDE_MS) / (SMOKE_FULL_MS - SMOKE_SLIDE_MS), 0.0, 1.0)


func _physics_process(_delta: float) -> void:
	if _truck == null:
		return
	var xf := _truck.global_transform
	var right := xf.basis.x.normalized()
	var com := xf * _truck.center_of_mass
	var on_ground := not _truck.is_wrecked()
	for k in WHEELS.size():
		var w := WHEELS[k]
		var probe := _truck.get_probe(w)
		var s := 0.0
		if on_ground and probe.in_contact and not _truck.is_tire_burst(w):
			var p := probe.contact_point
			var v := _truck.linear_velocity + _truck.angular_velocity.cross(p - com)
			s = absf(v.dot(right))
		_slide[k] = s
		var mark := s >= SKID_SLIDE_MS
		if mark:
			var at := probe.contact_point + probe.contact_normal * MARK_LIFT_M
			if _marking[k] == 0 or at.distance_to(_last[k]) > MARK_BREAK_M:
				_last[k] = at
			elif at.distance_to(_last[k]) >= MARK_STEP_M:
				_add_segment(_last[k], at, probe.contact_normal, s)
				_last[k] = at
		_marking[k] = 1 if mark else 0
	if _visual:
		_update_fx(xf)


func _add_segment(from: Vector3, to: Vector3, n: Vector3, s: float) -> void:
	_count = mini(_count + 1, MAX_SEGMENTS)
	if _mm == null:
		return
	var dir := to - from
	var length := dir.length()
	var z := dir / length
	var x := n.cross(z).normalized()
	var y := z.cross(x)
	var b := Basis(x * MARK_WIDTH, y, z * (length + 0.06))
	_mm.set_instance_transform(_next, Transform3D(b, (from + to) * 0.5))
	var a := clampf(0.35 + (s - SKID_SLIDE_MS) / 8.0, 0.35, 0.85)
	_mm.set_instance_color(_next, Color(1.0, 1.0, 1.0, a))
	_next = (_next + 1) % MAX_SEGMENTS
	_mm.visible_instance_count = _count


func _update_fx(xf: Transform3D) -> void:
	var inv := xf.affine_inverse()
	for k in _smoke.size():
		var w := WHEELS[k]
		var f := smoke_for(_slide[k])
		var fx := _smoke[k]
		var on := f > 0.0
		if on:
			fx.position = inv * _truck.get_probe(w).contact_point + Vector3(0.0, 0.35, 0.0)
			fx.amount_ratio = lerpf(0.3, 1.0, f)
		if fx.emitting != on:
			fx.emitting = on
	if _spray.is_empty():
		return
	var kmh := _truck.linear_velocity.length() * 3.6
	var r := clampf((kmh - SPRAY_FROM_KMH) / (SPRAY_FULL_KMH - SPRAY_FROM_KMH), 0.0, 1.0)
	var trailer_down := not _truck.is_trailer_detached() and _truck.wheels_on_ground() >= 2
	for k in _spray.size():
		var fx := _spray[k]
		var on := r > 0.0 and not _truck.is_wrecked()
		if k < 2:
			var probe := _truck.get_probe(WHEELS[k])
			on = on and probe.in_contact and not _truck.is_tire_burst(WHEELS[k])
			if on:
				fx.position = inv * probe.contact_point + Vector3(0.0, 0.25, 0.4)
		else:
			var wheel := Truck.TRAILER_LEFT if k == 2 else Truck.TRAILER_RIGHT
			on = on and trailer_down and not _truck.is_tire_burst(wheel)
			if on:
				fx.position = _truck.trailer_wheel_local(wheel) + Vector3(0.0, 0.25, 0.6)
		if on:
			fx.amount_ratio = lerpf(0.25, 1.0, r)
		if fx.emitting != on:
			fx.emitting = on


func _build_marks() -> void:
	if _mark_mat == null:
		# bande de gomme : bords adoucis, quelques rainures de la bande de
		# roulement dans la longueur
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.3, 0.38, 0.62, 0.7, 0.88, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 1.0),
			Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.6), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.9),
			Color(1, 1, 1, 0.0)])
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.width = 64
		tex.height = 4
		_mark_mat = StandardMaterial3D.new()
		_mark_mat.albedo_color = Color(0.025, 0.024, 0.024)
		_mark_mat.albedo_texture = tex
		_mark_mat.vertex_color_use_as_albedo = true
		_mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mark_mat.roughness = 0.55
		_mark_mat.render_priority = -1
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	plane.material = _mark_mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = plane
	_mm.instance_count = MAX_SEGMENTS
	_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = "SkidMarks"
	mi.multimesh = _mm
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.custom_aabb = AABB(Vector3(-4000.0, -400.0, -4000.0), Vector3(8000.0, 800.0, 8000.0))
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY


static func _particles(name: String, amount: int, lifetime: float, color: Color,
		size: float, grow: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = name
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30.0, -10.0, -30.0), Vector3(60.0, 30.0, 60.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, grow))
	curve.max_value = maxf(grow, 1.0)
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	ramp.colors = PackedColorArray([Color(color, 0.0), color, Color(color, 0.0)])
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	# bouffees des degats (FxKit, 2026-10-08) : contour ronge propre a chacune
	# (graine INSTANCE_CUSTOM.z), eclairees, fondues contre la route
	pm.anim_offset_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = FxKit.smoke_material()
	p.draw_pass_1 = quad
	return p


## Fumee de pneu : bouffees blanc-gris qui gonflent et montent doucement.
static func _make_smoke() -> GPUParticles3D:
	var p := _particles("TireSmoke", 140, 2.2, Color(0.86, 0.86, 0.88, 0.4), 1.8, 4.0)
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0.0, 0.5, 0.0)
	return p


## Projections : sable (nuage qui traine et retombe lentement) ou eau
## (bruine fine qui suit un peu le camion puis se dissipe).
static func _make_spray(kind: int) -> GPUParticles3D:
	var water := kind == Spray.WATER
	var p: GPUParticles3D
	if water:
		p = _particles("WaterSpray", 110, 0.9, Color(0.75, 0.79, 0.88, 0.3), 1.3, 3.6)
	else:
		p = _particles("Dust", 90, 2.0, Color(0.82, 0.72, 0.56, 0.4), 1.8, 4.5)
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0.0, 0.7, 1.0)
	pm.spread = 30.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 6.0
	pm.inherit_velocity_ratio = 0.45 if water else 0.15
	pm.gravity = Vector3(0.0, -2.5 if water else -0.3, 0.0)
	return p
