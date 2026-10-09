// getline and isatty are POSIX and hidden under -std=c11 without this.
#define _POSIX_C_SOURCE 200809L

#include "repl.h"

#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "lexer.h"
#include "reader.h"

typedef enum {
    RUN_OK,
    RUN_INCOMPLETE,
    RUN_ERROR,
} RunStatus;

static void *checked_realloc(void *ptr, size_t size) {
    void *result = realloc(ptr, size);
    if (result == NULL) {
        fprintf(stderr, "out of memory\n");
        exit(1);
    }
    return result;
}

// On RUN_INCOMPLETE, *consumed is where the unfinished datum starts, so the
// REPL can keep just that tail and read the rest on the next line.
// TODO: compile and execute each datum; for now it is only echoed.
static RunStatus run_source(VM *vm, const char *source, size_t *consumed) {
    Lexer lexer;
    lexer_init(&lexer, source);
    *consumed = 0;

    for (;;) {
        Value datum;
        ReadError error;
        switch (reader_read(vm, &lexer, &datum, &error)) {
        case READ_OK:
            value_print(datum);
            putchar('\n');
            *consumed = (size_t)(lexer.current - source);
            break;
        case READ_EOF:
            *consumed = strlen(source);
            return RUN_OK;
        case READ_INCOMPLETE:
            return RUN_INCOMPLETE;
        case READ_ERROR:
            // Flush first so stdout and stderr stay in order when they share a pipe.
            fflush(stdout);
            fprintf(stderr, "error: %s (line %d)\n", error.message, error.line);
            return RUN_ERROR;
        }
    }
}

int repl_run(VM *vm, FILE *in) {
    // No prompt when piped, so the output stays comparable in tests.
    bool interactive = isatty(fileno(in));
    char *pending = NULL;
    size_t pending_length = 0;
    char *line = NULL;
    size_t line_capacity = 0;

    for (;;) {
        if (interactive) {
            printf(pending_length == 0 ? "> " : "... ");
            fflush(stdout);
        }

        ssize_t line_length = getline(&line, &line_capacity, in);
        if (line_length < 0) break;

        pending = checked_realloc(pending, pending_length + (size_t)line_length + 1);
        memcpy(pending + pending_length, line, (size_t)line_length + 1);
        pending_length += (size_t)line_length;

        size_t consumed;
        if (run_source(vm, pending, &consumed) == RUN_INCOMPLETE) {
            pending_length -= consumed;
            memmove(pending, pending + consumed, pending_length + 1);
        } else {
            pending_length = 0;
        }
    }

    if (interactive) putchar('\n');
    free(pending);
    free(line);
    if (pending_length > 0 && !interactive) {
        fprintf(stderr, "error: unexpected end of input\n");
        return 1;
    }
    return 0;
}

static char *read_file(const char *path) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) return NULL;

    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    rewind(file);

    char *buffer = checked_realloc(NULL, (size_t)size + 1);
    size_t read = fread(buffer, 1, (size_t)size, file);
    buffer[read] = '\0';
    fclose(file);
    return buffer;
}

int repl_run_file(VM *vm, const char *path) {
    char *source = read_file(path);
    if (source == NULL) {
        fprintf(stderr, "cannot open '%s'\n", path);
        return 1;
    }

    size_t consumed;
    RunStatus status = run_source(vm, source, &consumed);
    if (status == RUN_INCOMPLETE) {
        fflush(stdout);
        fprintf(stderr, "error: unexpected end of input\n");
    }
    free(source);
    return status == RUN_OK ? 0 : 1;
}
