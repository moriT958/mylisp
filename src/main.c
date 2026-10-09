#include "chunk.h"
#include "debug.h"

// TODO:
// Temporary driver: there is no Reader yet, so build `1 + 2 * 3` by hand to
// exercise the chunk and the disassembler. Replace it with the REPL once the Reader exists.
int main(void) {
    Chunk chunk;
    chunk_init(&chunk);

    chunk_write(&chunk, OP_CONST);
    chunk_write(&chunk, (uint8_t)chunk_add_constant(&chunk, val_int(1)));
    chunk_write(&chunk, OP_CONST);
    chunk_write(&chunk, (uint8_t)chunk_add_constant(&chunk, val_int(2)));
    chunk_write(&chunk, OP_CONST);
    chunk_write(&chunk, (uint8_t)chunk_add_constant(&chunk, val_int(3)));
    chunk_write(&chunk, OP_MUL);
    chunk_write(&chunk, OP_ADD);
    chunk_write(&chunk, OP_RETURN);

    disassemble_chunk(&chunk, "1 + 2 * 3");
    chunk_free(&chunk);
    return 0;
}
