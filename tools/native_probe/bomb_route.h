#pragma once
#include "awaken_route.h"
#include "parlor_return.h"
#include "route_lookahead.h"

typedef struct { int x,y,approach; } RouteLedge;
/* Standing targets from the extracted awake Climb platforms, not game writes. */
static const RouteLedge climb_ledges[]={
  {424,2144},{456,2080},{360,2032},{400,1968},{424,1920},
  {440,1856,426},{400,1824},{360,1776},{400,1712},{424,1664},{456,1600},
  {400,1568},{360,1520},{400,1456},{424,1408},{456,1344},
  {400,1312},{360,1264},{400,1200},{424,1152},{456,1088},
  {400,1056},{360,1008},{400,944},{424,896},{456,832},
  {400,800},{360,752},{400,688},{424,640},{456,576},
  {400,544},{360,496},{400,432},{424,384},{456,320},
  {384,288,445},{432,224},{448,160,422},{464,96,438}
};
static const RouteLedge parlor_ledges[]={
  {376,1216},{384,1136},{456,1088},{384,1040},{448,960},
  {384,880},{376,816},{432,752},{376,672},{440,640},
  {392,544},{440,464},{352,448},{416,384},{328,352},
  {384,256},{448,176}
};
typedef struct {
  AwakenRoute awaken;
  uint16_t room;
  int active,age,stage,phase,end_age,descent_target,bomb_age,jump_hold,jump_release,start_y,start_x,previous_x,velocity;
  RoutePlan plan;
  int plan_index,search_age,search_stage;
} BombRoute;

static uint16_t bomb_ascent(BombRoute *r,const SmNativeState *s,const RouteLedge *ledges,int count) {
  int grounded=(s->movement_type==0||s->movement_type==1||s->movement_type==5||s->movement_type==14||s->movement_type==15||s->movement_type==21)&&s->y_direction==0&&s->y_speed==0;
  if(grounded) {
    int previous_stage=r->stage;
    while(r->stage<count&&s->y<=ledges[r->stage].y-4)r->stage++;
    if(s->y>r->start_y+24 && !(r->stage>=count&&r->phase>0&&s->y<150)) {
      r->stage=0;
      while(r->stage<count&&s->y<=ledges[r->stage].y-4)r->stage++;
    }
    if(previous_stage!=r->stage) { r->jump_hold=0; r->jump_release=2; r->start_y=s->y; r->end_age=0; r->phase=0; }
  }
  if(r->stage>=count) {
    r->end_age++;
    if(r->phase==0) {
      if(s->x<=396)r->phase=1;
      else {
        if(r->end_age<3)return 0;
        if(r->end_age<6)return 0x8200;
        return 0x8200|(r->end_age<55?0x80:0);
      }
    }
    if(r->phase==2)return 0x800|0x40|(r->end_age%80>=10&&r->end_age%80<60?0x80:0);
    if(!grounded)return route_towards(s->x+r->velocity*3,376)|(r->end_age<55?0x80:0);
    if(s->x<374)return 0x100;
    if(s->x>378)return 0x200;
    if(r->phase==1) { r->phase=2; r->end_age=0; }
    return 0x800|0x40;
  }
  const RouteLedge *ledge=&ledges[r->stage];
  if(grounded && ledge->approach && (s->x<ledge->approach-1||s->x>ledge->approach+1))
    return (s->x<ledge->approach?0x100:0x200)|0x40;
  if(grounded && !ledge->approach && s->x>ledge->x-32 && s->x<ledge->x+32)
    return route_towards(s->x,ledge->x+(s->x<=ledge->x?-36:36))|0x8000|0x40;
  uint16_t joy=0x8000|0x40;
  if(!grounded) {
    int target=s->y<=ledge->y-20?ledge->x:ledge->x+(r->start_x>ledge->x?32:-32);
    joy|=route_towards(s->x+r->velocity*3,target);
  }
  if(r->jump_hold) { joy|=0x80; if(--r->jump_hold==0)r->jump_release=2; }
  else if(r->jump_release)r->jump_release--;
  else if(grounded) {
    r->jump_hold=49; r->start_y=s->y; r->start_x=s->x; joy|=0x80;
    if(s->room_quota>0&&s->room_kills>=s->room_quota)joy|=route_towards(s->x,ledge->x);
  }
  return joy;
}

static uint16_t bomb_aim(uint16_t joy,const SmNativeState *s) {
  if(!(joy&0x40))return joy;
  SmNativeEnemy enemies[32];
  int count=sm_native_enemies(enemies,32),distance=65535,dy=0;
  for(int i=0;i<count;i++)if(enemies[i].id==0xf353) {
    int dx=(int)enemies[i].x-s->x,y=(int)enemies[i].y-s->y+8;
    int d=(dx<0?-dx:dx)+(y<0?-y:y);
    if(d<distance) { distance=d; dy=y; }
  }
  if(distance<160) {
    if(dy< -14)joy|=0x10;
    else if(dy>14)joy|=0x20;
  }
  return joy;
}

