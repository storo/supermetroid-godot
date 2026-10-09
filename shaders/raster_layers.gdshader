shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/raster_common.gdshaderinc"
uniform sampler2D sprites_tex : filter_nearest, repeat_disable;
uniform int draw_rank = 0;
uniform bool subscreen = false;

int tilemap_word(int row,int layer,ivec2 p,bool wide) {
	int flags=raster_byte(row,64+layer);
	int bits_y=(flags&4)!=0?4:3;
	int bits_x=wide?4:3;
	int tx=p.x>>bits_x,ty=p.y>>bits_y;
	int address=raster_word(row,32+layer*8)+(ty&31)*32+(tx&31);
	if((flags&1)!=0&&(tx&32)!=0)address+=1024;
	if((flags&2)!=0&&(ty&32)!=0)address+=(flags&1)!=0?2048:1024;
	return vram_word(address&32767);
}
ivec2 handle_offset(int row,int layer,ivec2 p,int mode) {
	int sx=raster_word(row,36+layer*8),sy=raster_word(row,38+layer*8);
	int column=mode==6?((p.x&~15)-((sx*2)&65520))>>4:((p.x&~7)-(sx&65528))>>3;
	if(column>0) {
		ivec2 scroll=ivec2(raster_word(row,52),raster_word(row,54));
		bool wide=(raster_byte(row,66)&4)!=0;
		int h=tilemap_word(row,2,ivec2((column-1)*8,0)+scroll,wide);
		int v=0;
		if(mode==4) { if((h&32768)!=0){v=h;h=0;} }
		else v=tilemap_word(row,2,ivec2((column-1)*8,8)+scroll,wide);
		int valid=layer==0?8192:16384;
		if((h&valid)!=0)p.x=mode==6?(((h&1016)+column*8)*2)|(p.x&15):((h&1016)+column*8)|(p.x&7);
		if((v&valid)!=0)p.y=(v&1023)+(p.y-sy);
	}
	return p;
}
ivec3 background_pixel(int row,int layer,ivec2 screen) {
	int mode=raster_byte(row,0),depth=raster_byte(row,108+layer);
	if(depth==0)return ivec3(0);
	ivec2 p=screen+ivec2(0,1);
	int mosaic=raster_byte(row,5);
	if((raster_byte(row,6)&(1<<layer))!=0&&mosaic>1) {
		p.x-=p.x%mosaic;
		p.y-=(p.y-raster_byte(row,7))%mosaic;
	}
	if(mode==7) {
		int flags=raster_byte(row,4);
		int x=(flags&1)!=0?255-p.x:p.x,y=(flags&2)!=0?255-p.y:p.y;
		int cx=signed13(raster_word(row,24)),cy=signed13(raster_word(row,26));
		int h=signed13(raster_word(row,28))-cx,v=signed13(raster_word(row,30))-cy;
		h=(h&8192)!=0?h|~1023:h&1023; v=(v&8192)!=0?v|~1023:v&1023;
		int a=signed_word(raster_word(row,16)),b=signed_word(raster_word(row,18));
		int c=signed_word(raster_word(row,20)),d=signed_word(raster_word(row,22));
		p=ivec2((((a*h)&~63)+((b*y)&~63)+((b*v)&~63)+(cx<<8)+a*x)>>8,(((c*h)&~63)+((d*y)&~63)+((d*v)&~63)+(cy<<8)+c*x)>>8);
		bool outside=p.x<0||p.x>=1024||p.y<0||p.y>=1024;
		if((flags&4)==0)outside=false;
		p&=ivec2(1023);
		if(outside&&(flags&8)==0)return ivec3(0);
		int number=outside?0:vram_byte(((p.y>>3)*128+(p.x>>3))*2);
		int pixel=vram_byte((number*64+(p.y&7)*8+(p.x&7))*2+1);
		int priority=layer==1?(pixel>>7)&1:0;
		if(layer==1)pixel&=127;
		return ivec3(pixel,priority,0);
	}
	p+=ivec2(raster_word(row,36+layer*8),raster_word(row,38+layer*8));
	bool mosaic_active=(raster_byte(row,6)&(1<<layer))!=0;
	if(mode==5||mode==6) {
		p.x=p.x*2+((subscreen||mosaic_active)?0:1);
		int flags=raster_byte(row,82);
		if((flags&32)!=0)p.y=p.y*2+(((flags&64)!=0||mosaic_active)?0:1);
	}
	if(mode==2||mode==4||mode==6)p=handle_offset(row,layer,p,mode);
	p&=ivec2(1023);
	int flags=raster_byte(row,64+layer);
	bool wide=(flags&4)!=0||mode==5||mode==6;
	int word=tilemap_word(row,layer,p,wide);
	int number=word&1023;
	if(wide && bool(p.x&8)!=bool(word&16384))number+=1;
	if((flags&4)!=0 && bool(p.y&8)!=bool(word&32768))number+=16;
	ivec2 within=p&ivec2(7);
	if((word&16384)!=0)within.x=7-within.x;
	if((word&32768)!=0)within.y=7-within.y;
	int address=raster_word(row,34+layer*8)*2+(number&1023)*depth*8;
	int pixel=planar_pixel(address,within,depth);
	int palette=(word>>10)&7;
	if(mode==0)palette+=layer*8;
	if(pixel!=0 && depth<8)pixel+=palette*(1<<depth);
	return ivec3(pixel,(word>>13)&1,palette);
}
void fragment() {
	ivec2 p=ivec2(clamp(floor(UV*vec2(256.0,224.0)),vec2(0.0),vec2(255.0,223.0)));
	int row=p.y;
	vec4 result=vec4(0.0);
	if(raster_byte(row,3)==0) {
		vec4 sprite=texture(sprites_tex,(vec2(p)+0.5)/vec2(256.0,224.0));
		int sprite_priority=int(round(sprite.g*255.0));
		if(sprite.a>0.5 && raster_byte(row,104+sprite_priority)==draw_rank && layer_active(row,4,p.x,subscreen)) {
			result=vec4(sprite.r,sprite.b,0.0,1.0);
		} else {
			for(int layer=0;layer<4;layer++) {
				if(layer_active(row,layer,p.x,subscreen)) {
					int low=raster_byte(row,96+layer*2),high=raster_byte(row,97+layer*2);
					if(low==draw_rank||high==draw_rank) {
						ivec3 pixel=background_pixel(row,layer,p);
						if(pixel.x!=0 && raster_byte(row,96+layer*2+pixel.y)==draw_rank) {
							result=vec4(float(pixel.x&255)/255.0,float(layer)/255.0,float(pixel.z&7)/255.0,1.0);
						}
					}
				}
			}
		}
	}
	COLOR=result;
}
