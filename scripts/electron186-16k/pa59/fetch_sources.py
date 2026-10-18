#!/usr/bin/env python3
"""Restore the small pinned source set and verify every SHA-256."""
from pathlib import Path
import concurrent.futures,hashlib,json,time,urllib.request
root=Path(__file__).resolve().parent
def fetch(item):
 path=root/'original'/item['path'];path.parent.mkdir(parents=True,exist_ok=True)
 if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256']:return
 for attempt in range(4):
  try:
   data=urllib.request.urlopen(item['url'],timeout=60).read()
   assert hashlib.sha256(data).hexdigest()==item['sha256'],item['path']
   path.write_bytes(data);return
  except Exception:
   if attempt==3:raise
   time.sleep(attempt+1)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 list(pool.map(fetch,json.loads((root/'sources.json').read_text())))
print('Pinned source hashes verified')
