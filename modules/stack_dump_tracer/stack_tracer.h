#if !defined(_TRACE_STACK_DUMP_H) || defined (TRACE_HEADER_MULTI_READ)
#define _TRACE_STACK_DUMP_H

#undef TRACE_SYSTEM
#define TRACE_SYSTEM stack_tracer

// #define TRACE_INCLUDE_PATH ./drivers/misc/stack_dump_tracer
// #undef TRACE_INCLUDE_FILE
// #define TRACE_INCLUDE_FILE stack_tracer

#include <linux/tracepoint.h>

#define STACK_TRACER_DUMP trace_stack_tracer_dump(__func__, __FILE__, __LINE__)

void stack_tracer_dump_stack(void);

// Define the trace event
TRACE_EVENT(stack_tracer_dump,
    TP_PROTO(const char *func_str, const char* file_str, int line),
    TP_ARGS(func_str, file_str, line),
    TP_STRUCT__entry(
        __field(const char *, func_str)
        __field(const char *, file_str)
        __field(int, line)
    ),
    TP_fast_assign(
        __entry->func_str = func_str;
        __entry->file_str = file_str;
        __entry->line = line;
        stack_tracer_dump_stack(); 
    ),
    TP_printk("Stack tracer %s:%s:%d", __entry->func_str, __entry->file_str, __entry->line)
);

#endif /* _TRACE_STACK_DUMP_H */

#include <trace/define_trace.h>

