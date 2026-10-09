#include "lexer.h"

#include <ctype.h>
#include <stdbool.h>
#include <string.h>

void lexer_init(Lexer *lexer, const char *source) {
    lexer->start = source;
    lexer->current = source;
    lexer->line = 1;
}

static bool is_at_end(const Lexer *lexer) {
    return *lexer->current == '\0';
}

static char advance(Lexer *lexer) {
    return *lexer->current++;
}

static bool is_delimiter(char c) {
    return c == '\0' || isspace((unsigned char)c) || c == '(' || c == ')' || c == ';' || c == '"' ||
           c == '\'';
}

static Token make_token(const Lexer *lexer, TokenType type) {
    return (Token){type, lexer->start, (size_t)(lexer->current - lexer->start), lexer->line};
}

static Token error_token(const Lexer *lexer, const char *message) {
    return (Token){TOKEN_ERROR, message, strlen(message), lexer->line};
}

static void skip_whitespace_and_comments(Lexer *lexer) {
    for (;;) {
        char c = *lexer->current;
        if (c == '\n') {
            lexer->line++;
            lexer->current++;
        } else if (isspace((unsigned char)c)) {
            lexer->current++;
        } else if (c == ';') {
            while (!is_at_end(lexer) && *lexer->current != '\n')
                lexer->current++;
        } else {
            return;
        }
    }
}

static void advance_to_delimiter(Lexer *lexer) {
    while (!is_delimiter(*lexer->current))
        lexer->current++;
}

// Integers and symbols share a character set ("-", "1+", "+5"), so the whole
// run is read first and classified afterwards.
static bool is_integer(const char *text, size_t length) {
    size_t i = 0;
    if (length > 0 && (text[0] == '+' || text[0] == '-')) i++;
    if (i == length) return false;
    for (; i < length; i++) {
        if (!isdigit((unsigned char)text[i])) return false;
    }
    return true;
}

static Token atom(Lexer *lexer) {
    advance_to_delimiter(lexer);
    size_t length = (size_t)(lexer->current - lexer->start);
    return make_token(lexer, is_integer(lexer->start, length) ? TOKEN_INT : TOKEN_SYMBOL);
}

static Token hash_literal(Lexer *lexer) {
    advance_to_delimiter(lexer);
    size_t length = (size_t)(lexer->current - lexer->start);
    if (length == 2 && lexer->start[1] == 't') return make_token(lexer, TOKEN_TRUE);
    if (length == 2 && lexer->start[1] == 'f') return make_token(lexer, TOKEN_FALSE);
    return error_token(lexer, "invalid # syntax");
}

// The token includes both quotes and the raw escapes; decoding is the parser's job.
static Token string(Lexer *lexer) {
    // Report where the string began: by the time we hit the end of input the
    // line counter points at the last line, far from the missing quote.
    int start_line = lexer->line;
    for (;;) {
        if (is_at_end(lexer)) break;
        char c = advance(lexer);
        if (c == '\n') lexer->line++;
        if (c == '"') return make_token(lexer, TOKEN_STRING);
        if (c == '\\') {
            if (is_at_end(lexer)) break;
            if (advance(lexer) == '\n') lexer->line++;
        }
    }
    Token token = error_token(lexer, "unterminated string");
    token.line = start_line;
    return token;
}

Token lexer_next(Lexer *lexer) {
    skip_whitespace_and_comments(lexer);
    lexer->start = lexer->current;
    if (is_at_end(lexer)) return make_token(lexer, TOKEN_EOF);

    switch (*lexer->current) {
    case '(':
        advance(lexer);
        return make_token(lexer, TOKEN_LPAREN);
    case ')':
        advance(lexer);
        return make_token(lexer, TOKEN_RPAREN);
    case '\'':
        advance(lexer);
        return make_token(lexer, TOKEN_QUOTE);
    case '"':
        advance(lexer);
        return string(lexer);
    case '#':
        return hash_literal(lexer);
    default:
        return atom(lexer);
    }
}
