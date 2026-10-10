/* Offline rendering oracle only. Its pixel buffer never enters Godot gameplay. */
#include "host.h"
#include "snes/snes.h"
#include "snes/ppu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

extern Snes *g_snes;
static uint8_t pixels[256*240*4];
static uint8_t vram[65536],palette[512],oam[544],raster[1024*256];
static int16_t audio[1068];
static FILE *manifest;
static int cases;
static void write_file(const char *directory,const char *name,const void *data,size_t size) {
  char path[4096]; snprintf(path,sizeof(path),"%s/%s",directory,name);
  FILE *file=fopen(path,"wb");
  if(!file||fwrite(data,1,size,file)!=size) { fprintf(stderr,"Cannot write %s\n",name); exit(1); }
  fclose(file);
}
static void fixture(const char *directory,const char *name,int frame) {
  char path[4096]; snprintf(path,sizeof(path),"%s/%s",directory,name);
  if(mkdir(path,0700)!=0) { fprintf(stderr,"Cannot create fixture directory\n"); exit(1); }
  SmNativeState state;
  sm_native_snapshot(&state,vram,palette,oam); sm_native_raster(raster);
  write_file(path,"frame.bgra",pixels,256*224*4);
  write_file(path,"frame.raster",raster,sizeof(raster));
  write_file(path,"frame.vram",vram,sizeof(vram));
  write_file(path,"frame.oam",oam,sizeof(oam));
  fprintf(manifest,"%s{\"name\":\"%s\",\"frame\":%d,\"state\":%d,\"room\":%d,\"mode\":%d,\"room_state\":%d,\"x\":%d,\"y\":%d,\"camera_x\":%d,\"camera_y\":%d,\"pose\":%d,\"health\":%d,\"items\":%d,\"beams\":%d,\"missiles\":%d}",cases++?",\n":"",name,frame,state.state,state.room,state.mode,state.room_state,state.x,state.y,state.camera_x,state.camera_y,state.pose,state.health,state.items,state.beams,state.missiles);
}
int main(int argc,char **argv) {
  if(argc!=3&&argc!=5&&argc!=6) { fprintf(stderr,"Usage: sm_raster_oracle ROM OUTPUT_DIRECTORY [INPUT_TRACE CHECKPOINT_CSV [SRAM_SEED]]\n"); return 1; }
  char save[4096];
  if(argc==6) {
    /* Read the seed without altering it; gameplay writes only a unique copy. */
    uint8_t seed_data[8192];
    FILE *seed=fopen(argv[5],"rb");
    if(!seed) { fprintf(stderr,"Cannot read SRAM seed\n"); return 1; }
    size_t size=fread(seed_data,1,sizeof(seed_data),seed);
    int extra=fgetc(seed); fclose(seed);
    if(size!=sizeof(seed_data)||extra!=EOF) { fprintf(stderr,"SRAM seed must be exactly 8192 bytes\n"); return 1; }
    snprintf(save,sizeof(save),"%s/oracle_XXXXXX",argv[2]);
    int fd=mkstemp(save);
    if(fd<0) { fprintf(stderr,"Cannot create private SRAM copy\n"); return 1; }
    FILE *copy=fdopen(fd,"wb");
    if(!copy) { close(fd); remove(save); return 1; }
    size_t written=fwrite(seed_data,1,sizeof(seed_data),copy);
    int closed=fclose(copy);
    if(written!=sizeof(seed_data)||closed) { remove(save); return 1; }
  } else { snprintf(save,sizeof(save),"%s/oracle.srm",argv[2]); remove(save); }
  if(!sm_native_boot(argv[1],save)) { fprintf(stderr,"%s\n",sm_native_error()); remove(save); return 1; }
  g_snes->disableRender=false;
  g_snes->ppu->renderBuffer=pixels;
  g_snes->ppu->renderPitch=256*4;
  char manifest_path[4096]; snprintf(manifest_path,sizeof(manifest_path),"%s/cases.json",argv[2]);
  manifest=fopen(manifest_path,"w"); if(!manifest)goto fail;
  fprintf(manifest,"[\n");
  SmNativeState state;
  int tick;
  if(argc>=5) {
    FILE *trace=fopen(argv[3],"rb"),*points=fopen(argv[4],"r");
    if(!trace||!points) { fprintf(stderr,"Cannot read replay/checkpoints\n"); goto fail; }
    int frames[32],count=0; char names[32][64],line[128];
    while(fgets(line,sizeof(line),points)) {
      if(count>=32||sscanf(line,"%d,%63[a-z_]",&frames[count],names[count])!=2) {
        fprintf(stderr,"Invalid checkpoint\n"); fclose(trace); fclose(points); goto fail;
      }
      count++;
    }
    fclose(points);
    uint8_t input[2]; tick=0;
    while(fread(input,1,2,trace)==2) {
      tick++;
      int point=-1;
      for(int i=0;i<count;i++)if(frames[i]==tick)point=i;
      g_snes->disableRender=point<0;
      if(!sm_native_tick(input[0]|input[1]<<8,audio)) { fclose(trace); goto fail; }
      if(point>=0)fixture(argv[2],names[point],tick);
    }
    fclose(trace);
    if(cases!=count||count==0) { fprintf(stderr,"Missing replay checkpoints\n"); goto fail; }
    fprintf(manifest,"\n]\n"); fclose(manifest); manifest=NULL;
    printf("RASTER_ORACLE_OK: %d replay fixtures from %d native input ticks\n",cases,tick);
    sm_native_close(); remove(save); return 0;
  }
  for(tick=0;tick<9000;tick++) {
    if(!sm_native_tick(tick%60<2?0x1080:0,audio))goto fail;
    sm_native_snapshot(&state,vram,palette,oam);
    if(tick==1199||tick==2399||tick==4799||tick==7199) {
      char name[64]; snprintf(name,sizeof(name),"intro_%d",tick+1);
      fixture(argv[2],name,tick+1);
    }
    if(state.state==8&&state.room==0xdf45)break;
  }
  if(tick==9000) { fprintf(stderr,"Ceres not reached\n"); goto fail; }
  for(int i=0;i<180;i++)if(!sm_native_tick(0,audio))goto fail;
  fixture(argv[2],"ceres_elevator",tick+181);
  sm_native_snapshot(&state,vram,palette,oam);
  int reached_corridor=0;
  for(int i=0;i<1200;i++) {
    /* Descend through the shaft's alternating platforms using ordinary input. */
    int target=state.y<160?184:state.y<260?128:state.y<350?64:state.y<445?128:184;
    uint16_t joy=state.y>=540?0x100:(state.x>target+4?0x200:state.x<target-4?0x100:0);
    if(i%30<5)joy|=0x40;
    if(!sm_native_tick(joy,audio))goto fail;
    sm_native_snapshot(&state,vram,palette,oam);
    if(state.state==8&&state.room==0xdf8d&&state.brightness==15) {
      fixture(argv[2],"ceres_corridor",tick+182+i);
      reached_corridor=1;
      break;
    }
  }
  printf("RASTER_ROUTE_END: room=%04x state=%d x=%d y=%d pose=%d\n",state.room,state.state,state.x,state.y,state.pose);
  if(!reached_corridor) { fprintf(stderr,"Native input route did not reach Ceres corridor\n"); goto fail; }
  fprintf(manifest,"\n]\n"); fclose(manifest); manifest=NULL;
  printf("RASTER_ORACLE_OK: %d native gameplay fixtures; offline PPU pixel oracle\n",cases);
  sm_native_close(); remove(save); return 0;
fail:
  if(manifest) { fclose(manifest); manifest=NULL; }
  fprintf(stderr,"%s\n",sm_native_error()); sm_native_close(); remove(save); return 1;
}
