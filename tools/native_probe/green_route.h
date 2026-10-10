#pragma once
#include "station_route.h"
#include "green_geometry.h"

/* Ordinary-input continuation from the genuine Crateria station save. */
static const RouteLedge green_left_ledges[]={
  {464,640},{392,544},{328,528},{456,464},{360,448},
  {416,384},{328,352},{456,320},{384,256},{416,192},{320,160}
};
typedef struct {
  StationRoute station;
  uint16_t room;
  int ready,load_age,age,phase,previous_x,velocity,green_age,green_first_x,moved;
} GreenRoute;

static uint16_t green_ascent(GreenRoute *r,const SmNativeState *s) {
  BombRoute *a=&r->station.ascent;
  if(a->plan_index<a->plan.count)return a->plan.joy[a->plan_index++];
  if(a->plan.count) { a->plan.count=0; a->jump_hold=0; a->jump_release=2; a->start_y=s->y; }
  if(route_grounded(s))while(a->stage<11&&s->y+4<=green_left_ledges[a->stage].y)a->stage++;
  if(a->stage>=11) { r->phase=3; return 0; }
  if(route_grounded(s)&&(a->stage!=a->search_stage||r->age-a->search_age>120)) {
    a->search_stage=a->stage; a->search_age=r->age;
    a->plan=route_search_ledge(s,green_left_ledges[a->stage].x,green_left_ledges[a->stage].y);
    a->plan_index=0;
    if(a->plan.score>0) {
      printf("GREEN_ASCENT stage=%d ticks=%d score=%d live_core_unchanged=1\n",a->stage,a->plan.count,a->plan.score);
      return a->plan.joy[a->plan_index++];
    }
    a->plan.count=0;
  }
  a->age=r->age; a->velocity=r->velocity;
  return bomb_ascent(a,s,green_left_ledges,11);
}

static uint16_t green_route_input(GreenRoute *r,const SmNativeState *s) {
  if(!r->ready) {
    if(s->state!=8)return r->load_age++%60<2?0x1080:0;
    r->ready=1; r->load_age=0;
  }
  if(r->load_age++<400)return 0;
  if(r->room!=s->room) {
    r->room=s->room; r->age=0; r->phase=0; r->previous_x=s->x;
    r->station=(StationRoute){0}; r->station.ascent.search_stage=-1;
    r->station.ascent.start_y=s->y;
  }
  r->age++;
  r->velocity=(int)s->x-r->previous_x; r->previous_x=s->x;
  if(r->velocity>8)r->velocity=8;
  if(r->velocity< -8)r->velocity=-8;
  r->station.age=r->age;
  if(s->state!=8)return 0;
  switch(s->room) {
  case 0x93d5:return 0x100|0x40|(s->x>135&&r->age%80<49?0x80:0);
  case 0x92fd:
    if(r->phase==0) {
      if(s->movement_type!=4&&s->movement_type!=8)return station_morph(r->age,s);
      if(s->x<356)return 0x100;
      r->phase=1;
    }
    if(r->phase==1) {
      if(s->movement_type==4||s->movement_type==8)return 0x800;
      r->phase=2;
    }
    if(r->phase==2)return green_ascent(r,s);
    if(r->phase==3) {
      if(s->x>280)return 0x200;
      r->phase=4;
    }
    if(r->phase==4) {
      r->station.phase=4;
      uint16_t joy=station_wall(&r->station,s,248,0x200,5);
      if(r->station.phase==5)r->phase=5;
      return joy;
    }
    if(s->movement_type==4||s->movement_type==8)return 0x800;
    return 0x200|0x40;
  case 0x990d:return 0x8200|0x40|(r->age%80<49?0x80:0);
  case 0x99bd:
    if(s->y<1640) {
      if(s->movement_type!=4&&s->movement_type!=8)return station_morph(r->age,s);
      if(s->y_direction==0&&s->y_speed==0) {
        int row=(s->y+7)/16,best=65535,target=s->x;
        if(row<112)for(int col=2;col<14;col++)if(green_pirates_air[row]&(1<<col)) {
          int x=col*16+8,distance=abs(x-(int)s->x);
          if(distance<best) { best=distance; target=x; }
        }
        r->station.ascent.descent_target=target;
      }
      return route_towards(s->x+r->velocity*2,r->station.ascent.descent_target);
    }
    if(s->movement_type==4||s->movement_type==8)return 0x800;
    return 0x200|0x40;
  case 0x9969:return 0x8200|0x40|(r->age%80<49?0x80:0);
  case 0x9938:
    if(s->x<122||s->x>134)return route_towards(s->x+r->velocity*2,128);
    return r->age%30<2?0x400:(r->age%30>=15&&r->age%30<17?0x800:0);
  case 0x9ad9:
    if(r->green_age++==0)r->green_first_x=s->x;
    if(abs((int)s->x-r->green_first_x)>20)r->moved=1;
    return s->x<180?0x100:0;
  }
  return 0;
}
