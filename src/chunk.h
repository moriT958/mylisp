#ifndef MYLISP_CHUNK_H
#define MYLISP_CHUNK_H

#include <stddef.h>
#include <stdint.h>

#include "value.h"

// One list drives the enum and the name table, so adding an instruction
// cannot leave one of them stale.
#define OPCODES(X) \
    X(OP_CONST)    \
    X(OP_ADD)      \
    X(OP_SUB)      \
    X(OP_MUL)      \
    X(OP_DIV)      \
    X(OP_RETURN)

typedef enum {
#define X(name) name,
    OPCODES(X)
#undef X
} OpCode;

const char *opcode_name(uint8_t opcode);

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
