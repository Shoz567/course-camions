class_name TruckVfx
extends Node3D

## Effets visuels arcade (Juice) : flammes d'echappement pendant le boost,
## lueurs neon, et effets de derive.
## Purement visuel : aucune collision, inactif en headless (tests).

var _truck: Truck
var _left_flame: MeshInstance3D
var _right_flame: MeshInstance3D
var _boost_light: OmniLight3D
var _flame_mat: ShaderMaterial


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_physics_process(false)
		return
	_truck = get_parent() as Truck
	_build_boost_flames()


func _build_boost_flames() -> void:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled, unshaded;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float u = clamp(lp.y / 2.0, 0.0, 1.0);
	float flicker = 0.85 + 0.15 * sin(TIME * 45.0 + lp.x * 20.0);
	vec3 core = vec3(1.0, 0.95, 0.8);
	vec3 outer = vec3(0.08, 0.85, 1.0);
	float fade = (1.0 - u) * flicker;
	ALBEDO = mix(outer, core, pow(1.0 - u, 2.0));
	ALPHA = fade;
}
"""
	_flame_mat = ShaderMaterial.new()
	_flame_mat.shader = sh

	var cone := CylinderMesh.new()
	cone.top_radius = 0.04
	cone.bottom_radius = 0.24
	cone.height = 2.0

	# deux echappements verticaux derriere la cabine
	_left_flame = MeshInstance3D.new()
	_left_flame.mesh = cone
	_left_flame.material_override = _flame_mat
	_left_flame.position = Vector3(-1.15, 3.2, 0.4) * TruckSpec.SCALE
	_left_flame.rotation_degrees = Vector3(15.0, 0.0, 0.0)
	_left_flame.visible = false
	_left_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_left_flame)

	_right_flame = MeshInstance3D.new()
	_right_flame.mesh = cone
	_right_flame.material_override = _flame_mat
	_right_flame.position = Vector3(1.15, 3.2, 0.4) * TruckSpec.SCALE
	_right_flame.rotation_degrees = Vector3(15.0, 0.0, 0.0)
	_right_flame.visible = false
	_right_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_right_flame)

	_boost_light = OmniLight3D.new()
	_boost_light.light_color = Color(0.15, 0.85, 1.0)
	_boost_light.light_energy = 3.5
	_boost_light.omni_range = 14.0
	_boost_light.position = Vector3(0.0, 3.0, 0.6) * TruckSpec.SCALE
	_boost_light.visible = false
	_boost_light.shadow_enabled = false
	add_child(_boost_light)


func _physics_process(_delta: float) -> void:
	if _truck == null:
		return
	var boosting := _truck.is_boosting()
	_left_flame.visible = boosting
	_right_flame.visible = boosting
	_boost_light.visible = boosting
	if boosting:
		var scale_y: float = 0.9 + 0.25 * sin(Time.get_ticks_msec() * 0.04)
		_left_flame.scale = Vector3(1.0, scale_y, 1.0)
		_right_flame.scale = Vector3(1.0, scale_y, 1.0)
