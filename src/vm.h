#ifndef MYLISP_VM_H
#define MYLISP_VM_H

#include <stdint.h>

#include "chunk.h"
#include "value.h"

// Fixed size so the stack never moves while the GC scans it.
enum { STACK_MAX = 256 };

typedef struct {
    const Chunk *chunk;
    const uint8_t *ip;
    Value stack[STACK_MAX];
    Value *stack_top;
} VM;

typedef enum {
    INTERPRET_OK,
    INTERPRET_RUNTIME_ERROR,
} InterpretResult;

void vm_init(VM *vm);

// *result is written only on INTERPRET_OK.
InterpretResult vm_interpret(VM *vm, const Chunk *chunk, Value *result);

#endif
