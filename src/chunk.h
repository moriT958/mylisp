#ifndef MYLISP_CHUNK_H
#define MYLISP_CHUNK_H

#include <stddef.h>
#include <stdint.h>

#include "value.h"

typedef enum {
    OP_CONST,
    OP_ADD,
    OP_SUB,
    OP_MUL,
    OP_DIV,
    OP_RETURN,
} OpCode;

typedef struct {
    size_t count;
    size_t capacity;
    uint8_t *code;
    ValueArray constants;
} Chunk;

void chunk_init(Chunk *chunk);
void chunk_write(Chunk *chunk, uint8_t byte);
void chunk_free(Chunk *chunk);

// Returns the index of the constant. Operands are one byte to keep the
// encoding simple, so the compiler must reject indexes above 255.
size_t chunk_add_constant(Chunk *chunk, Value value);

#endif
