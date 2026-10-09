#ifndef MYLISP_MEMORY_H
#define MYLISP_MEMORY_H

#include <stddef.h>

#include "value.h"

// Every allocation goes through here so the GC can track the byte count.
// old_size is passed because free() does not report sizes.
void *reallocate(VM *vm, void *ptr, size_t old_size, size_t new_size);

#define GROW_ARRAY(vm, type, ptr, old_count, new_count)                                            \
    ((type *)reallocate((vm), (ptr), sizeof(type) * (old_count), sizeof(type) * (new_count)))

#define FREE_ARRAY(vm, type, ptr, old_count) reallocate((vm), (ptr), sizeof(type) * (old_count), 0)

static inline size_t grow_capacity(size_t capacity) {
    return capacity < 8 ? 8 : capacity * 2;
}

#endif
