#include "pstore_logger.h"

static int __init pstore_logger_test_init(void)
{
    pr_info("[panic_logger_test] testing pstore logging by directly invoking the callback.\n");
    printk(KERN_INFO "panic logger init'd, a copy of /sys/fs/pstore/* should now be in /var/log/panic.log");
    return write_panic_log_to_file();
}

static void __exit pstore_logger_test_exit(void)
{
    pr_info("[panic_logger_test] module unloaded.\n");
    printk(KERN_INFO "removing panic logger, hope it went well :)");
}

module_init(pstore_logger_test_init);
module_exit(pstore_logger_test_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Alex Hoffman <alxhoff@cartken.com>");
MODULE_DESCRIPTION("Testing module to directly invoke pstore logging logic.");

