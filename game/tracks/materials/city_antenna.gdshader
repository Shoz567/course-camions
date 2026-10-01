shader_type spatial;

// Antennes de toit (MultiMesh) : mat sombre, feu rouge clignotant au sommet.
// INSTANCE_CUSTOM.r = dephasage du clignotement.

varying vec3 lp;
varying float height;
varying float phase;

void vertex() {
	lp = VERTEX;
	height = length(MODEL_MATRIX[1].xyz);
	phase = INSTANCE_CUSTOM.r;
}

void fragment() {
	float h = (lp.y + 0.5) * height;
	float tip = step(height - 1.2, h);
	float blink = step(0.45, fract(TIME * 0.8 + phase));
	ALBEDO = vec3(0.04, 0.04, 0.05);
	EMISSION = vec3(1.0, 0.08, 0.05) * tip * (0.3 + 4.0 * blink);
	ROUGHNESS = 0.5;
}
