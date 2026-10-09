#include "bomb_route.h"
#include <stdio.h>

static int16_t audio[1068];
int main(int argc,char **argv) {
  if(argc!=3&&argc!=4) { fprintf(stderr,"Usage: sm_bomb_route ROM OUTPUT_DIRECTORY [INPUT_PREFIX]\n"); return 1; }
  FILE *prefix=argc==4?fopen(argv[3],"rb"):NULL;
  if(argc==4&&!prefix) { perror("Input prefix"); return 1; }
  char save[4096],input_path[4096],csv_path[4096];
  snprintf(save,sizeof(save),"%s/bomb.srm",argv[2]); remove(save);
  snprintf(input_path,sizeof(input_path),"%s/bomb.inputs",argv[2]);
  snprintf(csv_path,sizeof(csv_path),"%s/bomb.csv",argv[2]);
  if(!sm_native_boot(argv[1],save)) { fprintf(stderr,"%s\n",sm_native_error()); return 1; }
  FILE *inputs=fopen(input_path,"wb"),*csv=fopen(csv_path,"w");
  if(!inputs||!csv) { if(inputs)fclose(inputs); if(csv)fclose(csv); sm_native_close(); remove(save); return 1; }
  fprintf(csv,"frame,state,room,x,y,pose,health,items,missiles,capacity,selected,projectiles,kills,quota,events_low,movement_type,room_state,bosses_low,bombs\n");
  BombRoute route={0}; SmNativeState s; sm_native_state(&s);
  uint16_t previous_room=0; int success=0,previous_stage=-1;
  for(int frame=0;frame<70000;frame++) {
    uint16_t joy=prefix?0:bomb_route_input(&route,&s);
    if(prefix) {
      uint8_t replay[2]; size_t count=fread(replay,1,2,prefix);
      if(count==2)joy=replay[0]|replay[1]<<8;
      else {
        fclose(prefix); prefix=NULL;
        if(count||!(s.event_flags[0]&1)||!(s.items&4)||s.missile_capacity!=5) {
          fprintf(stderr,"Invalid awake-Zebes input prefix\n"); break;
        }
        route=(BombRoute){0}; route.active=1;
        joy=bomb_route_input(&route,&s);
      }
    }
    uint8_t bytes[2]={joy&255,joy>>8}; fwrite(bytes,1,2,inputs);
    if(!sm_native_tick(joy,audio)) { fprintf(stderr,"Frame %d: %s\n",frame,sm_native_error()); break; }
    sm_native_state(&s);
    if(route.active&&route.stage!=previous_stage) {
      printf("BOMB_STAGE frame=%d room=%04x stage=%d x=%d y=%d movement=%d yd=%d ys=%d\n",frame+1,s.room,route.stage,s.x,s.y,s.movement_type,s.y_direction,s.y_speed);
      previous_stage=route.stage;
    }
    fprintf(csv,"%d,%d,%04x,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",frame+1,s.state,s.room,s.x,s.y,s.pose,s.health,s.items,s.missiles,s.missile_capacity,s.selected_item,s.active_projectiles,s.room_kills,s.room_quota,s.event_flags[0]|s.event_flags[1]<<8,s.movement_type,s.room_state,s.boss_flags[0],s.active_bombs);
    if(s.room!=previous_room||frame%180==0) {
      printf("BOMB_FRAME %d state=%d room=%04x/%04x x=%d y=%d pose=%04x health=%d items=%04x missiles=%d/%d kills=%d/%d events=%02x boss=%02x stage=%d joy=%04x\n",frame+1,s.state,s.room,s.room_state,s.x,s.y,s.pose,s.health,s.items,s.missiles,s.missile_capacity,s.room_kills,s.room_quota,s.event_flags[0],s.boss_flags[0],route.stage,joy);
      fflush(stdout); previous_room=s.room;
      if(s.room==0x9804||s.room==0x9879) {
        SmNativeEnemy enemies[32]; int count=sm_native_enemies(enemies,32);
        for(int i=0;i<count;i++)printf("BOMB_ENEMY slot=%d id=%04x x=%d y=%d health=%d ai=%04x\n",enemies[i].slot,enemies[i].id,enemies[i].x,enemies[i].y,enemies[i].health,enemies[i].ai);
      }
    }
    if(route.active&&route.bomb_seen&&s.state==8&&s.room==0x9804&&(s.items&0x1000)&&(s.boss_flags[0]&4)&&s.movement_type==0&&route_grounded(&s)&&s.active_bombs==0) { success=1; break; }
    if(s.state>=19&&s.state<=26) { fprintf(stderr,"Samus died\n"); break; }
    if(!prefix&&route.active&&s.state==8&&route.age>12000) { fprintf(stderr,"Route stalled in %04x\n",s.room); break; }
  }
  if(prefix)fclose(prefix);
  fclose(inputs); fclose(csv); sm_native_close(); remove(save);
  printf("BOMB_ROUTE_%s: awake=%d bombs=%d boss=%d\n",success?"OK":"INCOMPLETE",route.active,(s.items&0x1000)!=0,(s.boss_flags[0]&4)!=0);
  return success?0:1;
}
