class_name NativeProgression
extends RefCounted

# ROM bank $8F selectors. Boss bits are scoped to the room's area.
var events: Dictionary = {}
var boss_bits: Dictionary = {}

func reset() -> void:
	events.clear()
	boss_bits.clear()

func mark_event(event_id: int) -> void:
	events[str(event_id)] = true

func has_event(event_id: int) -> bool:
	return bool(events.get(str(event_id),false))

func mark_boss(area: int, mask: int) -> void:
	boss_bits[str(area)] = int(boss_bits.get(str(area),0)) | mask

func has_boss(area: int, mask: int) -> bool:
	return (int(boss_bits.get(str(area),0)) & mask) != 0

func select_state(data: Dictionary, abilities: Dictionary, max_missiles: int) -> int:
	for check in data.get("state_checks",[]):
		var matched := false
		match str(check.kind):
			"event": matched = has_event(int(check.argument))
			"boss": matched = has_boss(int(data.area),int(check.argument))
			"main_boss": matched = has_boss(int(data.area),1)
			"morph": matched = abilities.get("morph",false)
			"morph_missiles": matched = abilities.get("morph",false) and max_missiles>0
			"power_bombs": matched = abilities.get("power_bombs",false)
			"speed": matched = abilities.get("speed",false)
		if matched: return int(check.state)
	return int(data.get("default_state",0))

func grey_door_ready(condition: int, area: int, killed: int, quota: int) -> bool:
	match condition:
		0: return has_boss(area,1)
		1: return has_boss(area,2)
		2: return has_boss(area,4)
		3:
			if killed>=quota:
				# $84:BE01 sets this event after the room's enemy death quota.
				mark_event(0)
				return true
		6: return has_event(15)
	# Conditions 4 (never) and 5 (Tourian statue animation) stay locked.
	return false

func serialize() -> Dictionary:
	return {"events":events.duplicate(),"boss_bits":boss_bits.duplicate()}

func restore(data: Dictionary) -> void:
	events = data.get("events",{}).duplicate()
	boss_bits = data.get("boss_bits",{}).duplicate()
