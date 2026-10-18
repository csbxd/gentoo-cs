#!/usr/bin/env python3
"""Compile real pinned allocator sources with a logging-only dependency shim."""
from pathlib import Path
import os,subprocess
root=Path(__file__).resolve().parent
assert os.sysconf('SC_PAGE_SIZE')==16384, 'Original failure comparison expects native 16 KiB kernel'
subprocess.run(['git','apply','--check',str(root/'chromium59-linux-arm64-16k-pa.patch')],cwd=root/'original',check=True)
for implementation in ('chromium','pdfium'):
 for layout in ('original','patched'):
  for debug in (0,1):
   suffix=f'{implementation}-{layout}-{debug}'
   out=root/('smoke-'+suffix)
   source=root/layout
   if implementation=='pdfium':
    source=source/'third_party/pdfium'
    allocator=source/'third_party/base/allocator/partition_allocator'
   else:
    allocator=source/'base/allocator/partition_allocator'
   cmd=['g++','-std=c++14','-O2','-pthread','-Wall','-Wextra','-Wno-unused-parameter',f'-DPA59_DCHECK={debug}','-I'+str(root/'shims'),'-I'+str(source),'-I'+str(root/layout),str(root/'allocator_smoke.cc')]
   if implementation=='pdfium':cmd+=['-DPA59_PDFIUM=1']
   cmd += [str(allocator/f) for f in ('partition_alloc.cc','page_allocator.cc','spin_lock.cc','address_space_randomization.cc')]
   cmd += ['-o',str(out)]
   print('Compile',suffix,flush=True)
   compilation=subprocess.run(cmd,text=True,capture_output=True)
   (root/('compile-'+suffix+'.log')).write_text(compilation.stdout+compilation.stderr)
   assert compilation.returncode==0,compilation.stdout+compilation.stderr
   result=subprocess.run([str(out)],text=True,capture_output=True)
   text=f'{suffix}: exit={result.returncode}\n'+result.stdout+result.stderr
   print(text,flush=True)
   (root/('result-'+suffix+'.txt')).write_text(text)
   if layout=='patched':assert result.returncode==0,text
   else:assert result.returncode!=0,'Expected original allocator to fail on 16 KiB kernel'
