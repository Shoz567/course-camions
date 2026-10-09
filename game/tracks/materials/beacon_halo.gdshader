shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Halo du gyrophare d'un baril (quad toujours face a la camera, additif) :
// disque doux et rayons en croix, dont l'intensite suit le stroboscope
// (`flash`, pose par le baril). Il garde une taille apparente minimale au
// loin : le baril se repere a plus de 250 m.
uniform vec4 color : source_color = vec4(1.0, 0.6, 0.05, 1.0);
uniform float flash = 1.0;
uniform float min_pixels = 26.0;

void vertex() {
	// face a la camera, agrandi au loin pour ne pas tomber sous min_pixels
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float dist = max(-center.z, 0.1);
	float world_per_px = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float size = max(1.0, min_pixels * world_per_px / 3.0);
	vec4 v = center + vec4(VERTEX.xy * size, 0.0, 0.0);
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float disc = exp(-r * r * 6.0);
	float rays = exp(-abs(p.x) * 26.0) * (1.0 - r) + exp(-abs(p.y) * 26.0) * (1.0 - r);
	ALBEDO = color.rgb * (disc + 0.6 * max(rays, 0.0)) * flash * 2.2;
}
