extends SceneTree

## Lanceur de la suite de tests headless.
##
## Decouvre les scenes .tscn d'un dossier et les execute chacune dans un
## PROCESS SEPARE. L'isolation n'est pas un luxe ici : un solveur qui diverge ou
## un crash physique ne doit pas emporter le reste de la suite, et le code de
## sortie de chaque scene doit rester lisible.
##
## Usage :
##   godot --headless --path game -s res://tests/cli_runner.gd
##   godot --headless --path game -s res://tests/cli_runner.gd -- --runs=5
##
## Options (apres `--`) :
##   --runs=N            chaque scene N fois (regle des 5 runs, CLAUDE.md §10)
##   --dir=res://...     dossier des scenes (defaut : res://tests/scenes)
##   --max-iterations=N  garde anti-blocage par scene (defaut : 7200 iterations)
##   --selftest          mode auto-test du socle : le verdict attendu est lu dans
##                       le nom de la scene (expect_pass_*, expect_fail_*,
##                       expect_skip_*), et c'est l'ECART qui fait echouer
##
## Verdict d'une scene (cf. tests/physics_test.gd) :
##   PASS  code 0  ET ligne "RESULT PASS"
##   SKIP  code 77 ET ligne "RESULT SKIP"   -> ne fait pas echouer la suite
##   FAIL  tout le reste, y compris un code 0 SANS ligne RESULT : c'est le cas
##         d'un script en erreur ou d'une scene bloquee, que Godot termine
##         pourtant en code 0 via --quit-after. Sans cette regle, un test casse
##         serait compte comme reussi.
##         Egalement FAIL : toute sortie contenant "SCRIPT ERROR", meme si la
##         scene a conclu PASS avec les verifications posees avant l'erreur.
##
## Vitesse : chaque scene tourne avec `--fixed-fps 60`, donc sans attendre le
## temps reel (en headless, Godot regulerait sinon a 16,67 ms par tick : 600
## ticks = 10 s). Le pas physique reste 1/60 s : la simulation est la meme.
## Sans exception, y compris les scenes `perf_*` : sous --fixed-fps, les
## iterations s'enchainent sans attente, donc le temps mural divise par le
## nombre de ticks EST le cout d'un tick. C'est la seule mesure fiable :
## Performance.TIME_PHYSICS_PROCESS n'est rafraichi qu'environ une fois par
## seconde reelle (docs/SPIKE.md, acquis A2).
##
## Code de sortie : 0 si aucun FAIL, 1 sinon.

const DEFAULT_DIR := "res://tests/scenes"
## 12 000 images (200 s) : un tour complet des circuits rallonges (2026-10-20,
## 4,4 a 4,6 km) tient, pilote automatique prudent compris.
const DEFAULT_MAX_ITERATIONS := 12000

var _dir: String = DEFAULT_DIR
var _runs: int = 1
var _max_iterations: int = DEFAULT_MAX_ITERATIONS
var _selftest: bool = false

var _total_runs: int = 0
var _pass_count: int = 0
var _failures: PackedStringArray = []
var _skips: PackedStringArray = []


func _initialize() -> void:
	_parse_args()

	var scenes: PackedStringArray = _discover_scenes()

	print("")
	print("=== Course de camions — %s ===" % ("auto-test du socle" if _selftest else "suite de tests"))
	print("dossier=%s scenes=%d runs=%d max-iterations=%d"
		% [_dir, scenes.size(), _runs, _max_iterations])
	print("")

	if scenes.is_empty():
		print("Aucune scene de test dans %s/." % _dir)
		_report()
		return

	for scene in scenes:
		_run_scene(scene)

	_report()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			_runs = maxi(1, _int_arg(arg, "--runs=", _runs))
		elif arg.begins_with("--max-iterations="):
			_max_iterations = maxi(1, _int_arg(arg, "--max-iterations=", _max_iterations))
		elif arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=").trim_suffix("/")
		elif arg == "--selftest":
			_selftest = true
		else:
			push_warning("option inconnue, ignoree : %s" % arg)


func _int_arg(arg: String, prefix: String, fallback: int) -> int:
	var value := arg.trim_prefix(prefix)
	if value.is_valid_int():
		return value.to_int()
	push_warning("valeur invalide, ignoree : %s" % arg)
	return fallback


