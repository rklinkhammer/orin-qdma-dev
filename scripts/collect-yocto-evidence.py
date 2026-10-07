#!/usr/bin/env python3
"""Capture selected, non-secret build metadata after successful staged builds."""
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import struct
import subprocess
import sys

build = Path(sys.argv[1])
destination = Path('/artifacts') / build.name / 'yocto'
destination.mkdir(parents=True, exist_ok=True)
variables = {
    'MACHINE', 'DISTRO', 'DISTRO_VERSION', 'PV', 'PR', 'LICENSE', 'SRCREV',
    'PACKAGE_CLASSES', 'PACKAGE_ARCH',
    'S', 'B', 'WORKDIR', 'D', 'PATH', 'CC', 'CFLAGS', 'CPPFLAGS', 'LDFLAGS',
    'TARGET_SYS', 'TARGET_ARCH', 'TARGET_PREFIX', 'TUNE_FEATURES', 'TUNE_PKGARCH',
    'KERNEL_CC', 'KERNEL_VERSION', 'LINUX_VERSION', 'LINUX_VERSION_EXTENSION',
    'KERNEL_LOCALVERSION', 'KBUILD_DEFCONFIG', 'KCONFIG_MODE', 'L4T_VERSION',
    'KERNEL_IMAGETYPE', 'KERNEL_IMAGETYPES', 'KERNEL_OUTPUT_DIR',
    'STAGING_KERNEL_DIR', 'STAGING_KERNEL_BUILDDIR',
}


def metadata(recipe):
    # Never save the complete environment: it may include passed-through secrets.
    task = {'qdma-tools': 'build', 'qdma': 'install', 'virtual/kernel': 'compile'}[recipe]
    raw = subprocess.run(['bitbake', '-e', '-c', task, recipe], cwd=build, check=True,
                         capture_output=True, text=True).stdout
    result = {}
    for line in raw.splitlines():
        match = re.fullmatch(r'(?:export )?([A-Za-z_][A-Za-z_0-9]*)=(".*")', line)
        if match and match[1] in variables:
            result[match[1]] = ast.literal_eval(match[2])
    return result


def config_values(path):
    values = {}
    for line in path.read_text().splitlines():
        if line.startswith('CONFIG_') and '=' in line:
            key, value = line.split('=', 1)
            values[key] = value
        elif line.startswith('# CONFIG_') and line.endswith(' is not set'):
            values[line[2:-11]] = 'n'
    return values


def module_versions(path, kernel_source):
    # NVIDIA/Canonical's pinned kernel uses packed {u32 next, u32 crc,
    # char name[]} records. Ubuntu 24.04 kmod expects the older fixed-size
    # format. Check the real kernel definition, then read target ELF bytes.
    definition = (Path(kernel_source) / 'include/linux/module.h').read_text()
    definition = definition.split('struct modversion_info {', 1)[1].split('}', 1)[0]
    if not all(value in definition for value in ('u32 next;', 'u32 crc;', 'char name[];')):
        raise SystemExit('Unsupported kernel modversion record definition.')
    raw = path.read_bytes()
    if raw[:6] != b'\x7fELF\x02\x01':
        raise SystemExit('Expected the target ELF64 little-endian module.')
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', raw)
    offset, stride, count, string_index = header[6], header[11], header[12], header[13]
    sections = [struct.unpack_from('<IIQQQQIIQQ', raw, offset + n * stride)
                for n in range(count)]
    strings = sections[string_index]
    names = raw[strings[4]:strings[4] + strings[5]]
    matches = [section for section in sections
               if names[section[0]:].split(b'\0', 1)[0] == b'__versions']
    if len(matches) != 1:
        raise SystemExit('Expected one module __versions section.')
    section = matches[0]
    data = raw[section[4]:section[4] + section[5]]
    versions, cursor = {}, 0
    while cursor < len(data):
        next_offset, crc = struct.unpack_from('<II', data, cursor)
        # kernel/module/version.c stops on next == 0. Modpost emits an
        # all-zero terminator plus the C string's final NUL byte.
        if next_offset == 0:
            if any(data[cursor:]):
                raise SystemExit('Invalid nonzero module-version terminator.')
            break
        if next_offset < 9 or cursor + next_offset > len(data):
            raise SystemExit('Invalid sized module-version record.')
        name = data[cursor + 8:cursor + next_offset].split(b'\0', 1)[0].decode('ascii')
        if not name or name in versions:
            raise SystemExit('Invalid or duplicated imported module symbol.')
        versions[name] = crc
        cursor += next_offset
    return versions


meta = {recipe: metadata(recipe) for recipe in ('qdma-tools', 'qdma', 'virtual/kernel')}
(destination / 'effective-build-metadata.json').write_text(json.dumps(meta, indent=2) + '\n')
for recipe, values in meta.items():
    source = values['S']
    records = []
    for arguments in (['rev-parse', 'HEAD'], ['log', '-n', '8', '--oneline'], ['diff', '--stat']):
        result = subprocess.run(['git', '-C', source] + arguments,
                                capture_output=True, text=True)
        records.append('$ git ' + ' '.join(arguments) + '\n' + result.stdout + result.stderr)
    filename = recipe.replace('/', '-') + '-source-status.txt'
    (destination / filename).write_text('\n'.join(records))
    logs = destination / 'logs'
    logs.mkdir(exist_ok=True)
    for task in ('compile', 'compile_kernelmodules', 'install', 'package_qa', 'kernel_configcheck'):
        source_log = Path(values['WORKDIR']) / 'temp' / ('log.do_' + task)
        if source_log.is_file():
            shutil.copy2(source_log, logs / (recipe.replace('/', '-') + '-' + task + '.log'))
