#include "missile_route.h"
#include <stdio.h>

static int16_t audio[1068];
int main(int argc,char **argv) {
  if(argc!=3) { fprintf(stderr,"Usage: sm_missile_route ROM OUTPUT_DIRECTORY\n"); return 1; }
  char save[4096],input_path[4096],csv_path[4096];
  snprintf(save,sizeof(save),"%s/missile.srm",argv[2]); remove(save);
  snprintf(input_path,sizeof(input_path),"%s/missile.inputs",argv[2]);
  snprintf(csv_path,sizeof(csv_path),"%s/missile.csv",argv[2]);
  if(!sm_native_boot(argv[1],save)) { fprintf(stderr,"%s\n",sm_native_error()); return 1; }
  FILE *inputs=fopen(input_path,"wb"),*csv=fopen(csv_path,"w");
  if(!inputs||!csv) { if(inputs)fclose(inputs); if(csv)fclose(csv); sm_native_close(); remove(save); return 1; }
  fprintf(csv,"frame,state,room,x,y,pose,health,items,missiles,capacity,selected,projectiles,kills,quota,events_low,movement_type\n");
  MissileRoute route={0}; SmNativeState s; sm_native_state(&s);
  uint16_t previous_room=0; int success=0;
  for(int frame=0;frame<45000;frame++) {
    uint16_t joy=missile_route_input(&route,&s);
    uint8_t bytes[2]={joy&255,joy>>8}; fwrite(bytes,1,2,inputs);
    if(!sm_native_tick(joy,audio)) { fprintf(stderr,"Frame %d: %s\n",frame,sm_native_error()); break; }
    sm_native_state(&s);
    fprintf(csv,"%d,%d,%04x,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",frame+1,s.state,s.room,s.x,s.y,s.pose,s.health,s.items,s.missiles,s.missile_capacity,s.selected_item,s.active_projectiles,s.room_kills,s.room_quota,s.event_flags[0]|s.event_flags[1]<<8,s.movement_type);
    if(s.room!=previous_room||frame%600==0) {
      printf("MISSILE_FRAME %d state=%d room=%04x x=%d y=%d pose=%04x health=%d items=%04x missiles=%d/%d selected=%d kills=%d/%d events=%02x stage=%d\n",frame+1,s.state,s.room,s.x,s.y,s.pose,s.health,s.items,s.missiles,s.missile_capacity,s.selected_item,s.room_kills,s.room_quota,s.event_flags[0],route.stage);
      fflush(stdout); previous_room=s.room;
    }
    if(route.missile_fired&&s.state==8&&s.room==0xa107&&s.selected_item==0&&s.x>120) { success=1; break; }
    if(s.state>=19&&s.state<=26) { fprintf(stderr,"Samus died\n"); break; }
    if(route.active&&s.state==8&&route.age>4000) { fprintf(stderr,"Route stalled in %04x\n",s.room); break; }
  }
  fclose(inputs); fclose(csv); sm_native_close(); remove(save);
  printf("MISSILE_ROUTE_%s: morph=%d fired=%d\n",success?"OK":"INCOMPLETE",route.active,route.missile_fired);
  return success?0:1;
}
