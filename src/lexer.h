#ifndef MYLISP_LEXER_H
#define MYLISP_LEXER_H

#include <stddef.h>

typedef enum {
    TOKEN_LPAREN,
    TOKEN_RPAREN,
    TOKEN_QUOTE,
    TOKEN_INT,
    TOKEN_STRING,
    TOKEN_SYMBOL,
    TOKEN_TRUE,
    TOKEN_FALSE,
    TOKEN_EOF,
    TOKEN_ERROR,
} TokenType;

// start/length point into the source text (or at a static message for TOKEN_ERROR),
// so a token is only valid while the source buffer is alive.
typedef struct {
    TokenType type;
    const char *start;
    size_t length;
    int line;
} Token;

typedef struct {
    const char *start;
    const char *current;
    int line;
} Lexer;

void lexer_init(Lexer *lexer, const char *source);
Token lexer_next(Lexer *lexer);

#endif
