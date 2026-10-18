#!/usr/bin/env python2
from __future__ import print_function
import os
import shutil
import subprocess
import sys

root = os.path.dirname(os.path.abspath(__file__))
electron = os.path.join(root, 'electron-1.8.6')
output = os.path.join(electron, 'out', 'R')
runtime = os.path.join(root, 'electron186-runtime')
if os.path.exists(runtime):
    shutil.rmtree(runtime)
os.makedirs(runtime)
files = ['electron', 'content_shell.pak', 'pdf_viewer_resources.pak',
         'icudtl.dat', 'libffmpeg.so', 'libnode.so',
         'blink_image_resources_200_percent.pak',
         'content_resources_200_percent.pak',
         'ui_resources_200_percent.pak', 'views_resources_200_percent.pak',
         'natives_blob.bin', 'snapshot_blob.bin']
for name in files:
    # copy2 follows symlinks; no /build symlinks escape into the final runtime.
    shutil.copy2(os.path.join(output, name), os.path.join(runtime, name))
for name in ['resources', 'locales']:
    shutil.copytree(os.path.join(output, name), os.path.join(runtime, name),
                    symlinks=False)
shutil.copy2(os.path.join(electron, 'LICENSE'), os.path.join(runtime, 'LICENSE'))
subprocess.check_call([sys.executable, os.path.join(root, 'generate-runtime-licenses.py'), runtime])
with open(os.path.join(runtime, 'version'), 'w') as f:
    f.write('1.8.6\n')
print('Standalone runtime: ' + runtime)
