shader_type spatial;

// A single shared material meant to stand in for per-piece baked materials —
// assign this to a ShaderMaterial, set albedo to white or black (or anything
// else), and it works for every piece type.
uniform vec3 albedo : source_color = vec3(1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Edge/radius detailing — tints tight-curvature areas (rims, collars, fillet
// edges), for a "worn from handling" or "grime in the seams" look depending
// on what color you give it. Uses fwidth(NORMAL) — how fast the surface
// normal changes per screen pixel — as a cheap, texture-free "how sharply is
// this curving" detector. It does NOT distinguish a convex bulge from a
// concave groove (that needs curvature-sign math, which is genuinely fragile
// to tune correctly without a GPU to preview on) — pair this with SSAO
// (Environment setting) for real cavity/corner darkening, and use this
// shader's color for the convex/"worn" side of the look.
uniform vec3 edge_color : source_color = vec3(0.55, 0.5, 0.42);
uniform float edge_metallic : hint_range(0.0, 1.0) = 0.3;
uniform float edge_roughness : hint_range(0.0, 1.0) = 0.2;
uniform float edge_strength : hint_range(0.0, 3.0) = 1.0;
uniform float edge_sharpness : hint_range(0.1, 8.0) = 3.0; // higher = wider band caught by the effect

void fragment() {
	ALBEDO = albedo * texture(albedo_texture, UV).rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;

	float curvature = length(fwidth(NORMAL));
	float edge_mask = clamp(curvature * edge_sharpness, 0.0, 1.0);
	float mix_t = clamp(edge_mask * edge_strength, 0.0, 1.0);
	ALBEDO = mix(ALBEDO, edge_color, mix_t);
	METALLIC = mix(METALLIC, edge_metallic, mix_t);
	ROUGHNESS = mix(ROUGHNESS, edge_roughness, mix_t);
}
