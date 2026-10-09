#include "host.h"
#include "sm_cpu_infra.h"
#include "sm_rtl.h"
#include "funcs.h"
#include "variables.h"
#include "util.h"
#include "spc_player.h"
#include "snes/input.h"
#include "snes/ppu.h"
#include "snes/cart.h"
#include <setjmp.h>
#include <stdio.h>
#include <string.h>

Snes *g_snes;
Cpu *g_cpu;
bool g_fail, g_use_my_apu_code = true;
bool g_debug_flag, g_is_turbo, g_other_image, g_new_ppu;
SpcPlayer *g_spc_player;
uint16 currently_installed_bug_fix_counter;
static jmp_buf failure;
static bool guarded, ready;
static char error_message[512], save_path[4096];
static uint8 raster[1024*256];
static const uint8 sprite_sizes[8][2]={{8,16},{8,32},{8,64},{16,32},{16,64},{32,64},{16,32},{16,32}};
/* Priority order from the reference's ppu.c, highest first. MIT attribution retained. */
static const uint8 raster_layers[10][12]={
 {4,0,1,4,0,1,4,2,3,4,2,3},{4,0,1,4,0,1,4,2,4,2,5,5},
 {4,0,4,1,4,0,4,1,5,5,5,5},{4,0,4,1,4,0,4,1,5,5,5,5},
 {4,0,4,1,4,0,4,1,5,5,5,5},{4,0,4,1,4,0,4,1,5,5,5,5},
 {4,0,4,4,0,4,5,5,5,5,5,5},{4,4,4,0,4,5,5,5,5,5,5,5},
 {2,4,0,1,4,0,1,4,4,2,5,5},{4,4,1,4,0,4,1,5,5,5,5,5}};
static const uint8 raster_priorities[10][12]={
 {3,1,1,2,0,0,1,1,1,0,0,0},{3,1,1,2,0,0,1,1,0,0,5,5},
 {3,1,2,1,1,0,0,0,5,5,5,5},{3,1,2,1,1,0,0,0,5,5,5,5},
 {3,1,2,1,1,0,0,0,5,5,5,5},{3,1,2,1,1,0,0,0,5,5,5,5},
 {3,1,2,1,0,0,5,5,5,5,5,5},{3,2,1,0,0,5,5,5,5,5,5,5},
 {1,3,1,1,2,0,0,1,0,0,5,5},{3,2,1,1,0,0,0,5,5,5,5,5}};
static const uint8 raster_counts[10]={12,10,8,8,8,8,6,5,10,7};
static const uint8 raster_depths[8][4]={{2,2,2,2},{4,4,2,0},{4,4,0,0},{8,4,0,0},{8,2,0,0},{4,2,0,0},{4,0,0,0},{8,7,0,0}};
static void put16(uint8 *p,uint16 v) { p[0]=v; p[1]=v>>8; }
static void capture_line(Ppu *p,int line) {
  uint8 *r=raster+(line-1)*1024;
  memset(r,0,1024);
  r[0]=p->mode; r[1]=p->bg3priority; r[2]=p->brightness; r[3]=p->forcedBlank;
  r[4]=p->m7xFlip|p->m7yFlip<<1|p->m7largeField<<2|p->m7charFill<<3|p->m7extBg<<4;
  r[5]=p->mosaicSize; r[7]=p->mosaicStartLine;
  for(int i=0;i<5;i++) {
    r[8]|=p->layer[i].mainScreenEnabled<<i; r[9]|=p->layer[i].subScreenEnabled<<i;
    r[10]|=p->layer[i].mainScreenWindowed<<i; r[11]|=p->layer[i].subScreenWindowed<<i;
  }
  r[12]=p->window1left; r[13]=p->window1right; r[14]=p->window2left; r[15]=p->window2right;
  for(int i=0;i<8;i++) put16(r+16+i*2,p->m7matrix[i]);
  for(int i=0;i<4;i++) {
    BgLayer *b=&p->bgLayer[i];
    put16(r+32+i*8,b->tilemapAdr); put16(r+34+i*8,b->tileAdr);
    put16(r+36+i*8,b->hScroll); put16(r+38+i*8,b->vScroll);
    r[64+i]=b->tilemapWider|b->tilemapHigher<<1|b->bigTiles<<2;
    r[6]|=b->mosaicEnabled<<i;
  }
  for(int i=0;i<6;i++) {
    WindowLayer *w=&p->windowLayer[i];
    r[68+i]=w->window1inversed|w->window1enabled<<1|w->window2inversed<<2|w->window2enabled<<3;
    r[74+i]=w->maskLogic; r[83]|=p->mathEnabled[i]<<i;
  }
  r[80]=p->clipMode; r[81]=p->preventMathMode;
  r[82]=p->addSubscreen|p->subtractColor<<1|p->halfColor<<2|p->directColor<<3|p->pseudoHires<<4|p->interlace<<5|p->evenFrame<<6;
  r[84]=p->fixedColorR; r[85]=p->fixedColorG; r[86]=p->fixedColorB; r[87]=p->objSize;
  put16(r+88,p->objTileAdr1); put16(r+90,p->objTileAdr2);
  r[92]=p->objPriority?(p->oamAdr&0xfe)/2:0;
  r[93]=p->objInterlace;
  memset(r+96,255,12);
  int mode=p->mode==1&&p->bg3priority?8:p->mode;
  if(p->mode==7&&p->m7extBg) mode=9;
  for(int i=0;i<raster_counts[mode];i++) {
    int layer=raster_layers[mode][i],priority=raster_priorities[mode][i],rank=raster_counts[mode]-1-i;
    r[layer==4?104+priority:96+layer*2+priority]=rank;
  }
  memcpy(r+108,raster_depths[p->mode],4);
  if(p->mode==7&&!p->m7extBg) r[109]=0;
  int found=0,tiles=0;
  for(int n=0;n<128;n++) {
    int index=(r[92]+n)&127;
    uint16 xy=p->oam[index*2];
    uint8 high=(p->highOam[index/4]>>((index&3)*2))&3;
    int size=sprite_sizes[p->objSize][high>>1];
    uint8 row=(line-1)-(xy>>8);
    if(row>=(p->objInterlace?size/2:size)) continue;
    int x=(xy&255)|((high&1)<<8); if(x>=256)x-=512;
    if(x<=-size)continue;
    if(++found>32) { p->rangeOver=true; break; }
    for(int col=0;col<size;col+=8) {
      if(col+x>-8&&col+x<256) {
        if(++tiles>34) { p->timeOver=true; break; }
        r[128+index]|=1<<(col/8);
      }
    }
    if(tiles>34)break;
  }
  memcpy(r+256,p->cgram,512);
}

