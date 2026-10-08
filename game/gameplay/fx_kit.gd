class_name FxKit
extends RefCounted

## Briques des particules (2026-10-08 : « ameliore tout ce qui est
## particule ») : emetteurs GPU partages par les degats, les pneus, les
## explosions et les debris. Purement visuel ; l'alea des particules est celui
## du GPU (hors logique de jeu, CLAUDE.md §7). Rien n'est lu sur disque hors
## des shaders du depot (textures generees en memoire, CLAUDE.md §8).
##   - fumee (fx/smoke.gdshader) : bouffees qui tournent, contour ronge par un
##     bruit propre a chacune, eclairees comme des boules (le haut prend la
##     lumiere), fondues contre le decor. Pas de turbulence du moteur : elle
##     fige les bouffees sur place (mesure du 2026-10-08) ; le tourbillon
##     vient de leur rotation et du bruit qui roule dans chacune ;
##   - feu (fx/flame.gdshader) : langues dressees, additives, couleur HDR ;
##   - etincelles (fx/spark_particles.gdshader + fx/spark.gdshader) : traits
##     etires sur leur vitesse, qui refroidissent et rebondissent sur la
##     route (plan sous l'emetteur) ;
##   - eclats de tole froissee : plaques irregulieres pliees (SHARD_VARIANTS
##     maillages generes une fois, deterministes).

const SMOKE_SHADER := preload("res://gameplay/fx/smoke.gdshader")
const FLAME_SHADER := preload("res://gameplay/fx/flame.gdshader")
const SPARK_SHADER := preload("res://gameplay/fx/spark.gdshader")
const SPARK_PARTICLES := preload("res://gameplay/fx/spark_particles.gdshader")
const SHARD_VARIANTS := 6
## Epaisseur d'un eclat, en part de sa largeur (maillage unitaire).
const SHARD_THICKNESS := 0.08
## Boite de visibilite des emetteurs en coordonnees monde (le panache reste
## derriere un camion lance).
const WORLD_AABB := AABB(Vector3(-40.0, -10.0, -40.0), Vector3(80.0, 40.0, 80.0))
## Lueur propre de la fumee la nuit (part de sa couleur).
const NIGHT_SMOKE_LIGHT := 0.6

static var _noise: NoiseTexture2D
static var _smoke_mat: ShaderMaterial
static var _smoke_mat_night := false
static var _flame_mat: ShaderMaterial
static var _spark_mat: ShaderMaterial
static var _shards: Array[ArrayMesh] = []


## Bruit des volutes (fumee, feu) : fBm doux, raccordable, genere une fois.
static func noise() -> NoiseTexture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.seed = 11
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.012
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.generate_mipmaps = true
		_noise.noise = n
	return _noise


## Densite des particules : moitie en qualite basse.
static func density() -> float:
	return 0.5 if GameState.graphics_quality == GraphicsSettings.Quality.LOW else 1.0


## Materiau des bouffees ; `glow` : lueur de feu par-dessous, qui s'eteint
## sur la premiere part `glow_until` de leur vie. De nuit (TruckLights.night),
## la fumee renvoie un peu la lueur de la ville : sinon noire sur un ciel
## noir. Sans lueur : partage (un par ambiance).
static func smoke_material(glow: Color = Color.BLACK, glow_until: float = 0.3) -> ShaderMaterial:
	var night := TruckLights.night
	if glow == Color.BLACK and _smoke_mat != null and _smoke_mat_night == night:
		return _smoke_mat
	var m := ShaderMaterial.new()
	m.shader = SMOKE_SHADER
	m.set_shader_parameter("noise_tex", noise())
	m.set_shader_parameter("glow", Vector3(glow.r, glow.g, glow.b))
	m.set_shader_parameter("glow_until", glow_until)
	m.set_shader_parameter("self_light", NIGHT_SMOKE_LIGHT if night else 0.0)
	if glow == Color.BLACK:
		_smoke_mat = m
		_smoke_mat_night = night
	return m


## Materiau des flammes ; `tall` : etirement vertical (1 : boule de feu
## ronde d'une explosion). Le reglage par defaut est partage.
static func flame_material(tall: float = 1.35) -> ShaderMaterial:
	if tall == 1.35 and _flame_mat != null:
		return _flame_mat
	var m := ShaderMaterial.new()
	m.shader = FLAME_SHADER
	m.set_shader_parameter("noise_tex", noise())
	m.set_shader_parameter("tall", tall)
	if tall == 1.35:
		_flame_mat = m
	return m


