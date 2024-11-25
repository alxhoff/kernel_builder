#include "pstore_logger.h"

static int panic_handler(struct notifier_block *nb, unsigned long event, void *data)
{
    pr_alert("Kernel panic occurred. Writing logs to persistent storage.\n");
    return write_panic_log_to_file();
}

static struct notifier_block panic_notifier = {
    .notifier_call = panic_handler,
    .priority = 1,
};

static int __init pstore_logger_init(void)
{
    pr_info("Registering panic log handler.\n");
    return atomic_notifier_chain_register(&panic_notifier_list, &panic_notifier);
}

static void __exit pstore_logger_exit(void)
{
    pr_info("Unregistering panic log handler.\n");
    atomic_notifier_chain_unregister(&panic_notifier_list, &panic_notifier);
}

module_init(pstore_logger_init);
module_exit(pstore_logger_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Alex Hoffman <alxhoff@cartken.com>");
MODULE_DESCRIPTION("Kernel module to log pstore data during kernel panics.");

