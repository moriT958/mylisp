#include "debug.h"

#include <stdio.h>

static size_t simple_instruction(const char *name, size_t offset) {
    printf("%s\n", name);
    return offset + 1;
}

static size_t constant_instruction(const char *name, const Chunk *chunk, size_t offset) {
    uint8_t index = chunk->code[offset + 1];
    printf("%-10s %3u '", name, index);
    value_print(chunk->constants.values[index]);
    printf("'\n");
    return offset + 2;
}

void disassemble_chunk(const Chunk *chunk, const char *name) {
    printf("== %s ==\n", name);
    for (size_t offset = 0; offset < chunk->count;) {
        offset = disassemble_instruction(chunk, offset);
    }
}

size_t disassemble_instruction(const Chunk *chunk, size_t offset) {
    printf("%04zu ", offset);

    uint8_t opcode = chunk->code[offset];
    switch (opcode) {
    case OP_CONST:
        return constant_instruction("OP_CONST", chunk, offset);
    case OP_ADD:
        return simple_instruction("OP_ADD", offset);
    case OP_SUB:
        return simple_instruction("OP_SUB", offset);
    case OP_MUL:
        return simple_instruction("OP_MUL", offset);
    case OP_DIV:
        return simple_instruction("OP_DIV", offset);
    case OP_RETURN:
        return simple_instruction("OP_RETURN", offset);
    default:
        // Advance anyway so the dump continues past a bad byte.
        printf("unknown opcode %u\n", opcode);
        return offset + 1;
    }
}
