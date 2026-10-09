#include "awaken_route.h"
#include <stdio.h>

static int16_t audio[1068];
int main(int argc,char **argv) {
  if(argc!=3) { fprintf(stderr,"Usage: sm_awaken_route ROM OUTPUT_DIRECTORY\n"); return 1; }
  char save[4096],input_path[4096],csv_path[4096];
  snprintf(save,sizeof(save),"%s/awaken.srm",argv[2]); remove(save);
  snprintf(input_path,sizeof(input_path),"%s/awaken.inputs",argv[2]);
  snprintf(csv_path,sizeof(csv_path),"%s/awaken.csv",argv[2]);
  if(!sm_native_boot(argv[1],save)) { fprintf(stderr,"%s\n",sm_native_error()); return 1; }
  FILE *inputs=fopen(input_path,"wb"),*csv=fopen(csv_path,"w");
  if(!inputs||!csv) { if(inputs)fclose(inputs); if(csv)fclose(csv); sm_native_close(); remove(save); return 1; }
  fprintf(csv,"frame,state,room,x,y,pose,health,items,missiles,capacity,selected,projectiles,kills,quota,events_low,movement_type,room_state\n");
  AwakenRoute route={0}; SmNativeState s; sm_native_state(&s);
  uint16_t previous_room=0; int success=0;
  for(int frame=0;frame<50000;frame++) {
    uint16_t joy=awaken_route_input(&route,&s);
    uint8_t bytes[2]={joy&255,joy>>8}; fwrite(bytes,1,2,inputs);
    if(!sm_native_tick(joy,audio)) { fprintf(stderr,"Frame %d: %s\n",frame,sm_native_error()); break; }
    sm_native_state(&s);
    fprintf(csv,"%d,%d,%04x,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",frame+1,s.state,s.room,s.x,s.y,s.pose,s.health,s.items,s.missiles,s.missile_capacity,s.selected_item,s.active_projectiles,s.room_kills,s.room_quota,s.event_flags[0]|s.event_flags[1]<<8,s.movement_type,s.room_state);
    if(s.room!=previous_room||frame%300==0) {
      printf("AWAKEN_FRAME %d state=%d room=%04x/%04x x=%d y=%d pose=%04x health=%d items=%04x missiles=%d/%d kills=%d/%d events=%02x stage=%d\n",frame+1,s.state,s.room,s.room_state,s.x,s.y,s.pose,s.health,s.items,s.missiles,s.missile_capacity,s.room_kills,s.room_quota,s.event_flags[0],route.stage);
      fflush(stdout); previous_room=s.room;
      if(s.room==0x975c&&s.room_kills>=4) {
        SmNativeEnemy enemies[32]; int count=sm_native_enemies(enemies,32);
        for(int i=0;i<count;i++)printf("AWAKEN_ENEMY slot=%d id=%04x x=%d y=%d health=%d ai=%04x\n",enemies[i].slot,enemies[i].id,enemies[i].x,enemies[i].y,enemies[i].health,enemies[i].ai);
      }
    }
    if(route.active&&s.state==8&&s.room==0x975c&&(s.event_flags[0]&1)&&s.room_kills>=5) { success=1; break; }
    if(s.state>=19&&s.state<=26) { fprintf(stderr,"Samus died\n"); break; }
    if(route.active&&s.state==8&&route.age>5000) { fprintf(stderr,"Route stalled in %04x\n",s.room); break; }
  }
  fclose(inputs); fclose(csv); sm_native_close(); remove(save);
  printf("AWAKEN_ROUTE_%s: missiles=%d awake=%d\n",success?"OK":"INCOMPLETE",route.active,success);
  return success?0:1;
}
