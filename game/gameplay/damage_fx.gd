class_name DamageFx
extends RefCounted

## Briques visuelles des degats (purement visuelles, aucune physique) :
##   - traces de choc : cicatrices peintes dans la carrosserie (BodyScars,
##     truck_body.gdshader) au point d'impact - eraflures et vernis terni
##     pour un frottement, peinture arrachee, tole nue rayee et pliee pour un
##     choc plus fort, suie au centre d'un choc violent. Chaque trace garde
##     un repere (DamageMark, Node3D sans rendu) : position, axe sortant et
##     gravite ; elles remplacent les decalques d'eraflures (2026-10-07 :
##     « des traits blancs, pas tres realiste ») ;
##   - fumee (particules CPU, monde) : grise legere ou noire epaisse ;
##   - etincelles (particules CPU) qui crepitent.
## Textures generees une fois, en memoire (aucun fichier, CLAUDE.md §8).

## Calque de rendu des carrosseries (camions, remorques larguees, debris).
const RENDER_LAYER := 11
const LAYER_BIT := 1 << (RENDER_LAYER - 1)
## Rayon d'une cicatrice (m) : eraflure legere .. choc violent.
const SCAR_RADIUS := Vector2(0.55, 1.5)

enum Smoke { NONE, LIGHT, HEAVY, WRECK }

static var _puff: GradientTexture2D


## Repere d'une trace de choc de gravite `severity` (0 .. 1).
static func make_mark(severity: float) -> Node3D:
	var d := Node3D.new()
	d.name = "DamageMark"
	d.set_meta(&"severity", clampf(severity, 0.0, 1.0))
	return d


## Pose le repere au point local `at` : son axe +Y suit la normale sortante
## `outward` (vers l'exterieur du camion), son axe X (le sens du frottement)
## reste horizontal.
static func place_mark(d: Node3D, at: Vector3, outward: Vector3) -> void:
	var y := outward.normalized()
	var x := Vector3.UP.cross(y)
	if x.length_squared() < 1e-3:
		x = Vector3.RIGHT.cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	d.transform = Transform3D(Basis(x, y, z), at)


## Trace de choc complete : repere `d` pose sous `parent` au point monde
## `point`, et cicatrice peinte sur les carrosseries de `parent` autour.
static func scar(parent: Node3D, point: Vector3, outward: Vector3, severity: float) -> Node3D:
	var d := make_mark(severity)
	var inv := parent.global_transform.affine_inverse()
	place_mark(d, inv * point, inv.basis * outward)
	parent.add_child(d)
	var s := clampf(severity, 0.0, 1.0)
	BodyScars.add(parent, point, lerpf(SCAR_RADIUS.x, SCAR_RADIUS.y, s), lerpf(0.3, 1.0, s))
	return d


static func _puff_texture() -> Texture2D:
	if _puff == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		_puff = GradientTexture2D.new()
		_puff.gradient = g
		_puff.fill = GradientTexture2D.FILL_RADIAL
		_puff.fill_from = Vector2(0.5, 0.5)
		_puff.fill_to = Vector2(1.0, 0.5)
		_puff.width = 64
		_puff.height = 64
	return _puff


## Panache de fumee (eteint) : bouffees en coordonnees monde, qui montent,
## grossissent et s'effacent.
static func make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.emitting = false
	p.amount = 48
	p.lifetime = 1.6
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 18.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.2
	p.gravity = Vector3(0.0, 2.0, 0.0)
	p.damping_min = 0.6
	p.damping_max = 1.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.scale_amount_min = 0.9
	p.scale_amount_max = 1.5
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 2.0))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.15, Color(1, 1, 1, 1.0))
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _puff_texture()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Regle le panache : rien, gris leger, noir epais, ou fumee d'epave (le
## nombre de bouffees change : le panache repart, une fois par palier).
static func set_smoke(p: CPUParticles3D, level: int) -> void:
	if p == null:
		return
	match level:
		Smoke.NONE:
			p.emitting = false
		Smoke.LIGHT:
			p.color = Color(0.85, 0.85, 0.88, 0.5)
			p.amount = 16
			p.scale_amount_min = 0.8
			p.scale_amount_max = 1.3
			p.emitting = true
		Smoke.HEAVY:
			# anthracite plutot que noir : il se voit encore sur un ciel de nuit
			p.color = Color(0.17, 0.16, 0.16, 0.9)
			p.amount = 48
			p.scale_amount_min = 1.3
			p.scale_amount_max = 2.1
			p.emitting = true
		_:
			p.color = Color(0.13, 0.12, 0.12, 0.95)
			p.amount = 60
			p.scale_amount_min = 1.8
			p.scale_amount_max = 2.8
			p.emitting = true


## Etincelles (eteintes) : petits eclats orange qui jaillissent et retombent.
static func make_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Sparks"
	p.emitting = false
	p.amount = 18
	p.lifetime = 0.45
	p.explosiveness = 0.35
	p.randomness = 0.6
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0.0, -14.0, 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var spark := BoxMesh.new()
	spark.size = Vector3(0.06, 0.06, 0.22)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.12)
	mat.emission_energy_multiplier = 6.0
	spark.material = mat
	p.mesh = spark
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
