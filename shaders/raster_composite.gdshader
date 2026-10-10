shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/raster_common.gdshaderinc"
uniform sampler2D main_tex : filter_nearest, repeat_disable;
uniform sampler2D sub_tex : filter_nearest, repeat_disable;
uniform bool enhanced=true;
uniform sampler2D backdrop_tex : filter_linear, repeat_disable;
uniform sampler2D ceres_wall_tex : filter_linear, repeat_enable;
uniform sampler2D green_bg2_tiles_tex : filter_linear, repeat_disable;
uniform sampler2D pink_bg2_tiles_tex : filter_linear, repeat_disable;
uniform bool remastered_background_enabled=false;
uniform int remastered_background_kind=0;
uniform vec2 backdrop_camera=vec2(0.0);
ivec3 palette5(int row,int pixel) {
	int word=raster_word(row,256+(pixel&255)*2);
	return ivec3(word&31,(word>>5)&31,(word>>10)&31);
}
ivec3 metadata_color(int row,ivec4 data) {
	if(data.w==0)return palette5(row,0);
	if(data.y<4 && (raster_byte(row,82)&8)!=0 && raster_byte(row,108+data.y)==8) {
		int pixel=data.x|(data.z<<8);
		return ivec3(((pixel&7)<<2)|((pixel&256)>>7),((pixel&56)>>1)|((pixel&512)>>8),((pixel&192)>>3)|((pixel&1024)>>8));
	}
	return palette5(row,data.x);
}
ivec4 meta_at(sampler2D source,ivec2 p) {
	return ivec4(round(texture(source,(vec2(clamp(p,ivec2(0),ivec2(255,223)))+0.5)/vec2(256.0,224.0))*255.0));
}
ivec4 scaled_meta(sampler2D source,ivec2 p,ivec2 quadrant) {
	ivec4 e=meta_at(source,p);
	if(!enhanced)return e;
	ivec4 b=meta_at(source,p+ivec2(0,-1)),d=meta_at(source,p+ivec2(-1,0));
	ivec4 f=meta_at(source,p+ivec2(1,0)),h=meta_at(source,p+ivec2(0,1));
	if(b!=h && d!=f) {
		if(quadrant.x==0 && quadrant.y==0 && d==b)return d;
		if(quadrant.x==1 && quadrant.y==0 && b==f)return f;
		if(quadrant.x==0 && quadrant.y==1 && d==h)return d;
		if(quadrant.x==1 && quadrant.y==1 && h==f)return f;
	}
	return e;
}
vec3 composed(ivec2 p,ivec2 quadrant) {
	int row=clamp(p.y,0,223);
	if(raster_byte(row,3)!=0)return vec3(0.0);
	ivec4 main=scaled_meta(main_tex,p,quadrant),sub=scaled_meta(sub_tex,p,quadrant);
	int main_layer=main.w==0?5:main.y,sub_layer=sub.w==0?5:sub.y;
	ivec3 color=metadata_color(row,main);
	bool window=window_at(row,5,p.x);
	int clip=raster_byte(row,80);
	if(clip==3||(clip==2&&window)||(clip==1&&!window))color=ivec3(0);
	int prevent=raster_byte(row,81);
	bool math=main_layer!=6 && (raster_byte(row,83)&(1<<main_layer))!=0 && !(prevent==3||(prevent==2&&window)||(prevent==1&&!window));
	int flags=raster_byte(row,82);
	if(math) {
		bool use_sub=(flags&1)!=0 && sub_layer!=5;
		ivec3 other=use_sub?metadata_color(row,sub):ivec3(raster_byte(row,84),raster_byte(row,85),raster_byte(row,86));
		color=(flags&2)!=0?color-other:color+other;
		if((flags&4)!=0 && ((flags&1)==0||sub_layer!=5))color>>=ivec3(1);
		color=clamp(color,ivec3(0),ivec3(31));
	}
	ivec3 expanded=(color<<ivec3(3))|(color>>ivec3(2));
	return vec3((expanded*raster_byte(row,2))/15)/255.0;
}
vec3 ceres_reference_color(int index) {
	// Native palette 5 at the extracted Ceres reference checkpoint (5-bit RGB).
	// Carry subsequent CGRAM changes into the new art, including escape flashes.
	if(index==81)return vec3(0.0,11.0,13.0);
	if(index==82)return vec3(0.0,6.0,9.0);
	if(index==83)return vec3(0.0,0.0,2.0);
	if(index==84)return vec3(0.0,0.0,1.0);
	if(index==85)return vec3(0.0,9.0,12.0);
	if(index==86)return vec3(0.0,4.0,6.0);
	if(index==87)return vec3(0.0,2.0,5.0);
	return vec3(0.0,0.0,7.0);
}
vec3 green_reference_color(int index) {
	// CGRAM at the source atlas checkpoint. Preserve native palette animation.
	if(index==113)return vec3(0.0,4.0,18.0);
	if(index==114)return vec3(0.0,0.0,14.0);
	if(index==115)return vec3(0.0,0.0,3.0);
	if(index==116)return vec3(0.0,6.0,9.0);
	if(index==117)return vec3(0.0,5.0,7.0);
	if(index==118)return vec3(0.0,4.0,5.0);
	if(index==119)return vec3(0.0,2.0,4.0);
	if(index==120 || index==126)return vec3(31.0,22.0,5.0);
	if(index==121)return vec3(23.0,14.0,5.0);
	if(index==122)return vec3(14.0,7.0,5.0);
	if(index==123)return vec3(6.0,4.0,5.0);
	if(index==124 || index==125)return vec3(24.0);
	return vec3(0.0,0.0,2.0);
}
bool green_tile_supported(int number) {
	return (number>=236 && number<=239) || (number>=252 && number<=255)
		|| (number>=291 && number<=303) || (number>=307 && number<=351);
}
vec3 pink_reference_color(int index) {
	if(index==49)return vec3(18.0,21.0,28.0);
	if(index==50)return vec3(7.0,14.0,28.0);
	if(index==51)return vec3(3.0,8.0,19.0);
	if(index==52)return vec3(4.0,5.0,12.0);
	if(index==53)return vec3(1.0,3.0,9.0);
	if(index==54)return vec3(0.0,2.0,6.0);
	if(index==55)return vec3(0.0,0.0,2.0);
	if(index==56)return vec3(18.0,18.0,23.0);
	if(index==57)return vec3(11.0,11.0,16.0);
	if(index==58)return vec3(4.0,7.0,12.0);
	if(index==59)return vec3(0.0,3.0,7.0);
	if(index==60 || index==61)return vec3(24.0);
	if(index==62)return vec3(28.0,28.0,31.0);
	return vec3(0.0);
}
bool pink_tile_supported(int number) {
	return number>=492 && number<=543 && number%16>=12;
}
vec3 remastered_background(ivec2 p,ivec2 quadrant,vec2 cell,vec3 original) {
	// BG2 is the distant scenery. Protect the HUD, BG1 terrain, all sprites,
	// blanking and pixels whose Scale2x neighbourhood crosses a layer boundary.
	if(!remastered_background_enabled || p.y<32 || raster_byte(p.y,3)!=0 || raster_byte(p.y,0)!=1)return original;
	ivec4 center=meta_at(main_tex,p),main=scaled_meta(main_tex,p,quadrant);
	if(center.w==0 || center.y!=1 || main.w==0 || main.y!=1)return original;
	vec3 color;
	if(remastered_background_kind==2) {
		if(main.x<81 || main.x>88)return original;
		// Sample the same 512x256 BG2 map coordinates as native tiles. The
		// captured scroll registers include camera motion, shaking and HDMA.
		vec2 uv=(cell+vec2(float(raster_word(p.y,44)),1.0+float(raster_word(p.y,46))))/vec2(512.0,256.0);
		color=texture(ceres_wall_tex,uv).rgb*31.0;
		color=clamp(color+vec3(palette5(p.y,main.x))-ceres_reference_color(main.x),vec3(0.0),vec3(31.0));
	} else if(remastered_background_kind==3 || remastered_background_kind==4) {
		// Follow the native BG2 map in VRAM and its live tile IDs/flips.
		// Every replacement retains the original tile's map coordinates.
		// Keep Scale2x pixels copied from another cell on the original path.
		bool pink=remastered_background_kind==4;
		int palette_first=pink?49:113;
		if(main!=center || main.x<palette_first || main.x>palette_first+14 || raster_byte(p.y,65)!=1 || raster_word(p.y,42)!=0)return original;
		ivec2 mapped=(p+ivec2(raster_word(p.y,44),1+raster_word(p.y,46)))&ivec2(1023);
		ivec2 tile=mapped>>ivec2(3);
		int address=raster_word(p.y,40)+(tile.y&31)*32+(tile.x&31);
		if((tile.x&32)!=0)address+=1024;
		int word=vram_word(address&32767),number=word&1023;
		if(((word>>10)&7)!=(pink?3:7) || !(pink?pink_tile_supported(number):green_tile_supported(number)))return original;
		vec2 within=vec2(mapped&ivec2(7))+fract(cell);
		if((word&16384)!=0)within.x=8.0-within.x;
		if((word&32768)!=0)within.y=8.0-within.y;
		if(pink) {
			vec2 inset=vec2(16.0)/vec2(textureSize(pink_bg2_tiles_tex,0));
			within=clamp(within,inset,vec2(8.0)-inset);
			vec2 uv=(vec2(float(number%16-12)*8.0,float(number/16-30)*8.0)+within)/vec2(32.0);
			color=texture(pink_bg2_tiles_tex,uv).rgb*31.0;
			color=clamp(color+vec3(palette5(p.y,main.x))-pink_reference_color(main.x),vec3(0.0),vec3(31.0));
		} else {
			vec2 inset=vec2(64.0,32.0)/vec2(textureSize(green_bg2_tiles_tex,0));
			within=clamp(within,inset,vec2(8.0)-inset);
			vec2 uv=(vec2(float(number%16)*8.0,float(number/16-14)*8.0)+within)/vec2(128.0,64.0);
			color=texture(green_bg2_tiles_tex,uv).rgb*31.0;
			color=clamp(color+vec3(palette5(p.y,main.x))-green_reference_color(main.x),vec3(0.0),vec3(31.0));
		}
	} else {
		vec2 uv=vec2((cell.x+backdrop_camera.x*0.25)/1024.0,
			(cell.y-32.0)/256.0+0.1+max(backdrop_camera.y-512.0,0.0)/4096.0);
		color=texture(backdrop_tex,clamp(uv,vec2(0.0),vec2(1.0))).rgb*31.0;
	}
	bool window=window_at(p.y,5,p.x);
	int clip=raster_byte(p.y,80),prevent=raster_byte(p.y,81);
	if(clip==3 || (clip==2&&window) || (clip==1&&!window))color=vec3(0.0);
	bool math=(raster_byte(p.y,83)&2)!=0 && !(prevent==3 || (prevent==2&&window) || (prevent==1&&!window));
	if(math) {
		ivec4 sub=scaled_meta(sub_tex,p,quadrant);
		int sub_layer=sub.w==0?5:sub.y,flags=raster_byte(p.y,82);
		vec3 other=(flags&1)!=0 && sub_layer!=5?vec3(metadata_color(p.y,sub)):vec3(ivec3(raster_byte(p.y,84),raster_byte(p.y,85),raster_byte(p.y,86)));
		color=(flags&2)!=0?color-other:color+other;
		if((flags&4)!=0 && ((flags&1)==0 || sub_layer!=5))color*=0.5;
		color=clamp(color,vec3(0.0),vec3(31.0));
	}
	color=color/31.0*(float(raster_byte(p.y,2))/15.0);
	// Retain the animated native scenery/rain contribution over the new art.
	return mix(original,color,0.82);
}
void fragment() {
	vec2 cell=clamp(UV*vec2(256.0,224.0),vec2(0.0),vec2(255.999,223.999));
	ivec2 p=ivec2(floor(cell)),q=ivec2(fract(cell)*2.0);
	vec3 color=composed(p,q);
	if(enhanced) {
		vec3 weights=vec3(0.2126,0.7152,0.0722);
		float dx=dot(composed(p+ivec2(1,0),q)-composed(p+ivec2(-1,0),q),weights);
		float dy=dot(composed(p+ivec2(0,1),q)-composed(p+ivec2(0,-1),q),weights);
		float light=clamp(1.02+dx*0.1-dy*0.14,0.88,1.16);
		color=mix(vec3(dot(color,weights)),color,1.08)*light;
	}
	color=remastered_background(p,q,cell,color);
	COLOR=vec4(color,1.0);
}
