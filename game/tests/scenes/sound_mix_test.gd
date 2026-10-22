extends PhysicsTest

## Mixage (2026-10-21 : « un grésillement, tous les bruitages plutôt forts,
## la pluie vachement forte au début ») :
##   A. trois bus sous le Master (Effets, Ambiance, Musique) ; bruitages et
##      ambiance plus bas que la musique ; bruitages 12 dB sous elle
##      (2026-10-22 : « les bruitages sont trop forts par rapport a la
##      musique » ; 6 avant) ;
##   B. un limiteur sur le Master, plafond sous 0 dB (plus d'ecretage) ;
##   C. setup() rejoue sans doubler bus ni limiteur ;
##   D. chaque son part sur son bus : foule et ambiance sur Ambiance, klaxon
##      et boost sur Effets ;
##   F. jauges Musique et Bruitages (2026-10-22) : par-dessus le niveau du
##      bus ; la jauge des bruitages regle aussi l'ambiance ; 0 % : muet ;
##   E. la pluie de Cyber City sous les autres ambiances, et plus douce :
##      part de l'energie dans les aigus (derivee / signal) sous la moitie de
##      l'ancienne pluie (mesuree avant le changement : 0,65 ; apres : 0,10).

var _seen: Dictionary = {}


func _test_setup() -> void:
	duration_ticks = 2
	var crowd := CrowdSound.new()
	add_child(crowd)
	var horn := TruckHorn.new()
	add_child(horn)
	var boost := TruckBoostSound.new()
	add_child(boost)
	_seen["buses"] = [crowd.bus, horn.bus, boost.bus]


func _test_finish() -> void:
	var levels := []
	var sends := []
	for b: StringName in [SoundMix.EFFECTS, SoundMix.AMBIENCE, SoundMix.MUSIC]:
		var idx := AudioServer.get_bus_index(b)
		levels.append(AudioServer.get_bus_volume_db(idx) if idx >= 0 else 99.0)
		sends.append(AudioServer.get_bus_send(idx) if idx >= 0 else &"")
	check("A trois bus vers le Master", sends == [&"Master", &"Master", &"Master"], str(sends))
	check("A bruitages et ambiance sous la musique, bruitages 12 dB sous elle (dB)", float(levels[0]) < float(levels[2])
		and float(levels[1]) < float(levels[2]) and float(levels[2]) - float(levels[0]) >= 12.0, str(levels))
	var lim := SoundMix.limiter()
	check("B limiteur sur le Master, plafond < 0 dB", lim != null and lim.ceiling_db < 0.0,
		str(lim.ceiling_db if lim != null else null))
	var count := AudioServer.bus_count
	SoundMix.setup()
	var master := AudioServer.get_bus_index(&"Master")
	check("C setup() idempotent", AudioServer.bus_count == count and AudioServer.get_bus_effect_count(master) == 1,
		"%d bus, %d effet(s)" % [AudioServer.bus_count, AudioServer.get_bus_effect_count(master)])
	check("D foule : Ambiance ; klaxon, boost : Effets",
		_seen.get("buses") == [SoundMix.AMBIENCE, SoundMix.EFFECTS, SoundMix.EFFECTS], str(_seen.get("buses")))
	check("E pluie sous les autres ambiances (dB)",
		AmbienceSound.volume_db_for(TrackTheme.Id.CYBER_CITY) < AmbienceSound.volume_db_for(TrackTheme.Id.PLAYA_DEL_SOL),
		"%.1f / %.1f" % [AmbienceSound.volume_db_for(TrackTheme.Id.CYBER_CITY),
			AmbienceSound.volume_db_for(TrackTheme.Id.PLAYA_DEL_SOL)])
	var rain := AmbienceSound.build(TrackTheme.Id.CYBER_CITY)
	var hf := 0.0
	var total := 0.0
	for i in range(1, rain.size()):
		hf += (rain[i] - rain[i - 1]) * (rain[i] - rain[i - 1])
		total += rain[i] * rain[i]
	check_below("E pluie plus douce (energie aigue / totale)", hf / total, 0.65 / 2.0)
	var buses := [AudioServer.get_bus_index(SoundMix.MUSIC), AudioServer.get_bus_index(SoundMix.EFFECTS),
		AudioServer.get_bus_index(SoundMix.AMBIENCE)]
	SoundMix.apply_user_volumes(50.0, 25.0)
	var half := []
	for idx: int in buses:
		half.append(snappedf(AudioServer.get_bus_volume_db(idx), 0.01))
	SoundMix.apply_user_volumes(100.0, 0.0)
	var silent := [AudioServer.is_bus_mute(buses[0]), AudioServer.is_bus_mute(buses[1]), AudioServer.is_bus_mute(buses[2])]
	SoundMix.apply_user_volumes(GameState.music_volume, GameState.effects_volume)
	var want := [snappedf(3.0 + linear_to_db(0.5), 0.01), snappedf(-12.0 + linear_to_db(0.25), 0.01),
		snappedf(-6.0 + linear_to_db(0.25), 0.01)]
	check("F jauges : musique 50 %, bruitages 25 % (ambiance comprise), par-dessus le bus", half == want,
		"%s / %s" % [half, want])
	check("F bruitages a 0 % : Effets et Ambiance muets, musique non", silent == [false, true, true], str(silent))
