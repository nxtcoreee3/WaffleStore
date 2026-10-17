#ifndef WAFFLE_MEMORY_PROBE_H
#define WAFFLE_MEMORY_PROBE_H
#include <stdint.h>
typedef struct {
    int32_t signed_text_result;
    int32_t rw_allocation_errno;
    int32_t rw_to_rx_errno;
    int32_t rwx_allocation_errno;
} waffle_memory_result;
// Tests permission requests only. Never branches to unsigned memory or aborts.
waffle_memory_result waffle_probe_memory(void);
#endif
