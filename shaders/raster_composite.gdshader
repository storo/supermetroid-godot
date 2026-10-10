shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/raster_common.gdshaderinc"
uniform sampler2D main_tex : filter_nearest, repeat_disable;
uniform sampler2D sub_tex : filter_nearest, repeat_disable;
uniform bool enhanced=true;
uniform sampler2D backdrop_tex : filter_linear, repeat_disable;
uniform sampler2D ceres_wall_tex : filter_linear, repeat_enable;
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
