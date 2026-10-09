#pragma once
#include "zebes_route.h"

/* Extends the fresh-game route using only normal SNES controller inputs. */
typedef struct {
  ZebesRoute zebes;
  uint16_t room;
  int active,age,stage,shoot_age,pickup_age,missile_fired;
} MissileRoute;

static uint16_t missile_route_input(MissileRoute *route,const SmNativeState *s) {
  if(!route->active) {
    if(s->state==8&&s->room==0x9e9f&&(s->items&4)&&s->movement_type==4&&s->x>1160&&s->y>=680)
      route->active=1;
    else return zebes_route_input(&route->zebes,s);
  }
  if(s->room!=route->room) { route->room=s->room; route->age=0; }
  route->age++;
  if(s->state!=8)return 0;
  uint16_t joy=0;
  switch(s->room) {
  case 0x9e9f:
    if(route->stage==0&&s->x>=1205)route->stage=1;
    if(route->stage==0)joy=0x100;
    else if(route->stage==1) {
      if(!route->shoot_age&&(s->movement_type==4||s->movement_type==8))joy=0x800;
      else {
        route->shoot_age++;
        if(route->shoot_age<=50)joy=0x400|0x40;
        else if(route->shoot_age>54) {
          joy=0x400;
          if(s->movement_type==4||s->movement_type==8)route->stage=2;
        }
      }
    } else if(route->stage==2&&s->x<1295)joy=0x100;
    else if(s->movement_type==4||s->movement_type==8)joy=0x800;
    else {
      joy=0x8100|0x40;
      if(route->age%60<40)joy|=0x80;
    }
    break;
  case 0x9f11:
    if(s->y<350) {
      joy=(s->x<135?0x100:s->x>137?0x200:0)|0x40;
      if(route->age%60<40)joy|=0x80;
      if(s->y_direction)joy|=0x400;
    } else if(s->x>70) {
      if(s->movement_type==4||s->movement_type==8)joy=0x200;
      else joy=route->age%40<18?0x400:0;
    } else if(s->movement_type==4||s->movement_type==8)joy=0x800;
    else joy=0x8200|0x40;
    break;
  case 0xa107:
    if(s->missile_capacity==0) {
      joy=0x8200|0x40;
      if(route->age%60<40)joy|=0x80;
    } else {
      route->pickup_age++;
      if(route->pickup_age<420)joy=route->pickup_age%30<2?0x80:0;
      else if(!route->missile_fired) {
        if(s->selected_item!=1)joy=route->pickup_age%30<2?0x2000:0;
        else { joy=0x40; if(s->missiles<s->missile_capacity)route->missile_fired=1; }
      } else joy=0x100|0x4000;
    }
    break;
  }
  return joy;
}
