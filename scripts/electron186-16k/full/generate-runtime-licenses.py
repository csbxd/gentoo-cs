#!/usr/bin/env python2
"""Generate Chromium credits from the exact compiled source and copy notices."""
from __future__ import print_function
import hashlib
import json
import os
import shutil
import subprocess
import sys

root = os.path.dirname(os.path.abspath(__file__))
destination = os.path.abspath(sys.argv[1])
electron = os.path.join(root, 'electron-1.8.6')
libcc = os.path.join(electron, 'vendor', 'libchromiumcontent')
chromium = os.path.join(root, 'chromium-59.0.3071.115')
link = os.path.join(libcc, 'src')
if os.path.lexists(link):
    if os.path.realpath(link) != os.path.realpath(chromium):
        raise RuntimeError('libchromiumcontent/src already points to another tree')
else:
    os.symlink(os.path.relpath(chromium, libcc), link)
if not os.path.isdir(destination):
    os.makedirs(destination)
credits = os.path.join(destination, 'LICENSES.chromium.html')
generator = os.path.join(libcc, 'tools', 'licenses.py')
subprocess.check_call([sys.executable, generator, 'credits', credits,
                       '--file-template', os.path.join(libcc, 'resources', 'about_credits.tmpl'),
                       '--entry-template', os.path.join(libcc, 'resources', 'about_credits_entry.tmpl')])
html = open(credits, 'rb').read()
if len(html) < 1000000 or '<div class="product">' not in html:
    raise RuntimeError('Generated Chromium credits are unexpectedly incomplete')
for filename, source in [
    ('LICENSE', os.path.join(electron, 'LICENSE')),
    ('LICENSE.node', os.path.join(electron, 'vendor', 'node', 'LICENSE')),
    ('LICENSE.chromium', os.path.join(chromium, 'LICENSE')),
]:
    shutil.copy2(source, os.path.join(destination, filename))
provenance = {
    'method': 'generated_from_compiled_chromium_source',
    'chromiumVersion': '59.0.3071.115',
    'libchromiumcontentCommit': 'd56634abfa9f1068b1cb4788510b4c23b14e8c0a',
    'generator': 'vendor/libchromiumcontent/tools/licenses.py',
    'generatorSHA256': hashlib.sha256(open(generator, 'rb').read()).hexdigest(),
    'creditsEntryCount': html.count('<div class="product">'),
    'creditsSHA256': hashlib.sha256(html).hexdigest(),
    'officialFallbackUsed': False,
}
with open(os.path.join(destination, 'LICENSES.provenance.json'), 'w') as output:
    json.dump(provenance, output, indent=2, sort_keys=True)
    output.write('\n')
print('Generated Chromium credits: %d entries, %d bytes' %
      (provenance['creditsEntryCount'], len(html)))
