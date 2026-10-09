shader_type canvas_item;
render_mode unshaded;
uniform sampler2D vram_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable;
uniform bool enhanced = true;
uniform float brightness = 1.0;
varying vec4 tile_data;

int read_byte(int address) {
	int a = address & 65535;
	return int(round(texture(vram_tex, (vec2(float(a % 256), float(a / 256)) + 0.5) / 256.0).r * 255.0));
}
int pixel_index(ivec2 position) {
	ivec2 p = clamp(position, ivec2(0), ivec2(7));
	int flags = int(tile_data.w);
	if ((flags & 1) != 0) p.x = 7 - p.x;
	if ((flags & 2) != 0) p.y = 7 - p.y;
	int base = int(tile_data.x) + p.y * 2;
	int depth = int(tile_data.z);
	int value = 0;
	for (int plane = 0; plane < 8; plane++) {
		if (plane < depth) {
			int bits = read_byte(base + (plane / 2) * 16 + (plane & 1));
			value |= ((bits >> (7 - p.x)) & 1) << plane;
		}
	}
	return value;
}
vec4 palette_color(int pixel) {
	if (pixel == 0) return vec4(0.0);
	int index = (int(tile_data.y) + pixel) & 255;
	return texture(palette_tex, vec2((float(index) + 0.5) / 256.0, 0.5));
}
void vertex() {
	tile_data = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 cell = clamp(UV * 8.0, vec2(0.0), vec2(7.999));
	ivec2 p = ivec2(floor(cell));
	int e = pixel_index(p);
	int result = e;
	int b = pixel_index(p + ivec2(0, -1));
	int d = pixel_index(p + ivec2(-1, 0));
	int f = pixel_index(p + ivec2(1, 0));
	int h = pixel_index(p + ivec2(0, 1));
	if (enhanced && b != h && d != f) {
		ivec2 q = ivec2(fract(cell) * 2.0);
		if (q.x == 0 && q.y == 0 && d == b) result = d;
		if (q.x == 1 && q.y == 0 && b == f) result = f;
		if (q.x == 0 && q.y == 1 && d == h) result = d;
		if (q.x == 1 && q.y == 1 && h == f) result = f;
	}
	vec4 color = palette_color(result);
	if (enhanced && color.a > 0.0) {
		vec3 weights = vec3(0.2126, 0.7152, 0.0722);
		float dx = dot(palette_color(f).rgb - palette_color(d).rgb, weights);
		float dy = dot(palette_color(h).rgb - palette_color(b).rgb, weights);
		float light = clamp(1.04 + dx * 0.10 - dy * 0.14, 0.88, 1.16);
		color.rgb = mix(vec3(dot(color.rgb, weights)), color.rgb, 1.08) * light;
	}
	COLOR = vec4(color.rgb * brightness, color.a);
}