void Die(const char *message) {
  snprintf(error_message, sizeof(error_message), "%s", message);
  g_fail = true;
  if (guarded) longjmp(failure, 1);
  fprintf(stderr, "Native core error: %s\n", message);
  abort();
}
void Warning(const char *message) { fprintf(stderr,"Native core warning: %s\n",message); }
void getProcessorStateSpc(Apu *apu, char *line) { strcpy(line,"SPC opcode execution unavailable"); }
void DumpCpuHistory(void) { Die("Invalid cartridge access in native routine"); }
/* The host advances gameplay/audio on one thread. No callback accesses the core. */
void RtlApuLock(void) {}
void RtlApuUnlock(void) {}
void RtlUpdateSnesPatchForBugfix(void) { currently_installed_bug_fix_counter = bug_fix_counter; }
void DebugGameOverMenu(void) { Die("Original debug menu is not supported"); }
/* The reference's only active ASM dispatch is Bang's ROM-selected native routine. */
void Call(uint32 addr) {
  switch (addr) {
    case 0xa3bb2b: Bang_Func_1(); return;
    case 0xa3bb4a: Bang_Func_2(); return;
    case 0xa3bb66: Bang_Func_3(); return;
    default: Die("Unsupported native routine dispatch");
  }
}
void RtlReadSram(void) {
  FILE *f=fopen(save_path,"rb");
  if (f) { if (fread(g_sram,1,8192,f)!=8192) memset(g_sram,0,8192); fclose(f); }
}
void RtlWriteSram(void) {
  FILE *f=fopen(save_path,"wb");
  if (f) { fwrite(g_sram,1,8192,f); fclose(f); }
}
static void native_draw_registers(void) {
  g_snes->hPos=g_snes->vPos=0;
  while (!g_snes->cpu->nmiWanted) {
    do {
      if(g_snes->disableRender&&g_snes->hPos==512&&g_snes->vPos==0) {
        Ppu *p=g_snes->ppu;
        p->mosaicStartLine=1; p->rangeOver=p->timeOver=false;
        p->evenFrame=!p->evenFrame;
      }
      if(g_snes->hPos==512&&g_snes->vPos>=1&&g_snes->vPos<=224)
        capture_line(g_snes->ppu,g_snes->vPos);
      snes_handle_pos_stuff(g_snes);
    } while (g_snes->hPos!=0);
    if (g_snes->vIrqEnabled && g_snes->vPos-1==g_snes->vTimer) Vector_IRQ();
  }
  g_snes->cpu->nmiWanted=false;
}
int sm_native_boot(const char *rom_path, const char *sram_path) {
  sm_native_close();
  error_message[0]=0; g_fail=false;
  if (strlen(sram_path)>=sizeof(save_path)) { snprintf(error_message,sizeof(error_message),"Save path too long"); return 0; }
  snprintf(save_path,sizeof(save_path),"%s",sram_path);
  guarded=true;
  if (setjmp(failure)) { guarded=false; ready=false; return 0; }
  memset(g_ram,0,sizeof(g_ram));
  memset(raster,0,sizeof(raster));
  size_t size=0; uint8 *rom=ReadWholeFile(rom_path,&size);
  if (!rom) Die("Cannot read the provided ROM");
  g_snes=snes_init(g_ram); g_cpu=g_snes->cpu;
  bool loaded=snes_loadRom(g_snes,rom,(int)size); free(rom);
  if (!loaded) Die("Cannot load the provided ROM");
  g_rom=g_snes->cart->rom; g_sram=g_snes->cart->ram;
  g_snes->ppu=g_snes->my_ppu; g_snes->disableRender=true;
  snes_reset(g_snes,true);
  memset(g_sram,0,8192);
  g_spc_player=SpcPlayer_Create(); SpcPlayer_Initialize(g_spc_player);
  RtlSetupEmuCallbacks(NULL,NULL,NULL);
  coroutine_state_0=1;
  guarded=false; ready=true;
  return 1;
}
int sm_native_tick(uint16_t joy1, int16_t *audio) {
  if (!ready) return 0;
  guarded=true;
  if (setjmp(failure)) { guarded=false; ready=false; return 0; }
  uint16 reversed=0;
  for(int i=0;i<16;i++,joy1>>=1) reversed=(reversed<<1)|(joy1&1);
  g_snes->input1->currentState=reversed;
  g_snes->runningWhichVersion=0xff;
  RunOneFrameOfGame(); native_draw_registers();
  g_snes->runningWhichVersion=0;
  RtlPushApuState(); RtlRenderAudio(audio,534,2);
  if (g_fail) Die("Native routine reported an invalid ROM access");
  guarded=false; return 1;
}
void sm_native_close(void) {
  ready=false;
  if (g_spc_player) { dsp_free(g_spc_player->dsp); free(g_spc_player); g_spc_player=NULL; }
  if (g_snes) {
    Ppu *unused=g_snes->ppu==g_snes->my_ppu?g_snes->snes_ppu:g_snes->my_ppu;
    ppu_free(unused); snes_free(g_snes); g_snes=NULL;
  }
  g_cpu=NULL; g_rom=NULL; g_sram=NULL;
}
const char *sm_native_error(void) { return error_message; }
int sm_native_raster(uint8_t *destination) {
  if(!ready)return 0;
  memcpy(destination,raster,sizeof(raster)); return 1;
}
int sm_native_snapshot(SmNativeState *s,uint8_t *vram,uint8_t *palette,uint8_t *oam) {
  if (!ready) return 0;
  memset(s,0,sizeof(*s));
  s->state=game_state; s->room=room_ptr; s->area=area_index;
  s->x=samus_x_pos; s->y=samus_y_pos; s->camera_x=layer1_x_pos; s->camera_y=layer1_y_pos; s->pose=samus_pose;
  s->health=samus_health; s->missiles=samus_missiles; s->supers=samus_super_missiles; s->power_bombs=samus_power_bombs;
  s->items=equipped_items; s->beams=equipped_beams;
  Ppu *p=g_snes->ppu;
  s->mode=p->mode; s->brightness=p->brightness; s->forced_blank=p->forcedBlank;
  s->bg3priority=p->bg3priority; s->obj_enabled=p->layer[4].mainScreenEnabled;
  memcpy(s->mode7,p->m7matrix,sizeof(s->mode7));
  s->mode7_flags=p->m7xFlip|p->m7yFlip<<1|p->m7largeField<<2|p->m7charFill<<3|p->m7extBg<<4;
  s->obj_size=p->objSize; s->obj_base1=p->objTileAdr1; s->obj_base2=p->objTileAdr2;
  for(int i=0;i<4;i++) {
    BgLayer *b=&p->bgLayer[i];
    s->bg[i].map=b->tilemapAdr; s->bg[i].tiles=b->tileAdr; s->bg[i].x=b->hScroll; s->bg[i].y=b->vScroll;
    s->bg[i].wide=b->tilemapWider; s->bg[i].high=b->tilemapHigher; s->bg[i].big=b->bigTiles; s->bg[i].enabled=p->layer[i].mainScreenEnabled;
  }
  memcpy(vram,p->vram,65536); memcpy(palette,p->cgram,512);
  memcpy(oam,p->oam,512); memcpy(oam+512,p->highOam,32);
  return 1;
}
