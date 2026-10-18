#ifdef PA59_PDFIUM
#include "third_party/base/allocator/partition_allocator/partition_alloc.h"
namespace base=pdfium::base;
#else
#include "base/allocator/partition_allocator/partition_alloc.h"
#endif
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <vector>
#include <unistd.h>

struct Allocation { void* ptr; size_t size; unsigned char byte; };
static void CheckBytes(const Allocation& a) {
  auto p = static_cast<unsigned char*>(a.ptr);
  for (size_t i = 0; i < a.size; ++i) CHECK(p[i] == a.byte);
}
int main() {
  std::printf("kernel=%ld allocation=%zu system=%zu partition=%zu super=%zu dcheck=%d\n",
      sysconf(_SC_PAGESIZE), base::kPageAllocationGranularity,
      base::kSystemPageSize, base::kPartitionPageSize, base::kSuperPageSize,
      DCHECK_IS_ON());
  std::fflush(stdout);
  base::PartitionAllocGlobalInit([] { std::abort(); });
  static base::PartitionAllocatorGeneric allocator;
  allocator.init();
  auto* root=allocator.root();
  const size_t sizes[] = {0, 1, 8, 16, 24, 64, 96, 128, 255, 256, 512,
    1000, 4095, 4096, 4097, 8192, 12288, 16383, 16384, 16385,
    32768, 49152, 65536, 65537, 131072, 196608, 262144, 262145,
    524288, 917504, 983000, 983041, 1048576, 1048577, 4194304};
  std::vector<size_t> all_sizes(std::begin(sizes), std::end(sizes));
  size_t bucket_classes=0;
  for (size_t i=0;i<base::kGenericNumBuckets;++i) {
    size_t slot=root->buckets[i].slot_size;
    if (slot % base::kGenericSmallestBucket) continue;
#if DCHECK_IS_ON()
    if (slot<2*base::kCookieSize) continue;
#endif
    all_sizes.push_back(base::PartitionCookieSizeAdjustSubtract(slot));
    ++bucket_classes;
  }
  std::printf("reachable bucket classes=%zu\n",bucket_classes);
  std::vector<Allocation> live;
  unsigned seq=0;
  for (size_t size : all_sizes) {
    for (unsigned i=0; i<12; ++i) {
      void* p=base::PartitionAllocGeneric(root, size, "smoke"); CHECK(p);
      CHECK(base::PartitionAllocGetSize(p)>=size);
      const auto value=static_cast<unsigned char>(++seq);
      std::memset(p,value,size); live.push_back({p,size,value});
    }
  }
  std::mt19937 rng(18616);
  std::shuffle(live.begin(),live.end(),rng);
  for (auto& a:live) {
    CheckBytes(a);
    size_t new_size=(a.size % 2097152) + 16385;
    void* p=base::PartitionReallocGeneric(root,a.ptr,new_size,"realloc");CHECK(p);
    Allocation preserved{p,std::min(a.size,new_size),a.byte}; CheckBytes(preserved);
    std::memset(p,a.byte,new_size);
    a={p,new_size,a.byte};
  }
  // Purge partially occupied spans to exercise system-page discard paths.
  for (size_t i=0;i<live.size();i+=2) {
    CheckBytes(live[i]); base::PartitionFreeGeneric(root,live[i].ptr);live[i].ptr=nullptr;
  }
  base::PartitionPurgeMemoryGeneric(root,
      base::PartitionPurgeDecommitEmptyPages | base::PartitionPurgeDiscardUnusedSystemPages);
  for (auto a:live) if (a.ptr) { CheckBytes(a);base::PartitionFreeGeneric(root,a.ptr); }
  base::PartitionPurgeMemoryGeneric(root,
      base::PartitionPurgeDecommitEmptyPages | base::PartitionPurgeDiscardUnusedSystemPages);
  // Recommit and re-use freed pages in multiple small-object slot spans.
  live.clear();
  for (size_t i=0;i<100000;++i) {
    size_t n=(i%192)+1;
    void* p=base::PartitionAllocGeneric(root,n,"small");CHECK(p);
    auto v=static_cast<unsigned char>(i);std::memset(p,v,n);live.push_back({p,n,v});
  }
  std::shuffle(live.begin(),live.end(),rng);
  for(auto a:live) {CheckBytes(a);base::PartitionFreeGeneric(root,a.ptr);}
  base::PartitionPurgeMemoryGeneric(root,base::PartitionPurgeDecommitEmptyPages);
  std::puts("PASS: allocate/free, all size classes, direct maps, realloc, purge, recommit, data preservation");
}
