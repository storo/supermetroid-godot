#include "sm_cpu_infra.h"
#include "sm_rtl.h"
#include "funcs.h"
#include "variables.h"
#include "spc_player.h"
#include "snes/input.h"
#include "snes/ppu.h"
#include <stdio.h>

bool g_debug_flag, g_is_turbo, g_other_image, g_new_ppu;
int g_got_mismatch_count;
SpcPlayer *g_spc_player;
extern uint8 g_runmode;
void DrawFrameToPpu(void);

void Die(const char *s) { fprintf(stderr, "NATIVE_PROBE_ERROR %s\n", s); exit(1); }
void Warning(const char *s) { fprintf(stderr, "NATIVE_PROBE_WARNING %s\n", s); }
/* Single-threaded diagnostic, with no SDL audio callback. */
void RtlApuLock(void) {}
void RtlApuUnlock(void) {}

int main(int argc, char **argv) {
  if (argc != 2) Die("Expected local ROM path");
  if (!SnesInit(argv[1])) Die("ROM initialization failed");
  g_runmode = 1; /* RM_MINE: compiled C gameplay only. */
  g_snes->ppu = g_snes->my_ppu;
  g_snes->disableRender = true;
  g_spc_player = SpcPlayer_Create();
  SpcPlayer_Initialize(g_spc_player);
  snes_reset(g_snes, true);
  coroutine_state_0 = 1;
  uint64 seen_states = 0;
  int playing_frames = 0;
  int moving_frames = 0, projectile_frames = 0, audible_frames = 0;
  uint16 previous_x = 0;
  bool reached_ceres = false;
  int16 audio[534 * 2];
  for (int frame = 0; frame < 18000; frame++) {
    /* Start/A to skip intro and choose first file. Release between presses. */
    uint16 input = frame % 60 < 2 ? 0x0108 : 0;
    /* Device input order is reversed relative to the game's JOY1 bitmask. */
    if (game_state == 8) {
      playing_frames++;
      input = playing_frames % 240 < 120 ? 0x0080 : 0x0040;
      if (playing_frames % 90 < 20) input |= 0x0100;
      if (playing_frames % 30 < 5) input |= 0x0200;
    }
    g_snes->input1->currentState = input;
    g_snes->runningWhichVersion = 0xff;
    RunOneFrameOfGame();
    DrawFrameToPpu();
    g_snes->runningWhichVersion = 0;
    RtlPushApuState();
    RtlRenderAudio(audio, 534, 2);
    for (int sample = 0; sample < 534 * 2; sample++) {
      if (audio[sample]) { audible_frames++; break; }
    }
    if (game_state == 8) {
      if (samus_x_pos != previous_x) moving_frames++;
      if (projectile_counter) projectile_frames++;
      if (room_ptr == 0xdf45) reached_ceres = true;
      previous_x = samus_x_pos;
    }
    if (game_state < 64) seen_states |= (uint64)1 << game_state;
    if (frame % 300 == 0)
      printf("NATIVE_FRAME %d state=%u cinematic=%04x room=%04x samus=%u,%u\n", frame, game_state, cinematic_function, room_ptr, samus_x_pos, samus_y_pos);
    if (g_fail || g_ram[0x1ffff]) Die("Native reference reported an invalid ROM access");
  }
  if (playing_frames < 300) Die("Did not reach 300 gameplay frames");
  printf("NATIVE_EVIDENCE ceres=%u moving=%d projectile=%d audible=%d\n", reached_ceres, moving_frames, projectile_frames, audible_frames);
  if (!reached_ceres || moving_frames < 60 || projectile_frames < 60 || audible_frames < 60)
    Die("Missing Ceres movement, projectile or native audio evidence");
  printf("NATIVE_PROBE_OK frames=18000 gameplay_frames=%d moving_frames=%d projectile_frames=%d audible_frames=%d states=%016llx final_state=%u room=%04x cpu_opcodes=0 spc_opcodes=0 campaign_verified=false\n", playing_frames, moving_frames, projectile_frames, audible_frames, (unsigned long long)seen_states, game_state, room_ptr);
  dsp_free(g_spc_player->dsp);
  free(g_spc_player);
  /* snes_free owns the selected PPU; free the unused comparison PPU here. */
  ppu_free(g_snes->snes_ppu);
  snes_free(g_snes);
  return 0;
}
