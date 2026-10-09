#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include "core/host.h"
#include <cstring>
using namespace godot;

class SmNativeCore : public RefCounted {
  GDCLASS(SmNativeCore, RefCounted);
  static SmNativeCore *owner;
  String error;
  int64_t frames = 0;
  int16_t audio[1068] = {};
protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("boot", "rom_path", "sram_path"), &SmNativeCore::boot);
    ClassDB::bind_method(D_METHOD("step", "joy1"), &SmNativeCore::step);
    ClassDB::bind_method(D_METHOD("get_snapshot"), &SmNativeCore::get_snapshot);
    ClassDB::bind_method(D_METHOD("get_state"), &SmNativeCore::get_state);
    ClassDB::bind_method(D_METHOD("get_audio"), &SmNativeCore::get_audio);
    ClassDB::bind_method(D_METHOD("get_error"), &SmNativeCore::get_error);
    ClassDB::bind_method(D_METHOD("close"), &SmNativeCore::close);
  }
public:
  ~SmNativeCore() { close(); }
  bool boot(const String &rom_path, const String &sram_path) {
    if (owner && owner != this) { error="The native core already has an owner"; return false; }
    if (FileAccess::get_sha256(rom_path) != "12b77c4bc9c1832cee8881244659065ee1d84c70c3d29e6eaf92e6798cc2ca72") {
      error="The selected ROM does not match the extracted assets"; return false;
    }
    String rom = ProjectSettings::get_singleton()->globalize_path(rom_path);
    String save = ProjectSettings::get_singleton()->globalize_path(sram_path);
    CharString rom_utf8=rom.utf8(), save_utf8=save.utf8();
    if (!sm_native_boot(rom_utf8.get_data(), save_utf8.get_data())) { error=sm_native_error(); sm_native_close(); return false; }
    owner=this; frames=0; error=""; return true;
  }
  bool step(int64_t joy1) {
    if (owner != this) { error="The native core is not running"; return false; }
    if (!sm_native_tick(uint16_t(joy1),audio)) { error=sm_native_error(); return false; }
    frames++; return true;
  }
  String get_error() const { return error; }
  void close() { if (owner==this) { sm_native_close(); owner=nullptr; } }
  PackedVector2Array get_audio() const {
    PackedVector2Array result;
    if (owner != this) return result;
    result.resize(534);
    for(int i=0;i<534;i++) result.set(i,Vector2(audio[i*2]/32768.0f,audio[i*2+1]/32768.0f));
    return result;
  }
  Dictionary state_fields(const SmNativeState &s) const {
    Dictionary result;
    result["frame"]=frames; result["state"]=s.state; result["room"]=s.room; result["area"]=s.area;
    result["position"]=Vector2(s.x,s.y); result["camera"]=Vector2(s.camera_x,s.camera_y); result["pose"]=s.pose;
    result["health"]=s.health; result["missiles"]=s.missiles; result["supers"]=s.supers; result["power_bombs"]=s.power_bombs;
    result["items"]=s.items; result["beams"]=s.beams;
    result["ceres_status"]=s.ceres_phase; result["timer_status"]=s.timer_phase;
    result["timer_digits"]=Vector3(s.clock_minutes,s.clock_seconds,s.clock_centiseconds);
    result["y_direction"]=s.y_direction; result["y_speed"]=s.y_speed; result["movement_type"]=s.movement_type;
    result["enemy0_id"]=s.enemy0_id; result["enemy0_health"]=s.enemy0_health; result["enemy0_ai"]=s.enemy0_ai;
    result["enemy0_position"]=Vector2(s.enemy0_x,s.enemy0_y);
    return result;
  }
  Dictionary get_state() const {
    SmNativeState s;
    if(owner!=this||!sm_native_state(&s))return Dictionary();
    return state_fields(s);
  }
  Dictionary get_snapshot() const {
    Dictionary result;
    if (owner != this) return result;
    SmNativeState s;
    PackedByteArray vram,palette,oam,raster;
    vram.resize(65536); palette.resize(512); oam.resize(544);
    if (!sm_native_snapshot(&s,vram.ptrw(),palette.ptrw(),oam.ptrw())) return result;
    raster.resize(1024*256);
    if(!sm_native_raster(raster.ptrw()))return result;
    result=state_fields(s);
    result["mode"]=s.mode;
    result["brightness"]=s.brightness; result["forced_blank"]=bool(s.forced_blank);
    result["bg3priority"]=bool(s.bg3priority); result["obj_enabled"]=bool(s.obj_enabled);
    Array mode7;
    for(int i=0;i<8;i++) mode7.append(s.mode7[i]);
    result["mode7"]=mode7; result["mode7_flags"]=s.mode7_flags;
    result["obj_size"]=s.obj_size; result["obj_base1"]=s.obj_base1; result["obj_base2"]=s.obj_base2;
    result["vram"]=vram; result["palette"]=palette; result["oam"]=oam;
    result["raster"]=raster;
    Array backgrounds;
    for(int i=0;i<4;i++) {
      Dictionary b;
      b["map"]=s.bg[i].map; b["tiles"]=s.bg[i].tiles; b["scroll"]=Vector2(s.bg[i].x,s.bg[i].y);
      b["wide"]=bool(s.bg[i].wide); b["high"]=bool(s.bg[i].high); b["big"]=bool(s.bg[i].big); b["enabled"]=bool(s.bg[i].enabled);
      backgrounds.append(b);
    }
    result["backgrounds"]=backgrounds;
    result["cpu_opcodes"]=0; result["spc_opcodes"]=0;
    return result;
  }
};
SmNativeCore *SmNativeCore::owner=nullptr;
static void initialize(ModuleInitializationLevel level) { if(level==MODULE_INITIALIZATION_LEVEL_SCENE) GDREGISTER_CLASS(SmNativeCore); }
static void uninitialize(ModuleInitializationLevel level) {}
extern "C" GDExtensionBool GDE_EXPORT sm_native_init(GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
  GDExtensionBinding::InitObject init(get_proc,library,initialization);
  init.register_initializer(initialize); init.register_terminator(uninitialize);
  init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
  return init.init();
}
