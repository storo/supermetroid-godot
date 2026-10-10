#pragma once
#include "green_route.h"

/* Read-only original Main Shaft air cells, rows 40..106, columns 2..13. */
static const uint16_t pink_main_geometry[]={0x3ffc,0x3ffc,0x3ffc,0x3ffc,0x3c3c,0x3c3c,0x3ffc,0x3ffc,0x3ffc,0x3fe0,0x3fe0,0x3f80,0x3fc0,0x3ff8,0x3ffc,0x3ffc,0x3fc,0xffc,0x3f3c,0x3ffc,0x3ffc,0x3ffc,0x3ffc,0x3fc0,0x3fc0,0x3ffc,0x3ffc,0x3ffc,0x1ff8,0x1e38,0x3ffc,0x3ffc,0x3ffc,0x3ffc,0x3e0,0x3e0,0x3ffc,0x3f7c,0x3ffc,0x3ffc,0x3ffc,0x3ffc,0x3e7c,0x3ffc,0x7fc,0x7fc,0x1ffc,0x1fbc,0x1ffc,0x1ffc,0x1ff0,0xef0,0xffc,0x3ffc,0x3ffc,0x3ffc,0x3c3c,0x3f3c,0x3f9c,0x3fdc,0xff8,0x1f8,0x3ffc,0x3ffc,0x3ffc,0x3ffc,0x0};
typedef struct {
  GreenRoute approach;
  uint16_t room;
  int age,phase,previous_x,velocity,target,shoot_age,enemy_slot,enemy_x,enemy_y,loot_age;
  RoutePlan drop_plan;
  int drop_planned,drop_index;
} PinkRoute;
static RoutePlan pink_search_drop(const PinkRoute *r,const SmNativeState *start);

static uint16_t pink_pirates_descent(PinkRoute *r,const SmNativeState *s) {
  if(s->y>=1640) {
    if(s->movement_type==4||s->movement_type==8)return 0x800;
    if(s->selected_item)return 0x4000;
    return 0x200|0x40;
  }
  if(s->movement_type!=4&&s->movement_type!=8)return station_morph(r->age,s);
  if(s->y_direction==0&&s->y_speed==0) {
    int row=(s->y+7)/16,best=65535;
    if(row<112)for(int col=2;col<14;) {
      if(!(green_pirates_air[row]&(1<<col))) { col++; continue; }
      int first=col; while(col<14&&(green_pirates_air[row]&(1<<col)))col++;
      int target=(first+col)*8,distance=abs(target-(int)s->x);
      if(distance<best) { best=distance; r->target=target; }
    }
  }
  return route_towards(s->x+r->velocity*2,r->target);
}

