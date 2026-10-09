class_name DamageFx
extends RefCounted

## Briques visuelles des degats (purement visuelles, aucune physique) :
##   - traces de choc : decalques (Decal) projetes sur la carrosserie au point
##     d'impact - eraflures claires pour un frottement, brulure noire et
##     eraflures pour un choc violent. Ils ne marquent que les carrosseries
##     (calque de rendu RENDER_LAYER, pose par TruckVisual), jamais la route ;
##   - fumee (particules CPU, monde) : grise legere ou noire epaisse ;
##   - etincelles (particules CPU) qui crepitent.
## Textures generees une fois, en memoire (aucun fichier, CLAUDE.md §8),
## de facon deterministe.

## Calque de rendu des carrosseries (camions, remorques larguees).
const RENDER_LAYER := 11
const LAYER_BIT := 1 << (RENDER_LAYER - 1)

enum Smoke { NONE, LIGHT, HEAVY, WRECK }

static var _scorch: ImageTexture
static var _scratch: ImageTexture
static var _puff: GradientTexture2D


## Bruit de valeur deterministe (0 .. 1) sur une grille de cellules.
static func _noise(x: float, y: float, seed_value: int) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var fx := x - xi
	var fy := y - yi
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(xi, yi, seed_value)
	var b := _hash(xi + 1, yi, seed_value)
	var c := _hash(xi, yi + 1, seed_value)
	var d := _hash(xi + 1, yi + 1, seed_value)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func _hash(x: int, y: int, seed_value: int) -> float:
	var h := (x * 374761393 + y * 668265263 + seed_value * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## Brulure : tache noire et brune a bord dechiquete, avec quelques eraflures.
static func scorch_texture() -> Texture2D:
	if _scorch == null:
		var size := 128
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			for x in size:
				var u := (x + 0.5) / size * 2.0 - 1.0
				var v := (y + 0.5) / size * 2.0 - 1.0
				var n := _noise(x / 9.0, y / 9.0, 3) * 0.65 + _noise(x / 3.0, y / 3.0, 5) * 0.35
				var d := sqrt(u * u + v * v) + (n - 0.5) * 0.55
				var a := clampf((1.0 - d) * 2.2, 0.0, 1.0) * 0.95
				var col := Color(0.02, 0.018, 0.015).lerp(Color(0.16, 0.09, 0.04), n * (1.0 - a * 0.6))
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
		_draw_scratches(img, 7, 11)
		_scorch = ImageTexture.create_from_image(img)
	return _scorch


## Eraflures : traits clairs (metal mis a nu) et sombres, surtout dans la
## longueur (axe X du decalque).
static func scratch_texture() -> Texture2D:
	if _scratch == null:
		var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_draw_scratches(img, 16, 23)
		_scratch = ImageTexture.create_from_image(img)
	return _scratch


static func _draw_scratches(img: Image, count: int, seed_value: int) -> void:
	var size := img.get_width()
	for k in count:
		var y0 := 16.0 + _hash(k, 1, seed_value) * (size - 32.0)
		var slope := (_hash(k, 2, seed_value) - 0.5) * 0.35
		var x0 := _hash(k, 3, seed_value) * size * 0.4
		var x1 := x0 + size * (0.35 + 0.5 * _hash(k, 4, seed_value))
		var bright := _hash(k, 5, seed_value) > 0.3
		var col := Color(0.82, 0.82, 0.86) if bright else Color(0.05, 0.05, 0.05)
		var x := x0
		while x < minf(x1, size - 1.0):
			var y := y0 + (x - x0) * slope
			var fade := sin(PI * (x - x0) / (x1 - x0))
			for w in 2:
				var py := clampi(roundi(y) + w, 0, size - 1)
				var px := clampi(roundi(x), 0, size - 1)
				var old := img.get_pixel(px, py)
				var a := maxf(old.a, 0.9 * fade * (1.0 if w == 0 else 0.45))
				img.set_pixel(px, py, Color(col.r, col.g, col.b, a))
			x += 1.0


## Trace de choc de gravite `severity` (0 .. 1) : eraflures en dessous de
## 0,35, brulure au-dela ; plus grande quand c'est plus violent.
static func make_mark(severity: float) -> Decal:
	var s := clampf(severity, 0.0, 1.0)
	var d := Decal.new()
	d.name = "DamageMark"
	var size := lerpf(1.3, 3.4, s)
	d.size = Vector3(size * 1.4, 1.4, size)
	d.texture_albedo = scorch_texture() if s >= 0.35 else scratch_texture()
	d.modulate = Color(1.0, 1.0, 1.0, lerpf(0.8, 1.0, s))
	d.albedo_mix = 1.0
	d.cull_mask = LAYER_BIT
	d.upper_fade = 0.25
	d.lower_fade = 0.25
	d.normal_fade = 0.25
	d.set_meta(&"severity", s)
	return d


## Pose le decalque au point local `at`, projete vers la carrosserie : son axe
## +Y suit la normale sortante `outward` (vers l'exterieur du camion), son axe
## X (la longueur des eraflures) reste horizontal.
static func place_mark(d: Decal, at: Vector3, outward: Vector3) -> void:
	var y := outward.normalized()
	var x := Vector3.UP.cross(y)
	if x.length_squared() < 1e-3:
		x = Vector3.RIGHT.cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	d.transform = Transform3D(Basis(x, y, z), at)


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
