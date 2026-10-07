class_name TruckMaterials
extends RefCounted

## Materiaux realistes des camions et des remorques (2026-10-07 : « le plus
## realiste possible », « pas qu'ils ressemblent a des jouets »). Les modeles
## de l'equipe n'ont que des aplats de couleur ; on garde leurs couleurs (un
## peu moins saturees : la peinture industrielle n'est pas celle d'un jouet)
## et on remplace, par nom de materiau, le comportement de la matiere :
##
##   peinture    vernis (clearcoat), peau d'orange a peine visible ;
##   chrome      miroir ; aluminium, acier : metal brosse ; jantes : acier
##               peint satine (pas un miroir) ;
##   pneus       gomme gris-noir mate, poussiereuse ; caoutchouc, joints ;
##   chassis     acier peint, sale ;
##   plastiques  grain mat ; vitres : verre fume tres lisse ;
##   feux        reflecteur chrome derriere un verre lisse : allume la nuit
##               (TruckLights.night), eteint de jour (plus de pave blanc).
##
## Les matieres opaques passent par truck_body.gdshader : la salissure de la
## route (boue basse, coulures, poussiere sur le dessus, pluie) y est
## calculee d'apres la hauteur au-dessus du sol, posee par maillage
## (upgrade). Couleur de la salissure et pluie : set_weather (par circuit).
## Textures procedurales (bruit), aucun fichier. Une copie par materiau
## source, partagee par tous les camions (cache). Purement visuel.

const BODY_SHADER := preload("res://vehicles/truck_body.gdshader")
## Saturation et luminosite gardees des peintures d'origine.
const PAINT_SATURATION := 0.86
const PAINT_VALUE := 0.94
## Salissure de la route (set_weather) : crasse de ville, poussiere de plage.
const CITY_GRIME := Color(0.1, 0.085, 0.07)
const BEACH_GRIME := Color(0.46, 0.39, 0.29)

static var _cache: Dictionary = {}
static var _detail: NoiseTexture2D
static var _grime: NoiseTexture2D


## Matieres realistes pour les maillages sous `root` (surcharges de surface,
## livree comprise), et hauteur au-dessus du sol de chaque maillage, mesuree
## dans le repere de `frame` (le camion ; sol `ground_y`, par defaut le bas
## des pneus). `root` doit etre dans l'arbre. Renvoie le nombre de surfaces
## modifiees.
static func upgrade(root: Node3D, frame: Node3D = null, ground_y: float = NAN) -> int:
	var count := 0
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	if frame == null:
		frame = root
	if is_nan(ground_y):
		ground_y = lowest_point(root, frame)
	var inv := frame.global_transform.affine_inverse()
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_surface_override_material(s)
			if src == null:
				src = mi.mesh.surface_get_material(s)
			var base := src as BaseMaterial3D
			if base == null:
				continue
			var m := realistic(base)
			if m != src:
				mi.set_surface_override_material(s, m)
				count += 1
		# hauteur au-dessus du sol d'un sommet : ligne y de maillage -> camion
		var xf := inv * mi.global_transform
		mi.set_instance_shader_parameter(&"height_row",
			Vector4(xf.basis.x.y, xf.basis.y.y, xf.basis.z.y, xf.origin.y - ground_y))
	return count


## Plus bas point des maillages sous `root`, dans le repere de `frame`.
static func lowest_point(root: Node3D, frame: Node3D) -> float:
	var inv := frame.global_transform.affine_inverse()
	var low := INF
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := (inv * mi.global_transform) * mi.get_aabb()
		low = minf(low, box.position.y)
	return low if low < INF else 0.0


## Salissure et pluie des camions pour ce circuit : poussiere claire au bord
## de mer, crasse sombre et carrosseries mouillees sous la pluie.
static func set_weather(grime_color: Color, wetness: float) -> void:
	RenderingServer.global_shader_parameter_set(&"truck_grime_color", grime_color)
	RenderingServer.global_shader_parameter_set(&"truck_wetness", wetness)


## Version realiste de `src` (elle-meme si rien ne s'applique, ou deja faite).
static func realistic(src: BaseMaterial3D) -> Material:
	if src.has_meta(&"realistic"):
		return src
	var kind := kind_of(src.resource_name)
	# un feu n'a pas le meme verre de jour et de nuit (TruckLights.night)
	var key: Variant = src if kind != &"lamp" else [src, TruckLights.night]
	if _cache.has(key):
		return _cache[key]
	var m: Material = src
	match kind:
		&"":
			pass
		&"glass", &"lamp":
			var b := src.duplicate() as BaseMaterial3D
			_apply_lamp_or_glass(b, kind)
			m = b
		_:
			m = _body(src, kind)
	if m != src:
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
	if n.begins_with("jante"):
		return &"rim"
	for p: String in ["aluminium", "laiton", "acier"]:
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