static uint16_t pink_route_input(PinkRoute *r,const SmNativeState *s) {
  if(r->room!=s->room) { r->room=s->room; r->age=0; r->phase=0; r->previous_x=s->x; r->target=s->x; }
  r->age++; r->velocity=(int)s->x-r->previous_x; r->previous_x=s->x;
  if(s->state!=8)return 0;
  switch(s->room) {
  case 0x99bd: {
    if(r->drop_index<r->drop_plan.count)return r->drop_plan.joy[r->drop_index++];
    SmNativeEnemy enemies[32]; int count=sm_native_enemies(enemies,32),target=-1,best=65535;
    for(int i=0;i<count;i++)if(enemies[i].id==0xf693&&enemies[i].health&&enemies[i].y>=s->y-48&&enemies[i].y<s->y+140) {
      int distance=abs((int)enemies[i].y-s->y);
      if(distance<best) { best=distance; target=i; }
    }
    if(r->age%30==0)for(int i=0;i<count;i++)printf("PIRATE_ENEMY slot=%d id=%04x x=%d y=%d health=%d\n",enemies[i].slot,enemies[i].id,enemies[i].x,enemies[i].y,enemies[i].health);
    if(r->phase==1) {
      target=-1;
      for(int i=0;i<count;i++)if(enemies[i].slot==r->enemy_slot&&enemies[i].id==0xf693&&enemies[i].health)target=i;
      if(target<0) { r->phase=2; r->loot_age=0; }
    } else if(r->phase==0&&target>=0&&s->missiles&&enemies[target].y<(int)s->y+72&&s->y_speed>0) {
      r->phase=1; r->enemy_slot=enemies[target].slot;
    }
    if(r->phase==1&&target>=0&&s->missiles) {
      SmNativeEnemy *e=&enemies[target];
      r->enemy_x=e->x; r->enemy_y=e->y;
      if(e->slot==4&&!r->drop_planned) {
        r->drop_planned=1; r->drop_plan=pink_search_drop(r,s); r->drop_index=0;
        printf("PINK_PICKUP_PLAN ticks=%d score=%d live_core_unchanged=1\n",r->drop_plan.count,r->drop_plan.score);
        if(r->drop_plan.score>0)return r->drop_plan.joy[r->drop_index++];
        r->drop_plan.count=0;
      }
      if(s->movement_type==4||s->movement_type==8)return 0x800;
      if(s->selected_item!=1)return r->age%30<2?0x2000:0;
      uint16_t direction=e->x<s->x?0x200:0x100;
      if(r->age%20<2)return direction;
      int dy=(int)e->y-(int)s->y;
      return (dy>20?0x20:dy< -20?0x10:0)|(abs(dy)<=48&&r->age%20>=3&&r->age%20<5?0x40:0);
    }
    if(r->phase==2) {
      if(s->movement_type==4||s->movement_type==8)return 0x800;
      if(++r->loot_age<70)return route_towards(s->x,r->enemy_x);
      r->phase=0;
    }
    return pink_pirates_descent(r,s);
  }
  case 0x9969:
  case 0x9938:return green_route_input(&r->approach,s);
  case 0x9ad9:
    if(s->pose==0)return 0x100;
    if(s->y<1620) {
      if(s->movement_type!=4&&s->movement_type!=8)return station_morph(r->age,s);
      if(s->y_direction==0&&s->y_speed==0) {
        int row=(s->y+7)/16,closest=65535,target=s->x;
        if(row>=40&&row<107)for(int col=2;col<14;) {
          if(!(pink_main_geometry[row-40]&(1<<col))) { col++; continue; }
          int first=col; while(col<14&&(pink_main_geometry[row-40]&(1<<col)))col++;
            int x=(first+col)*8,score=abs(x-(int)s->x);
            SmNativeEnemy enemies[32]; int count=sm_native_enemies(enemies,32);
            for(int i=0;i<count;i++)if(enemies[i].health&&enemies[i].y>s->y-24&&enemies[i].y<s->y+180&&abs(x-(int)enemies[i].x)<36)score+=500;
            if(score<closest) { closest=score; target=x; }
        }
        r->target=target;
      }
      SmNativeEnemy enemies[32]; int count=sm_native_enemies(enemies,32),bomb=0;
      for(int i=0;i<count;i++)if(enemies[i].id==0xdc7f&&abs((int)enemies[i].x-s->x)<60&&abs((int)enemies[i].y-s->y)<60)bomb=1;
      return route_towards(s->x+r->velocity*2,r->target)|(bomb&&r->age%20<6?0x40:0);
    }
    if(s->movement_type==4||s->movement_type==8)return 0x800;
    if(s->x<190)return 0x100;
    if(s->selected_item!=1&&s->missiles>0)return r->age%30<2?0x2000:0;
    return 0x100|(r->age%20<4?0x40:0);
  case 0x9cb3:
    if(s->selected_item)return 0x4000;
    if(s->x>912&&s->x<1060) {
      if(s->movement_type!=4&&s->movement_type!=8)return station_morph(r->age,s);
      return 0x100|(r->age%20<6?0x40:0);
    }
    if(s->movement_type==4||s->movement_type==8)return 0x800;
    return 0x8100|0x40|(r->age%80<49?0x80:0);
  case 0x9d19:return 0;
  }
  return 0;
}

static RoutePlan pink_search_drop(const PinkRoute *r,const SmNativeState *start) {
  RoutePlan best={0};
  for(int delay=0;delay<60;delay++) {
    int pipefd[2]; if(pipe(pipefd)!=0)continue;
    pid_t pid=fork();
    if(pid==0) {
      close(pipefd[0]); int fd=open("/dev/null",O_WRONLY);
      if(fd>=0) { dup2(fd,STDOUT_FILENO); dup2(fd,STDERR_FILENO); close(fd); }
      PinkRoute controller=*r; controller.drop_planned=1; controller.drop_plan.count=0;
      RoutePlan plan={0}; SmNativeState s=*start; int16_t samples[1068];
      for(int tick=0;tick<160;tick++) {
        uint16_t joy=tick<delay?0:pink_route_input(&controller,&s);
        plan.joy[plan.count++]=joy;
        if(!sm_native_tick(joy,samples)||!sm_native_state(&s)||s.room!=start->room||s.health==0)break;
        if(s.room_kills>=5&&s.missiles==s.missile_capacity&&controller.phase!=1) { plan.score=100000+s.health; break; }
      }
      route_transfer(pipefd[1],&plan,sizeof(plan),1); close(pipefd[1]); _exit(0);
    }
    close(pipefd[1]); RoutePlan trial={0}; int transferred=pid>0&&route_transfer(pipefd[0],&trial,sizeof(trial),0); close(pipefd[0]);
    if(pid>0) { int status; while(waitpid(pid,&status,0)<0&&errno==EINTR){} }
    if(transferred&&trial.score>0) { best=trial; break; }
  }
  SmNativeState after;
  if(!sm_native_state(&after)||memcmp(start,&after,sizeof(after))) { fprintf(stderr,"Drop planning changed live native state\n"); abort(); }
  return best;
}