static uint16_t bomb_parlor(BombRoute *r,const SmNativeState *s) {
  if(r->plan_index<r->plan.count)return r->plan.joy[r->plan_index++];
  if(r->plan.count) { r->plan.count=0; r->jump_hold=0; r->jump_release=2; r->start_y=s->y; }
  if(r->phase==0&&r->stage<17) {
    uint16_t joy=bomb_ascent(r,s,parlor_ledges,17);
    if(r->stage<17&&route_grounded(s)&&(r->stage!=r->search_stage||r->age-r->search_age>100)) {
      r->search_age=r->age; r->search_stage=r->stage;
      r->plan=route_search_ledge(s,parlor_ledges[r->stage].x,parlor_ledges[r->stage].y);
      r->plan_index=0;
      if(r->plan.score>0) {
        printf("PARLOR_LOOKAHEAD stage=%d input_ticks=%d score=%d live_core_unchanged=1\n",r->stage,r->plan.count,r->plan.score);
        return r->plan.joy[r->plan_index++];
      }
      r->plan.count=0;
    }
    return joy;
  }
  if(r->phase==0) {
    if(s->x<780)return 0x8100|0x40|(r->age%60<40?0x80:0);
    if(s->movement_type!=4&&s->movement_type!=8)return r->age%40<18?0x400:0;
    if(s->x<838)return 0x100;
    r->phase=1; r->descent_target=840;
  }
  if(s->y>=600) {
    if(s->movement_type==4||s->movement_type==8)return 0x800;
    return 0x8100|0x40|(r->age%60<40?0x80:0);
  }
  if(s->y_direction==0&&s->y_speed==0) {
    int row=(s->y+(s->movement_type==4?9:21))/16;
    if(row<43) {
      int closest=65535;
      for(int col=0;col<15;col++)if(parlor_return_air[row]&(1<<col)) {
        int target=(49+col)*16+8;
        int distance=target>s->x?target-s->x:s->x-target;
        if(distance<closest) { closest=distance; r->descent_target=target; }
      }
    }
  }
  return s->x<r->descent_target-1?0x100:s->x>r->descent_target+1?0x200:0;
}

static uint16_t bomb_flyway(BombRoute *r,const SmNativeState *s) {
  if(r->phase==0) {
    if(s->x>640)r->phase=s->health>=80?2:1;
    return 0x8100|0x40|(r->age%60<40?0x80:0);
  }
  if(r->phase==1) {
    if(s->x<220)r->phase=0;
    return 0x8200|0x40|(r->age%60<40?0x80:0);
  }
  if(s->x<710)return 0x8100|0x40|(r->age%60<40?0x80:0);
  if(s->selected_item!=1&&s->missiles>0)return r->age%30<2?0x2000:0;
  return 0x100|0x40;
}

static uint16_t bomb_torizo(BombRoute *r,const SmNativeState *s) {
  if(!(s->items&0x1000))return 0x8100|0x40|(r->age%60<40?0x80:0);
  r->bomb_age++;
  if(r->bomb_age<420)return r->bomb_age%30<2?0x80:0;
  if(s->selected_item!=0)return 0x4000;
  if(s->x>80)return 0x8200|0x40;
  return 0x100|0x40|(r->age%60<40?0x80:0);
}

static uint16_t bomb_route_input(BombRoute *r,const SmNativeState *s) {
  if(!r->active) {
    if(s->state==8&&s->room==0x975c&&(s->event_flags[0]&1)&&s->room_kills>=5)r->active=1;
    else return awaken_route_input(&r->awaken,s);
  }
  if(r->room!=s->room) { r->room=s->room; r->age=0; r->stage=r->phase=r->jump_hold=r->jump_release=0; r->start_y=s->y; r->previous_x=s->x; r->plan.count=0; r->plan_index=0; r->search_stage=-1; }
  r->velocity=s->x-r->previous_x;
  if(r->velocity>8)r->velocity=8;
  if(r->velocity< -8)r->velocity=-8;
  r->previous_x=s->x;
  r->age++;
  if(s->state!=8)return 0;
  switch(s->room) {
  case 0x975c:return 0x8200|0x40|(r->age%60<40?0x80:0);
  case 0x96ba: {
    if(r->plan_index<r->plan.count)return r->plan.joy[r->plan_index++];
    if(r->plan.count) { r->plan.count=0; r->jump_hold=0; r->jump_release=2; r->start_y=s->y; }
    if(r->stage>=36&&r->stage<(int)(sizeof(climb_ledges)/sizeof(climb_ledges[0]))&&route_grounded(s)&&(r->stage!=r->search_stage||r->age-r->search_age>100)) {
      r->search_age=r->age;
      r->search_stage=r->stage;
      r->plan=route_search_ledge(s,climb_ledges[r->stage].x,climb_ledges[r->stage].y);
      r->plan_index=0;
      if(r->plan.count&&r->plan.score>0) {
        printf("BOMB_LOOKAHEAD stage=%d input_ticks=%d score=%d live_core_unchanged=1\n",r->stage,r->plan.count,r->plan.score);
        return r->plan.joy[r->plan_index++];
      }
      r->plan.count=0;
    }
    uint16_t joy=bomb_ascent(r,s,climb_ledges,sizeof(climb_ledges)/sizeof(climb_ledges[0]));
    if(s->room_kills>=s->room_quota&&s->room_quota>0&&r->stage<(int)(sizeof(climb_ledges)/sizeof(climb_ledges[0])))return joy&~0x40;
    return bomb_aim(joy,s);
  }
  case 0x92fd:return bomb_parlor(r,s);
  case 0x9879:return bomb_flyway(r,s);
  case 0x9804:return bomb_torizo(r,s);
  }
  return 0;
}
