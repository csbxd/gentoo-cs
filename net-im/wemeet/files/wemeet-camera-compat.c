/* Copyright 2026 Gentoo Authors
 * Distributed under the terms of the GNU General Public License v2
 */

#define _GNU_SOURCE

#include <dlfcn.h>
#include <link.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define XCAST_FORMAT_BGRA 0x50120000U
#define XCAST_MAP_WRITE 2U
#define XCAST_FRAME_MEM_SIZE 136U
#define XCAST_NV12_CALL_OFFSET 0x2727bcU
#define XCAST_NV12_CALL_PLACEHOLDER 0xaa1f03e0U

typedef void *(*frame_alloc_fn)(uint32_t, uint32_t, uint32_t);
typedef int (*frame_map_fn)(void *, void *, uint32_t);
typedef int (*frame_unmap_fn)(void *, uint32_t);
typedef void (*frame_unref_fn)(void *);
typedef uint32_t (*plane_count_fn)(void *);
typedef void *(*plane_data_fn)(void *, uint32_t);
typedef uint32_t (*plane_value_fn)(void *, uint32_t);

extern int NV12ToARGB(const uint8_t *src_y, int src_stride_y,
		      const uint8_t *src_uv, int src_stride_uv,
		      uint8_t *dst_argb, int dst_stride_argb,
		      int width, int height);

static frame_alloc_fn frame_alloc;
static frame_map_fn frame_map;
static frame_unmap_fn frame_unmap;
static frame_unref_fn frame_unref;
static plane_count_fn plane_count;
static plane_data_fn plane_data;
static plane_value_fn plane_stride;
static pthread_once_t api_once = PTHREAD_ONCE_INIT;
static int api_ready;
static atomic_int conversion_error_reported;

static uintptr_t wemeet_nv12_call(uint32_t width, uint32_t height,
				  const uint8_t *source, uint32_t source_size);

static void *lookup(void *handle, const char *name)
{
	void *symbol = dlsym(handle, name);

	if (!symbol)
		fprintf(stderr, "wemeet-camera-compat: missing %s: %s\n", name,
			dlerror());
	return symbol;
}

static void resolve_xcast_api(void)
{
	void *xcast = dlopen("libxcast.so", RTLD_NOW | RTLD_NOLOAD);

	if (!xcast) {
		fprintf(stderr, "wemeet-camera-compat: libxcast handle: %s\n",
			dlerror());
		return;
	}
	frame_alloc = (frame_alloc_fn)lookup(xcast, "xcast_video_frame_alloc");
	frame_map = (frame_map_fn)lookup(xcast, "xcast_media_frame_map");
	frame_unmap = (frame_unmap_fn)lookup(xcast, "xcast_media_frame_unmap");
	frame_unref = (frame_unref_fn)lookup(xcast, "xcast_media_frame_unref");
	plane_count = (plane_count_fn)lookup(xcast,
		"xcast_media_frame_mem_get_plane_count");
	plane_data = (plane_data_fn)lookup(xcast,
		"xcast_media_frame_mem_get_data");
	plane_stride = (plane_value_fn)lookup(xcast,
		"xcast_media_frame_mem_get_stride");
	api_ready = frame_alloc && frame_map && frame_unmap && frame_unref &&
		plane_count && plane_data && plane_stride;
}

static int patch_xcast_nv12_call(struct dl_phdr_info *info, size_t size,
				 void *data)
{
	const char *name = strrchr(info->dlpi_name, '/');
	uint32_t *call;
	intptr_t displacement;
	uint32_t instruction;
	long page_size;
	void *page;

	(void)size;
	(void)data;
	name = name ? name + 1 : info->dlpi_name;
	if (strcmp(name, "libxcast.so") != 0)
		return 0;

	call = (uint32_t *)(info->dlpi_addr + XCAST_NV12_CALL_OFFSET);
	if (*call != XCAST_NV12_CALL_PLACEHOLDER) {
		fprintf(stderr,
			"wemeet-camera-compat: unexpected NV12 call instruction 0x%08x\n",
			*call);
		return 1;
	}
	displacement = (intptr_t)(void *)wemeet_nv12_call -
		(intptr_t)(void *)call;
	if ((displacement & 3) != 0 || displacement < -(1L << 27) ||
	    displacement >= (1L << 27)) {
		fprintf(stderr,
			"wemeet-camera-compat: NV12 call target outside BL range\n");
		return 1;
	}

	page_size = sysconf(_SC_PAGESIZE);
	if (page_size <= 0)
		return 1;
	page = (void *)((uintptr_t)call & ~((uintptr_t)page_size - 1U));
	if (mprotect(page, (size_t)page_size,
		     PROT_READ | PROT_WRITE | PROT_EXEC) != 0) {
		perror("wemeet-camera-compat: mprotect writable");
		return 1;
	}
	instruction = 0x94000000U |
		((uint32_t)(displacement >> 2) & 0x03ffffffU);
	*call = instruction;
	__builtin___clear_cache((char *)call, (char *)(call + 1));
	if (mprotect(page, (size_t)page_size, PROT_READ | PROT_EXEC) != 0)
		perror("wemeet-camera-compat: mprotect executable");
	return 1;
}

__attribute__((constructor)) static void initialize(void)
{
	dl_iterate_phdr(patch_xcast_nv12_call, NULL);
}

static void report_conversion_error(const char *message)
{
	if (!atomic_exchange(&conversion_error_reported, 1)) {
		fprintf(stderr, "wemeet-camera-compat: %s\n", message);
	}
}

static uintptr_t wemeet_nv12_call(uint32_t width, uint32_t height,
				  const uint8_t *source, uint32_t source_size)
{
	uint8_t memory[XCAST_FRAME_MEM_SIZE] __attribute__((aligned(8))) = { 0 };
	uint8_t *destination;
	uint32_t destination_stride;
	uint64_t required;
	void *frame;
	int result;

	pthread_once(&api_once, resolve_xcast_api);
	if (!api_ready || !source || !width || !height || (width & 1U) ||
	    (height & 1U))
		return 0;
	required = (uint64_t)width * height * 3U / 2U;
	if (source_size < required)
		return 0;

	frame = frame_alloc(XCAST_FORMAT_BGRA, width, height);
	if (!frame)
		return 0;
	result = frame_map(frame, memory, XCAST_MAP_WRITE);
	if (result != 0 || plane_count(memory) != 1) {
		report_conversion_error("unable to map BGRA frame");
		if (result == 0)
			frame_unmap(frame, XCAST_MAP_WRITE);
		frame_unref(frame);
		return 0;
	}

	destination = plane_data(memory, 0);
	destination_stride = plane_stride(memory, 0);
	if (!destination || destination_stride < width * 4U) {
		report_conversion_error("invalid BGRA destination plane");
		frame_unmap(frame, XCAST_MAP_WRITE);
		frame_unref(frame);
		return 0;
	}

	result = NV12ToARGB(source, (int)width,
			      source + (uint64_t)width * height, (int)width,
			      destination, (int)destination_stride,
			      (int)width, (int)height);
	frame_unmap(frame, XCAST_MAP_WRITE);
	if (result != 0) {
		report_conversion_error("NV12ToARGB failed");
		frame_unref(frame);
		return 0;
	}
	return (uintptr_t)frame;
}