## Matiere opaque vieillie (truck_body.gdshader) d'apres `src`.
static func _body(src: BaseMaterial3D, kind: StringName) -> ShaderMaterial:
	_ensure_textures()
	var m := ShaderMaterial.new()
	m.shader = BODY_SHADER
	m.resource_name = src.resource_name
	var col := src.albedo_color
	var metal := src.metallic
	var rough := src.roughness
	var coat := 0.0
	var coat_rough := 0.05
	var spec := 0.5
	# relief : amplitude (m), repetitions par metre, etirement
	var bump := 0.00004
	var scale := 3.0
	var stretch := Vector2.ONE
	var variation := 0.15
	var grime := 1.0
	var scars := 1.0
	match kind:
		&"paint":
			col = Color.from_hsv(col.h, col.s * PAINT_SATURATION, col.v * PAINT_VALUE, col.a)
			metal = minf(metal, 0.15)
			rough = 0.38
			coat = 1.0
			coat_rough = 0.04
			bump = 0.00003
			scale = 4.0
			variation = 0.25
		&"chrome":
			col = Color(0.9, 0.9, 0.92)
			metal = 1.0
			rough = 0.1
			bump = 0.00001
			variation = 0.1
			grime = 0.6
		&"rim":
			# acier peint satine : clair, un peu metallique, jamais un miroir
			var v := clampf(col.v, 0.35, 0.8)
			col = Color(v, v, v * 1.02)
			metal = 0.45
			rough = 0.42
			bump = 0.00002
			grime = 1.0
		&"metal":
			metal = maxf(metal, 0.85)
			rough = maxf(rough, 0.32)
			bump = 0.00003
			scale = 1.5
			stretch = Vector2(1.0, 12.0)
			variation = 0.3
		&"rubber":
			col = Color(0.045, 0.045, 0.048)
			metal = 0.0
			rough = 0.9
			spec = 0.35
			bump = 0.0002
			scale = 9.0
			variation = 0.1
			grime = 0.45
			scars = 0.0
		&"chassis":
			col = col * 0.6
			metal = 0.45
			rough = 0.7
			bump = 0.00008
			grime = 1.5
		&"plastic":
			metal = 0.0
			rough = minf(maxf(rough, 0.5) + 0.15, 0.95)
			bump = 0.00006
			scale = 8.0
	m.set_shader_parameter(&"albedo", col)
	m.set_shader_parameter(&"metallic", metal)
	m.set_shader_parameter(&"roughness", rough)
	m.set_shader_parameter(&"specular", spec)
	m.set_shader_parameter(&"clearcoat", coat)
	m.set_shader_parameter(&"clearcoat_roughness", coat_rough)
	if src.emission_enabled:
		m.set_shader_parameter(&"emission", src.emission)
		m.set_shader_parameter(&"emission_energy", minf(src.emission_energy_multiplier, 1.5))
	m.set_shader_parameter(&"detail_tex", _detail)
	m.set_shader_parameter(&"detail_scale", scale)
	m.set_shader_parameter(&"detail_stretch", stretch)
	m.set_shader_parameter(&"bump_strength", bump)
	m.set_shader_parameter(&"rough_variation", variation)
	m.set_shader_parameter(&"grime", grime)
	m.set_shader_parameter(&"scars", scars)
	m.set_shader_parameter(&"grime_tex", _grime)
	return m


static func _apply_lamp_or_glass(m: BaseMaterial3D, kind: StringName) -> void:
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if kind == &"glass":
		m.metallic = 0.0
		m.roughness = 0.0
		m.metallic_specular = 0.6
		m.albedo_color = Color(0.05, 0.07, 0.08, 0.55)
		return
	# feu : reflecteur chrome sous un verre lisse, teinte d'origine ; allume
	# la nuit, eteint de jour (un phare au soleil n'est pas un pave blanc)
	var lname := m.resource_name.to_lower()
	var headlamp := lname.begins_with("phare") or lname.begins_with("feu_recul")
	m.metallic = 0.85 if headlamp else 0.3
	m.roughness = 0.08
	m.metallic_specular = 0.7
	m.albedo_color = Color(0.72, 0.72, 0.7) if headlamp else m.albedo_color * 0.8
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.02
	if m.emission_enabled:
		var base := 1.0 if headlamp else 0.6
		m.emission_energy_multiplier = base * (4.0 if TruckLights.night else 0.04)


static func _noise(freq: float, octaves: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	t.generate_mipmaps = true
	return t


static func _ensure_textures() -> void:
	if _detail != null:
		return
	_detail = _noise(0.06, 3)
	_grime = _noise(0.02, 5)
