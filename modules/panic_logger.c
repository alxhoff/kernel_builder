#include "pstore_logger.h"

#define PANIC_MSG "CARTKEN_KERNEL_HAS_PANICKED"

static int panic_handler(struct notifier_block *nb, unsigned long event, void *data)
{
    pr_alert("[panic_logger] kernel panic occurred\n");
    pr_emerg("%s\n", PANIC_MSG);

    return NOTIFY_OK;
}

static struct notifier_block panic_notifier = {
    .notifier_call = panic_handler,
    .priority = 1,
};

static int __init pstore_logger_init(void)
{
    int ret = 0;
    pr_info("[panic_logger] registering panic log handler\n");
    ret = atomic_notifier_chain_register(&panic_notifier_list, &panic_notifier);
    if(ret != 0){
        printk(KERN_ERR "[panic_logger] failed to register panic log handler");
        return ret;
    }
    pr_info("[panic logger] panic log handler registered");
    return 0;
}

static void __exit pstore_logger_exit(void)
{
    pr_info("[panic_logger] unregistering panic log handler\n");
    atomic_notifier_chain_unregister(&panic_notifier_list, &panic_notifier);
}

module_init(pstore_logger_init);
module_exit(pstore_logger_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Alex Hoffman <alxhoff@cartken.com>");
MODULE_DESCRIPTION("Kernel module to log pstore data during kernel panics.");

