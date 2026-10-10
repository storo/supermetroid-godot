#include "pink_ascent_route.h"

static int16_t audio[1068];
int main(int argc,char **argv) {
  if(argc!=5) { fprintf(stderr,"Usage: sm_pink_ascent_route ROM OUTPUT_DIRECTORY SRAM_SEED INPUT_PREFIX\n");return 1; }
  FILE *source=fopen(argv[3],"rb");
  if(!source)return 1;
  uint8_t seed[8192];size_t size=fread(seed,1,sizeof(seed),source);int extra=fgetc(source);fclose(source);
  if(size!=sizeof(seed)||extra!=EOF)return 1;
  char save[4096],input_path[4096],csv_path[4096];
  snprintf(save,sizeof(save),"%s/ascent_XXXXXX",argv[2]);int fd=mkstemp(save);
  if(fd<0)return 1;
  FILE *copy=fdopen(fd,"wb");if(!copy) { close(fd);remove(save);return 1; }
  size_t written=fwrite(seed,1,sizeof(seed),copy);int closed=fclose(copy);
  if(written!=sizeof(seed)||closed) { remove(save);return 1; }
  source=fopen(argv[4],"rb");if(!source) { remove(save);return 1; }
  snprintf(input_path,sizeof(input_path),"%s/ascent.inputs",argv[2]);snprintf(csv_path,sizeof(csv_path),"%s/ascent.csv",argv[2]);
  if(!sm_native_boot(argv[1],save)) { fclose(source);remove(save);return 1; }
  FILE *inputs=fopen(input_path,"wb"),*csv=fopen(csv_path,"w");
  if(!inputs||!csv) { if(inputs)fclose(inputs);if(csv)fclose(csv);fclose(source);sm_native_close();remove(save);return 1; }
  fprintf(csv,"frame,state,room,x,y,pose,health,items,missiles,capacity,selected,projectiles,kills,quota,events_low,movement_type,room_state,bosses_low,bombs,max_health,save_station,save_slot,save_writes,area,supers,beams,beam_charge,charged_projectiles,time_frozen\n");
  PinkAscentRoute route={0};SmNativeState s;sm_native_state(&s);int success=0;
  for(int frame=0;frame<15000;frame++) {
    uint16_t joy=0;
    if(source) {
      uint8_t bytes[2];size_t count=fread(bytes,1,2,source);
      if(count==2)joy=bytes[0]|bytes[1]<<8;
      else {
        fclose(source);source=NULL;
        if(count||s.state!=8||s.room!=0x9d19||s.beams!=0x1000||s.items!=0x1004||s.missile_capacity!=10||s.health==0||s.y<1840) { fprintf(stderr,"Invalid Charge Beam approach\n");break; }
        route.previous_x=s.x;joy=pink_ascent_input(&route,&s);
      }
    } else joy=pink_ascent_input(&route,&s);
    uint8_t bytes[2]={joy&255,joy>>8};fwrite(bytes,1,2,inputs);
    if(!sm_native_tick(joy,audio))break;sm_native_state(&s);
    fprintf(csv,"%d,%d,%04x,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%u,%d,%d,%d,%d,%d,%d\n",frame+1,s.state,s.room,s.x,s.y,s.pose,s.health,s.items,s.missiles,s.missile_capacity,s.selected_item,s.active_projectiles,s.room_kills,s.room_quota,s.event_flags[0]|s.event_flags[1]<<8,s.movement_type,s.room_state,s.boss_flags[0],s.active_bombs,s.max_health,s.save_station,s.save_slot,s.save_writes,s.area,s.supers,s.beams,s.beam_charge,s.charged_projectiles,s.time_frozen);
    if(!source&&(route.age%15==0||s.movement_type==20)) {
      printf("ASCENT_FRAME %d x=%d y=%d movement=%d pose=%04x dir=%d speed=%d phase=%d wall_jumps=%d joy=%04x\n",frame+1,s.x,s.y,s.movement_type,s.pose,s.y_direction,s.y_speed,route.phase,route.wall_jumps,joy);fflush(stdout);
    }
    if(!source&&s.state==8&&s.room==0x9d19&&route.phase==5&&s.x<645&&s.y<1680&&route_grounded(&s)&&s.health>0&&route.wall_jumps>=3&&route.control_age>130&&abs((int)s.x-route.control_x)>16&&s.active_bombs==0) { success=1;break; }
    if(s.state>=19&&s.state<=26)break;
    if(route.age>1000)break;
  }
  if(source)fclose(source);fclose(inputs);fclose(csv);sm_native_close();remove(save);
  printf("PINK_ASCENT_ROUTE_%s: room=%04x x=%d y=%d health=%d wall_jumps=%d frames=%d\n",success?"OK":"INCOMPLETE",s.room,s.x,s.y,s.health,route.wall_jumps,route.wall_jump_frames);
  return success?0:1;
}
