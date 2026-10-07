#!/usr/bin/env python3
"""Export staged Yocto binaries and build evidence without invoking deployment."""
import hashlib
import json
import shutil
import sys
from pathlib import Path

build = Path(sys.argv[1])
destination = Path('/artifacts') / build.name / 'yocto'
destination.mkdir(parents=True, exist_ok=True)
manifest = []
for pattern in ('tmp/work/**/qdma/*/image/**/qdma-pf.ko', 'tmp/work/**/qdma-tools/*/image/usr/bin/dma-*'):
    for source in build.glob(pattern):
        if not source.is_file():
            continue
        target = destination / source.name
        shutil.copy2(source, target)
        manifest.append({'source': str(source), 'artifact': target.name, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
if not manifest:
    raise SystemExit('No staged Yocto QDMA artifacts found. Complete tools/driver builds first.')
(destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(destination)
