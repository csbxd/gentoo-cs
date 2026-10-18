#!/usr/bin/env python3
"""Apply the pinned Electron release patches, followed by the 16 KiB port."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tarfile
import urllib.request

root = Path(__file__).resolve().parent
source = root / 'chromium-59.0.3071.115'
libcc = root / 'electron-1.8.6/vendor/libchromiumcontent'
patch_root = libcc / 'patches'

def apply(cwd, patch):
    command = ['git', 'apply', '--ignore-space-change', '--ignore-whitespace']
    if subprocess.run(command + ['--check', str(patch)], cwd=cwd,
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        subprocess.run(command + ['--reverse', '--check', str(patch)],
                       cwd=cwd, check=True)
        print('Already applied:', patch.relative_to(root.parent), flush=True)
        return
    subprocess.run(command + [str(patch)], cwd=cwd, check=True)
    print('Applied:', patch.relative_to(root.parent), flush=True)

# The release source archive omits Linux's optional bundled FreeType tree,
# while PDFium still includes its private glyph-name tables. Restore the whole
# immutable DEPS-pinned source, with the archive hash recorded for reproduction.
for dependency in json.loads((root / 'source-deps.json').read_text()):
    destination = source / dependency['target']
    revision_file = destination / '.electron186-dependency-revision'
    if revision_file.exists() and revision_file.read_text().strip() == dependency['revision']:
        continue
    archive = root / dependency['archive']
    if not archive.exists():
        with urllib.request.urlopen(dependency['url'], timeout=60) as response:
            archive.write_bytes(response.read())
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != dependency['sha256']:
        raise RuntimeError('Pinned dependency archive SHA-256 mismatch: ' + dependency['name'])
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as bundle:
        bundle.extractall(destination, filter='data')
    revision_file.write_text(dependency['revision'] + '\n')
    print('Restored pinned dependency:', dependency['name'], dependency['revision'], flush=True)

for patch in sorted(patch_root.rglob('*.patch')):
    apply(source / patch.parent.relative_to(patch_root), patch)
apply(source, root / '16k-patches/chromium59-linux-arm64-16k-pa.patch')
shutil.copytree(libcc / 'chromiumcontent', source / 'chromiumcontent',
                dirs_exist_ok=True)
for patch in sorted((root / 'compat-patches').glob('*.patch')):
    apply(source, patch)
(source / '.electron186-16k-patched').write_text('Electron v1.8.6 / 16 KiB PA\n')
print('Source prepared:', source, flush=True)
