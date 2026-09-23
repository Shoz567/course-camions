extends SceneTree

## Lanceur de la suite de tests headless.
##
## Decouvre toutes les scenes de res://tests/scenes/ et les execute chacune
## dans un PROCESS SEPARE. L'isolation n'est pas un luxe ici : un solveur qui
## diverge ou un crash physique ne doit pas emporter le reste de la suite, et
## le code de sortie de chaque scene doit rester lisible.
##
## Usage :
##   godot --headless --path game -s res://tests/cli_runner.gd
##   godot --headless --path game -s res://tests/cli_runner.gd -- --runs=5
##
## `--runs=N` implemente la regle des 5 runs de CLAUDE.md §10 : la physique
## n'est pas deterministe, donc un test sensible doit passer 5 fois sur 5.
## Un test qui echoue 1 fois sur 5 est un bug de tuning, pas un test instable.
##
## Code de sortie : 0 si tout passe, 1 sinon.

const SCENES_DIR := "res://tests/scenes"
const TIMEOUT_PER_RUN_MS := 120_000

var _runs: int = 1
var _failures: PackedStringArray = []
var _total_runs: int = 0


func _initialize() -> void:
	_parse_args()

	var scenes: PackedStringArray = _discover_scenes()

	print("")
	print("=== Ragdoll Brawler — suite de tests ===")
	print("scenes=%d runs=%d" % [scenes.size(), _runs])
	print("")

	if scenes.is_empty():
		# Phase 0 : aucune scene de test n'existe encore. Ce n'est pas un echec,
		# c'est l'etat attendu tant que la phase 1 n'a pas commence.
		print("Aucune scene de test dans %s/ (attendu en phase 0)." % SCENES_DIR)
		_report()
		return

	for scene in scenes:
		_run_scene(scene)

	_report()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			var value := arg.trim_prefix("--runs=")
			if value.is_valid_int():
				_runs = maxi(1, value.to_int())
			else:
				push_warning("--runs invalide, ignore: %s" % arg)


func _discover_scenes() -> PackedStringArray:
	var found: PackedStringArray = []
	var dir := DirAccess.open(SCENES_DIR)
	if dir == null:
		return found
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension() == "tscn":
			found.append("%s/%s" % [SCENES_DIR, name])
		name = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found


func _run_scene(scene_path: String) -> void:
	var exe := OS.get_executable_path()
	var project_dir := ProjectSettings.globalize_path("res://")

	for run_index in _runs:
		var args: PackedStringArray = [
			"--headless",
			"--path", project_dir,
			scene_path,
		]
		var output: Array = []
		var started_ms := Time.get_ticks_msec()
		var code := OS.execute(exe, args, output, true)
		var elapsed_ms := Time.get_ticks_msec() - started_ms
		_total_runs += 1

		var label := scene_path.get_file()
		if _runs > 1:
			label += " [run %d/%d]" % [run_index + 1, _runs]

		var raw := ""
		for chunk in output:
			raw += str(chunk)

		if code == 0:
			print("  PASS  %-46s %5d ms" % [label, elapsed_ms])
		else:
			print("  FAIL  %-46s %5d ms  (exit=%d)" % [label, elapsed_ms, code])
			_failures.append(label)

		# La sortie de la scene contient les mesures : on la conserve toujours.
		# Sur un jeu physique, un PASS sans son nombre ne vaut pas grand-chose.
		for line in raw.strip_edges().split("\n"):
			if line.strip_edges() != "":
				print("        | %s" % line.strip_edges())


func _report() -> void:
	print("")
	print("--- resultat : %d run(s), %d echec(s) ---" % [_total_runs, _failures.size()])
	for failure in _failures:
		print("    ECHEC  %s" % failure)
	print("")
	quit(1 if _failures.size() > 0 else 0)
