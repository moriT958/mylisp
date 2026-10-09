#include "chunk.h"
#include "debug.h"
#include "vm.h"

#include <stdio.h>

// TODO: temporary driver; replace with the REPL once the Reader exists.
int main(void) {
    VM vm;
    vm_init(&vm);

    Chunk chunk;
    chunk_init(&chunk);

    chunk_write(&vm, &chunk, OP_CONST);
    chunk_write(&vm, &chunk, (uint8_t)chunk_add_constant(&vm, &chunk, val_int(1)));
    chunk_write(&vm, &chunk, OP_CONST);
    chunk_write(&vm, &chunk, (uint8_t)chunk_add_constant(&vm, &chunk, val_int(2)));
    chunk_write(&vm, &chunk, OP_CONST);
    chunk_write(&vm, &chunk, (uint8_t)chunk_add_constant(&vm, &chunk, val_int(3)));
    chunk_write(&vm, &chunk, OP_MUL);
    chunk_write(&vm, &chunk, OP_ADD);
    chunk_write(&vm, &chunk, OP_RETURN);

    disassemble_chunk(&chunk, "1 + 2 * 3");

    Value result;
    int status = 0;
    if (vm_interpret(&vm, &chunk, &result) == INTERPRET_OK) {
        value_print(result);
        printf("\n");
    } else {
        status = 1;
    }

    chunk_free(&vm, &chunk);
    vm_free(&vm);
    return status;
}
