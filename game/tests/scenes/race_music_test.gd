extends PhysicsTest

## Musique de course (2026-10-22 : « une par map [...] la musique change
## uniquement au dernier tour [...] sur la version avec un plus gros BPM » ;
## morceaux CC0 de MintoDog, audio/music/CREDITS.md) :
##   A. chaque habillage a sa musique et sa version du dernier tour : deux
##      fichiers differents, lus en boucle, de plus de 30 s ;
##   B. RaceMusic.final_due : course, version rapide au dernier tour
##      seulement (un tour : des le depart) ; arene et elimination, a la
##      derniere minute ou a 2 camions restants (pas si la manche commence a
##      deux) ;
##   C. une course (dev/race.tscn) en un tour, en headless : la musique du
##      circuit (Cyber City), lancee au GO, passe aussitot au dernier tour ;
##      aucun lecteur audio en headless.

var _race: Node3D
var _saved_players: int = 0


func _test_setup() -> void:
	duration_ticks = 400
	_saved_players = GameState.requested_players
	GameState.requested_players = 1
	_race = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_race.set("ready_gate", false)   # le sas READY a son propre test (race_ready_test)
	(_race.get_node(^"RaceLaps") as RaceLaps).total_laps = 1
	_race.position = Vector3(0.0, -500.0, 0.0)
	add_child(_race)


func _test_tick(t: int) -> void:
	var m := _race.get("music") as RaceMusic
	if m != null and m.final:
		duration_ticks = mini(duration_ticks, t + 1)


func _test_finish() -> void:
	var bad := []
	for id: int in [TrackTheme.Id.CYBER_CITY, TrackTheme.Id.PLAYA_DEL_SOL, TrackTheme.Id.SAKURA]:
		var normal := RaceMusic.stream_for(id, false)
		var last := RaceMusic.stream_for(id, true)
		for s: AudioStream in [normal, last]:
			if s == null or not bool(s.get("loop")) or s.get_length() < 30.0:
				bad.append([id, s.resource_path if s != null else "absent"])
		if normal != null and last != null and normal.resource_path == last.resource_path:
			bad.append([id, "meme fichier"])
	check("A 3 habillages : musique et version du dernier tour, en boucle, > 30 s", bad.is_empty(), str(bad))

	var race := GameStateNode.GameMode.RACE
	var arena := GameStateNode.GameMode.ARENA
	var elim := GameStateNode.GameMode.ELIMINATION
	var laps := [RaceMusic.final_due(race, 1, 3, 6, 6, -1), RaceMusic.final_due(race, 2, 3, 6, 6, -1),
		RaceMusic.final_due(race, 3, 3, 6, 6, -1), RaceMusic.final_due(race, 1, 1, 6, 6, -1)]
	check("B course : version rapide au dernier tour seulement (3 tours ; 1 tour : des le depart)",
		laps == [false, false, true, true], str(laps))
	var ends := [RaceMusic.final_due(arena, 1, 999, 6, 6, 200), RaceMusic.final_due(arena, 1, 999, 2, 6, 200),
		RaceMusic.final_due(arena, 1, 999, 2, 2, 200), RaceMusic.final_due(arena, 1, 999, 5, 6, 60),
		RaceMusic.final_due(arena, 1, 999, 3, 6, -1), RaceMusic.final_due(elim, 1, 99, 2, 6, -1),
		RaceMusic.final_due(elim, 4, 99, 4, 6, -1)]
	check("B arene et elimination : derniere minute ou 2 camions restants (pas une manche a deux)",
		ends == [false, true, false, true, false, true, false], str(ends))

	var m := _race.get("music") as RaceMusic
	check("C course en un tour : musique de Cyber City, lancee au GO, version du dernier tour",
		m != null and m.theme_id == TrackTheme.Id.CYBER_CITY and m.playing and m.final,
		str([m.theme_id, m.playing, m.final]) if m != null else "pas de musique")
	check("C headless : aucun lecteur audio", m != null and m.get_child_count() == 0 and not m.is_playing())
	GameState.requested_players = _saved_players
