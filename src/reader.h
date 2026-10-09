#ifndef MYLISP_READER_H
#define MYLISP_READER_H

#include "lexer.h"
#include "value.h"

typedef enum {
    READ_OK,
    READ_EOF,
    // The input ended inside a datum, e.g. "(1 2". A REPL can ask for more lines.
    READ_INCOMPLETE,
    READ_ERROR,
} ReadStatus;

typedef struct {
    int line;
    char message[96];
} ReadError;

// Reads one datum from the lexer's current position. Call repeatedly to read
// every datum in the source until READ_EOF. error is filled only on READ_ERROR.
ReadStatus reader_read(VM *vm, Lexer *lexer, Value *out, ReadError *error);

#endif
