extends PhysicsTest

## Destruction etalee (tache 7.6) : les quatre bosses de la cabine detruite
## (BodyDamage.dent, ~38 ms chacune) ne tombent plus dans la meme image - elles
## figeaient l'image ~190 ms a 4 joueurs. Juste apres la destruction : 4 en
## attente, aucune encore appliquee ; une par image ensuite ; toutes posees
## en 4 images, sur les 4 faces ; un reset (clear_all) vide la file.

var _scene: Node3D
var _fx: TruckDamageFx
var _truck: Truck
var _seen: Dictionary = {}
var _frame: int = -1


func _test_setup() -> void:
	duration_ticks = 60
	_scene = (load("res://dev/race.tscn") as PackedScene).instantiate() as Node3D
	_scene.set("ready_gate", false)
	add_child(_scene)


func _hits() -> int:
	var root := (_truck.get_node(^"Visual") as TruckVisual).mark_parent(false)
	var total := 0
	for side: Vector3 in [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3.UP]:
		total += BodyDamage.hits_near(root, _truck.global_transform * (TruckSpec.CAB_CENTER + side * TruckSpec.CAB_SIZE / 2.0))
	return total


func _process(_delta: float) -> void:
	if _frame < 0 or _fx == null:
		return
	_frame += 1
	_seen["pending_%d" % _frame] = _fx._pending_dents.size()


func _test_tick(t: int) -> void:
	if t == 10:
		_truck = ((_scene.get("players") as Array)[0] as Object).get("truck") as Truck
		for c in _truck.get_children():
			if c is TruckDamageFx:
				_fx = c
		_fx._on_destroyed()
		_seen["queued"] = _fx._pending_dents.size()
		_seen["hits_before"] = _hits()
		_frame = 0
	if t == 30:
		_seen["hits_after"] = _hits()
		_seen["left"] = _fx._pending_dents.size()
		_fx._on_destroyed()
		_fx.clear_all()
		_seen["cleared"] = _fx._pending_dents.size()


func _test_finish() -> void:
	check("destruction : 4 bosses en attente, aucune appliquee dans l'image",
		int(_seen.get("queued", 0)) == 4 and int(_seen.get("hits_before", -1)) == 0,
		"%s en attente, %s coups" % [_seen.get("queued"), _seen.get("hits_before")])
	var per := []
	for k in range(1, 7):
		per.append(int(_seen.get("pending_%d" % k, -1)))
	# ordre de traitement dans l'image : la file est lue avant ou apres sa
	# bosse du jour, selon la place du test dans l'arbre
	var one_each := true
	for k in range(1, per.size()):
		var expected := maxi(int(per[k - 1]) - 1, 0)
		one_each = one_each and int(per[k]) == expected
	check("une bosse par image jusqu'a la derniere", one_each and per[per.size() - 1] == 0 and per[0] >= 3, str(per))
	check("toutes posees sur la cabine", int(_seen.get("left", -1)) == 0 and int(_seen.get("hits_after", 0)) >= 4,
		"%s coups" % _seen.get("hits_after"))
	check("reset : la file est videe", int(_seen.get("cleared", -1)) == 0)
