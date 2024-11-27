#define CREATE_TRACE_POINTS  
#include <trace/events/stack_tracer.h> 

#include <linux/module.h>
#include <linux/stacktrace.h>
#include <linux/tracepoint.h>

void stack_tracer_dump_stack(void)
{
    unsigned long entries[32];
    unsigned int num_entries;
    int i;

    num_entries = stack_trace_save(entries, ARRAY_SIZE(entries), 0);

    // Write the stack trace to the trace buffer
    trace_printk("Stack tracer:\n");
    for (i = 0; i < num_entries; i++) {
        trace_printk(" %p\n", (void *)entries[i]);
    }
}
EXPORT_SYMBOL(stack_tracer_dump_stack);
EXPORT_TRACEPOINT_SYMBOL(stack_tracer_dump);

static int __init stack_tracer_init(void)
{
    pr_info("Stack dump trace module loaded\n");
    return 0;
}

static void __exit stack_tracer_exit(void)
{
    pr_info("Stack dump trace module unloaded\n");
}

module_init(stack_tracer_init);
module_exit(stack_tracer_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Alex Hoffman <alxhoff@cartken.com>");
MODULE_DESCRIPTION("Tracepoint module with stack trace dump");

