uniform sampler2D vram_tex : filter_nearest, repeat_disable;
uniform sampler2D raster_tex : filter_nearest, repeat_disable;
int raster_byte(int row, int offset) {
	return int(round(texture(raster_tex,vec2((float(offset)+0.5)/1024.0,(float(clamp(row,0,223))+0.5)/256.0)).r*255.0));
}
int raster_word(int row,int offset) { return raster_byte(row,offset)|(raster_byte(row,offset+1)<<8); }
int signed_word(int value) { return (value^32768)-32768; }
int signed13(int value) { return ((value&8191)^4096)-4096; }
int vram_byte(int address) {
	int a=address&65535;
	return int(round(texture(vram_tex,(vec2(float(a%256),float(a/256))+0.5)/256.0).r*255.0));
}
int vram_word(int address) { return vram_byte(address*2)|(vram_byte(address*2+1)<<8); }
bool window_at(int row,int layer,int x) {
	int flags=raster_byte(row,68+layer);
	bool a=x>=raster_byte(row,12)&&x<=raster_byte(row,13);
	bool b=x>=raster_byte(row,14)&&x<=raster_byte(row,15);
	if((flags&1)!=0)a=!a;
	if((flags&4)!=0)b=!b;
	if((flags&2)==0)return (flags&8)!=0&&b;
	if((flags&8)==0)return a;
	int logic=raster_byte(row,74+layer);
	if(logic==0)return a||b;
	if(logic==1)return a&&b;
	if(logic==2)return a!=b;
	return a==b;
}
bool layer_active(int row,int layer,int x,bool sub) {
	if((raster_byte(row,sub?9:8)&(1<<layer))==0)return false;
	return (raster_byte(row,sub?11:10)&(1<<layer))==0||!window_at(row,layer,x);
}
int planar_pixel(int address,ivec2 p,int depth) {
	int value=0;
	for(int plane=0;plane<8;plane++) {
		if(plane<depth) {
			int bits=vram_byte(address+p.y*2+(plane/2)*16+(plane&1));
			value|=((bits>>(7-p.x))&1)<<plane;
		}
	}
	return value;
}
