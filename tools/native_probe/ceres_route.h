#pragma once
#include "host.h"
#include <string.h>

/* Test controller only: every action is a normal joypad input, never a RAM write. */
typedef struct {
  int frame,room_age;
  int shaft_stage,jump_hold,jump_release;
  uint16_t previous_room;
} CeresRoute;

static uint16_t route_towards(int x,int target) { return x>target+4?0x200:x<target-4?0x100:0; }
static uint16_t ceres_route_input(CeresRoute *route,const SmNativeState *s) {
  if(route->previous_room!=s->room) {
    route->previous_room=s->room; route->room_age=0;
    route->shaft_stage=route->jump_hold=route->jump_release=0;
  }
  route->room_age++; route->frame++;
  if(s->state!=8) return s->area==6?0:(route->frame%60<2?0x1080:0);
  if(s->area==0&&s->room==0x91f8)return 0x200|0x8000;
  uint16_t joy=0;
  if(s->ceres_phase==1)return 0; /* Let the original getaway cutscene finish. */
  int returning=s->ceres_phase>=2;
  if(!returning) {
    switch(s->room) {
    case 0xdf45: {
      int target=s->y<160?184:s->y<260?128:s->y<350?64:s->y<445?128:184;
      joy=s->y>=540?0x100:route_towards(s->x,target);
      break;
    }
    case 0xdf8d:
      joy=0x100|0x8000;
      if(s->x>140&&s->x<380&&route->room_age%60<30)joy|=0x80;
      break;
    case 0xe021: case 0xe06b: joy=0x100|0x8000; break;
    case 0xdfd7: joy=s->y<175?route_towards(s->x,208):s->y<335?route_towards(s->x,48):0x100; break;
    case 0xe0b5:
      joy=route_towards(s->x,160);
      if(route->room_age%30<5)joy|=0x40;
      break;
    }
  } else {
    switch(s->room) {
    case 0xe0b5:
      if(s->y<=145&&s->y_direction==0)joy=0x200|0x8000;
      else {
        joy=route_towards(s->x,40);
        if(s->y>145&&route->room_age%60<30)joy|=0x80;
      }
      break;
    case 0xe06b: case 0xe021: joy=0x200|0x8000; break;
    case 0xdf8d:
      joy=0x200|0x8000;
      if(s->x>140&&s->x<380&&route->room_age%60<30)joy|=0x80;
      break;
    case 0xdfd7:
      joy=s->y>280?route_towards(s->x,48):s->y>=140?route_towards(s->x,208):0x200;
      if(s->y>=140&&route->room_age%48<30)joy|=0x80;
      joy|=0x8000;
      break;
    case 0xdf45: {
      static const int targets[8]={224,80,128,64,184,128,184,128};
      static const int standing_y[8]={651,571,475,379,363,267,171,75};
      int grounded=s->y_direction==0&&s->y_speed==0;
      if(grounded&&s->y>655)route->shaft_stage=0;
      if(grounded&&route->shaft_stage<8&&s->y<=standing_y[route->shaft_stage]+4)
        route->shaft_stage++;
      if(route->shaft_stage>=8) { joy=route_towards(s->x,128); break; }
      int stage=route->shaft_stage;
      if(!grounded&&(stage==0||stage==4||s->y<=standing_y[stage]+4))
        joy=route_towards(s->x,targets[stage]);
      joy|=0x8000;
      if(route->jump_hold>0) {
        joy|=0x80;
        if(--route->jump_hold==0)route->jump_release=2;
      } else if(route->jump_release>0)route->jump_release--;
      else if(grounded) { route->jump_hold=49; joy|=0x80; }
      break;
    }
    }
  }
  return joy;
}
