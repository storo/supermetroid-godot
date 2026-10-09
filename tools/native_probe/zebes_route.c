#include "zebes_route.h"
#include <stdio.h>
#include <stdlib.h>

static int16_t audio[1068];
int main(int argc,char **argv) {
  if(argc!=3) { fprintf(stderr,"Usage: sm_zebes_route ROM OUTPUT_DIRECTORY\n"); return 1; }
  char save[4096],input_path[4096],csv_path[4096];
  snprintf(save,sizeof(save),"%s/zebes.srm",argv[2]); remove(save);
  snprintf(input_path,sizeof(input_path),"%s/zebes.inputs",argv[2]);
  snprintf(csv_path,sizeof(csv_path),"%s/zebes.csv",argv[2]);
  if(!sm_native_boot(argv[1],save)) { fprintf(stderr,"%s\n",sm_native_error()); return 1; }
  FILE *inputs=fopen(input_path,"wb"),*csv=fopen(csv_path,"w");
  if(!inputs||!csv) { fprintf(stderr,"Cannot open route output\n"); sm_native_close(); return 1; }
  fprintf(csv,"frame,state,room,x,y,pose,health,items,missiles,y_direction,y_speed,movement_type\n");
  ZebesRoute route={0}; SmNativeState s; sm_native_state(&s);
  uint16_t previous_room=0; int acquired=0;
  for(int frame=0;frame<40000;frame++) {
    uint16_t joy=zebes_route_input(&route,&s);
    uint8_t bytes[2]={joy&255,joy>>8}; fwrite(bytes,1,2,inputs);
    if(!sm_native_tick(joy,audio)) { fprintf(stderr,"Frame %d: %s\n",frame,sm_native_error()); break; }
    sm_native_state(&s);
    fprintf(csv,"%d,%d,%04x,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",frame+1,s.state,s.room,s.x,s.y,s.pose,s.health,s.items,s.missiles,s.y_direction,s.y_speed,s.movement_type);
    if(s.room!=previous_room||frame%600==0) {
      printf("ZEBES_FRAME %d state=%d room=%04x x=%d y=%d pose=%04x health=%d items=%04x missiles=%d dir=%d speed=%d\n",frame+1,s.state,s.room,s.x,s.y,s.pose,s.health,s.items,s.missiles,s.y_direction,s.y_speed);
      fflush(stdout); previous_room=s.room;
    }
    if(s.state==8&&s.room==0x9e9f&&(s.items&4)&&s.movement_type==4&&s.x>1160&&s.y>=680) { acquired=1; break; }
    if(s.state==8&&s.area!=6&&route.age>3500) { fprintf(stderr,"Route stalled in room %04x\n",s.room); break; }
    if(s.state>=19&&s.state<=26) { fprintf(stderr,"Samus died during route\n"); break; }
  }
  fclose(inputs); fclose(csv); sm_native_close(); remove(save);
  printf("ZEBES_ROUTE_%s: morph_ball=%d rolling=%d\n",acquired?"OK":"INCOMPLETE",acquired,acquired);
  return acquired?0:1;
}
