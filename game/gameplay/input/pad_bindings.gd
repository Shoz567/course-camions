class_name PadBindings
extends RefCounted

## Reaffectation des boutons de la manette (tache 7.1, ecran des parametres) :
## pour chaque action numerique, les boutons qui la declenchent. Un profil
## pour toutes les manettes, garde dans GameState.pad_bindings et sauvegarde
## avec les autres options. Les gachettes (accelerer R2, freiner L2) et le
## stick gauche ne se reaffectent pas.
##
## Un bouton ne sert qu'a une action : le donner a une action le retire des
## autres, et une action qui n'aurait plus aucun bouton recoit en echange les
## anciens boutons de la premiere (aucune action ne devient injouable).

## Actions dans l'ordre de l'ecran, et leur nom affiche.
const ACTIONS: PackedStringArray = ["handbrake", "boost", "cargo", "honk", "camera", "look_back", "reset",
	"power_left", "power_right", "target"]
const LABELS: Dictionary = {
	"handbrake": "Frein à main / dérapage (drift)",
	"boost": "Nitro boost",
	"cargo": "Largage de remorque",
	"honk": "Klaxon",
	"camera": "Changer de vue",
	"look_back": "Regarder derrière",
	"reset": "Reset sur la piste",
	"power_left": "Pouvoir de gauche",
	"power_right": "Pouvoir de droite",
	"target": "Changer de cible",
}

## Boutons qu'on ne peut pas donner : le bouton PS ouvre le systeme, Options
## le menu pause de la course (2026-10-22 ; il faisait aussi reset avant).
const RESERVED: Array[JoyButton] = [JOY_BUTTON_GUIDE, JOY_BUTTON_START]


## Profil par defaut (disposition Forza Horizon, DeviceInputSource).
static func defaults() -> Dictionary:
	return {
		"handbrake": PackedInt32Array([JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER]),
		"boost": PackedInt32Array([JOY_BUTTON_X]),
		"cargo": PackedInt32Array([JOY_BUTTON_Y]),
		"honk": PackedInt32Array([JOY_BUTTON_LEFT_STICK]),
		"camera": PackedInt32Array([JOY_BUTTON_RIGHT_STICK]),
		"look_back": PackedInt32Array([JOY_BUTTON_LEFT_SHOULDER]),
		"reset": PackedInt32Array([JOY_BUTTON_BACK, JOY_BUTTON_TOUCHPAD]),
		"power_left": PackedInt32Array([JOY_BUTTON_DPAD_LEFT]),
		"power_right": PackedInt32Array([JOY_BUTTON_DPAD_RIGHT]),
		"target": PackedInt32Array([JOY_BUTTON_DPAD_UP]),
	}


## `button` declenche desormais `action`, et elle seule (voir l'en-tete).
## Renvoie un nouveau profil ; `bindings` n'est pas modifie.
static func assign(bindings: Dictionary, action: String, button: int) -> Dictionary:
	var out := sanitized(bindings)
	if not ACTIONS.has(action) or RESERVED.has(button as JoyButton) or button < 0:
		return out
	var old: PackedInt32Array = out[action]
	for a: String in ACTIONS:
		if a == action:
			continue
		var list: PackedInt32Array = out[a]
		var k := list.find(button)
		if k < 0:
			continue
		list.remove_at(k)
		if list.is_empty():
			for b in old:
				if b != button:
					list.append(b)
		out[a] = list
	out[action] = PackedInt32Array([button])
	return out


## Profil complet et valide : une action absente ou vide reprend son defaut
## (fichier d'options ancien ou abime).
static func sanitized(bindings: Dictionary) -> Dictionary:
	var d := defaults()
	var out := {}
	var fallback := PackedStringArray()
	for a: String in ACTIONS:
		var list := PackedInt32Array()
		var src: Variant = bindings.get(a, null)
		if src is PackedInt32Array or src is Array:
			for b: Variant in src:
				var v := int(b)
				if v >= 0 and v < JOY_BUTTON_MAX and not list.has(v) and not RESERVED.has(v as JoyButton):
					list.append(v)
		out[a] = list if not list.is_empty() else d[a]
		if list.is_empty():
			fallback.append(a)
	# action reprise par defaut (absente d'un profil d'avant son ajout, comme
	# look_back sur L1 le 2026-10-20) : ses boutons sont retires aux autres,
	# et une action laissee sans bouton reprend les siens (le klaxon : L3)
	for a: String in fallback:
		var taken: PackedInt32Array = d[a]
		for other: String in ACTIONS:
			if other == a:
				continue
			var list: PackedInt32Array = out[other]
			for b in taken:
				var k := list.find(b)
				if k >= 0:
					list.remove_at(k)
			if list.is_empty():
				for b in d[other]:
					if not taken.has(b):
						list.append(b)
			out[other] = list
	return out


## Pose le profil sur une manette (avant son entree dans l'arbre ou apres).
static func apply(source: DeviceInputSource, bindings: Dictionary) -> void:
	var b := sanitized(bindings)
	source.buttons_handbrake = _typed(b["handbrake"])
	source.buttons_boost = _typed(b["boost"])
	source.buttons_cargo = _typed(b["cargo"])
	source.buttons_honk = _typed(b["honk"])
	source.buttons_camera = _typed(b["camera"])
	source.buttons_look_back = _typed(b["look_back"])
	source.buttons_reset = _typed(b["reset"])
	source.buttons_power_left = _typed(b["power_left"])
	source.buttons_power_right = _typed(b["power_right"])
	source.buttons_target = _typed(b["target"])


static func _typed(list: PackedInt32Array) -> Array[JoyButton]:
	var out: Array[JoyButton] = []
	for v in list:
		out.append(v as JoyButton)
	return out


## Nom d'un bouton, etiquettes PlayStation (Godot nomme par position).
static func button_name(button: int) -> String:
	match button:
		JOY_BUTTON_A: return "Croix"
		JOY_BUTTON_B: return "Rond"
		JOY_BUTTON_X: return "Carré"
		JOY_BUTTON_Y: return "Triangle"
		JOY_BUTTON_BACK: return "Create"
		JOY_BUTTON_GUIDE: return "PS"
		JOY_BUTTON_START: return "Options"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_LEFT_SHOULDER: return "L1"
		JOY_BUTTON_RIGHT_SHOULDER: return "R1"
		JOY_BUTTON_DPAD_UP: return "Haut"
		JOY_BUTTON_DPAD_DOWN: return "Bas"
		JOY_BUTTON_DPAD_LEFT: return "Gauche"
		JOY_BUTTON_DPAD_RIGHT: return "Droite"
		JOY_BUTTON_MISC1: return "Micro"
		JOY_BUTTON_TOUCHPAD: return "Pavé tactile"
	return "Bouton %d" % button


## « Croix, R1 ».
static func list_name(list: PackedInt32Array) -> String:
	var names := PackedStringArray()
	for b in list:
		names.append(button_name(b))
	return ", ".join(names)
