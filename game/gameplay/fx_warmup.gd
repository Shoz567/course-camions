class_name FxWarmup
extends SubViewport

## Prechauffe des effets (tache 7.6, 2026-10-17) : la premiere explosion
## d'une course a 4 joueurs figeait l'image 370 ms (9 pipelines de shaders
## compiles a son premier affichage : flammes, fumee, braises, texte KABOOM).
## Au chargement, une petite vue cachee (jamais affichee, meme monde que la
## course) filme pendant FRAMES images, a AT - tres loin sous la piste, hors
## de portee des cameras, des lumieres et des secousses - une explosion, un
## texte KABOOM, des etincelles, une fumee de degats et un debris fumant :
## leurs pipelines sont compiles avant le depart. Puis tout se libere.
## Purement visuel ; rien en headless.

const AT := Vector3(0.0, -600.0, 0.0)
## Images filmees : la boule de feu, puis la fumee et les braises (~0,75 s).
const FRAMES := 45

var _world: Node
var _quality: int
var _spawned: Array[Node] = []
var _frames: int = 0


## Lance la prechauffe sous `world` (la course), au format des vues de la
## course (`quality` : anticrenelage, GraphicsSettings.apply_viewport).
static func start(world: Node, quality: int) -> FxWarmup:
	if DisplayServer.get_name() == "headless":
		return null
	var w := FxWarmup.new()
	w._world = world
	w._quality = quality
	world.add_child(w)
	return w


func _ready() -> void:
	name = "FxWarmup"
	size = Vector2i(256, 144)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	GraphicsSettings.apply_viewport(self, _quality)
	# pas une case de l'ecran partage : la resolution dynamique ne la suit pas
	remove_from_group(DynamicResolution.GROUP)
	var cam := Camera3D.new()
	cam.position = AT + Vector3(0.0, 4.0, 16.0)
	add_child(cam)
	cam.look_at(AT + Vector3.UP * 2.0)
	cam.current = true
	_spawned.append(ExplosionFx.spawn(_world, AT, 6.0, false))
	_spawned.append(KaboomText.spawn(_world, AT + Vector3.UP * 5.0))
	_spawned.append(FxKit.fire_once(_world, DamageFx.make_sparks(), AT + Vector3(2.0, 1.0, 0.0)))
	var smoke := DamageFx.make_smoke()
	DamageFx.set_smoke(smoke, 2)
	_world.add_child(smoke)
	smoke.global_position = AT + Vector3(-2.0, 1.0, 0.0)
	smoke.emitting = true
	_spawned.append(smoke)
	var shard := Debris.shard(_world, AT + Vector3(0.0, 2.0, 3.0), Vector3(0.6, 0.05, 0.4), null, Vector3.ZERO)
	shard.gravity_scale = 0.0
	shard.add_trail(true)
	_spawned.append(shard)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < FRAMES:
		return
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	queue_free()
