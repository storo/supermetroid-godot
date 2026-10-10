#pragma once
#include "pink_route.h"

typedef struct {
  PinkRoute approach;
  int age,phase,previous_x,velocity,shoot_age,saw_full_charge,saw_charged_shot;
} ChargeRoute;

static uint16_t charge_route_input(ChargeRoute *r,const SmNativeState *s) {
  if(s->room!=0x9d19)return pink_route_input(&r->approach,s);
  r->age++;r->velocity=(int)s->x-r->previous_x;r->previous_x=s->x;
  if(s->state!=8||s->time_frozen)return r->age%60<2?0x80:0;
  if(s->beams&0x1000) {
    if(s->movement_type==4||s->movement_type==8) {
      if(s->x<620)return 0x100;
      return r->age%30<2?0x800:0;
    }
    r->phase=1;
    if(s->beam_charge>=60)r->saw_full_charge=1;
    if(s->charged_projectiles)r->saw_charged_shot=1;
    r->shoot_age++;
    return r->shoot_age<3?0x100:r->shoot_age<163?0x40:0;
  }
  if(s->movement_type!=4&&s->movement_type!=8)return station_morph(r->age,s);
  int target=s->y<850?952:s->y<950?920:s->y<1460?952:s->y<1590?592:552;
  if(s->missile_capacity>=10) {
    if(r->phase==0&&s->x>687)r->phase=2;
    target=s->y>=1760?600:s->y>1720?716:r->phase==2?744:696;
  }
  int projected=s->x+r->velocity*2;
  uint16_t joy=projected<target-1?0x100:projected>target+1?0x200:0;
  SmNativeEnemy enemies[32];int count=sm_native_enemies(enemies,32);
  for(int i=0;i<count;i++)if(abs((int)enemies[i].x-s->x)<70&&abs((int)enemies[i].y-s->y)<70&&enemies[i].id!=0xf193&&r->age%20<6)joy|=0x40;
  if(s->missile_capacity>=10&&s->x>675&&s->y<1760&&r->age%20<6)joy|=0x40;
  if(s->missile_capacity>=10&&s->y>=1840&&r->age%20<6)joy|=0x40;
  return joy;
}
