shader_type canvas_item;

// CRT/Static effect for retro handheld device aesthetic
// Combines subtle scanlines, vignette, chromatic aberration, and occasional static interference

uniform float scanline_intensity : hint_range(0.0, 0.2) = 0.03;
uniform float vignette_strength : hint_range(0.0, 0.5) = 0.15;
uniform float chromatic_aberration : hint_range(0.0, 0.01) = 0.002;
uniform float static_frequency : hint_range(0.0, 0.3) = 0.08;
uniform float static_duration : hint_range(0.05, 0.5) = 0.2;
uniform float static_intensity : hint_range(0.0, 0.5) = 0.15;

// Simple hash function for randomization
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Generate random vertical static lines
float get_static(vec2 uv, float time) {
	// Create time-based seed for when static appears
	float time_block = floor(time / static_duration);
	float random_trigger = hash(vec2(time_block, 0.0));

	// Only show static based on frequency
	if (random_trigger > static_frequency) {
		return 0.0;
	}

	// Create vertical lines at random x positions
	float line_count = 5.0 + hash(vec2(time_block, 1.0)) * 10.0;
	for (float i = 0.0; i < 15.0; i++) {
		if (i >= line_count) break;

		float line_x = hash(vec2(time_block, i + 2.0));
		float line_width = 0.001 + hash(vec2(time_block, i + 100.0)) * 0.003;

		if (abs(uv.x - line_x) < line_width) {
			// Vary intensity along the line
			float intensity_var = hash(vec2(uv.y * 100.0, time_block + i));
			return static_intensity * (0.5 + intensity_var * 0.5);
		}
	}

	return 0.0;
}

void fragment() {
	vec2 uv = UV;

	// 1. Scanlines - subtle horizontal lines
	float scanline = sin(uv.y * 3.14159 * 2.0 * 400.0) * scanline_intensity;

	// 2. Vignette - darken edges
	vec2 centered_uv = uv * 2.0 - 1.0;
	float vignette = 1.0 - length(centered_uv) * vignette_strength;
	vignette = clamp(vignette, 0.0, 1.0);

	// 3. Chromatic aberration - very subtle, only at edges
	float edge_dist = length(centered_uv);
	vec2 direction = normalize(centered_uv);
	float aberration_amount = chromatic_aberration * edge_dist;

	// Sample texture with slight color separation (simulating old LCD/CRT)
	vec4 col = texture(TEXTURE, uv);
	float r = texture(TEXTURE, uv + direction * aberration_amount).r;
	float g = col.g;
	float b = texture(TEXTURE, uv - direction * aberration_amount).b;

	vec3 final_color = vec3(r, g, b);

	// 4. Apply scanlines and vignette
	final_color -= scanline;
	final_color *= vignette;

	// 5. Add static interference
	float static_value = get_static(uv, TIME);
	final_color += static_value;

	COLOR = vec4(final_color, col.a);
}
