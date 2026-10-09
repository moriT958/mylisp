#include "chunk.h"

#include "memory.h"

void chunk_init(Chunk *chunk) {
    chunk->count = 0;
    chunk->capacity = 0;
    chunk->code = NULL;
    value_array_init(&chunk->constants);
}

void chunk_write(VM *vm, Chunk *chunk, uint8_t byte) {
    if (chunk->capacity < chunk->count + 1) {
        size_t old_capacity = chunk->capacity;
        chunk->capacity = grow_capacity(old_capacity);
        chunk->code = GROW_ARRAY(vm, uint8_t, chunk->code, old_capacity, chunk->capacity);
    }
    chunk->code[chunk->count++] = byte;
}

void chunk_free(VM *vm, Chunk *chunk) {
    FREE_ARRAY(vm, uint8_t, chunk->code, chunk->capacity);
    value_array_free(vm, &chunk->constants);
    chunk_init(chunk);
}

size_t chunk_add_constant(VM *vm, Chunk *chunk, Value value) {
    value_array_write(vm, &chunk->constants, value);
    return chunk->constants.count - 1;
}
