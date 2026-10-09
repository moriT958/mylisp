#ifndef MYLISP_DEBUG_H
#define MYLISP_DEBUG_H

#include <stddef.h>

#include "chunk.h"

void disassemble_chunk(const Chunk *chunk, const char *name);

// Returns the next instruction's offset, since instruction lengths vary.
size_t disassemble_instruction(const Chunk *chunk, size_t offset);

#endif
