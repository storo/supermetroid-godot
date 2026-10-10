#pragma once
#include "charge_route.h"

/* Ordinary-button return from the native Charge Beam alcove. */
typedef struct {
  int age,phase,previous_x,velocity,stalled,kick_age,wall_jump_frames,wall_jumps,previous_movement,settle,control_age,control_x;
} PinkAscentRoute;

static uint16_t pink_ascent_input(PinkAscentRoute *r,const SmNativeState *s) {
  r->age++; r->velocity=(int)s->x-r->previous_x; r->previous_x=s->x;
  if(s->state!=8||s->time_frozen)return r->age%60<2?0x80:0;
  if(r->phase==0) {
    if(s->movement_type==4||s->movement_type==8)return r->age%30<2?0x800:0;
    if(s->x<699)return 0x100;
    if(++r->settle<10)return 0;
    r->phase=1;
  }
  if(s->movement_type==20) { r->wall_jump_frames++;if(r->previous_movement!=20)r->wall_jumps++; }
  r->previous_movement=s->movement_type;
  if(r->phase==1&&s->y<1680)r->phase=2;
  if(r->phase==2) {
    if(route_grounded(s))r->phase=3;
    else return route_towards(s->x+r->velocity*2,716)|0x80;
  }
  if(r->phase==3) {
    if(s->movement_type!=4&&s->movement_type!=8)return station_morph(r->age,s);
    if(s->x<668)r->phase=4;
    else return route_towards(s->x+r->velocity*2,660)|(r->age%20<6?0x40:0);
  }
  if(r->phase==4) {
    if(s->movement_type==4||s->movement_type==8)return r->age%30<2?0x800:0;
    r->phase=5;r->control_x=s->x;
  }
  if(r->phase==5) { r->control_age++;return route_towards(s->x+r->velocity*2,640); }
  if(s->y<1740)return route_towards(s->x+r->velocity*2,744)|(r->age%60<40?0x80:0);
  if(r->kick_age) {
    int age=r->kick_age++;
    if(age<=2)return 0x200;
    if(age<=4)return 0x200|0x80;
    r->kick_age=0;r->stalled=0;
    return 0x100|0x80;
  }
  if((s->movement_type==3||s->movement_type==20)&&r->velocity==0)r->stalled++;
  else r->stalled=0;
  if(r->stalled>=3) { r->kick_age=1;return 0x200; }
  if(route_grounded(s))return r->age%60<2?0x100:0x100|0x80;
  return 0x100|0x80;
}
