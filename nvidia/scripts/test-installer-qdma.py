#!/usr/bin/env python3
"""Check generated NVIDIA installer commands for the QDMA cleanup regression."""
import pathlib,subprocess,sys,yaml
commands=yaml.safe_load(pathlib.Path(sys.argv[1]).read_text())['late-commands']
cleanup=next(i for i,c in enumerate(commands) if isinstance(c,str) and 'Filtering packages to remove' in c)
install=next(i for i,c in enumerate(commands) if isinstance(c,str) and 'packages/*.deb' in c)
verify=next(i for i,c in enumerate(commands) if isinstance(c,str) and 'install ok installed' in c)
assert cleanup<install<verify, 'QDMA must be installed after cleanup and verified at the end'
assert not any('apt purge' in c or 'apt-get purge' in c for c in commands[install+1:] if isinstance(c,str)), 'Review any purge after QDMA installation'
for cmd in commands:
 if isinstance(cmd,str):subprocess.run(['bash','-n'],input=cmd,text=True,check=True)
print('QDMA install order and final checks passed')
