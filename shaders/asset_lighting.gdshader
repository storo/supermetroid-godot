shader_type canvas_item;
render_mode unshaded;
// Surface relief derived from the extracted sprite's own palette luminance.
// UV, silhouette, alpha, frame layout and anchors remain untouched.
varying vec4 vertex_tint;
void vertex() { vertex_tint = COLOR; }
uniform float relief = 2.2;
uniform float specular_strength = 0.055;
float luminance(vec3 c) { return dot(c,vec3(0.2126,0.7152,0.0722)); }
void fragment() {
	vec4 source = texture(TEXTURE,UV);
	vec2 d = TEXTURE_PIXEL_SIZE;
	float left = luminance(texture(TEXTURE,UV-vec2(d.x,0.0)).rgb);
	float right = luminance(texture(TEXTURE,UV+vec2(d.x,0.0)).rgb);
	float top = luminance(texture(TEXTURE,UV-vec2(0.0,d.y)).rgb);
	float bottom = luminance(texture(TEXTURE,UV+vec2(0.0,d.y)).rgb);
	vec3 normal = normalize(vec3((left-right)*relief,(top-bottom)*relief,1.0));
	vec3 light = normalize(vec3(-0.35,-0.55,1.0));
	float diffuse = max(dot(normal,light),0.0);
	float highlight = pow(max(dot(normal,normalize(light+vec3(0.0,0.0,1.0))),0.0),20.0);
	vec3 color = source.rgb*(0.84+0.22*diffuse)+vec3(0.85,0.97,1.0)*highlight*specular_strength;
	COLOR = vec4(color,source.a)*vertex_tint;
}
