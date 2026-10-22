shader_type spatial;
render_mode cull_disabled;

// Tout ce qui luit dans le decor de bord de piste (RoadsideDressing) : neons,
// lanternes de papier, enseignes. Couleur de sommet (un seul materiau pour
// toutes les couleurs : un appel de rendu par case) ; COLOR.a : force de la
// lueur (0 : peint, 1 : pleine lueur). Lumineux de nuit comme de jour.

uniform float glow = 2.2;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.5;
	EMISSION = COLOR.rgb * glow * COLOR.a;
	BACKLIGHT = COLOR.rgb * 0.4 * COLOR.a;
}
