#!/usr/bin/env python3
"""Validate NVIDIA R39's variable-length modversion_info against vendor CRCs."""
import json, pathlib, struct, subprocess, sys, tempfile
symbols={}
for line in open(sys.argv[2]):
 fields=line.split()
 if len(fields)>=2: symbols[fields[1]]=int(fields[0],16)
with tempfile.TemporaryDirectory() as t:
 path=pathlib.Path(t)/'versions'
 subprocess.run(['aarch64-linux-gnu-objcopy','--dump-section',f'__versions={path}',sys.argv[1],str(pathlib.Path(t)/'module-copy.ko')],check=True)
 data=path.read_bytes()
# NVIDIA's include/linux/module.h: packed u32 next, u32 crc, char name[].
pos=0;used=[]
while pos+8<=len(data):
 step,crc=struct.unpack_from('<II',data,pos)
 if step==0 and crc==0 and not data[pos:].strip(b'\0'):
  pos=len(data);break
 end=pos+step if step else len(data)
 if end>len(data) or (step and step<9): raise SystemExit('Invalid modversion record')
 raw=data[pos+8:end]
 if b'\0' not in raw: raise SystemExit('Unterminated symbol name')
 name=raw.split(b'\0',1)[0].decode('ascii')
 if not name or symbols.get(name)!=crc: raise SystemExit(f'Kernel symbol CRC mismatch or missing symbol: {name}')
 used.append(name)
 if not step:
  pos=len(data);break
 pos=end
# The C string initializer can append one trailing zero byte.
if not used or data[pos:].strip(b'\0'): raise SystemExit('Invalid or empty version table')
print(json.dumps({'symbol_count':len(used),'all_crcs_match':True,'format':'NVIDIA R39 u32-next/u32-crc/name'},indent=2))
