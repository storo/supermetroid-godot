shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/raster_common.gdshaderinc"
varying vec4 sprite_data;
const ivec2 SPRITE_SIZES[8] = ivec2[8](ivec2(8,16),ivec2(8,32),ivec2(8,64),ivec2(16,32),ivec2(16,64),ivec2(32,64),ivec2(16,32),ivec2(16,32));
void vertex() { sprite_data=INSTANCE_CUSTOM; }
void fragment() {
	ivec2 screen=ivec2(floor(SCREEN_UV*vec2(256.0,224.0)));
	int row=clamp(screen.y,0,223);
	int index=int(sprite_data.z);
	int flags=int(sprite_data.w);
	ivec2 p=ivec2(clamp(floor(UV*64.0),vec2(0.0),vec2(63.0)));
	ivec2 sizes=SPRITE_SIZES[raster_byte(row,87)];
	int size=(flags&32)!=0?sizes.y:sizes.x;
	bool interlace=raster_byte(row,93)!=0;
	int height=interlace?size/2:size;
	int column=p.x/8;
	int allowed=raster_byte(row,128+index);
	vec4 result=vec4(0.0);
	if(p.x<size && p.y<height && (allowed&(1<<column))!=0 && raster_byte(row,3)==0) {
		if(interlace)p.y=p.y*2+((raster_byte(row,82)&64)!=0?0:1);
		if((flags&1)!=0)p.x=size-1-p.x;
		if((flags&2)!=0)p.y=size-1-p.y;
		int base=raster_word(row,(flags&16)!=0?90:88);
		int number=int(sprite_data.x);
		int used=(((number>>4)+(p.y>>3))<<4)|(((number&15)+(p.x>>3))&15);
		int pixel=planar_pixel((base+used*16)*2,p&ivec2(7),4);
		if(pixel!=0) {
			int palette=int(sprite_data.y)+pixel;
			result=vec4(float(palette)/255.0,float((flags>>2)&3)/255.0,float(palette<192?6:4)/255.0,1.0);
		}
	}
	COLOR=result;
}
