#!/usr/bin/env python2
"""Expose an existing libchromiumcontent GN build to Electron's old GYP build."""
from __future__ import print_function
import argparse
import glob
import os
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--prepare-only', action='store_true',
                    help='Allow missing libcc outputs while checking GYP generation')
args = parser.parse_args()
root = os.path.dirname(os.path.abspath(__file__))
electron = os.path.join(root, 'electron-1.8.6')
source = os.path.join(root, 'chromium-59.0.3071.115')
output = os.path.join(source, 'out', 'electron186-16k')
stage = os.path.join(root, 'libcc-dist', 'static_library')
download = os.path.join(electron, 'vendor', 'download', 'libchromiumcontent')

def mkdir(path):
    if not os.path.isdir(path):
        os.makedirs(path)

def link(src, dest):
    mkdir(os.path.dirname(dest))
    if os.path.lexists(dest):
        if os.path.islink(dest) and os.readlink(dest) == src:
            return
        if not os.path.islink(dest):
            raise RuntimeError('Refusing to replace non-symlink: ' + dest)
        os.unlink(dest)
    os.symlink(src, dest)

mkdir(stage)
mkdir(download)
archives = sorted(glob.glob(os.path.join(output, 'obj', 'chromiumcontent', '*.a')))
if args.prepare_only and not archives:
    names = ['chromiumcontent', 'base', 'cc', 'components', 'ppapi', 'media',
             'net', 'services', 'skia', 'angle', 'pdfium', 'webkit',
             'webkitbindings', 'webkitcore', 'webkitmodules', 'webrtc', 'v8', 'v8base']
    archives = [os.path.join(output, 'obj', 'chromiumcontent', 'lib' + n + '.a')
                for n in names]
if not archives:
    raise RuntimeError('No static libchromiumcontent archives; finish the GN second pass')
for old in glob.glob(os.path.join(stage, '*.a')):
    if os.path.islink(old):
        os.unlink(old)
for archive in archives:
    link(archive, os.path.join(stage, os.path.basename(archive)))
link(os.path.join(output, 'gen'), os.path.join(stage, 'gen'))

resources = {
    'content_shell.pak': 'content_shell.pak',
    'icudtl.dat': 'icudtl.dat',
    'natives_blob.bin': 'natives_blob.bin',
    'snapshot_blob.bin': 'snapshot_blob.bin',
    'libffmpeg.so': 'libffmpeg.so',
    'blink_image_resources_200_percent.pak': 'gen/blink/public/resources/blink_image_resources_200_percent.pak',
    'content_resources_200_percent.pak': 'gen/content/app/resources/content_resources_200_percent.pak',
    'ui_resources_200_percent.pak': 'gen/ui/resources/ui_resources_200_percent.pak',
    'views_resources_200_percent.pak': 'gen/ui/views/resources/views_resources_200_percent.pak',
}
for filename, relative in resources.items():
    link(os.path.join(output, relative), os.path.join(stage, filename))
mkdir(os.path.join(stage, 'locales'))
for resource in glob.glob(os.path.join(output, 'gen', 'content', 'app', 'strings',
                                      'content_strings_*.pak')):
    link(resource, os.path.join(stage, 'locales',
                               os.path.basename(resource).replace('content_strings_', '', 1)))

if not args.prepare_only:
    missing = [path for path in archives if not os.path.isfile(path)]
    missing += [os.path.join(output, path) for path in resources.values()
                if not os.path.isfile(os.path.join(output, path))]
    if not glob.glob(os.path.join(stage, 'locales', '*.pak')):
        missing.append(os.path.join(stage, 'locales', '*.pak'))
    if missing:
        raise RuntimeError('Missing libcc outputs:\n' + '\n'.join(missing))

generator = os.path.join(electron, 'vendor', 'libchromiumcontent', 'tools',
                         'generate_filenames_gypi.py')
subprocess.check_call([sys.executable, generator,
                       os.path.join(download, 'filenames.gypi'), source, stage, stage])
with open(os.path.join(download, '.target_arch'), 'w') as f:
    f.write('arm64')
sys.path.insert(0, os.path.join(electron, 'script'))
import bootstrap
bootstrap.create_chrome_version_h()
if not os.path.exists(os.path.join(electron, 'vendor', 'node', 'config.gypi')):
    bootstrap.touch_config_gypi()
print('Staged %d static libraries from %s' % (len(archives), output))
