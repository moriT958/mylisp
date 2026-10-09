#include "reader.h"

#include <stdint.h>
#include <stdio.h>

#include "memory.h"
#include "object.h"

// Recursion depth is bounded so hostile input cannot overflow the C stack.
enum { MAX_NESTING = 1000 };

typedef struct {
    VM *vm;
    Lexer *lexer;
    ReadError *error;
} Reader;

static ReadStatus fail(Reader *reader, int line, const char *message) {
    reader->error->line = line;
    snprintf(reader->error->message, sizeof reader->error->message, "%s", message);
    return READ_ERROR;
}

// Accumulates negatively because INT64_MIN has no positive counterpart.
static bool parse_int(const char *text, size_t length, int64_t *out) {
    size_t i = 0;
    bool negative = false;
    if (text[0] == '+' || text[0] == '-') {
        negative = text[0] == '-';
        i++;
    }
    int64_t value = 0;
    for (; i < length; i++) {
        int64_t scaled;
        if (__builtin_mul_overflow(value, 10, &scaled)) return false;
        if (__builtin_sub_overflow(scaled, text[i] - '0', &value)) return false;
    }
    if (!negative) {
        if (value == INT64_MIN) return false;
        value = -value;
    }
    *out = value;
    return true;
}

// Decodes the escapes inside a string token, which includes its quotes.
static ReadStatus read_string(Reader *reader, Token token, Value *out) {
    size_t capacity = token.length - 1;
    char *buffer = GROW_ARRAY(reader->vm, char, NULL, 0, capacity);

    size_t length = 0;
    for (size_t i = 1; i + 1 < token.length; i++) {
        char c = token.start[i];
        if (c == '\\') {
            switch (token.start[++i]) {
            case '"':
                c = '"';
                break;
            case '\\':
                c = '\\';
                break;
            case 'n':
                c = '\n';
                break;
            case 't':
                c = '\t';
                break;
            default:
                FREE_ARRAY(reader->vm, char, buffer, capacity);
                return fail(reader, token.line, "invalid escape sequence");
            }
        }
        buffer[length++] = c;
    }

    *out = val_string(string_new(reader->vm, buffer, length));
    FREE_ARRAY(reader->vm, char, buffer, capacity);
    return READ_OK;
}

static ReadStatus read_from_token(Reader *reader, Token token, int depth, Value *out);

// depth counts the open lists and quotes around the datum being read.
static ReadStatus read_datum(Reader *reader, int depth, Value *out) {
    return read_from_token(reader, lexer_next(reader->lexer), depth, out);
}

static ReadStatus read_list(Reader *reader, int depth, Value *out) {
    VM *vm = reader->vm;
    Value head = val_nil();
    ObjPair *tail = NULL;

    for (;;) {
        Token token = lexer_next(reader->lexer);
        if (token.type == TOKEN_RPAREN) break;
        if (token.type == TOKEN_EOF) return READ_INCOMPLETE;

        Value element;
        ReadStatus status = read_from_token(reader, token, depth, &element);
        if (status != READ_OK) return status;

        ObjPair *pair = pair_new(vm, element, val_nil());
        if (tail == NULL) {
            head = val_pair(pair);
        } else {
            tail->cdr = val_pair(pair);
        }
        tail = pair;
    }

    *out = head;
    return READ_OK;
}

static ReadStatus read_quote(Reader *reader, int depth, Value *out) {
    VM *vm = reader->vm;
    Value datum;
    ReadStatus status = read_datum(reader, depth, &datum);
    if (status == READ_EOF) return READ_INCOMPLETE;
    if (status != READ_OK) return status;

    Value quote = val_symbol(symbol_intern(vm, "quote", 5));
    *out = val_pair(pair_new(vm, quote, val_pair(pair_new(vm, datum, val_nil()))));
    return READ_OK;
}

static ReadStatus read_from_token(Reader *reader, Token token, int depth, Value *out) {
    switch (token.type) {
    case TOKEN_EOF:
        return depth == 0 ? READ_EOF : READ_INCOMPLETE;
    case TOKEN_ERROR: {
        char message[96];
        snprintf(message, sizeof message, "%.*s", (int)token.length, token.start);
        return fail(reader, token.line, message);
    }
    case TOKEN_RPAREN:
        return fail(reader, token.line, "unexpected ')'");
    case TOKEN_LPAREN:
        if (depth >= MAX_NESTING) return fail(reader, token.line, "nesting too deep");
        return read_list(reader, depth + 1, out);
    case TOKEN_QUOTE:
        if (depth >= MAX_NESTING) return fail(reader, token.line, "nesting too deep");
        return read_quote(reader, depth + 1, out);
    case TOKEN_INT: {
        int64_t value;
        if (!parse_int(token.start, token.length, &value)) {
            return fail(reader, token.line, "integer out of range");
        }
        *out = val_int(value);
        return READ_OK;
    }
    case TOKEN_STRING:
        return read_string(reader, token, out);
    case TOKEN_SYMBOL:
        *out = val_symbol(symbol_intern(reader->vm, token.start, token.length));
        return READ_OK;
    case TOKEN_TRUE:
        *out = val_bool(true);
        return READ_OK;
    case TOKEN_FALSE:
        *out = val_bool(false);
        return READ_OK;
    }
    return READ_ERROR;
}

ReadStatus reader_read(VM *vm, Lexer *lexer, Value *out, ReadError *error) {
    Reader reader = {vm, lexer, error};
    return read_datum(&reader, 0, out);
}
