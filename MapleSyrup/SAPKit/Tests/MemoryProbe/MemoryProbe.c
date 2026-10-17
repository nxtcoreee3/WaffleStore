#include "MemoryProbe.h"
#include <errno.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static int signed_text_control(void) { return 42; }

waffle_memory_result waffle_probe_memory(void) {
    waffle_memory_result result = {0};
    result.signed_text_result = signed_text_control();
    long page = sysconf(_SC_PAGESIZE);
    if (page <= 0) {
        result.rw_allocation_errno = EINVAL;
        result.rw_to_rx_errno = EINVAL;
        result.rwx_allocation_errno = EINVAL;
        return result;
    }
    size_t size = (size_t)page;
    void *buffer = mmap(NULL, size, PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANON, -1, 0);
    if (buffer == MAP_FAILED) {
        result.rw_allocation_errno = errno;
        result.rw_to_rx_errno = errno;
    } else {
        // This is the allocation/protection sequence in ipatool's iOS patch.
        // Byte contents are deliberately data, never executable instructions.
        memset(buffer, 0xA5, size);
        if (mprotect(buffer, size, PROT_READ | PROT_EXEC) != 0)
            result.rw_to_rx_errno = errno;
        munmap(buffer, size);
    }
    buffer = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC,
                  MAP_PRIVATE | MAP_ANON, -1, 0);
    if (buffer == MAP_FAILED) result.rwx_allocation_errno = errno;
    else munmap(buffer, size);
    return result;
}
