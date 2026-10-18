// Standalone allocator smoke only. Preserve CHECK/DCHECK failure behavior;
// avoid linking Chromium's unrelated logging/platform framework.
#ifndef PA59_STANDALONE_LOGGING_H
#define PA59_STANDALONE_LOGGING_H
#include <cstdio>
#include <cstdlib>
#ifndef PA59_DCHECK
#define PA59_DCHECK 1
#endif
#define DCHECK_IS_ON() PA59_DCHECK
#define CHECK(condition) do { if (!(condition)) { std::fprintf(stderr, "%s:%d: CHECK(%s) failed\n", __FILE__, __LINE__, #condition); std::abort(); } } while (0)
#if PA59_DCHECK
#define DCHECK(condition) CHECK(condition)
#else
#define DCHECK(condition) do { } while (0)
#endif
#define DCHECK_EQ(a,b) DCHECK((a)==(b))
#define NOTREACHED() do { std::abort(); } while (0)
#define IMMEDIATE_CRASH() do { std::abort(); } while (0)
#endif
