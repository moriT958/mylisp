#include "memory.h"

#include <stdio.h>
#include <stdlib.h>

static size_t bytes_allocated = 0;

size_t memory_bytes_allocated(void) {
    return bytes_allocated;
}

void *reallocate(void *ptr, size_t old_size, size_t new_size) {
    // Unsigned wraparound makes this correct when shrinking, too.
    bytes_allocated += new_size - old_size;

    if (new_size == 0) {
        free(ptr);
        return NULL;
    }

    void *result = realloc(ptr, new_size);
    if (result == NULL) {
        fprintf(stderr, "out of memory\n");
        exit(1);
    }
    return result;
}