static func _quad(material: Material, size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = material
	return q


## Courbe 0..1 par points [x, y].
static func curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	# au-dela de 1 (croissance) : sinon la courbe est bornee a 1
	for pt: Array in points:
		c.max_value = maxf(c.max_value, pt[1])
	for pt: Array in points:
		c.add_point(Vector2(pt[0], pt[1]))
	var t := CurveTexture.new()
	t.curve = c
	return t


## Rampe de couleur par arrets [position, Color] ; `hdr` : couleurs > 1.
static func ramp(stops: Array, hdr: bool = false) -> GradientTexture1D:
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s: Array in stops:
		offs.append(s[0])
		cols.append(s[1])
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = hdr
	return t


static func _emitter(node_name: String, amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.fixed_fps = 0
	p.visibility_aabb = WORLD_AABB
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Panache de fumee (eteint) : bouffees en coordonnees monde qui montent,
## grossissent, tournent et s'effacent ; la couleur et le debit se reglent
## par set_smoke_look (amount_ratio : le panache ne repart pas).
static func make_smoke(amount: int = 64, lifetime: float = 2.2, quad: float = 1.8,
		material: Material = null) -> GPUParticles3D:
	var p := _emitter("Smoke", amount, lifetime)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3.UP
	pm.spread = 20.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 3.6
	pm.inherit_velocity_ratio = 0.3
	pm.damping_min = 0.4
	pm.damping_max = 0.8
	pm.gravity = Vector3(0.0, 1.8, 0.0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -35.0
	pm.angular_velocity_max = 35.0
	# graine de la bouffee (INSTANCE_CUSTOM.z) : son propre motif de bruit
	pm.anim_offset_max = 1.0
	pm.lifetime_randomness = 0.3
	pm.scale_min = 0.9
	pm.scale_max = 1.5
	pm.scale_curve = curve([[0.0, 0.3], [0.35, 0.75], [1.0, 1.3]])
	pm.color_ramp = ramp([[0.0, Color(1, 1, 1, 0)], [0.07, Color(1, 1, 1, 1)],
		[0.5, Color(1, 1, 1, 0.65)], [1.0, Color(1, 1, 1, 0)]])
	p.process_material = pm
	p.draw_pass_1 = _quad(material if material != null else smoke_material(), quad)
	return p


## Couleur (alpha = opacite), debit (part de `amount`) et taille des
## bouffees d'un panache ; eteint si `ratio` <= 0.
static func set_smoke_look(p: GPUParticles3D, color: Color, ratio: float, scale_min: float,
		scale_max: float) -> void:
	var pm := p.process_material as ParticleProcessMaterial
	pm.color = color
	pm.scale_min = scale_min
	pm.scale_max = scale_max
	p.amount_ratio = clampf(ratio * density(), 0.05, 1.0)
	p.emitting = ratio > 0.0


## Feu (eteint) : langues qui montent vite et s'eteignent du jaune au rouge.
static func make_fire(amount: int = 40, lifetime: float = 0.65, quad: float = 1.0) -> GPUParticles3D:
	var p := _emitter("Fire", amount, lifetime)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3.UP
	pm.spread = 14.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.6
	pm.inherit_velocity_ratio = 0.7
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.gravity = Vector3(0.0, 3.5, 0.0)
	pm.anim_offset_max = 1.0
	pm.lifetime_randomness = 0.35
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	pm.scale_curve = curve([[0.0, 0.55], [0.25, 1.0], [1.0, 0.25]])
	pm.color_ramp = ramp([[0.0, Color(4.0, 3.0, 1.6, 1.0)], [0.3, Color(3.2, 1.3, 0.3, 1.0)],
		[0.7, Color(1.2, 0.25, 0.04, 0.7)], [1.0, Color(0, 0, 0, 0)]], true)
	p.process_material = pm
	p.draw_pass_1 = _quad(flame_material(), quad)
	return p


## Etincelles (eteintes) : `params` regle spark_particles.gdshader (direction,
## vitesses, sol...). Un materiau par emetteur (ses reglages lui sont propres).
static func make_sparks(amount: int = 40, lifetime: float = 0.6, params: Dictionary = {}) -> GPUParticles3D:
	var p := _emitter("Sparks", amount, lifetime)
	var pm := ShaderMaterial.new()
	pm.shader = SPARK_PARTICLES
	for k: String in params:
		pm.set_shader_parameter(k, params[k])
	p.process_material = pm
	if _spark_mat == null:
		_spark_mat = ShaderMaterial.new()
		_spark_mat.shader = SPARK_SHADER
	p.draw_pass_1 = _quad(_spark_mat, 1.0)
	return p


## Regle un parametre des etincelles `p`.
static func spark_param(p: GPUParticles3D, key: StringName, value: Variant) -> void:
	(p.process_material as ShaderMaterial).set_shader_parameter(key, value)


static func get_spark_param(p: GPUParticles3D, key: StringName) -> Variant:
	return (p.process_material as ShaderMaterial).get_shader_parameter(key)


## Tir unique de `p` sous `world`, au point monde `at` : il se libere une fois
## toutes ses particules eteintes. Rien en headless (purement visuel).
static func fire_once(world: Node, p: GPUParticles3D, at: Vector3, explosiveness: float = 1.0) -> GPUParticles3D:
	if DisplayServer.get_name() == "headless":
		p.free()
		return null
	p.one_shot = true
	p.explosiveness = explosiveness
	# pose AVANT l'entree dans l'arbre : un emetteur deplace apres coup etale
	# sa premiere emission sur le trajet (peigne de traits paralleles)
	var base := world as Node3D
	p.position = base.global_transform.affine_inverse() * at if base != null and base.is_inside_tree() else at
	world.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Eclat de tole froissee numero `k` : plaque irreguliere de 1 x 1 (x, z),
## epaisse de SHARD_THICKNESS, pliee et cabossee ; a mettre a l'echelle.
static func shard_mesh(k: int) -> ArrayMesh:
	if _shards.is_empty():
		for i in SHARD_VARIANTS:
			_shards.append(_build_shard(101 + i * 37))
	return _shards[posmod(k, SHARD_VARIANTS)]


static func _build_shard(seed_value: int) -> ArrayMesh:
	const N := 7
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var outer := PackedVector2Array()
	var phase := rng.randf() * TAU
	for i in N:
		var a := phase + (float(i) + rng.randf_range(-0.3, 0.3)) / N * TAU
		outer.append(Vector2(cos(a), sin(a)) * rng.randf_range(0.3, 0.5))
	# cadre dans 1 x 1
	var lo := outer[0]
	var hi := outer[0]
	for v in outer:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	var c := (lo + hi) * 0.5
	var span := (hi - lo).max(Vector2(0.01, 0.01))
	for i in N:
		outer[i] = (outer[i] - c) / span
	# pli (parabole), torsion, et creux au hasard sur l'anneau du milieu
	var bend := rng.randf_range(-0.35, 0.35)
	var twist := rng.randf_range(-0.3, 0.3)
	var crease := PackedFloat32Array()
	for i in N:
		crease.append(rng.randf_range(-0.06, 0.06))
	var top: Array[Vector3] = [Vector3(0.0, rng.randf_range(-0.04, 0.04), 0.0)]
	for ring: float in [0.5, 1.0]:
		for i in N:
			var p := outer[i] * ring
			var y := bend * p.x * p.x * 2.0 + twist * p.x * p.y * 2.0 + (crease[i] if ring < 1.0 else 0.0)
			top.append(Vector3(p.x, y, p.y))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var down := Vector3(0.0, -SHARD_THICKNESS, 0.0)
	for face: int in [0, 1]:
		var off := Vector3.ZERO if face == 0 else down
		for i in N:
			var j := (i + 1) % N
			var m0 := top[1 + i] + off
			var m1 := top[1 + j] + off
			var o0 := top[1 + N + i] + off
			var o1 := top[1 + N + j] + off
			# angle croissant vu de dessus : sens horaire (face avant de Godot)
			_tri(st, top[0] + off, m0, m1, face == 1)
			_tri(st, m0, o0, o1, face == 1)
			_tri(st, m0, o1, m1, face == 1)
	# tranche
	for i in N:
		var j := (i + 1) % N
		var a := top[1 + N + i]
		var b := top[1 + N + j]
		_tri(st, a, a + down, b + down, true)
		_tri(st, a, b + down, b, true)
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, flip: bool) -> void:
	for v: Vector3 in ([a, c, b] if flip else [a, b, c]):
		st.set_uv(Vector2(v.x + 0.5, v.z + 0.5))
		st.add_vertex(v)
