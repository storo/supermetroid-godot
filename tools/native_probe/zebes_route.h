#pragma once
#include "ceres_route.h"
#include "zebes_descent.h"

/* Read-only test policy. Its only outputs are the original controller buttons. */
typedef struct {
  CeresRoute ceres;
  uint16_t room;
  int age,descent_target,jump_hold,jump_release,morph_age;
} ZebesRoute;

static uint16_t zebes_descend(ZebesRoute *route,const SmNativeState *s,const uint16_t *air,int rows,int left,int width) {
  if(s->y_direction==0&&s->y_speed==0) {
    int row=(s->y+21)/16;
    if(row<rows) {
      int closest=65535;
      for(int col=0;col<width-1;col++)if((air[row]&(3<<col))==(3<<col)) {
        int target=(left+col+1)*16;
        int distance=target>s->x?target-s->x:s->x-target;
        if(distance<closest) { closest=distance; route->descent_target=target; }
      }
    }
  }
  uint16_t joy=route_towards(s->x,route->descent_target);
  if((s->pose==0x89||s->pose==0x8a)&&!route->jump_hold&&!route->jump_release)
    route->jump_hold=40;
  if(route->jump_hold) {
    joy|=0x80;
    if(--route->jump_hold==0)route->jump_release=8;
  } else if(route->jump_release)route->jump_release--;
  return joy;
}

static uint16_t zebes_route_input(ZebesRoute *route,const SmNativeState *s) {
  if(s->room!=route->room) { route->room=s->room; route->age=0; route->descent_target=376; }
  route->age++;
  if(s->area==6||s->room==0||s->room>=0xdf45)
    return ceres_route_input(&route->ceres,s);
  if(s->state!=8)return 0;
  uint16_t joy=0;
  switch(s->room) {
  case 0x91f8: joy=0x8200|0x40; break;
  case 0x92fd:
    joy=route_towards(s->x,376)|0x8000;
    if(s->x>400&&s->y<200&&route->age%60<42)joy|=0x80;
    if(s->y>=200&&s->y<1180)joy=zebes_descend(route,s,air_92fd,80,17,14);
    if(s->y>1160)joy|=0x400|0x40;
    break;
  case 0x96ba:
    joy=s->y<2100?zebes_descend(route,s,air_96ba,144,18,12):0x100;
    joy|=0x40;
    break;
  case 0x975c:
    joy=0x8100|0x40;
    if(route->age%60<40)joy|=0x80;
    break;
  case 0x97b5:
    joy=route_towards(s->x,128);
    if(s->x>=124&&s->x<=132&&route->age%30<2)joy|=0x400;
    if(s->x>=124&&s->x<=132&&route->age%30>=15&&route->age%30<17)joy|=0x800;
    break;
  case 0x9e9f:
    if(s->items&4) {
      route->morph_age++;
      if(route->morph_age<180)joy=route->morph_age%30<2?0x80:0;
      else if(s->movement_type==4||s->movement_type==8)joy=0x100;
      else joy=route->morph_age%40<18?0x400:0;
    } else {
      joy=0x8200|0x40;
      if(route->age%60<40)joy|=0x80;
    }
    break;
  }
  return joy;
}
