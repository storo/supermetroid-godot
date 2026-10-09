#pragma once
#include "bomb_route.h"
#include "station_geometry.h"

static const RouteLedge station_right_ledges[]={
  {920,640},{912,560},{984,544},{1000,496},{840,480},
  {920,416},{984,368},{944,288},{968,192}
};
typedef struct {
  BombRoute ascent;
  uint16_t room;
  int active,age,phase,have_tank,pad_age,saved_age,previous_x,velocity;
  uint32_t station_writes;
} StationRoute;

static uint16_t station_morph(int age,const SmNativeState *s) {
  if(s->movement_type==4||s->movement_type==8)return 0;
  return age%30<2?0x400:0;
}
static uint16_t station_wall(StationRoute *r,const SmNativeState *s,int target,int direction,int next_phase) {
  if((direction==0x200&&s->x<target-35)||(direction==0x100&&s->x>target+35)) { r->phase=next_phase; return direction; }
  if(s->movement_type!=4&&s->movement_type!=8)return station_morph(r->age,s);
  return direction|(r->age%20<6?0x40:0);
}
static uint16_t station_descend(StationRoute *r,const SmNativeState *s) {
  if(s->y>625&&s->x<313) {
    if(s->movement_type==4||s->movement_type==8)return 0x800;
    return 0x200|0x40;
  }
  if(s->movement_type!=4&&s->movement_type!=8)return station_morph(r->age,s);
  if(s->y>=660)return 0x200;
  if(s->y_direction==0&&s->y_speed==0) {
    int row=(s->y+7)/16,closest=65535,target=s->x;
    if(row<43)for(int col=0;col<15;col++)if(station_left_air[row]&(1<<col)) {
      int x=(17+col)*16+8,distance=x>s->x?x-s->x:s->x-x;
      if(distance<closest) { closest=distance; target=x; }
    }
    r->ascent.descent_target=target;
    r->ascent.start_y=s->y;
  }
  else if(s->y>=430&&s->y>r->ascent.start_y+20)r->ascent.descent_target=360;
  return route_towards(s->x+r->velocity*2,r->ascent.descent_target);
}
static uint16_t station_parlor(StationRoute *r,const SmNativeState *s) {
  if(r->have_tank) {
    if(r->phase==0) {
      if(s->x<202)return 0x8100|0x40;
      r->phase=1;
    }
    if(r->phase==1)return station_wall(r,s,224,0x100,2);
    if(r->phase==2) {
      if(s->x<390)return 0x100;
      if(s->y>200) { r->phase=3; r->ascent.descent_target=s->x; }
      else {
        if(s->movement_type!=4&&s->movement_type!=8)return station_morph(r->age,s);
        return r->age%20<6?0x40:0;
      }
    }
    return station_descend(r,s);
  }
  if(r->phase==0) {
    BombRoute *a=&r->ascent;
    if(a->plan_index<a->plan.count)return a->plan.joy[a->plan_index++];
    if(a->plan.count) { a->plan.count=0; a->jump_hold=0; a->jump_release=2; a->start_y=s->y; }
    if(route_grounded(s))while(a->stage<9&&s->y+4<=station_right_ledges[a->stage].y)a->stage++;
    if(a->stage>=9) { r->phase=1; return 0; }
    if(route_grounded(s)&&(a->stage!=a->search_stage||r->age-a->search_age>100)) {
      a->search_stage=a->stage; a->search_age=r->age;
      a->plan=route_search_ledge(s,station_right_ledges[a->stage].x,station_right_ledges[a->stage].y);
      a->plan_index=0;
      if(a->plan.score>0) {
        printf("STATION_ASCENT stage=%d ticks=%d score=%d live_core_unchanged=1\n",a->stage,a->plan.count,a->plan.score);
        return a->plan.joy[a->plan_index++];
      }
      a->plan.count=0;
    }
    a->age=r->age;
    return bomb_ascent(a,s,station_right_ledges,9);
  }
  if(r->phase==1) {
    if(s->x<1080) {
      if(s->movement_type!=4&&s->movement_type!=8)return station_morph(r->age,s);
      return 0x100|(r->age%20<6?0x40:0);
    }
    r->phase=6;
  }
  if(r->phase==6) {
    if(s->movement_type==4||s->movement_type==8)return 0x800;
    if(s->x>920)return 0x8200|0x40|(r->age%80<49?0x80:0);
    r->phase=7;
  }
  if(r->phase==7) {
    if(s->x>456)return 0x8200|0x40|(r->age%80<49?0x80:0);
    r->phase=8;
  }
  if(r->phase==8) {
    BombRoute *a=&r->ascent;
    if(a->plan_index<a->plan.count)return a->plan.joy[a->plan_index++];
    if(a->plan.count) { a->plan.count=0; r->phase=3; return 0x200; }
    if(!route_grounded(s)||s->x<448||s->x>464)return route_towards(s->x,456);
    if(r->age-a->search_age>100) {
      a->search_age=r->age;
      a->plan=route_search_jump(s,320,176,1); a->plan_index=0;
      if(a->plan.score>0) {
        printf("STATION_GAP ticks=%d score=%d live_core_unchanged=1\n",a->plan.count,a->plan.score);
        return a->plan.joy[a->plan_index++];
      }
      a->plan.count=0;
    }
    return 0;
  }
  if(r->phase==3) {
    if(s->x>280)return 0x200;
    r->phase=4;
  }
  if(r->phase==4)return station_wall(r,s,248,0x200,5);
  if(s->movement_type==4||s->movement_type==8)return 0x800;
  return 0x200|0x40;
}
static uint16_t station_route_input(StationRoute *r,const SmNativeState *s) {
  if(r->room!=s->room) {
    r->room=s->room; r->age=0; r->phase=0;
    r->ascent=(BombRoute){0}; r->ascent.search_stage=-1; r->ascent.start_y=s->y;
    r->previous_x=s->x;
    if(s->room==0x92fd&&s->max_health<199&&s->x<400&&s->y<180)r->phase=3;
    if(s->room==0x92fd&&s->max_health>=199&&s->x>330&&s->y>200) { r->phase=3; r->ascent.descent_target=s->x; }
    if(s->room==0x93d5)r->station_writes=s->save_writes;
  }
  r->age++;
  r->velocity=(int)s->x-r->previous_x; r->previous_x=s->x;
  if(r->velocity>8)r->velocity=8;
  if(r->velocity< -8)r->velocity=-8;
  r->ascent.velocity=r->velocity;
  if(s->max_health>=199)r->have_tank=1;
  if(s->state!=8)return 0;
  switch(s->room) {
  case 0x9804:
    if(s->active_bombs||s->movement_type==15||s->movement_type==4||s->movement_type==8)return 0x800;
    if(r->phase==0) {
      if(s->x<208)return 0x8100;
      r->phase=1;
    }
    return 0x8200|0x40|(r->age%80<49?0x80:0);
  case 0x9879:return 0x8200|0x40|(r->age%80<49?0x80:0);
  case 0x92fd:return station_parlor(r,s);
  case 0x990d:
    if(!r->have_tank) {
      if(s->x>220)return 0x8200|0x40|(r->age%80<49?0x80:0);
      return route_towards(s->x+r->velocity*3,120)|0x40;
    }
    if(++r->pad_age<420)return r->pad_age%30<2?0x80:0;
    return 0x8100|0x40|(r->age%80<49?0x80:0);
  case 0x93d5:
    if(s->movement_type==4||s->movement_type==8)return 0x800;
    if(s->save_writes>r->station_writes) {
      r->saved_age++;
      if(s->x>=120)return 0;
      return (r->saved_age>=240?0x100:0)|(r->saved_age%30<2?0x80:0);
    }
    if(s->x>90)return 0x200|(s->x<128&&r->age%80<49?0x80:0);
    if(s->x<88)return 0x100;
    r->pad_age++;
    if(r->pad_age<20)return 0;
    return r->pad_age%60<14?0x80:0;
  }
  return 0;
}
