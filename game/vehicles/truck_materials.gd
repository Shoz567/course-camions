class_name TruckMaterials
extends RefCounted

## Materiaux realistes des camions et des remorques (2026-10-07 : « le plus
## realiste possible »). Les modeles de l'equipe n'ont que des aplats de
## couleur ; on garde leurs couleurs et on remplace, par nom de materiau, le
## comportement de la matiere :
##
##   peinture    vernis brillant (clearcoat), peau d'orange a peine visible,
##               rugosite irreguliere (lavages, poussiere) ;
##   chrome      miroir ; aluminium, acier, jantes : metal brosse ;
##   pneus       gomme noire mate, relief ; caoutchouc, joints : idem ;
##   chassis     acier peint sale, plus rugueux ;
##   plastiques  grain mat ; vitres : verre fume tres lisse ;
##   feux        verre lisse, allume la nuit (TruckLights.night), a peine
##               lumineux de jour.
##
## Textures procedurales (bruit, NoiseTexture2D), plaquees en triplanaire :
## aucun fichier, aucune UV requise. Une copie par materiau source, partagee
## par tous les camions (cache). Purement visuel.

## Repetitions de texture par metre (triplanaire).
const PAINT_SCALE := 1.6
const METAL_SCALE := 2.5
const RUBBER_SCALE := 6.0

static var _cache: Dictionary = {}
static var _peel: NoiseTexture2D
static var _smudge: NoiseTexture2D
static var _brushed: NoiseTexture2D
static var _streaks: NoiseTexture2D
static var _rubber: NoiseTexture2D
static var _grain: NoiseTexture2D


## Remplace les materiaux des maillages sous `root` (surcharges de surface,
## livree comprise). Renvoie le nombre de surfaces modifiees.
static func upgrade(root: Node) -> int:
	var count := 0
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_surface_override_material(s) as BaseMaterial3D
			if src == null:
				src = mi.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			var m := realistic(src)
			if m != src:
				mi.set_surface_override_material(s, m)
				count += 1
	return count


## Version realiste de `src` (elle-meme si rien ne s'applique, ou deja faite).
static func realistic(src: BaseMaterial3D) -> BaseMaterial3D:
	if src.has_meta(&"realistic"):
		return src
	var kind := kind_of(src.resource_name)
	# un feu n'a pas le meme verre de jour et de nuit (TruckLights.night)
	var key: Variant = src if kind != &"lamp" else [src, TruckLights.night]
	if _cache.has(key):
		return _cache[key]
	var m := src
	if kind != &"":
		m = src.duplicate() as BaseMaterial3D
		_apply(m, kind)
		m.set_meta(&"realistic", kind)
	_cache[key] = m
	return m


## Famille de matiere d'apres le nom du materiau (« Peinture_Cabine_Bleu »,
## « Chrome.001 »...), &"" si inconnue.
static func kind_of(material_name: String) -> StringName:
	var n := material_name.to_lower()
	for p: String in ["peinture", "bande_deco", "texte_logo", "danger", "aimant", "flamme"]:
		if n.begins_with(p):
			return &"paint"
	if n.begins_with("chrome"):
		return &"chrome"
	for p: String in ["aluminium", "laiton", "acier", "jante"]:
		if n.begins_with(p):
			return &"metal"
	for p: String in ["pneu", "caoutchouc", "joint"]:
		if n.begins_with(p):
			return &"rubber"
	if n.begins_with("chassis"):
		return &"chassis"
	for p: String in ["plastique", "carbone", "tissu", "bois", "peluche", "flexible", "plaque", "texte"]:
		if n.begins_with(p):
			return &"plastic"
	for p: String in ["phare", "feu_", "clignotant", "gyrophare"]:
		if n.begins_with(p):
			return &"lamp"
	if n.begins_with("vitre"):
		return &"glass"
	return &""


