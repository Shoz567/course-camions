shader_type spatial;

// Bande d'avertissement du baril explosif : chevrons jaunes et noirs tres
// contrastes, lumineux (lisibles de jour sur l'asphalte clair comme de nuit),
// qui pulsent au rythme du gyrophare. UV.x : tour du fut (0 .. 1), UV.y :
// hauteur de la bande (0 .. 1).
uniform float chevrons = 9.0;
uniform float glow = 2.2;

void fragment() {
	float v = abs(UV.y - 0.5) * 2.0;
	float stripe = step(0.5, fract(UV.x * chevrons + v * 0.45));
	vec3 yellow = vec3(1.0, 0.78, 0.04);
	vec3 black = vec3(0.015, 0.015, 0.02);
	vec3 col = mix(black, yellow, stripe);
	float pulse = 0.75 + 0.25 * sin(TIME * 9.0);
	ALBEDO = col;
	EMISSION = yellow * stripe * glow * pulse;
	ROUGHNESS = 0.45;
}
