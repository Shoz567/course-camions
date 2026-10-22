extends Node

## Scene de depart de net_e2e : le pilote vit sous la racine (il survit au
## changement de scene).
func _ready() -> void:
	get_tree().root.add_child.call_deferred(load("res://dev/net_e2e.gd").new())
