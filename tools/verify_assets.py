#!/usr/bin/env python3
"""Integrity check for extracted assets. This does not assert campaign fidelity."""
from pathlib import Path
import hashlib,json
from PIL import Image
from extract_rom import ROOT,EXPECTED

rom=next((ROOT/'rom_src').glob('*.sfc')).read_bytes()
if len(rom)%0x8000==512:rom=rom[512:]
assert hashlib.sha256(rom).hexdigest()==EXPECTED,'The original ROM changed'
base=ROOT/'assets/extracted'
manifest=json.loads((base/'manifest.json').read_text())
catalog=json.loads((base/'room_catalog.json').read_text())
assert len(catalog)==manifest['room_count']==261
assert len({room['id'] for room in catalog})==len(catalog)
room_ids={room['id'] for room in catalog}
state_count=0;door_count=0;unresolved=[];predicate_count=0
for room in catalog:
 data=json.loads((base/f'rooms/{room["id"]}.json').read_text())
 assert data['width']==room['width'] and data['height']==room['height']
 assert 0<=data['default_state']<len(data['states'])
 assert data['state_checks']==room['state_checks']
 for check in data['state_checks']:
  assert 0<=check['state']<len(data['states'])
  assert check['kind'] in ['event','boss','main_boss','morph_missiles','power_bombs']
  predicate_count+=1
 for state in data['states']:
  assert len(state['blocks'])>=data['width']*data['height']
  assert len(state['blocks'])==len(state['bts'])
  assert all(0<=v<65536 for v in state['blocks'])
  assert all(0<=v<256 for v in state['bts'])
  assert 0<=state['tileset']<29
  assert 0<=state['enemy_death_quota']<=255
  state_count+=1
 for door in data['doors']:
  if door['kind']=='elevator_trigger':
   assert door['destination']=='0000' and door['address'] in ['8388FC','83A18A']
   assert 'flags' not in door and 'direction' not in door
  if int(door['destination'],16)>=0x8000 and door['destination'] not in room_ids:
   unresolved.append([room['id'],door['destination']])
  door_count+=1
assert not unresolved,unresolved
assert state_count==manifest['state_count']==322
for i in range(29):
 with Image.open(base/f'tilesets/{i:02d}_original.png') as im: assert im.size==(512,512)
 with Image.open(base/f'tilesets/{i:02d}_enhanced.png') as im: assert im.size==(2048,2048)
animations=json.loads((base/'samus/animations.json').read_text())
for name,info in animations.items():
 for suffix,scale in [('original',1),('enhanced',4)]:
  with Image.open(base/f'samus/{name}_{suffix}.png') as im:
   assert im.size==(info['frames']*64*scale,64*scale)
   assert im.getchannel('A').getextrema()==(0,255)
objects=json.loads((base/'objects/catalog.json').read_text())
assert len(objects)==154
for id in objects: assert (base/f'objects/{id}_tiles.png').exists()
pirates=json.loads((base/'objects/pirate_scripts.json').read_text())
pirate_frame_count=0;pirate_node_count=0
for family,header in [('pirate_walking','F653'),('pirate_wall','F353')]:
 info=objects[header];script=pirates[family]
 assert info['runtime_supported'] and len(script['maps'])==info['frames']==len(script['hitboxes'])
 for node in script['nodes'].values():
  if node['op']=='frame': assert 0<=node['frame']<info['frames'] and node['ticks']>0
  if node['op'] in ['goto','loop']:assert str(node['argument']) in script['nodes']
  if node['op'] not in ['goto','sleep','choose_walk','choose_wall_left','choose_wall_right']:assert node['next'] in script['nodes']
 for suffix,scale in [('original',1),('enhanced',4)]:
  with Image.open(base/f'objects/{family}_{suffix}.png') as im:
   assert im.size==(info['frames']*96*scale,96*scale)
   for frame in range(info['frames']):assert im.crop((frame*96*scale,0,(frame+1)*96*scale,96*scale)).getchannel('A').getbbox()
 pirate_frame_count+=info['frames'];pirate_node_count+=len(script['nodes'])
assert len(pirates['sine_8bit'])==128
elevator=json.loads((base/'objects/elevator.json').read_text())
assert elevator['speed']==90 and elevator['samus_offset_y']==26
assert elevator['frame_ticks']==2 and elevator['down_transition_delay_ticks']==48
for suffix,scale in [('original',1),('enhanced',4)]:
 with Image.open(base/f'objects/elevator_{suffix}.png') as im:
  assert im.size==(128*scale,64*scale) and im.getchannel('A').getbbox()
elevator_endpoints=0
for room in catalog:
 data=json.loads((base/f'rooms/{room["id"]}.json').read_text())
 for enemy in data['states'][0]['enemies']:
  if enemy['id']=='D73F':
   exits=[door for door in data['doors'] if door['kind']=='elevator']
   assert len(exits)==1
   destination=json.loads((base/f'rooms/{exits[0]["destination"]}.json').read_text())
   assert any(e['id']=='D73F' and e['x']==exits[0]['screen_x']*256+128 for e in destination['states'][0]['enemies'])
   elevator_endpoints+=1
assert elevator_endpoints==14
for tileset in range(29):
 for item in range(4,21):
  for suffix,scale in [('original',1),('enhanced',4)]:
   with Image.open(base/f'items/{tileset:02d}/{item:02d}_{suffix}.png') as im:assert im.size==(32*scale,16*scale)
slopes=json.loads((base/'slopes.json').read_text())
assert len(slopes['heights'])==32 and all(len(s)==16 for s in slopes['heights'])
physics=json.loads((base/'physics.json').read_text())
assert physics['gravity_air']==393.75 and physics['jump_air']==292.5
report={'rom_unchanged':True,'rooms':len(catalog),'room_states':state_count,'state_predicates':predicate_count,'doors':door_count,'tilesets':29,'samus_animation_sets':len(animations),'enemy_tile_atlases':len(objects),'pirate_animation_frames':pirate_frame_count,'pirate_instruction_nodes':pirate_node_count,'elevator_endpoints':elevator_endpoints,'dynamic_item_types':17,'dynamic_item_palette_variants':29,'complete_remake_verified':False,'scope':'Asset integrity and original room data only, not full runtime behavior'}
(ROOT/'docs/qa/asset_integrity.json').write_text(json.dumps(report,indent=2))
print('ASSET_INTEGRITY_OK',json.dumps(report))
