#include "chunk.h"

#include <stdio.h>
#include <stdlib.h>

static const char *opcode_names[] = {
#define X(name) #name,
    OPCODES(X)
#undef X
};

const char *opcode_name(uint8_t opcode) {
    if (opcode >= sizeof(opcode_names) / sizeof(opcode_names[0])) return "OP_UNKNOWN";
    return opcode_names[opcode];
}

void chunk_init(Chunk *chunk) {
    chunk->count = 0;
    chunk->capacity = 0;
    chunk->code = NULL;
    value_array_init(&chunk->constants);
}

// TODO: switch to the GC-aware reallocate() once the heap exists.
void chunk_write(Chunk *chunk, uint8_t byte) {
    if (chunk->capacity < chunk->count + 1) {
        size_t new_capacity = chunk->capacity < 8 ? 8 : chunk->capacity * 2;
        uint8_t *grown = realloc(chunk->code, new_capacity);
        if (grown == NULL) {
            fprintf(stderr, "out of memory\n");
            exit(1);
        }
        chunk->code = grown;
        chunk->capacity = new_capacity;
    }
    chunk->code[chunk->count++] = byte;
}

void chunk_free(Chunk *chunk) {
    free(chunk->code);
    value_array_free(&chunk->constants);
    chunk_init(chunk);
}

size_t chunk_add_constant(Chunk *chunk, Value value) {
    value_array_write(&chunk->constants, value);
    return chunk->constants.count - 1;
}
