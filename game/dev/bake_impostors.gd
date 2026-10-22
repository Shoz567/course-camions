extends SceneTree

## Photographie les arbres 3D pour leurs sprites lointains (FarLod,
## tracks/impostors/*.png) : chaque modele de reference (le palmier de Playa,
## le cerisier de Sakura, avec leurs vraies matieres), de profil, en
## projection orthogonale, sur fond transparent, sous une lumiere douce (le
## jeu eclaire le sprite comme le reste). Le cadre est un carre de
## FarLod.KINDS[kind].size m, pied du modele `bottom` m au-dessus du bas.
## A relancer si un modele d'arbre change (fenetre, pas en headless) :
##   godot --path game -s res://dev/bake_impostors.gd

const RES := 256

var _f := 0
var _view: SubViewport
var _queue: Array[String] = ["palm", "cherry", "palm_hd", "cherry_hd"]
var _kind: String = ""
var _stage: Node3D


func _process(_d: float) -> bool:
	_f += 1
	if _f == 1:
		_view = SubViewport.new()
		_view.size = Vector2i(RES, RES)
		_view.transparent_bg = true
		_view.own_world_3d = true
		_view.msaa_3d = Viewport.MSAA_8X
		_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(_view)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(1.0, 1.0, 1.0)
		env.ambient_light_energy = 0.75
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		var we := WorldEnvironment.new()
		we.environment = env
		_view.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50.0, 20.0, 0.0)
		sun.light_energy = 0.55
		_view.add_child(sun)
		return false
	if _kind == "":
		if _queue.is_empty():
			print("sprites ecrits dans res://tracks/impostors/")
			return true
		_kind = _queue.pop_front()
		var res := int(FarLod.KINDS[_kind].get("res", RES))
		_view.size = Vector2i(res, res)
		_build(_kind)
		_f = 2
		return false
	if _f == 8:
		var img := _view.get_texture().get_image()
		var path := String(FarLod.KINDS[_kind]["path"])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		img.save_png(ProjectSettings.globalize_path(path))
		print("ecrit ", path)
		_stage.queue_free()
		_kind = ""
	return false


func _build(kind: String) -> void:
	var spec: Dictionary = FarLod.KINDS[kind]
	var size: float = spec["size"]
	var ref: float = spec["ref"]
	_stage = Node3D.new()
	_view.add_child(_stage)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.position = Vector3(0.0, size / 2.0 - float(spec["bottom"]), 60.0)
	cam.current = true
	_stage.add_child(cam)
	match kind:
		"palm":
			# palmier de reference : tronc de `ref` m penche vers +x, couronne
			var b := Basis.IDENTITY.scaled(Vector3(ref, ref, ref))
			_stage.add_child(_one(PlayaBackdrop._trunk_mesh(), Transform3D(b, Vector3.ZERO), Color.WHITE))
			var cs := ref * 0.48
			_stage.add_child(_one(PlayaBackdrop._crown_mesh(), Transform3D(Basis.IDENTITY.scaled(Vector3(cs, cs, cs)),
				b * Vector3(0.14, 1.0, 0.0)), Color.WHITE))
		"palm_hd":
			var b := Basis.IDENTITY.scaled(Vector3(ref, ref, ref))
			_stage.add_child(_one(TreeKit.palm_trunk(), Transform3D(b, Vector3.ZERO), Color.WHITE))
			var cs := ref * 0.48
			_stage.add_child(_one(TreeKit.palm_crown(), Transform3D(Basis.IDENTITY.scaled(Vector3(cs, cs, cs)),
				b * Vector3(0.14, 1.0, 0.0)), Color.WHITE))
		"cherry_hd":
			var tree := TreeKit.cherry(SakuraBackdrop._wood(), TreeKit.blossom_material())
			_stage.add_child(_one(tree, Transform3D(Basis.IDENTITY.scaled(Vector3(ref, ref, ref)), Vector3.ZERO),
				Color(1.0, 0.97, 0.97)))
		"cherry":
			# cerisier de reference, couronne blanche (le jeu la teinte)
			var trunk := SakuraBackdrop._trunk_mesh()
			_stage.add_child(_one(trunk, Transform3D(Basis.IDENTITY.scaled(Vector3(ref * 0.1, ref, ref * 0.1)), Vector3.ZERO),
				Color.WHITE))
			var crown := SakuraBackdrop._crown_mesh()
			var mat := ShaderMaterial.new()
			mat.shader = preload("res://tracks/materials/sakura_blossom.gdshader")
			crown.surface_set_material(0, mat)
			var cs := ref * 1.1
			_stage.add_child(_one(crown, Transform3D(Basis.IDENTITY.scaled(Vector3(cs, cs * 0.75, cs)),
				Vector3(0.0, ref * 0.92, 0.0)), Color(1.0, 0.97, 0.97)))


## Un modele en MultiMesh d'une instance (la couleur d'instance des shaders).
func _one(mesh: Mesh, xf: Transform3D, color: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_color(0, color)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi
