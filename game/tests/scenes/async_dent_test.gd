extends PhysicsTest

## Creux asynchrones (BodyDamage.async_dents, tache 7.6 : un choc dur figeait
## l'image 40 a 90 ms) :
##   A. le creux part sans attendre : au retour de dent, la carrosserie n'a
##      pas encore change, un creux est en vol ;
##   B. quelques images plus tard, la carrosserie est EXACTEMENT celle d'un
##      creux synchrone au meme endroit (jumeau) ;
##   C. deux creux sur la meme piece coup sur coup : enchaines, meme resultat
##      que les deux en synchrone ;
##   D. remise a neuf pendant le calcul : le creux est abandonne, la
##      carrosserie reste neuve.

var _sync: Truck
var _async: Truck
var _seen: Dictionary = {}
const AT := Vector3(1.3, 2.5, -2.0)
const AT2 := Vector3(1.3, 2.2, -1.2)


func _test_setup() -> void:
	duration_ticks = 120
	add_floor(2000.0)
	_sync = TruckTestUtil.spawn_truck(self, Vector3(0.0, 0.0, 0.0))
	_async = TruckTestUtil.spawn_truck(self, Vector3(200.0, 0.0, 0.0))


func _root(t: Truck) -> Node3D:
	return (t.get_node(^"Visual") as TruckVisual).mark_parent(false)


func _dent(t: Truck, at: Vector3) -> void:
	BodyDamage.dent(_root(t), t.global_transform * at, t.global_basis * Vector3(-0.4, 0.0, 0.0), 1.6)


## Empreinte de la carrosserie : somme ponderee des sommets (repere des pieces).
func _sig(t: Truck) -> float:
	var s := 0.0
	for n in _root(t).find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for k in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]:
				s += v.x + 2.0 * v.y + 3.0 * v.z
	return s


func _test_tick(t: int) -> void:
	match t:
		5:
			_seen["pristine"] = _sig(_async)
			BodyDamage.async_dents = false
			_dent(_sync, AT)
			_seen["sync_one"] = _sig(_sync)
			BodyDamage.async_dents = true
			_dent(_async, AT)
			_seen["right_after"] = _sig(_async)
			_seen["in_flight"] = BodyDamage.dents_in_flight()
		25:
			_seen["async_one"] = _sig(_async)
			_seen["flight_after"] = BodyDamage.dents_in_flight()
			# C : deux coups de suite
			BodyDamage.async_dents = false
			_dent(_sync, AT2)
			_dent(_sync, AT2)
			_seen["sync_two"] = _sig(_sync)
			BodyDamage.async_dents = true
			_dent(_async, AT2)
			_dent(_async, AT2)
		60:
			_seen["async_two"] = _sig(_async)
			# D : remise a neuf pendant le calcul
			BodyDamage.restore(_root(_async))
			_seen["restored"] = _sig(_async)
			_dent(_async, AT)
			BodyDamage.restore(_root(_async))
		90:
			_seen["after_cancel"] = _sig(_async)
			_seen["flight_end"] = BodyDamage.dents_in_flight()


func _test_finish() -> void:
	BodyDamage.async_dents = false
	var pristine := float(_seen.get("pristine", 0.0))
	check("le creux part sans attendre : rien de change au retour, un creux en vol",
		is_equal_approx(float(_seen.get("right_after", 1.0)), pristine) and int(_seen.get("in_flight", 0)) >= 1,
		"%d en vol" % int(_seen.get("in_flight", 0)))
	check("quelques images plus tard : meme carrosserie qu'en synchrone",
		absf(float(_seen.get("async_one", 0.0)) - float(_seen.get("sync_one", 1.0))) < 1e-3
		and not is_equal_approx(float(_seen.get("sync_one", 0.0)), pristine) and int(_seen.get("flight_after", 1)) == 0,
		"%.4f / %.4f" % [float(_seen.get("async_one", 0.0)), float(_seen.get("sync_one", 0.0))])
	check("deux creux coup sur coup : enchaines, meme resultat",
		absf(float(_seen.get("async_two", 0.0)) - float(_seen.get("sync_two", 1.0))) < 1e-3,
		"%.4f / %.4f" % [float(_seen.get("async_two", 0.0)), float(_seen.get("sync_two", 0.0))])
	check("remise a neuf pendant le calcul : creux abandonne, carrosserie neuve",
		is_equal_approx(float(_seen.get("restored", 0.0)), pristine)
		and is_equal_approx(float(_seen.get("after_cancel", 0.0)), pristine) and int(_seen.get("flight_end", 1)) == 0)
