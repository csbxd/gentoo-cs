#!/usr/bin/env python3
"""Fetch the pinned 2017 sources without the retired libcc binary service."""
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import urllib.request

root = Path(__file__).resolve().parent
lock = json.loads((root / 'source-lock.json').read_text())
electron = root / 'electron-1.8.6'
source = root / ('chromium-' + lock['chromiumVersion'])

def run(*args, cwd=root):
    subprocess.run(args, cwd=cwd, check=True)

def apply(cwd, patch):
    command = ['git', 'apply', '--ignore-space-change', '--ignore-whitespace']
    if subprocess.run(command + ['--check', str(patch)], cwd=cwd,
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        run(*(command + ['--reverse', '--check', str(patch)]), cwd=cwd)
    else:
        run(*(command + [str(patch)]), cwd=cwd)

if not electron.exists():
    run('git', 'clone', '--depth=1', '--branch=' + lock['electronTag'],
        'https://github.com/electron/electron.git', str(electron))
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=electron, text=True).strip()
if head != lock['electronCommit']:
    raise SystemExit('Existing Electron checkout has a different commit: ' + head)
run('git', 'submodule', 'update', '--init', '--depth=1', 'vendor/libchromiumcontent', cwd=electron)
run('git', 'submodule', 'update', '--init', '--recursive', '--depth=1',
    'vendor/node', 'vendor/gyp', 'vendor/native_mate', 'vendor/breakpad',
    'vendor/crashpad', 'vendor/pdf_viewer', 'vendor/requests', 'vendor/boto', cwd=electron)

archive = root / ('chromium-' + lock['chromiumVersion'] + '.tar.xz')
if not archive.exists():
    print('Downloading the Chromium source archive', flush=True)
    with urllib.request.urlopen(lock['chromiumArchiveURL'], timeout=60) as response, archive.open('wb') as output:
        while block := response.read(1024 * 1024):
            output.write(block)
if hashlib.sha256(archive.read_bytes()).hexdigest() != lock['chromiumArchiveSHA256']:
    raise SystemExit('Chromium archive SHA-256 mismatch')
if not source.exists():
    print('Extracting Chromium', flush=True)
    with tarfile.open(archive) as content:
        content.extractall(root, filter='data')
run('python3', str(root / 'prepare-chromium.py'))
apply(electron, root / 'electron186-native-build.patch')
apply(electron / 'vendor/breakpad/src', root / 'breakpad-glibc-ucontext.patch')
run('npm', 'ci', '--prefix', str(root / 'npm-tools'), '--ignore-scripts',
    '--no-audit', '--no-fund')
modules = electron / 'node_modules'
if not modules.exists():
    modules.symlink_to('../npm-tools/node_modules', target_is_directory=True)
print('Pinned source and build tools are ready.', flush=True)
