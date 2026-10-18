#!/usr/bin/env python3
"""Package a stripped, pure Electron runtime with source and test evidence."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('runtime', type=Path)
parser.add_argument('release_directory', type=Path)
parser.add_argument('archive', type=Path)
parser.add_argument('--work-directory', type=Path, required=True)
parser.add_argument('--elf-verifier', type=Path, required=True)
parser.add_argument('--tag', default='electron-1.8.6-16k.1')
args = parser.parse_args()
work = args.work_directory.resolve()
source = args.runtime.resolve()
release = args.release_directory.resolve()
archive = args.archive.resolve()
for name in ['thunder', 'libxl_stat.so', 'libxl_thunder_sdk.so',
             'resources/app', 'resources/bin']:
    if (source / name).exists():
        raise SystemExit('Refusing proprietary app/SDK input: ' + name)
if release.exists() or archive.exists():
    raise SystemExit('Release destination already exists')
for name in ['LICENSE', 'LICENSE.node', 'LICENSE.chromium',
             'LICENSES.chromium.html', 'LICENSES.provenance.json']:
    if not (source / name).is_file():
        raise SystemExit('Missing generated source license: ' + name)
shutil.copytree(source, release, symlinks=False)
subprocess.run(['strip', '--strip-debug', str(release / 'electron'),
                str(release / 'libnode.so')], check=True)

tests = release / 'tests'
tests.mkdir()
renderer = json.loads((work / 'pure-electron-smoke/result.json').read_text())
if not renderer.get('ok') or renderer.get('renderer', {}).get('answer') != 42:
    raise SystemExit('The original runtime renderer smoke did not pass')
shutil.copy2(work / 'pure-electron-smoke/result.json', tests / 'renderer-smoke.json')
shutil.copy2(work / 'pure-electron-smoke/renderer.png', tests / 'renderer-smoke.png')
subprocess.run(['python3', str(args.elf_verifier.resolve()), str(release),
                '--json', str(tests / 'elf-layout.json')], check=True)
elf = json.loads((tests / 'elf-layout.json').read_text())
elf['runtime'] = '.'
(tests / 'elf-layout.json').write_text(json.dumps(elf, indent=2) + '\n')
if elf['elfCount'] != 3:
    raise SystemExit('Expected exactly the three open-source runtime ELF binaries')
env = os.environ.copy()
env.update(ELECTRON_RUN_AS_NODE='1',
           LD_LIBRARY_PATH=str(release) + ':/opt/xunlei-download')
node = subprocess.run([str(release / 'electron'), '-p',
                       'JSON.stringify(process.versions)'], env=env,
                      stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                      text=True, check=True)
node_versions = json.loads(node.stdout)
(tests / 'node-smoke.json').write_text(json.dumps({
    'exitCode': node.returncode, 'versions': node_versions,
    'testedAfterDebugStripping': True,
    'compatibilityLibrary': 'System libgconf-2.so.4; host test used the installed compatibility copy',
}, indent=2) + '\n')

source_lock = json.loads((work / 'source-lock.json').read_text())
recursive = subprocess.check_output(['git', '-C', str(work / 'electron-1.8.6'),
                                     'submodule', 'status', '--recursive'], text=True)
source_lock['recursiveSubmodules'] = dict((match.group(2), match.group(1))
    for line in recursive.splitlines()
    if (match := re.match(r'^[ +\-U]?([0-9a-f]{40})\s+(\S+)', line)))
source_lock['releaseTag'] = args.tag
source_lock['patchSHA256'] = {
    name: hashlib.sha256((work / name).read_bytes()).hexdigest()
    for name in ['electron186-native-build.patch', 'breakpad-glibc-ucontext.patch']
}
(release / 'SOURCE-LOCK.json').write_text(json.dumps(source_lock, indent=2) + '\n')
epoch = int(os.environ.get('SOURCE_DATE_EPOCH') or subprocess.check_output([
    'git', '-C', str(work / 'electron-1.8.6'), 'show', '-s', '--format=%ct', 'HEAD'], text=True).strip())
core_hashes = {name: hashlib.sha256((release / name).read_bytes()).hexdigest()
               for name in ['electron', 'libnode.so', 'libffmpeg.so', 'snapshot_blob.bin']}
build_info = {
    'releaseTag': args.tag, 'releaseDate': '2026-10-18',
    'electronVersion': renderer['versions']['electron'],
    'chromiumVersion': renderer['versions']['chrome'],
    'nodeVersion': node_versions['node'], 'v8Version': node_versions['v8'],
    'architecture': 'aarch64', 'kernelPageSize': 16384,
    'compiler': 'g++ (Ubuntu/Linaro 7.5.0-3ubuntu1~18.04) 7.5.0',
    'electronOptimization': 'O2, GNU gold, no GCC LTO',
    'chromiumGNArgs': (work / 'chromium-59.0.3071.115/out/electron186-16k/args.gn').read_text(),
    'dynamicSymbolPolicy': 'The executable localizes hb_*; Node and V8 exports stay in libnode.so',
    'debugStripping': {'tool': 'strip --strip-debug', 'files': ['electron', 'libnode.so']},
    'licenses': json.loads((release / 'LICENSES.provenance.json').read_text()),
    'tests': {'elfLayout16K': True, 'postStripNodeSmoke': True,
              'rendererDOMAndPaintingBeforeStrip': True,
              'rendererEvidence': 'tests/renderer-smoke.json',
              'rendererImage': 'tests/renderer-smoke.png'},
    'sourceDateEpoch': epoch, 'coreSHA256': core_hashes,
    'containsThunderAppOrSDK': False,
}
(release / 'BUILDINFO.json').write_text(json.dumps(build_info, indent=2) + '\n')
manifest = ''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' +
                   path.relative_to(release).as_posix() + '\n'
                   for path in sorted(release.rglob('*'))
                   if path.is_file() and path != release / 'SHA256SUMS')
(release / 'SHA256SUMS').write_text(manifest)
archive.parent.mkdir(parents=True, exist_ok=True)
with archive.open('wb') as target:
    tar = subprocess.Popen(['tar', '--sort=name', '--format=gnu',
                            '--owner=0', '--group=0', '--numeric-owner',
                            '--mtime=@' + str(epoch), '-C', str(release), '-cf', '-', '.'],
                           stdout=subprocess.PIPE)
    xz = subprocess.Popen(['xz', '-T2', '-6', '-c'], stdin=tar.stdout, stdout=target)
    tar.stdout.close()
    xz_code = xz.wait()
    tar_code = tar.wait()
    if xz_code or tar_code:
        raise SystemExit('Archive compression failed')
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
line = digest + '  ' + archive.name + '\n'
(archive.parent / (archive.name + '.sha256')).write_text(line)
aggregate = archive.parent / 'SHA256SUMS'
other = aggregate.read_text().splitlines(keepends=True) if aggregate.exists() else []
other = [entry for entry in other
         if not entry.strip() or entry.split(maxsplit=1)[-1].strip() != archive.name]
aggregate.write_text(''.join(other) + line)
print(json.dumps({'archive': str(archive), 'size': archive.stat().st_size,
                  'sha256': digest, 'releaseDirectory': str(release)}, indent=2))
