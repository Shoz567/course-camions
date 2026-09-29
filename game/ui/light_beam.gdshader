shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Faisceau de projecteur (cone ouvert vers le haut, additif) : intense au pied,
// qui s'evanouit en montant ; plus dense sur les bords vus de face.

uniform vec4 color : source_color = vec4(0.1, 0.9, 1.0, 1.0);
uniform float height = 70.0;
uniform float strength = 0.45;
varying float hy;

void vertex() {
	hy = VERTEX.y / height + 0.5;
}

void fragment() {
	float fade = pow(clamp(1.0 - hy, 0.0, 1.0), 1.6);
	float edge = 0.35 + 0.65 * (1.0 - abs(dot(NORMAL, VIEW)));
	ALBEDO = color.rgb * fade * edge * strength;
}
