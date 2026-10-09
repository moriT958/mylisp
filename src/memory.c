#include "memory.h"

#include <stdio.h>
#include <stdlib.h>

#include "vm.h"  // IWYU pragma: keep

void *reallocate(VM *vm, void *ptr, size_t old_size, size_t new_size) {
    // Unsigned wraparound makes this correct when shrinking, too.
    vm->bytes_allocated += new_size - old_size;

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
