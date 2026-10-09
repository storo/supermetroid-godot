#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
  uint16_t state, room, area, x, y, camera_x, camera_y, pose;
  uint16_t health, missiles, supers, power_bombs, items, beams;
  uint16_t missile_capacity, selected_item, active_projectiles, room_kills, room_quota, room_state, active_bombs;
  uint8_t event_flags[8], boss_flags[8];
  uint16_t ceres_phase, timer_phase, y_direction, y_speed, movement_type;
  uint16_t enemy0_id, enemy0_health, enemy0_ai, enemy0_x, enemy0_y;
  uint8_t clock_minutes, clock_seconds, clock_centiseconds;
  uint8_t mode, brightness, forced_blank, obj_size, bg3priority, obj_enabled;
  int16_t mode7[8];
  uint8_t mode7_flags;
  uint16_t obj_base1, obj_base2;
  struct { uint16_t map, tiles, x, y; uint8_t wide, high, big, enabled; } bg[4];
} SmNativeState;
typedef struct { uint16_t slot,id,x,y,health,properties,ai; } SmNativeEnemy;
int sm_native_boot(const char *rom_path, const char *sram_path);
int sm_native_tick(uint16_t joy1, int16_t *audio);
void sm_native_close(void);
const char *sm_native_error(void);
int sm_native_snapshot(SmNativeState *state, uint8_t *vram, uint8_t *palette, uint8_t *oam);
int sm_native_state(SmNativeState *state);
/* Optional read-only diagnostics; does not enter normal snapshot rendering. */
int sm_native_enemies(SmNativeEnemy *destination,int capacity);
/* 224 scanlines; 1024-byte rows in a 1024x256 R8 texture. See raster_layout.md. */
int sm_native_raster(uint8_t *destination);
#ifdef __cplusplus
}
#endif
