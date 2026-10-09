shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/raster_common.gdshaderinc"
uniform sampler2D main_tex : filter_nearest, repeat_disable;
uniform sampler2D sub_tex : filter_nearest, repeat_disable;
uniform bool enhanced=true;
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
	COLOR=vec4(color,1.0);
}
