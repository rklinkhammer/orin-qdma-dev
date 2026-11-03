#!/usr/bin/env python3
"""Offline regression check: remove properties, apply overlay, preserve boot args."""
from pathlib import Path
import subprocess,tempfile,json,shutil
project=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as t:
 p=Path(t)
 shutil.copy(project/'scripts/prepare-pcie.py',p/'prepare-pcie.py')
 shutil.copy(project/'overlay/pci0-clock-request.dts',p/'pci0-clock-request.dts')
 (p/'base.dts').write_text('/dts-v1/; / { bus@0 { pcie@14180000 { status="disabled"; nvidia,enable-power-down; }; pcie@14100000 { nvidia,enable-power-down; }; }; };')
 subprocess.run(['dtc','-q','-I','dts','-O','dtb','-o',str(p/'base.dtb'),str(p/'base.dts')],check=True)
 (p/'extlinux.conf').write_text('DEFAULT primary\nLABEL primary\n LINUX /boot/Image\n INITRD /boot/initrd\n APPEND ${cbootargs} custom=preserved\n')
 subprocess.run(['python3',str(p/'prepare-pcie.py'),'--base',str(p/'base.dtb'),'--extlinux',str(p/'extlinux.conf'),'--output',str(p/'out')],check=True)
 report=json.loads((p/'out/verification.json').read_text())
 assert len(report['removed_from'])==2
 conf=(p/'out/extlinux.conf').read_text()
 assert 'APPEND ${cbootargs} custom=preserved' in conf
 assert conf.count('FDT /boot/dtb/pcie-c0-no-power-down.dtb')==1
 status=subprocess.check_output(['fdtget','-t','s',str(p/'out/pcie-c0-no-power-down.dtb'),'/bus@0/pcie@14180000','status'],text=True).strip()
 assert status=='disabled'
 print('PCIe preparation test passed')