static func _apply(m: BaseMaterial3D, kind: StringName) -> void:
	_ensure_textures()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match kind:
		&"paint":
			# vernis : base peu metallique, couche claire tres lisse par-dessus
			m.metallic = minf(m.metallic, 0.2)
			m.roughness = 0.42
			m.roughness_texture = _smudge
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.06
			_normal(m, _peel, 0.12, PAINT_SCALE)
			if m.emission_enabled:
				m.emission_energy_multiplier = minf(m.emission_energy_multiplier, 1.5)
		&"chrome":
			m.metallic = 1.0
			m.roughness = 0.12
			m.roughness_texture = _smudge
			m.albedo_color = Color(0.92, 0.92, 0.94)
			_normal(m, _peel, 0.05, PAINT_SCALE)
		&"metal":
			m.metallic = maxf(m.metallic, 0.85)
			m.roughness = maxf(m.roughness, 0.3)
			m.roughness_texture = _streaks
			_normal(m, _brushed, 0.25, METAL_SCALE)
		&"rubber":
			m.albedo_color = Color(0.028, 0.028, 0.03)
			m.metallic = 0.0
			m.roughness = 1.0
			m.roughness_texture = _grain
			m.metallic_specular = 0.35
			_normal(m, _rubber, 0.8, RUBBER_SCALE)
		&"chassis":
			m.albedo_color = m.albedo_color * 0.55
			m.metallic = 0.5
			m.roughness = 0.75
			m.roughness_texture = _smudge
			_normal(m, _grain, 0.35, METAL_SCALE)
		&"plastic":
			m.metallic = 0.0
			m.roughness = maxf(m.roughness, 0.5) + 0.2
			m.roughness_texture = _grain
			_normal(m, _grain, 0.3, RUBBER_SCALE)
		&"glass":
			m.metallic = 0.0
			m.roughness = 0.0
			m.metallic_specular = 0.6
			m.albedo_color = Color(0.05, 0.07, 0.08, 0.55)
		&"lamp":
			# verre de feu : lisse ; allume la nuit, a peine lumineux de jour
			# (un phare eteint au soleil n'est pas un pave blanc)
			m.roughness = 0.05
			m.metallic = 0.0
			if m.emission_enabled:
				var base := 1.0 if m.resource_name.to_lower().begins_with("phare") else 0.6
				m.emission_energy_multiplier = base * (4.0 if TruckLights.night else 0.25)
				if not TruckLights.night:
					m.albedo_color = m.albedo_color * 0.75
	# la rugosite texturee module la valeur de base (canal rouge), sur le
	# meme placage triplanaire que la normale (_normal)
	if m.roughness_texture != null:
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED


static func _normal(m: BaseMaterial3D, tex: Texture2D, strength: float, scale: float) -> void:
	m.normal_enabled = true
	m.normal_texture = tex
	m.normal_scale = strength
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)


static func _noise(freq: float, octaves: int, normal: bool, stretch: Vector2 = Vector2.ONE,
		size: int = 256) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = int(size * stretch.x)
	t.height = int(size * stretch.y)
	t.seamless = true
	t.generate_mipmaps = true
	t.as_normal_map = normal
	if normal:
		t.bump_strength = 6.0
	else:
		# rugosite : de 0,55 a 1 (multiplie la valeur de base)
		var g := Gradient.new()
		g.set_color(0, Color(0.55, 0.55, 0.55))
		g.set_color(1, Color(1.0, 1.0, 1.0))
		t.color_ramp = g
	return t


static func _ensure_textures() -> void:
	if _peel != null:
		return
	_peel = _noise(0.09, 2, true)
	_smudge = _noise(0.012, 4, false)
	_brushed = _noise(0.03, 3, true, Vector2(2.0, 0.25))
	_streaks = _noise(0.03, 3, false, Vector2(2.0, 0.25))
	_rubber = _noise(0.12, 2, true)
	_grain = _noise(0.05, 3, false)