names = ('dma-ctl', 'dma-from-device', 'dma-to-device', 'dma-xfer', 'dma-perf', 'dma-latency')
sources = [Path(meta['qdma-tools']['D']) / 'usr/bin' / name for name in names]
modules = list(Path(meta['qdma']['D']).rglob('qdma-pf.ko'))
if len(modules) != 1:
    raise SystemExit('Complete the current Yocto qdma staged install before collecting evidence.')
sources += modules
manifest = []
for source in sources:
    if not source.is_file():
        raise SystemExit(f'Complete the current Yocto build first; missing artifact: {source}')
    target = destination / source.name
    shutil.copy2(source, target)
    manifest.append({'source': str(source), 'artifact': target.name,
                     'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
(destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
for recipe, values in meta.items():
    cc = values.get('KERNEL_CC' if recipe != 'qdma-tools' else 'CC') or values['CC']
    environment = {**os.environ, 'PATH': values['PATH']}
    result = subprocess.run(shlex.split(cc) + ['--version'], env=environment,
                            check=True, capture_output=True, text=True)
    filename = recipe.replace('/', '-') + '-compiler.txt'
    (destination / filename).write_text(result.stdout)

kernel = meta['virtual/kernel']
kernel_build = Path(kernel['B'])
kernel_destination = destination / 'kernel'
kernel_destination.mkdir(exist_ok=True)
for source, name in (
    (kernel_build / '.config', 'kernel.config'),
    (kernel_build / 'Module.symvers', 'Module.symvers'),
    (kernel_build / 'System.map', 'System.map'),
    (kernel_build / 'arch/arm64/boot/Image', 'Image'),
    (kernel_build / 'include/config/kernel.release', 'kernel.release'),
):
    if not source.is_file() or not source.stat().st_size:
        raise SystemExit(f'Missing finished Yocto kernel evidence: {source}')
    shutil.copy2(source, kernel_destination / name)

staging = Path(meta['qdma']['STAGING_KERNEL_BUILDDIR'])
for filename in ('.config', 'Module.symvers', 'kernel-abiversion', 'kernel-localversion'):
    source = staging / filename
    if source.is_file():
        shutil.copy2(source, kernel_destination / ('staged-' + filename.lstrip('.')))

smoke_config = destination.parent / 'smoke-kernel/kernel.config'
if smoke_config.is_file():
    smoke = config_values(smoke_config)
    yocto = config_values(kernel_destination / 'kernel.config')
    changes = ['symbol\tsmoke\tyocto']
    for key in sorted(smoke.keys() | yocto.keys()):
        before, after = smoke.get(key, '<absent>'), yocto.get(key, '<absent>')
        if before != after:
            changes.append(f'{key}\t{before}\t{after}')
    (destination / 'kernel-config-diff.tsv').write_text('\n'.join(changes) + '\n')

module = destination / 'qdma-pf.ko'
if module.is_file():
    (destination / 'module-info.txt').write_text(subprocess.check_output(['modinfo', str(module)], text=True))
    (destination / 'module-elf-header.txt').write_text(subprocess.check_output(['readelf', '-h', str(module)], text=True))
    # Read target ELF data; never insert the module into a running kernel.
    imports = module_versions(module, kernel['S'])
    (destination / 'module-imported-versions.txt').write_text(''.join(
        f'0x{crc:08x} {name}\n' for name, crc in imports.items()))
    symbols = {row[1]: int(row[0], 16)
               for line in (kernel_destination / 'Module.symvers').read_text().splitlines()
               if len(row := line.split()) >= 2}
    mismatches = [name for name, crc in imports.items() if symbols.get(name) != crc]
    release = (kernel_destination / 'kernel.release').read_text().strip()
    vermagic = subprocess.check_output(['modinfo', '-F', 'vermagic', str(module)], text=True).strip()
    result = {'kernel_release': release, 'module_vermagic': vermagic,
              'version_record_format': 'packed u32 next, u32 crc, flexible name; verified from kernel source',
              'kernel_exported_symbols': len(symbols), 'module_imported_symbols': len(imports),
              'mismatched_or_missing_symbols': mismatches,
              'release_matches': vermagic.split()[0] == release}
    (destination / 'module-abi-check.json').write_text(json.dumps(result, indent=2) + '\n')
    if not imports or mismatches or not result['release_matches']:
        raise SystemExit('Module release or imported symbol CRCs do not match the finished Yocto kernel.')
tools = [destination / name for name in names]
(destination / 'tools-file-types.txt').write_text(subprocess.check_output(['file'] + [str(path) for path in tools], text=True))
for package in build.glob('tmp/deploy/ipk/**/qdma-tools*.ipk'):
    shutil.copy2(package, destination / package.name)

hashes = []
for path in sorted(destination.rglob('*')):
    if path.is_file() and path.name != 'SHA256SUMS':
        hashes.append(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + str(path.relative_to(destination)))
(destination / 'SHA256SUMS').write_text('\n'.join(hashes) + '\n')
print('Yocto compiler, kernel configuration/ABI, packages and artifact hashes exported:', destination)
