#!/usr/bin/env python3
"""Decode original enemy metadata, tile atlases and supported OAM animation frames."""
from pathlib import Path
import csv,json,re,struct
from PIL import Image
from extract_rom import ROOT,lorom,palette,tile4,scale2x,EXPECTED,decompress
import hashlib

rom=next((ROOT/'rom_src').glob('*.sfc')).read_bytes()
if len(rom)%0x8000==512: rom=rom[512:]
assert hashlib.sha256(rom).hexdigest()==EXPECTED
labels={row[1]:int(row[0],16) for row in csv.reader((ROOT/'tools/reference_disassembly/diztinguish/labels.csv').open())}
read=lambda a,n=2:int.from_bytes(rom[lorom(a):lorom(a)+n],'little')
out=ROOT/'assets/extracted/objects';out.mkdir(exist_ok=True)


def render(tile_addr,tile_size,pal_addr,maps,size=64,tile_base=0x100):
    raw=rom[lorom(tile_addr):lorom(tile_addr)+tile_size]
    colors=palette(rom[lorom(pal_addr):lorom(pal_addr)+32])
    sheet=Image.new('RGBA',(size*len(maps),size))
    for fi,sp in enumerate(maps):
        canvas=Image.new('RGBA',(size,size))
        for pi in reversed(range(read(sp))):
            p=lorom(sp+2+pi*5)
            xw,y,tw=struct.unpack('<HBH',rom[p:p+5]);x=xw&511
            if x>=256:x-=512
            if y>=128:y-=256
            big=bool(xw&0x8000);n=(tw&511)-tile_base
            obj=Image.new('RGBA',(16 if big else 8,16 if big else 8))
            for q in range(4 if big else 1):
                tn=n+(q%2)+(q//2)*16
                if tn>=0:obj.paste(tile4(raw[tn*32:tn*32+32],colors),((q%2)*8,(q//2)*8))
            if tw&0x4000:obj=obj.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            if tw&0x8000:obj=obj.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
            canvas.alpha_composite(obj,(size//2+x,size//2+y))
        sheet.paste(canvas,(fi*size,0))
    return sheet

text=(ROOT/'tools/reference_disassembly/src/bank_A0.asm').read_text()
catalog={}
for m in re.finditer(r'^EnemyHeaders_(\w+):.*?;([A-F0-9]{6});',text,re.M):
    name,a=m[1],int(m[2],16)
    size=read(a)&0x7fff;bank=read(a+12,1);pal=(bank<<16)|read(a+2);tiles=read(a+54,3)
    if size==0 or size>0x8000 or (tiles&0xffff)<0x8000:continue
    colors=palette(rom[lorom(pal):lorom(pal)+32]);raw=rom[lorom(tiles):lorom(tiles)+size]
    image=Image.new('RGBA',(128,((size//32+15)//16)*8))
    for n in range(size//32):image.paste(tile4(raw[n*32:n*32+32],colors),((n%16)*8,(n//16)*8))
    image.save(out/f'{a&65535:04X}_tiles.png')
    catalog[f'{a&65535:04X}']={'name':name,'health':read(a+4),'damage':read(a+6),'width':read(a+8),'height':read(a+10),'bank':bank,'tile_address':f'{tiles:06X}','palette_address':f'{pal:06X}','tile_bytes':size,'runtime_supported':False}

for name,header,prefix,frames in [('zoomer','DCFF','Spritemap_Crawlers_UpsideUp_FacingRight_',5),('ripper','D47F','Spritemap_Ripper_MovingRight_',3),('skree','DB7F','Spritemap_Skree_',5)]:
    record=catalog[header]
    image=render(int(record['tile_address'],16),record['tile_bytes'],int(record['palette_address'],16),[labels[prefix+str(i)] for i in range(frames)])
    image.save(out/f'{name}_original.png');scale2x(scale2x(image)).save(out/f'{name}_enhanced.png')
    record.update({'runtime_supported':True,'animation':name,'frames':frames,'frame_size':64,'ai_fidelity':'Native approximation, not exact original AI'})

# ROM instruction streams for the two grey pirate families in the early route.
# These are animation/gameplay commands, interpreted natively in GDScript, not CPU opcodes.
signed=lambda value:value-65536 if value&0x8000 else value
op_specs={
 'Instruction_Common_GotoY':('goto',1),
 'Instruction_Common_TimerInY':('timer',1),
 'Instruction_Common_DecrementTimer_GotoYIfNonZero_duplicate':('loop',1),
 'Instruction_Common_Sleep':('sleep',0),
 'Instruction_Common_WaitYFrames':('wait',1),
 'Instruction_PirateWall_FunctionInY':('function',1),
 'Instruction_PirateWalking_FunctionInY':('function',1),
 'Instruction_PirateWalking_FireLaserLeftWithYOffsetInY':('laser_left',1),
 'Instruction_PirateWalking_FireLaserRightWithYOffsetInY':('laser_right',1),
 'Instruction_PirateWalking_ChooseAMovement':('choose_walk',0),
 'Inst_PirateWall_MoveYPixelsDown_ChangeDirOnCollision_Left':('move_wall_left',1),
 'Inst_PirateWall_MoveYPixelsDown_ChangeDirOnCollision_Right':('move_wall_right',1),
 'Instruction_PirateWall_RandomlyChooseADirection_LeftWall':('choose_wall_left',0),
 'Instruction_PirateWall_RandomlyChooseADirection_RightWall':('choose_wall_right',0),
 'Instruction_PirateWall_PrepareWallJumpToLeft':('prepare_left',0),
 'Instruction_PirateWall_PrepareWallJumpToRight':('prepare_right',0),
 'Instruction_PirateWall_FireLaserLeft':('laser_left',0),
 'Instruction_PirateWall_FireLaserRight':('laser_right',0),
 'Instruction_PirateWall_QueueSpacePirateAttackSFX':('sound',0),
}
opcode_specs={labels[name]&65535:spec for name,spec in op_specs.items()}
pirates={}
for family,header,begin,end in [('pirate_walking','F653',0xfb4c,0xfc68),('pirate_wall','F353',0xecc0,0xee40)]:
 nodes={};maps=[];cursor=begin
 while cursor<end:
  address=cursor;value=read(0xb20000|cursor);cursor+=2
  if value<0x8000:
   sp=0xb20000|read(0xb20000|cursor);cursor+=2
   if sp not in maps:maps.append(sp)
   node={'op':'frame','ticks':value,'frame':maps.index(sp),'map':f'{sp:06X}'}
  else:
   if value not in opcode_specs:raise ValueError(f'Unsupported pirate instruction {value:04X} at {address:04X}')
   op,args=opcode_specs[value];node={'op':op}
   if args:node['argument']=read(0xb20000|cursor);cursor+=2
  node['next']=str(cursor);nodes[str(address)]=node
 record=catalog[header];frames=[];hitboxes=[]
 for extended in maps:
  count=read(extended);assert 1<=count<=4
  canvas=Image.new('RGBA',(96,96));boxes=[]
  for part in reversed(range(count)):
   a=extended+2+part*8;dx,dy=signed(read(a)),signed(read(a+2));sp=0xb20000|read(a+4);hp=0xb20000|read(a+6)
   layer=render(int(record['tile_address'],16),record['tile_bytes'],int(record['palette_address'],16),[sp],96)
   canvas.alpha_composite(layer,(dx,dy))
   for bi in range(read(hp)):
    box=[signed(read(hp+2+bi*12+q*2)) for q in range(4)]
    boxes.append([box[0]+dx,box[1]+dy,box[2]+dx,box[3]+dy])
  frames.append(canvas);hitboxes.append(boxes)
 sheet=Image.new('RGBA',(96*len(frames),96))
 for i,image in enumerate(frames):sheet.paste(image,(i*96,0))
 sheet.save(out/f'{family}_original.png');scale2x(scale2x(sheet)).save(out/f'{family}_enhanced.png')
 pirates[family]={'nodes':nodes,'hitboxes':hitboxes,'maps':[f'{m:06X}' for m in maps]}
 record.update({'runtime_supported':True,'animation':family,'frames':len(frames),'frame_size':96,'ai_fidelity':'ROM instruction timing and native port of grey pirate movement/attack routines; exact collision and frame parity unverified'})
pirates['sine_8bit']=list(rom[lorom(0xa0b143):lorom(0xa0b143)+128])
(out/'pirate_scripts.json').write_text(json.dumps(pirates,indent=2))
laser_maps=[labels[f'EnemyProjSpritemaps_Pirate_MotherBrain_Laser_{i:X}'] for i in range(11)]
laser=render(labels['Tiles_Standard_Sprite_0'],0x2000,labels['Initial_Palette_spritePalette5'],laser_maps,64,0)
laser.save(out/'pirate_laser_original.png');scale2x(scale2x(laser)).save(out/'pirate_laser_enhanced.png')
elevator=render(labels['Tiles_Standard_Sprite_0'],0x2000,labels['Initial_Palette_spritePalette5'],[labels[f'Spritemap_Elevator_{i}'] for i in range(2)],64,0)
elevator.save(out/'elevator_original.png');scale2x(scale2x(elevator)).save(out/'elevator_enhanced.png')
elevator_data={'header':'D73F','frame_size':64,'frames':2,'frame_ticks':read(0xa394d6),'speed':(read(0xa39595)+read(0xa3958c)/65536)*60,'samus_offset_y':read(0xa3961a),'down_transition_delay_ticks':read(0x82e18f),'source':'Local ROM bank A3:94D6-962E and 82:E18E'}
(out/'elevator.json').write_text(json.dumps(elevator_data,indent=2))
ship=Image.new('RGBA',(256,256))
for sp,dy in [('Spritemap_Ship_1',15),('Spritemap_Ship_C',-26),('Spritemap_Ship_0',-25)]:
    im=render(labels['Tiles_Ship'],0x1000,labels['Palette_Ship'],[labels[sp]],256)
    ship.alpha_composite(im,(0,dy))
ship.save(out/'ship_original.png');scale2x(scale2x(ship)).save(out/'ship_enhanced.png')
# Dynamic PLM item graphics are not ordinary room atlas tiles.
item_names=['Bombs','ChargeBeam','IceBeam','HiJumpBoots','SpeedBooster','WaveBeam','Spazer','SpringBall','VariaSuit','GravitySuit','XrayScope','PlasmaBeam','GrappleBeam','SpaceJump','ScrewAttack','MorphBall','ReserveTank']
item_dir=ROOT/'assets/extracted/items'
for tileset in range(29):
 folder=item_dir/f'{tileset:02d}';folder.mkdir(parents=True,exist_ok=True)
 table=0x8f0000|read(0x8fe7a7+tileset*2)
 colors=palette(decompress(rom,read(table+6,3)))
 for item_index,name in enumerate(item_names,4):
  addr=labels['ItemPLMGFX_'+name]
  raw=rom[lorom(addr):lorom(addr)+256]
  sheet=Image.new('RGBA',(32,16))
  for frame in range(2):
   for q in range(4):
    tile=(frame*4+q)*32
    sheet.paste(tile4(raw[tile:tile+32],colors,0),(frame*16+(q%2)*8,(q//2)*8))
  sheet.save(folder/f'{item_index:02d}_original.png')
  scale2x(scale2x(sheet)).save(folder/f'{item_index:02d}_enhanced.png')
(out/'catalog.json').write_text(json.dumps(catalog,indent=2))
(ROOT/'assets/extracted/slopes.json').write_text(json.dumps({'heights':[list(rom[lorom(0x948b2b+i*16):lorom(0x948b2b+i*16)+16]) for i in range(32)],'square':[list(rom[lorom(0x948e54+i*4):lorom(0x948e54+i*4)+4]) for i in range(5)]},indent=2))
fixed=lambda whole,sub:read(whole)+read(sub)/65536
physics={'source':'Local NTSC ROM','tick_rate':60,'gravity_air':fixed(0x909ea7,0x909ea1)*3600,'jump_air':fixed(0x909eb9,0x909ebf)*60,'jump_hi':fixed(0x909ec5,0x909ecb)*60,'jump_wall':fixed(0x909ed1,0x909ed7)*60,'bomb_jump':fixed(0x909ef5,0x909efb)*60,'dash_acceleration':fixed(0x909f01,0x909f07)*3600,'dash_extra_max':fixed(0x909f19,0x909f1f)*60,'speed_extra_max':fixed(0x909f0d,0x909f13)*60,'movement':{}}
for name,idx in [('stand',0),('run',1),('jump',2),('spin',3),('morph',4),('crouch',5),('fall',6)]:
 a=0x909f55+idx*12
 physics['movement'][name]={'acceleration':fixed(a,a+2)*3600,'max_speed':fixed(a+4,a+6)*60,'deceleration':fixed(a+8,a+10)*3600}
(ROOT/'assets/extracted/physics.json').write_text(json.dumps(physics,indent=2))
print(f'Exported {len(catalog)} enemy tile atlases; ship, 5 native enemy animation sets and pirate instruction streams.')
