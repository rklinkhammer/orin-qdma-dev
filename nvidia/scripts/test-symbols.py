#!/usr/bin/env python3
"""Check a module and confirm that an intentionally wrong kernel CRC is rejected."""
import pathlib,subprocess,tempfile,sys
checker=pathlib.Path(__file__).with_name('check-symbols.py')
module,header=map(pathlib.Path,sys.argv[1:])
subprocess.run(['python3',str(checker),str(module),str(header)],check=True)
with tempfile.TemporaryDirectory() as t:
 lines=header.read_text().splitlines()
 for i,line in enumerate(lines):
  f=line.split()
  if len(f)>1 and f[1]=='pci_save_state':
   lines[i]=line.replace(f[0],'0x00000000',1);break
 else: raise AssertionError('pci_save_state missing')
 bad=pathlib.Path(t)/'wrong.symvers';bad.write_text('\n'.join(lines)+'\n')
 result=subprocess.run(['python3',str(checker),str(module),str(bad)],capture_output=True,text=True)
 assert result.returncode and 'pci_save_state' in result.stderr
 print('PASS: intentionally wrong kernel CRC rejected')