func _discover_scenes() -> PackedStringArray:
	var found: PackedStringArray = []
	var dir := DirAccess.open(_dir)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.get_extension() == "tscn":
			found.append("%s/%s" % [_dir, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found


func _run_scene(scene_path: String) -> void:
	var exe := OS.get_executable_path()
	var project_dir := ProjectSettings.globalize_path("res://")
	var expected := _expected_verdict(scene_path)

	for run_index in _runs:
		var args: PackedStringArray = [
			"--headless",
			"--path", project_dir,
			"--quit-after", str(_max_iterations),
		]
		args.append_array(["--fixed-fps", "60"])
		args.append(scene_path)
		var output: Array = []
		var started_ms := Time.get_ticks_msec()
		var code := OS.execute(exe, args, output, true)
		var elapsed_ms := Time.get_ticks_msec() - started_ms
		_total_runs += 1

		var raw := ""
		for chunk in output:
			raw += str(chunk)

		var label := scene_path.get_file()
		if _runs > 1:
			label += " [run %d/%d]" % [run_index + 1, _runs]

		var result := _verdict(code, raw)
		var verdict: String = result[0]
		var reason: String = result[1]

		if _selftest:
			_record_selftest(label, verdict, expected, elapsed_ms, reason)
		else:
			_record(label, verdict, elapsed_ms, reason)

		# La sortie de la scene contient les mesures : on la montre toujours.
		for line in raw.strip_edges().split("\n"):
			if line.strip_edges() != "":
				print("        | %s" % line.strip_edges())

		# Un SKIP ne depend pas du hasard physique : inutile de le rejouer.
		if verdict == "SKIP":
			break


## Retourne [verdict, raison].
func _verdict(code: int, raw: String) -> Array:
	var claimed := ""
	for line in raw.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("RESULT "):
			claimed = l.get_slice(" ", 1)

	if claimed == "":
		return ["FAIL", "aucune ligne RESULT (script en erreur, ou scene bloquee jusqu'a --quit-after)"]
	# Une erreur d'execution GDScript interrompt la fonction fautive, mais pas la
	# scene : le test peut encore conclure PASS avec les verifications posees
	# AVANT l'erreur. On ne laisse jamais passer ce cas.
	if raw.contains("SCRIPT ERROR"):
		return ["FAIL", "erreur de script pendant le test (voir la sortie)"]
	if claimed == "PASS" and code == PhysicsTest.EXIT_PASS:
		return ["PASS", ""]
	if claimed == "SKIP" and code == PhysicsTest.EXIT_SKIP:
		return ["SKIP", _result_detail(raw)]
	if claimed == "FAIL":
		return ["FAIL", _result_detail(raw)]
	return ["FAIL", "verdict %s mais code de sortie %d : incoherent" % [claimed, code]]


func _result_detail(raw: String) -> String:
	for line in raw.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("RESULT "):
			return l.substr(7).strip_edges().substr(4).strip_edges()
	return ""


func _expected_verdict(scene_path: String) -> String:
	var n := scene_path.get_file()
	if n.begins_with("expect_pass_"):
		return "PASS"
	if n.begins_with("expect_fail_"):
		return "FAIL"
	if n.begins_with("expect_skip_"):
		return "SKIP"
	return ""


func _record(label: String, verdict: String, elapsed_ms: int, reason: String) -> void:
	match verdict:
		"PASS":
			_pass_count += 1
			print("  PASS  %-46s %5d ms" % [label, elapsed_ms])
		"SKIP":
			_skips.append("%s — %s" % [label, reason])
			print("  SKIP  %-46s %5d ms" % [label, elapsed_ms])
		_:
			_failures.append("%s — %s" % [label, reason])
			print("  FAIL  %-46s %5d ms" % [label, elapsed_ms])


func _record_selftest(label: String, verdict: String, expected: String,
		elapsed_ms: int, reason: String) -> void:
	if expected == "":
		_failures.append("%s — nom sans prefixe expect_pass_/expect_fail_/expect_skip_" % label)
		print("  ????  %-46s" % label)
		return
	if verdict == expected:
		_pass_count += 1
		print("  OK    %-46s %5d ms  (%s, attendu %s)" % [label, elapsed_ms, verdict, expected])
	else:
		_failures.append("%s — obtenu %s, attendu %s. %s" % [label, verdict, expected, reason])
		print("  ECART %-46s %5d ms  (%s, attendu %s)" % [label, elapsed_ms, verdict, expected])


func _report() -> void:
	print("")
	print("--- resultat : %d run(s) : %d ok, %d echec(s), %d saute(s) ---"
		% [_total_runs, _pass_count, _failures.size(), _skips.size()])
	for failure in _failures:
		print("    ECHEC  %s" % failure)
	for s in _skips:
		print("    SAUTE  %s" % s)
	print("")
	quit(1 if _failures.size() > 0 else 0)
