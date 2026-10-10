#include "green_route.h"

static int16_t audio[1068];
int main(int argc,char **argv) {
  if(argc!=5||(strcmp(argv[3],"--seed")&&strcmp(argv[3],"--prefix"))) {
    fprintf(stderr,"Usage: sm_green_route ROM OUTPUT_DIRECTORY --seed SRAM | --prefix INPUT_TRACE\n"); return 1;
  }
  int seeded=strcmp(argv[3],"--seed")==0;
  FILE *source=fopen(argv[4],"rb");
  if(!source) { perror("Route source"); return 1; }
  char save[4096],input_path[4096],csv_path[4096];
  snprintf(save,sizeof(save),"%s/green_XXXXXX",argv[2]);
  int fd=mkstemp(save);
  if(fd<0) { fclose(source); return 1; }
  close(fd);
  if(seeded) {
    uint8_t data[8192]; size_t size=fread(data,1,sizeof(data),source); int extra=fgetc(source); fclose(source); source=NULL;
    if(size!=sizeof(data)||extra!=EOF) { fprintf(stderr,"SRAM seed must be exactly 8192 bytes\n"); remove(save); return 1; }
    FILE *copy=fopen(save,"wb");
    if(!copy) { remove(save); return 1; }
    size_t written=fwrite(data,1,sizeof(data),copy); int closed=fclose(copy);
    if(written!=sizeof(data)||closed) { remove(save); return 1; }
  }
  snprintf(input_path,sizeof(input_path),"%s/green.inputs",argv[2]);
  snprintf(csv_path,sizeof(csv_path),"%s/green.csv",argv[2]);
  if(!sm_native_boot(argv[1],save)) { fprintf(stderr,"%s\n",sm_native_error()); if(source)fclose(source); remove(save); return 1; }
  FILE *inputs=fopen(input_path,"wb"),*csv=fopen(csv_path,"w");
  if(!inputs||!csv) { if(inputs)fclose(inputs); if(csv)fclose(csv); if(source)fclose(source); sm_native_close(); remove(save); return 1; }
  fprintf(csv,"frame,state,room,x,y,pose,health,items,missiles,capacity,selected,projectiles,kills,quota,events_low,movement_type,room_state,bosses_low,bombs,max_health,save_station,save_slot,save_writes,area,supers\n");
  GreenRoute route={0}; SmNativeState s; sm_native_state(&s);
  uint16_t previous_room=0; int success=0;
  for(int frame=0;frame<120000;frame++) {
    uint16_t joy=0;
    if(source) {
      uint8_t bytes[2]; size_t count=fread(bytes,1,2,source);
      if(count==2)joy=bytes[0]|bytes[1]<<8;
      else {
        fclose(source); source=NULL;
        if(count||s.state!=8||s.room!=0x93d5||s.max_health!=199||!(s.items&0x1000)||!(s.boss_flags[0]&4)||!(s.event_flags[0]&1)) {
          fprintf(stderr,"Invalid station input prefix\n"); break;
        }
        route.ready=1; route.load_age=400; joy=green_route_input(&route,&s);
      }
    } else joy=green_route_input(&route,&s);
    uint8_t bytes[2]={joy&255,joy>>8}; fwrite(bytes,1,2,inputs);
    if(!sm_native_tick(joy,audio)) { fprintf(stderr,"Frame %d: %s\n",frame,sm_native_error()); break; }
    sm_native_state(&s);
    fprintf(csv,"%d,%d,%04x,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%u,%d,%d\n",frame+1,s.state,s.room,s.x,s.y,s.pose,s.health,s.items,s.missiles,s.missile_capacity,s.selected_item,s.active_projectiles,s.room_kills,s.room_quota,s.event_flags[0]|s.event_flags[1]<<8,s.movement_type,s.room_state,s.boss_flags[0],s.active_bombs,s.max_health,s.save_station,s.save_slot,s.save_writes,s.area,s.supers);
    if(s.room!=previous_room||frame%180==0) {
      printf("GREEN_FRAME %d state=%d room=%04x x=%d y=%d pose=%04x health=%d/%d phase=%d ledge=%d joy=%04x\n",frame+1,s.state,s.room,s.x,s.y,s.pose,s.health,s.max_health,route.phase,route.station.ascent.stage,joy);
      fflush(stdout); previous_room=s.room;
    }
    if(route.ready&&s.state==8&&s.room==0x9ad9&&s.area==1&&route.green_age>=160&&route.moved&&s.health>0&&s.max_health==199&&(s.items&0x1004)==0x1004) { success=1; break; }
    if(s.state>=19&&s.state<=26) { fprintf(stderr,"Samus died\n"); break; }
    if(route.ready&&s.state==8&&route.age>5000) { fprintf(stderr,"Route stalled in %04x\n",s.room); break; }
  }
  if(source)fclose(source);
  fclose(inputs); fclose(csv); sm_native_close(); remove(save);
  printf("GREEN_ROUTE_%s: room=%04x area=%d moved=%d health=%d\n",success?"OK":"INCOMPLETE",s.room,s.area,route.moved,s.health);
  return success?0:1;
}
