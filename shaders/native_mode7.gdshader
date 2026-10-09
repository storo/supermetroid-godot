shader_type canvas_item;
render_mode unshaded;
uniform sampler2D vram_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable;
uniform vec4 matrix;
uniform vec4 center_scroll;
uniform int flags = 0;
uniform int layer = 0;
uniform int priority = 0;
uniform bool enhanced = true;
uniform float brightness = 1.0;

int read_byte(int address) {
	int a = address & 65535;
	return int(round(texture(vram_tex,(vec2(float(a%256),float(a/256))+0.5)/256.0).r*255.0));
}
int signed13(int value) { return ((value & 8191) ^ 4096) - 4096; }
int mode7_pixel(ivec2 coordinate) {
	bool outside = coordinate.x < 0 || coordinate.x >= 1024 || coordinate.y < 0 || coordinate.y >= 1024;
	ivec2 p = coordinate & ivec2(1023);
	if ((flags&4)==0) outside=false;
	if (outside && (flags&8)==0) return 0;
	int number = outside ? 0 : read_byte(((p.y>>3)*128+(p.x>>3))*2);
	return read_byte((number*64+(p.y&7)*8+(p.x&7))*2+1);
}
vec4 pixel_color(int pixel) {
	if (layer==1) {
		if (((pixel>>7)&1)!=priority) return vec4(0.0);
		pixel &= 127;
	}
	if (pixel==0) return vec4(0.0);
	return texture(palette_tex,vec2((float(pixel)+0.5)/256.0,0.5));
}
void fragment() {
	ivec2 screen = ivec2(clamp(floor(UV*vec2(256.0,224.0)),vec2(0.0),vec2(255.0,223.0)));
	int x = (flags&1)!=0 ? 255-screen.x : screen.x;
	int y = (flags&2)!=0 ? 255-(screen.y+1) : screen.y+1;
	int cx=signed13(int(center_scroll.x));
	int cy=signed13(int(center_scroll.y));
	int h=signed13(int(center_scroll.z))-cx;
	int v=signed13(int(center_scroll.w))-cy;
	h=(h&8192)!=0 ? (h|~1023) : (h&1023);
	v=(v&8192)!=0 ? (v|~1023) : (v&1023);
	int a=int(matrix.x), b=int(matrix.y), c=int(matrix.z), d=int(matrix.w);
	int wx=((a*h)&~63)+((b*y)&~63)+((b*v)&~63)+(cx<<8)+a*x;
	int wy=((c*h)&~63)+((d*y)&~63)+((d*v)&~63)+(cy<<8)+c*x;
	ivec2 p=ivec2(wx>>8,wy>>8);
	int e=mode7_pixel(p);
	int pixel=e;
	if (enhanced) {
		int n=mode7_pixel(p+ivec2(0,-1));
		int w=mode7_pixel(p+ivec2(-1,0));
		int r=mode7_pixel(p+ivec2(1,0));
		int s=mode7_pixel(p+ivec2(0,1));
		if (n!=s && w!=r) {
			ivec2 q=ivec2(fract(UV*vec2(256.0,224.0))*2.0);
			if(q.x==0 && q.y==0 && w==n) pixel=w;
			if(q.x==1 && q.y==0 && n==r) pixel=r;
			if(q.x==0 && q.y==1 && w==s) pixel=w;
			if(q.x==1 && q.y==1 && s==r) pixel=s;
		}
	}
	vec4 color=pixel_color(pixel);
	if(enhanced) color.rgb*=1.06;
	COLOR=vec4(color.rgb*brightness,color.a);
}
