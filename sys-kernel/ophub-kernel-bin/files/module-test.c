// SPDX-License-Identifier: GPL-2.0-only
#include <linux/init.h>
#include <linux/module.h>

static int __init ophub_headers_test_init(void)
{
	return 0;
}

static void __exit ophub_headers_test_exit(void)
{
}

module_init(ophub_headers_test_init);
module_exit(ophub_headers_test_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Build-only smoke test for the ophub prepared module tree");
