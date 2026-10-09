/* Register containers for the reference's DMA/PPU/DSP host. No opcode interpreter. */
#include "types.h"
#include "snes/cpu.h"
#include "snes/spc.h"
#include <string.h>
#include <stddef.h>
Cpu *cpu_init(void *mem, int type) {
  Cpu *c = calloc(1, sizeof(*c)); c->mem = mem; c->memType = type; return c;
}
void cpu_free(Cpu *c) { free(c); }
void cpu_reset(Cpu *c) {
  void *mem = c->mem; int type = c->memType;
  memset(c, 0, sizeof(*c)); c->mem = mem; c->memType = type;
  c->sp = 0x100; c->i = c->xf = c->mf = c->e = true;
}
int cpu_runOpcode(Cpu *c) { Die("CPU opcode execution is unavailable in the native core"); return 0; }
uint8_t cpu_getFlags(Cpu *c) {
  return c->n << 7 | c->v << 6 | c->mf << 5 | c->xf << 4 | c->d << 3 | c->i << 2 | c->z << 1 | c->c;
}
void cpu_setFlags(Cpu *c, uint8_t v) {
  c->n=v&128; c->v=v&64; c->mf=v&32; c->xf=v&16; c->d=v&8; c->i=v&4; c->z=v&2; c->c=v&1;
}
void cpu_saveload(Cpu *c, SaveLoadFunc *f, void *ctx) { f(ctx, &c->a, offsetof(Cpu, cyclesUsed)-offsetof(Cpu, a)); }
Spc *spc_init(Apu *a) { Spc *s=calloc(1,sizeof(*s)); s->apu=a; return s; }
void spc_free(Spc *s) { free(s); }
void spc_reset(Spc *s) { Apu *a=s->apu; memset(s,0,sizeof(*s)); s->apu=a; }
int spc_runOpcode(Spc *s) { Die("SPC opcode execution is unavailable in the native core"); return 0; }
void spc_saveload(Spc *s, SaveLoadFunc *f, void *ctx) { f(ctx,&s->a,offsetof(Spc,cyclesUsed)-offsetof(Spc,a)); }
