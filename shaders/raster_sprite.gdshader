shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/raster_common.gdshaderinc"
varying vec4 sprite_data;
void vertex() { sprite_data=INSTANCE_CUSTOM; }
void fragment() {
	ivec2 screen=ivec2(floor(SCREEN_UV*vec2(256.0,224.0)));
	int row=clamp(screen.y,0,223);
	int index=int(sprite_data.z)%128;
	int column=int(sprite_data.z)/128;
	int flags=int(sprite_data.w);
	int allowed=raster_byte(row,128+index);
	vec4 result=vec4(0.0);
	if((allowed&(1<<column))!=0 && raster_byte(row,3)==0) {
		ivec2 p=ivec2(clamp(floor(UV*8.0),vec2(0.0),vec2(7.0)));
		if((flags&1)!=0)p.x=7-p.x;
		if((flags&2)!=0)p.y=7-p.y;
		int base=raster_word(row,(flags&16)!=0?90:88);
		int pixel=planar_pixel((base+int(sprite_data.x)*16)*2,p,4);
		if(pixel!=0) {
			int palette=int(sprite_data.y)+pixel;
			result=vec4(float(palette)/255.0,float((flags>>2)&3)/255.0,float(palette<192?6:4)/255.0,1.0);
		}
	}
	COLOR=result;
}
