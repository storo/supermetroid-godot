#include "ceres_route.h"
#include <stdio.h>
#include <stdlib.h>

static int16_t audio[1068];
int main(int argc,char **argv) {
  if(argc!=3) { fprintf(stderr,"Usage: sm_campaign_route ROM OUTPUT_DIRECTORY\n"); return 1; }
  char save[4096],trace_path[4096],log_path[4096];
  snprintf(save,sizeof(save),"%s/route.srm",argv[2]); remove(save);
  snprintf(trace_path,sizeof(trace_path),"%s/route.inputs",argv[2]);
  snprintf(log_path,sizeof(log_path),"%s/route.csv",argv[2]);
  if(!sm_native_boot(argv[1],save)) { fprintf(stderr,"%s\n",sm_native_error()); return 1; }
  FILE *inputs=fopen(trace_path,"wb"),*csv=fopen(log_path,"w");
  if(!inputs||!csv) { fprintf(stderr,"Cannot open route output\n"); sm_native_close(); return 1; }
  fprintf(csv,"frame,state,room,x,y,pose,health,ceres_status,timer_status,enemy_id,enemy_ai,enemy_x,enemy_y,y_direction,y_speed\n");
  CeresRoute route={0}; SmNativeState s; sm_native_state(&s);
  uint16_t previous_room=0; int reached_ridley=0,escape_started=0,landed=0;
  for(int frame=0;frame<60000;frame++) {
    uint16_t joy=ceres_route_input(&route,&s);
    uint8_t bytes[2]={joy&255,joy>>8}; fwrite(bytes,1,2,inputs);
    if(!sm_native_tick(joy,audio)) { fprintf(stderr,"Frame %d: %s\n",frame,sm_native_error()); break; }
    sm_native_state(&s);
    fprintf(csv,"%d,%d,%04x,%d,%d,%d,%d,%d,%d,%04x,%04x,%d,%d,%d,%d\n",frame+1,s.state,s.room,s.x,s.y,s.pose,s.health,s.ceres_phase,s.timer_phase,s.enemy0_id,s.enemy0_ai,s.enemy0_x,s.enemy0_y,s.y_direction,s.y_speed);
    if(s.room!=previous_room||frame%600==0) {
      printf("ROUTE_FRAME %d state=%d room=%04x x=%d y=%d health=%d escape=%d timer=%d enemy=%04x ai=%04x\n",frame+1,s.state,s.room,s.x,s.y,s.health,s.ceres_phase,s.timer_phase,s.enemy0_id,s.enemy0_ai);
      fflush(stdout); previous_room=s.room;
    }
    if(s.room==0xe0b5&&s.state==8)reached_ridley=1;
    if(s.ceres_phase&&s.timer_phase)escape_started=1;
    if(reached_ridley&&escape_started&&s.room==0x91f8&&s.area==0&&s.state==8&&s.brightness==15&&s.y>=800&&s.x<1130) { landed=1; break; }
    if(reached_ridley&&s.state>=19&&s.state<=26) { fprintf(stderr,"Samus died during route\n"); break; }
    if(s.state==8&&s.room!=0xe0b5&&route.room_age>3000) { fprintf(stderr,"Route stalled in room %04x\n",s.room); break; }
  }
  fclose(inputs); fclose(csv); sm_native_close(); remove(save);
  printf("CAMPAIGN_ROUTE_%s: ridley=%d escape=%d landed=%d\n",landed?"OK":"INCOMPLETE",reached_ridley,escape_started,landed);
  return landed?0:1;
}
