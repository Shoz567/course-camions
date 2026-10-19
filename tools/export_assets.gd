extends SceneTree

## Copie a cote d'un jeu exporte les modeles de l'equipe qu'il charge a
## l'execution (TruckVisual.asset_base) : res:// n'existe pas sur le disque
## d'un jeu exporte, et les .glb (Git LFS) sont hors du projet Godot.
##
##     godot --headless -s tools/export_assets.gd -- builds/windows
##
## Lance depuis la racine du depot. Sort en code 1 si un dossier manque ou si
## un fichier n'est qu'un pointeur Git LFS (clone sans `git lfs pull`).

const DIRS: PackedStringArray = [
	"Assets_Visuels/Camion/Camions_Course_Export/Realiste",
	"Assets_Visuels/Armes_et_camions/vehicules/Realiste",
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("export_assets : dossier de destination manquant")
		quit(1)
		return
	# sans --path, res:// est le dossier courant : la racine du depot
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var dest := root.path_join(args[0])
	var copied := 0
	var bytes := 0
	for d in DIRS:
		var src := root.path_join(d)
		var dir := DirAccess.open(src)
		if dir == null:
			printerr("export_assets : %s introuvable" % src)
			quit(1)
			return
		DirAccess.make_dir_recursive_absolute(dest.path_join(d))
		for f in dir.get_files():
			if not f.ends_with(".glb"):
				continue
			var from := src.path_join(f)
			var size := FileAccess.get_file_as_bytes(from).size()
			if size < 1024:
				printerr("export_assets : %s fait %d octets, pointeur Git LFS ? (git lfs pull)" % [from, size])
				quit(1)
				return
			var err := DirAccess.copy_absolute(from, dest.path_join(d).path_join(f))
			if err != OK:
				printerr("export_assets : copie de %s impossible (%d)" % [from, err])
				quit(1)
				return
			copied += 1
			bytes += size
	print("OK %d modele(s), %.1f Mo -> %s" % [copied, bytes / 1048576.0, dest])
	quit(0)
