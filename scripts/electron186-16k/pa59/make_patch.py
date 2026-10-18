#!/usr/bin/env python3
"""Generate Chromium 59 / pinned PDFium ARM64 16 KiB PA backport."""
from pathlib import Path
import difflib,shutil
root=Path(__file__).resolve().parent
source=root/'original'; target=root/'patched'
shutil.copytree(source,target,dirs_exist_ok=True)
changed=[]
for prefix in ('base/allocator/partition_allocator', 'third_party/pdfium/third_party/base/allocator/partition_allocator'):
 p=target/prefix/'page_allocator.h'; old=p.read_text(); new=old.replace(
 '''static const size_t kPageAllocationGranularityShift = 16;  // 64KB
#else''',
 '''static const size_t kPageAllocationGranularityShift = 16;  // 64KB
#elif defined(OS_LINUX) && defined(ARCH_CPU_ARM64)
// A 16 KiB granule also works on 4 KiB kernels. Keep these values constant:
// Chromium 59 uses them in templates, fixed-size arrays and static assertions.
static const size_t kPageAllocationGranularityShift = 14;  // 16KB
#else''').replace(
 '''// All Blink-supported systems have 4096 sized system pages and can handle
// permissions and commit / decommit at this granularity.
static const size_t kSystemPageSize = 4096;''',
 '''// Linux ARM64 kernels can use 4 KiB or 16 KiB system pages. All protection,
// decommit and discard operations must use at least the kernel page size.
#if defined(OS_LINUX) && defined(ARCH_CPU_ARM64)
static const size_t kSystemPageSize = 1 << kPageAllocationGranularityShift;
#else
static const size_t kSystemPageSize = 4096;
#endif''')
 assert new!=old and 'kSystemPageSize = 1 <<' in new,p
 p.write_text(new);changed.append(str(p.relative_to(target)))
 p=target/prefix/'partition_alloc.h'; old=p.read_text();new=old.replace(
 '''// system page of the span. For our current max slot span size of 64k and other
// constant values, we pack _all_ PartitionAllocGeneric() sizes perfectly up
// against the end of a system page.
static const size_t kPartitionPageShift = 14;  // 16KB''',
 '''// system page of the span.
// Keep four system pages per partition page so that its first four pages can
// hold a guard page, metadata page and two more guard pages.
#if defined(OS_LINUX) && defined(ARCH_CPU_ARM64)
static const size_t kPartitionPageShift =
    kPageAllocationGranularityShift + 2;  // 64KB with a 16KB granule.
#else
static const size_t kPartitionPageShift = 14;  // 16KB
#endif''').replace(
 '''// What we're actually doing is avoiding filling the full partition page (16 KB)''',
 '''// What we're actually doing is avoiding filling the full partition page''')
 assert new!=old,p
 # Keep the schematic valid for either supported system-page size.
 for a,b in [('Guard page (4KB)', 'Guard page (1 system page)'),('Metadata page (4KB)','Metadata page (1 system page)'),('Guard pages (8KB)','Guard pages (2 system pages)')]: new=new.replace(a,b)
 # Re-align only the schematic rows touched by variable-sized page labels.
 lines=new.splitlines(True)
 for i,line in enumerate(lines):
  if 'system page)' in line or 'system pages)' in line:
   prefix=line.split('|')[0]
   content=line.split('|')[1].strip()
   lines[i]=prefix+'| '+content.ljust(30)+' |\n'
 new=''.join(lines)
 p.write_text(new);changed.append(str(p.relative_to(target)))
header='''From: Electron 1.8.6 Linux ARM64 16 KiB adaptation
Subject: [PATCH] Chromium 59: use a 16 KiB PartitionAlloc granule on Linux ARM64

Based on the page/partition size invariants used by Chromium CL 3545665 and
csbxd/electron11-16k. Chromium 59 predates runtime PA constants and uses its
sizes in template arguments, fixed arrays and static_assert. Reserve/protect/
decommit in 16 KiB units, with 64 KiB partition pages and 2 MiB super pages.
The resulting PA layout is valid on both 4 KiB and 16 KiB kernels; 64 KiB
kernels are outside this backport's scope. This is a source ABI/layout change:
rebuild all consumers, do not replace a PA library inside an existing process.

Applies to Chromium 59.0.3071.115 and PDFium
e0b592236db902e3e8cbca7ec64f8e2b192e1935 (Chromium 59 DEPS).

'''
patch=header
for f in changed:
 patch+='diff --git a/'+f+' b/'+f+'\n'
 patch+=''.join(difflib.unified_diff((source/f).read_text().splitlines(True),(target/f).read_text().splitlines(True),fromfile='a/'+f,tofile='b/'+f))
(root/'chromium59-linux-arm64-16k-pa.patch').write_text(patch)
print('Created',root/'chromium59-linux-arm64-16k-pa.patch')
