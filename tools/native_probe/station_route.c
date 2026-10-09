#include "station_route.h"
#include <stdio.h>

static int16_t audio[1068];
int main(int argc,char **argv) {
  if(argc!=4) { fprintf(stderr,"Usage: sm_station_route ROM OUTPUT_DIRECTORY INPUT_PREFIX\n"); return 1; }
  FILE *prefix=fopen(argv[3],"rb");
  if(!prefix) { perror("Input prefix"); return 1; }
  char save[4096],input_path[4096],csv_path[4096];
  snprintf(save,sizeof(save),"%s/station.srm",argv[2]); remove(save);
  snprintf(input_path,sizeof(input_path),"%s/station.inputs",argv[2]);
  snprintf(csv_path,sizeof(csv_path),"%s/station.csv",argv[2]);
  if(!sm_native_boot(argv[1],save)) { fprintf(stderr,"%s\n",sm_native_error()); fclose(prefix); return 1; }
  FILE *inputs=fopen(input_path,"wb"),*csv=fopen(csv_path,"w");
  if(!inputs||!csv) { if(inputs)fclose(inputs); if(csv)fclose(csv); fclose(prefix); sm_native_close(); remove(save); return 1; }
  fprintf(csv,"frame,state,room,x,y,pose,health,items,missiles,capacity,selected,projectiles,kills,quota,events_low,movement_type,room_state,bosses_low,bombs,max_health,save_station,save_slot,save_writes\n");
  StationRoute route={0}; SmNativeState s; sm_native_state(&s);
  uint16_t previous_room=0; int success=0;
  for(int frame=0;frame<95000;frame++) {
    uint16_t joy=0;
    if(prefix) {
      uint8_t replay[2]; size_t count=fread(replay,1,2,prefix);
      if(count==2)joy=replay[0]|replay[1]<<8;
      else {
        fclose(prefix); prefix=NULL;
        if(count||!(s.event_flags[0]&1)||!(s.items&0x1000)||!(s.boss_flags[0]&4)) { fprintf(stderr,"Invalid Bomb Torizo input prefix\n"); break; }
        route.active=1; joy=station_route_input(&route,&s);
      }
    } else joy=station_route_input(&route,&s);
    uint8_t bytes[2]={joy&255,joy>>8}; fwrite(bytes,1,2,inputs);
    if(!sm_native_tick(joy,audio)) { fprintf(stderr,"Frame %d: %s\n",frame,sm_native_error()); break; }
    sm_native_state(&s);
    fprintf(csv,"%d,%d,%04x,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%u\n",frame+1,s.state,s.room,s.x,s.y,s.pose,s.health,s.items,s.missiles,s.missile_capacity,s.selected_item,s.active_projectiles,s.room_kills,s.room_quota,s.event_flags[0]|s.event_flags[1]<<8,s.movement_type,s.room_state,s.boss_flags[0],s.active_bombs,s.max_health,s.save_station,s.save_slot,s.save_writes);
    if(s.room!=previous_room||frame%180==0) {
      printf("STATION_FRAME %d state=%d room=%04x x=%d y=%d pose=%04x health=%d/%d items=%04x missiles=%d/5 phase=%d ledge=%d writes=%u station=%d joy=%04x\n",frame+1,s.state,s.room,s.x,s.y,s.pose,s.health,s.max_health,s.items,s.missiles,route.phase,route.ascent.stage,s.save_writes,s.save_station,joy);
      fflush(stdout); previous_room=s.room;
    }
    if(route.active&&s.state==8&&s.room==0x93d5&&s.max_health==199&&s.save_station==1&&s.save_writes>route.station_writes&&route.saved_age>200&&s.movement_type==0&&(s.pose==1||s.pose==2)) { success=1; break; }
    if(s.state>=19&&s.state<=26) { fprintf(stderr,"Samus died\n"); break; }
    if(route.active&&s.state==8&&route.age>12000) { fprintf(stderr,"Route stalled in %04x\n",s.room); break; }
  }
  if(prefix)fclose(prefix);
  fclose(inputs); fclose(csv); sm_native_close();
  if(!success)remove(save);
  printf("STATION_ROUTE_%s: tank=%d saved=%d writes=%u station=%d\n",success?"OK":"INCOMPLETE",s.max_health==199,success,s.save_writes,s.save_station);
  return success?0:1;
}
