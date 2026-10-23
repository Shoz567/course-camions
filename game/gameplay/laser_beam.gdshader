shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Halo du laser (TruckPowers, 2026-10-23 : « c'est juste un trait rouge
// lambda ») : cylindre additif aux bords doux (il s'efface la ou on le voit de
// biais), cœur plus clair au centre, pulsations d'energie qui filent le long
// du rayon (UV.y : 0 a la bouche, 1 a l'impact) et leger scintillement.
// Purement visuel.

uniform vec4 glow_color : source_color = vec4(1.0, 0.12, 0.38, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.8, 0.92, 1.0);
uniform float energy = 3.0;
// longueur du rayon (m) : les pulsations gardent le meme pas quelle qu'elle soit
uniform float length_m = 10.0;
uniform float pulse_speed = 42.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = pow(facing, 2.2);
	float along = UV.y * length_m;
	float pulse = 0.6 + 0.4 * sin(along * 1.3 - TIME * pulse_speed);
	float shimmer = 0.88 + 0.12 * sin(TIME * 97.0 + along * 5.0);
	// fondu a la bouche, pour que le rayon naisse de l'arme
	float birth = smoothstep(0.0, 0.6, along);
	vec3 col = mix(glow_color.rgb, core_color.rgb, pow(facing, 7.0));
	ALBEDO = col * energy * soft * pulse * shimmer * birth;
}
