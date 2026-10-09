shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform bool enhanced = true;
void fragment() {
	vec3 base = texture(screen_texture, SCREEN_UV).rgb;
	if (enhanced) {
		vec2 texel = SCREEN_PIXEL_SIZE * 2.0;
		vec3 bloom = vec3(0.0);
		for (int x=-1;x<=1;x++) {
			for (int y=-1;y<=1;y++) {
				vec3 c = texture(screen_texture,SCREEN_UV+vec2(float(x),float(y))*texel).rgb;
				bloom += max(c-vec3(0.55),vec3(0.0))/9.0;
			}
		}
		float l = dot(base,vec3(0.2126,0.7152,0.0722));
		base = mix(vec3(l),base,1.12)+bloom*0.24;
		vec2 uv = SCREEN_UV*2.0-1.0;
		base *= 1.0-0.15*pow(clamp(length(uv)/1.414,0.0,1.0),2.0);
	}
	COLOR = vec4(base,1.0);
}
