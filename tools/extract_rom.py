#!/usr/bin/env python3
"""Export local NTSC Super Metroid ROM data for the native Godot project.
Address names are read from the annotated disassembly, never executable code.
"""
from pathlib import Path
import argparse, hashlib, json, re, struct
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = '12b77c4bc9c1832cee8881244659065ee1d84c70c3d29e6eaf92e6798cc2ca72'


def lorom(address):
    return ((address & 0x7f0000) >> 1) | (address & 0x7fff)


def decompress(rom, address):
    pos = lorom(address)
    out = bytearray()
    def take(n=1):
        nonlocal pos
        v = rom[pos:pos+n]
        if len(v) != n: raise ValueError('Truncated compressed stream')
        pos += n
        return v
    for _ in range(65536):
        h = take()[0]
        if h == 0xff: return bytes(out)
        cmd, size = h >> 5, (h & 31) + 1
        if cmd == 7:
            cmd, size = (h >> 2) & 7, (((h & 3) << 8) | take()[0]) + 1
        if cmd == 0: out.extend(take(size))
        elif cmd == 1: out.extend(take() * size)
        elif cmd == 2:
            pair = take(2)
            out.extend((pair * ((size+1)//2))[:size])
        elif cmd == 3:
            start = take()[0]
            out.extend((start+i) & 255 for i in range(size))
        else:
            src = int.from_bytes(take(2), 'little') if cmd < 6 else len(out)-take()[0]
            xor = 255 if cmd in (5,7) else 0
            for i in range(size):
                if not 0 <= src+i < len(out): raise ValueError('Invalid dictionary offset')
                out.append(out[src+i] ^ xor)
        if len(out) > 1024*1024: raise ValueError('Decompression bound exceeded')
    raise ValueError('Unterminated compressed stream')


def palette(raw):
    colors = []
    for (v,) in struct.iter_unpack('<H', raw):
        colors.append(tuple(((v >> shift) & 31)*255//31 for shift in (0,5,10))+(255,))
    return colors


def tile4(raw, colors, pal=0):
    img = Image.new('RGBA', (8,8))
    if len(raw) < 32: return img
    for y in range(8):
        for x in range(8):
            bit = 7-x
            index = sum(((raw[(plane//2)*16+y*2+plane%2] >> bit)&1)<<plane for plane in range(4))
            if index: img.putpixel((x,y), colors[(pal*16+index)%len(colors)])
    return img


def scale2x(image):
    """Edge-aware enlargement; never blends adjacent atlas cells."""
    e = np.array(image)
    p = np.pad(e, ((1,1),(1,1),(0,0)), mode='edge')
    b,d,f,h = p[:-2,1:-1],p[1:-1,:-2],p[1:-1,2:],p[2:,1:-1]
    eq = lambda a,b: np.all(a==b,axis=2)
    test = (~eq(b,h)) & (~eq(d,f))
    out = np.empty((e.shape[0]*2,e.shape[1]*2,4),dtype=np.uint8)
    for yy,xx,a,c in [(0,0,d,b),(0,1,b,f),(1,0,d,h),(1,1,h,f)]:
        out[yy::2,xx::2] = np.where((test & eq(a,c))[...,None],a,e)
    return Image.fromarray(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rom',type=Path,default=next((ROOT/'rom_src').glob('*.sfc'),None))
    args = parser.parse_args()
    if args.rom is None: parser.error('Place your ROM in rom_src or use --rom')
    rom = args.rom.read_bytes()
    if len(rom)%0x8000 == 512: rom = rom[512:]
    digest = hashlib.sha256(rom).hexdigest()
    if digest != EXPECTED: parser.error('Unsupported ROM: expected unmodified NTSC Japan/USA Super Metroid')
    def read(addr,n=2): return int.from_bytes(rom[lorom(addr):lorom(addr)+n],'little')
    out = ROOT/'assets'/'extracted'
    for part in ['tilesets','samus','rooms','references']: (out/part).mkdir(parents=True,exist_ok=True)
    source = ROOT/'tools/reference_disassembly/src/bank_8F.asm'
    if not source.exists(): parser.error('Run tools/setup_reference.sh first')
    text = source.read_text()
    cre_tiles = decompress(rom,0xb98000)
    cre_table = decompress(rom,0xb9a09d)
    atlases = {}
    for index in range(29):
        ptr = 0x8f0000 | read(0x8fe7a7+index*2)
        table_ptr,tiles_ptr,pal_ptr = [read(ptr+i,3) for i in (0,3,6)]
        if (out/f'tilesets/{index:02d}_enhanced.png').exists():
            atlases[index] = Image.open(out/f'tilesets/{index:02d}_original.png').convert('RGBA')
            continue
        table = decompress(rom,table_ptr)
        tiles = bytearray(0x8000)
        tiles[0x5000:0x5000+len(cre_tiles)] = cre_tiles
        specific = decompress(rom,tiles_ptr)
        tiles[:len(specific)] = specific
        colors = palette(decompress(rom,pal_ptr))
        if index not in range(15,21): table = cre_table + table
        atlas = Image.new('RGBA',(512,512))
        atlas_hd = Image.new('RGBA',(2048,2048))
        for tile_id in range(min(1024,len(table)//8)):
            meta = Image.new('RGBA',(16,16))
            for quadrant in range(4):
                word = int.from_bytes(table[tile_id*8+quadrant*2:tile_id*8+quadrant*2+2],'little')
                n,pal = word&1023,(word>>10)&7
                cell = tile4(tiles[n*32:n*32+32],colors,pal)
                if word&0x4000: cell = cell.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                if word&0x8000: cell = cell.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
                meta.paste(cell,((quadrant%2)*8,(quadrant//2)*8))
            atlas.paste(meta,((tile_id%32)*16,(tile_id//32)*16))
            atlas_hd.paste(scale2x(scale2x(meta)),((tile_id%32)*64,(tile_id//32)*64))
        atlas.save(out/f'tilesets/{index:02d}_original.png')
        atlas_hd.save(out/f'tilesets/{index:02d}_enhanced.png')
        atlases[index] = atlas
    headers = list(re.finditer(r'^RoomHeader_(\w+):.*?;([0-9A-F]{6});',text,re.M))
    catalog = []
    all_states = 0
    for hi,match in enumerate(headers):
        name,addr = match[1],int(match[2],16)
        section = text[match.end():headers[hi+1].start() if hi+1<len(headers) else len(text)]
        states = list(re.finditer(r'^RoomState_'+re.escape(name)+r'(?:_\d+)?:.*?;([0-9A-F]{6});',section,re.M))
        if not states: continue
        off = lorom(addr)
        area,mx,my,w,h = rom[off+1:off+6]
        if not (1<=w<=16 and 1<=h<=16): continue
        entry = {'id':f'{addr&65535:04X}','name':name,'area':area,'map_x':mx,'map_y':my,'width':w*16,'height':h*16,'states':[],'doors':[]}
        # Decode the original ordered state checks from ROM, not source macros.
        state_indices = {int(sm[1],16)&65535:i for i,sm in enumerate(states)}
        selectors = {0xe5ff:'main_boss',0xe612:'event',0xe629:'boss',0xe640:'morph',0xe652:'morph_missiles',0xe669:'power_bombs',0xe678:'speed'}
        cursor = addr+11
        entry['state_checks'] = []
        for _ in range(16):
            selector = read(cursor)
            cursor += 2
            if selector == 0xe5e6:
                entry['default_state'] = state_indices[cursor&65535]
                break
            if selector not in selectors: raise ValueError(f'Unknown state selector {selector:04X} in {name}')
            argument = read(cursor,1) if selector in (0xe612,0xe629) else 0
            if selector in (0xe612,0xe629): cursor += 1
            target = read(cursor)
            cursor += 2
            entry['state_checks'].append({'kind':selectors[selector],'argument':argument,'state':state_indices[target],'selector':f'{selector:04X}'})
        else: raise ValueError(f'Unterminated state checks in {name}')
        door_match = re.search(r'^RoomDoors_'+re.escape(name)+r':\n(.*?)(?=\n\n)',section,re.M|re.S)
        count = len(re.findall(r'^\s+dw ',door_match[1],re.M)) if door_match else 0
        door_list = 0x8f0000 | read(addr+9)
        for di in range(count):
            daddr = 0x830000 | read(door_list+di*2)
            dp = lorom(daddr)
            if read(daddr)==0:
                # $83:88FC/$83:A18A are two-byte virtual elevator triggers, not full doors.
                entry['doors'].append({'index':di,'destination':'0000','kind':'elevator_trigger','address':f'{daddr:06X}'})
                continue
            entry['doors'].append({'index':di,'destination':f'{read(daddr):04X}','kind':'elevator' if rom[dp+2]&0x80 else 'normal','address':f'{daddr:06X}','flags':rom[dp+2],'direction':rom[dp+3],'cap_x':rom[dp+4],'cap_y':rom[dp+5],'screen_x':rom[dp+6],'screen_y':rom[dp+7],'distance':read(daddr+8),'asm':f'{read(daddr+10):04X}'})
        for si,sm in enumerate(states):
            state_addr = int(sm[1],16)
            raw = decompress(rom,read(state_addr,3))
            size = int.from_bytes(raw[:2],'little')
            if size//2 < w*h*256: raise ValueError(f'Room dimension mismatch: {name}')
            layer = list(struct.unpack(f'<{size//2}H',raw[2:2+size]))
            bts = list(raw[2+size:2+size+size//2])
            plm_addr = 0x8f0000 | read(state_addr+20)
            plms = []
            for pi in range(512):
                p = lorom(plm_addr+pi*6)
                code = int.from_bytes(rom[p:p+2],'little')
                if code==0: break
                plms.append({'id':f'{code:04X}','x':rom[p+2],'y':rom[p+3],'argument':int.from_bytes(rom[p+4:p+6],'little')})
            enemy_addr = 0xa10000 | read(state_addr+8)
            enemies = []
            for ei in range(256):
                p = lorom(enemy_addr+ei*16)
                words = struct.unpack('<8H',rom[p:p+16])
                if words[0]==65535:
                    enemy_death_quota = rom[p+2]
                    break
                enemies.append({'id':f'{words[0]:04X}','x':words[1],'y':words[2],'init':words[3],'properties':words[4],'extra':words[5],'parameter1':words[6],'parameter2':words[7]})
            state = {'address':f'{state_addr:06X}','tileset':read(state_addr+3,1),'blocks':layer,'bts':bts,'plms':plms,'enemies':enemies,'enemy_death_quota':enemy_death_quota,'asm':{'main':f'{read(state_addr+18):04X}','setup':f'{read(state_addr+24):04X}'}}
            if len(raw)>2+size*3//2:
                bg = raw[2+size*3//2:]
                state['background'] = list(struct.unpack(f'<{len(bg)//2}H',bg[:len(bg)//2*2]))
            entry['states'].append(state)
            all_states += 1
        (out/f'rooms/{entry["id"]}.json').write_text(json.dumps(entry,separators=(',',':')))
        catalog.append({k:v for k,v in entry.items() if k!='states'})
        if name=='LandingSite':
            preview = Image.new('RGBA',(w*256,h*256),(5,8,18,255))
            for i,word in enumerate(entry['states'][0]['blocks']):
                n = word&1023
                tile = atlases[0].crop(((n%32)*16,(n//32)*16,(n%32)*16+16,(n//32)*16+16))
                if word&0x400: tile=tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                if word&0x800: tile=tile.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
                preview.alpha_composite(tile,((i%(w*16))*16,(i//(w*16))*16))
            preview.save(out/'references/landing_site_original.png')
            preview.crop((768,896,1536,1280)).resize((1536,768),Image.Resampling.NEAREST).save(out/'references/crateria_reference.png')
    (out/'room_catalog.json').write_text(json.dumps(catalog,indent=2))
    # Reconstruct Samus graphics via the original DMA definitions and OAM spritemaps.
    colors = palette(rom[lorom(0x9b9400):lorom(0x9b9400)+32])
    poses = {'idle':(1,4),'run':(9,10),'jump':(0x4d,3),'spin':(0x19,8),'crouch':(0x27,3),'morph':(0x1d,8),'aim_up':(3,2),'aim_diagonal':(5,1),'fall':(0x29,3)}
    poses.update({'idle_left':(2,4),'run_left':(10,10),'jump_left':(0x4e,3),'spin_left':(0x1a,8),'crouch_left':(0x28,3),'morph_left':(0x41,8),'aim_up_left':(4,2),'aim_diagonal_left':(6,1),'fall_left':(0x2a,3)})
    poses['front']=(0,1)
    frame_catalog = {}
    for animation,(pose,frames) in poses.items():
        sheet = Image.new('RGBA',(64*frames,64))
        vram = bytearray(0x4000)
        for frame in range(frames):
            ap = 0x920000 | read(0x92d94e+pose*2)
            p=lorom(ap+frame*4)
            defs=rom[p:p+4]
            for half,(table,base) in enumerate([(0x92d91e,0),(0x92d938,0x100)]):
                idx,sub = defs[half*2:half*2+2]
                if idx==255: continue
                dp = (0x920000 | read(table+idx*2))+sub*7
                src,n,m = read(dp,3),read(dp+3),read(dp+5)
                off=lorom(src)
                vram[base:base+n] = rom[off:off+n]
                vram[base+0x200:base+0x200+m] = rom[off+n:off+n+m]
            canvas = Image.new('RGBA',(64,64))
            for table in (0x92945d,0x929263):
                index=read(table+pose*2)+frame
                sp = 0x920000 | read(0x92808d+index*2)
                if sp == 0x920000: continue
                count=read(sp)
                if count>64: raise ValueError(f'Invalid Samus spritemap {animation} frame {frame} table {table:06X} index {index:X} sp {sp:06X} count {count}')
                for piece in reversed(range(count)):
                    pp = lorom(sp+2+piece*5)
                    xword,y,tword=struct.unpack('<HBH',rom[pp:pp+5])
                    x=xword&511
                    if x>=256: x-=512
                    if y>=128: y-=256
                    big=bool(xword&0x8000)
                    n=tword&511
                    obj=Image.new('RGBA',(16 if big else 8,16 if big else 8))
                    for q in range(4 if big else 1):
                        tn=n+(q%2)+(q//2)*16
                        obj.paste(tile4(vram[tn*32:tn*32+32],colors),((q%2)*8,(q//2)*8))
                    if tword&0x4000: obj=obj.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                    if tword&0x8000: obj=obj.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
                    canvas.alpha_composite(obj,(32+x,32+y))
            sheet.paste(canvas,(frame*64,0))
        sheet.save(out/f'samus/{animation}_original.png')
        scale2x(scale2x(sheet)).save(out/f'samus/{animation}_enhanced.png')
        frame_catalog[animation]={'frames':frames,'pose':pose,'size':64,'anchor':[32,32]}
    (out/'samus/animations.json').write_text(json.dumps(frame_catalog,indent=2))
    # A clean reference contact sheet for art replacement, drawn from the ROM.
    ref=Image.new('RGBA',(768,256),(0,0,0,0))
    for j,(anim,frame) in enumerate([('idle',0),('run',0),('run',2),('run',4),('run',6),('run',8),('jump',0),('spin',2),('crouch',0),('morph',0),('aim_up',0),('aim_diagonal',0)]):
        im=Image.open(out/f'samus/{anim}_original.png').crop((frame*64,0,frame*64+64,64)).resize((128,128),Image.Resampling.NEAREST)
        ref.paste(im,((j%6)*128,(j//6)*128))
    ref.save(out/'references/samus_reference.png')
    manifest={'rom_sha256':digest,'rom_modified':False,'room_count':len(catalog),'state_count':all_states,'tileset_count':29,'animations':frame_catalog,'source':'Local ROM; address labels from InsaneFirebat/sm_disassembly','enhancement':'Per-tile Scale2x twice (4x); replacement art is separate','unsupported_runtime':['65816 room ASM','enemy AI','scripted PLM logic','SPC music','bosses and narrative events']}
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2))
    print(f'Extracted {len(catalog)} rooms, {all_states} states, 29 tilesets and {len(poses)} Samus animations.')

if __name__=='__main__': main()
