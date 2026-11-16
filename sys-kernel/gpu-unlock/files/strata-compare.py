# SPDX-License-Identifier: GPL-2.0-only
"""A fixed request sequence; run against a fresh Strata instance in each phase."""
import argparse
import hashlib
import json
import pathlib
import time
import urllib.request

p=argparse.ArgumentParser()
p.add_argument('--out',required=True,type=pathlib.Path)
p.add_argument('--key-file',required=True,type=pathlib.Path)
p.add_argument('--url',default='http://127.0.0.1:8080')
a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
key=a.key_file.read_text().strip()
op=urllib.request.build_opener(urllib.request.ProxyHandler({}))
model='qwen3.8-flash-next-iq3_xxs'
def request(path,data=None):
    req=urllib.request.Request(a.url+path,data=json.dumps(data).encode() if data is not None else None,
        headers={'Content-Type':'application/json','Authorization':'Bearer '+key})
    with op.open(req,timeout=600) as r:return json.load(r)
deadline=time.monotonic()+300
while True:
    try:
        if request('/health').get('loaded'):break
    except OSError:pass
    if time.monotonic()>deadline:raise TimeoutError('Strata did not become ready')
    time.sleep(2)

warm={'model':model,'messages':[{'role':'user','content':'Reply with OK.'}],
    'max_tokens':16,'temperature':0,'seed':42,'chat_template_kwargs':{'enable_thinking':False}}
request('/v1/chat/completions',warm)
records=[]
# Distinct leading strings prevent cross-request prefix reuse; the same strings
# and order are replayed after unlock. We report prompt_n and cache_n explicitly.
for size,repeat in [(16,0),(16,1),(16,2),(512,0),(512,1),(512,2)]:
    lines=[f'Record {i:05d}: the CPU routes experts; the GPU computes matrix operations; memory holds weights.' for i in range(size)]
    prompt=f'{size}x{repeat} measurement case.\n'+'\n'.join(lines)+'\nExplain the relationship of computation, memory bandwidth and latency in detail. Write at least 300 words.'
    req={'model':model,'messages':[{'role':'user','content':prompt}], 'max_tokens':256,
        'temperature':0,'seed':42,'chat_template_kwargs':{'enable_thinking':False}}
    t=time.monotonic();r=request('/v1/chat/completions',req);wall=time.monotonic()-t
    content=r['choices'][0]['message'].get('content') or ''
    assert content and r['usage']['completion_tokens']>=100,r
    record={'case_lines':size,'repeat':repeat,'request_sha256':hashlib.sha256(json.dumps(req,sort_keys=True).encode()).hexdigest(),
        'wall_s':wall,'usage':r['usage'],'timings':r.get('timings'),
        'response_sha256':hashlib.sha256(content.encode()).hexdigest(),'finish':r['choices'][0]['finish_reason']}
    records.append(record);(a.out/'strata-results.json').write_text(json.dumps(records,indent=2)+'\n')
    print(json.dumps(record),flush=True)
print('Strata suite completed',flush=True)
