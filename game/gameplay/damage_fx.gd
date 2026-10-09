class_name DamageFx
extends RefCounted

## Briques visuelles des degats (purement visuelles, aucune physique) :
##   - traces de choc : cicatrices peintes dans la carrosserie (BodyScars,
##     truck_body.gdshader) au point d'impact - eraflures et vernis terni
##     pour un frottement, peinture arrachee, tole nue rayee et pliee pour un
##     choc plus fort, suie au centre d'un choc violent. Chaque trace garde
##     un repere (DamageMark, Node3D sans rendu) : position, axe sortant et
##     gravite ; elles remplacent les decalques d'eraflures (2026-10-07 :
##     « des traits blancs, pas tres realiste ») ;
##   - fumee (particules GPU, monde, FxKit) : grise legere ou noire epaisse ;
##   - etincelles (FxKit) qui crepitent et rebondissent sur la route.
## Textures generees une fois, en memoire (aucun fichier, CLAUDE.md §8).

## Calque de rendu des carrosseries (camions, remorques larguees, debris).
const RENDER_LAYER := 11
const LAYER_BIT := 1 << (RENDER_LAYER - 1)
## Rayon d'une cicatrice (m) : eraflure legere .. choc violent.
const SCAR_RADIUS := Vector2(0.55, 1.5)

enum Smoke { NONE, LIGHT, HEAVY, WRECK }



## Repere d'une trace de choc de gravite `severity` (0 .. 1).
static func make_mark(severity: float) -> Node3D:
	var d := Node3D.new()
	d.name = "DamageMark"
	d.set_meta(&"severity", clampf(severity, 0.0, 1.0))
	return d


## Pose le repere au point local `at` : son axe +Y suit la normale sortante
## `outward` (vers l'exterieur du camion), son axe X (le sens du frottement)
## reste horizontal.
static func place_mark(d: Node3D, at: Vector3, outward: Vector3) -> void:
	var y := outward.normalized()
	var x := Vector3.UP.cross(y)
	if x.length_squared() < 1e-3:
		x = Vector3.RIGHT.cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	d.transform = Transform3D(Basis(x, y, z), at)


## Trace de choc complete : repere `d` pose sous `parent` au point monde
## `point`, et cicatrice peinte sur les carrosseries de `parent` autour.
static func scar(parent: Node3D, point: Vector3, outward: Vector3, severity: float) -> Node3D:
	var d := make_mark(severity)
	var inv := parent.global_transform.affine_inverse()
	place_mark(d, inv * point, inv.basis * outward)
	parent.add_child(d)
	var s := clampf(severity, 0.0, 1.0)
	BodyScars.add(parent, point, lerpf(SCAR_RADIUS.x, SCAR_RADIUS.y, s), lerpf(0.3, 1.0, s))
	return d


## Panache de fumee (eteint) : bouffees en coordonnees monde qui montent,
## grossissent, tournent et s'effacent (FxKit.make_smoke).
static func make_smoke() -> GPUParticles3D:
	return FxKit.make_smoke(72, 2.4)


## Regle le panache : rien, gris leger, noir epais, ou fumee d'epave (le
## debit change, le panache ne repart pas).
static func set_smoke(p: GPUParticles3D, level: int) -> void:
	if p == null:
		return
	# plus clair la nuit : il prend la lueur de la ville (FxKit.smoke_material)
	var nk := 1.8 if TruckLights.night else 1.0
	match level:
		Smoke.NONE:
			p.emitting = false
		Smoke.LIGHT:
			FxKit.set_smoke_look(p, Color(0.8, 0.8, 0.82, 0.5), 0.35, 0.9, 1.4)
		Smoke.HEAVY:
			# anthracite plutot que noir : il se voit encore sur un ciel de nuit
			FxKit.set_smoke_look(p, Color(0.16 * nk, 0.15 * nk, 0.15 * nk, 0.95), 0.9, 1.4, 2.3)
		_:
			FxKit.set_smoke_look(p, Color(0.1 * nk, 0.095 * nk, 0.09 * nk, 0.95), 1.0, 1.9, 3.0)


## Couleur des bouffees du panache `p`.
static func smoke_color(p: GPUParticles3D) -> Color:
	return (p.process_material as ParticleProcessMaterial).color


## Etincelles (eteintes) : un moteur qui lache crache par a-coups des traits
## orange qui tombent et rebondissent sur la route, `floor_below` m sous
## l'emetteur.
static func make_sparks(floor_below: float = 0.9) -> GPUParticles3D:
	var p := FxKit.make_sparks(36, 0.8, {
		"direction": Vector3(0.0, 0.6, -0.4), "spread": 1.0, "speed_min": 2.5, "speed_max": 7.0,
		"inherit": 0.95, "box_extents": Vector3(0.5, 0.15, 0.2), "gravity": 14.0, "drag": 0.6,
		"floor_below": floor_below, "life_min": 0.35, "stretch": 0.03, "max_len": 0.35,
		"width": 0.018, "heat": 5.0})
	# crepitement : emission irreguliere, par paquets
	p.randomness = 0.9
	p.explosiveness = 0.4
	return p
