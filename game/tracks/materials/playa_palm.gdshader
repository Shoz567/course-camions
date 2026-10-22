shader_type spatial;
render_mode cull_disabled;

// Palmier : tronc annele brun (trunk = true) ou palmes vertes qui ondulent
// dans le vent (UV.y : 0 a la base de la palme, 1 a sa pointe). Palmier
// detaille (TreeKit) : un sommet a alpha < 0,5 prend sa couleur telle quelle
// (palmes seches, noix de coco) ; `rings` : anneaux du tronc par unite d'UV.
uniform bool trunk = false;
uniform float rings = 5.0;

void vertex() {
	if (!trunk) {
		vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float phase = origin.x * 0.13 + origin.z * 0.17;
		float tip = UV.y * UV.y;
		VERTEX.y += sin(TIME * 1.6 + phase + UV.y * 2.0) * 0.06 * tip;
		VERTEX.x += sin(TIME * 1.1 + phase) * 0.04 * tip;
	}
}

void fragment() {
	if (trunk) {
		float ring = smoothstep(0.35, 0.5, abs(fract(UV.y * rings) - 0.5));
		ALBEDO = mix(vec3(0.42, 0.31, 0.2), vec3(0.27, 0.19, 0.12), ring);
		ROUGHNESS = 0.9;
	} else {
		// nervure plus claire, pointe plus jaune
		float rib = 1.0 - abs(UV.x - 0.5) * 2.0;
		vec3 leaf = mix(vec3(0.07, 0.33, 0.08), vec3(0.2, 0.55, 0.12), UV.y * 0.6 + (1.0 - rib) * 0.3);
		ALBEDO = COLOR.a < 0.5 ? COLOR.rgb : leaf;
		ROUGHNESS = 0.6;
		// la lumiere traverse un peu les palmes
		BACKLIGHT = vec3(0.12, 0.3, 0.05);
	}
}
