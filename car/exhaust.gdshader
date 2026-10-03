shader_type spatial;
// Boost exhaust cone: additive glow, bright at the nozzle, fading to the tip and toward the cone's silhouette.
// The cone mesh is a CylinderMesh with its tip at +Y (model space), base at -Y.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(0.3, 0.55, 1.0);
uniform float intensity = 1.0;      // 0..1, driven per frame (fade in/out + flicker)
uniform float half_length = 0.5;    // half the mesh height

varying float along;                // 0 at the nozzle (base), 1 at the tip

void vertex() {
	along = clamp((VERTEX.y + half_length) / (2.0 * half_length), 0.0, 1.0);
}

void fragment() {
	float fade = 1.0 - along;
	float facing = abs(dot(NORMAL, VIEW));
	ALBEDO = color * (0.6 + 0.6 * fade);
	ALPHA = fade * fade * facing * intensity;
}
