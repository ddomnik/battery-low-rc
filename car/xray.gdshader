shader_type spatial;
// X-ray silhouette (§10.1): an overlay pass on car meshes that draws a flat player-colored silhouette only where
// the car is hidden behind other geometry. Visible parts are discarded by comparing this fragment's view depth
// with the scene depth; the margin ignores the car's own parts covering each other.

render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.55);
uniform float margin = 2.2;   // m; larger than the car, so self-occlusion never shows

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_dist = -scene_view.z / scene_view.w;
	float my_dist = -VERTEX.z;
	if (my_dist - scene_dist < margin) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
