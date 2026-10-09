#ifndef MYLISP_VM_H
#define MYLISP_VM_H

#include <stdint.h>

#include "chunk.h"
#include "value.h"

// Fixed size so push never allocates: the GC will run inside allocation, and
// the stack must stay valid (and scannable as a root) at that point.
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

// On INTERPRET_OK, *result holds the value returned by the chunk. Errors are
// reported on stderr and leave *result untouched.
InterpretResult vm_interpret(VM *vm, const Chunk *chunk, Value *result);

#endif
