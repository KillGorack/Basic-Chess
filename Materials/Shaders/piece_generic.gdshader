shader_type spatial;

uniform vec3 albedo : source_color = vec3(1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec3 edge_color : source_color = vec3(0.55, 0.5, 0.42);
uniform float edge_metallic : hint_range(0.0, 1.0) = 0.3;
uniform float edge_roughness : hint_range(0.0, 1.0) = 0.2;
uniform float edge_strength : hint_range(0.0, 3.0) = 1.0;
uniform float edge_sharpness : hint_range(0.1, 8.0) = 3.0;

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
