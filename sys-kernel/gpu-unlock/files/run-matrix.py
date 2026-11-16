# SPDX-License-Identifier: GPL-2.0-only
"""Run identical cuBLAS cases at stock boost and an optional fixed GPU clock."""
import argparse
import csv
import hashlib
import json
import pathlib
import statistics
import subprocess
import time

p=argparse.ArgumentParser()
p.add_argument('--out',required=True,type=pathlib.Path)
p.add_argument('--binary',default='/usr/libexec/gpu-unlock/tensor-bench')
p.add_argument('--fixed-clock',default='1800')
p.add_argument('--trials',type=int,default=7)
p.add_argument('--batch-ms',type=float,default=400)
a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
def smi(*args):
    return subprocess.run(['nvidia-smi',*args],capture_output=True,text=True)
metadata={'binary_sha256':hashlib.file_digest(open(a.binary,'rb'),'sha256').hexdigest(),
    'boot_id':pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
    'cmdline':pathlib.Path('/proc/cmdline').read_text().strip(),
    'module_loaded':pathlib.Path('/sys/module/gpu_unlock').exists(),
    'gpu':smi('--query-gpu=name,driver_version,power.limit,memory.total','--format=csv').stdout}
(a.out/'metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
results=[]
try:
    for clock in ['stock',a.fixed_clock]:
        setting=smi('-rgc') if clock=='stock' else smi('-lgc',clock+','+clock)
        if setting.returncode:
            if clock=='stock':raise RuntimeError(setting.stderr+setting.stdout)
            print('Fixed clock unavailable: '+setting.stderr+setting.stdout,flush=True);continue
        time.sleep(2)
        power_file=(a.out/(clock+'-sensors.csv')).open('w')
        fields='timestamp,power.draw.average,power.draw.instant,clocks.sm,clocks.mem,temperature.gpu,utilization.gpu'
        monitor=subprocess.Popen(['nvidia-smi','--query-gpu='+fields,'--format=csv','--loop-ms=200'],stdout=power_file,stderr=subprocess.DEVNULL)
        try:
            with (a.out/(clock+'-matrix.jsonl')).open('w') as log:
                proc=subprocess.Popen([a.binary,str(a.trials),str(a.batch_ms)],stdout=subprocess.PIPE,text=True)
                for line in proc.stdout:
                    log.write(line);log.flush()
                    record=json.loads(line);record['clock_policy']=clock;results.append(record)
                    print(clock,record['mode'],record['n'],round(record['tflops'],2),'TFLOPS','correct='+str(record['correct']),flush=True)
                if proc.wait():raise RuntimeError('Matrix benchmark failed')
        finally:
            monitor.terminate();monitor.wait();power_file.close()
        numeric=[]
        with (a.out/(clock+'-sensors.csv')).open() as f:
            for row in csv.reader(f):
                try:numeric.append([float(v.strip().split()[0]) for v in row[1:]])
                except (ValueError,IndexError):pass
        summary={}
        for i,name in enumerate(['power_average_w','power_instant_w','sm_mhz','memory_mhz','temperature_c','gpu_busy_percent']):
            vals=[r[i] for r in numeric]
            if vals:summary[name]={'min':min(vals),'median':statistics.median(vals),'mean':statistics.mean(vals),'max':max(vals)}
        (a.out/(clock+'-sensor-summary.json')).write_text(json.dumps(summary,indent=2)+'\n')
        if clock!='stock' and abs(summary['sm_mhz']['median']-float(clock))>30:
            raise RuntimeError('Requested fixed GPU clock was not maintained')
finally:
    smi('-rgc')
    (a.out/'matrix-results.json').write_text(json.dumps(results,indent=2)+'\n')
print('Matrix suite completed',flush=True)
