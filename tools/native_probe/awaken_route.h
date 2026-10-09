#pragma once
#include "missile_route.h"

typedef struct {
  MissileRoute missile;
  uint16_t room;
  int active,age,stage,jump_hold,jump_release,ascent_fire_age;
} AwakenRoute;

static uint16_t awaken_ascent(AwakenRoute *r,const SmNativeState *s) {
  static const int x[]={104,48,104,48};
  static const int y[]={315,267,235,139};
  int grounded=s->y_direction==0&&s->y_speed==0;
  if(grounded&&r->stage>=2&&s->y>280) { r->stage=1; r->ascent_fire_age=0; }
  if(grounded&&r->stage<4&&s->y<=y[r->stage]+3)r->stage++;
  if(r->stage>=4)return 0x8200|0x40;
  if(r->stage==3&&grounded&&r->ascent_fire_age<90) { r->ascent_fire_age++; return 0x800|0x40; }
  if(r->stage==2&&grounded&&s->x<60)return 0x8100;
  uint16_t joy=0x8000;
  if(!grounded&&(r->stage==1||r->stage==2||s->y<=y[r->stage]+4)) {
    int target=r->stage==2&&s->y>y[r->stage]+4?84:x[r->stage];
    joy|=route_towards(s->x,target);
  }
  if(r->jump_hold) {
    joy|=0x80;
    if(--r->jump_hold==0)r->jump_release=2;
  } else if(r->jump_release)r->jump_release--;
  else if(grounded) { r->jump_hold=49; joy|=0x80; }
  return joy;
}

static uint16_t awaken_route_input(AwakenRoute *r,const SmNativeState *s) {
  if(!r->active) {
    if(r->missile.missile_fired&&s->state==8&&s->room==0xa107&&s->selected_item==0&&s->x>120)r->active=1;
    else return missile_route_input(&r->missile,s);
  }
  if(r->room!=s->room) { r->room=s->room; r->age=0; r->stage=r->jump_hold=r->jump_release=0; }
  r->age++;
  if(s->state!=8)return 0;
  switch(s->room) {
  case 0xa107:return 0x8100|0x40;
  case 0x9f11:
    if(s->y>360&&s->x<135) {
      if(s->movement_type==4||s->movement_type==8)return 0x100;
      return r->age%40<18?0x400:0;
    }
    if(s->movement_type==4||s->movement_type==8)return 0x800;
    return awaken_ascent(r,s);
  case 0x9e9f:
    if(s->x>1412) {
      uint16_t joy=0x8200|0x40;
      if(r->age%60<40)joy|=0x80;
      return joy;
    }
    if(s->x<1404)return 0x100;
    return r->age%30<2?0x800:0;
  case 0x97b5:return 0x8200|0x40;
  case 0x975c: {
    if(s->room_kills>=4&&s->room_kills<s->room_quota) {
      SmNativeEnemy enemies[32];
      int count=sm_native_enemies(enemies,32);
      for(int i=0;i<count;i++)if(enemies[i].id==0xf353||enemies[i].id==0xf653) {
        if(enemies[i].id==0xf653) {
          uint16_t joy=route_towards(s->x,enemies[i].x-64)|0x40;
          if(r->age%60<40)joy|=0x80;
          return joy;
        }
        int target=enemies[i].x-(s->y-enemies[i].y)-8;
        if(target<64)target=64;
        if(target>700)target=700;
        uint16_t joy=route_towards(s->x,target)|0x40;
        int distance=s->x>target?s->x-target:target-s->x;
        if(distance>12) {
          joy|=0x8000;
          if(r->age%60<40)joy|=0x80;
          return joy;
        }
        if(enemies[i].y+24<s->y)joy|=0x10;
        return joy;
      }
    }
    uint16_t joy=0x8200|0x40;
    if(r->age%60<40)joy|=0x80;
    return joy;
  }
  }
  return 0;
}
