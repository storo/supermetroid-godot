#pragma once
/* Test-only controller planning. A fork runs ordinary joypad ticks on its own
 * process copy. The live core is never restored, edited or advanced by search;
 * the parent receives only a proposed sequence of controller buttons. */
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

typedef struct { int count,score; uint16_t joy[160]; } RoutePlan;
static int route_grounded(const SmNativeState *s) {
  int m=s->movement_type;
  return (m==0||m==1||m==5||m==14||m==15||m==21)&&s->y_direction==0&&s->y_speed==0;
}
static int route_transfer(int fd,void *data,size_t size,int writing) {
  uint8_t *p=data;
  while(size) {
    ssize_t n=writing?write(fd,p,size):read(fd,p,size);
    if(n<0&&errno==EINTR)continue;
    if(n<=0)return 0;
    p+=n; size-=n;
  }
  return 1;
}
static RoutePlan route_search_ledge(const SmNativeState *start,int target_x,int target_y) {
  RoutePlan best={0};
  static const int delays[]={0,1,3,5,8};
  for(int variant=0;variant<62;variant++) {
    int pipefd[2];
    if(pipe(pipefd)!=0)continue;
    pid_t pid=fork();
    if(pid==0) {
      close(pipefd[0]);
      int nullfd=open("/dev/null",O_WRONLY);
      if(nullfd>=0) { dup2(nullfd,STDOUT_FILENO); dup2(nullfd,STDERR_FILENO); close(nullfd); }
      RoutePlan plan={0}; SmNativeState s=*start;
      int goal=target_x+(variant/20==1?-64:variant/20==2?64:0);
      int previous_x=s.x,delay=delays[variant%5],hold=(variant/5)%2?49:30,brake=variant/10?3:0;
      int prep_done=0,jump_ticks=0,edge=start->y==139&&target_y==96?442:(int)start->x-8;
      int16_t trial_audio[1068];
      for(int tick=0;tick<160;tick++) {
        int velocity=(int)s.x-previous_x; previous_x=s.x;
        uint16_t joy=0x8000|route_towards(s.x+velocity*brake,goal);
        if(tick>=delay&&tick<delay+hold)joy|=0x80;
        if(variant>=60) {
          if(!prep_done&&s.x>edge)joy=0x8200;
          else {
            prep_done=1;
            int aim=variant==60?target_x-64:(s.y>target_y-20?edge-24:target_x);
            joy=0x8000|route_towards(s.x+velocity*3,aim);
            if(jump_ticks++<49)joy|=0x80;
          }
        }
        plan.joy[plan.count++]=joy;
        if(!sm_native_tick(joy,trial_audio)||!sm_native_state(&s))break;
        if(s.state>=19&&s.state<=26)break;
        if(s.room!=start->room)break;
        if(tick>delay+8&&s.state==8&&route_grounded(&s)&&s.y+16<start->y&&s.y+4<=target_y) {
          int distance=s.x>target_x?s.x-target_x:target_x-s.x;
          int vertical=(int)s.y+21-target_y;
          if(vertical<0)vertical=-vertical;
          plan.score=100000+(start->y-s.y)*100-distance*2-vertical*5-(start->health-s.health)*20;
          break;
        }
      }
      route_transfer(pipefd[1],&plan,sizeof(plan),1);
      close(pipefd[1]); _exit(0);
    }
    close(pipefd[1]);
    RoutePlan trial={0};
    int transferred=pid>0&&route_transfer(pipefd[0],&trial,sizeof(trial),0);
    close(pipefd[0]);
    if(pid>0) { int status; while(waitpid(pid,&status,0)<0&&errno==EINTR){} }
    if(transferred&&trial.score>best.score) { best=trial; break; }
  }
  SmNativeState after;
  if(!sm_native_state(&after)||memcmp(start,&after,sizeof(after))!=0) {
    fprintf(stderr,"Lookahead modified the live core\n"); abort();
  }
  return best;
}
