#!/usr/bin/env python3
"""Prepare an OPTIONAL whole-tree PCIe experiment from an explicitly selected DTB."""
import argparse, hashlib, json, pathlib, re, shutil, subprocess
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--base',required=True,type=pathlib.Path,help='matching complete board DTB, including required board overlays')
p.add_argument('--extlinux',required=True,type=pathlib.Path)
p.add_argument('--output',required=True,type=pathlib.Path)
a=p.parse_args(); a.output.mkdir(parents=True,exist_ok=False)
source=pathlib.Path(__file__).resolve().parent/'pci0-clock-request.dts'
shutil.copyfile(source,a.output/source.name)
base=a.output/'base-original.dtb'; shutil.copyfile(a.base,base)
merged=a.output/'pcie-c0-no-power-down.dtb';shutil.copyfile(base,merged)
def run(*args): return subprocess.check_output(list(map(str,args)),text=True).strip()
def nodes(n='/'):
 yield n
 for c in run('fdtget','-l',merged,n).splitlines(): yield from nodes(n.rstrip('/')+'/'+c)
def props(n):return run('fdtget','-p',merged,n).splitlines()
removed=[]
for n in list(nodes()):
 if 'nvidia,enable-power-down' in props(n):
  run('fdtput','-d',merged,n,'nvidia,enable-power-down');removed.append(n)
overlay=a.output/'pci0-clock-request.dtbo'
run('dtc','-@','-I','dts','-O','dtb','-o',overlay,source)
clean=a.output/'base-no-power-down.dtb';shutil.copyfile(merged,clean)
run('fdtoverlay','-i',clean,'-o',merged,overlay)
assert not any('nvidia,enable-power-down' in props(n) for n in nodes())
assert 'nvidia,disable-clock-request' in props('/bus@0/pcie@14180000')
conf=a.extlinux.read_text();(a.output/'extlinux.conf.original').write_text(conf)
# Do not silently replace other boot entries or discard additional overlays.
if re.search(r'^\s*(OVERLAYS|FDTOVERLAYS)\s',conf,re.M):raise SystemExit('Review existing extlinux overlays before proceeding')
lines=conf.splitlines(); labels=[i for i,l in enumerate(lines) if re.match(r'^\s*LABEL\s+',l)]
if len(labels)!=1:raise SystemExit('Expected one active LABEL; merge manually for multi-entry configurations')
lines=[l for l in lines if not re.match(r'^\s*FDT\s+',l)]
idx=next(i for i,l in enumerate(lines) if re.match(r'^\s*LINUX\s+',l))
lines.insert(idx+1,'      FDT /boot/dtb/pcie-c0-no-power-down.dtb')
(a.output/'extlinux.conf').write_text('\n'.join(lines)+'\n')
(a.output/'verification.json').write_text(json.dumps(dict(removed_from=removed,checked_nodes=len(list(nodes())),sha256=hashlib.sha256(merged.read_bytes()).hexdigest()),indent=2)+'\n')
print('Prepared optional configuration; no boot files installed. Verify the live tree after boot.')
