extends PhysicsTest

## Musique de course procedurale (RaceMusic, demande du 2026-09-30) :
##   - la partition tient debout : 16 mesures, chaque mesure du theme fait
##     exactement 16 doubles croches ;
##   - le rendu (fait ici a 8 kHz pour aller vite) a la duree exacte de la
##     boucle (16 mesures a 150 BPM = 25,6 s), n'est pas muet, ne sature pas
##     (crete <= 0,9), se raccorde sans clic (saut au bouclage pas plus grand
##     que les sauts ordinaires) et est deterministe ;
##   - en headless, rien ne se lance : ni rendu de fond, ni lecteur audio, ni
##     musique au GO de la course (dev/race.tscn).

const TEST_RATE := 8000

var _pcm: PackedByteArray
var _pcm_again: PackedByteArray
var _render_ms: float = 0.0
var _music: RaceMusic
var _race: Node3D


func _test_setup() -> void:
	duration_ticks = 240
	var t0 := Time.get_ticks_usec()
	_pcm = RaceMusic.render(TEST_RATE, RaceMusic.BARS)
	_render_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_pcm_again = RaceMusic.render(TEST_RATE, 2)
	_music = RaceMusic.new()
	add_child(_music)
	_music.play()
	RaceMusic.prepare()
	GameState.requested_players = 1
	_race = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_race.position = Vector3(0.0, -500.0, 0.0)
	add_child(_race)


func _test_tick(_t: int) -> void:
	pass


func _test_finish() -> void:
	check("16 mesures d'accords", RaceMusic.PROGRESSION.size() == RaceMusic.BARS,
		"%d" % RaceMusic.PROGRESSION.size())
	var bad_bars: Array[int] = []
	for b in RaceMusic.LEAD.size():
		var total := 0
		for nd: Array in RaceMusic.LEAD[b]:
			total += int(nd[1])
		if total != RaceMusic.STEPS_PER_BAR:
			bad_bars.append(b)
	check("theme : 16 doubles croches par mesure", bad_bars.is_empty(), "%s" % [bad_bars])

	var frames := _pcm.size() / 4
	var expected := roundi(RaceMusic.BARS * 4 * 60.0 / RaceMusic.BPM * TEST_RATE)
	check("duree exacte de la boucle (echantillons)", frames == expected,
		"%d / %d (%.1f s)" % [frames, expected, frames / float(TEST_RATE)])
	var peak := 0.0
	var sum2 := 0.0
	var max_jump := 0.0
	var prev := 0.0
	for i in frames:
		var v := _pcm.decode_s16(i * 4) / 32768.0
		peak = maxf(peak, absf(v))
		sum2 += v * v
		if i > 0:
			max_jump = maxf(max_jump, absf(v - prev))
		prev = v
	var rms := sqrt(sum2 / maxi(frames, 1))
	var seam := absf(_pcm.decode_s16(0) / 32768.0 - _pcm.decode_s16((frames - 1) * 4) / 32768.0)
	print("  INFO   rendu %.0f ms a %d Hz ; crete %.2f, efficace %.3f, saut au bouclage %.3f (max ordinaire %.3f)"
		% [_render_ms, TEST_RATE, peak, rms, seam, max_jump])
	check_above("pas muette : valeur efficace", rms, 0.05)
	check_below("ne sature pas : crete", peak, 0.91)
	check("bouclage sans clic : saut <= sauts ordinaires", seam <= max_jump,
		"%.3f / %.3f" % [seam, max_jump])
	var again := RaceMusic.render(TEST_RATE, 2)
	check("deterministe : deux rendus identiques",
		_pcm_again.size() == 2 * RaceMusic.STEPS_PER_BAR * TEST_RATE / 10 * 4 and again == _pcm_again)

	check("headless : aucun lecteur audio", _music.get_child_count() == 0 and not _music.is_playing())
	var race_music := _race.get("music") as RaceMusic
	check("headless : la course cree sa musique, muette apres le GO",
		race_music != null and _race.get("state") != 0 and not race_music.is_playing()
		and race_music.get_child_count() == 0,
		"state=%s" % _race.get("state"))
	check("headless : aucun rendu de fond lance", RaceMusic._task_id == -1 and RaceMusic._stream == null)
